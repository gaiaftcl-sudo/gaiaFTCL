//! Biosphere global ingest from NOAA NOMADS OPeNDAP (GFS 0.25°) biosphere proxies.
//!
//! Writes directly to `biosphere_tiles` with:
//! - vegetation fraction (vegsfc)
//! - soil moisture water (soilw0_10cm)
//! - soil temperature (tsoil0_10cm)
//! - land mask (landsfc)
//!
//! Adaptive resolution tiers:
//! - low: 10° global (stride 40)
//! - medium: 1° lat band (-60..75), land-only (stride 4)
//!
//! FoT: real model output; no fabrication.

use anyhow::{anyhow, Context, Result};
use chrono::{DateTime, NaiveDate, Utc};
use log::info;
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
    nomads_base: String,

    medium_lat_min: f64,
    medium_lat_max: f64,

    high_airport_limit: usize,
    high_radius_km: f64,
}

impl Config {
    fn from_env() -> Self {
        Self {
            arango_url: env::var("ARANGO_URL").unwrap_or_else(|_| "http://localhost:8529".to_string()),
            arango_db: env::var("ARANGO_DB").unwrap_or_else(|_| "gaiaos".to_string()),
            arango_user: env::var("ARANGO_USER").unwrap_or_else(|_| "root".to_string()),
            arango_password: env::var("ARANGO_PASSWORD").unwrap_or_else(|_| "gaiaos".to_string()),
            tiles_collection: env::var("BIOSPHERE_TILES_COLLECTION").unwrap_or_else(|_| "biosphere_tiles".to_string()),
            poll_interval_secs: env::var("POLL_INTERVAL_SECS").ok().and_then(|v| v.parse().ok()).unwrap_or(3600),
            nomads_base: env::var("NOMADS_BASE").unwrap_or_else(|_| "https://nomads.ncep.noaa.gov/dods".to_string()),
            medium_lat_min: env::var("MEDIUM_LAT_MIN").ok().and_then(|v| v.parse().ok()).unwrap_or(-60.0),
            medium_lat_max: env::var("MEDIUM_LAT_MAX").ok().and_then(|v| v.parse().ok()).unwrap_or(75.0),
            high_airport_limit: env::var("HIGH_AIRPORT_LIMIT").ok().and_then(|v| v.parse().ok()).unwrap_or(200),
            high_radius_km: env::var("HIGH_RADIUS_KM").ok().and_then(|v| v.parse().ok()).unwrap_or(200.0),
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
            .timeout(Duration::from_secs(60))
            .user_agent("GaiaOS-Biosphere-NOAA-GFS/0.1.0")
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

fn tile_key(tier: &str, lat: f64, lon: f64, valid_time: i64, step_deg: f64) -> String {
    format!(
        "BIO_GFS_{}_R{}_L{}_O{}_T{}",
        tier,
        (step_deg * 100.0).round() as i32,
        quantize(lat, step_deg),
        quantize(lon, step_deg),
        valid_time
    )
}

#[derive(Default)]
struct Parsed {
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
            if dims.len() != 3 {
                continue;
            }
            let comma = match l.find(',') {
                Some(c) => c,
                None => continue,
            };
            let values_str = &l[comma + 1..];
            let vals: Vec<f64> = values_str
                .split(',')
                .filter_map(|s| s.trim().parse::<f64>().ok())
                .collect();
            p.arrays_2d.entry(var).or_default().extend(vals);
        }
    }
    Ok(p)
}

fn dataset_valid_time_unix(dataset: &str) -> Result<i64> {
    let date_idx = dataset
        .find("gfs20")
        .ok_or_else(|| anyhow!("dataset missing gfsYYYYMMDD: {dataset}"))?;
    let date_str = &dataset[date_idx + 3..date_idx + 11];
    let y = date_str[0..4].parse::<i32>()?;
    let m = date_str[4..6].parse::<u32>()?;
    let d = date_str[6..8].parse::<u32>()?;
    let hour = if let Some(pos) = dataset.rfind('_') {
        let tail = &dataset[pos + 1..];
        tail.get(0..2).ok_or_else(|| anyhow!("missing hour: {dataset}"))?.parse::<u32>()?
    } else {
        0
    };
    let dt = NaiveDate::from_ymd_opt(y, m, d)
        .ok_or_else(|| anyhow!("invalid date ymd in dataset: {dataset}"))?
        .and_hms_opt(hour, 0, 0)
        .ok_or_else(|| anyhow!("invalid hour in dataset: {dataset}"))?;
    Ok(DateTime::<Utc>::from_naive_utc_and_offset(dt, Utc).timestamp())
}

fn dataset_base(cfg: &Config) -> String {
    let now = Utc::now();
    let d = now.format("%Y%m%d").to_string();
    format!("{}/gfs_0p25/gfs{}/gfs_0p25", cfg.nomads_base, d)
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

async fn fetch_vars(
    http: &reqwest::Client,
    dataset: &str,
    lat_start: usize,
    lat_stop: usize,
    lon_start: usize,
    lon_stop: usize,
    stride: usize,
) -> Result<(Parsed, (usize, usize))> {
    // Variables are 0.25° native; indices: lat 0..720, lon 0..1439
    let url = format!(
        "{ds}.ascii?landsfc[0][{ls}:{st}:{le}][{os}:{st}:{oe}],vegsfc[0][{ls}:{st}:{le}][{os}:{st}:{oe}],soilw0_10cm[0][{ls}:{st}:{le}][{os}:{st}:{oe}],tsoil0_10cm[0][{ls}:{st}:{le}][{os}:{st}:{oe}]",
        ds = dataset,
        ls = lat_start,
        le = lat_stop,
        os = lon_start,
        oe = lon_stop,
        st = stride,
    );
    let resp = http.get(&url).send().await.context("ascii request failed")?;
    if !resp.status().is_success() {
        let status = resp.status();
        let text = resp.text().await.unwrap_or_default();
        return Err(anyhow!("ascii http {status}: {text}"));
    }
    let body = resp.text().await?;
    let btrim = body.trim_start();
    if btrim.starts_with("<html") || btrim.contains("GrADS Data Server - error") {
        return Err(anyhow!(
            "nomads returned HTML error page: {}",
            btrim.lines().take(4).collect::<Vec<_>>().join(" | ")
        ));
    }
    let parsed = parse_ascii(&body)?;
    let (lat_n, lon_n) = parsed
        .dims_2d
        .get("landsfc")
        .copied()
        .ok_or_else(|| anyhow!("missing landsfc dims"))?;
    Ok((parsed, (lat_n, lon_n)))
}

async fn write_tiles(
    arango: &Arango,
    collection: &str,
    dataset: &str,
    valid_time: i64,
    tier: &str,
    resolution_deg: f64,
    lat0: f64,
    lon0: f64,
    lat_n: usize,
    lon_n: usize,
    lands: &[f64],
    veg: &[f64],
    soilw: &[f64],
    tsoil: &[f64],
    land_only: bool,
) -> Result<usize> {
    let forecast_time = Utc::now().timestamp();
    let mut written = 0usize;

    for i in 0..lat_n {
        for j in 0..lon_n {
            let idx = i * lon_n + j;
            if idx >= lands.len() || idx >= veg.len() || idx >= soilw.len() || idx >= tsoil.len() {
                continue;
            }
            let land = lands[idx];
            if land_only && land < 0.5 {
                continue;
            }
            let lat = lat0 + (i as f64) * resolution_deg;
            let lon = lon0 + (j as f64) * resolution_deg;
            let key = tile_key(tier, lat, lon, valid_time, resolution_deg);

            let doc = json!({
                "_key": key,
                "location": { "type": "Point", "coordinates": [lon, lat] },
                "forecast_time": forecast_time,
                "valid_time": valid_time,
                "resolution_level": 2,
                "resolution_deg": resolution_deg,
                "resolution_tier": tier,
                "state": {
                    "land_mask": land,
                    "vegetation_fraction": veg[idx],
                    "soil_moisture_0_10cm": soilw[idx],
                    "soil_temp_k_0_10cm": tsoil[idx],
                },
                "uncertainty": { "confidence": 0.7 },
                "provenance": {
                    "source": "noaa_nomads_gfs_biosphere_opendap",
                    "dataset": dataset,
                    "ingest_timestamp": Utc::now().timestamp(),
                    "is_prediction": false
                },
                "observations": []
            });

            arango.upsert_document(collection, &doc).await?;
            written += 1;
        }
    }
    Ok(written)
}

fn approx_deg_radius_km(radius_km: f64) -> f64 {
    radius_km / 111.0
}

async fn run_cycle(cfg: &Config, arango: &Arango, http: &reqwest::Client) -> Result<()> {
    let base = dataset_base(cfg);
    let dataset = select_existing_dataset(http, &base).await?;
    let valid_time = dataset_valid_time_unix(&dataset)?;

    // Low: 10° global (stride 40)
    let (p_low, (lat_n, lon_n)) = fetch_vars(http, &dataset, 0, 720, 0, 1439, 40).await?;
    let lands = p_low.arrays_2d.get("landsfc").cloned().unwrap_or_default();
    let veg = p_low.arrays_2d.get("vegsfc").cloned().unwrap_or_default();
    let soilw = p_low.arrays_2d.get("soilw0_10cm").cloned().unwrap_or_default();
    let tsoil = p_low.arrays_2d.get("tsoil0_10cm").cloned().unwrap_or_default();

    let wrote_low = write_tiles(
        arango,
        &cfg.tiles_collection,
        &dataset,
        valid_time,
        "low",
        10.0,
        -90.0,
        0.0,
        lat_n,
        lon_n,
        &lands,
        &veg,
        &soilw,
        &tsoil,
        false,
    )
    .await?;

    // Medium: 1° land-band (-60..75), land-only (stride 4)
    let lat_start = ((cfg.medium_lat_min + 90.0) / 0.25).round() as usize;
    let lat_stop = ((cfg.medium_lat_max + 90.0) / 0.25).round() as usize;
    let (p_med, (lat_n2, lon_n2)) = fetch_vars(http, &dataset, lat_start, lat_stop, 0, 1439, 4).await?;
    let lands2 = p_med.arrays_2d.get("landsfc").cloned().unwrap_or_default();
    let veg2 = p_med.arrays_2d.get("vegsfc").cloned().unwrap_or_default();
    let soilw2 = p_med.arrays_2d.get("soilw0_10cm").cloned().unwrap_or_default();
    let tsoil2 = p_med.arrays_2d.get("tsoil0_10cm").cloned().unwrap_or_default();

    let lat0 = -90.0 + (lat_start as f64) * 0.25;
    let wrote_med = write_tiles(
        arango,
        &cfg.tiles_collection,
        &dataset,
        valid_time,
        "medium",
        1.0,
        lat0,
        0.0,
        lat_n2,
        lon_n2,
        &lands2,
        &veg2,
        &soilw2,
        &tsoil2,
        true,
    )
    .await?;

    // High: airport-focused refinement (point sets via many small subset requests).
    // This is bounded by HIGH_AIRPORT_LIMIT to keep run time and NOMADS load bounded.
    let mut wrote_high = 0usize;
    let deg_r = approx_deg_radius_km(cfg.high_radius_km);

    // Use a deterministic airport list from ourairports artifacts if present in Arango? Not required.
    // We approximate by selecting a global "high-res rings" centered on major lat/lon anchors.
    // FoT: still uses NOMADS data; high-tier is optional refinement.
    let centers = [
        (40.7, -74.0),   // NYC
        (34.0, -118.2),  // LA
        (51.5, -0.1),    // London
        (35.7, 139.7),   // Tokyo
        (31.2, 121.5),   // Shanghai
        (25.3, 55.3),    // Dubai
        (1.35, 103.8),   // Singapore
        (48.35, 11.8),   // Munich
        (19.4, -99.1),   // Mexico City
        (-23.6, -46.7),  // Sao Paulo
    ];

    for (idx, (clat_ref, clon_raw_ref)) in centers.iter().enumerate() {
        if idx >= cfg.high_airport_limit {
            break;
        }
        let clat: f64 = *clat_ref;
        let clon_raw: f64 = *clon_raw_ref;
        let clon = if clon_raw < 0.0 { clon_raw + 360.0 } else { clon_raw };

        // Convert to index space (0.25° grid)
        let lat_center_idx = ((clat + 90.0) / 0.25_f64).round() as i64;
        let lon_center_idx = (clon / 0.25_f64).round() as i64;
        let delta_idx = (deg_r / 0.25).round() as i64;

        let lat_start = (lat_center_idx - delta_idx).max(0) as usize;
        let lat_stop = (lat_center_idx + delta_idx).min(720) as usize;
        let lon_start = (lon_center_idx - delta_idx).max(0) as usize;
        let lon_stop = (lon_center_idx + delta_idx).min(1439) as usize;

        let (p_hi, (hn, wn)) = fetch_vars(http, &dataset, lat_start, lat_stop, lon_start, lon_stop, 1).await?;
        let lands_h = p_hi.arrays_2d.get("landsfc").cloned().unwrap_or_default();
        let veg_h = p_hi.arrays_2d.get("vegsfc").cloned().unwrap_or_default();
        let soilw_h = p_hi.arrays_2d.get("soilw0_10cm").cloned().unwrap_or_default();
        let tsoil_h = p_hi.arrays_2d.get("tsoil0_10cm").cloned().unwrap_or_default();

        let lat0 = -90.0 + (lat_start as f64) * 0.25;
        let lon0 = (lon_start as f64) * 0.25;
        wrote_high += write_tiles(
            arango,
            &cfg.tiles_collection,
            &dataset,
            valid_time,
            "high",
            0.25,
            lat0,
            lon0,
            hn,
            wn,
            &lands_h,
            &veg_h,
            &soilw_h,
            &tsoil_h,
            true,
        )
        .await?;
    }

    info!(
        "biosphere_noaa_gfs cycle: dataset={} valid_time={} wrote_low={} wrote_medium={} wrote_high={}",
        dataset, valid_time, wrote_low, wrote_med, wrote_high
    );
    Ok(())
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

    info!("Starting biosphere_noaa_gfs_biosphere_ingest nomads_base={}", cfg.nomads_base);
    let mut interval = tokio::time::interval(Duration::from_secs(cfg.poll_interval_secs));
    loop {
        interval.tick().await;
        if let Err(e) = run_cycle(&cfg, &arango, &http).await {
            return Err(e);
        }
    }
}


