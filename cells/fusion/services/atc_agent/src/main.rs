//! GaiaOS ATC Agent Service
//!
//! Subscribes to NATS `atc.aircraft.state` events from atc_ingest,
//! optionally enriches with weather data, and writes combined 8D patches
//! to ArangoDB `world_patches` collection.
//!
//! Also provides query endpoints for fetching local ATC+weather context
//! to feed into `/evolve/unified`.

use chrono::{DateTime, Timelike, Utc};
use futures::StreamExt;
use log::{error, info, warn};
use serde::{Deserialize, Serialize};
use std::{collections::HashMap, env, sync::Arc};
use tokio::sync::RwLock;
use uuid::Uuid;

// ═══════════════════════════════════════════════════════════════════════════
// MODELS
// ═══════════════════════════════════════════════════════════════════════════

/// Flight event from atc_ingest (via NATS)
#[derive(Debug, Clone, Deserialize)]
pub struct FlightEvent {
    pub icao24: String,
    pub callsign: String,
    pub origin_country: String,
    pub latitude: f64,
    pub longitude: f64,
    pub altitude_m: f64,
    pub altitude_ft: f64,
    pub velocity_ms: f64,
    pub ground_speed_kts: f64,
    pub heading_deg: f64,
    pub vertical_rate_ms: f64,
    pub vertical_rate_fpm: f64,
    pub timestamp: DateTime<Utc>,
    pub timestamp_unix: i64,
    pub category: Option<i64>,
    pub source: String,
    pub is_predicted: bool,
    #[serde(alias = "vqbit_8d")]
    pub d_vec: Option<[f64; 8]>,
    pub uncertainty: f64,
}

/// Weather point response (from weather_ingest)
#[derive(Debug, Clone, Deserialize)]
pub struct WeatherPoint {
    pub success: bool,
    pub latitude: f64,
    pub longitude: f64,
    pub altitude_m: f64,
    pub timestamp: DateTime<Utc>,
    pub d_vec: [f64; 8],
    pub temperature_c: Option<f64>,
    pub humidity_pct: Option<f64>,
    pub wind_speed_ms: Option<f64>,
    pub visibility_m: Option<f64>,
    pub weather_description: String,
}

/// Combined ATC + Weather world patch
#[derive(Debug, Serialize)]
pub struct AtcWorldPatch {
    pub _key: String,
    pub scale: String,
    pub context: String,
    pub center_lat: f64,
    pub center_lon: f64,
    pub center_alt_m: f64,
    pub timestamp: DateTime<Utc>,
    pub d_vec: [f64; 8],
    // ATC-specific fields
    pub icao24: String,
    pub callsign: String,
    pub origin_country: String,
    pub category: Option<i64>,
    pub velocity_ms: f64,
    pub heading_deg: f64,
    pub vertical_rate_ms: f64,
    pub is_predicted: bool,
    pub uncertainty: f64,
    // Weather overlay (if enriched)
    pub weather_d_vec: Option<[f64; 8]>,
    pub temperature_c: Option<f64>,
    pub wind_speed_ms: Option<f64>,
    pub visibility_m: Option<f64>,
    // Combined 8D (ATC + Weather fusion)
    pub fused_d_vec: [f64; 8],
}

/// Aircraft tracking state
#[derive(Debug, Clone)]
struct TrackedAircraft {
    event: FlightEvent,
    weather: Option<WeatherPoint>,
    last_weather_fetch: Option<DateTime<Utc>>,
}

// ═══════════════════════════════════════════════════════════════════════════
// ARANGO CLIENT
// ═══════════════════════════════════════════════════════════════════════════

#[derive(Clone)]
struct ArangoClient {
    base_url: String,
    db_name: String,
    collection: String,
    http: reqwest::Client,
    auth: String,
}

impl ArangoClient {
    fn new(base_url: String, db_name: String, collection: String) -> Self {
        let http = reqwest::Client::builder()
            .user_agent("GaiaOS-ATC-Agent/0.1")
            .timeout(std::time::Duration::from_secs(30))
            .build()
            .expect("failed to build reqwest client");

        let user = env::var("ARANGO_USER").unwrap_or_else(|_| "root".to_string());
        let password = env::var("ARANGO_PASSWORD").unwrap_or_else(|_| "gaiaos".to_string());
        let auth = base64_encode(&format!("{}:{}", user, password));

        Self {
            base_url: base_url.trim_end_matches('/').to_string(),
            db_name,
            collection,
            http,
            auth,
        }
    }

    async fn ensure_collection(&self) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        let url = format!(
            "{}/_db/{}/_api/collection/{}",
            self.base_url, self.db_name, self.collection
        );

