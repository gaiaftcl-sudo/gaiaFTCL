//! GaiaOS Field Assimilation Service
//!
//! Reads normalized `observations` and produces derived field tiles:
//! - `atmosphere_tiles` (MVP): surface + flight-level buckets where observations exist
//! - `ocean_tiles`: only created when real ocean observations exist (no fabrication)
//! - `field_relations`: adjacency/coupling edges when both endpoints exist
//!
//! FoT policy: do not synthesize tiles without evidence; every tile must cite contributing
//! observations and provenance.

use anyhow::{anyhow, Context, Result};
use axum::{routing::get, Router};
use axum::response::IntoResponse;
use chrono::Utc;
use log::{error, info, warn};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::{collections::HashMap, env, net::SocketAddr, time::Duration};
use tokio::time;

mod metrics;

#[derive(Clone)]
struct Config {
    arango_url: String,
    arango_db: String,
    arango_user: String,
    arango_password: String,
    observations_collection: String,
    atmosphere_tiles_collection: String,
    ocean_tiles_collection: String,
    biosphere_tiles_collection: String,
    field_relations_collection: String,
    poll_interval_secs: u64,
    max_age_secs: i64,
    tile_latlon_step_deg: f64,
    tile_alt_step_ft: f64,
    tile_time_bucket_secs: i64,
}

