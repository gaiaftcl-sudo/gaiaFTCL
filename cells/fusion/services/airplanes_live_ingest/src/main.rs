//! GaiaOS Aircraft Ingest from airplanes.live API
//! 
//! FREE global aircraft data, no API key required!
//! Rate limit: 1 request per second
//! 
//! Polls multiple geographic points and writes aircraft data to ArangoDB world_patches

use anyhow::Result;
use chrono::{DateTime, Timelike, Utc};
use log::{error, info, warn};
use serde::{Deserialize, Serialize};
use std::env;
use std::time::Duration;
use tokio::time::sleep;

const DEFAULT_BASE_URL: &str = "https://api.airplanes.live/v2";
const DEFAULT_ARANGO_URL: &str = "http://arangodb:8529";
const DEFAULT_ARANGO_DB: &str = "gaiaos";
const DEFAULT_WORLD_PATCHES_COLLECTION: &str = "world_patches";
// Default points: JFK, LAX, Heathrow, Tokyo, Chicago
const DEFAULT_POINTS: &str = "40.6,-73.8,250;33.9,-118.4,250;51.5,-0.5,250;35.5,139.8,250;41.9,-87.6,250";
const DEFAULT_RATE_LIMIT_MS: u64 = 1100; // Slightly over 1 second to be safe
const DEFAULT_LOOP_DELAY_SEC: u64 = 30;  // Delay between full cycles

/// Config for one polling point (lat/lon & radius in NM)
#[derive(Clone, Debug)]
struct PointConfig {
    lat: f64,
    lon: f64,
    radius_nm: f64,
}

/// Global configuration
#[derive(Clone, Debug)]
struct Config {
    base_url: String,
    arango_url: String,
    arango_db: String,
    arango_user: String,
    arango_password: String,
    world_patches_collection: String,
    points: Vec<PointConfig>,
    rate_limit_ms: u64,
    loop_delay_sec: u64,
}

impl Config {
    fn from_env() -> Self {
        let base_url = env::var("AIRPLANES_LIVE_BASE_URL")
            .unwrap_or_else(|_| DEFAULT_BASE_URL.to_string());
        let arango_url = env::var("ARANGO_URL")
            .unwrap_or_else(|_| DEFAULT_ARANGO_URL.to_string());
        let arango_db = env::var("ARANGO_DB")
            .unwrap_or_else(|_| DEFAULT_ARANGO_DB.to_string());
        let arango_user = env::var("ARANGO_USER")
            .unwrap_or_else(|_| "root".to_string());
        let arango_password = env::var("ARANGO_PASSWORD")
            .unwrap_or_else(|_| "gaiaos".to_string());
        let world_patches_collection = env::var("ARANGO_WORLD_PATCHES_COLLECTION")
            .unwrap_or_else(|_| DEFAULT_WORLD_PATCHES_COLLECTION.to_string());
        let points_raw = env::var("AIRPLANES_LIVE_POINTS")
            .unwrap_or_else(|_| DEFAULT_POINTS.to_string());
        let rate_limit_ms = env::var("AIRPLANES_LIVE_RATE_LIMIT_MS")
            .ok()
            .and_then(|s| s.parse::<u64>().ok())
            .unwrap_or(DEFAULT_RATE_LIMIT_MS);
        let loop_delay_sec = env::var("AIRPLANES_LIVE_LOOP_DELAY_SEC")
            .ok()
            .and_then(|s| s.parse::<u64>().ok())
            .unwrap_or(DEFAULT_LOOP_DELAY_SEC);

        let mut points = Vec::new();
        for spec in points_raw.split(';') {
            let trimmed = spec.trim();
            if trimmed.is_empty() {
                continue;
            }
            let parts: Vec<&str> = trimmed.split(',').collect();
            if parts.len() != 3 {
                warn!("Skipping invalid AIRPLANES_LIVE_POINTS entry: {}", trimmed);
                continue;
            }
            if let (Ok(lat), Ok(lon), Ok(radius_nm)) = (
                parts[0].parse::<f64>(),
                parts[1].parse::<f64>(),
                parts[2].parse::<f64>(),
            ) {
                points.push(PointConfig { lat, lon, radius_nm });
            } else {
                warn!("Skipping unparsable AIRPLANES_LIVE_POINTS entry: {}", trimmed);
            }
        }

        if points.is_empty() {
            warn!("No valid polling points found; using default JFK-only fallback");
            points.push(PointConfig {
                lat: 40.6413,
                lon: -73.7781,
                radius_nm: 250.0,
            });
        }

        Self {
            base_url,
            arango_url,
            arango_db,
            arango_user,
            arango_password,
            world_patches_collection,
            points,
            rate_limit_ms,
            loop_delay_sec,
        }
    }
}

