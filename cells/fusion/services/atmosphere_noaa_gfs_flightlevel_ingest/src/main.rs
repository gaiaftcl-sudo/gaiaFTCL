//! Cruise-altitude atmosphere ingest from NOAA NOMADS OPeNDAP (GFS 0.25° isobaric levels).
//!
//! Produces `atmosphere_tiles` with:
//! - altitude_m / altitude_ft (from hgtprs)
//! - temperature_k (tmpprs)
//! - wind_u / wind_v (ugrdprs/vgrdprs)
//! - air_density_kg_m3 computed as p/(R*T) at the pressure level
//! - pressure_pa (from selected lev millibar)
//!
//! FoT: all values are real model output; no synthesis.

use anyhow::{anyhow, Context, Result};
use chrono::{DateTime, NaiveDate, Utc};
use log::{info, warn};
use serde_json::json;
use std::{collections::HashMap, env, time::Duration};

mod turbulence;

const R_DRY_AIR: f64 = 287.05;

const DEFAULT_LEVELS_MB: &str = "200,250,300,350,400";
const DEFAULT_VARIABLES: &str = "tmpprs,hgtprs,ugrdprs,vgrdprs,vvelprs,absvprs";

#[derive(Clone)]
struct Config {
    arango_url: String,
    arango_db: String,
    arango_user: String,
    arango_password: String,
    tiles_collection: String,
    poll_interval_secs: u64,
    nomads_base: String,
    stride: usize, // 40 => 10° grid
    levels_mb: Vec<i64>, // e.g. 300,250,200
    variables: Vec<String>,
}

impl Config {
    fn from_env() -> Self {
        let levels_raw = env::var("LEVELS_MB").unwrap_or_else(|_| DEFAULT_LEVELS_MB.to_string());
        let mut levels_mb = Vec::new();
        for s in levels_raw.split(',') {
            if let Ok(v) = s.trim().parse::<i64>() {
                levels_mb.push(v);
            }
        }
        if levels_mb.is_empty() {
            levels_mb = DEFAULT_LEVELS_MB
                .split(',')
                .filter_map(|s| s.trim().parse::<i64>().ok())
                .collect();
        }

        // Supported variables for this ingest.
        // Defaults match the CAT turbulence plan: 6 variables.
        let variables_raw = env::var("VARIABLES").unwrap_or_else(|_| DEFAULT_VARIABLES.to_string());
        let variables = variables_raw
            .split(',')
            .map(|s| s.trim().to_string())
            .filter(|s| !s.is_empty())
            .collect::<Vec<_>>();

        Self {
            arango_url: env::var("ARANGO_URL").unwrap_or_else(|_| "http://localhost:8529".to_string()),
            arango_db: env::var("ARANGO_DB").unwrap_or_else(|_| "gaiaos".to_string()),
            arango_user: env::var("ARANGO_USER").unwrap_or_else(|_| "root".to_string()),
            arango_password: env::var("ARANGO_PASSWORD").unwrap_or_else(|_| "gaiaos".to_string()),
            tiles_collection: env::var("ATMOSPHERE_TILES_COLLECTION").unwrap_or_else(|_| "atmosphere_tiles".to_string()),
            poll_interval_secs: env::var("POLL_INTERVAL_SECS").ok().and_then(|v| v.parse().ok()).unwrap_or(3600),
            nomads_base: env::var("NOMADS_BASE").unwrap_or_else(|_| "https://nomads.ncep.noaa.gov/dods".to_string()),
            stride: env::var("STRIDE").ok().and_then(|v| v.parse().ok()).unwrap_or(40),
            levels_mb,
            variables,
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
            .user_agent("GaiaOS-Atmosphere-NOAA-GFS-FlightLevel/0.1.0")
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
                // [time][lat][lon]
                p.dims_2d.insert(name, (dims[1], dims[2]));
            } else if dims.len() == 4 {
                // [time][lev][lat][lon] (time+lev fixed by query => 2D field)
                p.dims_2d.insert(name, (dims[2], dims[3]));
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
                .filter_map(|s| s.trim().parse::<f64>().ok())
                .collect();
            if dims.len() == 1 {
                p.arrays_1d.entry(var).or_default().extend(vals);
            } else if dims.len() == 3 || dims.len() == 4 {
                p.arrays_2d.entry(var).or_default().extend(vals);
            }
        } else {
            // scalar/1D blocks may be unindexed
            let Some(var) = current.clone() else { continue };
            let Some(dims) = current_dims.clone() else { continue };
            if dims.len() != 1 {
                continue;
            }
            let vals: Vec<f64> = l
                .split(',')
                .filter_map(|s| s.trim().parse::<f64>().ok())
                .collect();
            if !vals.is_empty() {
                p.arrays_1d.entry(var).or_default().extend(vals);
            }
        }
    }

