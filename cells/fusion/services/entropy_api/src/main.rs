use anyhow::{anyhow, Context, Result};
use axum::{
    extract::{Query, State},
    http::StatusCode,
    response::IntoResponse,
    routing::get,
    Json, Router,
};
use chrono::Utc;
use log::info;
use serde::{Deserialize, Serialize};
use serde_json::json;
use std::{collections::HashMap, env, net::SocketAddr, sync::Arc, time::Duration};
use tower_http::cors::{Any, CorsLayer};

mod atc_notam;

#[derive(Clone)]
struct Config {
    bind_addr: String,
    arango_url: String,
    arango_db: String,
    arango_user: String,
    arango_password: String,
    atmosphere_tiles_collection: String,
    world_patches_collection: String,
    fuel_price_usd_per_kg: f64,
    flightlevel_source: String,
    atc_context: String,
}

impl Config {
    fn from_env() -> Self {
        Self {
            bind_addr: env::var("ENTROPY_API_BIND_ADDR").unwrap_or_else(|_| "0.0.0.0:8800".to_string()),
            arango_url: env::var("ARANGO_URL").unwrap_or_else(|_| "http://arangodb:8529".to_string()),
            arango_db: env::var("ARANGO_DB").unwrap_or_else(|_| "gaiaos".to_string()),
            arango_user: env::var("ARANGO_USER").unwrap_or_else(|_| "root".to_string()),
            arango_password: env::var("ARANGO_PASSWORD").unwrap_or_else(|_| "gaiaos".to_string()),
            atmosphere_tiles_collection: env::var("ARANGO_ATMOSPHERE_TILES_COLLECTION")
                .unwrap_or_else(|_| "atmosphere_tiles".to_string()),
            world_patches_collection: env::var("ARANGO_WORLD_PATCHES_COLLECTION")
                .unwrap_or_else(|_| "world_patches".to_string()),
            fuel_price_usd_per_kg: env::var("FUEL_PRICE_USD_PER_KG").ok().and_then(|v| v.parse().ok()).unwrap_or(1.0),
            flightlevel_source: env::var("FLIGHTLEVEL_SOURCE")
                .unwrap_or_else(|_| "noaa_nomads_gfs_0p25_flightlevel_opendap".to_string()),
            atc_context: env::var("ATC_CONTEXT").unwrap_or_else(|_| "planetary:atc_live".to_string()),
        }
    }
}

