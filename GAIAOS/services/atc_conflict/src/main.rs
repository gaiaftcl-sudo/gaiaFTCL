//! GaiaOS ATC Conflict Detector - TRUE 8D Implementation
//!
//! Detects loss of separation between aircraft using FULL 8D analysis:
//! - D0-D1: Horizontal separation (position)
//! - D2: Vertical separation (altitude)
//! - D3: Time to Closest Point of Approach (CPA)
//! - D4: Intent (converging vs diverging)
//! - D5: Combined risk score
//! - D6: Compliance
//! - D7: Uncertainty
//!
//! ## Loss of Separation Criteria (FAA/ICAO):
//! - Horizontal: < 5 NM (nautical miles)
//! - Vertical: < 1000 ft
//! - BOTH must be violated for a conflict (OR logic for safety)
//!
//! NO SYNTHETIC DATA. NO SIMULATIONS. REAL 8D CONFLICT DETECTION.

use std::collections::HashMap;
use std::time::Duration;
use std::sync::Arc;

use chrono::{DateTime, Timelike, Utc};
use log::{error, info, warn};
use serde::{Deserialize, Serialize};
use uuid::Uuid;
use axum::{routing::get, Json, Router};
use axum::http::StatusCode;
use axum::extract::State;

mod stochastic_trajectory;

use stochastic_trajectory::{AircraftKinematics, predict_coupled_pair_trajectory, predict_stochastic_trajectory};

#[derive(Clone)]
struct ApiState {
    arango_url: String,
    arango_db: String,
    arango_collection: String,
    arango_user: String,
    arango_password: String,
    http: reqwest::Client,
}

#[derive(Debug, Serialize)]
struct ConflictsResponse {
    status: &'static str,
    count: usize,
    conflicts: Vec<serde_json::Value>,
}

/// Aircraft state from ArangoDB
#[derive(Debug, Clone, Serialize, Deserialize)]
struct AircraftPatch {
    #[serde(rename = "_key")]
    key: Option<String>,
    context: Option<String>,
    center_lat: Option<f64>,
    center_lon: Option<f64>,
    center_alt_m: Option<f64>,
    timestamp: Option<String>,
    d_vec: Option<Vec<f64>>,
    // Top-level fields from airplanes.live ingest
    icao24: Option<String>,
    callsign: Option<String>,
    altitude_ft: Option<f64>,
    velocity_kts: Option<f64>,
    heading_deg: Option<f64>,
    vertical_rate_fpm: Option<f64>,
    // Legacy nested format
    #[serde(default)]
    atc: Option<AtcInner>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct AtcInner {
    icao24: Option<String>,
    callsign: Option<String>,
    altitude_ft: Option<f64>,
    velocity_kts: Option<f64>,
    heading_deg: Option<f64>,
    vertical_rate_fpm: Option<f64>,
}

/// Normalized aircraft state for conflict detection
#[derive(Debug, Clone)]
struct AircraftState {
    icao24: String,
    callsign: String,
    lat: f64,
    lon: f64,
    alt_ft: f64,
    velocity_kts: f64,
    heading_deg: f64,
    vertical_rate_fpm: f64,
}

impl AircraftState {
    fn from_patch(patch: &AircraftPatch) -> Option<Self> {
        let lat = patch.center_lat?;
        let lon = patch.center_lon?;
        
        // Try top-level fields first (airplanes.live format), then nested atc
        let icao24 = patch.icao24.clone()
            .or_else(|| patch.atc.as_ref().and_then(|a| a.icao24.clone()))
            .or_else(|| patch.key.clone())
            .unwrap_or_default();
        
        if icao24.is_empty() {
            return None;
        }
        
        let callsign = patch.callsign.clone()
            .or_else(|| patch.atc.as_ref().and_then(|a| a.callsign.clone()))
            .unwrap_or_default();
        
        let alt_ft = patch.altitude_ft
            .or_else(|| patch.atc.as_ref().and_then(|a| a.altitude_ft))
            .or_else(|| patch.center_alt_m.map(|m| m * 3.28084))
            .unwrap_or(0.0);
        
        let velocity_kts = patch.velocity_kts
            .or_else(|| patch.atc.as_ref().and_then(|a| a.velocity_kts))
            .unwrap_or(0.0);
        
        let heading_deg = patch.heading_deg
            .or_else(|| patch.atc.as_ref().and_then(|a| a.heading_deg))
            .unwrap_or(0.0);
        
        let vertical_rate_fpm = patch.vertical_rate_fpm
            .or_else(|| patch.atc.as_ref().and_then(|a| a.vertical_rate_fpm))
            .unwrap_or(0.0);
        
        Some(Self {
            icao24,
            callsign,
            lat,
            lon,
            alt_ft,
            velocity_kts,
            heading_deg,
            vertical_rate_fpm,
        })
    }
    
