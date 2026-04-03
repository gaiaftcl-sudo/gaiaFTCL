//! Atmosphere global ingest from Open-Meteo GFS (real model output; no synthesis).
//!
//! Writes directly to `atmosphere_tiles` as non-prediction model tiles.

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
            tiles_collection: env::var("ATMOSPHERE_TILES_COLLECTION").unwrap_or_else(|_| "atmosphere_tiles".to_string()),
            poll_interval_secs: env::var("POLL_INTERVAL_SECS").ok().and_then(|v| v.parse().ok()).unwrap_or(60),
            step_deg: env::var("GLOBAL_STEP_DEG").ok().and_then(|v| v.parse().ok()).unwrap_or(5.0),
            batch_size: env::var("BATCH_SIZE").ok().and_then(|v| v.parse().ok()).unwrap_or(500),
            max_batches_per_cycle: env::var("MAX_BATCHES_PER_CYCLE").ok().and_then(|v| v.parse().ok()).unwrap_or(4),
            batch_delay_ms: env::var("BATCH_DELAY_MS").ok().and_then(|v| v.parse().ok()).unwrap_or(1500),
            api_base: env::var("OPEN_METEO_GFS_URL").unwrap_or_else(|_| "https://api.open-meteo.com/v1/gfs".to_string()),
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
            .user_agent("GaiaOS-Atmosphere-Global-GFS/0.1.0")
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
struct GfsCurrent {
    time: String,
    temperature_2m: Option<f64>,
    pressure_msl: Option<f64>,
    wind_speed_10m: Option<f64>,
    wind_direction_10m: Option<f64>,
}

#[derive(Debug, Deserialize)]
struct GfsResp {
    latitude: f64,
    longitude: f64,
    #[serde(default)]
    current: Option<GfsCurrent>,
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
    format!("ATM_GFS_L{}_O{}_A0_T{}", quantize(lat, step_deg), quantize(lon, step_deg), valid_time)
}

fn wind_uv_from_speed_dir(speed_ms: f64, dir_deg: f64) -> (f64, f64) {
    let theta = (dir_deg + 180.0).to_radians();
    (speed_ms * theta.sin(), speed_ms * theta.cos())
}

fn generate_grid(step: f64) -> Vec<(f64, f64)> {
    let mut pts = Vec::new();
    let mut lat = -90.0;
    while lat <= 90.0 {
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

async fn fetch_batch(http: &reqwest::Client, cfg: &Config, batch: &[(f64, f64)]) -> Result<Vec<GfsResp>> {
    let lats = batch.iter().map(|(lat, _)| lat.to_string()).collect::<Vec<_>>().join(",");
    let lons = batch.iter().map(|(_, lon)| lon.to_string()).collect::<Vec<_>>().join(",");

    // Open-Meteo supports multiple locations by comma-separated latitude/longitude lists.
    let url = format!(
        "{base}?latitude={lats}&longitude={lons}&current=temperature_2m,pressure_msl,wind_speed_10m,wind_direction_10m&timezone=UTC",
        base = cfg.api_base
    );
    let resp = http.get(url).send().await.context("gfs request failed")?;
    if !resp.status().is_success() {
        let status = resp.status();
        let text = resp.text().await.unwrap_or_default();
        return Err(anyhow!("gfs http {status}: {text}"));
    }

    // Multi-location response is an array; single-location is an object.
    let v: serde_json::Value = resp.json().await.context("gfs json decode failed")?;
    if v.is_array() {
        let arr = v.as_array().cloned().unwrap_or_default();
        let mut out = Vec::with_capacity(arr.len());
        for item in arr {
            if let Ok(x) = serde_json::from_value::<GfsResp>(item) {
                out.push(x);
            }
        }
        return Ok(out);
    }
    Ok(vec![serde_json::from_value::<GfsResp>(v)?])
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

                    let temp_k = cur.temperature_2m.unwrap_or(0.0) + 273.15;
                    let pressure_pa = cur.pressure_msl.unwrap_or(0.0) * 100.0;
                    let wind_speed = cur.wind_speed_10m.unwrap_or(0.0);
                    let wind_dir = cur.wind_direction_10m.unwrap_or(0.0);
                    let (u, v) = wind_uv_from_speed_dir(wind_speed, wind_dir);

                    let key = tile_key(it.latitude, it.longitude, valid_time, cfg.step_deg);
                    let doc = json!({
                        "_key": key,
                        "location": { "type": "Point", "coordinates": [it.longitude, it.latitude] },
                        "altitude_ft": 0,
                        "forecast_time": forecast_time,
                        "valid_time": valid_time,
                        "resolution_level": 3,
                        "resolution_deg": cfg.step_deg,
                        "state": {
                            "wind_u": u,
                            "wind_v": v,
                            "temperature_k": temp_k,
                            "pressure_pa": pressure_pa
                        },
                        "uncertainty": { "confidence": 0.6 },
                        "provenance": {
                            "source": "gfs_open_meteo",
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
                    warn!("gfs rate-limited (429): backing off 60s");
                    tokio::time::sleep(Duration::from_secs(60)).await;
                } else {
                    warn!("gfs batch failed: {e:#}");
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
        "Starting atmosphere_global_gfs_ingest step_deg={} batch_size={} max_batches_per_cycle={} batch_delay_ms={}",
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
    // Open-Meteo commonly returns "YYYY-MM-DDTHH:MM" in UTC when timezone=UTC
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