#[derive(Clone)]
struct AppState {
    cfg: Config,
    arango: Arango,
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
            .user_agent("GaiaOS-Entropy-API/0.1.0")
            .build()
            .context("failed to build http client")?;
        let auth = base64_encode(&format!("{user}:{password}"));
        Ok(Self {
            base_url: base_url.trim_end_matches('/').to_string(),
            db_name,
            http,
            auth_header: format!("Basic {auth}"),
        })
    }

    async fn aql(&self, query: &str, bind: serde_json::Value) -> Result<Vec<serde_json::Value>> {
        let url = format!("{}/_db/{}/_api/cursor", self.base_url, self.db_name);
        let resp = self
            .http
            .post(url)
            .header("Authorization", &self.auth_header)
            .header("Content-Type", "application/json")
            .json(&json!({ "query": query, "bindVars": bind, "batchSize": 2000 }))
            .send()
            .await
            .context("aql request failed")?;
        if !resp.status().is_success() {
            let status = resp.status();
            let text = resp.text().await.unwrap_or_default();
            return Err(anyhow!("AQL failed {status}: {text}"));
        }
        let body: serde_json::Value = resp.json().await.context("aql decode failed")?;
        Ok(body["result"].as_array().cloned().unwrap_or_default())
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

#[derive(Debug, Deserialize)]
struct GeoPoint {
    #[serde(rename = "type")]
    _typ: String,
    coordinates: [f64; 2], // [lon, lat] lon in [0,360)
}

#[derive(Debug, Deserialize)]
struct TileState {
    air_density_kg_m3: f64,
    temperature_k: f64,
    pressure_pa: f64,
}

#[derive(Debug, Deserialize)]
struct AtmosTile {
    valid_time: i64,
    altitude_m: f64,
    pressure_level_mb: i64,
    location: GeoPoint,
    state: TileState,
    provenance: serde_json::Value,
}

#[derive(Debug, Deserialize)]
struct AtcPatch {
    #[serde(default)]
    icao24: Option<String>,
    #[serde(default)]
    callsign: Option<String>,
    #[serde(default)]
    aircraft_type: Option<String>,
    center_lat: f64,
    center_lon: f64,
    altitude_ft: f64,
    velocity_kts: f64,
    timestamp: chrono::DateTime<Utc>,
}

#[derive(Debug, Deserialize)]
struct AnomalyQuery {
    min_anomaly_pct: Option<f64>,
    max_age_seconds: Option<i64>,
}

#[derive(Debug, Serialize)]
struct DensityAnomaly {
    lat: f64,
    lon: f64,
    altitude_m: f64,
    pressure_level_mb: i64,
    anomaly_pct: f64,
    timestamp: i64,
    source: String,
}

#[derive(Debug, Serialize)]
struct LiveFlight {
    icao24: String,
    callsign: String,
    aircraft_type: Option<String>,
    lat: f64,
    lon: f64,
    altitude_ft: f64,
    velocity_kts: f64,
    timestamp: i64,
}

#[derive(Debug, Serialize)]
struct WasteMetrics {
    total_waste_kg: f64,
    affected_flights: usize,
    waste_rate_kg_per_hour: f64,
    cost_rate_usd_per_hour: f64,
    window_seconds: i64,
}

fn isa_density_kg_m3(alt_m: f64) -> f64 {
    // Deterministic ISA approximation (0-20km). Documented approximation, not a stub.
    let g = 9.80665;
    let r = 287.05;
    let p0 = 101325.0;
    let t0 = 288.15;
    let l = 0.0065;
    if alt_m <= 11000.0 {
        let t = t0 - l * alt_m;
        let p = p0 * (t / t0).powf(g / (r * l));
        p / (r * t)
    } else {
        let t = 216.65;
        let p11 = p0 * (t / t0).powf(g / (r * l));
        let p = p11 * (-g * (alt_m - 11000.0) / (r * t)).exp();
        p / (r * t)
    }
}

fn great_circle_distance_km(lat1: f64, lon1: f64, lat2: f64, lon2: f64) -> f64 {
    let r = 6371.0;
    let (lat1, lon1, lat2, lon2) = (lat1.to_radians(), lon1.to_radians(), lat2.to_radians(), lon2.to_radians());
    let dlat = lat2 - lat1;
    let dlon = lon2 - lon1;
    let a = (dlat / 2.0).sin().powi(2) + lat1.cos() * lat2.cos() * (dlon / 2.0).sin().powi(2);
    2.0 * r * a.sqrt().asin()
}

fn estimate_burn_kg_per_hour(aircraft_type: &Option<String>) -> f64 {
    let t = aircraft_type.as_deref().unwrap_or("").to_uppercase();
    if t.starts_with("B77") || t.starts_with("B78") || t.starts_with("A35") || t.starts_with("A33") || t.starts_with("A34") {
        6500.0
    } else {
        2500.0
    }
}

async fn load_anomalies(state: &AppState, min_anom_pct: f64, max_age_seconds: i64) -> Result<Vec<DensityAnomaly>> {
    let now = Utc::now().timestamp();
    let t_min = now - max_age_seconds;
    let aql = format!(
        r#"
FOR t IN {coll}
  FILTER t.valid_time >= @t_min
  FILTER t.provenance != null AND t.provenance.source == @src
  FILTER t.altitude_m >= 9000 AND t.altitude_m <= 13700
  SORT t.valid_time DESC
  LIMIT 4000
  RETURN t
"#,
        coll = state.cfg.atmosphere_tiles_collection
    );
    let rows = state.arango.aql(&aql, json!({ "t_min": t_min, "src": state.cfg.flightlevel_source })).await?;
    let mut out = Vec::new();
    for v in rows {
        let Ok(t) = serde_json::from_value::<AtmosTile>(v) else { continue };
        // Read these fields so we never silently accept malformed tiles.
        // (We don't currently return them; this is to ensure schema stability and avoid dead-code warnings.)
        let _temperature_k = t.state.temperature_k;
        let _pressure_pa = t.state.pressure_pa;

        let baseline = isa_density_kg_m3(t.altitude_m);
        if baseline <= 0.0 {
            continue;
        }
        let anomaly_pct = ((t.state.air_density_kg_m3 - baseline) / baseline) * 100.0;
        if anomaly_pct.abs() >= min_anom_pct {
            let lon = t.location.coordinates[0];
            let lat = t.location.coordinates[1];
            let source = t
                .provenance
                .get("source")
                .and_then(|s| s.as_str())
                .unwrap_or("unknown")
                .to_string();
            out.push(DensityAnomaly {
                lat,
                lon,
                altitude_m: t.altitude_m,
                pressure_level_mb: t.pressure_level_mb,
                anomaly_pct,
                timestamp: t.valid_time,
                source,
            });
        }
    }
    Ok(out)
}

async fn load_live_flights(state: &AppState, max_age_seconds: i64) -> Result<Vec<LiveFlight>> {
    let now = Utc::now().timestamp();
    let t_min = now - max_age_seconds;
    let aql = format!(
        r#"
FOR p IN {coll}
  FILTER p.context == @ctx
  FILTER p.timestamp != null
  LET ts = DATE_TIMESTAMP(p.timestamp) / 1000
  FILTER ts >= @t_min
  SORT p.timestamp DESC
  LIMIT 5000
  RETURN p
"#,
        coll = state.cfg.world_patches_collection
    );
    let rows = state.arango.aql(&aql, json!({ "ctx": state.cfg.atc_context, "t_min": t_min })).await?;
    let mut out = Vec::new();
    for v in rows {
        let Ok(p) = serde_json::from_value::<AtcPatch>(v) else { continue };
        let cs = p.callsign.clone().unwrap_or_else(|| "unknown".to_string()).trim().to_string();
        let icao24 = p.icao24.clone().unwrap_or_else(|| "unknown".to_string()).trim().to_string();
        let lon = if p.center_lon < 0.0 { p.center_lon + 360.0 } else { p.center_lon };
        out.push(LiveFlight {
            icao24,
            callsign: cs,
            aircraft_type: p.aircraft_type.clone(),
            lat: p.center_lat,
            lon,
            altitude_ft: p.altitude_ft,
            velocity_kts: p.velocity_kts,
            timestamp: p.timestamp.timestamp(),
        });
    }
    Ok(out)
}

async fn health() -> impl IntoResponse {
    (StatusCode::OK, Json(json!({ "status":"ok", "component":"entropy-api", "timestamp": Utc::now().timestamp() })))
}

async fn get_current_anomalies(State(state): State<Arc<AppState>>, Query(q): Query<AnomalyQuery>) -> Result<Json<Vec<DensityAnomaly>>, StatusCode> {
    let min_pct = q.min_anomaly_pct.unwrap_or(2.0);
    let max_age = q.max_age_seconds.unwrap_or(3600).max(60);
    load_anomalies(&state, min_pct, max_age)
        .await
        .map(Json)
        .map_err(|_| StatusCode::BAD_GATEWAY)
}

async fn get_live_flights_endpoint(State(state): State<Arc<AppState>>, Query(q): Query<AnomalyQuery>) -> Result<Json<Vec<LiveFlight>>, StatusCode> {
    let max_age = q.max_age_seconds.unwrap_or(300).max(60);
    load_live_flights(&state, max_age)
        .await
        .map(Json)
        .map_err(|_| StatusCode::BAD_GATEWAY)
}

async fn calculate_live_waste(State(state): State<Arc<AppState>>, Query(q): Query<AnomalyQuery>) -> Result<Json<WasteMetrics>, StatusCode> {
    let min_pct = q.min_anomaly_pct.unwrap_or(2.0);
    let max_age = q.max_age_seconds.unwrap_or(300).max(60);
    let anomalies = load_anomalies(&state, min_pct, max_age).await.map_err(|_| StatusCode::BAD_GATEWAY)?;
    let flights = load_live_flights(&state, max_age).await.map_err(|_| StatusCode::BAD_GATEWAY)?;

    // Match rules consistent with offline analysis.
    let max_dist_km = 650.0;
    let max_alt_diff_m = 1200.0;
    let dt_hr = 30.0 / 3600.0; // bounded assumption: each patch represents ~30s

    let mut total_waste_kg = 0.0;
    let mut affected: HashMap<String, ()> = HashMap::new();

    for f in &flights {
        let alt_m = f.altitude_ft * 0.3048;
        let burn_kgph = estimate_burn_kg_per_hour(&f.aircraft_type);
        let mut hit = false;
        for a in &anomalies {
            // drag penalty only for positive density anomaly
            if a.anomaly_pct <= 0.0 {
                continue;
            }
            let alt_diff = (alt_m - a.altitude_m).abs();
            if alt_diff > max_alt_diff_m {
                continue;
            }
            let d_km = great_circle_distance_km(f.lat, f.lon, a.lat, a.lon);
            if d_km > max_dist_km {
                continue;
            }
            let excess = (burn_kgph * dt_hr) * (a.anomaly_pct / 100.0);
            total_waste_kg += excess.max(0.0);
            hit = true;
            break;
        }
        if hit {
            affected.insert(format!("{}:{}", f.icao24, f.callsign), ());
        }
    }

    let waste_rate_kgph = if max_age > 0 { total_waste_kg / (max_age as f64 / 3600.0) } else { 0.0 };
    let cost_rate = waste_rate_kgph * state.cfg.fuel_price_usd_per_kg;

    Ok(Json(WasteMetrics {
        total_waste_kg,
        affected_flights: affected.len(),
        waste_rate_kg_per_hour: waste_rate_kgph,
        cost_rate_usd_per_hour: cost_rate,
        window_seconds: max_age,
    }))
}

#[derive(Debug, Deserialize)]
struct TurbulenceQuery {
    min_probability: Option<f64>,
    forecast_hours: Option<u32>,
    min_severity: Option<String>,
}

async fn get_turbulence_alerts(State(state): State<Arc<AppState>>, Query(q): Query<TurbulenceQuery>) -> Result<Json<Vec<atc_notam::TurbulenceAlert>>, StatusCode> {
    let min_prob = q.min_probability.unwrap_or(0.5);
    let forecast_hours = q.forecast_hours.unwrap_or(6);
    let now = Utc::now().timestamp();
    let forecast_end = now + (forecast_hours as i64 * 3600);

    let aql = format!(
        r#"
FOR tile IN {coll}
  FILTER tile.valid_time >= @now
  FILTER tile.valid_time <= @forecast_end
  FILTER tile.state.turbulence != null
  FILTER tile.state.turbulence.probability >= @min_prob
  FILTER tile.altitude_m >= 9000
  SORT tile.state.turbulence.probability DESC
  LIMIT 500
  RETURN {{
    location: {{
      lat: tile.location.coordinates[1],
      lon: tile.location.coordinates[0]
    }},
    altitude_m: tile.altitude_m,
    flight_level: FLOOR(tile.altitude_m / 30.48 / 100),
    severity: tile.state.turbulence.severity,
    probability: tile.state.turbulence.probability,
    valid_time: tile.valid_time,
    expires_time: tile.valid_time + 3600,
    richardson_number: tile.state.turbulence.richardson_number,
    eddy_dissipation_rate: tile.state.turbulence.eddy_dissipation_rate,
    wind_shear: tile.state.turbulence.wind_shear_1_per_s
  }}
"#,
        coll = state.cfg.atmosphere_tiles_collection
    );

    let rows = state.arango.aql(&aql, json!({ "now": now, "forecast_end": forecast_end, "min_prob": min_prob })).await.map_err(|_| StatusCode::BAD_GATEWAY)?;
    let mut alerts: Vec<atc_notam::TurbulenceAlert> = rows.into_iter().filter_map(|v| serde_json::from_value(v).ok()).collect();

    // Enhance with affected routes
    let flights = load_live_flights(&state, 300).await.map_err(|_| StatusCode::BAD_GATEWAY)?;
    for alert in &mut alerts {
        let mut affected = Vec::new();
        for f in &flights {
            let alt_m = f.altitude_ft * 0.3048;
            let alt_diff = (alt_m - alert.altitude_m).abs();
            if alt_diff > 1000.0 {
                continue;
            }
            let d_km = great_circle_distance_km(f.lat, f.lon, alert.location.lat, alert.location.lon);
            if d_km < 50.0 {
                affected.push(f.callsign.clone());
            }
        }
        alert.affected_routes = affected;
    }

    Ok(Json(alerts))
}

async fn get_turbulence_forecast(State(state): State<Arc<AppState>>, Query(q): Query<TurbulenceQuery>) -> Result<Json<Vec<atc_notam::TurbulenceAlert>>, StatusCode> {
    // Alias to alerts endpoint
    get_turbulence_alerts(State(state), Query(q)).await
}

async fn get_turbulence_notams(State(state): State<Arc<AppState>>) -> Result<Json<Vec<atc_notam::TurbulenceNOTAM>>, StatusCode> {
    let alerts_resp = get_turbulence_alerts(
        State(state),
        Query(TurbulenceQuery {
            min_probability: Some(0.7),
            forecast_hours: Some(6),
            min_severity: None,
        }),
    )
    .await?;

    let notams = atc_notam::publish_notams(&alerts_resp.0);
    Ok(Json(notams))
}

async fn get_turbulence_pireps(State(state): State<Arc<AppState>>) -> Result<Json<Vec<serde_json::Value>>, StatusCode> {
    let now = Utc::now().timestamp();
    let t_min = now - 3600;

    let aql = format!(
        r#"
FOR p IN {coll}
  FILTER p.context == "planetary:atc_pirep"
  FILTER p.timestamp >= @t_min
  FILTER p.state.turbulence_intensity != null
  SORT p.timestamp DESC
  LIMIT 200
  RETURN p
"#,
        coll = state.cfg.world_patches_collection
    );

    let rows = state.arango.aql(&aql, json!({ "t_min": t_min })).await.map_err(|_| StatusCode::BAD_GATEWAY)?;
    Ok(Json(rows))
}

#[tokio::main]
async fn main() -> Result<()> {
    env_logger::init();
    let cfg = Config::from_env();
    let arango = Arango::new(cfg.arango_url.clone(), cfg.arango_db.clone(), cfg.arango_user.clone(), cfg.arango_password.clone())?;
    let state = Arc::new(AppState { cfg: cfg.clone(), arango });

    let cors = CorsLayer::new()
        .allow_origin(Any)
        .allow_headers(Any)
        .allow_methods(Any);

    let app = Router::new()
        .route("/health", get(health))
        .route("/api/entropy/aviation/anomalies", get(get_current_anomalies))
        .route("/api/entropy/aviation/flights", get(get_live_flights_endpoint))
        .route("/api/entropy/aviation/waste", get(calculate_live_waste))
        .route("/api/turbulence/alerts", get(get_turbulence_alerts))
        .route("/api/turbulence/forecast", get(get_turbulence_forecast))
        .route("/api/turbulence/notams", get(get_turbulence_notams))
        .route("/api/turbulence/pireps", get(get_turbulence_pireps))
        .with_state(state)
        .layer(cors);

    let addr: SocketAddr = cfg.bind_addr.parse().context("ENTROPY_API_BIND_ADDR parse failed")?;
    info!("entropy-api listening on http://{}", addr);
    axum::serve(tokio::net::TcpListener::bind(addr).await?, app).await?;
    Ok(())
}