    /// Calculate velocity components in nm/hour
    fn velocity_components(&self) -> (f64, f64) {
        let hdg_rad = self.heading_deg.to_radians();
        let vx = self.velocity_kts * hdg_rad.sin();  // East component
        let vy = self.velocity_kts * hdg_rad.cos();  // North component
        (vx, vy)
    }
}

/// Conflict severity based on 8D analysis
#[derive(Debug, Clone, Copy, PartialEq)]
enum ConflictSeverity {
    Critical,  // Loss of separation imminent or occurred (<60s to CPA)
    High,      // Predicted LOS within 2 minutes
    Medium,    // Predicted LOS within 5 minutes
    Low,       // Close proximity, >5 minutes to LOS
}

impl ConflictSeverity {
    fn as_str(&self) -> &'static str {
        match self {
            Self::Critical => "CRITICAL",
            Self::High => "HIGH",
            Self::Medium => "MEDIUM",
            Self::Low => "LOW",
        }
    }
}

/// Full 8D conflict analysis result
#[derive(Debug)]
struct Conflict8D {
    aircraft_a: AircraftState,
    aircraft_b: AircraftState,
    horizontal_nm: f64,
    vertical_ft: f64,
    time_to_cpa_sec: f64,
    h_sep_at_cpa_nm: f64,
    v_sep_at_cpa_ft: f64,
    is_converging: bool,
    risk_8d: f64,
    severity: ConflictSeverity,
}

/// Conflict patch to write to ArangoDB
#[derive(Debug, Serialize)]
struct ConflictPatch {
    _key: String,
    scale: String,
    context: String,
    center_lat: f64,
    center_lon: f64,
    center_alt_m: f64,
    timestamp: DateTime<Utc>,
    d_vec: [f64; 8],
    conflict: ConflictDetails,
}

#[derive(Debug, Serialize)]
struct ConflictDetails {
    horizontal_nm: f64,
    vertical_ft: f64,
    time_to_cpa_sec: f64,
    h_sep_at_cpa_nm: f64,
    v_sep_at_cpa_ft: f64,
    is_converging: bool,
    risk_8d: f64,
    severity: String,
    aircraft: [ConflictAircraft; 2],
}

#[derive(Debug, Serialize)]
struct ConflictAircraft {
    icao24: String,
    callsign: String,
    latitude: f64,
    longitude: f64,
    altitude_ft: f64,
    velocity_kts: f64,
    heading_deg: f64,
}

#[derive(Debug, Deserialize)]
struct CursorResult {
    result: Vec<AircraftPatch>,
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    env_logger::init();

    info!("╔════════════════════════════════════════════════════════════╗");
    info!("║      GAIAOS 8D ATC CONFLICT DETECTOR v0.2.0                ║");
    info!("║   True 8D Analysis - Time to CPA - NO SYNTHETIC DATA       ║");
    info!("╚════════════════════════════════════════════════════════════╝");

    let arango_url =
        std::env::var("ARANGO_URL").unwrap_or_else(|_| "http://arangodb:8529".to_string());
    let arango_db = std::env::var("ARANGO_DB").unwrap_or_else(|_| "gaiaos".to_string());
    let arango_collection = std::env::var("ARANGO_WORLD_PATCHES_COLLECTION")
        .unwrap_or_else(|_| "world_patches".to_string());
    let arango_user = std::env::var("ARANGO_USER").unwrap_or_else(|_| "root".to_string());
    let arango_password = std::env::var("ARANGO_PASSWORD").unwrap_or_else(|_| "gaiaos".to_string());
    let host = std::env::var("HOST").unwrap_or_else(|_| "0.0.0.0".to_string());
    let port: u16 = std::env::var("PORT").ok().and_then(|v| v.parse().ok()).unwrap_or(8701);
    let _conflict_limit: usize = std::env::var("CONFLICT_LIMIT")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(200);

