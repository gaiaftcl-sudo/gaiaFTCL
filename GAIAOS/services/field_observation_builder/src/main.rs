//! GaiaOS Field Observation Builder
//!
//! Converts existing real-time substrate signals in `world_patches` into normalized `observations`
//! for field assimilation and QFOT validation.
//!
//! Inputs (real):
//! - `world_patches` where `context == "planetary:atc_live"` (airplanes.live ingest)
//! - `world_patches` where `context == "planetary:weather"` (open-meteo ingest)
//!
//! Output:
//! - `observations` documents with provenance and uncertainty.
//!
//! FoT policy: no fabricated observations; every observation must trace to a world_patches source doc.

use anyhow::{anyhow, Context, Result};
use axum::{routing::get, Router};
use chrono::{DateTime, Utc};
use log::{error, info, warn};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::{env, net::SocketAddr, sync::Arc, time::Duration};
use tokio::{sync::RwLock, time};

#[derive(Clone)]
struct Config {
    arango_url: String,
    arango_db: String,
    arango_user: String,
    arango_password: String,
    world_patches_collection: String,
    observations_collection: String,
    poll_interval_secs: u64,
    max_age_secs: i64,
}

impl Config {
    fn from_env() -> Self {
        Self {
            arango_url: env::var("ARANGO_URL").unwrap_or_else(|_| "http://localhost:8529".to_string()),
            arango_db: env::var("ARANGO_DB").unwrap_or_else(|_| "gaiaos".to_string()),
            arango_user: env::var("ARANGO_USER").unwrap_or_else(|_| "root".to_string()),
            arango_password: env::var("ARANGO_PASSWORD").unwrap_or_else(|_| "gaiaos".to_string()),
            world_patches_collection: env::var("ARANGO_WORLD_PATCHES_COLLECTION")
                .unwrap_or_else(|_| "world_patches".to_string()),
            observations_collection: env::var("ARANGO_OBSERVATIONS_COLLECTION")
                .unwrap_or_else(|_| "observations".to_string()),
            poll_interval_secs: env::var("POLL_INTERVAL_SECS")
                .ok()
                .and_then(|v| v.parse().ok())
                .unwrap_or(15),
            max_age_secs: env::var("MAX_AGE_SECS")
                .ok()
                .and_then(|v| v.parse().ok())
                .unwrap_or(600),
        }
    }
}

#[derive(Clone)]
struct Arango {
    base_url: String,
    db_name: String,
    http: reqwest::Client,
    auth_header: String,
}

impl Arango {
    fn new(base_url: String, db_name: String, user: String, password: String) -> Result<Self> {
        let http = reqwest::Client::builder()
            .timeout(Duration::from_secs(30))
            .user_agent("GaiaOS-Field-Observation-Builder/0.1.0")
            .build()
            .context("failed to build reqwest client")?;

        let auth = base64_encode(&format!("{user}:{password}"));

        Ok(Self {
            base_url: base_url.trim_end_matches('/').to_string(),
            db_name,
            http,
            auth_header: format!("Basic {auth}"),
        })
    }

    async fn aql_query(&self, aql: &str, bind_vars: Value) -> Result<Vec<Value>> {
        let url = format!("{}/_db/{}/_api/cursor", self.base_url, self.db_name);
        let resp = self
            .http
            .post(url)
            .header("Authorization", &self.auth_header)
            .header("Content-Type", "application/json")
            .json(&json!({ "query": aql, "bindVars": bind_vars, "batchSize": 2000 }))
            .send()
            .await
            .context("aql query request failed")?;

        if !resp.status().is_success() {
            let status = resp.status();
            let text = resp.text().await.unwrap_or_default();
            return Err(anyhow!("AQL query failed {status}: {text}"));
        }

        let body: Value = resp.json().await.context("failed to decode AQL response")?;
        Ok(body["result"].as_array().cloned().unwrap_or_default())
    }

