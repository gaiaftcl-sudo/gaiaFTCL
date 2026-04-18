//! GaiaOS Flight Ingest Service
//! 
//! Production-ready flight data aggregation with:
//! - OAuth2 authenticated OpenSky access
//! - Credit-aware polling policy
//! - Continuous 4D→8D prediction between measurements
//! - NATS streaming to Spatial Gateway / ATC Agent

mod opensky;
mod policy;

use anyhow::Result;
use chrono::Utc;
use policy::{AircraftState, AreaCredits, PollDecision, PollingPolicy, PredictionEngine, RegionBBox};
use opensky::OpenSkyClient;
use serde::Serialize;
use std::sync::Arc;
use std::time::Instant;
use tokio::sync::RwLock;
use tokio::time::Duration;
use tracing::{error, info, warn};

/// Configuration from environment
struct Config {
    nats_url: String,
    opensky_client_id: String,
    opensky_client_secret: String,
    daily_credit_limit: u32,
    prediction_tick_ms: u64,
    stale_threshold_secs: i64,
}

impl Config {
    fn from_env() -> Self {
        Self {
            nats_url: std::env::var("NATS_URL").unwrap_or_else(|_| "nats://127.0.0.1:4222".into()),
            opensky_client_id: std::env::var("OPENSKY_CLIENT_ID")
                .unwrap_or_else(|_| "gaiaos-api-client".into()),
            opensky_client_secret: std::env::var("OPENSKY_CLIENT_SECRET")
                .unwrap_or_else(|_| "".into()),
            daily_credit_limit: std::env::var("DAILY_CREDIT_LIMIT")
                .ok()
                .and_then(|s| s.parse().ok())
                .unwrap_or(4000),
            prediction_tick_ms: std::env::var("PREDICTION_TICK_MS")
                .ok()
                .and_then(|s| s.parse().ok())
                .unwrap_or(1000),
            stale_threshold_secs: std::env::var("STALE_THRESHOLD_SECS")
                .ok()
                .and_then(|s| s.parse().ok())
                .unwrap_or(300),
        }
    }
}

/// Message sent to NATS for each aircraft state
#[derive(Debug, Serialize)]
struct AircraftMessage {
    icao24: String,
    callsign: String,
    latitude: f64,
    longitude: f64,
    altitude_ft: f64,
    ground_speed_kts: f64,
    vertical_rate_fpm: f64,
    heading: f64,
    timestamp_unix: i64,
    region: String,
    source: String,
    is_predicted: bool,
    uncertainty: f64,
    vqbit_8d: [f64; 8],
}

impl From<&AircraftState> for AircraftMessage {
    fn from(ac: &AircraftState) -> Self {
        Self {
            icao24: ac.icao24.clone(),
            callsign: ac.callsign.clone(),
            latitude: ac.lat,
            longitude: ac.lon,
            altitude_ft: ac.alt_m * 3.28084,
            ground_speed_kts: ac.velocity_ms * 1.94384,
            vertical_rate_fpm: ac.vertical_rate_ms * 196.85,
            heading: ac.heading_deg,
            timestamp_unix: ac.last_update.timestamp(),
            region: ac.region.clone(),
            source: if ac.is_predicted { "prediction" } else { "opensky_oauth2" }.into(),
            is_predicted: ac.is_predicted,
            uncertainty: ac.uncertainty,
            vqbit_8d: ac.to_vqbit_8d(),
        }
    }
}

/// Batch completion message
#[derive(Debug, Serialize)]
struct BatchMessage {
    r#type: String,
    region: String,
    count: usize,
    predicted_count: usize,
    total_tracked: usize,
    credits_used: u32,
    credits_remaining: u32,
    timestamp: i64,
}

/// Shared state between polling and prediction tasks
struct SharedState {
    policy: PollingPolicy,
    prediction: PredictionEngine,
    opensky: OpenSkyClient,
    rate_limit_until: Option<Instant>,
}