    Ok(p)
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

fn lon_lat_counts_for_stride(stride: usize) -> (usize, usize) {
    let lat_stop = 720usize;
    let lon_stop = 1439usize;
    ((lat_stop / stride) + 1, (lon_stop / stride) + 1)
}

fn grid_lat_lon(stride: usize) -> (Vec<f64>, Vec<f64>, f64) {
    let (lat_n, lon_n) = lon_lat_counts_for_stride(stride);
    let step_deg = stride as f64 * 0.25;
    let lat = (0..lat_n).map(|i| -90.0 + (i as f64) * step_deg).collect::<Vec<_>>();
    let lon = (0..lon_n).map(|j| 0.0 + (j as f64) * step_deg).collect::<Vec<_>>();
    (lat, lon, step_deg)
}

async fn fetch_lev_mb(http: &reqwest::Client, dataset: &str) -> Result<Vec<i64>> {
    let url = format!("{dataset}.ascii?lev[0:40]");
    let resp = http.get(&url).send().await.context("lev ascii request failed")?;
    if !resp.status().is_success() {
        let status = resp.status();
        let text = resp.text().await.unwrap_or_default();
        return Err(anyhow!("lev ascii http {status}: {text}"));
    }
    let body = resp.text().await?;
    let p = parse_ascii(&body)?;
    let lev = p
        .arrays_1d
        .get("lev")
        .cloned()
        .ok_or_else(|| anyhow!("missing lev array"))?;
    Ok(lev.into_iter().map(|v| v.round() as i64).collect())
}

async fn fetch_level_fields(
    http: &reqwest::Client,
    dataset: &str,
    variables: &[String],
    stride: usize,
    lev_idx: usize,
) -> Result<HashMap<String, Vec<f64>>> {
    let lat_stop = 720usize;
    let lon_stop = 1439usize;

    let required = ["tmpprs", "hgtprs", "ugrdprs", "vgrdprs", "vvelprs", "absvprs"];
    for r in required {
        if !variables.iter().any(|v| v == r) {
            return Err(anyhow!("VARIABLES missing required var={r} (need {DEFAULT_VARIABLES})"));
        }
    }

    let mut segs = Vec::new();
    for v in variables {
        match v.as_str() {
            "tmpprs" | "hgtprs" | "ugrdprs" | "vgrdprs" | "vvelprs" | "absvprs" => {
                segs.push(format!(
                    "{v}[0][{lev}][0:{st}:{lat_stop}][0:{st}:{lon_stop}]",
                    lev = lev_idx,
                    st = stride
                ));
            }
            other => return Err(anyhow!("unsupported VARIABLES entry: {other}")),
        }
    }
    let url = format!("{dataset}.ascii?{}", segs.join(","));
    let resp = http.get(&url).send().await.context("level ascii request failed")?;
    if !resp.status().is_success() {
        let status = resp.status();
        let text = resp.text().await.unwrap_or_default();
        return Err(anyhow!("level ascii http {status}: {text}"));
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
    let mut out = HashMap::new();
    for k in &required {
        let vals = parsed
            .arrays_2d
            .get(*k)
            .cloned()
            .ok_or_else(|| anyhow!("missing {k}"))?;
        out.insert((*k).to_string(), vals);
    }
    Ok(out)
}

fn make_key(level_mb: i64, step_deg: f64, lat: f64, lon: f64, valid_time: i64) -> String {
    let res_tag = (step_deg * 100.0).round() as i32;
    let la = (lat / step_deg).round() as i32;
    let lo = (lon / step_deg).round() as i32;
    format!("ATM_FL_LMB{}_R{}_L{}_O{}_T{}", level_mb, res_tag, la, lo, valid_time)
}

fn sanitize_f64(v: f64) -> Option<f64> {
    if !v.is_finite() {
        return None;
    }
    // NOAA fields sometimes encode missing with huge sentinels.
    if v.abs() > 1.0e10 {
        return None;
    }
    Some(v)
}

async fn run_cycle(cfg: &Config, arango: &Arango, http: &reqwest::Client) -> Result<()> {
    let base = dataset_base(cfg);
    let dataset = select_existing_dataset(http, &base).await?;
    let valid_time = dataset_valid_time_unix(&dataset)?;
    let forecast_time = Utc::now().timestamp();

    let levs = fetch_lev_mb(http, &dataset).await?;
    let (lat_vec, lon_vec, step_deg) = grid_lat_lon(cfg.stride);
    let (lat_n, lon_n) = lon_lat_counts_for_stride(cfg.stride);

    let mut wrote = 0usize;
    let mut missing_levels = Vec::new();

    // Fetch all requested levels first so we can compute adjacent-level turbulence deterministically per (lat,lon).
    let mut levels_mb = cfg.levels_mb.clone();
    levels_mb.sort_unstable();
    let mut fields_by_level: HashMap<i64, HashMap<String, Vec<f64>>> = HashMap::new();

    for &target_mb in &levels_mb {
        let Some(lev_idx) = levs.iter().position(|&x| x == target_mb) else {
            missing_levels.push(target_mb);
            continue;
        };

        let fields = fetch_level_fields(http, &dataset, &cfg.variables, cfg.stride, lev_idx).await?;
        for (k, v) in &fields {
            if v.len() != lat_n * lon_n {
                return Err(anyhow!(
                    "field size mismatch for level {}mb var={} got={} expected={}",
                    target_mb,
                    k,
                    v.len(),
                    lat_n * lon_n
                ));
            }
        }
        fields_by_level.insert(target_mb, fields);
    }

    for (level_idx, &target_mb) in levels_mb.iter().enumerate() {
        let Some(fields) = fields_by_level.get(&target_mb) else { continue };
        let pressure_pa = (target_mb as f64) * 100.0;

        let tmp = &fields["tmpprs"];
        let hgt = &fields["hgtprs"];
        let u = &fields["ugrdprs"];
        let v = &fields["vgrdprs"];
        let vvel = &fields["vvelprs"];
        let absv = &fields["absvprs"];

        let upper_mb = if level_idx > 0 { Some(levels_mb[level_idx - 1]) } else { None };
        let upper_fields = upper_mb.and_then(|mb| fields_by_level.get(&mb));

        for i in 0..lat_n {
            for j in 0..lon_n {
                let idx = i * lon_n + j;
                let lat = lat_vec[i];
                let lon = lon_vec[j];

                let temp_k = match sanitize_f64(tmp[idx]) {
                    Some(t) if t > 0.0 => t,
                    _ => continue,
                };
                let altitude_m = match sanitize_f64(hgt[idx]) {
                    Some(z) => z,
                    None => continue,
                };
                let altitude_ft = altitude_m * 3.28084;
                let air_density = pressure_pa / (R_DRY_AIR * temp_k);

                let turbulence = upper_fields.and_then(|uf| {
                    let upper_tmp = sanitize_f64(uf["tmpprs"][idx]).filter(|t| *t > 0.0);
                    let upper_hgt = sanitize_f64(uf["hgtprs"][idx]);
                    let upper_u = sanitize_f64(uf["ugrdprs"][idx]);
                    let upper_v = sanitize_f64(uf["vgrdprs"][idx]);

                    match (upper_tmp, upper_hgt, upper_u, upper_v) {
                        (Some(ut), Some(uz), Some(uu), Some(uv)) => {
                            let upper_tile = turbulence::AtmosphereTileLite {
                                altitude_m: uz,
                                temperature_k: ut,
                                wind_u_m_s: uu,
                                wind_v_m_s: uv,
                            };
                            let lower_tile = turbulence::AtmosphereTileLite {
                                altitude_m,
                                temperature_k: temp_k,
                                wind_u_m_s: u[idx],
                                wind_v_m_s: v[idx],
                            };
                            Some(turbulence::calculate_turbulence_indicators(&upper_tile, &lower_tile))
                        }
                        _ => None,
                    }
                });

                let doc = json!({
                    "_key": make_key(target_mb, step_deg, lat, lon, valid_time),
                    "location": { "type": "Point", "coordinates": [lon, lat] }, // lon in [0,360)
                    "altitude_m": altitude_m,
                    "altitude_ft": altitude_ft,
                    "pressure_level_mb": target_mb,
                    "forecast_time": forecast_time,
                    "valid_time": valid_time,
                    "resolution_level": 4,
                    "resolution_deg": step_deg,
                    "state": {
                        "wind_u": sanitize_f64(u[idx]),
                        "wind_v": sanitize_f64(v[idx]),
                        "temperature_k": temp_k,
                        "pressure_pa": pressure_pa,
                        "air_density_kg_m3": air_density,
                        "vertical_velocity_pa_s": sanitize_f64(vvel[idx]),
                        "absolute_vorticity_1_s": sanitize_f64(absv[idx]),
                        "turbulence": turbulence
                    },
                    "uncertainty": { "confidence": 0.7 },
                    "provenance": {
                        "source": "noaa_nomads_gfs_0p25_flightlevel_opendap",
                        "dataset": dataset,
                        "ingest_timestamp": Utc::now().timestamp(),
                        "is_prediction": false
                    },
                    "observations": []
                });

                arango.upsert_document(&cfg.tiles_collection, &doc).await?;
                wrote += 1;
            }
        }
    }

    if !missing_levels.is_empty() {
        warn!("missing requested pressure levels mb={:?} available={:?}", missing_levels, levs);
    }

    info!(
        "flightlevel ingest cycle: dataset={} valid_time={} stride={} wrote_tiles={}",
        dataset, valid_time, cfg.stride, wrote
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

    info!(
        "Starting atmosphere_noaa_gfs_flightlevel_ingest stride={} levels_mb={:?} variables={:?}",
        cfg.stride, cfg.levels_mb, cfg.variables
    );

    let mut interval = tokio::time::interval(Duration::from_secs(cfg.poll_interval_secs));
    loop {
        interval.tick().await;
        if let Err(e) = run_cycle(&cfg, &arango, &http).await {
            return Err(e);
        }
    }
}


