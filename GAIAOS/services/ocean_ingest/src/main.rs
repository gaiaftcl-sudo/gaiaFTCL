//! Ocean Ingest (NOAA NDBC buoys + optional CMEMS Motu; evidence-only)
//!
//! Fetches:
//! - Latest station coordinates: `https://www.ndbc.noaa.gov/data/latest_obs/{STATION}.txt`
//! - Latest numeric observation row: `https://www.ndbc.noaa.gov/data/realtime2/{STATION}.txt`
//! - (Optional) CMEMS daily physics subset via Motu endpoint (requires credentials)
//!
//! Writes (ArangoDB, authenticated):
//! - `observers` docs (type="ocean_buoy")
//! - `observations` docs (observer_type="ocean_buoy")
//!
//! FoT: no synthesis. If metadata or observation parsing fails, we skip the station.

use anyhow::{anyhow, Context, Result};
use chrono::{TimeZone, Utc};
use log::{info, warn};
use serde_json::json;
use std::{collections::HashMap, env, time::Duration};
use std::sync::Arc;

mod routing;

#[derive(Clone)]
struct Config {
    arango_url: String,
    arango_db: String,
    arango_user: String,
    arango_password: String,
    stations: Vec<String>,
    max_stations: usize,
    ndbc_base: String,
    poll_interval_secs: u64,
    tile_step_deg: f64,
    tile_time_bucket_secs: i64,

    // CMEMS (Copernicus Marine) via Motu (optional)
    cmems_enabled: bool,
    cmems_username: Option<String>,
    cmems_password: Option<String>,
    cmems_password_file: Option<String>,
    cmems_motu_url: String,
    cmems_service_id: String,
    cmems_product_id: String,
    cmems_lon_min: f64,
    cmems_lon_max: f64,
    cmems_lat_min: f64,
    cmems_lat_max: f64,
    cmems_depth_min_m: f64,
    cmems_depth_max_m: f64,
    cmems_max_rows: usize,
}

