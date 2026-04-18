use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

#[derive(Debug, Deserialize)]
pub struct SnapshotRequest {
    pub lat: f64,
    pub lon: f64,
    /// Radius in kilometers around (lat, lon)
    #[serde(default = "default_radius_km")]
    pub radius_km: f64,
    /// Seconds back from now for time window
    #[serde(default = "default_seconds_back")]
    pub seconds_back: i64,
    /// Seconds forward from now for time window (for slightly future-projected patches)
    #[serde(default = "default_seconds_forward")]
    pub seconds_forward: i64,
}

fn default_radius_km() -> f64 {
    250.0
}

fn default_seconds_back() -> i64 {
    900
}

fn default_seconds_forward() -> i64 {
    60
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct Patch {
    #[serde(rename = "_key")]
    pub key: Option<String>,
    pub scale: Option<String>,
    pub context: Option<String>,
    pub center_lat: Option<f64>,
    pub center_lon: Option<f64>,
    pub center_alt_m: Option<f64>,
    /// Stored in Arango as string ISO8601; we deserialize as string for simplicity
    pub timestamp: Option<String>,
    pub d_vec: Option<Vec<f64>>,
    /// Added by the query via MERGE, may be absent for legacy docs
    #[serde(default)]
    pub distance_m: Option<f64>,
    /// Observer metadata (for observer patches)
    #[serde(default)]
    pub observer: Option<ObserverMeta>,
    /// Weather-specific fields
    pub temperature_c: Option<f64>,
    pub humidity_pct: Option<f64>,
    pub wind_speed_ms: Option<f64>,
    pub visibility_m: Option<f64>,
    /// ATC-specific fields
    pub icao24: Option<String>,
    pub callsign: Option<String>,
    pub altitude_m: Option<f64>,
    pub velocity_ms: Option<f64>,
    pub heading_deg: Option<f64>,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct ObserverMeta {
    pub cell_id: Option<String>,
    pub observer_name: Option<String>,
    pub host: Option<String>,
    pub kind: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct SnapshotResponse {
    pub center_lat: f64,
    pub center_lon: f64,
    pub radius_km: f64,
    pub t_min: DateTime<Utc>,
    pub t_max: DateTime<Utc>,
    pub atc_count: usize,
    pub weather_count: usize,
    pub observer_count: usize,
    pub conflict_count: usize,
    pub atc: Vec<Patch>,
    pub weather: Vec<Patch>,
    pub observers: Vec<Patch>,
    pub conflicts: Vec<Patch>,
}

#[derive(Debug, Serialize)]
pub struct HealthResponse {
    pub status: &'static str,
    pub service: &'static str,
    pub info: &'static str,
}

