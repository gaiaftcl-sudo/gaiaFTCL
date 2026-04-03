//! PIREP (Pilot Report) ingest from NOAA Aviation Weather Center.
//!
//! Polls https://aviationweather.gov/api/data/pirep for real turbulence reports
//! and persists them into world_patches with context planetary:atc_pirep.
//!
//! FoT: no mocking/simulation; real pilot reports only.

use anyhow::{anyhow, Context, Result};
use chrono::Utc;
use log::{info, warn};
use serde::{Deserialize, Serialize};
use serde_json::json;
use std::{env, time::Duration};

#[derive(Clone)]
struct Config {
    arango_url: String,
    arango_db: String,
    arango_user: String,
    arango_password: String,
    world_patches_collection: String,
    poll_interval_secs: u64,
    aviationweather_url: String,
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
            poll_interval_secs: env::var("POLL_INTERVAL_SECS")
                .ok()
                .and_then(|v| v.parse().ok())
                .unwrap_or(300),
            aviationweather_url: env::var("AVIATIONWEATHER_URL")
                .unwrap_or_else(|_| "https://aviationweather.gov/api/data/pirep".to_string()),
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
            .user_agent("GaiaOS-PIREP-Ingest/0.1.0")
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

    async fn insert_document(&self, collection: &str, doc: &serde_json::Value) -> Result<()> {
        let url = format!(
            "{}/_db/{}/_api/document/{}",
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
            .context("arango insert request failed")?;
        if !resp.status().is_success() {
            let status = resp.status();
            let text = resp.text().await.unwrap_or_default();
            return Err(anyhow!("Arango insert failed {status}: {text}"));
        }
        Ok(())
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

#[derive(Debug, Deserialize, Serialize)]
struct PIREP {
    #[serde(rename = "reportId")]
    report_id: String,
    #[serde(rename = "obsTime")]
    observation_time: i64,
    #[serde(rename = "lat")]
    latitude: f64,
    #[serde(rename = "lon")]
    longitude: f64,
    #[serde(rename = "altitudeFt")]
    altitude_ft: u32,
    #[serde(rename = "aircraftType")]
    aircraft_type: Option<String>,
    #[serde(rename = "turbulence")]
    turbulence_condition: Option<TurbulenceCondition>,
    #[serde(rename = "rawOb")]
    raw_text: String,
}

#[derive(Debug, Deserialize, Serialize)]
struct TurbulenceCondition {
    intensity: String, // "LGT", "MOD", "SEV", "EXTRM"
    #[serde(rename = "type")]
    type_: Option<String>, // "CAT", "CHOP", etc.
}

async fn ingest_pireps(cfg: &Config, arango: &Arango, http: &reqwest::Client) -> Result<usize> {
    let url = format!("{}?format=json&age=1", cfg.aviationweather_url);
    let resp = http
        .get(&url)
        .send()
        .await
        .context("aviationweather request failed")?;

    if !resp.status().is_success() {
        let status = resp.status();
        let text = resp.text().await.unwrap_or_default();
        return Err(anyhow!("aviationweather http {status}: {text}"));
    }

    let pireps: Vec<PIREP> = resp.json().await.context("failed to parse PIREP JSON")?;

    let mut count = 0;
    for pirep in pireps {
        if pirep.turbulence_condition.is_none() {
            continue;
        }

        let turb = pirep.turbulence_condition.as_ref().unwrap();
        let patch = json!({
            "_key": format!("pirep_{}", pirep.report_id),
            "context": "planetary:atc_pirep",
            "timestamp": pirep.observation_time,
            "state": {
                "lat": pirep.latitude,
                "lon": pirep.longitude,
                "altitude_ft": pirep.altitude_ft,
                "turbulence_intensity": turb.intensity,
                "turbulence_type": turb.type_,
                "aircraft_type": pirep.aircraft_type,
                "raw_text": pirep.raw_text,
            },
            "provenance": {
                "source": "noaa_aviationweather_pirep",
                "ingest_timestamp": Utc::now().timestamp(),
            },
        });

        match arango.insert_document(&cfg.world_patches_collection, &patch).await {
            Ok(_) => count += 1,
            Err(e) => {
                warn!("Failed to insert PIREP {}: {}", pirep.report_id, e);
            }
        }
    }

    Ok(count)
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
        .timeout(Duration::from_secs(30))
        .user_agent("GaiaOS-PIREP-Ingest/0.1.0")
        .build()?;

    info!(
        "Starting pirep_ingest poll_interval={}s",
        cfg.poll_interval_secs
    );

    let mut interval = tokio::time::interval(Duration::from_secs(cfg.poll_interval_secs));
    loop {
        interval.tick().await;
        match ingest_pireps(&cfg, &arango, &http).await {
            Ok(count) => info!("Ingested {} PIREPs", count),
            Err(e) => warn!("PIREP ingest error: {}", e),
        }
    }
}

