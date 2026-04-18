/*!
 * UUM 8D Digital Twin API
 * 
 * Maps ALL aircraft to UUM 8D spacetime coordinates.
 * Provides viewer API for 2D/3D frontends.
 * NO FILTERING - tracks everything, frontends handle display.
 */

use actix_cors::Cors;
use actix_web::{web, App, HttpResponse, HttpServer, Responder};
use chrono::{DateTime, Utc, Timelike};
use log::{error, info};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::RwLock;

// ═══════════════════════════════════════════════════════════════════════════
// UUM 8D COORDINATE SYSTEM
// ═══════════════════════════════════════════════════════════════════════════

/// UUM 8D coordinates for any entity
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UUM8D {
    /// D0: Longitude (X) normalized [-1, 1]
    pub d0_lon: f64,
    /// D1: Latitude (Y) normalized [-1, 1]
    pub d1_lat: f64,
    /// D2: Altitude (Z) normalized [0, 1]
    pub d2_alt: f64,
    /// D3: Time (T) normalized flow [0, 1]
    pub d3_time: f64,
    /// D4: Intent (heading toward destination) [0, 1]
    pub d4_intent: f64,
    /// D5: Risk (conflict proximity) [0, 1]
    pub d5_risk: f64,
    /// D6: Compliance (regulatory adherence) [0, 1]
    pub d6_comply: f64,
    /// D7: Uncertainty (measurement confidence) [0, 1]
    pub d7_uncert: f64,
}

impl UUM8D {
    pub fn to_array(&self) -> [f64; 8] {
        [
            self.d0_lon, self.d1_lat, self.d2_alt, self.d3_time,
            self.d4_intent, self.d5_risk, self.d6_comply, self.d7_uncert,
        ]
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// TWIN ENTITY - Aircraft in 8D Space
// ═══════════════════════════════════════════════════════════════════════════

/// Entity in digital twin (aircraft, vehicle, etc.)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TwinEntity {
    pub id: String,
    pub callsign: String,
    
    /// Real-world WGS-84 position
    pub lat: f64,
    pub lon: f64,
    pub alt_ft: f64,
    pub heading: f64,
    pub speed_kts: f64,
    pub vertical_rate_fpm: f64,
    
    /// UUM 8D coordinates
    pub uum_8d: UUM8D,
    
    /// 8D velocity (rate of change per second)
    pub velocity_8d: [f64; 8],
    
    /// Nearest anchor reference
    pub nearest_anchor_id: Option<String>,
    pub distance_to_anchor_nm: f64,
    
    /// Metadata
    pub aircraft_type: Option<String>,
    pub timestamp: DateTime<Utc>,
}

// ═══════════════════════════════════════════════════════════════════════════
// ANCHOR - Real-world reference points
// ═══════════════════════════════════════════════════════════════════════════

/// Real-world anchor point (airport, waypoint, VOR, etc.)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Anchor {
    pub id: String,
    pub name: String,
    pub anchor_type: String,
    
    /// Real-world coordinates
    pub lat: f64,
    pub lon: f64,
    pub alt_ft: f64,
    
    /// UUM 8D coordinates
    pub uum_8d: UUM8D,
}

// ═══════════════════════════════════════════════════════════════════════════
// DIGITAL TWIN STATE
// ═══════════════════════════════════════════════════════════════════════════

pub struct DigitalTwinState {
    entities: RwLock<HashMap<String, TwinEntity>>,
    anchors: RwLock<HashMap<String, Anchor>>,
    time_ref: DateTime<Utc>,
}

impl DigitalTwinState {
    pub fn new() -> Self {
        let mut state = Self {
            entities: RwLock::new(HashMap::new()),
            anchors: RwLock::new(HashMap::new()),
            time_ref: Utc::now(),
        };
        
        // Add default anchors
        state.add_default_anchors();
        state
    }
    
