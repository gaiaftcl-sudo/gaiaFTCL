//! GaiaOS ATC Ingest Service
//! 
//! Full loop: bbox policy + OpenSky OAuth2 + prediction + NATS streaming

mod model;
mod opensky_client;
mod policy;

use crate::model::aircraft_to_event;
use crate::opensky_client::{OpenSkyClient, OpenSkyError};
use crate::policy::{
    AircraftState, AreaCredits, PollDecision, PollingPolicy, PredictionEngine, RegionBBox,
};
use chrono::{DateTime, Utc};
use serde_json::Value;
use std::env;
use tokio::time::{sleep, Duration, Instant};

fn parse_states_json(data: &Value, now: DateTime<Utc>) -> Vec<AircraftState> {
    let mut out = Vec::new();

    let states_opt = data.get("states").and_then(|v| v.as_array());
    let states = match states_opt {
        Some(s) => s,
        None => return out,
    };

    for row in states {
        if !row.is_array() {
            continue;
        }
        let arr = row.as_array().unwrap();
        if arr.len() < 15 {
            continue;
        }

        let on_ground = arr[8].as_bool().unwrap_or(false);
        if on_ground {
            continue;
        }

        let lon = arr[5].as_f64();
        let lat = arr[6].as_f64();
        if lon.is_none() || lat.is_none() {
            continue;
        }

        let icao24 = arr[0].as_str().unwrap_or("").to_string();
        if icao24.is_empty() {
            continue;
        }

        let callsign = arr[1].as_str().unwrap_or("").trim().to_string();
        let origin_country = arr[2].as_str().unwrap_or("").to_string();

        let baro_alt_m = arr[7].as_f64().unwrap_or(0.0);
        let velocity_ms = arr[9].as_f64().unwrap_or(0.0);
        let true_track = arr[10].as_f64().unwrap_or(0.0);
        let vertical_rate_ms = arr[11].as_f64().unwrap_or(0.0);
        let category = if arr.len() > 17 { arr[17].as_i64() } else { None };

        let ac = AircraftState {
            icao24,
            callsign,
            origin_country,
            lat: lat.unwrap(),
            lon: lon.unwrap(),
            alt_m: baro_alt_m,
            velocity_ms,
            heading_deg: true_track,
            vertical_rate_ms,
            last_update: now,
            uncertainty: 0.0,
            category,
        };
        out.push(ac);
    }

    out
}

