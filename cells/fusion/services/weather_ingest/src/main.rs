//! GaiaOS Weather Ingest Service
//!
//! Open-Meteo global weather data → 8D world_patches in ArangoDB
//! Provides HTTP endpoint for point queries + background grid refresh

use axum::{
    extract::{Query, State},
    http::StatusCode,
    routing::{get, post},
    Json, Router,
};
use chrono::{DateTime, Timelike, Utc};
use log::{error, info, warn};
use serde::{Deserialize, Serialize};
use std::{collections::HashMap, env, sync::Arc};
use tokio::{sync::RwLock, time::{sleep, Duration}};
use tower_http::cors::{Any, CorsLayer};

// ═══════════════════════════════════════════════════════════════════════════
// MODELS
// ═══════════════════════════════════════════════════════════════════════════

/// Weather data from Open-Meteo API
#[derive(Debug, Deserialize)]
struct OpenMeteoResponse {
    latitude: f64,
    longitude: f64,
    elevation: Option<f64>,
    current: Option<CurrentWeather>,
    hourly: Option<HourlyWeather>,
}

#[derive(Debug, Deserialize)]
struct CurrentWeather {
    time: String,
    temperature_2m: Option<f64>,
    relative_humidity_2m: Option<f64>,
    apparent_temperature: Option<f64>,
    precipitation: Option<f64>,
    rain: Option<f64>,
    showers: Option<f64>,
    snowfall: Option<f64>,
    weather_code: Option<i64>,
    cloud_cover: Option<f64>,
    pressure_msl: Option<f64>,
    surface_pressure: Option<f64>,
    wind_speed_10m: Option<f64>,
    wind_direction_10m: Option<f64>,
    wind_gusts_10m: Option<f64>,
}

#[derive(Debug, Deserialize)]
struct HourlyWeather {
    time: Vec<String>,
    temperature_2m: Option<Vec<f64>>,
    visibility: Option<Vec<f64>>,
    wind_speed_10m: Option<Vec<f64>>,
    cloud_cover: Option<Vec<f64>>,
}

/// 8D Weather Vector for world_patches
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Weather8D {
    pub d0: f64, // Longitude normalized [-1, 1]
    pub d1: f64, // Latitude normalized [-1, 1]
    pub d2: f64, // Altitude normalized [0, 1]
    pub d3: f64, // Time of day [0, 1]
    pub d4: f64, // Temperature normalized [-1, 1] (cold to hot)
    pub d5: f64, // Precipitation risk [0, 1]
    pub d6: f64, // Visibility quality [0, 1] (1 = clear)
    pub d7: f64, // Wind severity [0, 1]
}

impl Weather8D {
    pub fn to_array(&self) -> [f64; 8] {
        [self.d0, self.d1, self.d2, self.d3, self.d4, self.d5, self.d6, self.d7]
    }
}

/// World patch document for ArangoDB
#[derive(Debug, Serialize)]
struct WorldPatch {
    _key: String,
    scale: String,
    context: String,
    center_lat: f64,
    center_lon: f64,
    center_alt_m: f64,
    timestamp: DateTime<Utc>,
    d_vec: [f64; 8],
    // Weather-specific fields
    temperature_c: Option<f64>,
    humidity_pct: Option<f64>,
    wind_speed_ms: Option<f64>,
    wind_dir_deg: Option<f64>,
    visibility_m: Option<f64>,
    cloud_cover_pct: Option<f64>,
    precipitation_mm: Option<f64>,
    weather_code: Option<i64>,
    uncertainty: f64,
}

/// Point query request
#[derive(Debug, Deserialize)]
pub struct PointQueryParams {
    lat: f64,
    lon: f64,
    #[serde(default)]
    alt: Option<f64>,
}

/// Point query response
#[derive(Debug, Clone, Serialize)]
pub struct WeatherPointResponse {
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
            .user_agent("GaiaOS-Weather-Ingest/0.1")
            .timeout(Duration::from_secs(30))
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

