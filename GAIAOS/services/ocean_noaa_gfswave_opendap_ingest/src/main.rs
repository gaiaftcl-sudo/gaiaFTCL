//! Ocean global ingest from NOAA NOMADS OPeNDAP (GFSWAVE global 0p25).
//!
//! - Pulls a coarse, strided global subset via `.ascii` (single request per cycle).
//! - Writes directly to `ocean_tiles` with wave height/direction/period.

use anyhow::{anyhow, Context, Result};
use chrono::{DateTime, Duration as ChronoDuration, NaiveDate, Utc};
use log::{info, warn};
use serde_json::json;
use std::{collections::HashMap, env, time::Duration};

#[derive(Clone)]
struct Config {
    arango_url: String,
    arango_db: String,
    arango_user: String,
    arango_password: String,
    tiles_collection: String,
    poll_interval_secs: u64,

    nomads_base: String, // https://nomads.ncep.noaa.gov/dods
    stride: usize,       // index stride across lat/lon (0.25° native for this dataset)
}

impl Config {
    fn from_env() -> Self {
        Self {
            arango_url: env::var("ARANGO_URL").unwrap_or_else(|_| "http://localhost:8529".to_string()),
            arango_db: env::var("ARANGO_DB").unwrap_or_else(|_| "gaiaos".to_string()),
            arango_user: env::var("ARANGO_USER").unwrap_or_else(|_| "root".to_string()),
            arango_password: env::var("ARANGO_PASSWORD").unwrap_or_else(|_| "gaiaos".to_string()),
            tiles_collection: env::var("OCEAN_TILES_COLLECTION").unwrap_or_else(|_| "ocean_tiles".to_string()),
            poll_interval_secs: env::var("POLL_INTERVAL_SECS").ok().and_then(|v| v.parse().ok()).unwrap_or(3600),
            nomads_base: env::var("NOMADS_BASE").unwrap_or_else(|_| "https://nomads.ncep.noaa.gov/dods".to_string()),
            stride: env::var("STRIDE").ok().and_then(|v| v.parse().ok()).unwrap_or(40), // 10°
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
            .timeout(Duration::from_secs(90))
            .user_agent("GaiaOS-Ocean-NOAA-GFSWAVE-OPeNDAP/0.1.0")
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

fn quantize(v: f64, step: f64) -> i32 {
    if step <= 0.0 {
        return (v * 100.0).round() as i32;
    }
    (v / step).round() as i32
}

fn tile_key(lat: f64, lon: f64, valid_time: i64, step_deg: f64) -> String {
    format!(
        "OCN_GFSWAVE_NOAA_L{}_O{}_Z0_T{}",
        quantize(lat, step_deg),
        quantize(lon, step_deg),
        valid_time
    )
}

#[derive(Default)]
struct Parsed {
    arrays_1d: HashMap<String, Vec<f64>>,
    arrays_2d: HashMap<String, Vec<f64>>,
    dims_2d: HashMap<String, (usize, usize)>,
}

fn parse_ascii(body: &str) -> Result<Parsed> {
    let mut p = Parsed::default();
    let mut current: Option<String> = None;
    let mut current_dims: Option<Vec<usize>> = None;

    for line in body.lines() {
        let l = line.trim();
        if l.is_empty() {
            continue;
        }
        if l.contains(", [") && !l.starts_with('[') {
            let parts: Vec<&str> = l.splitn(2, ',').collect();
            if parts.len() != 2 {
                continue;
            }
            let name = parts[0].trim().to_string();
            let dim_part = parts[1];
            let mut dims = Vec::new();
            for seg in dim_part.split('[').skip(1) {
                if let Some(end) = seg.find(']') {
                    let n = seg[..end].trim().parse::<usize>().unwrap_or(0);
                    dims.push(n);
                }
            }
            current = Some(name.clone());
            current_dims = Some(dims.clone());
            if dims.len() == 3 {
                p.dims_2d.insert(name, (dims[1], dims[2]));
            }
            continue;
        }
        if l.starts_with('[') {
            let Some(var) = current.clone() else { continue };
            let Some(dims) = current_dims.clone() else { continue };
            let comma = match l.find(',') {
                Some(c) => c,
                None => continue,
            };
            let values_str = &l[comma + 1..];
            let vals: Vec<f64> = values_str
                .split(',')
                .filter_map(|s| {
                    let t = s.trim();
                    if t.is_empty() {
                        None
                    } else {
                        t.parse::<f64>().ok()
                    }
                })
                .collect();
            if dims.len() == 1 {
                p.arrays_1d.entry(var).or_default().extend(vals);
            } else if dims.len() == 3 {
                p.arrays_2d.entry(var).or_default().extend(vals);
            }
        } else {
            let Some(var) = current.clone() else { continue };
            let Some(dims) = current_dims.clone() else { continue };
            if dims.len() != 1 {
                continue;
            }
            let vals: Vec<f64> = l
                .split(',')
                .filter_map(|s| {
                    let t = s.trim();
                    if t.is_empty() {
                        None
                    } else {
                        t.parse::<f64>().ok()
                    }
                })
                .collect();
            if !vals.is_empty() {
                p.arrays_1d.entry(var).or_default().extend(vals);
            }
        }
    }
    Ok(p)
}

fn dataset_valid_time_unix(dataset: &str) -> Result<i64> {
    // Example:
    // .../wave/gfswave/20251227/gfswave.global.0p25_06z
    let parts: Vec<&str> = dataset.split('/').collect();
    let date_part = parts
        .iter()
        .rev()
        .find(|s| s.len() == 8 && s.chars().all(|c| c.is_ascii_digit()))
        .ok_or_else(|| anyhow!("dataset missing YYYYMMDD path: {dataset}"))?;
    let y = date_part[0..4].parse::<i32>()?;
    let m = date_part[4..6].parse::<u32>()?;
    let d = date_part[6..8].parse::<u32>()?;

    let hour = if let Some(pos) = dataset.rfind('_') {
        let tail = &dataset[pos + 1..];
        let hh = tail
            .get(0..2)
            .ok_or_else(|| anyhow!("missing hour in dataset tail: {dataset}"))?;
        hh.parse::<u32>()?
    } else {
        0
    };

    let dt = NaiveDate::from_ymd_opt(y, m, d)
        .ok_or_else(|| anyhow!("invalid date ymd in dataset: {dataset}"))?
        .and_hms_opt(hour, 0, 0)
        .ok_or_else(|| anyhow!("invalid hour in dataset: {dataset}"))?;
    Ok(DateTime::<Utc>::from_naive_utc_and_offset(dt, Utc).timestamp())
}

fn find_dataset_base(cfg: &Config) -> String {
    let now = Utc::now();
    let d = now.format("%Y%m%d").to_string();
    format!("{}/wave/gfswave/{}/gfswave.global.0p25", cfg.nomads_base, d)
}

async fn select_existing_dataset(http: &reqwest::Client, base: &str) -> Result<String> {
    for cand in [
        format!("{base}_18z"),
        format!("{base}_12z"),
        format!("{base}_06z"),
        format!("{base}_00z"),
    ] {
        let url = format!("{cand}.dds");
        let resp = http.get(&url).send().await?;
        if resp.status().is_success() {
            let txt = resp.text().await.unwrap_or_default();
            let t = txt.trim_start();
            if t.starts_with("Dataset {") || t.contains("Dataset {") {
                return Ok(cand);
            }
        }
    }
    Err(anyhow!("no available dataset found under base={base}"))
}

async fn fetch_global_subset(
    cfg: &Config,
    http: &reqwest::Client,
    dataset: &str,
) -> Result<(i64, Vec<f64>, Vec<f64>, Vec<f64>, Vec<f64>, Vec<f64>, (usize, usize))> {
    let stride = cfg.stride;
    let lat_stop = 720usize;
    let lon_stop = 1439usize;
    let valid_time = dataset_valid_time_unix(dataset)?;
    let lat_n = (lat_stop / stride) + 1;
    let lon_n = (lon_stop / stride) + 1;
    let step_deg = stride as f64 * 0.25;
    let lat = (0..lat_n).map(|i| -90.0 + (i as f64) * step_deg).collect::<Vec<_>>();
    let lon = (0..lon_n).map(|j| 0.0 + (j as f64) * step_deg).collect::<Vec<_>>();

    let data_url = format!(
        "{ds}.ascii?htsgwsfc[0][0:{st}:{lat_stop}][0:{st}:{lon_stop}],wvdirsfc[0][0:{st}:{lat_stop}][0:{st}:{lon_stop}],wvpersfc[0][0:{st}:{lat_stop}][0:{st}:{lon_stop}]",
        ds = dataset,
        st = stride,
        lat_stop = lat_stop,
        lon_stop = lon_stop,
    );
    let resp = http.get(&data_url).send().await.context("ascii data request failed")?;
    if !resp.status().is_success() {
        let status = resp.status();
        let text = resp.text().await.unwrap_or_default();
        return Err(anyhow!("ascii data http {status}: {text}"));
    }
    let body = resp.text().await?;
    let btrim = body.trim_start();
    if btrim.starts_with("<html") || btrim.contains("GrADS Data Server - error") {
        return Err(anyhow!(
            "nomads returned HTML error page for data request (dataset={}): {}",
            dataset,
            btrim.lines().take(4).collect::<Vec<_>>().join(" | ")
        ));
    }
    let parsed = parse_ascii(&body)?;

    let (lat_n2, lon_n2) = parsed
        .dims_2d
        .get("htsgwsfc")
        .copied()
        .ok_or_else(|| anyhow!("missing htsgwsfc dims"))?;
    if lat_n2 != lat_n || lon_n2 != lon_n {
        return Err(anyhow!(
            "dims mismatch lat_n/lon_n computed={}x{} vs dataset={}x{}",
            lat_n, lon_n, lat_n2, lon_n2
        ));
    }

    let htsgwsfc = parsed.arrays_2d.get("htsgwsfc").cloned().ok_or_else(|| anyhow!("missing htsgwsfc"))?;
    let wvdirsfc = parsed.arrays_2d.get("wvdirsfc").cloned().ok_or_else(|| anyhow!("missing wvdirsfc"))?;
    let wvpersfc = parsed.arrays_2d.get("wvpersfc").cloned().ok_or_else(|| anyhow!("missing wvpersfc"))?;

    Ok((valid_time, lat, lon, htsgwsfc, wvdirsfc, wvpersfc, (lat_n, lon_n)))
}

async fn run_cycle(cfg: &Config, arango: &Arango, http: &reqwest::Client) -> Result<usize> {
    let base = find_dataset_base(cfg);
    let dataset = select_existing_dataset(http, &base).await?;
    let (valid_time, lat, lon, hts, wdir, wper, (lat_n, lon_n)) = fetch_global_subset(cfg, http, &dataset).await?;

    let resolution_deg = cfg.stride as f64 * 0.25;
    let forecast_time = Utc::now().timestamp();

    if lat.len() != lat_n {
        return Err(anyhow!("lat len mismatch: {} vs {}", lat.len(), lat_n));
    }
    if lon.len() != lon_n {
        return Err(anyhow!("lon len mismatch: {} vs {}", lon.len(), lon_n));
    }

    let mut written = 0usize;
    for i in 0..lat_n {
        for j in 0..lon_n {
            let idx = i * lon_n + j;
            if idx >= hts.len() || idx >= wdir.len() || idx >= wper.len() {
                continue;
            }
            let la = lat[i];
            let lo = lon[j];
            let key = tile_key(la, lo, valid_time, resolution_deg);
            let doc = json!({
                "_key": key,
                "location": { "type": "Point", "coordinates": [lo, la] },
                "depth_m": 0,
                "forecast_time": forecast_time,
                "valid_time": valid_time,
                "resolution_level": 4,
                "resolution_deg": resolution_deg,
                "state": {
                    "current_u": 0.0,
                    "current_v": 0.0,
                    "temperature_k": 0.0,
                    "salinity_psu": 0.0,
                    "wave_height_m": hts[idx],
                    "wave_direction_deg": wdir[idx],
                    "wave_period_s": wper[idx]
                },
                "uncertainty": { "confidence": 0.7 },
                "provenance": {
                    "source": "noaa_nomads_gfswave_global_0p25_opendap",
                    "dataset": dataset,
                    "ingest_timestamp": Utc::now().timestamp(),
                    "is_prediction": false
                },
                "observations": []
            });
            if let Err(e) = arango.upsert_document(&cfg.tiles_collection, &doc).await {
                warn!("upsert failed: {e:#}");
            } else {
                written += 1;
            }
        }
    }

    info!(
        "noaa_gfswave cycle: dataset={} valid_time={} resolution_deg={} tiles_upserted={}",
        dataset, valid_time, resolution_deg, written
    );
    Ok(written)
}

#[tokio::main]
async fn main() -> Result<()> {
    env_logger::init();
    let cfg = Config::from_env();
    let arango = Arango::new(cfg.arango_url.clone(), cfg.arango_db.clone(), cfg.arango_user.clone(), cfg.arango_password.clone())?;
    let http = reqwest::Client::builder()
        .timeout(Duration::from_secs(120))
        .http1_only()
        .user_agent("curl/8.0 (GaiaOS NOMADS client)")
        .build()?;

    info!("Starting ocean_noaa_gfswave_opendap_ingest stride={}", cfg.stride);
    let mut interval = tokio::time::interval(Duration::from_secs(cfg.poll_interval_secs));
    loop {
        interval.tick().await;
        if let Err(e) = run_cycle(&cfg, &arango, &http).await {
            warn!("cycle failed: {e:#}");
        }
    }
}