#[tokio::main]
async fn main() -> Result<()> {
    // Initialize tracing
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::from_default_env()
                .add_directive("flight_ingest=info".parse()?)
                .add_directive("reqwest=warn".parse()?),
        )
        .json()
        .init();

    let config = Config::from_env();

    info!("╔════════════════════════════════════════════════════════════╗");
    info!("║      GAIAOS FLIGHT INGEST SERVICE v1.0.0                   ║");
    info!("║      Credit-Aware • OAuth2 • Predictive 8D Substrate       ║");
    info!("╚════════════════════════════════════════════════════════════╝");

    // Define polling regions
    let regions = vec![
        // NYC Metro - Primary demo region, high frequency
        RegionBBox::new("NYC", 40.0, 41.5, -75.0, -72.5, AreaCredits::Small, 15),
        // US East Coast - High traffic
        RegionBBox::new("US_EAST", 25.0, 45.0, -85.0, -70.0, AreaCredits::Medium, 45),
        // US West Coast
        RegionBBox::new("US_WEST", 30.0, 50.0, -125.0, -110.0, AreaCredits::Medium, 60),
        // Europe
        RegionBBox::new("EUROPE", 35.0, 60.0, -10.0, 30.0, AreaCredits::Medium, 60),
        // East Asia
        RegionBBox::new("ASIA", 10.0, 50.0, 100.0, 150.0, AreaCredits::Medium, 90),
        // Global fallback (expensive, infrequent)
        RegionBBox::new("GLOBAL", -60.0, 60.0, -180.0, 180.0, AreaCredits::Global, 300),
    ];

    info!("Regions configured:");
    for r in &regions {
        info!("  • {}: ({:.1},{:.1}) to ({:.1},{:.1}) @ {:?}s, cost={:?}",
            r.name, r.lamin, r.lomin, r.lamax, r.lomax, r.poll_interval.as_secs(), r.cost);
    }

    // Initialize components
    let policy = PollingPolicy::new(config.daily_credit_limit, regions);
    let prediction = PredictionEngine::new(config.stale_threshold_secs);
    let opensky = OpenSkyClient::new(&config.opensky_client_id, &config.opensky_client_secret);

    let state = Arc::new(RwLock::new(SharedState {
        policy,
        prediction,
        opensky,
        rate_limit_until: None,
    }));

    // Connect to NATS
    info!("Connecting to NATS: {}", config.nats_url);
    let nc = loop {
        match async_nats::connect(&config.nats_url).await {
            Ok(client) => {
                info!("✓ Connected to NATS");
                break client;
            }
            Err(e) => {
                warn!("NATS connection failed: {}, retrying...", e);
                tokio::time::sleep(Duration::from_secs(2)).await;
            }
        }
    };

    // Spawn polling task
    let poll_state = state.clone();
    let poll_nc = nc.clone();
    let polling_task = tokio::spawn(async move {
        polling_loop(poll_state, poll_nc).await
    });

    // Spawn prediction task
    let pred_state = state.clone();
    let pred_nc = nc.clone();
    let tick_ms = config.prediction_tick_ms;
    let prediction_task = tokio::spawn(async move {
        prediction_loop(pred_state, pred_nc, tick_ms).await
    });

    // Wait for tasks
    tokio::select! {
        r = polling_task => {
            error!("Polling task exited: {:?}", r);
        }
        r = prediction_task => {
            error!("Prediction task exited: {:?}", r);
        }
    }

    Ok(())
}

