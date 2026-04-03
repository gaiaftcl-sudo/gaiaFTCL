//! GaiaOS ATC Turbulence Test Data Service
//!
//! Provides HTTP API for:
//! - Aircraft positions from ArangoDB
//! - Turbulence fields from RANS k-ε operator
//! - Risk zones (GeoJSON)
//! - Tar1090-compatible data feeds

use actix_web::{web, App, HttpResponse, HttpServer, Result};
use actix_cors::Cors;
use serde::{Deserialize, Serialize};
use std::sync::{Arc, Mutex};
use tracing::{info, error};

// ═══════════════════════════════════════════════════════════════════════════
// Data Structures
// ═══════════════════════════════════════════════════════════════════════════

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct Aircraft {
    pub hex: String,
    pub flight: Option<String>,
    pub lat: f64,
    pub lon: f64,
    pub alt_baro: Option<i32>,
    pub alt_geom: Option<i32>,
    pub gs: Option<f32>,        // Ground speed (knots)
    pub track: Option<f32>,     // Track angle (degrees)
    pub baro_rate: Option<i32>, // Vertical rate (ft/min)
    pub category: Option<String>,
    pub seen: f64,              // Seconds since last update
    pub rssi: Option<f32>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct TurbulenceField {
    pub region: Region,
    pub grid_shape: [usize; 2],  // [lat_cells, lon_cells]
    pub grid_data: Vec<TurbulenceCell>,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct TurbulenceCell {
    pub lat: f64,
    pub lon: f64,
    pub u: f32,        // Wind velocity east (m/s)
    pub v: f32,        // Wind velocity north (m/s)
    pub k: f32,        // Turbulent kinetic energy (m²/s²)
    pub epsilon: f32,  // Dissipation rate (m²/s³)
    pub nu_t: f32,     // Eddy viscosity (m²/s)
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct Region {
    pub lat_min: f64,
    pub lat_max: f64,
    pub lon_min: f64,
    pub lon_max: f64,
    pub alt_min: f32,  // meters
    pub alt_max: f32,  // meters
}

#[derive(Debug, Serialize)]
pub struct RiskZone {
    pub id: String,
    pub geometry: geojson::Geometry,
    pub properties: RiskProperties,
}

#[derive(Debug, Serialize)]
pub struct RiskProperties {
    pub severity: String,      // "low", "moderate", "high", "severe"
    pub k_max: f32,            // Max turbulence in zone
    pub epsilon_max: f32,
    pub timestamp: String,
}

// ═══════════════════════════════════════════════════════════════════════════
// Application State
// ═══════════════════════════════════════════════════════════════════════════

pub struct AppState {
    arango_url: String,
    arango_db: String,
    arango_user: String,
    arango_pass: String,
    turbulence_cache: Arc<Mutex<Option<TurbulenceField>>>,
}

// ═══════════════════════════════════════════════════════════════════════════
// API Endpoints
// ═══════════════════════════════════════════════════════════════════════════

/// GET /api/aircraft
/// Returns all aircraft from ArangoDB in Tar1090-compatible format
async fn get_aircraft(state: web::Data<AppState>) -> Result<HttpResponse> {
    info!("📡 Fetching aircraft from ArangoDB");
    
    // Query ArangoDB
    let url = format!(
        "{}/_db/{}/_api/cursor",
        state.arango_url, state.arango_db
    );
    
    let query = r#"{
        "query": "FOR doc IN aircraft_states FILTER doc.`geo:lat` != null RETURN doc"
    }"#;
    
    let client = reqwest::Client::new();
    let response = client
        .post(&url)
        .basic_auth(&state.arango_user, Some(&state.arango_pass))
        .header("Content-Type", "application/json")
        .body(query)
        .send()
        .await;
    
    match response {
        Ok(resp) => {
            if resp.status().is_success() {
                let json: serde_json::Value = resp.json().await.unwrap_or_default();
                let results = json["result"].as_array().unwrap_or(&vec![]);
                
                // Convert to Aircraft structs
                let aircraft: Vec<Aircraft> = results
                    .iter()
                    .filter_map(|doc| {
                        Some(Aircraft {
                            hex: doc["atc:hasHexCode"].as_str()?.to_string(),
                            flight: doc["atc:hasCallsign"].as_str().map(|s| s.to_string()),
                            lat: doc["geo:lat"].as_f64()?,
                            lon: doc["geo:long"].as_f64()?,
                            alt_baro: doc["atc:hasBarometricAltitude"].as_i64().map(|v| v as i32),
                            alt_geom: doc["atc:hasGeometricAltitude"].as_i64().map(|v| v as i32),
                            gs: doc["atc:hasGroundSpeed"].as_f64().map(|v| v as f32),
                            track: doc["atc:hasTrackAngle"].as_f64().map(|v| v as f32),
                            baro_rate: doc["atc:hasVerticalRate"].as_i64().map(|v| v as i32),
                            category: doc["atc:hasAircraftType"].as_str().map(|s| s.to_string()),
                            seen: doc["atc:hasSeenAgo"].as_f64().unwrap_or(0.0),
                            rssi: doc["atc:hasRssi"].as_f64().map(|v| v as f32),
                        })
                    })
                    .collect();
                
                info!("✅ Fetched {} aircraft", aircraft.len());
                Ok(HttpResponse::Ok().json(aircraft))
            } else {
                error!("❌ ArangoDB query failed: {}", resp.status());
                Ok(HttpResponse::InternalServerError().json(serde_json::json!({
                    "error": "ArangoDB query failed"
                })))
            }
        }
        Err(e) => {
            error!("❌ ArangoDB connection failed: {}", e);
            Ok(HttpResponse::InternalServerError().json(serde_json::json!({
                "error": format!("ArangoDB connection failed: {}", e)
            })))
        }
    }
}

/// GET /api/turbulence/field?lat_min=...&lat_max=...&lon_min=...&lon_max=...
/// Computes turbulence field using RANS k-ε operator
async fn get_turbulence_field(
    state: web::Data<AppState>,
    query: web::Query<Region>,
) -> Result<HttpResponse> {
    info!("🌪️ Computing turbulence field for region: {:?}", query);
    
    // Check cache first
    if let Ok(cache) = state.turbulence_cache.lock() {
        if let Some(cached_field) = cache.as_ref() {
            info!("✅ Using cached turbulence field");
            return Ok(HttpResponse::Ok().json(cached_field));
        }
    }
    
    // Planned: invoke real RANS k-ε (Field World operator graph) and return computed field.
    // Honesty rule: do not fabricate turbulence fields.
    let region = query.into_inner();
    let _ = state;
    Ok(
        HttpResponse::build(actix_web::http::StatusCode::NOT_IMPLEMENTED).json(serde_json::json!({
            "error": "turbulence_field_not_implemented",
            "message": "RANS k-ε operator not wired in this service; refusing synthetic turbulence.",
            "region": region
        }))
    )
}

/// GET /api/risk_zones?threshold=0.5
/// Generates GeoJSON polygons for high-turbulence regions
async fn get_risk_zones(
    state: web::Data<AppState>,
    query: web::Query<std::collections::HashMap<String, String>>,
) -> Result<HttpResponse> {
    let threshold: f32 = query
        .get("threshold")
        .and_then(|s| s.parse().ok())
        .unwrap_or(0.5);
    
    info!("🚨 Computing risk zones (k > {})", threshold);
    
    // Get cached turbulence field
    let field = if let Ok(cache) = state.turbulence_cache.lock() {
        cache.clone()
    } else {
        None
    };
    
    if field.is_none() {
        return Ok(HttpResponse::Ok().json(serde_json::json!({
            "type": "FeatureCollection",
            "features": []
        })));
    }
    
    let field = field.unwrap();
    
    // Find cells exceeding threshold
    let mut risk_cells: Vec<&TurbulenceCell> = field
        .grid_data
        .iter()
        .filter(|cell| cell.k > threshold)
        .collect();
    
    if risk_cells.is_empty() {
        return Ok(HttpResponse::Ok().json(serde_json::json!({
            "type": "FeatureCollection",
            "features": []
        })));
    }
    
    // Group into zones (simple bounding box for now)
    // Planned: implement proper clustering algorithm
    risk_cells.sort_by(|a, b| a.lat.partial_cmp(&b.lat).unwrap());
    
    let lat_min = risk_cells.first().unwrap().lat;
    let lat_max = risk_cells.last().unwrap().lat;
    
    risk_cells.sort_by(|a, b| a.lon.partial_cmp(&b.lon).unwrap());
    let lon_min = risk_cells.first().unwrap().lon;
    let lon_max = risk_cells.last().unwrap().lon;
    
    let k_max = risk_cells.iter().map(|c| c.k).fold(0.0f32, f32::max);
    
    // Create GeoJSON polygon
    let polygon = geojson::Geometry::new(geojson::Value::Polygon(vec![vec![
        vec![lon_min, lat_min],
        vec![lon_max, lat_min],
        vec![lon_max, lat_max],
        vec![lon_min, lat_max],
        vec![lon_min, lat_min],
    ]]));
    
    let severity = if k_max > 2.0 {
        "severe"
    } else if k_max > 1.0 {
        "high"
    } else if k_max > 0.5 {
        "moderate"
    } else {
        "low"
    };
    
    let feature = serde_json::json!({
        "type": "Feature",
        "geometry": polygon,
        "properties": {
            "severity": severity,
            "k_max": k_max,
            "timestamp": chrono::Utc::now().to_rfc3339()
        }
    });
    
    let feature_collection = serde_json::json!({
        "type": "FeatureCollection",
        "features": [feature]
    });
    
    info!("✅ Generated {} risk zone(s)", 1);
    Ok(HttpResponse::Ok().json(feature_collection))
}

/// GET /health
async fn health_check() -> Result<HttpResponse> {
    Ok(HttpResponse::Ok().json(serde_json::json!({
        "status": "healthy",
        "service": "gaiaos-atc-turbulence-test",
        "version": env!("CARGO_PKG_VERSION")
    })))
}

// ═══════════════════════════════════════════════════════════════════════════
// Main
// ═══════════════════════════════════════════════════════════════════════════

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    // Initialize tracing
    tracing_subscriber::fmt::init();
    
    info!("🚀 Starting GaiaOS ATC Turbulence Test Data Service");
    
    // Configuration
    let bind_addr = std::env::var("BIND_ADDR").unwrap_or_else(|_| "0.0.0.0:8850".to_string());
    let arango_url = std::env::var("ARANGO_URL").unwrap_or_else(|_| "http://localhost:8529".to_string());
    let arango_db = std::env::var("ARANGO_DB").unwrap_or_else(|_| "gaiaos".to_string());
    let arango_user = std::env::var("ARANGO_USER").unwrap_or_else(|_| "root".to_string());
    let arango_pass = std::env::var("ARANGO_PASS").unwrap_or_else(|_| "openSesame".to_string());
    
    let state = web::Data::new(AppState {
        arango_url,
        arango_db,
        arango_user,
        arango_pass,
        turbulence_cache: Arc::new(Mutex::new(None)),
    });
    
    info!("📡 Binding to {}", bind_addr);
    info!("🗄️ ArangoDB: {}", state.arango_url);
    
    HttpServer::new(move || {
        let cors = Cors::permissive();
        
        App::new()
            .wrap(cors)
            .app_data(state.clone())
            .route("/health", web::get().to(health_check))
            .route("/api/aircraft", web::get().to(get_aircraft))
            .route("/api/turbulence/field", web::get().to(get_turbulence_field))
            .route("/api/risk_zones", web::get().to(get_risk_zones))
    })
    .bind(&bind_addr)?
    .run()
    .await
}

