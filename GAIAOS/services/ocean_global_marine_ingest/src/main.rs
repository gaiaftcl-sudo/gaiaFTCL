//! Ocean global ingest from Open-Meteo Marine (real model output; no synthesis).
//!
//! Writes directly to `ocean_tiles` as non-prediction model tiles.

use anyhow::{anyhow, Context, Result};
use chrono::{DateTime, Utc};
use chrono::NaiveDateTime;
use log::{info, warn};
use serde::Deserialize;
use serde_json::json;
use std::{env, time::Duration};

#[derive(Clone)]
struct Config {
    arango_url: String,
    arango_db: String,
    arango_user: String,
    arango_password: String,
    tiles_collection: String,
    poll_interval_secs: u64,
    step_deg: f64,
    batch_size: usize,
    max_batches_per_cycle: usize,
    batch_delay_ms: u64,
    api_base: String,
}

impl Config {
    fn from_env() -> Self {
        Self {
            arango_url: env::var("ARANGO_URL").unwrap_or_else(|_| "http://localhost:8529".to_string()),
            arango_db: env::var("ARANGO_DB").unwrap_or_else(|_| "gaiaos".to_string()),
            arango_user: env::var("ARANGO_USER").unwrap_or_else(|_| "root".to_string()),
            arango_password: env::var("ARANGO_PASSWORD").unwrap_or_else(|_| "gaiaos".to_string()),
            tiles_collection: env::var("OCEAN_TILES_COLLECTION").unwrap_or_else(|_| "ocean_tiles".to_string()),
            poll_interval_secs: env::var("POLL_INTERVAL_SECS").ok().and_then(|v| v.parse().ok()).unwrap_or(60),
            step_deg: env::var("GLOBAL_STEP_DEG").ok().and_then(|v| v.parse().ok()).unwrap_or(5.0),
            batch_size: env::var("BATCH_SIZE").ok().and_then(|v| v.parse().ok()).unwrap_or(500),
            max_batches_per_cycle: env::var("MAX_BATCHES_PER_CYCLE").ok().and_then(|v| v.parse().ok()).unwrap_or(4),
            batch_delay_ms: env::var("BATCH_DELAY_MS").ok().and_then(|v| v.parse().ok()).unwrap_or(1500),
            api_base: env::var("OPEN_METEO_MARINE_URL").unwrap_or_else(|_| "https://marine-api.open-meteo.com/v1/marine".to_string()),
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
            .timeout(Duration::from_secs(45))
            .user_agent("GaiaOS-Ocean-Global-Marine/0.1.0")
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

    async fn upsert_document(&self, collection: &str, doc: &serde_json::Value) -> Result<()> {
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
struct MarineCurrent {
    time: String,
    wave_height: Option<f64>,
    wave_direction: Option<f64>,
    wave_period: Option<f64>,
}

#[derive(Debug, Deserialize)]
struct MarineResp {
    latitude: f64,
    longitude: f64,
    #[serde(default)]
    current: Option<MarineCurrent>,
}

fn time_bucket(ts_unix: i64, bucket_secs: i64) -> i64 {
    if bucket_secs <= 0 {
        return ts_unix;
    }
    (ts_unix / bucket_secs) * bucket_secs
}

fn quantize(v: f64, step: f64) -> i32 {
    if step <= 0.0 {
        return (v * 100.0).round() as i32;
    }
    (v / step).round() as i32
}

fn tile_key(lat: f64, lon: f64, valid_time: i64, step_deg: f64) -> String {
    format!("OCN_MAR_L{}_O{}_Z0_T{}", quantize(lat, step_deg), quantize(lon, step_deg), valid_time)
}

fn generate_grid(step: f64) -> Vec<(f64, f64)> {
    let mut pts = Vec::new();
    let mut lat = -80.0; // avoid polar singularities for marine grids
    while lat <= 80.0 {
        let mut lon = -180.0;
        while lon <= 180.0 {
            pts.push((lat, lon));
            lon += step;
        }
        lat += step;
    }
    pts
}

fn chunk<T: Clone>(v: &[T], n: usize) -> Vec<Vec<T>> {
    v.chunks(n).map(|c| c.to_vec()).collect()
}

async fn fetch_batch(http: &reqwest::Client, cfg: &Config, batch: &[(f64, f64)]) -> Result<Vec<MarineResp>> {
    let lats = batch.iter().map(|(lat, _)| lat.to_string()).collect::<Vec<_>>().join(",");
    let lons = batch.iter().map(|(_, lon)| lon.to_string()).collect::<Vec<_>>().join(",");
    let url = format!(
        "{base}?latitude={lats}&longitude={lons}&current=wave_height,wave_direction,wave_period&timezone=UTC",
        base = cfg.api_base
    );
    let resp = http.get(url).send().await.context("marine request failed")?;
    if !resp.status().is_success() {
        let status = resp.status();
        let text = resp.text().await.unwrap_or_default();
        return Err(anyhow!("marine http {status}: {text}"));
    }

    let v: serde_json::Value = resp.json().await.context("marine json decode failed")?;
    if v.is_array() {
        let arr = v.as_array().cloned().unwrap_or_default();
        let mut out = Vec::with_capacity(arr.len());
        for item in arr {
            if let Ok(x) = serde_json::from_value::<MarineResp>(item) {
                out.push(x);
            }
        }
        return Ok(out);
    }
    Ok(vec![serde_json::from_value::<MarineResp>(v)?])
}

async fn run_cycle(
    cfg: &Config,
    arango: &Arango,
    http: &reqwest::Client,
    batches: &[Vec<(f64, f64)>],
    cursor: &mut usize,
) -> Result<(usize, usize)> {
    let mut tiles_written = 0usize;
    let mut requests = 0usize;
    let forecast_time = Utc::now().timestamp();

    if batches.is_empty() {
        return Ok((0, 0));
    }

    let mut batches_this_cycle = 0usize;
    while batches_this_cycle < cfg.max_batches_per_cycle {
        let idx = *cursor % batches.len();
        let b = &batches[idx];
        requests += 1;
        match fetch_batch(http, cfg, &b).await {
            Ok(items) => {
                for it in items {
                    let Some(cur) = it.current else { continue };
                    let valid_time = match parse_open_meteo_time_utc(&cur.time) {
                        Ok(ts) => time_bucket(ts, 3600),
                        Err(e) => {
                            warn!("skip: bad current.time='{}': {e:#}", cur.time);
                            continue;
                        }
                    };

                    let key = tile_key(it.latitude, it.longitude, valid_time, cfg.step_deg);
                    let doc = json!({
                        "_key": key,
                        "location": { "type": "Point", "coordinates": [it.longitude, it.latitude] },
                        "depth_m": 0,
                        "forecast_time": forecast_time,
                        "valid_time": valid_time,
                        "resolution_level": 3,
                        "resolution_deg": cfg.step_deg,
                        "state": {
                            "current_u": 0.0,
                            "current_v": 0.0,
                            "temperature_k": 0.0,
                            "salinity_psu": 0.0,
                            "wave_height_m": cur.wave_height.unwrap_or(0.0),
                            "wave_period_s": cur.wave_period.unwrap_or(0.0),
                            "wave_direction_deg": cur.wave_direction.unwrap_or(0.0)
                        },
                        "uncertainty": { "confidence": 0.6 },
                        "provenance": {
                            "source": "marine_open_meteo",
                            "ingest_timestamp": Utc::now().timestamp(),
                            "is_prediction": false,
                            "api": cfg.api_base
                        },
                        "observations": []
                    });
                    if let Err(e) = arango.upsert_document(&cfg.tiles_collection, &doc).await {
                        warn!("tile upsert failed: {e:#}");
                    } else {
                        tiles_written += 1;
                    }
                }
            }
            Err(e) => {
                let msg = format!("{e:#}");
                if msg.contains("429") {
                    warn!("marine rate-limited (429): backing off 60s");
                    tokio::time::sleep(Duration::from_secs(60)).await;
                } else {
                    warn!("marine batch failed: {e:#}");
                }
            }
        }
        *cursor = (*cursor + 1) % batches.len();
        batches_this_cycle += 1;
        tokio::time::sleep(Duration::from_millis(cfg.batch_delay_ms)).await;
    }
    Ok((requests, tiles_written))
}

#[tokio::main]
async fn main() -> Result<()> {
    env_logger::init();
    let cfg = Config::from_env();
    let arango = Arango::new(cfg.arango_url.clone(), cfg.arango_db.clone(), cfg.arango_user.clone(), cfg.arango_password.clone())?;
    let http = reqwest::Client::builder().timeout(Duration::from_secs(60)).build()?;

    let grid = generate_grid(cfg.step_deg);
    let batches = chunk(&grid, cfg.batch_size);
    let mut cursor = 0usize;

    info!(
        "Starting ocean_global_marine_ingest step_deg={} batch_size={} max_batches_per_cycle={} batch_delay_ms={}",
        cfg.step_deg, cfg.batch_size, cfg.max_batches_per_cycle, cfg.batch_delay_ms
    );
    let mut interval = tokio::time::interval(Duration::from_secs(cfg.poll_interval_secs));
    loop {
        interval.tick().await;
        match run_cycle(&cfg, &arango, &http, &batches, &mut cursor).await {
            Ok((reqs, tiles)) => info!("cycle: requests={} tiles_upserted={}", reqs, tiles),
            Err(e) => warn!("cycle failed: {e:#}"),
        }
    }
}

fn parse_open_meteo_time_utc(s: &str) -> Result<i64> {
    let st = s.trim();
    if st.is_empty() {
        return Err(anyhow!("empty time string"));
    }
    if let Ok(dt) = DateTime::parse_from_rfc3339(st) {
        return Ok(dt.with_timezone(&Utc).timestamp());
    }
    if let Ok(ndt) = NaiveDateTime::parse_from_str(st, "%Y-%m-%dT%H:%M") {
        return Ok(DateTime::<Utc>::from_naive_utc_and_offset(ndt, Utc).timestamp());
    }
    if let Ok(ndt) = NaiveDateTime::parse_from_str(st, "%Y-%m-%dT%H:%M:%S") {
        return Ok(DateTime::<Utc>::from_naive_utc_and_offset(ndt, Utc).timestamp());
    }
    Err(anyhow!("unrecognized time format"))
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