/// Top-level response from airplanes.live /v2
#[derive(Debug, Deserialize)]
struct AirplanesLiveResponse {
    #[serde(default)]
    ac: Vec<Aircraft>,
    #[serde(default)]
    _msg: String,
    #[serde(default)]
    _now: i64,
    #[serde(default)]
    _total: i64,
}

/// Aircraft entry from airplanes.live
#[derive(Debug, Deserialize)]
struct Aircraft {
    hex: String,
    #[serde(default)]
    r: Option<String>,       // Registration
    #[serde(default)]
    t: Option<String>,       // Aircraft type
    #[serde(default)]
    flight: Option<String>,  // Callsign
    #[serde(default)]
    alt_baro: serde_json::Value,
    #[serde(default)]
    alt_geom: Option<f64>,
    #[serde(default)]
    gs: Option<f64>,         // Ground speed (knots)
    #[serde(default)]
    track: Option<f64>,      // Heading
    #[serde(default)]
    baro_rate: Option<f64>,  // Vertical rate (fpm)
    #[serde(default)]
    geom_rate: Option<f64>,
    #[serde(default)]
    lat: Option<f64>,
    #[serde(default)]
    lon: Option<f64>,
    #[serde(default)]
    _seen: Option<f64>,
    #[serde(default)]
    category: Option<String>,
    #[serde(default)]
    emergency: Option<String>,
}

/// Document for world_patches (ATC from airplanes.live)
#[derive(Debug, Serialize)]
struct AtcWorldPatch {
    _key: String,
    scale: String,
    context: String,
    source: String,
    center_lat: f64,
    center_lon: f64,
    center_alt_m: f64,
    timestamp: DateTime<Utc>,
    d_vec: [f64; 8],
    icao24: String,
    callsign: String,
    registration: Option<String>,
    aircraft_type: Option<String>,
    altitude_ft: f64,
    velocity_kts: f64,
    heading_deg: f64,
    vertical_rate_fpm: f64,
    category: Option<String>,
    emergency: Option<String>,
}

fn parse_altitude_ft(alt_baro: &serde_json::Value, alt_geom: Option<f64>) -> Option<f64> {
    match alt_baro {
        serde_json::Value::Number(n) => n.as_f64(),
        serde_json::Value::String(s) => {
            if s == "ground" {
                Some(0.0)
            } else {
                s.parse::<f64>().ok()
            }
        }
        _ => alt_geom,
    }
}