    info!("ArangoDB: {}/_db/{}/{}", arango_url, arango_db, arango_collection);

    let http_client = reqwest::Client::builder()
        .user_agent("GaiaOS-ATC-Conflict/0.2")
        .build()?;

    let api_state = Arc::new(ApiState {
        arango_url: arango_url.clone(),
        arango_db: arango_db.clone(),
        arango_collection: arango_collection.clone(),
        arango_user: arango_user.clone(),
        arango_password: arango_password.clone(),
        http: http_client.clone(),
    });

    info!("🚨 Starting TRUE 8D conflict scanner (5 second interval) + HTTP API on {}:{}", host, port);

    // Background scanner loop
    let scan_state = api_state.clone();
    tokio::spawn(async move {
        loop {
            if let Err(e) = scan_and_write_conflicts(
                &scan_state.http,
                &scan_state.arango_url,
                &scan_state.arango_db,
                &scan_state.arango_collection,
                &scan_state.arango_user,
                &scan_state.arango_password,
            )
            .await
            {
                error!("Conflict scan/write error: {e}");
            }
            tokio::time::sleep(Duration::from_secs(5)).await;
        }
    });

    // HTTP API server
    let app = Router::new()
        .route("/health", get(health))
        .route("/atc/conflicts", get(get_conflicts))
        .with_state(api_state);

    let listener = tokio::net::TcpListener::bind(format!("{host}:{port}")).await?;
    axum::serve(listener, app).await?;
    Ok(())
}

async fn health() -> Result<Json<serde_json::Value>, StatusCode> {
    Ok(Json(serde_json::json!({"status":"ok","service":"atc-conflict"})))
}

async fn get_conflicts(
    State(state): State<Arc<ApiState>>,
) -> Result<Json<ConflictsResponse>, StatusCode> {
    let limit: usize = std::env::var("CONFLICT_LIMIT")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(200);
    let url = format!(
        "{base}/_db/{db}/_api/cursor",
        base = state.arango_url.trim_end_matches('/'),
        db = state.arango_db
    );

    let query = format!(
        r#"
FOR p IN {coll}
  FILTER p.scale == "planetary"
  FILTER p.context == "planetary:atc_conflict"
  LET ts = DATE_TIMESTAMP(p.timestamp)
  SORT ts DESC
  LIMIT @limit
  RETURN p
"#,
        coll = state.arango_collection
    );

    let resp = state
        .http
        .post(&url)
        .basic_auth(&state.arango_user, Some(&state.arango_password))
        .json(&serde_json::json!({
            "query": query,
            "bindVars": { "limit": limit as i64 },
            "batchSize": 1000
        }))
        .send()
        .await
        .map_err(|_| StatusCode::SERVICE_UNAVAILABLE)?;

    if !resp.status().is_success() {
        return Err(StatusCode::SERVICE_UNAVAILABLE);
    }

    let v: serde_json::Value = resp.json().await.map_err(|_| StatusCode::SERVICE_UNAVAILABLE)?;
    let arr = v["result"].as_array().cloned().unwrap_or_default();
    Ok(Json(ConflictsResponse {
        status: "ok",
        count: arr.len(),
        conflicts: arr,
    }))
}

async fn fetch_recent_aircraft(
    client: &reqwest::Client,
    arango_url: &str,
    db_name: &str,
    collection: &str,
    user: &str,
    password: &str,
) -> Result<Vec<AircraftPatch>, Box<dyn std::error::Error + Send + Sync>> {
    let url = format!(
        "{base}/_db/{db}/_api/cursor",
        base = arango_url.trim_end_matches('/'),
        db = db_name
    );

    let query = format!(
        r#"
FOR p IN {coll}
  FILTER p.scale == "planetary"
  FILTER p.context LIKE "planetary:atc_live%"
  FILTER p.center_lat != null AND p.center_lon != null
  LET ts = DATE_TIMESTAMP(p.timestamp)
  FILTER ts >= DATE_NOW() - 120000
  SORT ts DESC
  LIMIT 5000
  RETURN p
"#,
        coll = collection
    );

    let resp = client
        .post(&url)
        .basic_auth(user, Some(password))
        .json(&serde_json::json!({
            "query": query,
            "batchSize": 10000
        }))
        .send()
        .await?;

    if !resp.status().is_success() {
        let text = resp.text().await.unwrap_or_default();
        return Err(format!("Arango query failed: {}", text).into());
    }

    let result: CursorResult = resp.json().await?;
    Ok(result.result)
}