    fn add_default_anchors(&mut self) {
        let airports = vec![
            // Major US airports
            ("KJFK", "John F Kennedy Intl", 40.6413, -73.7781, 13.0),
            ("KLAX", "Los Angeles Intl", 33.9416, -118.4085, 126.0),
            ("KORD", "Chicago O'Hare Intl", 41.9742, -87.9073, 672.0),
            ("KATL", "Hartsfield-Jackson Atlanta", 33.6407, -84.4277, 1026.0),
            ("KDFW", "Dallas/Fort Worth Intl", 32.8998, -97.0403, 607.0),
            ("KDEN", "Denver Intl", 39.8561, -104.6737, 5431.0),
            ("KSFO", "San Francisco Intl", 37.6213, -122.3790, 13.0),
            ("KSEA", "Seattle-Tacoma Intl", 47.4502, -122.3088, 433.0),
            ("KMIA", "Miami Intl", 25.7959, -80.2870, 8.0),
            ("KBOS", "Boston Logan Intl", 42.3656, -71.0096, 20.0),
            ("KPHX", "Phoenix Sky Harbor", 33.4373, -112.0078, 1135.0),
            ("KIAH", "Houston George Bush", 29.9902, -95.3368, 97.0),
            ("KMSP", "Minneapolis-St Paul", 44.8848, -93.2223, 841.0),
            ("KDCA", "Washington Reagan", 38.8512, -77.0402, 15.0),
            ("KLAS", "Las Vegas McCarran", 36.0840, -115.1537, 2181.0),
            // Major European airports
            ("EGLL", "London Heathrow", 51.4700, -0.4543, 83.0),
            ("EDDF", "Frankfurt Main", 50.0379, 8.5622, 364.0),
            ("LFPG", "Paris Charles de Gaulle", 49.0097, 2.5479, 392.0),
            ("EHAM", "Amsterdam Schiphol", 52.3105, 4.7683, -11.0),
            // Major Asian airports
            ("RJTT", "Tokyo Haneda", 35.5494, 139.7798, 21.0),
            ("VHHH", "Hong Kong Intl", 22.3080, 113.9185, 28.0),
            ("WSSS", "Singapore Changi", 1.3644, 103.9915, 22.0),
        ];
        
        let mut anchors = self.anchors.write().unwrap();
        for (id, name, lat, lon, alt_ft) in airports {
            let uum_8d = self.map_position_to_8d(lat, lon, alt_ft);
            anchors.insert(id.to_string(), Anchor {
                id: id.to_string(),
                name: name.to_string(),
                anchor_type: "Airport".to_string(),
                lat,
                lon,
                alt_ft,
                uum_8d,
            });
        }
    }
    
    fn map_position_to_8d(&self, lat: f64, lon: f64, alt_ft: f64) -> UUM8D {
        let now = Utc::now();
        
        // D0: Longitude [-1, 1]
        let d0_lon = lon / 180.0;
        
        // D1: Latitude [-1, 1]
        let d1_lat = lat / 90.0;
        
        // D2: Altitude [0, 1] (0 = sea level, 1 = FL600)
        let d2_alt = (alt_ft / 60000.0).clamp(0.0, 1.0);
        
        // D3: Time [0, 1] - normalized time of day
        let seconds_since_midnight = now.num_seconds_from_midnight() as f64;
        let d3_time = seconds_since_midnight / 86400.0;
        
        UUM8D {
            d0_lon,
            d1_lat,
            d2_alt,
            d3_time,
            d4_intent: 0.5,  // Unknown for static anchors
            d5_risk: 0.0,    // No risk for anchors
            d6_comply: 1.0,  // Full compliance
            d7_uncert: 0.0,  // No uncertainty
        }
    }
    
