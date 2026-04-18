//! Biosphere ingest (NASA EONET wildfires) - evidence-only
//!
//! Polls EONET for currently-open wildfire events and writes them into:
//! - observers (one logical observer: eonet_wildfires)
//! - observations (one per event geometry point + timestamp)
//!
//! No simulation: if EONET is unavailable, the cycle fails and writes nothing.

use anyhow::{anyhow, Context, Result};
use chrono::{DateTime, Utc};
use log::{info, warn};
use serde::Deserialize;
use serde_json::{json, Value};
use std::{env, time::Duration};

#[derive(Clone)]
struct Config {
    arango_url: String,
    arango_db: String,
    arango_user: String,
    arango_password: String,
    eonet_url: String,
    poll_interval_secs: u64,
    tile_step_deg: f64,
    tile_time_bucket_secs: i64,
}

impl Config {
    fn from_env() -> Self {
        Self {
            arango_url: env::var("ARANGO_URL").unwrap_or_else(|_| "http://localhost:8529".to_string()),
            arango_db: env::var("ARANGO_DB").unwrap_or_else(|_| "gaiaos".to_string()),
            arango_user: env::var("ARANGO_USER").unwrap_or_else(|_| "root".to_string()),
            arango_password: env::var("ARANGO_PASSWORD").unwrap_or_else(|_| "gaiaos".to_string()),
            eonet_url: env::var("EONET_URL").unwrap_or_else(|_| {
                "https://eonet.gsfc.nasa.gov/api/v3/events?category=wildfires&status=open&limit=2000"
                    .to_string()
            }),
            poll_interval_secs: env::var("POLL_INTERVAL_SECS").ok().and_then(|v| v.parse().ok()).unwrap_or(900),
            tile_step_deg: env::var("TILE_STEP_DEG").ok().and_then(|v| v.parse().ok()).unwrap_or(0.25),
            tile_time_bucket_secs: env::var("TILE_TIME_BUCKET_SECS").ok().and_then(|v| v.parse().ok()).unwrap_or(3600),
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
            .user_agent("GaiaOS-Biosphere-EONET/0.1.0")
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
            .await?;

        if !resp.status().is_success() {
            let status = resp.status();
            let text = resp.text().await.unwrap_or_default();
            return Err(anyhow!("upsert failed {status}: {text}"));
        }
        Ok(())
    }
}

#[derive(Debug, Deserialize)]
struct EonetResponse {
    events: Vec<EonetEvent>,
}

#[derive(Debug, Deserialize)]
struct EonetEvent {
    id: String,
    title: String,
    #[serde(default)]
    description: Option<String>,
    #[serde(default)]
    geometry: Vec<EonetGeometry>,
}

#[derive(Debug, Deserialize)]
struct EonetGeometry {
    date: String,
    #[serde(rename = "type")]
    geom_type: String,
    coordinates: serde_json::Value,
}

fn tile_time_bucket(ts: i64, bucket_secs: i64) -> i64 {
    if bucket_secs <= 0 {
        return ts;
    }
    (ts / bucket_secs) * bucket_secs
}

fn quantize(v: f64, step: f64) -> i32 {
    if step <= 0.0 {
        return (v * 100.0).round() as i32;
    }
    (v / step).round() as i32
}

fn biosphere_tile_key(lat: f64, lon: f64, valid_time: i64, step_deg: f64) -> String {
    format!(
        "BIO_L{}_O{}_T{}",
        quantize(lat, step_deg),
        quantize(lon, step_deg),
        valid_time
    )
}

fn parse_point_coords(v: &serde_json::Value) -> Option<(f64, f64)> {
    // EONET point coords are [lon, lat]
    let arr = v.as_array()?;
    if arr.len() < 2 {
        return None;
    }
    let lon = arr[0].as_f64()?;
    let lat = arr[1].as_f64()?;
    Some((lat, lon))
}

async fn fetch_json(client: &reqwest::Client, url: &str) -> Result<EonetResponse> {
    let resp = client.get(url).send().await.context("eonet request failed")?;
    if !resp.status().is_success() {
        let status = resp.status();
        let text = resp.text().await.unwrap_or_default();
        return Err(anyhow!("eonet http {status}: {text}"));
    }
    Ok(resp.json::<EonetResponse>().await.context("eonet json decode failed")?)
}

async fn ingest_cycle(cfg: &Config, arango: &Arango, http: &reqwest::Client) -> Result<(usize, usize)> {
    let eonet = fetch_json(http, &cfg.eonet_url).await?;

    // Observer (single logical observer for this stream)
    let observer_key = "eonet_wildfires".to_string();
    let observer_doc = json!({
        "_key": observer_key,
        "type": "biosphere_satellite_event",
        "observer_id": "eonet:wildfires",
        "name": "NASA EONET Wildfires (open events)",
        "operational": true,
        "provenance": {
            "source": "nasa_eonet",
            "eonet_url": cfg.eonet_url,
            "ingested_at": Utc::now().to_rfc3339()
        }
    });
    arango.upsert_document("observers", &observer_doc).await?;

    let observers_written = 1usize;
    let mut observations_written = 0usize;

    for ev in eonet.events {
        // EONET can provide multiple geometry points; we ingest all point geometries.
        for g in ev.geometry {
            if g.geom_type != "Point" {
                continue;
            }
            let (lat, lon) = match parse_point_coords(&g.coordinates) {
                Some(p) => p,
                None => continue,
            };
            let dt: DateTime<Utc> = DateTime::parse_from_rfc3339(&g.date)
                .map(|d| d.with_timezone(&Utc))
                .or_else(|_| {
                    // EONET sometimes emits `YYYY-MM-DDTHH:MM:SSZ`
                    DateTime::parse_from_str(&g.date, "%Y-%m-%dT%H:%M:%SZ")
                        .map(|d| d.with_timezone(&Utc))
                })
                .context("failed to parse geometry.date")?;
            let ts = dt.timestamp();
            let valid_time = tile_time_bucket(ts, cfg.tile_time_bucket_secs);
            let validates_tile = biosphere_tile_key(lat, lon, valid_time, cfg.tile_step_deg);

            let key = format!("EONET_WF_{}_{}", ev.id, ts);
            let doc = json!({
                "_key": key,
                "observer_id": "eonet:wildfires",
                "observer_type": "biosphere_wildfire",
                "timestamp": ts,
                "ingest_timestamp": Utc::now().timestamp(),
                "timestamp_rfc3339": dt.to_rfc3339(),
                "location": { "type": "Point", "coordinates": [lon, lat] },
                "altitude_ft": 0,
                "measurement": {
                    "wildfire_event": 1,
                    "title": ev.title,
                    "description": ev.description,
                },
                "quality": {
                    "confidence": 0.9,
                    "source": "nasa_eonet"
                },
                "validates_tile": validates_tile,
                "provenance": {
                    "source": "nasa_eonet",
                    "event_id": ev.id,
                    "ingested_at": Utc::now().to_rfc3339()
                }
            });

            arango.upsert_document("observations", &doc).await?;
            observations_written += 1;
        }
    }

    Ok((observers_written, observations_written))
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

#[tokio::main]
async fn main() -> Result<()> {
    env_logger::init();
    let cfg = Config::from_env();

    let arango = Arango::new(
        cfg.arango_url.clone(),
        cfg.arango_db.clone(),
        cfg.arango_user.clone(),
        cfg.arango_password.clone(),
    )?;
    let http = reqwest::Client::builder()
        .timeout(Duration::from_secs(60))
        .user_agent("GaiaOS-Biosphere-EONET/0.1.0")
        .build()
        .context("failed to build http client")?;

    info!("Starting biosphere_eonet_ingest url={}", cfg.eonet_url);
    let mut interval = tokio::time::interval(Duration::from_secs(cfg.poll_interval_secs));
    loop {
        interval.tick().await;
        match ingest_cycle(&cfg, &arango, &http).await {
            Ok((obsr, obs)) => {
                info!("biosphere_eonet_ingest cycle: observers_upserted={} observations_upserted={}", obsr, obs);
            }
            Err(e) => {
                warn!("biosphere_eonet_ingest cycle failed: {e:#}");
            }
        }
    }
}


