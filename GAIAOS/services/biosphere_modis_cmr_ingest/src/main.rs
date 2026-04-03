//! Biosphere ingest (NASA CMR -> MODIS NDVI granules) - evidence-only
//!
//! This service:
//! - Queries NASA CMR for MOD13A2 (MODIS NDVI) granules over a bbox+time window
//! - For each candidate URL, performs an authenticated HEAD against the LP DAAC host
//! - Only if HEAD succeeds, writes an observation (metadata + content-length) to ArangoDB
//!
//! FoT: does NOT invent NDVI values. It only ingests verified, reachable real granules.

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

    earthdata_user: String,
    earthdata_password: String,

    // CMR search
    cmr_url: String,
    short_name: String,
    version: String,
    bbox: String, // lon_min,lat_min,lon_max,lat_max
    temporal: String, // start,end RFC3339
    limit: usize,

    poll_interval_secs: u64,
    tile_step_deg: f64,
    tile_time_bucket_secs: i64,
}

impl Config {
    fn from_env() -> Result<Self> {
        let earthdata_user = env::var("EARTHDATA_USERNAME")
            .context("EARTHDATA_USERNAME is required")?
            .trim()
            .to_string();

        let earthdata_password_file = env::var("EARTHDATA_PASSWORD_FILE")
            .ok()
            .map(|v| v.trim().to_string())
            .filter(|v| !v.is_empty());

        let earthdata_password = match (&earthdata_password_file, env::var("EARTHDATA_PASSWORD").ok()) {
            (Some(path), _) => std::fs::read_to_string(path)
                .with_context(|| format!("failed to read EARTHDATA_PASSWORD_FILE at {path}"))?
                .trim()
                .to_string(),
            (None, Some(p)) => p.trim().to_string(),
            (None, None) => String::new(),
        };

        if earthdata_user.is_empty() || earthdata_password.is_empty() {
            return Err(anyhow!("EARTHDATA_USERNAME + (EARTHDATA_PASSWORD or EARTHDATA_PASSWORD_FILE) must be set to non-empty values"));
        }

        Ok(Self {
            arango_url: env::var("ARANGO_URL").unwrap_or_else(|_| "http://localhost:8529".to_string()),
            arango_db: env::var("ARANGO_DB").unwrap_or_else(|_| "gaiaos".to_string()),
            arango_user: env::var("ARANGO_USER").unwrap_or_else(|_| "root".to_string()),
            arango_password: env::var("ARANGO_PASSWORD").unwrap_or_else(|_| "gaiaos".to_string()),

            earthdata_user,
            earthdata_password,

            cmr_url: env::var("CMR_URL")
                .unwrap_or_else(|_| "https://cmr.earthdata.nasa.gov/search/granules.json".to_string()),
            short_name: env::var("CMR_SHORT_NAME").unwrap_or_else(|_| "MOD13A2".to_string()),
            version: env::var("CMR_VERSION").unwrap_or_else(|_| "061".to_string()),
            bbox: env::var("CMR_BBOX").unwrap_or_else(|_| "-180,-90,180,90".to_string()),
            temporal: env::var("CMR_TEMPORAL")
                .ok()
                .map(|v| v.trim().to_string())
                .filter(|v| !v.is_empty())
                .unwrap_or_else(|| {
                    // Default: last 2 days (CMR expects "start,end")
                    let end = Utc::now();
                    let start = end - chrono::Duration::days(2);
                    format!("{},{}", start.to_rfc3339(), end.to_rfc3339())
                }),
            limit: env::var("CMR_LIMIT").ok().and_then(|v| v.parse().ok()).unwrap_or(2000),

            poll_interval_secs: env::var("POLL_INTERVAL_SECS").ok().and_then(|v| v.parse().ok()).unwrap_or(21600),
            tile_step_deg: env::var("TILE_STEP_DEG").ok().and_then(|v| v.parse().ok()).unwrap_or(0.25),
            tile_time_bucket_secs: env::var("TILE_TIME_BUCKET_SECS").ok().and_then(|v| v.parse().ok()).unwrap_or(86400),
        })
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
            .user_agent("GaiaOS-Biosphere-MODIS-CMR/0.1.0")
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
            return Err(anyhow!("arango upsert failed {status}: {text}"));
        }
        Ok(())
    }
}

#[derive(Debug, Deserialize)]
struct CmrResp {
    feed: CmrFeed,
}

#[derive(Debug, Deserialize)]
struct CmrFeed {
    #[serde(rename = "entry")]
    entries: Vec<CmrEntry>,
}

