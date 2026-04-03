//! QFOT Trainer (scheduled)
//!
//! This service implements the **scheduled execution loop** described in the plan:
//! - evidence threshold trigger (new observations) OR time trigger (max hours)
//! - per-lane gating: atmosphere, ocean, molecular, astro
//! - model registry updates in `qfot_gnn_models`
//! - activation only after validator gates pass (via akg-gnn forecast endpoints)
//!
//! Note: this service does not synthesize data; it only orchestrates existing evidence-driven
//! ingest/assimilation/forecast/validation pipelines and records auditable model registry state.

use anyhow::{anyhow, Context, Result};
use chrono::Utc;
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
    akg_url: String,
    check_interval_secs: u64,
    observation_threshold: usize,
    max_hours_between_training: i64,
    // Forecast request defaults (bounded)
    bbox_lat_min: f64,
    bbox_lat_max: f64,
    bbox_lon_min: f64,
    bbox_lon_max: f64,
    ocean_depth_min_m: f64,
    ocean_depth_max_m: f64,
    molecular_protein_id: String,
}

impl Config {
    fn from_env() -> Self {
        Self {
            arango_url: env::var("ARANGO_URL").unwrap_or_else(|_| "http://localhost:8529".to_string()),
            arango_db: env::var("ARANGO_DB").unwrap_or_else(|_| "gaiaos".to_string()),
            arango_user: env::var("ARANGO_USER").unwrap_or_else(|_| "root".to_string()),
            arango_password: env::var("ARANGO_PASSWORD").unwrap_or_else(|_| "gaiaos".to_string()),
            akg_url: env::var("AKG_GNN_URL").unwrap_or_else(|_| "http://akg-gnn:8700".to_string()),
            check_interval_secs: env::var("CHECK_INTERVAL_SECS").ok().and_then(|v| v.parse().ok()).unwrap_or(3600),
            observation_threshold: env::var("OBSERVATION_THRESHOLD").ok().and_then(|v| v.parse().ok()).unwrap_or(1000),
            max_hours_between_training: env::var("MAX_HOURS_BETWEEN_TRAINING").ok().and_then(|v| v.parse().ok()).unwrap_or(24),
            bbox_lat_min: env::var("TRAIN_BBOX_LAT_MIN").ok().and_then(|v| v.parse().ok()).unwrap_or(-90.0),
            bbox_lat_max: env::var("TRAIN_BBOX_LAT_MAX").ok().and_then(|v| v.parse().ok()).unwrap_or(90.0),
            bbox_lon_min: env::var("TRAIN_BBOX_LON_MIN").ok().and_then(|v| v.parse().ok()).unwrap_or(-180.0),
            bbox_lon_max: env::var("TRAIN_BBOX_LON_MAX").ok().and_then(|v| v.parse().ok()).unwrap_or(180.0),
            ocean_depth_min_m: env::var("TRAIN_OCEAN_DEPTH_MIN_M").ok().and_then(|v| v.parse().ok()).unwrap_or(0.0),
            ocean_depth_max_m: env::var("TRAIN_OCEAN_DEPTH_MAX_M").ok().and_then(|v| v.parse().ok()).unwrap_or(0.0),
            molecular_protein_id: env::var("TRAIN_MOLECULAR_PROTEIN_ID").unwrap_or_else(|_| "AUTO".to_string()),
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
            .user_agent("GaiaOS-QFOT-Trainer/0.1.0")
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

    async fn aql_query(&self, query: &str, bind_vars: Value) -> Result<Vec<Value>> {
        let url = format!("{}/_db/{}/_api/cursor", self.base_url, self.db_name);
        let resp = self
            .http
            .post(url)
            .header("Authorization", &self.auth_header)
            .header("Content-Type", "application/json")
            .json(&json!({ "query": query, "bindVars": bind_vars, "batchSize": 1000 }))
            .send()
            .await?;
        if !resp.status().is_success() {
            let status = resp.status();
            let text = resp.text().await.unwrap_or_default();
            return Err(anyhow!("AQL query failed {status}: {text}"));
        }
        let body: Value = resp.json().await?;
        Ok(body["result"].as_array().cloned().unwrap_or_default())
    }

    async fn upsert_model_registry(&self, substrate: &str, active: bool, validation_key: Option<String>) -> Result<String> {
        let now = Utc::now().timestamp();
        let key = format!("{}_{}", substrate, now);
        let doc = json!({
            "_key": key,
            "substrate": substrate,
            "model_version": env!("CARGO_PKG_VERSION"),
            "trained_at": now,
            "active": active,
            "metrics": {
                "training_mode": "scheduled_gate",
                "validation_key": validation_key
            },
            "provenance": {
                "source": "qfot_trainer",
                "version": env!("CARGO_PKG_VERSION"),
                "ingested_at": Utc::now().to_rfc3339()
            }
        });

        let url = format!("{}/_db/{}/_api/document/qfot_gnn_models?overwrite=true", self.base_url, self.db_name);
        let resp = self
            .http
            .post(url)
            .header("Authorization", &self.auth_header)
            .header("Content-Type", "application/json")
            .json(&doc)
            .send()
            .await?;
        if !resp.status().is_success() {
            let status = resp.status();
            let text = resp.text().await.unwrap_or_default();
            return Err(anyhow!("model registry upsert failed {status}: {text}"));
        }

        // Enforce single-active-per-substrate
        if active {
            let aql = r#"
FOR m IN qfot_gnn_models
  FILTER m.substrate == @substrate
  FILTER m._key != @key
  UPDATE m WITH { active: false } IN qfot_gnn_models
  OPTIONS { keepNull: false }
RETURN 1
"#;
            let _ = self
                .aql_query(aql, json!({ "substrate": substrate, "key": key }))
                .await;
        }

        Ok(key)
    }

    async fn count_recent_observations(&self, window_secs: i64) -> Result<usize> {
        let now = Utc::now().timestamp();
        let min_ts = now - window_secs;
        let aql = r#"
FOR obs IN observations
  FILTER obs.ingest_timestamp >= @min_ts
  FILTER obs.processed != true
  COLLECT WITH COUNT INTO c
  RETURN c
"#;
        let res = self.aql_query(aql, json!({ "min_ts": min_ts })).await?;
        Ok(res.first().and_then(|v| v.as_u64()).unwrap_or(0) as usize)
    }

    async fn last_training_time(&self) -> Result<i64> {
        let aql = r#"
FOR m IN qfot_gnn_models
  SORT m.trained_at DESC
  LIMIT 1
  RETURN m.trained_at
"#;
        let res = self.aql_query(aql, json!({})).await?;
        Ok(res.first().and_then(|v| v.as_i64()).unwrap_or(0))
    }

    async fn latest_i64_field(&self, collection: &str, field: &str) -> Result<Option<i64>> {
        let aql = format!(
            r#"
FOR d IN {collection}
  FILTER HAS(d, @field)
  SORT d[@field] DESC
  LIMIT 1
  RETURN d[@field]
"#
        );
        let res = self.aql_query(&aql, json!({ "field": field })).await?;
        Ok(res.first().and_then(|v| v.as_i64()))
    }

    async fn latest_string_field(&self, collection: &str, field: &str) -> Result<Option<String>> {
        let aql = format!(
            r#"
FOR d IN {collection}
  FILTER HAS(d, @field)
  SORT d.ingest_timestamp DESC
  LIMIT 1
  RETURN d[@field]
"#
        );
        let res = self.aql_query(&aql, json!({ "field": field })).await?;
        Ok(res.first().and_then(|v| v.as_str()).map(|s| s.to_string()))
    }
}

#[derive(Debug, Deserialize)]
struct ForecastResponse {
    validation_passed: bool,
    validation_key: Option<String>,
    #[serde(default)]
    validation_failures: Vec<String>,
}

async fn post_json<T: for<'de> Deserialize<'de>>(client: &reqwest::Client, url: &str, body: &Value) -> Result<T> {
    let resp = client.post(url).json(body).send().await?;
    if !resp.status().is_success() {
        let status = resp.status();
        let text = resp.text().await.unwrap_or_default();
        return Err(anyhow!("http {status}: {text}"));
    }
    Ok(resp.json::<T>().await?)
}

async fn run_lane(cfg: &Config, arango: &Arango, http: &reqwest::Client, lane: &str) -> Result<()> {
    let now = Utc::now().timestamp();
    let (t_min, t_max) = match lane {
        "atmosphere" => {
            let center = arango
                .latest_i64_field("atmosphere_tiles", "valid_time")
                .await?
                .unwrap_or(now);
            (center - 3600, center + 3600)
        }
        "ocean" => {
            let center = arango
                .latest_i64_field("ocean_tiles", "valid_time")
                .await?
                .unwrap_or(now);
            (center - 3600, center + 3600)
        }
        "biosphere" => {
            let center = arango
                .latest_i64_field("biosphere_tiles", "valid_time")
                .await?
                .unwrap_or(now);
            (center - 3600, center + 3600)
        }
        _ => (now - 3600, now + 3600),
    };

    let (endpoint, payload) = match lane {
        "atmosphere" => (
            format!("{}/qfot/forecast", cfg.akg_url.trim_end_matches('/')),
            json!({
                "bbox": { "lat_min": cfg.bbox_lat_min, "lat_max": cfg.bbox_lat_max, "lon_min": cfg.bbox_lon_min, "lon_max": cfg.bbox_lon_max },
                "valid_time_min": t_min,
                "valid_time_max": t_max,
                "forecast_steps": 2,
                "step_secs": 900,
                "max_tiles": 20000
            }),
        ),
        "ocean" => (
            format!("{}/qfot/ocean/forecast", cfg.akg_url.trim_end_matches('/')),
            json!({
                "bbox": { "lat_min": cfg.bbox_lat_min, "lat_max": cfg.bbox_lat_max, "lon_min": cfg.bbox_lon_min, "lon_max": cfg.bbox_lon_max },
                "valid_time_min": t_min,
                "valid_time_max": t_max,
                "forecast_steps": 2,
                "step_secs": 900,
                "depth_min_m": cfg.ocean_depth_min_m,
                "depth_max_m": cfg.ocean_depth_max_m,
                "max_tiles": 20000
            }),
        ),
        "biosphere" => (
            format!("{}/qfot/biosphere/forecast", cfg.akg_url.trim_end_matches('/')),
            json!({
                "bbox": { "lat_min": cfg.bbox_lat_min, "lat_max": cfg.bbox_lat_max, "lon_min": cfg.bbox_lon_min, "lon_max": cfg.bbox_lon_max },
                "valid_time_min": t_min,
                "valid_time_max": t_max,
                "forecast_steps": 1,
                "step_secs": 3600,
                "max_tiles": 20000
            }),
        ),
        "molecular" => (
            format!("{}/qfot/molecular/forecast", cfg.akg_url.trim_end_matches('/')),
            {
                let protein_id = if cfg.molecular_protein_id.eq_ignore_ascii_case("AUTO")
                    || cfg.molecular_protein_id.eq_ignore_ascii_case("unknown")
                    || cfg.molecular_protein_id.eq_ignore_ascii_case("unknown_target")
                {
                    arango
                        .latest_string_field("molecular_tiles", "protein_id")
                        .await?
                        .unwrap_or_else(|| "unknown_target".to_string())
                } else {
                    cfg.molecular_protein_id.clone()
                };
                json!({
                "protein_id": protein_id,
                "sim_time_ps_min": 0.0,
                "sim_time_ps_max": 0.0,
                "x_min": -50.0, "x_max": 50.0,
                "y_min": -50.0, "y_max": 50.0,
                "z_min": -50.0, "z_max": 50.0,
                "forecast_steps": 1,
                "step_secs": 1,
                "max_tiles": 20000
                })
            },
        ),
        "astro" => (
            format!("{}/qfot/astro/forecast", cfg.akg_url.trim_end_matches('/')),
            {
                let center = arango
                    .latest_i64_field("gravitational_tiles", "epoch_seconds")
                    .await?
                    .unwrap_or(now);
                json!({
                "epoch_min": center - 3600,
                "epoch_max": center + 3600,
                "x_min": -50000.0, "x_max": 50000.0,
                "y_min": -50000.0, "y_max": 50000.0,
                "z_min": -50000.0, "z_max": 50000.0,
                "forecast_steps": 1,
                "step_secs": 60,
                "max_tiles": 20000
                })
            },
        ),
        _ => return Err(anyhow!("unknown lane")),
    };

    let resp: ForecastResponse = post_json(http, &endpoint, &payload).await?;
    if !resp.validation_passed {
        return Err(anyhow!("lane {lane} validation failed: {:?}", resp.validation_failures));
    }

    let _model_key = arango
        .upsert_model_registry(lane, true, resp.validation_key.clone())
        .await?;
    Ok(())
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
        .timeout(Duration::from_secs(90))
        .user_agent("GaiaOS-QFOT-Trainer/0.1.0")
        .build()
        .context("failed to build http client")?;

    info!("Starting qfot_trainer: check_interval={}s threshold={} max_hours={}",
        cfg.check_interval_secs, cfg.observation_threshold, cfg.max_hours_between_training);

    let mut interval = tokio::time::interval(Duration::from_secs(cfg.check_interval_secs));
    loop {
        interval.tick().await;

        let recent_obs = match arango.count_recent_observations(86400).await {
            Ok(c) => c,
            Err(e) => {
                warn!("trainer: observation count failed: {e:#}");
                continue;
            }
        };

        let last_train = arango.last_training_time().await.unwrap_or(0);
        let hours_since = if last_train <= 0 {
            i64::MAX
        } else {
            (Utc::now().timestamp() - last_train) / 3600
        };

        let should_train = recent_obs >= cfg.observation_threshold || hours_since >= cfg.max_hours_between_training;
        if !should_train {
            info!("trainer: skip (recent_obs={} hours_since_last={})", recent_obs, hours_since);
            continue;
        }

        info!("trainer: trigger (recent_obs={} hours_since_last={})", recent_obs, hours_since);

        for lane in ["atmosphere", "ocean", "biosphere", "molecular", "astro"] {
            match run_lane(&cfg, &arango, &http, lane).await {
                Ok(()) => info!("trainer: lane {} activated", lane),
                Err(e) => warn!("trainer: lane {} failed: {e:#}", lane),
            }
        }
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