async fn scan_and_write_conflicts(
    client: &reqwest::Client,
    arango_url: &str,
    db_name: &str,
    collection: &str,
    user: &str,
    password: &str,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let patches = fetch_recent_aircraft(client, arango_url, db_name, collection, user, password).await?;

    // Deduplicate by icao24 (keep most recent)
    let mut aircraft_map: HashMap<String, AircraftState> = HashMap::new();
    for patch in &patches {
        if let Some(state) = AircraftState::from_patch(patch) {
            aircraft_map.insert(state.icao24.clone(), state);
        }
    }

    let aircraft: Vec<AircraftState> = aircraft_map.into_values().collect();
    let aircraft_count = aircraft.len();

    if aircraft_count < 2 {
        return Ok(());
    }

    // Pairwise 8D conflict detection
    let mut conflicts: Vec<Conflict8D> = Vec::new();

    for i in 0..aircraft.len() {
        for j in (i + 1)..aircraft.len() {
            if let Some(conflict) = detect_conflict_8d(&aircraft[i], &aircraft[j]) {
                conflicts.push(conflict);
            }
        }
    }

    // Count by severity
    let critical = conflicts.iter().filter(|c| c.severity == ConflictSeverity::Critical).count();
    let high = conflicts.iter().filter(|c| c.severity == ConflictSeverity::High).count();
    let medium = conflicts.iter().filter(|c| c.severity == ConflictSeverity::Medium).count();
    let low = conflicts.iter().filter(|c| c.severity == ConflictSeverity::Low).count();

    if conflicts.is_empty() {
        info!(
            "✅ Scanned {} aircraft - NO TRUE CONFLICTS (adequate separation)",
            aircraft_count
        );
        return Ok(());
    }

    info!(
        "🚨 8D CONFLICTS: {} total from {} aircraft | CRITICAL: {} | HIGH: {} | MEDIUM: {} | LOW: {}",
        conflicts.len(), aircraft_count, critical, high, medium, low
    );

    // Write conflicts to ArangoDB
    let url = format!(
        "{base}/_db/{db}/_api/document/{coll}",
        base = arango_url.trim_end_matches('/'),
        db = db_name,
        coll = collection
    );

    let ts = Utc::now();
    let mut written = 0;

    for conflict in &conflicts {
        let patch = conflict_to_patch(conflict, ts);
        
        let resp = client
            .post(&url)
            .basic_auth(user, Some(password))
            .json(&patch)
            .send()
            .await?;

        if resp.status().is_success() {
            written += 1;
        } else {
            let text = resp.text().await.unwrap_or_default();
            warn!("Arango conflict insert failed: {}", text);
        }
    }

    // Log critical/high conflicts
    for conflict in conflicts.iter().filter(|c| c.severity == ConflictSeverity::Critical || c.severity == ConflictSeverity::High) {
        warn!(
            "   ⚠️ {} ↔ {} | H: {:.1}nm V: {:.0}ft | CPA: {:.0}s | {} | Risk: {:.2}",
            conflict.aircraft_a.callsign.as_str().trim(),
            conflict.aircraft_b.callsign.as_str().trim(),
            conflict.horizontal_nm,
            conflict.vertical_ft,
            conflict.time_to_cpa_sec,
            conflict.severity.as_str(),
            conflict.risk_8d
        );
    }

    info!("   → {} conflicts written to DB", written);

    // For high-severity conflicts, compute and store stochastic trajectory ensembles.
    // Deterministic (seeded), constitutionally gated by Franklin oversight (entropy floor).
    if critical + high > 0 {
        if let Err(e) = write_trajectory_ensembles(
            client,
            arango_url,
            db_name,
            collection,
            user,
            password,
            ts,
            &conflicts,
        )
        .await
        {
            warn!("Trajectory ensemble write failed: {e}");
        }
    }

    Ok(())
}

#[derive(Debug, Serialize)]
struct TrajectoryPatch {
    _key: String,
    scale: String,
    context: String,
    center_lat: f64,
    center_lon: f64,
    center_alt_m: f64,
    timestamp: DateTime<Utc>,
    d_vec: [f64; 8],
    trajectory: TrajectoryDetails,
}