    async fn upsert_document(&self, collection: &str, doc: &Value) -> Result<()> {
        let url = format!(
            "{}/_db/{}/_api/document/{}?overwrite=true",
            self.base_url, self.db_name, collection
        );
        let resp = self
            .http
            .post(url)
            .header("Authorization", &self.auth_header)
            .header("Content-Type", "application/json")
            .json(doc)
            .send()
            .await
            .context("arango upsert request failed")?;

        if !resp.status().is_success() {
            let status = resp.status();
            let text = resp.text().await.unwrap_or_default();
            return Err(anyhow!("Arango upsert failed {status}: {text}"));
        }
        Ok(())
    }
}

#[derive(Debug, Deserialize)]
struct WorldPatch {
    #[serde(rename = "_key")]
    key: String,
    context: String,
    #[serde(default)]
    source: Option<String>,
    #[serde(default)]
    center_lat: Option<f64>,
    #[serde(default)]
    center_lon: Option<f64>,
    #[serde(default)]
    center_alt_m: Option<f64>,
    #[serde(default)]
    timestamp: Option<String>,

    // ATC fields (airplanes.live)
    #[serde(default)]
    icao24: Option<String>,
    #[serde(default)]
    callsign: Option<String>,
    #[serde(default)]
    altitude_ft: Option<f64>,
    #[serde(default)]
    velocity_kts: Option<f64>,
    #[serde(default)]
    heading_deg: Option<f64>,
    #[serde(default)]
    vertical_rate_fpm: Option<f64>,

    // Weather fields (open-meteo ingest)
    #[serde(default)]
    temperature_c: Option<f64>,
    #[serde(default)]
    humidity_pct: Option<f64>,
    #[serde(default)]
    wind_speed_ms: Option<f64>,
    #[serde(default)]
    wind_dir_deg: Option<f64>,
    #[serde(default)]
    visibility_m: Option<f64>,
    #[serde(default)]
    cloud_cover_pct: Option<f64>,
    #[serde(default)]
    precipitation_mm: Option<f64>,
    #[serde(default)]
    weather_code: Option<i64>,
}

#[derive(Debug, Serialize)]
struct ObservationDoc<'a> {
    #[serde(rename = "_key")]
    key: &'a str,
    observer_id: &'a str,
    observer_type: &'a str,
    timestamp: i64,
    location: GeoPoint,
    altitude_ft: Option<f64>,
    measurement: Value,
    quality: Value,
    validates_tile: &'a str,
    provenance: Value,
}

#[derive(Debug, Serialize)]
struct GeoPoint {
    #[serde(rename = "type")]
    typ: &'static str,
    coordinates: [f64; 2], // [lon, lat]
}

fn parse_rfc3339(ts: &str) -> Result<DateTime<Utc>> {
    Ok(DateTime::parse_from_rfc3339(ts)
        .context("invalid rfc3339 timestamp")?
        .with_timezone(&Utc))
}

fn quantize_lat_lon(lat: f64, lon: f64, step_deg: f64) -> (f64, f64) {
    let qlat = (lat / step_deg).round() * step_deg;
    let qlon = (lon / step_deg).round() * step_deg;
    (qlat, qlon)
}

fn quantize_altitude_ft(alt_ft: f64, step_ft: f64) -> i32 {
    (alt_ft / step_ft).round() as i32 * step_ft as i32
}

fn time_bucket(ts_unix: i64, bucket_secs: i64) -> i64 {
    (ts_unix / bucket_secs) * bucket_secs
}

fn make_atmosphere_tile_key(lat: f64, lon: f64, alt_ft: i32, valid_time: i64) -> String {
    // Keep keys short and deterministic; avoid punctuation not allowed by Arango keys.
    // Example: ATM_40p25_-70p00_35000_1735248000
    fn f(v: f64) -> String {
        let s = format!("{:.2}", v);
        s.replace('.', "p")
    }
    format!("ATM_{}_{}_{}_{}", f(lat), f(lon), alt_ft, valid_time)
}

async fn health() -> axum::Json<Value> {
    axum::Json(json!({"status":"healthy","service":"field_observation_builder"}))
}