impl Config {
    fn from_env() -> Self {
        let stations_raw = env::var("NDBC_STATIONS")
            .unwrap_or_else(|_| "44013,44017,44025,41001,41002,46006,46011,46022,46026,46050,42001,42002,42003".to_string())
            .trim()
            .to_string();

        let stations = if stations_raw.eq_ignore_ascii_case("AUTO") || stations_raw.is_empty() {
            vec!["AUTO".to_string()]
        } else {
            stations_raw
                .split(',')
                .map(|s| s.trim().to_string())
                .filter(|s| !s.is_empty())
                .collect::<Vec<_>>()
        };
        Self {
            arango_url: env::var("ARANGO_URL").unwrap_or_else(|_| "http://localhost:8529".to_string()),
            arango_db: env::var("ARANGO_DB").unwrap_or_else(|_| "gaiaos".to_string()),
            arango_user: env::var("ARANGO_USER").unwrap_or_else(|_| "root".to_string()),
            arango_password: env::var("ARANGO_PASSWORD").unwrap_or_else(|_| "gaiaos".to_string()),
            stations,
            max_stations: env::var("NDBC_MAX_STATIONS").ok().and_then(|v| v.parse().ok()).unwrap_or(200),
            ndbc_base: env::var("NDBC_BASE_URL").unwrap_or_else(|_| "https://www.ndbc.noaa.gov".to_string()),
            poll_interval_secs: env::var("POLL_INTERVAL_SECS").ok().and_then(|v| v.parse().ok()).unwrap_or(10800),
            tile_step_deg: env::var("TILE_STEP_DEG").ok().and_then(|v| v.parse().ok()).unwrap_or(0.25),
            tile_time_bucket_secs: env::var("TILE_TIME_BUCKET_SECS").ok().and_then(|v| v.parse().ok()).unwrap_or(900),

            cmems_enabled: env::var("CMEMS_ENABLED")
                .ok()
                .map(|v| v == "1" || v.eq_ignore_ascii_case("true"))
                .unwrap_or(false),
            cmems_username: env::var("CMEMS_USERNAME").ok().filter(|s| !s.trim().is_empty()),
            cmems_password: env::var("CMEMS_PASSWORD").ok().filter(|s| !s.trim().is_empty()),
            cmems_password_file: env::var("CMEMS_PASSWORD_FILE").ok().filter(|s| !s.trim().is_empty()),
            cmems_motu_url: env::var("CMEMS_MOTU_URL")
                .unwrap_or_else(|_| "https://nrt.cmems-du.eu/motu-web/Motu".to_string()),
            cmems_service_id: env::var("CMEMS_SERVICE_ID")
                .unwrap_or_else(|_| "GLOBAL_ANALYSISFORECAST_PHY_001_024-TDS".to_string()),
            cmems_product_id: env::var("CMEMS_PRODUCT_ID")
                .unwrap_or_else(|_| "cmems_mod_glo_phy_anfc_0.083deg_P1D-m".to_string()),
            cmems_lon_min: env::var("CMEMS_LON_MIN").ok().and_then(|v| v.parse().ok()).unwrap_or(-75.0),
            cmems_lon_max: env::var("CMEMS_LON_MAX").ok().and_then(|v| v.parse().ok()).unwrap_or(-65.0),
            cmems_lat_min: env::var("CMEMS_LAT_MIN").ok().and_then(|v| v.parse().ok()).unwrap_or(35.0),
            cmems_lat_max: env::var("CMEMS_LAT_MAX").ok().and_then(|v| v.parse().ok()).unwrap_or(45.0),
            cmems_depth_min_m: env::var("CMEMS_DEPTH_MIN_M").ok().and_then(|v| v.parse().ok()).unwrap_or(0.0),
            cmems_depth_max_m: env::var("CMEMS_DEPTH_MAX_M").ok().and_then(|v| v.parse().ok()).unwrap_or(0.0),
            cmems_max_rows: env::var("CMEMS_MAX_ROWS").ok().and_then(|v| v.parse().ok()).unwrap_or(5000),
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
            .user_agent("GaiaOS-Ocean-Ingest/0.1.0")
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

    async fn aql_raw(&self, aql: &str, bind_vars: serde_json::Value) -> Result<serde_json::Value> {
        let url = format!("{}/_db/{}/_api/cursor", self.base_url, self.db_name);
        let resp = self
            .http
            .post(url)
            .header("Authorization", &self.auth_header)
            .header("Content-Type", "application/json")
            .json(&serde_json::json!({
                "query": aql,
                "bindVars": bind_vars,
                "batchSize": 1000
            }))
            .send()
            .await
            .context("arango aql request failed")?;

        if !resp.status().is_success() {
            let status = resp.status();
            let text = resp.text().await.unwrap_or_default();
            return Err(anyhow!("Arango AQL failed {status}: {text}"));
        }
        let v: serde_json::Value = resp.json().await.context("arango aql json decode failed")?;
        Ok(v["result"].clone())
    }
}

#[derive(Debug, Clone)]
struct BuoyObs {
    timestamp: i64,
    fields: HashMap<String, f64>,
    raw_line: String,
}

fn time_bucket(ts_unix: i64, bucket_secs: i64) -> i64 {
    (ts_unix / bucket_secs) * bucket_secs
}

fn quantize_deg(v: f64, step: f64) -> f64 {
    (v / step).round() * step
}

fn ocean_tile_key(lat: f64, lon: f64, depth_m: i32, valid_time: i64, step_deg: f64) -> String {
    let latq = quantize_deg(lat, step_deg);
    let lonq = quantize_deg(lon, step_deg);
    let lat_q100 = (latq * 100.0).round() as i32;
    let lon_q100 = (lonq * 100.0).round() as i32;
    format!("OCN_L{lat_q100}_O{lon_q100}_Z{depth_m}_T{valid_time}")
}

fn parse_float_token(tok: &str) -> Option<f64> {
    let t = tok.trim();
    if t.is_empty() || t.eq_ignore_ascii_case("MM") {
        return None;
    }
    t.parse::<f64>().ok()
}

fn parse_dms_coord(s: &str) -> Option<f64> {
    // Example: "42° 20.7' N" or "70° 39.1' W"
    let cleaned = s
        .replace('°', " ")
        .replace('\'', " ")
        .replace('’', " ")
        .replace('"', " ")
        .replace('\u{00b0}', " "); // degree symbol variants
    let parts: Vec<&str> = cleaned.split_whitespace().collect();
    if parts.len() < 3 {
        return None;
    }
    let deg: f64 = parts[0].parse().ok()?;
    let min: f64 = parts[1].parse().ok()?;
    let hemi = parts[2];
    let mut val = deg + (min / 60.0);
    if hemi.eq_ignore_ascii_case("S") || hemi.eq_ignore_ascii_case("W") {
        val = -val;
    }
    Some(val)
}

fn parse_coords_from_latest_obs(text: &str) -> Option<(f64, f64)> {
    // latest_obs format includes:
    // Station 44013
    // 42° 20.7' N  70° 39.1' W
    for line in text.lines().map(|l| l.trim()).filter(|l| !l.is_empty()) {
        if line.contains('N') && line.contains('W') && line.contains('\'') {
            // split into two halves by double-space or by trailing N token
            // simplest: parse left part up to 'N', and right part after that.
            if let Some((left, right)) = line.split_once('N') {
                let lat_part = format!("{left}N").trim().to_string();
                let lon_part = right.trim().to_string();
                let lat = parse_dms_coord(&lat_part)?;
                // lon_part starts with something like "70° 39.1' W"
                let lon = parse_dms_coord(&lon_part)?;
                return Some((lat, lon));
            }
        }
    }
    None
}

fn parse_realtime2_latest_row(text: &str) -> Option<BuoyObs> {
    // realtime2 format:
    // #YY  MM DD hh mm WDIR WSPD GST  WVHT   DPD   APD MWD   PRES  ATMP  WTMP  DEWP ...
    // #yr  mo dy hr mn ...
    // 2025 12 26 16 20 360  6.0 10.0   1.9     7   5.7  51 1022.5  -7.6   7.1 -13.1 ...
    let mut header_cols: Vec<String> = Vec::new();
    let mut data_line: Option<String> = None;

    for line in text.lines() {
        let l = line.trim();
        if l.is_empty() {
            continue;
        }
        if l.starts_with("#YY") {
            header_cols = l.trim_start_matches('#')
                .split_whitespace()
                .map(|s| s.to_string())
                .collect();
            continue;
        }
        if l.starts_with('#') {
            continue;
        }
        if !header_cols.is_empty() {
            data_line = Some(l.to_string());
            break;
        }
    }

    let header_cols = if header_cols.is_empty() { return None } else { header_cols };
    let data_line = data_line?;
    let tokens: Vec<&str> = data_line.split_whitespace().collect();
    if tokens.len() < header_cols.len().min(5) {
        return None;
    }

    let mut idx_map: HashMap<String, usize> = HashMap::new();
    for (i, c) in header_cols.iter().enumerate() {
        idx_map.insert(c.to_string(), i);
    }

    let year = if let Some(i) = idx_map.get("YY") {
        // realtime2 uses 4-digit year in YY column (historical)
        tokens.get(*i)?.parse::<i32>().ok()?
    } else {
        return None;
    };
    let m = tokens.get(*idx_map.get("MM")?)?.parse::<u32>().ok()?;
    let d = tokens.get(*idx_map.get("DD")?)?.parse::<u32>().ok()?;
    let h = tokens.get(*idx_map.get("hh")?)?.parse::<u32>().ok()?;
    let min = tokens.get(*idx_map.get("mm")?)?.parse::<u32>().ok()?;
    let ts = Utc.with_ymd_and_hms(year, m, d, h, min, 0).single()?.timestamp();

    let mut fields = HashMap::new();
    for col in ["WDIR", "WSPD", "GST", "WVHT", "DPD", "APD", "MWD", "PRES", "ATMP", "WTMP"] {
        if let Some(i) = idx_map.get(col) {
            if let Some(tok) = tokens.get(*i) {
                if let Some(v) = parse_float_token(tok) {
                    fields.insert(col.to_string(), v);
                }
            }
        }
    }

    Some(BuoyObs {
        timestamp: ts,
        fields,
        raw_line: data_line,
    })
}

#[derive(Debug, Clone)]
struct StationInfo {
    id: String,
    lat: f64,
    lon: f64,
    name: Option<String>,
}

fn attr_value(line: &str, key: &str) -> Option<String> {
    // naive XML attribute parse: key="value"
    let needle = format!(r#"{key}=""#);
    let start = line.find(&needle)? + needle.len();
    let rest = &line[start..];
    let end = rest.find('"')?;
    Some(rest[..end].to_string())
}

fn parse_active_stations_xml(xml: &str, max: usize) -> Vec<StationInfo> {
    let mut out = Vec::new();
    for line in xml.lines() {
        let l = line.trim();
        if !l.starts_with("<station ") {
            continue;
        }
        let Some(id) = attr_value(l, "id") else { continue };
        let Some(lat_s) = attr_value(l, "lat") else { continue };
        let Some(lon_s) = attr_value(l, "lon") else { continue };
        let lat = match lat_s.parse::<f64>() {
            Ok(v) => v,
            Err(_) => continue,
        };
        let lon = match lon_s.parse::<f64>() {
            Ok(v) => v,
            Err(_) => continue,
        };
        let name = attr_value(l, "name");
        out.push(StationInfo { id, lat, lon, name });
        if out.len() >= max {
            break;
        }
    }
    out
}

async fn fetch_text(client: &reqwest::Client, url: &str) -> Result<String> {
    let resp = client.get(url).send().await.context("http request failed")?;
    if !resp.status().is_success() {
        return Err(anyhow!("http {}: {}", resp.status(), url));
    }
    resp.text().await.context("decode text failed")
}

#[derive(Debug, Clone)]
struct CmemsRow {
    timestamp: i64,
    lat: f64,
    lon: f64,
    depth_m: f64,
    uo: Option<f64>,
    vo: Option<f64>,
    thetao_c: Option<f64>,
    so: Option<f64>,
}

fn parse_time_any(s: &str) -> Option<i64> {
    let t = s.trim();
    if t.is_empty() {
        return None;
    }
    if let Ok(dt) = chrono::DateTime::parse_from_rfc3339(t) {
        return Some(dt.with_timezone(&Utc).timestamp());
    }
    if let Ok(dt) = chrono::DateTime::parse_from_str(t, "%Y-%m-%dT%H:%M:%SZ") {
        return Some(dt.with_timezone(&Utc).timestamp());
    }
    if let Ok(naive) = chrono::NaiveDateTime::parse_from_str(t, "%Y-%m-%d %H:%M:%S") {
        return Some(Utc.from_utc_datetime(&naive).timestamp());
    }
    None
}

fn split_csv_line(line: &str, delim: char) -> Vec<String> {
    // Minimal CSV splitter (no quoted fields expected for CMEMS numeric outputs).
    line.split(delim).map(|s| s.trim().trim_matches('"').to_string()).collect()
}

fn find_delim(header: &str) -> char {
    if header.contains(';') && !header.contains(',') {
        return ';';
    }
    ','
}

fn parse_cmems_csv(text: &str, max_rows: usize) -> Result<Vec<CmemsRow>> {
    // Best-effort parser for Motu CSV-like outputs. Fail-closed on missing essential columns.
    let mut lines = text.lines().map(|l| l.trim()).filter(|l| !l.is_empty());

    // Find header line (must contain lon/lat and time).
    let mut header_line: Option<String> = None;
    for _ in 0..200 {
        if let Some(l) = lines.next() {
            // Skip HTML or error pages
            if l.to_ascii_lowercase().contains("<html") {
                return Err(anyhow!("cmems motu returned html (unexpected)"));
            }
            if l.to_ascii_lowercase().contains("error") && l.to_ascii_lowercase().contains("motu") {
                return Err(anyhow!("cmems motu returned error: {l}"));
            }
            let ll = l.to_ascii_lowercase();
            if (ll.contains("longitude") || ll.contains("lon")) && (ll.contains("latitude") || ll.contains("lat")) && ll.contains("time") {
                header_line = Some(l.to_string());
                break;
            }
        } else {
            break;
        }
    }

    let header_line = header_line.ok_or_else(|| anyhow!("cmems csv header not found"))?;
    let delim = find_delim(&header_line);
    let header_cols = split_csv_line(&header_line, delim);
    let mut idx = HashMap::<String, usize>::new();
    for (i, c) in header_cols.iter().enumerate() {
        idx.insert(c.to_ascii_lowercase(), i);
    }

    let get_i = |names: &[&str]| -> Option<usize> {
        for n in names {
            if let Some(i) = idx.get(&n.to_string()) {
                return Some(*i);
            }
        }
        None
    };

    let i_time = get_i(&["time", "date"] ).ok_or_else(|| anyhow!("cmems csv missing time column"))?;
    let i_lat = get_i(&["latitude", "lat"]).ok_or_else(|| anyhow!("cmems csv missing latitude column"))?;
    let i_lon = get_i(&["longitude", "lon"]).ok_or_else(|| anyhow!("cmems csv missing longitude column"))?;
    let i_depth = get_i(&["depth", "depth_m", "depth (m)"]).unwrap_or(usize::MAX);
    let i_uo = get_i(&["uo", "u"]).unwrap_or(usize::MAX);
    let i_vo = get_i(&["vo", "v"]).unwrap_or(usize::MAX);
    let i_thetao = get_i(&["thetao", "temperature", "temp"]).unwrap_or(usize::MAX);
    let i_so = get_i(&["so", "salinity"]).unwrap_or(usize::MAX);

    let mut out: Vec<CmemsRow> = Vec::new();
    for line in lines {
        if out.len() >= max_rows {
            break;
        }
        if line.starts_with('#') {
            continue;
        }
        let cols = split_csv_line(line, delim);
        if cols.len() <= i_lon.max(i_lat).max(i_time) {
            continue;
        }
        let Some(ts) = parse_time_any(&cols[i_time]) else { continue };
        let lat = cols[i_lat].parse::<f64>().ok();
        let lon = cols[i_lon].parse::<f64>().ok();
        let (Some(lat), Some(lon)) = (lat, lon) else { continue };
        let depth_m = if i_depth != usize::MAX && i_depth < cols.len() {
            cols[i_depth].parse::<f64>().unwrap_or(0.0)
        } else {
            0.0
        };
        let uo = if i_uo != usize::MAX && i_uo < cols.len() { cols[i_uo].parse::<f64>().ok() } else { None };
        let vo = if i_vo != usize::MAX && i_vo < cols.len() { cols[i_vo].parse::<f64>().ok() } else { None };
        let thetao_c = if i_thetao != usize::MAX && i_thetao < cols.len() { cols[i_thetao].parse::<f64>().ok() } else { None };
        let so = if i_so != usize::MAX && i_so < cols.len() { cols[i_so].parse::<f64>().ok() } else { None };
        out.push(CmemsRow { timestamp: ts, lat, lon, depth_m, uo, vo, thetao_c, so });
    }
    Ok(out)
}

async fn ingest_cmems(arango: &Arango, http: &reqwest::Client, cfg: &Config) -> Result<(usize, usize)> {
    let user = cfg
        .cmems_username
        .clone()
        .ok_or_else(|| anyhow!("cmems enabled but CMEMS_USERNAME not set"))?;
    let pwd = match (&cfg.cmems_password_file, &cfg.cmems_password) {
        (Some(path), _) => std::fs::read_to_string(path)
            .with_context(|| format!("failed to read CMEMS_PASSWORD_FILE at {path}"))?
            .trim()
            .to_string(),
        (None, Some(p)) => p.trim().to_string(),
        (None, None) => return Err(anyhow!("cmems enabled but CMEMS_PASSWORD/CMEMS_PASSWORD_FILE not set")),
    };
    if pwd.is_empty() {
        return Err(anyhow!("cmems enabled but CMEMS password resolved empty"));
    }

    // Motu request: 1-day window ending "now" (UTC).
    let now = Utc::now();
    let date_max = now.format("%Y-%m-%d %H:%M:%S").to_string();
    let date_min = (now - chrono::Duration::hours(24)).format("%Y-%m-%d %H:%M:%S").to_string();

    // Best-effort Motu parameter set; fail-closed if response is not parseable.
    let form: Vec<(String, String)> = vec![
        ("service-id".into(), cfg.cmems_service_id.clone()),
        ("product-id".into(), cfg.cmems_product_id.clone()),
        ("longitude-min".into(), cfg.cmems_lon_min.to_string()),
        ("longitude-max".into(), cfg.cmems_lon_max.to_string()),
        ("latitude-min".into(), cfg.cmems_lat_min.to_string()),
        ("latitude-max".into(), cfg.cmems_lat_max.to_string()),
        ("date-min".into(), date_min),
        ("date-max".into(), date_max),
        ("depth-min".into(), cfg.cmems_depth_min_m.to_string()),
        ("depth-max".into(), cfg.cmems_depth_max_m.to_string()),
        ("variable".into(), "uo".into()),
        ("variable".into(), "vo".into()),
        ("variable".into(), "thetao".into()),
        ("variable".into(), "so".into()),
        // Output as CSV if supported; otherwise parser will fail closed.
        ("output-format".into(), "csv".into()),
        ("user".into(), user),
        ("pwd".into(), pwd),
    ];

    let resp = http
        .post(cfg.cmems_motu_url.clone())
        .form(&form)
        .send()
        .await
        .context("cmems motu request failed")?;

    if !resp.status().is_success() {
        let status = resp.status();
        let text = resp.text().await.unwrap_or_default();
        return Err(anyhow!("cmems motu http {status}: {text}"));
    }

    let text = resp.text().await.context("cmems motu decode failed")?;
    let rows = parse_cmems_csv(&text, cfg.cmems_max_rows)?;

    // Observer doc
    let observer_key = "cmems_global_phy".to_string();
    let observer_id = format!("cmems:{}:{}", cfg.cmems_service_id, cfg.cmems_product_id);
    let observer_doc = json!({
        "_key": observer_key,
        "type": "ocean_model",
        "observer_id": observer_id,
        "name": "Copernicus Marine (CMEMS) Motu subset",
        "operational": true,
        "provenance": {
            "source": "cmems_motu",
            "motu_url": cfg.cmems_motu_url,
            "service_id": cfg.cmems_service_id,
            "product_id": cfg.cmems_product_id,
            "bbox": { "lon_min": cfg.cmems_lon_min, "lon_max": cfg.cmems_lon_max, "lat_min": cfg.cmems_lat_min, "lat_max": cfg.cmems_lat_max },
            "depth_min_m": cfg.cmems_depth_min_m,
            "depth_max_m": cfg.cmems_depth_max_m,
            "ingested_at": Utc::now().to_rfc3339()
        }
    });
    arango.upsert_document("observers", &observer_doc).await?;

    let mut written = 0usize;
    for (i, r) in rows.iter().enumerate() {
        // Evidence gate: require at least current or temperature.
        if r.uo.is_none() && r.vo.is_none() && r.thetao_c.is_none() && r.so.is_none() {
            continue;
        }
        let valid_time = time_bucket(r.timestamp, cfg.tile_time_bucket_secs);
        let depth_i32 = r.depth_m.round() as i32;
        let validates_tile = ocean_tile_key(r.lat, r.lon, depth_i32, valid_time, cfg.tile_step_deg);
        let key = format!("CMEMS_{}_{}", r.timestamp, i);

        let doc = json!({
            "_key": key,
            "observer_id": observer_id,
            "observer_type": "ocean_cmems",
            "timestamp": r.timestamp,
            "ingest_timestamp": Utc::now().timestamp(),
            "timestamp_rfc3339": Utc.timestamp_opt(r.timestamp, 0).single().map(|t| t.to_rfc3339()),
            "location": { "type": "Point", "coordinates": [r.lon, r.lat] },
            "altitude_ft": 0,
            "measurement": {
                "current_u": r.uo,
                "current_v": r.vo,
                "temperature_k": r.thetao_c.map(|c| c + 273.15),
                "salinity_psu": r.so,
                "depth_m": r.depth_m
            },
            "quality": {
                "confidence": 0.9,
                "source": "cmems_motu"
            },
            "validates_tile": validates_tile,
            "provenance": {
                "source": "cmems_motu",
                "service_id": cfg.cmems_service_id,
                "product_id": cfg.cmems_product_id,
                "ingested_at": Utc::now().to_rfc3339()
            }
        });

        arango.upsert_document("observations", &doc).await?;
        written += 1;
    }

    Ok((1, written))
}

async fn ingest_station_with_coords(
    arango: &Arango,
    http: &reqwest::Client,
    cfg: &Config,
    station: &str,
    lat: f64,
    lon: f64,
    name: Option<String>,
) -> Result<(usize, usize)> {
    let realtime_url = format!("{}/data/realtime2/{}.txt", cfg.ndbc_base.trim_end_matches('/'), station);
    let realtime_text = fetch_text(http, &realtime_url).await?;
    let obs = parse_realtime2_latest_row(&realtime_text).ok_or_else(|| anyhow!("failed to parse realtime2 latest row"))?;

    // Observer doc
    let observer_key = format!("ndbc_{}", station);
    let observer_id = format!("ndbc:{}", station);
    let observer_doc = json!({
        "_key": observer_key,
        "type": "ocean_buoy",
        "station_id": station,
        "location": { "type": "Point", "coordinates": [lon, lat] },
        "name": name.unwrap_or_else(|| format!("NOAA NDBC station {station}")),
        "operational": true,
        "provenance": {
            "source": "noaa_ndbc",
            "station_id": station,
            "realtime_url": realtime_url,
            "ingested_at": Utc::now().to_rfc3339()
        }
    });
    arango.upsert_document("observers", &observer_doc).await?;

    // Observation doc
    let valid_time = time_bucket(obs.timestamp, cfg.tile_time_bucket_secs);
    let depth_m: i32 = 0;
    let validates_tile = ocean_tile_key(lat, lon, depth_m, valid_time, cfg.tile_step_deg);
    let key = format!("NDBC_{}_{}", station, obs.timestamp);

    let wave_height_m = obs.fields.get("WVHT").copied();
    let wave_period_s = obs.fields.get("DPD").copied().or_else(|| obs.fields.get("APD").copied());
    let wave_direction_deg = obs.fields.get("MWD").copied();
    let wind_speed_ms = obs.fields.get("WSPD").copied();
    let wind_dir_deg = obs.fields.get("WDIR").copied();
    let water_temperature_c = obs.fields.get("WTMP").copied();
    let air_temperature_c = obs.fields.get("ATMP").copied();
    let pressure_hpa = obs.fields.get("PRES").copied();

    // Evidence gate: require at least one ocean measurement.
    if wave_height_m.is_none() && water_temperature_c.is_none() {
        return Err(anyhow!("no ocean measurements present (WVHT/WTMP missing)"));
    }

    let doc = json!({
        "_key": key,
        "observer_id": observer_id,
        "observer_type": "ocean_buoy",
        "timestamp": obs.timestamp,
        "ingest_timestamp": Utc::now().timestamp(),
        "timestamp_rfc3339": Utc.timestamp_opt(obs.timestamp, 0).single().map(|t| t.to_rfc3339()),
        "location": { "type": "Point", "coordinates": [lon, lat] },
        "altitude_ft": 0,
        "measurement": {
            "wave_height_m": wave_height_m,
            "wave_period_s": wave_period_s,
            "wave_direction_deg": wave_direction_deg,
            "wind_speed_ms": wind_speed_ms,
            "wind_dir_deg": wind_dir_deg,
            "water_temperature_c": water_temperature_c,
            "air_temperature_c": air_temperature_c,
            "pressure_hpa": pressure_hpa,
            "depth_m": depth_m
        },
        "quality": {
            "confidence": 0.95,
            "source": "noaa_ndbc"
        },
        "validates_tile": validates_tile,
        "provenance": {
            "source": "noaa_ndbc",
            "station_id": station,
            "realtime_url": realtime_url,
            "raw_line": obs.raw_line,
            "ingested_at": Utc::now().to_rfc3339()
        }
    });
    arango.upsert_document("observations", &doc).await?;

    Ok((1, 1))
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
        .user_agent("GaiaOS-Ocean-Ingest/0.1.0")
        .build()
        .context("failed to build http client")?;

    let routing_host = env::var("ROUTING_HOST").unwrap_or_else(|_| "0.0.0.0".to_string());
    let routing_port: u16 = env::var("ROUTING_PORT").ok().and_then(|v| v.parse().ok()).unwrap_or(8703);

    let app_state = Arc::new(routing::AppState { arango: arango.clone() });
    let app = axum::Router::new()
        .route("/health", axum::routing::get(routing::health))
        .merge(routing::routing_routes(app_state.clone()));

    info!("Starting ocean_ingest ingest loop + routing API on {}:{}", routing_host, routing_port);

    // Ingest loop in background
    let ingest_cfg = cfg.clone();
    let ingest_arango = arango.clone();
    let ingest_http = http.clone();
    tokio::spawn(async move {
        let mut interval = tokio::time::interval(Duration::from_secs(ingest_cfg.poll_interval_secs));
        loop {
            interval.tick().await;

            // Load active stations map (provides id->lat/lon/name) for robust ingest without station metadata endpoints.
            let active_url = format!("{}/activestations.xml", ingest_cfg.ndbc_base.trim_end_matches('/'));
            let active_xml = fetch_text(&ingest_http, &active_url).await.unwrap_or_default();
            let active_list = parse_active_stations_xml(&active_xml, ingest_cfg.max_stations);
            let mut active_map: HashMap<String, StationInfo> = HashMap::new();
            for s in active_list {
                active_map.insert(s.id.clone(), s);
            }

            let mut obs_written = 0usize;
            let mut observers_written = 0usize;
            let mut failures = 0usize;

            let stations_to_run: Vec<String> =
                if ingest_cfg.stations.len() == 1 && ingest_cfg.stations[0] == "AUTO" {
                    active_map.keys().cloned().take(ingest_cfg.max_stations).collect()
                } else {
                    ingest_cfg.stations.clone()
                };

            for st in &stations_to_run {
                // Prefer activestations.xml coords; fallback to latest_obs parsing.
                let (lat, lon, name) = if let Some(info) = active_map.get(st) {
                    (info.lat, info.lon, info.name.clone())
                } else {
                    let latest_obs_url = format!(
                        "{}/data/latest_obs/{}.txt",
                        ingest_cfg.ndbc_base.trim_end_matches('/'),
                        st
                    );
                    match fetch_text(&ingest_http, &latest_obs_url).await {
                        Ok(txt) => match parse_coords_from_latest_obs(&txt) {
                            Some((lat, lon)) => (lat, lon, Some(format!("NOAA NDBC station {st}"))),
                            None => {
                                failures += 1;
                                warn!("skip station {st}: failed to parse coords from latest_obs");
                                continue;
                            }
                        },
                        Err(_) => {
                            failures += 1;
                            warn!("skip station {st}: station not found in activestations and latest_obs unavailable");
                            continue;
                        }
                    }
                };

                match ingest_station_with_coords(&ingest_arango, &ingest_http, &ingest_cfg, st, lat, lon, name).await {
                    Ok((o1, o2)) => {
                        observers_written += o1;
                        obs_written += o2;
                    }
                    Err(e) => {
                        failures += 1;
                        warn!("skip station {st}: {e:#}");
                    }
                }
            }

            info!(
                "ocean_ingest cycle: observers_upserted={} observations_upserted={} failures={}",
                observers_written, obs_written, failures
            );

            if ingest_cfg.cmems_enabled {
                match ingest_cmems(&ingest_arango, &ingest_http, &ingest_cfg).await {
                    Ok((_o, n)) => info!("cmems cycle: observations_upserted={}", n),
                    Err(e) => warn!("cmems cycle failed: {e:#}"),
                }
            }
        }
    });

    let listener = tokio::net::TcpListener::bind(format!("{routing_host}:{routing_port}"))
        .await
        .context("failed to bind routing listener")?;
    axum::serve(listener, app).await.context("routing server error")?;

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