#[derive(Debug, Serialize)]
struct TrajectoryDetails {
    aircraft: [ConflictAircraft; 2],
    horizon_sec: u64,
    dt_sec: u64,
    ensemble_size: usize,
    los_probability: f64,
    los_any_member: bool,
    earliest_los_sec: Option<u64>,
    min_horizontal_nm: f64,
    min_vertical_ft: f64,
    a: stochastic_trajectory::TrajectorySummary,
    b: stochastic_trajectory::TrajectorySummary,
    #[serde(skip_serializing_if = "Option::is_none")]
    a_independent: Option<stochastic_trajectory::TrajectorySummary>,
    #[serde(skip_serializing_if = "Option::is_none")]
    b_independent: Option<stochastic_trajectory::TrajectorySummary>,
}

async fn write_trajectory_ensembles(
    client: &reqwest::Client,
    arango_url: &str,
    db_name: &str,
    collection: &str,
    user: &str,
    password: &str,
    ts: DateTime<Utc>,
    conflicts: &[Conflict8D],
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    // Limit to avoid runaway compute on dense traffic.
    let max_pairs = 20usize;
    let mut handled = 0usize;

    for c in conflicts.iter().filter(|c| c.severity == ConflictSeverity::Critical || c.severity == ConflictSeverity::High) {
        if handled >= max_pairs {
            break;
        }
        handled += 1;

        let a = &c.aircraft_a;
        let b = &c.aircraft_b;

        let kin_a = AircraftKinematics {
            icao24: a.icao24.clone(),
            callsign: a.callsign.clone(),
            lat: a.lat,
            lon: a.lon,
            alt_ft: a.alt_ft,
            velocity_kts: a.velocity_kts,
            heading_deg: a.heading_deg,
            vertical_rate_fpm: a.vertical_rate_fpm,
        };
        let kin_b = AircraftKinematics {
            icao24: b.icao24.clone(),
            callsign: b.callsign.clone(),
            lat: b.lat,
            lon: b.lon,
            alt_ft: b.alt_ft,
            velocity_kts: b.velocity_kts,
            heading_deg: b.heading_deg,
            vertical_rate_fpm: b.vertical_rate_fpm,
        };

        // Horizon: 120 seconds, 5-second increments.
        // Coupled ensemble: produces meaningful separation probability without 50×50 cross-product.
        let pair = predict_coupled_pair_trajectory(&kin_a, &kin_b, ts, 120, 5).map_err(|e| e.to_string())?;

        // Optional independent per-aircraft ensembles (debug/audit), enabled only when explicitly requested.
        let want_independent = std::env::var("ATC_CONFLICT_WRITE_INDEPENDENT_ENSEMBLES").is_ok();
        let (a_independent, b_independent) = if want_independent {
            let a_ens = predict_stochastic_trajectory(&kin_a, ts, 120, 5).map(|e| e.mean).ok();
            let b_ens = predict_stochastic_trajectory(&kin_b, ts, 120, 5).map(|e| e.mean).ok();
            (a_ens, b_ens)
        } else {
            (None, None)
        };

        let center_lat = (a.lat + b.lat) / 2.0;
        let center_lon = (a.lon + b.lon) / 2.0;
        let center_alt_ft = (a.alt_ft + b.alt_ft) / 2.0;
        let center_alt_m = center_alt_ft * 0.3048;

        // d_vec: reuse conflict risk encoding for compatibility with existing 8D viewers.
        let d0 = center_lon / 180.0;
        let d1 = center_lat / 90.0;
        let d2 = (center_alt_m / 15000.0).clamp(0.0, 1.0);
        let d3 = (ts.num_seconds_from_midnight() as f64 / 86400.0).clamp(0.0, 1.0);
        let d4 = if c.is_converging { c.risk_8d } else { 0.2 };
        let d5 = c.risk_8d;
        let d6 = (1.0 - c.risk_8d * 0.7).clamp(0.0, 1.0);
        let d7 = (0.1 + c.risk_8d * 0.5).clamp(0.0, 1.0);

        let patch = TrajectoryPatch {
            _key: Uuid::new_v4().to_string(),
            scale: "planetary".to_string(),
            context: "planetary:atc_trajectory_ensemble".to_string(),
            center_lat,
            center_lon,
            center_alt_m,
            timestamp: ts,
            d_vec: [d0, d1, d2, d3, d4, d5, d6, d7],
            trajectory: TrajectoryDetails {
                aircraft: [
                    ConflictAircraft {
                        icao24: a.icao24.clone(),
                        callsign: a.callsign.clone(),
                        latitude: a.lat,
                        longitude: a.lon,
                        altitude_ft: a.alt_ft,
                        velocity_kts: a.velocity_kts,
                        heading_deg: a.heading_deg,
                    },
                    ConflictAircraft {
                        icao24: b.icao24.clone(),
                        callsign: b.callsign.clone(),
                        latitude: b.lat,
                        longitude: b.lon,
                        altitude_ft: b.alt_ft,
                        velocity_kts: b.velocity_kts,
                        heading_deg: b.heading_deg,
                    },
                ],
                horizon_sec: 120,
                dt_sec: 5,
                ensemble_size: pair.ensemble_size,
                los_probability: pair.separation.los_probability,
                los_any_member: pair.separation.los_any_member,
                earliest_los_sec: pair.separation.earliest_los_sec,
                min_horizontal_nm: pair.separation.min_horizontal_nm,
                min_vertical_ft: pair.separation.min_vertical_ft,
                a: pair.a,
                b: pair.b,
                a_independent,
                b_independent,
            },
        };

        let url = format!(
            "{base}/_db/{db}/_api/document/{coll}",
            base = arango_url.trim_end_matches('/'),
            db = db_name,
            coll = collection
        );

        let resp = client
            .post(&url)
            .basic_auth(user, Some(password))
            .json(&patch)
            .send()
            .await?;

        if !resp.status().is_success() {
            let text = resp.text().await.unwrap_or_default();
            warn!("Arango trajectory insert failed: {}", text);
        }
    }

    Ok(())
}