impl Config {
    fn from_env() -> Self {
        Self {
            arango_url: env::var("ARANGO_URL").unwrap_or_else(|_| "http://localhost:8529".to_string()),
            arango_db: env::var("ARANGO_DB").unwrap_or_else(|_| "gaiaos".to_string()),
            arango_user: env::var("ARANGO_USER").unwrap_or_else(|_| "root".to_string()),
            arango_password: env::var("ARANGO_PASSWORD").unwrap_or_else(|_| "gaiaos".to_string()),
            observations_collection: env::var("ARANGO_OBSERVATIONS_COLLECTION")
                .unwrap_or_else(|_| "observations".to_string()),
            atmosphere_tiles_collection: env::var("ARANGO_ATMOSPHERE_TILES_COLLECTION")
                .unwrap_or_else(|_| "atmosphere_tiles".to_string()),
            ocean_tiles_collection: env::var("ARANGO_OCEAN_TILES_COLLECTION")
                .unwrap_or_else(|_| "ocean_tiles".to_string()),
            biosphere_tiles_collection: env::var("ARANGO_BIOSPHERE_TILES_COLLECTION")
                .unwrap_or_else(|_| "biosphere_tiles".to_string()),
            field_relations_collection: env::var("ARANGO_FIELD_RELATIONS_COLLECTION")
                .unwrap_or_else(|_| "field_relations".to_string()),
            poll_interval_secs: env::var("POLL_INTERVAL_SECS")
                .ok()
                .and_then(|v| v.parse().ok())
                .unwrap_or(30),
            max_age_secs: env::var("MAX_AGE_SECS").ok().and_then(|v| v.parse().ok()).unwrap_or(900),
            tile_latlon_step_deg: env::var("TILE_STEP_DEG").ok().and_then(|v| v.parse().ok()).unwrap_or(0.25),
            tile_alt_step_ft: env::var("TILE_ALT_STEP_FT").ok().and_then(|v| v.parse().ok()).unwrap_or(1000.0),
            tile_time_bucket_secs: env::var("TILE_TIME_BUCKET_SECS").ok().and_then(|v| v.parse().ok()).unwrap_or(900),
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
            .user_agent("GaiaOS-Field-Assimilation/0.1.0")
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
struct Observation {
    #[serde(rename = "_key")]
    key: String,
    #[serde(rename = "observer_id")]
    _observer_id: String,
    observer_type: String,
    timestamp: i64,
    location: GeoPoint,
    #[serde(default)]
    altitude_ft: Option<f64>,
    measurement: Value,
    quality: Value,
    validates_tile: String,
    #[serde(rename = "provenance")]
    _provenance: Value,
}

#[derive(Debug, Deserialize, Serialize, Clone)]
struct GeoPoint {
    #[serde(rename = "type")]
    typ: String,
    coordinates: [f64; 2], // [lon, lat]
}

#[derive(Default)]
struct TileAccum {
    lat: f64,
    lon: f64,
    alt_ft: i32,
    valid_time: i64,
    forecast_time: i64,
    // Aggregates
    wind_u_ms_sum: f64,
    wind_v_ms_sum: f64,
    wind_count: usize,
    temp_k_sum: f64,
    temp_count: usize,
    visibility_m_sum: f64,
    visibility_count: usize,
    trajectory_density: usize,
    observations: Vec<String>,
    quality_scores: Vec<f64>,
}

#[derive(Default)]
struct OceanTileAccum {
    lat: f64,
    lon: f64,
    depth_m: i32,
    valid_time: i64,
    forecast_time: i64,
    wave_height_m_sum: f64,
    wave_height_count: usize,
    wave_period_s_sum: f64,
    wave_period_count: usize,
    wave_dir_deg_sum: f64,
    wave_dir_count: usize,
    water_temp_c_sum: f64,
    water_temp_count: usize,
    current_u_ms_sum: f64,
    current_u_count: usize,
    current_v_ms_sum: f64,
    current_v_count: usize,
    observations: Vec<String>,
    quality_scores: Vec<f64>,
}

#[derive(Debug, Clone)]
struct BiosphereTileAccum {
    lat: f64,
    lon: f64,
    valid_time: i64,
    wildfire_event_count: u64,
    modis_catalog_count: u64,
    observations: Vec<String>,
}

fn wind_uv_from_speed_dir(speed_ms: f64, dir_deg: f64) -> (f64, f64) {
    // Meteorological convention: wind direction is where it's coming FROM.
    // Convert to vector components (u eastward, v northward) of wind flowing TO.
    let theta = (dir_deg + 180.0).to_radians();
    (speed_ms * theta.sin(), speed_ms * theta.cos())
}

async fn health() -> axum::Json<Value> {
    axum::Json(json!({"status":"healthy","service":"field_assimilation"}))
}

async fn metrics_handler() -> axum::response::Response {
    let body = metrics::gather_text();
    (
        [(axum::http::header::CONTENT_TYPE, "text/plain; version=0.0.4; charset=utf-8")],
        body,
    )
        .into_response()
}

#[tokio::main]
async fn main() -> Result<()> {
    env_logger::init();
    metrics::register_metrics();
    let cfg = Config::from_env();
    let arango = Arango::new(
        cfg.arango_url.clone(),
        cfg.arango_db.clone(),
        cfg.arango_user.clone(),
        cfg.arango_password.clone(),
    )?;

    info!("Starting field_assimilation");
    info!(
        "Arango: {} db={} obs={} atm={} ocn={} rel={}",
        cfg.arango_url,
        cfg.arango_db,
        cfg.observations_collection,
        cfg.atmosphere_tiles_collection,
        cfg.ocean_tiles_collection,
        cfg.field_relations_collection
    );

    // Background loop
    let arango_bg = arango.clone();
    let cfg_bg = cfg.clone();
    tokio::spawn(async move {
        let mut interval = time::interval(Duration::from_secs(cfg_bg.poll_interval_secs));
        loop {
            interval.tick().await;
            if let Err(e) = run_cycle(&arango_bg, &cfg_bg).await {
                error!("assimilation cycle failed: {e:#}");
            }
        }
    });

    // Health server
    let host = env::var("HOST").unwrap_or_else(|_| "0.0.0.0".to_string());
    let port: u16 = env::var("PORT").ok().and_then(|v| v.parse().ok()).unwrap_or(8762);
    let addr: SocketAddr = format!("{host}:{port}").parse().context("invalid bind addr")?;
    let app = Router::new()
        .route("/health", get(health))
        .route("/metrics", get(metrics_handler));
    info!("Listening on http://{addr}");
    axum::serve(tokio::net::TcpListener::bind(addr).await?, app).await?;
    Ok(())
}

async fn run_cycle(arango: &Arango, cfg: &Config) -> Result<()> {
    metrics::ASSIMILATION_CYCLES_TOTAL.inc();
    let now = Utc::now().timestamp();
    let min_ingest_ts = now - cfg.max_age_secs;

    let aql = format!(
        r#"
FOR obs IN {coll}
  FILTER obs.ingest_timestamp >= @min_ingest_ts
  SORT obs.timestamp ASC
  LIMIT 20000
  RETURN obs
"#,
        coll = cfg.observations_collection
    );

    let docs = arango
        .aql_query(&aql, json!({ "min_ingest_ts": min_ingest_ts }))
        .await?;
    if docs.is_empty() {
        info!("cycle: no observations in window");
        return Ok(());
    }

    let mut acc: HashMap<String, TileAccum> = HashMap::new();
    let mut ocean_acc: HashMap<String, OceanTileAccum> = HashMap::new();
    let mut ocean_obs_seen = 0usize;
    let mut biosphere_acc: HashMap<String, BiosphereTileAccum> = HashMap::new();
    let mut biosphere_obs_seen = 0usize;

    for v in docs {
        let obs: Observation = match serde_json::from_value(v) {
            Ok(o) => o,
            Err(e) => {
                warn!("skip: bad observation doc: {e}");
                continue;
            }
        };

        match obs.observer_type.as_str() {
            "weather" => {
                let tile_key = obs.validates_tile.clone();
                let entry = acc.entry(tile_key.clone()).or_insert_with(|| {
                    let lat = obs.location.coordinates[1];
                    let lon = obs.location.coordinates[0];
                    let alt_ft = obs.altitude_ft.unwrap_or(0.0);
                    TileAccum {
                        lat,
                        lon,
                        alt_ft: quantize_altitude_ft(alt_ft, cfg.tile_alt_step_ft),
                        valid_time: time_bucket(obs.timestamp, cfg.tile_time_bucket_secs),
                        // forecast_time equals ingest time for nowcasts derived from observations
                        forecast_time: time_bucket(obs.timestamp, cfg.tile_time_bucket_secs),
                        ..Default::default()
                    }
                });

                entry.observations.push(obs.key.clone());
                if let Some(conf) = obs.quality.get("confidence").and_then(|v| v.as_f64()) {
                    entry.quality_scores.push(conf);
                }

                // Temperature: prefer temperature_c if present
                if let Some(temp_c) = obs.measurement.get("temperature_c").and_then(|v| v.as_f64()) {
                    entry.temp_k_sum += temp_c + 273.15;
                    entry.temp_count += 1;
                }
                if let Some(vis_m) = obs.measurement.get("visibility_m").and_then(|v| v.as_f64()) {
                    entry.visibility_m_sum += vis_m;
                    entry.visibility_count += 1;
                }
                // Wind from speed+dir
                if let (Some(ws), Some(wd)) = (
                    obs.measurement.get("wind_speed_ms").and_then(|v| v.as_f64()),
                    obs.measurement.get("wind_dir_deg").and_then(|v| v.as_f64()),
                ) {
                    let (u, v) = wind_uv_from_speed_dir(ws, wd);
                    entry.wind_u_ms_sum += u;
                    entry.wind_v_ms_sum += v;
                    entry.wind_count += 1;
                }
            }
            "adsb" => {
                let tile_key = obs.validates_tile.clone();
                let entry = acc.entry(tile_key.clone()).or_insert_with(|| {
                    let lat = obs.location.coordinates[1];
                    let lon = obs.location.coordinates[0];
                    let alt_ft = obs.altitude_ft.unwrap_or(0.0);
                    TileAccum {
                        lat,
                        lon,
                        alt_ft: quantize_altitude_ft(alt_ft, cfg.tile_alt_step_ft),
                        valid_time: time_bucket(obs.timestamp, cfg.tile_time_bucket_secs),
                        forecast_time: time_bucket(obs.timestamp, cfg.tile_time_bucket_secs),
                        ..Default::default()
                    }
                });
                entry.observations.push(obs.key.clone());
                if let Some(conf) = obs.quality.get("confidence").and_then(|v| v.as_f64()) {
                    entry.quality_scores.push(conf);
                }
                entry.trajectory_density += 1;
            }
            other => {
                if other.starts_with("ocean_") {
                    ocean_obs_seen += 1;
                    let tile_key = obs.validates_tile.clone();
                    let entry = ocean_acc.entry(tile_key.clone()).or_insert_with(|| {
                        let lat = obs.location.coordinates[1];
                        let lon = obs.location.coordinates[0];
                        let depth_m = obs
                            .measurement
                            .get("depth_m")
                            .and_then(|v| v.as_i64())
                            .unwrap_or(0) as i32;
                        OceanTileAccum {
                            lat,
                            lon,
                            depth_m,
                            valid_time: time_bucket(obs.timestamp, cfg.tile_time_bucket_secs),
                            forecast_time: time_bucket(obs.timestamp, cfg.tile_time_bucket_secs),
                            ..Default::default()
                        }
                    });

                    entry.observations.push(obs.key.clone());
                    if let Some(conf) = obs.quality.get("confidence").and_then(|v| v.as_f64()) {
                        entry.quality_scores.push(conf);
                    }

                    if let Some(wvht) = obs.measurement.get("wave_height_m").and_then(|v| v.as_f64()) {
                        entry.wave_height_m_sum += wvht;
                        entry.wave_height_count += 1;
                    }
                    if let Some(wp) = obs.measurement.get("wave_period_s").and_then(|v| v.as_f64()) {
                        entry.wave_period_s_sum += wp;
                        entry.wave_period_count += 1;
                    }
                    if let Some(wd) = obs.measurement.get("wave_direction_deg").and_then(|v| v.as_f64()) {
                        entry.wave_dir_deg_sum += wd;
                        entry.wave_dir_count += 1;
                    }
                    if let Some(wtmp) = obs.measurement.get("water_temperature_c").and_then(|v| v.as_f64()) {
                        entry.water_temp_c_sum += wtmp;
                        entry.water_temp_count += 1;
                    }
                    if let Some(cu) = obs.measurement.get("current_u").and_then(|v| v.as_f64()) {
                        entry.current_u_ms_sum += cu;
                        entry.current_u_count += 1;
                    }
                    if let Some(cv) = obs.measurement.get("current_v").and_then(|v| v.as_f64()) {
                        entry.current_v_ms_sum += cv;
                        entry.current_v_count += 1;
                    }
                }
                if other.starts_with("biosphere_") {
                    biosphere_obs_seen += 1;
                    let tile_key = obs.validates_tile.clone();
                    let entry = biosphere_acc.entry(tile_key.clone()).or_insert_with(|| {
                        let lat = obs.location.coordinates[1];
                        let lon = obs.location.coordinates[0];
                        BiosphereTileAccum {
                            lat,
                            lon,
                            valid_time: time_bucket(obs.timestamp, cfg.tile_time_bucket_secs),
                            wildfire_event_count: 0,
                            modis_catalog_count: 0,
                            observations: Vec::new(),
                        }
                    });

                    // Evidence-only: count biosphere contributions by type (no fabrication).
                    entry.observations.push(obs.key.clone());
                    if other == "biosphere_modis_ndvi_catalog" {
                        entry.modis_catalog_count += 1;
                    } else {
                        entry.wildfire_event_count += 1;
                    }
                }
            }
        }
    }

    let mut written = 0usize;
    for (tile_key, t) in acc {
        // MVP: only write atmosphere tiles for now (derived from weather/adsb evidence)
        let avg_temp_k = if t.temp_count > 0 {
            Some(t.temp_k_sum / t.temp_count as f64)
        } else {
            None
        };
        let (wind_u, wind_v) = if t.wind_count > 0 {
            (
                Some(t.wind_u_ms_sum / t.wind_count as f64),
                Some(t.wind_v_ms_sum / t.wind_count as f64),
            )
        } else {
            (None, None)
        };
        let avg_vis = if t.visibility_count > 0 {
            Some(t.visibility_m_sum / t.visibility_count as f64)
        } else {
            None
        };

        // Require at least one physical measurement (weather or wind or visibility) OR at least 1 trajectory density
        // to avoid fabricating empty tiles.
        let has_evidence = avg_temp_k.is_some() || wind_u.is_some() || avg_vis.is_some() || t.trajectory_density > 0;
        if !has_evidence {
            continue;
        }

        let quality_score = if t.quality_scores.is_empty() {
            0.0
        } else {
            t.quality_scores.iter().sum::<f64>() / t.quality_scores.len() as f64
        };

        let doc = json!({
            "_key": tile_key,
            "location": { "type": "Point", "coordinates": [t.lon, t.lat] },
            "altitude_ft": t.alt_ft,
            "forecast_time": t.forecast_time,
            "valid_time": t.valid_time,
            "resolution_level": 2,
            "resolution_deg": cfg.tile_latlon_step_deg,
            "state": {
                "wind_u": wind_u.unwrap_or(0.0),
                "wind_v": wind_v.unwrap_or(0.0),
                "wind_w": 0.0,
                "temperature_k": avg_temp_k.unwrap_or(0.0),
                "pressure_pa": 0.0,
                "potential_temp_k": avg_temp_k.unwrap_or(0.0),
                "kinetic_energy": match (wind_u, wind_v) {
                    (Some(u), Some(v)) => 0.5 * (u*u + v*v),
                    _ => 0.0
                },
                "vorticity": 0.0,
                "divergence": 0.0,
                "helicity": 0.0,
                "humidity_percent": 0.0,
                "cloud_cover_percent": 0.0,
                "precipitation_rate": 0.0,
                "visibility_m": avg_vis.unwrap_or(0.0),
                "turbulence_index": 0.0,
                "trajectory_density": t.trajectory_density
            },
            "uncertainty": {
                "wind_u_std": 0.0,
                "wind_v_std": 0.0,
                "temperature_std": 0.0,
                "pressure_std": 0.0,
                "ensemble_members": 0,
                "confidence": quality_score
            },
            "coupling": {
                "ocean_surface_below": null,
                "layer_above": null,
                "wind_stress_magnitude": 0.0,
                "heat_flux_w_m2": 0.0
            },
            "provenance": {
                "source": "field_assimilation",
                "model_version": env!("CARGO_PKG_VERSION"),
                "ingest_timestamp": Utc::now().timestamp(),
                "quality_score": quality_score,
                "validator": "qfot_field_pending"
            },
            "trajectories": [],
            "observations": t.observations
        });

        arango.upsert_document(&cfg.atmosphere_tiles_collection, &doc).await?;
        written += 1;
    }

    let mut ocean_written = 0usize;
    for (tile_key, t) in ocean_acc {
        let avg_wvht = if t.wave_height_count > 0 {
            Some(t.wave_height_m_sum / t.wave_height_count as f64)
        } else {
            None
        };
        let avg_wperiod = if t.wave_period_count > 0 {
            Some(t.wave_period_s_sum / t.wave_period_count as f64)
        } else {
            None
        };
        let avg_wdir = if t.wave_dir_count > 0 {
            Some(t.wave_dir_deg_sum / t.wave_dir_count as f64)
        } else {
            None
        };
        let avg_wtmp_c = if t.water_temp_count > 0 {
            Some(t.water_temp_c_sum / t.water_temp_count as f64)
        } else {
            None
        };
        let avg_current_u = if t.current_u_count > 0 {
            Some(t.current_u_ms_sum / t.current_u_count as f64)
        } else {
            None
        };
        let avg_current_v = if t.current_v_count > 0 {
            Some(t.current_v_ms_sum / t.current_v_count as f64)
        } else {
            None
        };

        // Fail-closed: only write if we have at least one real ocean measurement.
        let has_ocean_evidence = avg_wvht.is_some() || avg_wtmp_c.is_some() || avg_current_u.is_some() || avg_current_v.is_some();
        if !has_ocean_evidence {
            continue;
        }

        let quality_score = if t.quality_scores.is_empty() {
            0.0
        } else {
            t.quality_scores.iter().sum::<f64>() / t.quality_scores.len() as f64
        };

        let doc = json!({
            "_key": tile_key,
            "location": { "type": "Point", "coordinates": [t.lon, t.lat] },
            "depth_m": t.depth_m,
            "forecast_time": t.forecast_time,
            "valid_time": t.valid_time,
            "resolution_level": 2,
            "resolution_deg": cfg.tile_latlon_step_deg,
            "state": {
                "current_u": avg_current_u.unwrap_or(0.0),
                "current_v": avg_current_v.unwrap_or(0.0),
                "temperature_k": avg_wtmp_c.map(|c| c + 273.15).unwrap_or(0.0),
                "salinity_psu": 0.0,
                "wave_height_m": avg_wvht.unwrap_or(0.0),
                "wave_period_s": avg_wperiod.unwrap_or(0.0),
                "wave_direction_deg": avg_wdir.unwrap_or(0.0)
            },
            "uncertainty": {
                "current_std": 0.0,
                "temperature_std": 0.0,
                "wave_height_std": 0.0,
                "confidence": quality_score
            },
            "provenance": {
                "source": "field_assimilation",
                "model_version": env!("CARGO_PKG_VERSION"),
                "ingest_timestamp": Utc::now().timestamp(),
                "quality_score": quality_score,
                "validator": "qfot_ocean_pending"
            },
            "observations": t.observations
        });

        arango.upsert_document(&cfg.ocean_tiles_collection, &doc).await?;
        ocean_written += 1;
    }

    let mut biosphere_written = 0usize;
    for (tile_key, t) in biosphere_acc {
        let doc = json!({
            "_key": tile_key,
            "location": { "type": "Point", "coordinates": [t.lon, t.lat] },
            "forecast_time": t.valid_time,
            "valid_time": t.valid_time,
            "resolution_level": 2,
            "resolution_deg": cfg.tile_latlon_step_deg,
            "state": {
                "wildfire_event_count": t.wildfire_event_count,
                "modis_ndvi_catalog_count": t.modis_catalog_count,
                "ndvi_catalog_present": t.modis_catalog_count > 0
            },
            "uncertainty": {},
            "provenance": {
                "source": "field_assimilation",
                "model_version": env!("CARGO_PKG_VERSION"),
                "ingest_timestamp": Utc::now().timestamp(),
                "is_prediction": false,
                "quality_score": 1.0,
                "validator": "qfot_field_pending"
            },
            "observations": t.observations,
        });
        arango.upsert_document(&cfg.biosphere_tiles_collection, &doc).await?;
        biosphere_written += 1;
    }

    metrics::ATMOSPHERE_TILES_WRITTEN_TOTAL.inc_by(written as u64);
    metrics::OCEAN_TILES_WRITTEN_TOTAL.inc_by(ocean_written as u64);
    metrics::OCEAN_OBSERVATIONS_SEEN_TOTAL.inc_by(ocean_obs_seen as u64);
    metrics::BIOSPHERE_TILES_WRITTEN_TOTAL.inc_by(biosphere_written as u64);
    metrics::BIOSPHERE_OBSERVATIONS_SEEN_TOTAL.inc_by(biosphere_obs_seen as u64);

    info!(
        "cycle: wrote_atmosphere_tiles={} wrote_ocean_tiles={} ocean_observations_seen={} wrote_biosphere_tiles={} biosphere_observations_seen={}",
        written, ocean_written, ocean_obs_seen, biosphere_written, biosphere_obs_seen
    );

    Ok(())
}

fn time_bucket(ts_unix: i64, bucket_secs: i64) -> i64 {
    (ts_unix / bucket_secs) * bucket_secs
}

fn quantize_altitude_ft(alt_ft: f64, step_ft: f64) -> i32 {
    (alt_ft / step_ft).round() as i32 * step_ft as i32
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