    fn map_aircraft_to_8d(
        &self,
        lat: f64,
        lon: f64,
        alt_ft: f64,
        heading: f64,
        speed_kts: f64,
        vertical_rate_fpm: f64,
        risk: f64,
    ) -> UUM8D {
        let now = Utc::now();
        
        // D0-D3: Spatial + Time
        let d0_lon = lon / 180.0;
        let d1_lat = lat / 90.0;
        let d2_alt = (alt_ft / 60000.0).clamp(0.0, 1.0);
        let seconds_since_midnight = now.num_seconds_from_midnight() as f64;
        let d3_time = seconds_since_midnight / 86400.0;
        
        // D4: Intent - based on speed (faster = higher intent)
        let d4_intent = (speed_kts / 600.0).clamp(0.0, 1.0);
        
        // D5: Risk - passed in from conflict detection
        let d5_risk = risk.clamp(0.0, 1.0);
        
        // D6: Compliance - based on altitude bands and vertical rate
        let in_standard_altitude = (alt_ft % 1000.0).abs() < 100.0;
        let reasonable_vertical_rate = vertical_rate_fpm.abs() < 3000.0;
        let d6_comply = if in_standard_altitude && reasonable_vertical_rate {
            0.95
        } else if reasonable_vertical_rate {
            0.8
        } else {
            0.6
        };
        
        // D7: Uncertainty - based on speed (faster = more predictable)
        let d7_uncert = (1.0 - speed_kts / 600.0).clamp(0.1, 0.9);
        
        UUM8D {
            d0_lon,
            d1_lat,
            d2_alt,
            d3_time,
            d4_intent,
            d5_risk,
            d6_comply,
            d7_uncert,
        }
    }
    
    fn find_nearest_anchor(&self, lat: f64, lon: f64) -> (Option<String>, f64) {
        let anchors = self.anchors.read().unwrap();
        
        if anchors.is_empty() {
            return (None, f64::INFINITY);
        }
        
        let mut nearest_id = None;
        let mut min_dist = f64::INFINITY;
        
        for (id, anchor) in anchors.iter() {
            let dist = haversine_nm(lat, lon, anchor.lat, anchor.lon);
            if dist < min_dist {
                min_dist = dist;
                nearest_id = Some(id.clone());
            }
        }
        
        (nearest_id, min_dist)
    }
    
    fn calc_velocity_8d(
        &self,
        prev: &UUM8D,
        curr: &UUM8D,
        dt_seconds: f64,
    ) -> [f64; 8] {
        if dt_seconds < 0.001 {
            return [0.0; 8];
        }
        
        [
            (curr.d0_lon - prev.d0_lon) / dt_seconds,
            (curr.d1_lat - prev.d1_lat) / dt_seconds,
            (curr.d2_alt - prev.d2_alt) / dt_seconds,
            (curr.d3_time - prev.d3_time) / dt_seconds,
            (curr.d4_intent - prev.d4_intent) / dt_seconds,
            (curr.d5_risk - prev.d5_risk) / dt_seconds,
            (curr.d6_comply - prev.d6_comply) / dt_seconds,
            (curr.d7_uncert - prev.d7_uncert) / dt_seconds,
        ]
    }
}

fn haversine_nm(lat1: f64, lon1: f64, lat2: f64, lon2: f64) -> f64 {
    const R_NM: f64 = 3440.065;
    
    let lat1 = lat1.to_radians();
    let lat2 = lat2.to_radians();
    let dlat = lat2 - lat1;
    let dlon = (lon2 - lon1).to_radians();
    
    let a = (dlat / 2.0).sin().powi(2)
        + lat1.cos() * lat2.cos() * (dlon / 2.0).sin().powi(2);
    let c = 2.0 * a.sqrt().atan2((1.0 - a).sqrt());
    
    R_NM * c
}

// ═══════════════════════════════════════════════════════════════════════════
// API TYPES
// ═══════════════════════════════════════════════════════════════════════════

#[derive(Debug, Deserialize)]
struct ViewportQuery {
    lat: f64,
    lon: f64,
    radius_km: f64,
    seconds_back: Option<i64>,
}

#[derive(Debug, Serialize)]
struct TwinSnapshot {
    center_lat: f64,
    center_lon: f64,
    radius_km: f64,
    timestamp: DateTime<Utc>,
    entity_count: usize,
    anchor_count: usize,
    entities: Vec<TwinEntity>,
    anchors: Vec<Anchor>,
}

#[derive(Debug, Serialize)]
struct TwinStats {
    total_entities: usize,
    total_anchors: usize,
    last_update: DateTime<Utc>,
}

// ═══════════════════════════════════════════════════════════════════════════
// API HANDLERS
// ═══════════════════════════════════════════════════════════════════════════