/// TRUE 8D conflict detection with CPA calculation
fn detect_conflict_8d(a: &AircraftState, b: &AircraftState) -> Option<Conflict8D> {
    // Skip ground traffic (below 500 ft)
    if a.alt_ft < 500.0 && b.alt_ft < 500.0 {
        return None;
    }

    // Current separations
    let horiz_nm = haversine_nm(a.lat, a.lon, b.lat, b.lon);
    let vert_ft = (a.alt_ft - b.alt_ft).abs();

    // FAA/ICAO: Safe if EITHER horizontal >= 5nm OR vertical >= 1000ft
    let currently_safe = horiz_nm >= 5.0 || vert_ft >= 1000.0;

    // Calculate time to Closest Point of Approach (CPA)
    let (time_to_cpa, h_sep_at_cpa, v_sep_at_cpa, is_converging) = 
        calculate_cpa(a, b, horiz_nm, vert_ft);

    // Safe at CPA?
    let cpa_safe = h_sep_at_cpa >= 5.0 || v_sep_at_cpa >= 1000.0;

    // If currently safe AND will be safe at CPA, no conflict
    if currently_safe && cpa_safe {
        return None;
    }

    // If diverging and currently safe, no conflict
    if !is_converging && currently_safe {
        return None;
    }

    // Conflict detected - calculate severity
    let severity = calculate_severity(
        horiz_nm, vert_ft,
        h_sep_at_cpa, v_sep_at_cpa,
        time_to_cpa, is_converging
    );

    // Calculate 8D risk score
    let risk_8d = calculate_risk_8d(
        horiz_nm, vert_ft,
        h_sep_at_cpa, v_sep_at_cpa,
        time_to_cpa, is_converging,
        a, b
    );

    Some(Conflict8D {
        aircraft_a: a.clone(),
        aircraft_b: b.clone(),
        horizontal_nm: horiz_nm,
        vertical_ft: vert_ft,
        time_to_cpa_sec: time_to_cpa,
        h_sep_at_cpa_nm: h_sep_at_cpa,
        v_sep_at_cpa_ft: v_sep_at_cpa,
        is_converging,
        risk_8d,
        severity,
    })
}