#[tokio::main]
async fn main() {
    env_logger::init();
    
    log::info!("╔════════════════════════════════════════════════════════════╗");
    log::info!("║      GAIAOS ATC INGEST SERVICE v1.0.0                      ║");
    log::info!("║      OpenSky OAuth2 + Credit Policy + 8D Prediction        ║");
    log::info!("╚════════════════════════════════════════════════════════════╝");

    let client_id = env::var("OPEN_SKY_CLIENT_ID")
        .or_else(|_| env::var("OPENSKY_CLIENT_ID"))
        .unwrap_or_else(|_| {
            log::warn!("No OpenSky client ID set, using empty");
            String::new()
        });
    
    let client_secret = env::var("OPEN_SKY_CLIENT_SECRET")
        .or_else(|_| env::var("OPENSKY_CLIENT_SECRET"))
        .unwrap_or_else(|_| {
            log::warn!("No OpenSky client secret set, using empty");
            String::new()
        });

    let daily_limit: u32 = env::var("OPEN_SKY_DAILY_LIMIT")
        .or_else(|_| env::var("DAILY_CREDIT_LIMIT"))
        .ok()
        .and_then(|s| s.parse::<u32>().ok())
        .unwrap_or(4000);

    let nats_url = env::var("NATS_URL").unwrap_or_else(|_| "nats://127.0.0.1:4222".into());

    log::info!("Client ID: {}...", &client_id[..client_id.len().min(20)]);
    log::info!("Daily credit limit: {}", daily_limit);
    log::info!("NATS URL: {}", nats_url);

    // Regions: tune as needed
    let regions = vec![
        RegionBBox::new("NYC", 40.0, 41.5, -75.0, -72.5, AreaCredits::Small, 15),
        RegionBBox::new("US-East", 24.0, 50.0, -95.0, -60.0, AreaCredits::Medium, 45),
        RegionBBox::new("US-West", 24.0, 50.0, -130.0, -95.0, AreaCredits::Medium, 60),
        RegionBBox::new("Europe", 35.0, 60.0, -10.0, 30.0, AreaCredits::Medium, 60),
        RegionBBox::new("East-Asia", 10.0, 50.0, 100.0, 150.0, AreaCredits::Medium, 90),
        RegionBBox::new("Global-Coarse", -60.0, 60.0, -180.0, 180.0, AreaCredits::Global, 300),
    ];

    log::info!("Regions configured:");
    for r in &regions {
        log::info!(
            "  • {}: ({:.1},{:.1}) to ({:.1},{:.1}) @ {}s, cost={:?}",
            r.name, r.lamin, r.lomin, r.lamax, r.lomax, r.poll_interval.as_secs(), r.cost
        );
    }

    let mut policy = PollingPolicy::new(daily_limit, regions);
    let mut opensky = OpenSkyClient::new(client_id, client_secret);
    let mut prediction = PredictionEngine::new();

    // Connect to NATS
    log::info!("Connecting to NATS: {}", nats_url);
    let nc = loop {
        match async_nats::connect(&nats_url).await {
            Ok(client) => {
                log::info!("✓ Connected to NATS");
                break client;
            }
            Err(e) => {
                log::warn!("NATS connection failed: {}, retrying...", e);
                sleep(Duration::from_secs(2)).await;
            }
        }
    };

    let tick_interval = Duration::from_secs(1);
    let mut rate_limit_until: Option<Instant> = None;

    loop {
        let tick_start = Utc::now();

        // Check rate limit
        if let Some(until) = rate_limit_until {
            if Instant::now() < until {
                sleep(Duration::from_millis(100)).await;
                continue;
            }
            rate_limit_until = None;
        }

        // Poll each region if due
        let num_regions = policy.regions.len();
        for i in 0..num_regions {
            // First, get the decision
            let decision = policy.should_poll_by_index(i);
            
            // Then get the region data
            let (name, lamin, lomin, lamax, lomax) = {
                let region = &policy.regions[i];
                (region.name.clone(), region.lamin, region.lomin, region.lamax, region.lomax)
            };
            
            match decision {
                PollDecision::PollNow => {
                    log::info!(
                        "Polling {} ({:.1},{:.1}) to ({:.1},{:.1})",
                        name, lamin, lomin, lamax, lomax
                    );
                    
                    match opensky
                        .fetch_states_bbox(lamin, lamax, lomin, lomax)
                        .await
                    {
                        Ok(json) => {
                            let now = Utc::now();
                            let ac_list = parse_states_json(&json, now);
                            let count = ac_list.len();
                            for ac in ac_list {
                                prediction.update_from_measurement(ac);
                            }
                            policy.register_poll_by_index(i);
                            
                            let timestamp = now.format("%H:%M:%S");
                            log::info!(
                                "[{}] {}: ✓ {} aircraft (total: {}, credits: {}/{})",
                                timestamp,
                                name,
                                count,
                                prediction.count(),
                                policy.credit_mgr.credits_used_today,
                                policy.credit_mgr.daily_credit_limit
                            );
                        }
                        Err(OpenSkyError::RateLimited(wait_secs)) => {
                            log::warn!("Rate limited, backing off {} seconds", wait_secs);
                            rate_limit_until = Some(Instant::now() + Duration::from_secs(wait_secs));
                        }
                        Err(e) => {
                            log::warn!("OpenSky error for {}: {}", name, e);
                        }
                    }
                }
                PollDecision::Skip => {
                    // Not due yet
                }
                PollDecision::Critical => {
                    log::warn!("{}: Credit budget critical, skipping", name);
                }
            }
        }

        // Propagate all aircraft forward
        prediction.propagate_all(tick_interval.as_secs_f64());
        
        // Prune stale aircraft (> 5 min since last measurement)
        prediction.prune_stale(300);

        // Emit all aircraft states to NATS
        let snapshot = prediction.get_snapshot();
        for ac in &snapshot {
            let is_predicted = ac.uncertainty > 0.0;
            let event = aircraft_to_event(ac, is_predicted);
            
            if let Ok(json) = serde_json::to_vec(&event) {
                if let Err(e) = nc.publish("atc.aircraft.state".to_string(), json.into()).await {
                    log::error!("NATS publish error: {}", e);
                }
            }
        }

        // Sleep for remainder of tick
        let elapsed = Utc::now()
            .signed_duration_since(tick_start)
            .num_milliseconds();
        if elapsed < tick_interval.as_millis() as i64 {
            let sleep_ms = (tick_interval.as_millis() as i64 - elapsed) as u64;
            sleep(Duration::from_millis(sleep_ms)).await;
        }
    }
}