fn compute_8d_from_aircraft(
    lat: f64,
    lon: f64,
    altitude_ft: f64,
    velocity_kts: f64,
    vertical_rate_fpm: f64,
    timestamp: DateTime<Utc>,
    emergency: Option<&str>,
) -> [f64; 8] {
    // D0: Longitude normalized [-1, 1]
    let d0 = lon / 180.0;

    // D1: Latitude normalized [-1, 1]
    let d1 = lat / 90.0;

    // D2: Altitude normalized [0, 1] (assume 0..45000 ft)
    let d2 = (altitude_ft / 45000.0).clamp(0.0, 1.0);

    // D3: Time of day [0, 1]
    let seconds = timestamp.num_seconds_from_midnight() as f64;
    let d3 = (seconds / 86400.0).clamp(0.0, 1.0);

    // D4: Intent proxy – normalized speed (0..600 kts -> 0..1)
    let d4 = (velocity_kts / 600.0).clamp(0.0, 1.0);

    // D5: Risk – low altitude + high vertical rate + emergency
    let low_alt_factor = (1.0 - (altitude_ft / 20000.0)).clamp(0.0, 1.0);
    let vert_factor = (vertical_rate_fpm.abs() / 3000.0).clamp(0.0, 1.0);
    let emergency_factor = match emergency {
        Some("none") | None => 0.0,
        _ => 1.0,
    };
    let d5 = (0.5 * low_alt_factor + 0.3 * vert_factor + 0.2 * emergency_factor).clamp(0.0, 1.0);

    // D6: Compliance – inverse of risk
    let d6 = (1.0 - d5 * 0.8).clamp(0.0, 1.0);

    // D7: Uncertainty – based on speed and altitude
    let speed_factor = (velocity_kts / 600.0).clamp(0.0, 1.0);
    let alt_factor = (altitude_ft / 45000.0).clamp(0.0, 1.0);
    let d7 = (0.5 * (1.0 - alt_factor) + 0.5 * (1.0 - speed_factor)).clamp(0.0, 1.0) * 0.3; // Lower uncertainty for live data

    [d0, d1, d2, d3, d4, d5, d6, d7]
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

async fn insert_world_patch(cfg: &Config, client: &reqwest::Client, patch: &AtcWorldPatch) -> Result<()> {
    let url = format!(
        "{}/_db/{}/_api/document/{}",
        cfg.arango_url, cfg.arango_db, cfg.world_patches_collection
    );
    
    let auth = base64_encode(&format!("{}:{}", cfg.arango_user, cfg.arango_password));
    
    let resp = client
        .post(&url)
        .header("Authorization", format!("Basic {}", auth))
        .header("Content-Type", "application/json")
        .json(patch)
        .send()
        .await?;
        
    if !resp.status().is_success() {
        let status = resp.status();
        let text = resp.text().await.unwrap_or_default();
        return Err(anyhow::anyhow!("Arango insert error {}: {}", status, text));
    }
    
    Ok(())
}

async fn fetch_for_point(
    cfg: &Config,
    client: &reqwest::Client,
    point: &PointConfig,
) -> Result<AirplanesLiveResponse> {
    let url = format!(
        "{}/point/{:.4}/{:.4}/{:.0}",
        cfg.base_url, point.lat, point.lon, point.radius_nm
    );
    
    let resp = client
        .get(&url)
        .header("User-Agent", "GaiaOS-ATC-Ingest/1.0")
        .send()
        .await?;
        
    if !resp.status().is_success() {
        let status = resp.status();
        let text = resp.text().await.unwrap_or_default();
        return Err(anyhow::anyhow!("airplanes.live error {}: {}", status, text));
    }
    
    let parsed = resp.json::<AirplanesLiveResponse>().await?;
    Ok(parsed)
}

async fn process_point(
    cfg: &Config,
    http_client: &reqwest::Client,
    point: &PointConfig,
) -> usize {
    match fetch_for_point(cfg, http_client, point).await {
        Ok(resp) => {
            let ts = Utc::now();
            let aircraft_count = resp.ac.len();
            let mut inserted = 0;

            info!(
                "Point ({:.2},{:.2}, {}nm): {} aircraft",
                point.lat, point.lon, point.radius_nm, aircraft_count
            );

            for ac in resp.ac {
                // Require basic positional data
                let (lat, lon) = match (ac.lat, ac.lon) {
                    (Some(la), Some(lo)) => (la, lo),
                    _ => continue,
                };
                let altitude_ft = match parse_altitude_ft(&ac.alt_baro, ac.alt_geom) {
                    Some(a) => a,
                    None => continue,
                };
                let velocity_kts = ac.gs.unwrap_or(0.0);
                let heading_deg = ac.track.unwrap_or(0.0);
                let vertical_rate_fpm = ac.baro_rate.or(ac.geom_rate).unwrap_or(0.0);
                let callsign = ac.flight.unwrap_or_default().trim().to_string();

                let d_vec = compute_8d_from_aircraft(
                    lat,
                    lon,
                    altitude_ft,
                    velocity_kts,
                    vertical_rate_fpm,
                    ts,
                    ac.emergency.as_deref(),
                );

                let patch = AtcWorldPatch {
                    _key: format!("atc_{}_{}", ac.hex.to_lowercase(), ts.timestamp()),
                    scale: "planetary".to_string(),
                    context: "planetary:atc_live".to_string(),
                    source: "airplanes.live".to_string(),
                    center_lat: lat,
                    center_lon: lon,
                    center_alt_m: altitude_ft * 0.3048,
                    timestamp: ts,
                    d_vec,
                    icao24: ac.hex.to_lowercase(),
                    callsign,
                    registration: ac.r,
                    aircraft_type: ac.t,
                    altitude_ft,
                    velocity_kts,
                    heading_deg,
                    vertical_rate_fpm,
                    category: ac.category,
                    emergency: ac.emergency,
                };

                // Insert into ArangoDB
                if let Err(e) = insert_world_patch(cfg, http_client, &patch).await {
                    error!("Failed to insert world patch: {}", e);
                } else {
                    inserted += 1;
                }
            }

            info!("  → Inserted {} aircraft patches", inserted);
            inserted
        }
        Err(e) => {
            error!(
                "Failed to fetch airplanes.live data for point ({:.2},{:.2},{}nm): {}",
                point.lat, point.lon, point.radius_nm, e
            );
            0
        }
    }
}

#[tokio::main]
async fn main() -> Result<()> {
    env_logger::init();
    
    info!("╔════════════════════════════════════════════════════════════╗");
    info!("║      GAIAOS AIRPLANES.LIVE INGEST SERVICE v1.0.0          ║");
    info!("║      FREE Global Aircraft Data → world_patches            ║");
    info!("╚════════════════════════════════════════════════════════════╝");

    let cfg = Config::from_env();

    info!("Configuration:");
    info!("  Base URL: {}", cfg.base_url);
    info!("  ArangoDB: {}", cfg.arango_url);
    info!("  Database: {}", cfg.arango_db);
    info!("  Collection: {}", cfg.world_patches_collection);
    info!("  Rate limit: {} ms", cfg.rate_limit_ms);
    info!("  Loop delay: {} sec", cfg.loop_delay_sec);
    info!("  Points to poll:");
    for (i, point) in cfg.points.iter().enumerate() {
        info!("    {}: ({:.2}, {:.2}) radius {}nm", i + 1, point.lat, point.lon, point.radius_nm);
    }

    let http_client = reqwest::Client::builder()
        .user_agent("GaiaOS-airplanes-live-ingest/1.0")
        .timeout(Duration::from_secs(30))
        .build()?;

    info!("🛫 Starting aircraft polling loop...");

    let mut total_aircraft: u64 = 0;
    let mut cycles: u64 = 0;

    loop {
        cycles += 1;
        let cycle_start = Utc::now();
        let mut cycle_aircraft = 0;

        for point in &cfg.points {
            let inserted = process_point(&cfg, &http_client, point).await;
            cycle_aircraft += inserted;
            
            // Rate limit: wait between requests
            sleep(Duration::from_millis(cfg.rate_limit_ms)).await;
        }

        total_aircraft += cycle_aircraft as u64;
        
        info!(
            "📊 Cycle {} complete: {} aircraft this cycle, {} total | {}",
            cycles,
            cycle_aircraft,
            total_aircraft,
            cycle_start.format("%H:%M:%S")
        );

        // Wait before next cycle
        if cfg.loop_delay_sec > 0 {
            sleep(Duration::from_secs(cfg.loop_delay_sec)).await;
        }
    }
}