#[derive(Debug, Deserialize)]
struct CmrEntry {
    id: String,
    title: String,
    updated: String,
    #[serde(default)]
    boxes: Vec<String>,
    #[serde(default)]
    links: Vec<CmrLink>,
}

#[derive(Debug, Deserialize)]
struct CmrLink {
    href: Option<String>,
    #[serde(default)]
    rel: Option<String>,
    #[serde(default)]
    inherited: Option<bool>,
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

fn biosphere_tile_key(lat: f64, lon: f64, valid_time: i64, step_deg: f64) -> String {
    format!(
        "BIO_L{}_O{}_T{}",
        quantize(lat, step_deg),
        quantize(lon, step_deg),
        valid_time
    )
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

fn pick_candidate_urls(entry: &CmrEntry) -> Vec<String> {
    // Prefer https links that look like data pool or LP DAAC.
    let mut out = Vec::new();
    for l in &entry.links {
        if l.inherited.unwrap_or(false) {
            continue;
        }
        let Some(href) = &l.href else { continue };
        if !href.starts_with("https://") {
            continue;
        }
        // Skip "metadata" rels
        if let Some(rel) = &l.rel {
            if rel.contains("metadata") {
                continue;
            }
        }
        out.push(href.clone());
    }
    out
}

async fn cmr_search(http: &reqwest::Client, cfg: &Config) -> Result<Vec<CmrEntry>> {
    let resp = http
        .get(&cfg.cmr_url)
        .query(&[
            ("short_name", cfg.short_name.as_str()),
            ("version", cfg.version.as_str()),
            ("bounding_box", cfg.bbox.as_str()),
            ("temporal", cfg.temporal.as_str()),
            ("page_size", &cfg.limit.to_string()),
        ])
        .send()
        .await
        .context("cmr request failed")?;

    if !resp.status().is_success() {
        let status = resp.status();
        let text = resp.text().await.unwrap_or_default();
        return Err(anyhow!("cmr http {status}: {text}"));
    }

    let body: CmrResp = resp.json().await.context("cmr json decode failed")?;
    Ok(body.feed.entries)
}

async fn head_verify(http: &reqwest::Client, user: &str, pwd: &str, url: &str) -> Result<(u16, Option<u64>)> {
    let resp = http
        .head(url)
        .basic_auth(user, Some(pwd))
        .send()
        .await
        .context("earthdata head failed")?;
    let status = resp.status().as_u16();
    let len = resp
        .headers()
        .get(reqwest::header::CONTENT_LENGTH)
        .and_then(|v| v.to_str().ok())
        .and_then(|s| s.parse::<u64>().ok());
    Ok((status, len))
}

async fn ingest_cycle(cfg: &Config, arango: &Arango, http: &reqwest::Client) -> Result<(usize, usize)> {
    let entries = cmr_search(http, cfg).await?;

    // Single observer for this stream
    let observer_key = "earthdata_modis_mod13a2".to_string();
    let observer_id = format!("earthdata:{}:{}", cfg.short_name, cfg.version);
    let observer_doc = json!({
        "_key": observer_key,
        "type": "biosphere_remote_sensing_catalog",
        "observer_id": observer_id,
        "name": "NASA Earthdata CMR (MODIS MOD13A2 NDVI catalog)",
        "operational": true,
        "provenance": {
            "source": "nasa_cmr",
            "cmr_url": cfg.cmr_url,
            "short_name": cfg.short_name,
            "version": cfg.version,
            "bbox": cfg.bbox,
            "temporal": cfg.temporal,
            "ingested_at": Utc::now().to_rfc3339()
        }
    });
    arango.upsert_document("observers", &observer_doc).await?;

    let mut obs_written = 0usize;
    for e in entries {
        let updated: DateTime<Utc> = DateTime::parse_from_rfc3339(&e.updated)
            .map(|d| d.with_timezone(&Utc))
            .or_else(|_| DateTime::parse_from_str(&e.updated, "%Y-%m-%dT%H:%M:%SZ").map(|d| d.with_timezone(&Utc)))
            .context("failed to parse entry.updated")?;

        // Verify at least one candidate URL is reachable with Earthdata creds.
        let candidates = pick_candidate_urls(&e);
        let mut verified: Option<(String, u16, Option<u64>)> = None;
        for url in candidates {
            match head_verify(http, &cfg.earthdata_user, &cfg.earthdata_password, &url).await {
                Ok((status, len)) if status >= 200 && status < 400 => {
                    verified = Some((url, status, len));
                    break;
                }
                Ok((status, _)) => {
                    // 401/403 common if user hasn't approved DAAC; keep searching.
                    warn!("earthdata head not ok status={} for {}", status, url);
                }
                Err(err) => {
                    warn!("earthdata head failed for url: {err:#}");
                }
            }
        }

        let Some((verified_url, verified_status, content_len)) = verified else {
            continue;
        };

        // Evidence-only: locate each granule using CMR-provided spatial boxes if present.
        // If boxes are absent, we fall back to the query bbox center.
        let (lon_min, lat_min, lon_max, lat_max) = if let Some(b) = e.boxes.first() {
            // CMR boxes are "lat_min lon_min lat_max lon_max"
            let parts: Vec<&str> = b.split_whitespace().collect();
            if parts.len() == 4 {
                let lat_min = parts[0].parse::<f64>()?;
                let lon_min = parts[1].parse::<f64>()?;
                let lat_max = parts[2].parse::<f64>()?;
                let lon_max = parts[3].parse::<f64>()?;
                (lon_min, lat_min, lon_max, lat_max)
            } else {
                let parts: Vec<&str> = cfg.bbox.split(',').map(|s| s.trim()).collect();
                if parts.len() != 4 {
                    return Err(anyhow!("CMR_BBOX must be lon_min,lat_min,lon_max,lat_max"));
                }
                (
                    parts[0].parse::<f64>()?,
                    parts[1].parse::<f64>()?,
                    parts[2].parse::<f64>()?,
                    parts[3].parse::<f64>()?,
                )
            }
        } else {
            let parts: Vec<&str> = cfg.bbox.split(',').map(|s| s.trim()).collect();
            if parts.len() != 4 {
                return Err(anyhow!("CMR_BBOX must be lon_min,lat_min,lon_max,lat_max"));
            }
            (
                parts[0].parse::<f64>()?,
                parts[1].parse::<f64>()?,
                parts[2].parse::<f64>()?,
                parts[3].parse::<f64>()?,
            )
        };
        let lat = (lat_min + lat_max) / 2.0;
        let lon = (lon_min + lon_max) / 2.0;

        let ts = updated.timestamp();
        let valid_time = time_bucket(ts, cfg.tile_time_bucket_secs);
        let validates_tile = biosphere_tile_key(lat, lon, valid_time, cfg.tile_step_deg);

        let key = format!("CMR_MOD13A2_{}", e.id.replace('-', "_"));
        let doc = json!({
            "_key": key,
            "observer_id": observer_id,
            "observer_type": "biosphere_modis_ndvi_catalog",
            "timestamp": ts,
            "ingest_timestamp": Utc::now().timestamp(),
            "timestamp_rfc3339": updated.to_rfc3339(),
            "location": { "type": "Point", "coordinates": [lon, lat] },
            "altitude_ft": 0,
            "measurement": {
                "granule_id": e.id,
                "title": e.title,
                "cmr_box": e.boxes.first().cloned().unwrap_or_default(),
                "verified_url": verified_url,
                "verified_http_status": verified_status,
                "content_length_bytes": content_len
            },
            "quality": {
                "confidence": 0.9,
                "source": "nasa_earthdata"
            },
            "validates_tile": validates_tile,
            "provenance": {
                "source": "nasa_cmr",
                "short_name": cfg.short_name,
                "version": cfg.version,
                "cmr_url": cfg.cmr_url,
                "ingested_at": Utc::now().to_rfc3339()
            }
        });

        arango.upsert_document("observations", &doc).await?;
        obs_written += 1;
    }

    Ok((1, obs_written))
}

#[tokio::main]
async fn main() -> Result<()> {
    env_logger::init();
    let cfg = Config::from_env()?;

    let arango = Arango::new(
        cfg.arango_url.clone(),
        cfg.arango_db.clone(),
        cfg.arango_user.clone(),
        cfg.arango_password.clone(),
    )?;
    let http = reqwest::Client::builder()
        .timeout(Duration::from_secs(60))
        .user_agent("GaiaOS-Biosphere-MODIS-CMR/0.1.0")
        .build()
        .context("failed to build http client")?;

    info!(
        "Starting biosphere_modis_cmr_ingest short_name={} version={} bbox={} temporal={} limit={}",
        cfg.short_name, cfg.version, cfg.bbox, cfg.temporal, cfg.limit
    );

    let mut interval = tokio::time::interval(Duration::from_secs(cfg.poll_interval_secs));
    loop {
        interval.tick().await;
        match ingest_cycle(&cfg, &arango, &http).await {
            Ok((o, n)) => info!("modis_cmr cycle: observers_upserted={} observations_upserted={}", o, n),
            Err(e) => warn!("modis_cmr cycle failed: {e:#}"),
        }
    }
}