        let resp = self
            .http
            .get(&url)
            .header("Authorization", format!("Basic {}", self.auth))
            .send()
            .await?;

        if resp.status().is_success() {
            return Ok(());
        }

        // Create collection
        let create_url = format!("{}/_db/{}/_api/collection", self.base_url, self.db_name);
        let body = serde_json::json!({
            "name": self.collection,
            "type": 2
        });

        let resp = self
            .http
            .post(&create_url)
            .header("Authorization", format!("Basic {}", self.auth))
            .header("Content-Type", "application/json")
            .json(&body)
            .send()
            .await?;

        if !resp.status().is_success() {
            let text = resp.text().await.unwrap_or_default();
            warn!("Failed to create collection: {}", text);
        } else {
            info!("✓ Created collection: {}", self.collection);
        }

        Ok(())
    }

    async fn upsert_patch(
        &self,
        patch: &AtcWorldPatch,
    ) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        let url = format!(
            "{}/_db/{}/_api/document/{}?overwrite=true",
            self.base_url, self.db_name, self.collection
        );

        let resp = self
            .http
            .post(&url)
            .header("Authorization", format!("Basic {}", self.auth))
            .header("Content-Type", "application/json")
            .json(patch)
            .send()
            .await?;

        if !resp.status().is_success() {
            let status = resp.status();
            let text = resp.text().await.unwrap_or_default();
            return Err(format!("Arango insert error {}: {}", status, text).into());
        }

        Ok(())
    }

    /// Query ATC patches near a position
    async fn query_atc_near(
        &self,
        lat: f64,
        lon: f64,
        radius_deg: f64,
        max_results: usize,
    ) -> Result<Vec<serde_json::Value>, Box<dyn std::error::Error + Send + Sync>> {
        let aql = r#"
            FOR doc IN @@collection
                FILTER doc.context == "planetary:atc_live"
                FILTER ABS(doc.center_lat - @lat) < @radius
                FILTER ABS(doc.center_lon - @lon) < @radius
                SORT doc.timestamp DESC
                LIMIT @max_results
                RETURN doc
        "#;

        let body = serde_json::json!({
            "query": aql,
            "bindVars": {
                "@collection": self.collection,
                "lat": lat,
                "lon": lon,
                "radius": radius_deg,
                "max_results": max_results as i64
            }
        });

        let url = format!("{}/_db/{}/_api/cursor", self.base_url, self.db_name);

        let resp = self
            .http
            .post(&url)
            .header("Authorization", format!("Basic {}", self.auth))
            .header("Content-Type", "application/json")
            .json(&body)
            .send()
            .await?;

        if !resp.status().is_success() {
            let text = resp.text().await.unwrap_or_default();
            return Err(format!("AQL query failed: {}", text).into());
        }

        let result: serde_json::Value = resp.json().await?;
        let docs = result["result"]
            .as_array()
            .cloned()
            .unwrap_or_default();

        Ok(docs)
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// WEATHER CLIENT
// ═══════════════════════════════════════════════════════════════════════════

#[derive(Clone)]
struct WeatherClient {
    base_url: String,
    http: reqwest::Client,
}

impl WeatherClient {
    fn new(base_url: String) -> Self {
        let http = reqwest::Client::builder()
            .user_agent("GaiaOS-ATC-Agent/0.1")
            .timeout(std::time::Duration::from_secs(10))
            .build()
            .expect("failed to build reqwest client");

        Self {
            base_url: base_url.trim_end_matches('/').to_string(),
            http,
        }
    }

    async fn fetch_weather(
        &self,
        lat: f64,
        lon: f64,
        alt: f64,
    ) -> Result<WeatherPoint, Box<dyn std::error::Error + Send + Sync>> {
        let url = format!(
            "{}/ingest/point?lat={}&lon={}&alt={}",
            self.base_url, lat, lon, alt
        );

        let resp = self.http.get(&url).send().await?;

        if !resp.status().is_success() {
            let status = resp.status();
            let text = resp.text().await.unwrap_or_default();
            return Err(format!("Weather fetch error {}: {}", status, text).into());
        }

        let weather: WeatherPoint = resp.json().await?;
        Ok(weather)
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// 8D FUSION
// ═══════════════════════════════════════════════════════════════════════════

/// Fuse ATC 8D vector with Weather 8D vector
/// 
/// ATC D0-D7: [lon, lat, alt, time, intent, risk, compliance, uncertainty]
/// Weather D0-D7: [lon, lat, alt, time, temp, precip_risk, visibility, wind]
/// 
/// Fusion strategy:
/// - D0-D3: Keep from ATC (spatial-temporal is aircraft-centric)
/// - D4: Blend intent with weather visibility
/// - D5: Combine ATC risk with weather risks (precip, wind)
/// - D6: Compliance adjusted by weather factors
/// - D7: Max uncertainty from both sources
fn fuse_atc_weather(atc: &[f64; 8], weather: Option<&[f64; 8]>) -> [f64; 8] {
    let weather = match weather {
        Some(w) => w,
        None => return *atc, // No weather, return ATC as-is
    };

    let mut fused = [0.0f64; 8];

    // D0-D3: Spatial-temporal from ATC
    fused[0] = atc[0];
    fused[1] = atc[1];
    fused[2] = atc[2];
    fused[3] = atc[3];

    // D4: Intent adjusted by visibility
    // Low visibility = more conservative intent
    let visibility_factor = weather[6]; // Weather D6 = visibility quality
    fused[4] = atc[4] * (0.5 + 0.5 * visibility_factor);

    // D5: Combined risk
    // ATC risk + weather precipitation risk + wind severity
    let atc_risk = atc[5];
    let precip_risk = weather[5];
    let wind_risk = weather[7];
    fused[5] = (atc_risk + precip_risk * 0.3 + wind_risk * 0.3).clamp(0.0, 1.0);

    // D6: Compliance adjusted by weather
    // Poor weather = lower effective compliance
    let weather_quality = (visibility_factor + (1.0 - precip_risk) + (1.0 - wind_risk)) / 3.0;
    fused[6] = atc[6] * (0.7 + 0.3 * weather_quality);

    // D7: Max uncertainty
    fused[7] = atc[7].max(0.1); // Weather adds some baseline uncertainty

    fused
}

/// Compute default 8D from flight event if not provided
fn compute_atc_8d(event: &FlightEvent) -> [f64; 8] {
    // D0: Longitude normalized [-1, 1]
    let d0 = event.longitude / 180.0;

    // D1: Latitude normalized [-1, 1]
    let d1 = event.latitude / 90.0;

    // D2: Altitude normalized [0, 1] (assuming 15km max)
    let d2 = (event.altitude_m / 15000.0).clamp(0.0, 1.0);

    // D3: Time of day [0, 1]
    let seconds_since_midnight = event.timestamp.time().num_seconds_from_midnight() as f64;
    let d3 = (seconds_since_midnight / 86400.0).clamp(0.0, 1.0);

    // Speed and climb rate normalized
    let speed_norm = (event.velocity_ms / 280.0).clamp(0.0, 1.0);
    let climb_norm = (event.vertical_rate_ms.abs() / 30.0).clamp(0.0, 1.0);

    // D4: Intent proxy
    let d4 = (1.0 - climb_norm * 0.5).clamp(0.0, 1.0);

    // D5: Risk level
    let risk = (speed_norm * 0.4 + climb_norm * 0.6).clamp(0.0, 1.0);
    let d5 = risk;

    // D6: Compliance
    let d6 = (1.0 - risk * 0.7).clamp(0.0, 1.0);

    // D7: Uncertainty
    let d7 = (event.uncertainty / 5.0).clamp(0.0, 1.0);

    [d0, d1, d2, d3, d4, d5, d6, d7]
}

// ═══════════════════════════════════════════════════════════════════════════
// APPLICATION STATE
// ═══════════════════════════════════════════════════════════════════════════

struct AppState {
    arango: ArangoClient,
    weather: Option<WeatherClient>,
    tracked: RwLock<HashMap<String, TrackedAircraft>>,
    weather_cache_ttl_secs: i64,
    enrich_weather: bool,
}

impl AppState {
    fn new(arango: ArangoClient, weather: Option<WeatherClient>) -> Self {
        let enrich_weather = env::var("ENRICH_WEATHER")
            .map(|v| v == "true" || v == "1")
            .unwrap_or(true);

        let weather_cache_ttl_secs: i64 = env::var("WEATHER_CACHE_TTL_SECS")
            .ok()
            .and_then(|s| s.parse().ok())
            .unwrap_or(300); // 5 minutes

        Self {
            arango,
            weather,
            tracked: RwLock::new(HashMap::new()),
            weather_cache_ttl_secs,
            enrich_weather,
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// EVENT PROCESSING
// ═══════════════════════════════════════════════════════════════════════════

async fn process_flight_event(state: &Arc<AppState>, event: FlightEvent) {
    let now = Utc::now();
    let icao24 = event.icao24.clone();

    // Get or compute 8D vector
    let atc_d_vec = event.d_vec.unwrap_or_else(|| compute_atc_8d(&event));

    // Check if we need to fetch weather
    let mut weather_d_vec: Option<[f64; 8]> = None;
    let mut weather_temp: Option<f64> = None;
    let mut weather_wind: Option<f64> = None;
    let mut weather_vis: Option<f64> = None;

    if state.enrich_weather {
        if let Some(weather_client) = &state.weather {
            // Check cache
            let needs_fetch = {
                let tracked = state.tracked.read().await;
                if let Some(aircraft) = tracked.get(&icao24) {
                    match aircraft.last_weather_fetch {
                        Some(fetch_time) => {
                            now.signed_duration_since(fetch_time).num_seconds()
                                > state.weather_cache_ttl_secs
                        }
                        None => true,
                    }
                } else {
                    true
                }
            };

            if needs_fetch {
                match weather_client
                    .fetch_weather(event.latitude, event.longitude, event.altitude_m)
                    .await
                {
                    Ok(weather) => {
                        weather_d_vec = Some(weather.d_vec);
                        weather_temp = weather.temperature_c;
                        weather_wind = weather.wind_speed_ms;
                        weather_vis = weather.visibility_m;

                        // Update cache
                        let mut tracked = state.tracked.write().await;
                        let entry = tracked.entry(icao24.clone()).or_insert(TrackedAircraft {
                            event: event.clone(),
                            weather: None,
                            last_weather_fetch: None,
                        });
                        entry.weather = Some(weather);
                        entry.last_weather_fetch = Some(now);
                    }
                    Err(e) => {
                        warn!("Weather fetch failed for {}: {}", icao24, e);
                    }
                }
            } else {
                // Use cached weather
                let tracked = state.tracked.read().await;
                if let Some(aircraft) = tracked.get(&icao24) {
                    if let Some(ref weather) = aircraft.weather {
                        weather_d_vec = Some(weather.d_vec);
                        weather_temp = weather.temperature_c;
                        weather_wind = weather.wind_speed_ms;
                        weather_vis = weather.visibility_m;
                    }
                }
            }
        }
    }

    // Fuse ATC + Weather
    let fused_d_vec = fuse_atc_weather(&atc_d_vec, weather_d_vec.as_ref());

    // Build world patch
    let patch = AtcWorldPatch {
        _key: format!("atc_{}_{}", icao24, now.timestamp()),
        scale: "planetary".to_string(),
        context: "planetary:atc_live".to_string(),
        center_lat: event.latitude,
        center_lon: event.longitude,
        center_alt_m: event.altitude_m,
        timestamp: now,
        d_vec: atc_d_vec,
        icao24: event.icao24,
        callsign: event.callsign,
        origin_country: event.origin_country,
        category: event.category,
        velocity_ms: event.velocity_ms,
        heading_deg: event.heading_deg,
        vertical_rate_ms: event.vertical_rate_ms,
        is_predicted: event.is_predicted,
        uncertainty: event.uncertainty,
        weather_d_vec,
        temperature_c: weather_temp,
        wind_speed_ms: weather_wind,
        visibility_m: weather_vis,
        fused_d_vec,
    };

    // Write to ArangoDB
    if let Err(e) = state.arango.upsert_patch(&patch).await {
        error!("Failed to write ATC patch: {}", e);
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// MAIN
// ═══════════════════════════════════════════════════════════════════════════

#[tokio::main]
async fn main() {
    env_logger::init();

    info!("╔════════════════════════════════════════════════════════════╗");
    info!("║      GAIAOS ATC AGENT SERVICE v0.1.0                       ║");
    info!("║      NATS → Weather Fusion → World Patches                 ║");
    info!("╚════════════════════════════════════════════════════════════╝");

    // Configuration
    let nats_url = env::var("NATS_URL").unwrap_or_else(|_| "nats://127.0.0.1:4222".to_string());
    let arango_url = env::var("ARANGO_URL").unwrap_or_else(|_| "http://arangodb:8529".to_string());
    let db_name = env::var("ARANGO_DB").unwrap_or_else(|_| "gaiaos".to_string());
    let collection = env::var("ARANGO_WORLD_PATCHES_COLLECTION")
        .unwrap_or_else(|_| "world_patches".to_string());
    let weather_url = env::var("WEATHER_INGEST_URL").ok();

    info!("NATS URL: {}", nats_url);
    info!("ArangoDB: {}", arango_url);
    info!("Database: {}", db_name);
    info!("Collection: {}", collection);
    info!(
        "Weather enrichment: {}",
        if weather_url.is_some() {
            "enabled"
        } else {
            "disabled"
        }
    );

    // Initialize clients
    let arango = ArangoClient::new(arango_url, db_name, collection);
    let weather = weather_url.map(WeatherClient::new);

    // Ensure collection exists
    if let Err(e) = arango.ensure_collection().await {
        error!("Failed to ensure collection: {}", e);
    }

    let state = Arc::new(AppState::new(arango, weather));

    // Connect to NATS
    info!("Connecting to NATS: {}", nats_url);
    let nc = loop {
        match async_nats::connect(&nats_url).await {
            Ok(client) => {
                info!("✓ Connected to NATS");
                break client;
            }
            Err(e) => {
                warn!("NATS connection failed: {}, retrying in 5s...", e);
                tokio::time::sleep(std::time::Duration::from_secs(5)).await;
            }
        }
    };

    // Subscribe to ATC events
    let subject = "atc.aircraft.state";
    info!("Subscribing to: {}", subject);

    let mut subscriber = match nc.subscribe(subject.to_string()).await {
        Ok(sub) => {
            info!("✓ Subscribed to {}", subject);
            sub
        }
        Err(e) => {
            error!("Failed to subscribe: {}", e);
            return;
        }
    };

    // Process messages
    info!("🛫 ATC Agent ready, processing events...");

    let mut event_count: u64 = 0;
    let mut last_log = Utc::now();

    while let Some(msg) = subscriber.next().await {
        match serde_json::from_slice::<FlightEvent>(&msg.payload) {
            Ok(event) => {
                let state_clone = state.clone();
                tokio::spawn(async move {
                    process_flight_event(&state_clone, event).await;
                });

                event_count += 1;

                // Log stats every 30 seconds
                let now = Utc::now();
                if now.signed_duration_since(last_log).num_seconds() >= 30 {
                    let tracked_count = state.tracked.read().await.len();
                    info!(
                        "📊 Stats: {} events processed, {} aircraft tracked",
                        event_count, tracked_count
                    );
                    last_log = now;
                }
            }
            Err(e) => {
                warn!("Failed to parse FlightEvent: {}", e);
            }
        }
    }

    warn!("NATS subscription ended");
}

// ═══════════════════════════════════════════════════════════════════════════
// HELPERS
// ═══════════════════════════════════════════════════════════════════════════

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

// ═══════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_fuse_atc_weather() {
        let atc = [0.5, 0.5, 0.5, 0.5, 0.8, 0.3, 0.9, 0.1];
        let weather = [0.5, 0.5, 0.0, 0.5, 0.2, 0.4, 0.6, 0.5];

        let fused = fuse_atc_weather(&atc, Some(&weather));

        // D0-D3 should match ATC
        assert_eq!(fused[0], atc[0]);
        assert_eq!(fused[1], atc[1]);
        assert_eq!(fused[2], atc[2]);
        assert_eq!(fused[3], atc[3]);

        // D4 should be reduced by visibility
        assert!(fused[4] < atc[4]);

        // D5 should be increased by weather risks
        assert!(fused[5] > atc[5]);

        // D7 should be at least baseline
        assert!(fused[7] >= 0.1);
    }

    #[test]
    fn test_compute_atc_8d() {
        let event = FlightEvent {
            icao24: "abc123".to_string(),
            callsign: "TEST123".to_string(),
            origin_country: "US".to_string(),
            latitude: 40.0,
            longitude: -74.0,
            altitude_m: 10000.0,
            altitude_ft: 32808.0,
            velocity_ms: 250.0,
            ground_speed_kts: 485.0,
            heading_deg: 90.0,
            vertical_rate_ms: 0.0,
            vertical_rate_fpm: 0.0,
            timestamp: Utc::now(),
            timestamp_unix: Utc::now().timestamp(),
            category: Some(4),
            source: "opensky".to_string(),
            is_predicted: false,
            d_vec: None,
            uncertainty: 0.0,
        };

        let d_vec = compute_atc_8d(&event);

        // Check ranges
        assert!(d_vec[0] >= -1.0 && d_vec[0] <= 1.0); // lon
        assert!(d_vec[1] >= -1.0 && d_vec[1] <= 1.0); // lat
        assert!(d_vec[2] >= 0.0 && d_vec[2] <= 1.0); // alt
        assert!(d_vec[3] >= 0.0 && d_vec[3] <= 1.0); // time
        assert!(d_vec[4] >= 0.0 && d_vec[4] <= 1.0); // intent
        assert!(d_vec[5] >= 0.0 && d_vec[5] <= 1.0); // risk
        assert!(d_vec[6] >= 0.0 && d_vec[6] <= 1.0); // compliance
        assert!(d_vec[7] >= 0.0 && d_vec[7] <= 1.0); // uncertainty
    }
}