/// Calculate Closest Point of Approach (CPA)
/// Returns: (time_to_cpa_seconds, h_separation_at_cpa_nm, v_separation_at_cpa_ft, is_converging)
fn calculate_cpa(a: &AircraftState, b: &AircraftState, current_h: f64, current_v: f64) -> (f64, f64, f64, bool) {
    // Get velocity components
    let (vax, vay) = a.velocity_components();
    let (vbx, vby) = b.velocity_components();

    // Relative velocity (nm/hour)
    let rel_vx = vbx - vax;
    let rel_vy = vby - vay;
    let rel_v_squared = rel_vx * rel_vx + rel_vy * rel_vy;

    // If relative velocity is near zero, they're moving together
    if rel_v_squared < 0.01 {
        return (f64::INFINITY, current_h, current_v, false);
    }

    // Position difference in nm (approximate)
    let dx = (b.lon - a.lon) * 60.0 * a.lat.to_radians().cos();  // nm
    let dy = (b.lat - a.lat) * 60.0;  // nm

    // Time to CPA: t = -(r · v) / |v|²
    let dot_rv = dx * rel_vx + dy * rel_vy;
    let time_to_cpa_hours = -dot_rv / rel_v_squared;

    // If CPA is in the past, use current time
    let time_to_cpa_hours = time_to_cpa_hours.max(0.0);
    let time_to_cpa_sec = time_to_cpa_hours * 3600.0;

    // Cap at 10 minutes (600 seconds) for practical purposes
    let time_to_cpa_sec = time_to_cpa_sec.min(600.0);

    // Position at CPA
    let dx_at_cpa = dx + rel_vx * time_to_cpa_hours;
    let dy_at_cpa = dy + rel_vy * time_to_cpa_hours;
    let h_sep_at_cpa = (dx_at_cpa * dx_at_cpa + dy_at_cpa * dy_at_cpa).sqrt();

    // Vertical separation at CPA
    let rel_vertical_rate = b.vertical_rate_fpm - a.vertical_rate_fpm;  // fpm
    let v_sep_at_cpa = (current_v + rel_vertical_rate * time_to_cpa_hours * 60.0).abs();

    // Is converging? (getting closer)
    let is_converging = h_sep_at_cpa < current_h;

    (time_to_cpa_sec, h_sep_at_cpa, v_sep_at_cpa, is_converging)
}

fn calculate_severity(
    h_now: f64, v_now: f64,
    h_cpa: f64, v_cpa: f64,
    time_to_cpa: f64, is_converging: bool
) -> ConflictSeverity {
    // Current loss of separation (BOTH violated)
    let los_now = h_now < 5.0 && v_now < 1000.0;
    
    // Predicted loss of separation at CPA
    let los_at_cpa = h_cpa < 5.0 && v_cpa < 1000.0;

    if los_now {
        // Already in conflict
        if h_now < 1.0 && v_now < 300.0 {
            ConflictSeverity::Critical
        } else if h_now < 2.0 && v_now < 500.0 {
            ConflictSeverity::High
        } else {
            ConflictSeverity::Medium
        }
    } else if los_at_cpa && is_converging {
        // Predicted conflict
        if time_to_cpa < 60.0 {
            ConflictSeverity::Critical
        } else if time_to_cpa < 120.0 {
            ConflictSeverity::High
        } else if time_to_cpa < 300.0 {
            ConflictSeverity::Medium
        } else {
            ConflictSeverity::Low
        }
    } else {
        ConflictSeverity::Low
    }
}

fn calculate_risk_8d(
    h_now: f64, v_now: f64,
    h_cpa: f64, v_cpa: f64,
    time_to_cpa: f64, is_converging: bool,
    a: &AircraftState, b: &AircraftState
) -> f64 {
    // D0-D1 (Spatial): Current horizontal separation risk
    let spatial_risk = (5.0 - h_now.min(5.0)) / 5.0;
    
    // D2 (Altitude): Current vertical separation risk
    let vertical_risk = (1000.0 - v_now.min(1000.0)) / 1000.0;
    
    // D3 (Time): Time pressure - closer CPA = higher risk
    let time_risk = if time_to_cpa < 600.0 {
        (600.0 - time_to_cpa) / 600.0
    } else {
        0.0
    };
    
    // D4 (Intent): Convergence risk
    let intent_risk = if is_converging {
        // Risk based on how much closer they'll get
        let h_reduction = (h_now - h_cpa).max(0.0);
        (h_reduction / h_now.max(0.1)).min(1.0)
    } else {
        0.0  // Diverging = low intent risk
    };
    
    // D5 (Base risk): From predicted separation at CPA
    let cpa_h_risk = (5.0 - h_cpa.min(5.0)) / 5.0;
    let cpa_v_risk = (1000.0 - v_cpa.min(1000.0)) / 1000.0;
    let base_risk = (cpa_h_risk + cpa_v_risk) / 2.0;
    
    // D6 (Compliance): Speed-based (very fast = less predictable)
    let max_speed = a.velocity_kts.max(b.velocity_kts);
    let compliance_risk = (max_speed / 600.0).min(1.0) * 0.3;
    
    // D7 (Uncertainty): Based on vertical rate (high climb/descent = more uncertain)
    let max_vert_rate = a.vertical_rate_fpm.abs().max(b.vertical_rate_fpm.abs());
    let uncertainty_risk = (max_vert_rate / 3000.0).min(1.0) * 0.5;
    
    // Weighted combination
    let risk = 
        spatial_risk * 0.20 +
        vertical_risk * 0.20 +
        time_risk * 0.20 +
        intent_risk * 0.15 +
        base_risk * 0.15 +
        compliance_risk * 0.05 +
        uncertainty_risk * 0.05;
    
    risk.min(1.0)
}