#[derive(Default)]
struct Counters {
    last_cycle_ingested: usize,
    last_cycle_errors: usize,
}

#[tokio::main]
async fn main() -> Result<()> {
    env_logger::init();
    let cfg = Config::from_env();

    info!("Starting field_observation_builder");
    info!("Arango: {} db={} world_patches={} observations={}",
        cfg.arango_url, cfg.arango_db, cfg.world_patches_collection, cfg.observations_collection
    );

    let arango = Arango::new(
        cfg.arango_url.clone(),
        cfg.arango_db.clone(),
        cfg.arango_user.clone(),
        cfg.arango_password.clone(),
    )?;

    let counters = Arc::new(RwLock::new(Counters::default()));

    // Background ingest loop
    let arango_bg = arango.clone();
    let cfg_bg = cfg.clone();
    let counters_bg = counters.clone();
    tokio::spawn(async move {
        let mut interval = time::interval(Duration::from_secs(cfg_bg.poll_interval_secs));
        loop {
            interval.tick().await;
            match run_cycle(&arango_bg, &cfg_bg).await {
                Ok((ingested, errors)) => {
                    let mut c = counters_bg.write().await;
                    c.last_cycle_ingested = ingested;
                    c.last_cycle_errors = errors;
                }
                Err(e) => {
                    error!("cycle failed: {e:#}");
                    let mut c = counters_bg.write().await;
                    c.last_cycle_errors += 1;
                }
            }
        }
    });

    // Health server
    let host = env::var("HOST").unwrap_or_else(|_| "0.0.0.0".to_string());
    let port: u16 = env::var("PORT").ok().and_then(|v| v.parse().ok()).unwrap_or(8761);
    let addr: SocketAddr = format!("{host}:{port}").parse().context("invalid bind addr")?;

    let app = Router::new().route("/health", get(health));
    info!("Listening on http://{addr}");
    axum::serve(tokio::net::TcpListener::bind(addr).await?, app).await?;

    Ok(())
}

async fn run_cycle(arango: &Arango, cfg: &Config) -> Result<(usize, usize)> {
    let now = Utc::now();
    let min_ts = now.timestamp() - cfg.max_age_secs;

    let aql = format!(
        r#"
FOR doc IN {coll}
  FILTER doc.context == "planetary:atc_live" OR doc.context == "planetary:weather"
  FILTER doc.center_lat != null AND doc.center_lon != null
  LET ts = DATE_TIMESTAMP(doc.timestamp)
  FILTER ts >= @min_ts_ms
  SORT ts DESC
  LIMIT 5000
  RETURN doc
"#,
        coll = cfg.world_patches_collection
    );

    let docs = arango
        .aql_query(&aql, json!({ "min_ts_ms": min_ts * 1000 }))
        .await?;

    let mut ingested = 0usize;
    let mut errors = 0usize;

    for v in docs {
        let patch: WorldPatch = match serde_json::from_value(v) {
            Ok(p) => p,
            Err(e) => {
                errors += 1;
                warn!("skip: failed to decode patch: {e}");
                continue;
            }
        };

        match patch_to_observation_docs(&patch) {
            Ok(obs_docs) => {
                for obs in obs_docs {
                    if let Err(e) = arango.upsert_document(&cfg.observations_collection, &obs).await {
                        errors += 1;
                        warn!("observation upsert failed: {e}");
                    } else {
                        ingested += 1;
                    }
                }
            }
            Err(e) => {
                errors += 1;
                warn!("skip patch {}: {e}", patch.key);
            }
        }
    }

    info!(
        "cycle: ingested={} errors={} window_secs={}",
        ingested, errors, cfg.max_age_secs
    );
    Ok((ingested, errors))
}

