//! METAR Observation Ingest (offline, evidence-only)
//!
//! Reads AviationWeather METAR JSON artifacts (already captured locally) and writes:
//! - `observations` documents (observer_type = "weather")
//! - `observers` station documents (type="metar_station")
//!
//! FoT: no synthesis. Every value comes directly from METAR artifacts or deterministic unit conversion.

use anyhow::{anyhow, Context, Result};
use chrono::{TimeZone, Utc};
use log::{info, warn};
use serde::{Deserialize, Serialize};
use serde_json::json;
use std::{env, fs, path::Path, time::Duration};

#[derive(Clone)]
struct Config {
    arango_url: String,
    arango_db: String,
    arango_user: String,
    arango_password: String,
    artifacts_dir: String,
    max_files: usize,
    tile_step_deg: f64,
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
            artifacts_dir: env::var("METAR_ARTIFACT_DIR")
                .unwrap_or_else(|_| "apps/gaiaos_browser_cell/usd/artifacts/aviationweather_metar".to_string()),
            max_files: env::var("MAX_FILES").ok().and_then(|v| v.parse().ok()).unwrap_or(5000),
            tile_step_deg: env::var("TILE_STEP_DEG").ok().and_then(|v| v.parse().ok()).unwrap_or(0.25),
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
            .user_agent("GaiaOS-METAR-Observation-Ingest/0.1.0")
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
struct MetarRecord {
    #[serde(rename = "icaoId")]
    icao_id: String,
    #[serde(rename = "receiptTime")]
    receipt_time: String,
    #[serde(rename = "obsTime")]
    obs_time: i64, // unix seconds
    #[serde(rename = "reportTime")]
    report_time: String,
    temp: Option<f64>, // C
    dewp: Option<f64>, // C
    wdir: Option<f64>, // deg
    wspd: Option<f64>, // knots
    visib: Option<serde_json::Value>, // string or number
    altim: Option<f64>, // hPa
    slp: Option<f64>,   // hPa
    #[serde(rename = "qcField")]
    qc_field: Option<f64>,
    #[serde(rename = "metarType")]
    metar_type: Option<String>,
    #[serde(rename = "rawOb")]
    raw_ob: Option<String>,
    lat: f64,
    lon: f64,
    elev: Option<f64>,
    name: Option<String>,
    #[serde(rename = "fltCat")]
    flt_cat: Option<String>,
}

#[derive(Debug, Serialize)]
struct GeoPoint {
    #[serde(rename = "type")]
    typ: &'static str,
    coordinates: [f64; 2], // [lon, lat]
}

fn time_bucket(ts_unix: i64, bucket_secs: i64) -> i64 {
    (ts_unix / bucket_secs) * bucket_secs
}

fn quantize_deg(v: f64, step: f64) -> f64 {
    (v / step).round() * step
}

fn quantize_altitude_ft(alt_ft: f64, step_ft: f64) -> i32 {
    (alt_ft / step_ft).round() as i32 * step_ft as i32
}

fn tile_key(lat: f64, lon: f64, alt_ft: i32, valid_time: i64, step_deg: f64) -> String {
    let latq = quantize_deg(lat, step_deg);
    let lonq = quantize_deg(lon, step_deg);
    let lat_q100 = (latq * 100.0).round() as i32;
    let lon_q100 = (lonq * 100.0).round() as i32;
    format!("ATM_L{lat_q100}_O{lon_q100}_A{alt_ft}_T{valid_time}")
}

fn knots_to_ms(knots: f64) -> f64 {
    knots * 0.514_444
}

fn visib_to_m(vis: &serde_json::Value) -> Option<f64> {
    // AviationWeather API sometimes returns:
    // - "10+" (miles)
    // - "10SM" (miles)
    // - "3/4SM"
    // - numeric (miles)
    match vis {
        serde_json::Value::Number(n) => n.as_f64().map(|miles| miles * 1609.344),
        serde_json::Value::String(s) => {
            let s = s.trim();
            if s.is_empty() {
                return None;
            }
            if s == "10+" {
                return Some(10.0 * 1609.344);
            }
            let s = s.strip_suffix("SM").unwrap_or(s);
            // fraction like "3/4"
            if let Some((a, b)) = s.split_once('/') {
                let num: f64 = a.parse().ok()?;
                let den: f64 = b.parse().ok()?;
                if den == 0.0 {
                    return None;
                }
                return Some((num / den) * 1609.344);
            }
            // plain number
            let miles: f64 = s.parse().ok()?;
            Some(miles * 1609.344)
        }
        _ => None,
    }
}

fn artifact_ts_ms_from_filename(name: &str) -> Option<i64> {
    // Expected: metar_{ICAO}_{EPOCH_MS}.json
    let stem = name.strip_suffix(".json")?;
    let (_prefix, ts) = stem.rsplit_once('_')?;
    ts.parse::<i64>().ok()
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

    let dir = Path::new(&cfg.artifacts_dir);
    let mut entries: Vec<_> = fs::read_dir(dir)
        .with_context(|| format!("failed to read METAR dir: {}", dir.display()))?
        .filter_map(|e| e.ok())
        .filter(|e| {
            e.path()
                .file_name()
                .and_then(|n| n.to_str())
                .map(|n| n.starts_with("metar_") && n.ends_with(".json"))
                .unwrap_or(false)
        })
        .collect();

    // Process most-recent first by artifact capture timestamp in filename (epoch ms).
    entries.sort_by(|a, b| {
        let a_name = a
            .path()
            .file_name()
            .and_then(|n| n.to_str())
            .unwrap_or("")
            .to_string();
        let b_name = b
            .path()
            .file_name()
            .and_then(|n| n.to_str())
            .unwrap_or("")
            .to_string();
        let a_ts = artifact_ts_ms_from_filename(&a_name).unwrap_or(0);
        let b_ts = artifact_ts_ms_from_filename(&b_name).unwrap_or(0);
        b_ts.cmp(&a_ts)
    });
    entries.truncate(cfg.max_files);

    let mut obs_written = 0usize;
    let mut observers_written = 0usize;

    for entry in entries {
        let path = entry.path();
        let bytes = match fs::read(&path) {
            Ok(b) => b,
            Err(e) => {
                warn!("skip: read failed {}: {e}", path.display());
                continue;
            }
        };

        let records: Vec<MetarRecord> = match serde_json::from_slice(&bytes) {
            Ok(v) => v,
            Err(e) => {
                warn!("skip: parse failed {}: {e}", path.display());
                continue;
            }
        };

        for r in records {
            let obs_ts = r.obs_time;
            let valid_time = time_bucket(obs_ts, cfg.tile_time_bucket_secs);
            let alt_ft = quantize_altitude_ft(r.elev.unwrap_or(0.0) * 3.28084, cfg.tile_alt_step_ft);
            let validates_tile = tile_key(r.lat, r.lon, alt_ft, valid_time, cfg.tile_step_deg);
            let observer_id = format!("metar:{}", r.icao_id);

            // Observer station doc
            let obs_station_doc = json!({
                "_key": format!("metar_{}", r.icao_id),
                "type": "metar_station",
                "station_id": r.icao_id,
                "location": { "type": "Point", "coordinates": [r.lon, r.lat] },
                "elevation_m": r.elev,
                "name": r.name,
                "operational": true,
                "provenance": {
                    "source": "aviationweather_metar_artifacts",
                    "artifact_path": path.display().to_string(),
                    "ingested_at": Utc::now().to_rfc3339()
                }
            });
            arango.upsert_document("observers", &obs_station_doc).await?;
            observers_written += 1;

            let visibility_m = r
                .visib
                .as_ref()
                .and_then(visib_to_m);

            let wind_speed_ms = r.wspd.map(knots_to_ms);
            let wind_dir_deg = r.wdir;

            let quality_confidence = r
                .qc_field
                .map(|q| (q / 20.0).min(1.0).max(0.0));

            // Observation doc (schema expected by field_assimilation)
            let key = format!("METAR_{}_{}", r.icao_id, obs_ts);
            let doc = json!({
                "_key": key,
                "observer_id": observer_id,
                "observer_type": "weather",
                "timestamp": obs_ts,
                "ingest_timestamp": Utc::now().timestamp(),
                "timestamp_rfc3339": Utc.timestamp_opt(obs_ts, 0).single().map(|t| t.to_rfc3339()),
                "location": GeoPoint { typ: "Point", coordinates: [r.lon, r.lat] },
                "altitude_ft": alt_ft,
                "measurement": {
                    "temperature_c": r.temp,
                    "dewpoint_c": r.dewp,
                    "visibility_m": visibility_m,
                    "wind_speed_ms": wind_speed_ms,
                    "wind_dir_deg": wind_dir_deg,
                    "altimeter_hpa": r.altim,
                    "sea_level_pressure_hpa": r.slp,
                    "flight_category": r.flt_cat
                },
                "quality": {
                    "confidence": quality_confidence,
                    "qc_field": r.qc_field,
                    "metar_type": r.metar_type
                },
                "validates_tile": validates_tile,
                "provenance": {
                    "source": "aviationweather_metar_artifacts",
                    "artifact_path": path.display().to_string(),
                    "receipt_time": r.receipt_time,
                    "report_time": r.report_time,
                    "raw_ob": r.raw_ob,
                    "ingested_at": Utc::now().to_rfc3339()
                }
            });

            arango.upsert_document("observations", &doc).await?;
            obs_written += 1;
        }
    }

    info!(
        "metar_ingest complete: observers_upserted={} observations_upserted={}",
        observers_written, obs_written
    );
    Ok(())
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