fn conflict_to_patch(conflict: &Conflict8D, ts: DateTime<Utc>) -> ConflictPatch {
    let a = &conflict.aircraft_a;
    let b = &conflict.aircraft_b;
    
    let center_lat = (a.lat + b.lat) / 2.0;
    let center_lon = (a.lon + b.lon) / 2.0;
    let center_alt_ft = (a.alt_ft + b.alt_ft) / 2.0;
    let center_alt_m = center_alt_ft * 0.3048;

    // Build 8D vector
    let d0 = center_lon / 180.0;
    let d1 = center_lat / 90.0;
    let d2 = (center_alt_m / 15000.0).clamp(0.0, 1.0);
    let d3 = (ts.num_seconds_from_midnight() as f64 / 86400.0).clamp(0.0, 1.0);
    let d4 = if conflict.is_converging { conflict.risk_8d } else { 0.2 };
    let d5 = conflict.risk_8d;
    let d6 = (1.0 - conflict.risk_8d * 0.7).clamp(0.0, 1.0);
    let d7 = (0.1 + conflict.risk_8d * 0.5).clamp(0.0, 1.0);

    ConflictPatch {
        _key: Uuid::new_v4().to_string(),
        scale: "planetary".to_string(),
        context: "planetary:atc_conflict".to_string(),
        center_lat,
        center_lon,
        center_alt_m,
        timestamp: ts,
        d_vec: [d0, d1, d2, d3, d4, d5, d6, d7],
        conflict: ConflictDetails {
            horizontal_nm: conflict.horizontal_nm,
            vertical_ft: conflict.vertical_ft,
            time_to_cpa_sec: conflict.time_to_cpa_sec,
            h_sep_at_cpa_nm: conflict.h_sep_at_cpa_nm,
            v_sep_at_cpa_ft: conflict.v_sep_at_cpa_ft,
            is_converging: conflict.is_converging,
            risk_8d: conflict.risk_8d,
            severity: conflict.severity.as_str().to_string(),
            aircraft: [
                ConflictAircraft {
                    icao24: a.icao24.clone(),
                    callsign: a.callsign.clone(),
                    latitude: a.lat,
                    longitude: a.lon,
                    altitude_ft: a.alt_ft,
                    velocity_kts: a.velocity_kts,
                    heading_deg: a.heading_deg,
                },
                ConflictAircraft {
                    icao24: b.icao24.clone(),
                    callsign: b.callsign.clone(),
                    latitude: b.lat,
                    longitude: b.lon,
                    altitude_ft: b.alt_ft,
                    velocity_kts: b.velocity_kts,
                    heading_deg: b.heading_deg,
                },
            ],
        },
    }
}

/// Haversine distance in nautical miles
fn haversine_nm(lat1: f64, lon1: f64, lat2: f64, lon2: f64) -> f64 {
    let r_earth_nm = 3440.065;

    let lat1_rad = lat1.to_radians();
    let lat2_rad = lat2.to_radians();
    let dlat = (lat2 - lat1).to_radians();
    let dlon = (lon2 - lon1).to_radians();

    let a = (dlat / 2.0).sin().powi(2)
        + lat1_rad.cos() * lat2_rad.cos() * (dlon / 2.0).sin().powi(2);
    let c = 2.0 * a.sqrt().atan2((1.0 - a).sqrt());

    r_earth_nm * c
}