fn patch_to_observation_docs(p: &WorldPatch) -> Result<Vec<Value>> {
    let lat = p.center_lat.ok_or_else(|| anyhow!("missing center_lat"))?;
    let lon = p.center_lon.ok_or_else(|| anyhow!("missing center_lon"))?;
    let ts_str = p.timestamp.as_deref().ok_or_else(|| anyhow!("missing timestamp"))?;
    let ts = parse_rfc3339(ts_str)?.timestamp();

    let (qlat, qlon) = quantize_lat_lon(lat, lon, 0.25);
    let valid_time = time_bucket(ts, 900);

    let location = GeoPoint {
        typ: "Point",
        coordinates: [lon, lat],
    };

    match p.context.as_str() {
        "planetary:atc_live" => {
            let icao = p.icao24.as_deref().unwrap_or(&p.key);
            let observer_id = icao;
            let alt_ft = p.altitude_ft.unwrap_or(0.0);
            let alt_bucket = quantize_altitude_ft(alt_ft, 1000.0);
            let tile_key = make_atmosphere_tile_key(qlat, qlon, alt_bucket, valid_time);
            let obs_key = format!("obs_atc_{}", p.key);

            let measurement = json!({
                "callsign": p.callsign,
                "altitude_ft": p.altitude_ft,
                "velocity_kts": p.velocity_kts,
                "heading_deg": p.heading_deg,
                "vertical_rate_fpm": p.vertical_rate_fpm,
            });

            let quality = json!({
                "confidence": 0.95,
                "position_accuracy_m": 50.0
            });

            let doc = ObservationDoc {
                key: obs_key.as_str(),
                observer_id,
                observer_type: "adsb",
                timestamp: ts,
                location,
                altitude_ft: Some(alt_ft),
                measurement,
                quality,
                validates_tile: tile_key.as_str(),
                provenance: json!({
                    "source": p.source.as_deref().unwrap_or("world_patches"),
                    "world_patch_key": p.key,
                    "ingested_at": Utc::now().to_rfc3339(),
                }),
            };

            Ok(vec![serde_json::to_value(doc)?])
        }
        "planetary:weather" => {
            // Weather is surface-layer observation by default (altitude optional from center_alt_m)
            let alt_ft = p.center_alt_m.unwrap_or(0.0) * 3.28084;
            let alt_bucket = quantize_altitude_ft(alt_ft, 1000.0);
            let tile_key = make_atmosphere_tile_key(qlat, qlon, alt_bucket, valid_time);

            let observer_id = format!("weather_{:.2}_{:.2}", qlat, qlon).replace('.', "p");
            let obs_key = format!("obs_weather_{}", p.key);

            let measurement = json!({
                "temperature_c": p.temperature_c,
                "humidity_pct": p.humidity_pct,
                "wind_speed_ms": p.wind_speed_ms,
                "wind_dir_deg": p.wind_dir_deg,
                "visibility_m": p.visibility_m,
                "cloud_cover_pct": p.cloud_cover_pct,
                "precipitation_mm": p.precipitation_mm,
                "weather_code": p.weather_code,
            });

            let quality = json!({
                "confidence": 0.90
            });

            let doc = ObservationDoc {
                key: obs_key.as_str(),
                observer_id: observer_id.as_str(),
                observer_type: "weather",
                timestamp: ts,
                location,
                altitude_ft: Some(alt_ft),
                measurement,
                quality,
                validates_tile: tile_key.as_str(),
                provenance: json!({
                    "source": p.source.as_deref().unwrap_or("world_patches"),
                    "world_patch_key": p.key,
                    "ingested_at": Utc::now().to_rfc3339(),
                }),
            };

            Ok(vec![serde_json::to_value(doc)?])
        }
        other => Err(anyhow!("unsupported context: {other}")),
    }
}

fn base64_encode(input: &str) -> String {
    const ALPHABET: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let bytes = input.as_bytes();
    let mut result = String::new();

    for chunk in bytes.chunks(3) {
        let mut n: u32 = 0;
        for (i, &byte) in chunk.iter().enumerate() {
            n |= (byte as u32) << (16 - i * 8);
        }

        let padding = 3 - chunk.len();
        for i in 0..(4 - padding) {
            let idx = ((n >> (18 - i * 6)) & 0x3F) as usize;
            result.push(ALPHABET[idx] as char);
        }

        for _ in 0..padding {
            result.push('=');
        }
    }

    result
}