async fn health() -> impl Responder {
    HttpResponse::Ok().json(serde_json::json!({
        "status": "ok",
        "service": "gaiaos-digital-twin",
        "version": "0.1.0"
    }))
}

async fn get_stats(state: web::Data<DigitalTwinState>) -> impl Responder {
    let entities = state.entities.read().unwrap();
    let anchors = state.anchors.read().unwrap();
    
    let last_update = entities.values()
        .map(|e| e.timestamp)
        .max()
        .unwrap_or_else(Utc::now);
    
    HttpResponse::Ok().json(TwinStats {
        total_entities: entities.len(),
        total_anchors: anchors.len(),
        last_update,
    })
}

async fn get_anchors(state: web::Data<DigitalTwinState>) -> impl Responder {
    let anchors = state.anchors.read().unwrap();
    let anchor_list: Vec<Anchor> = anchors.values().cloned().collect();
    HttpResponse::Ok().json(anchor_list)
}

/// Viewer API - Get TwinEntity snapshot for viewport
async fn get_snapshot(
    state: web::Data<DigitalTwinState>,
    query: web::Json<ViewportQuery>,
) -> impl Responder {
    let entities = state.entities.read().unwrap();
    let anchors = state.anchors.read().unwrap();
    
    let radius_nm = query.radius_km / 1.852;
    
    // Filter entities within viewport
    let viewport_entities: Vec<TwinEntity> = entities.values()
        .filter(|e| {
            let dist = haversine_nm(query.lat, query.lon, e.lat, e.lon);
            dist <= radius_nm
        })
        .cloned()
        .collect();
    
    // Filter anchors within viewport
    let viewport_anchors: Vec<Anchor> = anchors.values()
        .filter(|a| {
            let dist = haversine_nm(query.lat, query.lon, a.lat, a.lon);
            dist <= radius_nm
        })
        .cloned()
        .collect();
    
    HttpResponse::Ok().json(TwinSnapshot {
        center_lat: query.lat,
        center_lon: query.lon,
        radius_km: query.radius_km,
        timestamp: Utc::now(),
        entity_count: viewport_entities.len(),
        anchor_count: viewport_anchors.len(),
        entities: viewport_entities,
        anchors: viewport_anchors,
    })
}

/// Ingest aircraft data from Crystal Snapshot
async fn ingest_aircraft(
    state: web::Data<DigitalTwinState>,
    payload: web::Json<Vec<serde_json::Value>>,
) -> impl Responder {
    let now = Utc::now();
    let mut entities = state.entities.write().unwrap();
    let mut count = 0;
    
    for ac in payload.iter() {
        // Extract fields from various formats
        let icao = ac.get("icao24")
            .or_else(|| ac.get("_key"))
            .and_then(|v| v.as_str())
            .unwrap_or_default()
            .to_string();
        
        if icao.is_empty() {
            continue;
        }
        
        let lat = ac.get("center_lat")
            .and_then(|v| v.as_f64())
            .unwrap_or(0.0);
        let lon = ac.get("center_lon")
            .and_then(|v| v.as_f64())
            .unwrap_or(0.0);
        let alt_ft = ac.get("altitude_ft")
            .and_then(|v| v.as_f64())
            .or_else(|| ac.get("center_alt_m").and_then(|v| v.as_f64()).map(|m| m * 3.28084))
            .unwrap_or(0.0);
        let heading = ac.get("heading_deg")
            .and_then(|v| v.as_f64())
            .unwrap_or(0.0);
        let speed_kts = ac.get("velocity_kts")
            .and_then(|v| v.as_f64())
            .unwrap_or(0.0);
        let vertical_rate = ac.get("vertical_rate_fpm")
            .and_then(|v| v.as_f64())
            .unwrap_or(0.0);
        let callsign = ac.get("callsign")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .trim()
            .to_string();
        
        // Get risk from d_vec if available
        let risk = ac.get("d_vec")
            .and_then(|v| v.as_array())
            .and_then(|arr| arr.get(5))
            .and_then(|v| v.as_f64())
            .unwrap_or(0.0);
        
        // Map to 8D
        let uum_8d = state.map_aircraft_to_8d(
            lat, lon, alt_ft, heading, speed_kts, vertical_rate, risk
        );
        
        // Calculate velocity if we have previous state
        let velocity_8d = if let Some(prev) = entities.get(&icao) {
            let dt = (now.timestamp_millis() - prev.timestamp.timestamp_millis()) as f64 / 1000.0;
            state.calc_velocity_8d(&prev.uum_8d, &uum_8d, dt)
        } else {
            [0.0; 8]
        };
        
        // Find nearest anchor
        let (anchor_id, distance) = state.find_nearest_anchor(lat, lon);
        
        let entity = TwinEntity {
            id: icao.clone(),
            callsign,
            lat,
            lon,
            alt_ft,
            heading,
            speed_kts,
            vertical_rate_fpm: vertical_rate,
            uum_8d,
            velocity_8d,
            nearest_anchor_id: anchor_id,
            distance_to_anchor_nm: distance,
            aircraft_type: ac.get("aircraft_type").and_then(|v| v.as_str()).map(|s| s.to_string()),
            timestamp: now,
        };
        
        entities.insert(icao, entity);
        count += 1;
    }
    
    HttpResponse::Ok().json(serde_json::json!({
        "status": "ok",
        "ingested": count,
        "total_entities": entities.len()
    }))
}

