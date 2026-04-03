//! Normalized flight event + 8D mapping.

use crate::policy::AircraftState;
use chrono::{DateTime, Timelike, Utc};
use serde::Serialize;

#[derive(Debug, Serialize)]
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
    pub source: &'static str,
    pub is_predicted: bool,
    pub vqbit_8d: [f64; 8],
    pub uncertainty: f64,
}

/// Map aircraft state → 8D UUM vector for ATC.
///
/// D0–D2: normalized spatial
/// D3: time of day
/// D4: intent proxy (cruise vs maneuver)
/// D5: risk (high vertical rate, high speed → higher risk)
/// D6: compliance (1 - f(risk))
/// D7: uncertainty (from propagation)
pub fn aircraft_to_8d(ac: &AircraftState) -> [f64; 8] {
    // D0: Longitude normalized [-1, 1]
    let d0 = ac.lon / 180.0;
    
    // D1: Latitude normalized [-1, 1]
    let d1 = ac.lat / 90.0;
    
    // D2: Altitude normalized [0, 1] (assuming 15km max)
    let d2 = (ac.alt_m / 15000.0).clamp(0.0, 1.0);

    // D3: Time of day [0, 1]
    let seconds_since_midnight = ac.last_update.time().num_seconds_from_midnight() as f64;
    let d3 = (seconds_since_midnight / 86400.0).clamp(0.0, 1.0);

    // Speed and climb rate normalized for risk calculation
    let speed_norm = (ac.velocity_ms / 280.0).clamp(0.0, 1.0); // ~280 m/s = Mach 0.85
    let climb_norm = (ac.vertical_rate_ms.abs() / 30.0).clamp(0.0, 1.0); // ~30 m/s = ~6000 fpm

    // D4: Intent proxy (1.0 = stable cruise, lower = maneuvering)
    let d4 = (1.0 - climb_norm * 0.5).clamp(0.0, 1.0);

    // D5: Risk level
    let risk = (speed_norm * 0.4 + climb_norm * 0.6).clamp(0.0, 1.0);
    let d5 = risk;
    
    // D6: Compliance/confidence (inverse of risk)
    let d6 = (1.0 - risk * 0.7).clamp(0.0, 1.0);

    // D7: Uncertainty from prediction propagation
    let unc_norm = (ac.uncertainty / 5.0).clamp(0.0, 1.0);
    let d7 = unc_norm;

    [d0, d1, d2, d3, d4, d5, d6, d7]
}

pub fn aircraft_to_event(ac: &AircraftState, is_predicted: bool) -> FlightEvent {
    let d_vec = aircraft_to_8d(ac);
    FlightEvent {
        icao24: ac.icao24.clone(),
        callsign: ac.callsign.clone(),
        origin_country: ac.origin_country.clone(),
        latitude: ac.lat,
        longitude: ac.lon,
        altitude_m: ac.alt_m,
        altitude_ft: ac.alt_m * 3.28084,
        velocity_ms: ac.velocity_ms,
        ground_speed_kts: ac.velocity_ms * 1.94384,
        heading_deg: ac.heading_deg,
        vertical_rate_ms: ac.vertical_rate_ms,
        vertical_rate_fpm: ac.vertical_rate_ms * 196.85,
        timestamp: ac.last_update,
        timestamp_unix: ac.last_update.timestamp(),
        category: ac.category,
        source: if is_predicted { "prediction" } else { "opensky" },
        is_predicted,
        vqbit_8d: d_vec,
        uncertainty: ac.uncertainty,
    }
}