/// Main polling loop - fetches from OpenSky based on credit policy
async fn polling_loop(state: Arc<RwLock<SharedState>>, nc: async_nats::Client) {
    loop {
        // Check rate limit
        {
            let s = state.read().await;
            if let Some(until) = s.rate_limit_until {
                if Instant::now() < until {
                    let wait = until.duration_since(Instant::now());
                    info!("Rate limited, waiting {:?}", wait);
                    drop(s);
                    tokio::time::sleep(wait).await;
                    continue;
                }
            }
        }

        // Find next region to poll
        let region_idx = {
            let s = state.read().await;
            s.policy.next_due_region()
        };

        let Some(region_idx) = region_idx else {
            // No region due - sleep briefly
            tokio::time::sleep(Duration::from_millis(100)).await;
            continue;
        };

        // Check polling decision
        let decision = {
            let mut s = state.write().await;
            s.policy.should_poll(region_idx)
        };

        match decision {
            PollDecision::PollNow => {
                // Get region info
                let (region_name, region_bbox) = {
                    let s = state.read().await;
                    let r = &s.policy.regions[region_idx];
                    (r.name.clone(), r.clone())
                };

                // Fetch from OpenSky
                let fetch_start = Instant::now();
                let result = {
                    let s = state.read().await;
                    s.opensky.fetch_states(&region_bbox).await
                };

                match result {
                    Ok(aircraft) => {
                        let count = aircraft.len();
                        let latency = fetch_start.elapsed().as_millis();

                        // Update prediction engine with fresh measurements
                        {
                            let mut s = state.write().await;
                            for ac in aircraft {
                                s.prediction.update_from_measurement(ac);
                            }
                            s.policy.register_poll(region_idx, count);
                        }

                        // Publish batch message
                        let batch_msg = {
                            let s = state.read().await;
                            BatchMessage {
                                r#type: "batch_complete".into(),
                                region: region_name.clone(),
                                count,
                                predicted_count: s.prediction.predicted_count(),
                                total_tracked: s.prediction.aircraft_count(),
                                credits_used: s.policy.credit_mgr.credits_used_today,
                                credits_remaining: s.policy.credit_mgr.remaining(),
                                timestamp: Utc::now().timestamp(),
                            }
                        };

                        if let Err(e) = nc
                            .publish("atc.aircraft.batch", serde_json::to_vec(&batch_msg).unwrap().into())
                            .await
                        {
                            error!("Failed to publish batch message: {}", e);
                        }

                        let status = {
                            let s = state.read().await;
                            s.policy.credit_mgr.usage_percent()
                        };

                        info!(
                            "[{}] ✓ {} aircraft in {}ms (total: {}, credits: {:.1}% used)",
                            region_name,
                            count,
                            latency,
                            batch_msg.total_tracked,
                            status
                        );
                    }
                    Err(e) => {
                        let err_str = e.to_string();
                        if err_str.starts_with("RATE_LIMITED:") {
                            let wait_secs: u64 = err_str
                                .strip_prefix("RATE_LIMITED:")
                                .and_then(|s| s.parse().ok())
                                .unwrap_or(60);

                            let mut s = state.write().await;
                            s.rate_limit_until = Some(Instant::now() + Duration::from_secs(wait_secs));
                            warn!("Rate limited, backing off {} seconds", wait_secs);
                        } else {
                            error!("[{}] OpenSky fetch error: {}", region_name, e);
                        }
                    }
                }
            }
            PollDecision::Skip => {
                // Region not due or credits low - just continue
            }
            PollDecision::Critical => {
                warn!("Credit budget critical - using prediction only");
            }
        }

        // Small delay to prevent tight loop
        tokio::time::sleep(Duration::from_millis(50)).await;
    }
}

/// Prediction loop - propagates all aircraft forward and emits states
async fn prediction_loop(state: Arc<RwLock<SharedState>>, nc: async_nats::Client, tick_ms: u64) {
    let tick_duration = Duration::from_millis(tick_ms);
    let dt_secs = tick_ms as f64 / 1000.0;

    loop {
        tokio::time::sleep(tick_duration).await;

        // Propagate all aircraft
        {
            let mut s = state.write().await;
            s.prediction.propagate_all(dt_secs);
            s.prediction.prune_stale();
        }

        // Get snapshot and emit
        let snapshot = {
            let s = state.read().await;
            s.prediction.get_snapshot()
        };

        // Emit each aircraft state to NATS
        for ac in &snapshot {
            let msg = AircraftMessage::from(ac);
            if let Err(e) = nc
                .publish("atc.aircraft.state", serde_json::to_vec(&msg).unwrap().into())
                .await
            {
                error!("Failed to publish aircraft state: {}", e);
            }
        }
    }
}