        // Collection doesn't exist, create it
        let create_url = format!("{}/_db/{}/_api/collection", self.base_url, self.db_name);
        let body = serde_json::json!({
            "name": self.collection,
            "type": 2  // document collection
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
        patch: &WorldPatch,
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
}

// ═══════════════════════════════════════════════════════════════════════════
// OPEN-METEO CLIENT
// ═══════════════════════════════════════════════════════════════════════════

struct OpenMeteoClient {
    http: reqwest::Client,
    base_url: String,
}

impl OpenMeteoClient {
    fn new() -> Self {
        let http = reqwest::Client::builder()
            .user_agent("GaiaOS-Weather-Ingest/0.1")
            .timeout(Duration::from_secs(30))
            .build()
            .expect("failed to build reqwest client");

        Self {
            http,
            base_url: "https://api.open-meteo.com/v1/forecast".to_string(),
        }
    }

    async fn fetch_weather(
        &self,
        lat: f64,
        lon: f64,
    ) -> Result<OpenMeteoResponse, Box<dyn std::error::Error + Send + Sync>> {
        let url = format!(
            "{}?latitude={}&longitude={}&current=temperature_2m,relative_humidity_2m,apparent_temperature,precipitation,rain,showers,snowfall,weather_code,cloud_cover,pressure_msl,surface_pressure,wind_speed_10m,wind_direction_10m,wind_gusts_10m&hourly=temperature_2m,visibility,wind_speed_10m,cloud_cover&forecast_days=1",
            self.base_url, lat, lon
        );

        let resp = self.http.get(&url).send().await?;

        if !resp.status().is_success() {
            let status = resp.status();
            let text = resp.text().await.unwrap_or_default();
            return Err(format!("Open-Meteo error {}: {}", status, text).into());
        }

        let data: OpenMeteoResponse = resp.json().await?;
        Ok(data)
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// 8D CONVERSION
// ═══════════════════════════════════════════════════════════════════════════

/// Convert weather data to 8D vector
fn weather_to_8d(
    lat: f64,
    lon: f64,
    alt_m: f64,
    timestamp: DateTime<Utc>,
    current: &CurrentWeather,
    hourly: Option<&HourlyWeather>,
) -> Weather8D {
    // D0: Longitude normalized [-1, 1]
    let d0 = lon / 180.0;

    // D1: Latitude normalized [-1, 1]
    let d1 = lat / 90.0;

    // D2: Altitude normalized [0, 1] (assuming 15km max)
    let d2 = (alt_m / 15000.0).clamp(0.0, 1.0);

    // D3: Time of day [0, 1]
    let seconds_since_midnight = timestamp.time().num_seconds_from_midnight() as f64;
    let d3 = (seconds_since_midnight / 86400.0).clamp(0.0, 1.0);

    // D4: Temperature normalized [-1, 1] (-50°C to +50°C range)
    let temp_c = current.temperature_2m.unwrap_or(15.0);
    let d4 = (temp_c / 50.0).clamp(-1.0, 1.0);

    // D5: Precipitation risk [0, 1]
    let precip = current.precipitation.unwrap_or(0.0)
        + current.rain.unwrap_or(0.0)
        + current.showers.unwrap_or(0.0)
        + current.snowfall.unwrap_or(0.0) * 2.0; // Snow weighted higher
    let d5 = (precip / 20.0).clamp(0.0, 1.0); // 20mm = max risk

    // D6: Visibility quality [0, 1] (1 = excellent)
    // Get visibility from hourly if available
    let visibility_m = hourly
        .and_then(|h| h.visibility.as_ref())
        .and_then(|v| v.first().copied())
        .unwrap_or(10000.0);
    let cloud_cover = current.cloud_cover.unwrap_or(50.0);
    let visibility_factor = (visibility_m / 10000.0).clamp(0.0, 1.0);
    let cloud_factor = 1.0 - (cloud_cover / 100.0);
    let d6 = (visibility_factor * 0.7 + cloud_factor * 0.3).clamp(0.0, 1.0);

    // D7: Wind severity [0, 1]
    let wind_speed = current.wind_speed_10m.unwrap_or(0.0);
    let gusts = current.wind_gusts_10m.unwrap_or(wind_speed);
    let wind_severity = (gusts / 30.0).clamp(0.0, 1.0); // 30 m/s = severe
    let d7 = wind_severity;

    Weather8D {
        d0,
        d1,
        d2,
        d3,
        d4,
        d5,
        d6,
        d7,
    }
}

fn weather_code_to_description(code: Option<i64>) -> String {
    match code {
        Some(0) => "Clear sky".to_string(),
        Some(1) => "Mainly clear".to_string(),
        Some(2) => "Partly cloudy".to_string(),
        Some(3) => "Overcast".to_string(),
        Some(45) | Some(48) => "Fog".to_string(),
        Some(51) | Some(53) | Some(55) => "Drizzle".to_string(),
        Some(56) | Some(57) => "Freezing drizzle".to_string(),
        Some(61) | Some(63) | Some(65) => "Rain".to_string(),
        Some(66) | Some(67) => "Freezing rain".to_string(),
        Some(71) | Some(73) | Some(75) => "Snow".to_string(),
        Some(77) => "Snow grains".to_string(),
        Some(80) | Some(81) | Some(82) => "Rain showers".to_string(),
        Some(85) | Some(86) => "Snow showers".to_string(),
        Some(95) => "Thunderstorm".to_string(),
        Some(96) | Some(99) => "Thunderstorm with hail".to_string(),
        _ => "Unknown".to_string(),
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// APPLICATION STATE
// ═══════════════════════════════════════════════════════════════════════════

struct AppState {
    arango: ArangoClient,
    meteo: OpenMeteoClient,
    cache: RwLock<HashMap<String, (DateTime<Utc>, WeatherPointResponse)>>,
}

impl AppState {
    fn new(arango: ArangoClient) -> Self {
        Self {
            arango,
            meteo: OpenMeteoClient::new(),
            cache: RwLock::new(HashMap::new()),
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// HTTP HANDLERS
// ═══════════════════════════════════════════════════════════════════════════

/// Health check endpoint
async fn health() -> Json<serde_json::Value> {
    Json(serde_json::json!({
        "status": "healthy",
        "service": "weather-ingest",
        "version": "0.1.0"
    }))
}

/// Query weather for a specific point
async fn ingest_point(
    State(state): State<Arc<AppState>>,
    Query(params): Query<PointQueryParams>,
) -> Result<Json<WeatherPointResponse>, (StatusCode, String)> {
    let lat = params.lat;
    let lon = params.lon;
    let alt = params.alt.unwrap_or(0.0);

    // Check cache (5 minute TTL)
    let cache_key = format!("{:.2}_{:.2}", lat, lon);
    {
        let cache = state.cache.read().await;
        if let Some((cached_at, response)) = cache.get(&cache_key) {
            if Utc::now().signed_duration_since(*cached_at).num_seconds() < 300 {
                return Ok(Json(response.clone()));
            }
        }
    }

    // Fetch from Open-Meteo
    let weather = state
        .meteo
        .fetch_weather(lat, lon)
        .await
        .map_err(|e| (StatusCode::BAD_GATEWAY, format!("Weather fetch failed: {}", e)))?;

    let now = Utc::now();
    let current = weather.current.as_ref().ok_or((
        StatusCode::BAD_GATEWAY,
        "No current weather data".to_string(),
    ))?;

    // Convert to 8D
    let weather_8d = weather_to_8d(lat, lon, alt, now, current, weather.hourly.as_ref());
    let d_vec = weather_8d.to_array();

    // Get visibility from hourly
    let visibility_m = weather
        .hourly
        .as_ref()
        .and_then(|h| h.visibility.as_ref())
        .and_then(|v| v.first().copied());

    // Build response
    let response = WeatherPointResponse {
        success: true,
        latitude: lat,
        longitude: lon,
        altitude_m: alt,
        timestamp: now,
        d_vec,
        temperature_c: current.temperature_2m,
        humidity_pct: current.relative_humidity_2m,
        wind_speed_ms: current.wind_speed_10m,
        visibility_m,
        weather_description: weather_code_to_description(current.weather_code),
    };

    // Write to ArangoDB
    let patch = WorldPatch {
        _key: format!("weather_{:.4}_{:.4}_{}", lat, lon, now.timestamp()),
        scale: "planetary".to_string(),
        context: "planetary:weather".to_string(),
        center_lat: lat,
        center_lon: lon,
        center_alt_m: alt,
        timestamp: now,
        d_vec,
        temperature_c: current.temperature_2m,
        humidity_pct: current.relative_humidity_2m,
        wind_speed_ms: current.wind_speed_10m,
        wind_dir_deg: current.wind_direction_10m,
        visibility_m,
        cloud_cover_pct: current.cloud_cover,
        precipitation_mm: current.precipitation,
        weather_code: current.weather_code,
        uncertainty: 0.1, // Weather data has low uncertainty
    };

    if let Err(e) = state.arango.upsert_patch(&patch).await {
        warn!("Failed to write weather patch to Arango: {}", e);
    }

    // Update cache
    {
        let mut cache = state.cache.write().await;
        cache.insert(cache_key, (now, response.clone()));
    }

    Ok(Json(response))
}

/// Bulk grid ingest (POST with list of coordinates)
#[derive(Debug, Deserialize)]
struct BulkIngestRequest {
    points: Vec<PointQueryParams>,
}

#[derive(Debug, Serialize)]
struct BulkIngestResponse {
    success: bool,
    ingested: usize,
    failed: usize,
}

async fn bulk_ingest(
    State(state): State<Arc<AppState>>,
    Json(request): Json<BulkIngestRequest>,
) -> Result<Json<BulkIngestResponse>, (StatusCode, String)> {
    let mut ingested = 0;
    let mut failed = 0;

    for point in &request.points {
        match state.meteo.fetch_weather(point.lat, point.lon).await {
            Ok(weather) => {
                if let Some(current) = &weather.current {
                    let now = Utc::now();
                    let alt = point.alt.unwrap_or(0.0);
                    let weather_8d =
                        weather_to_8d(point.lat, point.lon, alt, now, current, weather.hourly.as_ref());

                    let patch = WorldPatch {
                        _key: format!(
                            "weather_{:.4}_{:.4}_{}",
                            point.lat,
                            point.lon,
                            now.timestamp()
                        ),
                        scale: "planetary".to_string(),
                        context: "planetary:weather".to_string(),
                        center_lat: point.lat,
                        center_lon: point.lon,
                        center_alt_m: alt,
                        timestamp: now,
                        d_vec: weather_8d.to_array(),
                        temperature_c: current.temperature_2m,
                        humidity_pct: current.relative_humidity_2m,
                        wind_speed_ms: current.wind_speed_10m,
                        wind_dir_deg: current.wind_direction_10m,
                        visibility_m: weather
                            .hourly
                            .as_ref()
                            .and_then(|h| h.visibility.as_ref())
                            .and_then(|v| v.first().copied()),
                        cloud_cover_pct: current.cloud_cover,
                        precipitation_mm: current.precipitation,
                        weather_code: current.weather_code,
                        uncertainty: 0.1,
                    };

                    if state.arango.upsert_patch(&patch).await.is_ok() {
                        ingested += 1;
                    } else {
                        failed += 1;
                    }
                } else {
                    failed += 1;
                }
            }
            Err(e) => {
                warn!("Weather fetch failed for ({}, {}): {}", point.lat, point.lon, e);
                failed += 1;
            }
        }

        // Rate limit: 1 request per 100ms
        sleep(Duration::from_millis(100)).await;
    }

    Ok(Json(BulkIngestResponse {
        success: failed == 0,
        ingested,
        failed,
    }))
}

// ═══════════════════════════════════════════════════════════════════════════
// BACKGROUND GRID REFRESH
// ═══════════════════════════════════════════════════════════════════════════

/// Global grid points for background refresh (major airports + waypoints)
fn get_global_grid_points() -> Vec<(f64, f64, &'static str)> {
    vec![
        // North America
        (40.6413, -73.7781, "JFK"),
        (33.9425, -118.4081, "LAX"),
        (41.9742, -87.9073, "ORD"),
        (33.6407, -84.4277, "ATL"),
        (37.6213, -122.3790, "SFO"),
        (25.7959, -80.2870, "MIA"),
        (47.4502, -122.3088, "SEA"),
        (39.8561, -104.6737, "DEN"),
        (29.9902, -95.3368, "IAH"),
        (42.3656, -71.0096, "BOS"),
        // Europe
        (51.4700, -0.4543, "LHR"),
        (49.0097, 2.5479, "CDG"),
        (52.5597, 13.2877, "BER"),
        (50.0379, 8.5622, "FRA"),
        (41.2971, 2.0785, "BCN"),
        (40.4719, -3.5626, "MAD"),
        (45.4654, 9.1866, "MXP"),
        (52.3105, 4.7683, "AMS"),
        (47.4647, 8.5492, "ZRH"),
        (55.6180, 12.6508, "CPH"),
        // Asia-Pacific
        (35.5494, 139.7798, "HND"),
        (22.3080, 113.9185, "HKG"),
        (1.3644, 103.9915, "SIN"),
        (25.2532, 55.3657, "DXB"),
        (31.1443, 121.8083, "PVG"),
        (37.4602, 126.4407, "ICN"),
        (13.6900, 100.7501, "BKK"),
        (-33.9399, 151.1753, "SYD"),
        (19.0896, 72.8656, "BOM"),
        (28.5562, 77.1000, "DEL"),
        // Middle East / Africa
        (25.2528, 55.3644, "DXB"),
        (24.4539, 54.3773, "AUH"),
        (-1.3192, 36.9278, "NBO"),
        (-26.1392, 28.2460, "JNB"),
        (30.1219, 31.4056, "CAI"),
        // South America
        (-23.4356, -46.4731, "GRU"),
        (-34.8222, -58.5358, "EZE"),
        (-33.3930, -70.7858, "SCL"),
        (4.7016, -74.1469, "BOG"),
        (-12.0219, -77.1143, "LIM"),
    ]
}

async fn background_grid_refresh(state: Arc<AppState>) {
    let grid_points = get_global_grid_points();
    let refresh_interval = Duration::from_secs(1800); // 30 minutes

    loop {
        info!("Starting global weather grid refresh ({} points)...", grid_points.len());

        let mut success_count = 0;
        let mut fail_count = 0;

        for (lat, lon, name) in &grid_points {
            match state.meteo.fetch_weather(*lat, *lon).await {
                Ok(weather) => {
                    if let Some(current) = &weather.current {
                        let now = Utc::now();
                        let weather_8d = weather_to_8d(*lat, *lon, 0.0, now, current, weather.hourly.as_ref());

                        let patch = WorldPatch {
                            _key: format!("weather_grid_{}_{}", name, now.timestamp() / 1800),
                            scale: "planetary".to_string(),
                            context: "planetary:weather".to_string(),
                            center_lat: *lat,
                            center_lon: *lon,
                            center_alt_m: weather.elevation.unwrap_or(0.0),
                            timestamp: now,
                            d_vec: weather_8d.to_array(),
                            temperature_c: current.temperature_2m,
                            humidity_pct: current.relative_humidity_2m,
                            wind_speed_ms: current.wind_speed_10m,
                            wind_dir_deg: current.wind_direction_10m,
                            visibility_m: weather
                                .hourly
                                .as_ref()
                                .and_then(|h| h.visibility.as_ref())
                                .and_then(|v| v.first().copied()),
                            cloud_cover_pct: current.cloud_cover,
                            precipitation_mm: current.precipitation,
                            weather_code: current.weather_code,
                            uncertainty: 0.1,
                        };

                        if state.arango.upsert_patch(&patch).await.is_ok() {
                            success_count += 1;
                        } else {
                            fail_count += 1;
                        }
                    }
                }
                Err(e) => {
                    warn!("Grid refresh failed for {}: {}", name, e);
                    fail_count += 1;
                }
            }

            // Rate limit
            sleep(Duration::from_millis(200)).await;
        }

        info!(
            "Grid refresh complete: {} succeeded, {} failed",
            success_count, fail_count
        );

        sleep(refresh_interval).await;
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// MAIN
// ═══════════════════════════════════════════════════════════════════════════

#[tokio::main]
async fn main() {
    env_logger::init();

    info!("╔════════════════════════════════════════════════════════════╗");
    info!("║      GAIAOS WEATHER INGEST SERVICE v0.1.0                  ║");
    info!("║      Open-Meteo → 8D World Patches                         ║");
    info!("╚════════════════════════════════════════════════════════════╝");

    let host = env::var("HOST").unwrap_or_else(|_| "0.0.0.0".to_string());
    let port: u16 = env::var("PORT")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(8750);

    let arango_url = env::var("ARANGO_URL").unwrap_or_else(|_| "http://arangodb:8529".to_string());
    let db_name = env::var("ARANGO_DB").unwrap_or_else(|_| "gaiaos".to_string());
    let collection = env::var("ARANGO_WORLD_PATCHES_COLLECTION")
        .unwrap_or_else(|_| "world_patches".to_string());

    info!("ArangoDB: {}", arango_url);
    info!("Database: {}", db_name);
    info!("Collection: {}", collection);

    let arango = ArangoClient::new(arango_url, db_name, collection);

    // Ensure collection exists
    if let Err(e) = arango.ensure_collection().await {
        error!("Failed to ensure collection: {}", e);
    }

    let state = Arc::new(AppState::new(arango));

    // Start background grid refresh
    let bg_state = state.clone();
    tokio::spawn(async move {
        // Initial delay to let things settle
        sleep(Duration::from_secs(10)).await;
        background_grid_refresh(bg_state).await;
    });

    // Build router
    let cors = CorsLayer::new()
        .allow_origin(Any)
        .allow_methods(Any)
        .allow_headers(Any);

    let app = Router::new()
        .route("/health", get(health))
        .route("/ingest/point", get(ingest_point))
        .route("/ingest/bulk", post(bulk_ingest))
        .layer(cors)
        .with_state(state);

    let addr = format!("{}:{}", host, port);
    info!("🌤️  Weather Ingest listening on http://{}", addr);

    let listener = tokio::net::TcpListener::bind(&addr).await.unwrap();
    axum::serve(listener, app).await.unwrap();
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