// ═══════════════════════════════════════════════════════════════════════════
// MAIN
// ═══════════════════════════════════════════════════════════════════════════

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    // Initialize logging
    env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("info"))
        .format_timestamp_millis()
        .init();
    
    // Wire consciousness layer
    let nats_url = std::env::var("NATS_URL").unwrap_or_else(|_| "nats://gaiaos-nats:4222".to_string());
    if let Ok(nats_client) = async_nats::connect(&nats_url).await {
        info!("✓ NATS connected for consciousness");
        
        let nats_announce = nats_client.clone();
        actix_web::rt::spawn(async move {
            gaiaos_introspection::announce_service_loop(
                nats_announce, "digital-twin".to_string(), env!("CARGO_PKG_VERSION").to_string(),
                std::env::var("GAIA_CELL_ID").unwrap_or_else(|_| "unknown".to_string()),
                vec![gaiaos_introspection::IntrospectionEndpoint {
                    name: "aircraft".into(), kind: "http".into(), path: Some("/aircraft".into()), subject: None,
                }],
            ).await;
        });
        
        let nats_introspect = nats_client.clone();
        actix_web::rt::spawn(async move {
            let _ = gaiaos_introspection::run_introspection_handler(
                nats_introspect, "digital-twin".to_string(),
                || gaiaos_introspection::ServiceIntrospectionReply {
                    service: "digital-twin".into(),
                    functions: vec![gaiaos_introspection::FunctionDescriptor {
                        name: "digital_twin::aircraft".into(), inputs: vec![], outputs: vec!["Aircraft".into()],
                        kind: "http".into(), path: Some("/aircraft".into()), subject: None, side_effects: vec![],
                    }],
                    call_graph_edges: vec![], state_keys: vec!["aircraft".into()],
                    timestamp: chrono::Utc::now().to_rfc3339(),
                },
            ).await;
        });
        info!("✓ Consciousness wired");
    }
    
    let bind_addr = std::env::var("BIND_ADDR").unwrap_or_else(|_| "0.0.0.0:8770".to_string());
    
    println!("🎯 Starting GaiaOS UUM 8D Digital Twin API on {}", bind_addr);
    info!("🎯 Starting GaiaOS UUM 8D Digital Twin API on {}", bind_addr);
    
    let state = web::Data::new(DigitalTwinState::new());
    
    println!("📍 Loaded {} anchors", state.anchors.read().unwrap().len());
    info!("📍 Loaded {} anchors", state.anchors.read().unwrap().len());
    
    HttpServer::new(move || {
        App::new()
            .wrap(Cors::permissive())
            .app_data(state.clone())
            .route("/health", web::get().to(health))
            .route("/stats", web::get().to(get_stats))
            .route("/anchors", web::get().to(get_anchors))
            .route("/snapshot", web::post().to(get_snapshot))
            .route("/ingest", web::post().to(ingest_aircraft))
    })
    .bind(&bind_addr)?
    .run()
    .await
}

