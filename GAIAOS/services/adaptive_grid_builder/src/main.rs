//! Adaptive Resolution Grid Builder
//!
//! Generates a planet-wide adaptive grid with three tiers and stores it in ArangoDB:
//! - low: 10° global (baseline, full planet)
//! - medium: 1° band (-60..75 lat) (regional coverage)
//! - high: 0.25° around real airports (evidence-based refinement)
//!
//! FoT: this is grid metadata only (no synthetic measurements).

use anyhow::{anyhow, Context, Result};
use airport_registry::AirportRegistry;
use chrono::Utc;
use log::info;
use serde_json::json;
use std::{collections::HashMap, env, time::Duration};

#[derive(Clone)]
struct Config {
    arango_url: String,
    arango_db: String,
    arango_user: String,
    arango_password: String,
    collection: String,

    airports_csv_path: String,
    poll_interval_secs: u64,

    high_res_deg: f64,
    high_res_radius_km: f64,
    medium_res_deg: f64,
    low_res_deg: f64,

    medium_lat_min: f64,
    medium_lat_max: f64,
}

impl Config {
    fn from_env() -> Self {
        Self {
            arango_url: env::var("ARANGO_URL").unwrap_or_else(|_| "http://localhost:8529".to_string()),
            arango_db: env::var("ARANGO_DB").unwrap_or_else(|_| "gaiaos".to_string()),
            arango_user: env::var("ARANGO_USER").unwrap_or_else(|_| "root".to_string()),
            arango_password: env::var("ARANGO_PASSWORD").unwrap_or_else(|_| "gaiaos".to_string()),
            collection: env::var("ARANGO_ADAPTIVE_GRID_COLLECTION").unwrap_or_else(|_| "adaptive_grid_tiles".to_string()),

            airports_csv_path: env::var("OURAIRPORTS_CSV").unwrap_or_else(|_| "/app/airports.csv".to_string()),
            poll_interval_secs: env::var("POLL_INTERVAL_SECS").ok().and_then(|v| v.parse().ok()).unwrap_or(86400),

            high_res_deg: env::var("HIGH_RES_DEG").ok().and_then(|v| v.parse().ok()).unwrap_or(0.25),
            high_res_radius_km: env::var("HIGH_RES_RADIUS_KM").ok().and_then(|v| v.parse().ok()).unwrap_or(200.0),
            medium_res_deg: env::var("MEDIUM_RES_DEG").ok().and_then(|v| v.parse().ok()).unwrap_or(1.0),
            low_res_deg: env::var("LOW_RES_DEG").ok().and_then(|v| v.parse().ok()).unwrap_or(10.0),

            medium_lat_min: env::var("MEDIUM_LAT_MIN").ok().and_then(|v| v.parse().ok()).unwrap_or(-60.0),
            medium_lat_max: env::var("MEDIUM_LAT_MAX").ok().and_then(|v| v.parse().ok()).unwrap_or(75.0),
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
            .user_agent("GaiaOS-AdaptiveGridBuilder/0.1.0")
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

    async fn upsert(&self, collection: &str, doc: &serde_json::Value) -> Result<()> {
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

#[derive(Clone, Copy)]
struct Tier {
    name: &'static str,
    resolution_deg: f64,
}

fn quantize_deg(v: f64, step: f64) -> i32 {
    (v / step).round() as i32
}

fn tile_key(tier: &Tier, lat: f64, lon: f64) -> String {
    let la = quantize_deg(lat, tier.resolution_deg);
    let lo = quantize_deg(lon, tier.resolution_deg);
    format!("AGR_{}_L{}_O{}", tier.name, la, lo)
}

fn iter_lon_0_360(step: f64) -> Vec<f64> {
    let mut out = Vec::new();
    let mut lon = 0.0;
    while lon < 360.0 {
        out.push(lon);
        lon += step;
    }
    out
}

fn iter_lat_inclusive(min_lat: f64, max_lat: f64, step: f64) -> Vec<f64> {
    let mut out = Vec::new();
    let mut lat = min_lat;
    while lat <= max_lat + 1e-9 {
        out.push(lat);
        lat += step;
    }
    out
}

fn approx_deg_radius_km(radius_km: f64) -> f64 {
    radius_km / 111.0
}

async fn build_and_write(cfg: &Config, arango: &Arango) -> Result<()> {
    let tier_low = Tier { name: "low", resolution_deg: cfg.low_res_deg };
    let tier_med = Tier { name: "medium", resolution_deg: cfg.medium_res_deg };
    let tier_high = Tier { name: "high", resolution_deg: cfg.high_res_deg };

    // Map of (latq, lonq, base_res) -> (tier, lat, lon)
    // Key is tier-specific quantization, so we keep separate maps per tier and then merge by priority.
    let mut chosen: HashMap<String, (Tier, f64, f64, serde_json::Value)> = HashMap::new();

    // Low-res: global baseline (lat -90..90 inclusive, lon 0..360 step)
    let lats = iter_lat_inclusive(-90.0, 90.0, tier_low.resolution_deg);
    let lons = iter_lon_0_360(tier_low.resolution_deg);
    for &lat in &lats {
        for &lon in &lons {
            let k = format!("LONLAT_{:.3}_{:.3}", lon, lat);
            chosen.insert(
                k,
                (
                    tier_low,
                    lat,
                    lon,
                    json!({"tier_source":"baseline_global"}),
                ),
            );
        }
    }

    // Medium-res: band (-60..75), override low within its coverage.
    let lats = iter_lat_inclusive(cfg.medium_lat_min, cfg.medium_lat_max, tier_med.resolution_deg);
    let lons = iter_lon_0_360(tier_med.resolution_deg);
    for &lat in &lats {
        for &lon in &lons {
            let k = format!("LONLAT_{:.3}_{:.3}", lon, lat);
            chosen.insert(
                k,
                (
                    tier_med,
                    lat,
                    lon,
                    json!({"tier_source":"medium_lat_band"}),
                ),
            );
        }
    }

    // High-res: around airports (evidence-based refinement).
    let reg = AirportRegistry::load_ourairports_airports_csv(std::path::Path::new(&cfg.airports_csv_path))
        .with_context(|| format!("load airports csv {}", cfg.airports_csv_path))?;

    let deg_r = approx_deg_radius_km(cfg.high_res_radius_km);
    let step = tier_high.resolution_deg;

    let mut airport_count = 0usize;
    for a in reg.airports_by_icao.values() {
        // Evidence-based filter: restrict to airports most indicative of human activity.
        // OurAirports fields are authoritative source CSV.
        let t = a.airport_type.trim().to_string();
        if t != "large_airport" && t != "medium_airport" {
            continue;
        }
        let scheduled = a
            .scheduled_service
            .as_deref()
            .unwrap_or("")
            .trim()
            .eq_ignore_ascii_case("yes");
        if !scheduled {
            continue;
        }

        let lat = a.latitude_deg;
        let lon_raw = a.longitude_deg;

        airport_count += 1;
        let lon = if lon_raw < 0.0 { lon_raw + 360.0 } else { lon_raw };
        let lat_min = (lat - deg_r).max(-90.0);
        let lat_max = (lat + deg_r).min(90.0);
        let lon_min = (lon - deg_r).max(0.0);
        let lon_max = (lon + deg_r).min(360.0 - step);

        let mut la = (lat_min / step).floor() * step;
        while la <= lat_max + 1e-9 {
            let mut lo = (lon_min / step).floor() * step;
            while lo <= lon_max + 1e-9 {
                let k = format!("LONLAT_{:.3}_{:.3}", lo, la);
                chosen.insert(
                    k,
                    (
                        tier_high,
                        la,
                        lo,
                        json!({"tier_source":"airport_radius_km","radius_km":cfg.high_res_radius_km}),
                    ),
                );
                lo += step;
            }
            la += step;
        }
    }

    // Write tiles
    let now = Utc::now().timestamp();
    let run_id = format!("run_{}", now);
    let mut written = 0usize;
    let mut by_tier: HashMap<&'static str, usize> = HashMap::new();

    for (_k, (tier, lat, lon, meta)) in chosen {
        let doc = json!({
            "_key": tile_key(&tier, lat, lon),
            "location": { "type": "Point", "coordinates": [lon, lat] }, // lon in [0,360)
            "resolution_deg": tier.resolution_deg,
            "resolution_tier": tier.name,
            "provenance": {
                "source": "adaptive_grid_builder",
                "ingest_timestamp": now,
                "run_id": run_id
            },
            "meta": meta
        });
        arango.upsert(&cfg.collection, &doc).await?;
        written += 1;
        *by_tier.entry(tier.name).or_insert(0) += 1;
    }

    // Cleanup: remove previous adaptive_grid_builder tiles not part of this run_id.
    // This prevents unbounded growth when tier rules change.
    let cleanup_aql = format!(
        r#"
FOR d IN {coll}
  FILTER d.provenance != null
  FILTER d.provenance.source == "adaptive_grid_builder"
  FILTER d.provenance.run_id != @run_id
  REMOVE d IN {coll}
"#,
        coll = cfg.collection
    );
    // Use Arango cursor endpoint for deletion via AQL.
    let url = format!("{}/_db/{}/_api/cursor", arango.base_url, arango.db_name);
    let resp = arango
        .http
        .post(url)
        .header("Authorization", &arango.auth_header)
        .header("Content-Type", "application/json")
        .json(&json!({ "query": cleanup_aql, "bindVars": { "run_id": run_id }, "batchSize": 1000 }))
        .send()
        .await
        .context("cleanup aql request failed")?;
    if !resp.status().is_success() {
        let status = resp.status();
        let text = resp.text().await.unwrap_or_default();
        return Err(anyhow!("cleanup aql failed {status}: {text}"));
    }

    info!(
        "adaptive_grid_builder cycle: airports={} wrote_tiles={} by_tier={:?}",
        airport_count, written, by_tier
    );
    Ok(())
}

#[tokio::main]
async fn main() -> Result<()> {
    env_logger::init();
    let cfg = Config::from_env();
    let arango = Arango::new(cfg.arango_url.clone(), cfg.arango_db.clone(), cfg.arango_user.clone(), cfg.arango_password.clone())?;

    info!(
        "Starting adaptive_grid_builder airports_csv={} high_res_deg={} medium_res_deg={} low_res_deg={}",
        cfg.airports_csv_path, cfg.high_res_deg, cfg.medium_res_deg, cfg.low_res_deg
    );

    let mut interval = tokio::time::interval(Duration::from_secs(cfg.poll_interval_secs));
    loop {
        interval.tick().await;
        if let Err(e) = build_and_write(&cfg, &arango).await {
            return Err(e);
        }
    }
}


