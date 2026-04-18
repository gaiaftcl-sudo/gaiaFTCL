//! Extended Atmospheric Overlays for ATC World
//!
//! Future layers beyond turbulence:
//! - Storm/Convective Activity
//! - Wake Vortex Prediction
//! - Thermal Plumes
//!
//! Status: Architectural stubs - ready for implementation

use serde::{Deserialize, Serialize};
use geo::{Point, Polygon};

// ═══════════════════════════════════════════════════════════════════════════
// Storm / Convective Activity Layer
// ═══════════════════════════════════════════════════════════════════════════

/// Storm cell detected from satellite/radar data
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StormCell {
    pub id: String,
    pub center: Point<f64>,        // lat, lon
    pub intensity_dbz: f32,        // Radar reflectivity (dBZ)
    pub top_altitude_ft: i32,      // Storm top height
    pub movement_vector: (f32, f32), // (east m/s, north m/s)
    pub severity: StormSeverity,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub enum StormSeverity {
    Light,       // <30 dBZ
    Moderate,    // 30-45 dBZ
    Heavy,       // 45-55 dBZ
    Severe,      // >55 dBZ (hail, tornado risk)
}

/// Data source: NEXRAD, GOES-R satellite, ground radar
pub struct StormOverlayConfig {
    pub nexrad_endpoint: String,
    pub goes_satellite_feed: String,
    pub update_interval_seconds: u64,
}

impl Default for StormOverlayConfig {
    fn default() -> Self {
        Self {
            nexrad_endpoint: "https://noaa.gov/nexrad/api".to_string(),
            goes_satellite_feed: "https://noaa.gov/goes/api".to_string(),
            update_interval_seconds: 300,  // 5 minutes
        }
    }
}

/// Planned: implement storm cell detection and tracking
pub fn fetch_storm_cells(_config: &StormOverlayConfig) -> Vec<StormCell> {
    // Stub: Would query NEXRAD/GOES APIs
    vec![]
}

// ═══════════════════════════════════════════════════════════════════════════
// Wake Vortex Layer
// ═══════════════════════════════════════════════════════════════════════════

/// Wake vortex hazard from leading aircraft
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WakeVortex {
    pub generator_aircraft_icao: String,
    pub generator_weight_class: WeightClass,
    pub vortex_strength: f32,    // Circulation strength (m²/s)
    pub decay_rate: f32,         // Dissipation per second
    pub trail_points: Vec<Point<f64>>,  // Vortex centerline
    pub danger_radius_m: f32,    // Safe separation distance
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub enum WeightClass {
    Super,   // A380, 747-8
    Heavy,   // 777, 747, A330+
    Medium,  // 737, A320
    Light,   // Regional jets, props
}

impl WeightClass {
    pub fn typical_vortex_strength(&self) -> f32 {
        match self {
            Self::Super => 500.0,
            Self::Heavy => 350.0,
            Self::Medium => 200.0,
            Self::Light => 100.0,
        }
    }
    
    pub fn safe_separation_nm(&self) -> f32 {
        match self {
            Self::Super => 8.0,
            Self::Heavy => 6.0,
            Self::Medium => 4.0,
            Self::Light => 2.5,
        }
    }
}

/// Planned: implement wake vortex prediction model
/// Based on:
/// - Aircraft weight class
/// - Ground speed
/// - Atmospheric conditions (wind, temp, stability)
/// - Time since aircraft passage
pub fn predict_wake_vortex(
    _aircraft_icao: &str,
    _weight_class: WeightClass,
    _trail_history: &[Point<f64>],
    _elapsed_seconds: f64,
) -> Option<WakeVortex> {
    // Stub: Would compute vortex decay using circulation model
    None
}

// ═══════════════════════════════════════════════════════════════════════════
// Thermal Plume Layer
// ═══════════════════════════════════════════════════════════════════════════

/// Thermal updraft/downdraft zone (terrain-induced or convective)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ThermalPlume {
    pub id: String,
    pub center: Point<f64>,
    pub radius_m: f32,
    pub vertical_velocity_ms: f32,  // Positive = updraft, negative = downdraft
    pub top_altitude_ft: i32,
    pub source: ThermalSource,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub enum ThermalSource {
    TerrainInduced,    // Mountain wave, rotor
    Convective,        // Solar heating of ground
    UrbanHeatIsland,   // City warmth
    FirePlume,         // Wildfire smoke column
}

/// Planned: implement thermal detection
/// Data sources:
/// - Terrain elevation + wind data → mountain wave prediction
/// - Ground temperature + solar radiation → convective thermal prediction
/// - Urban area detection + temperature → heat island mapping
pub fn detect_thermals(
    _terrain_elevation: &[f32],
    _wind_field: &[f32],
    _ground_temp: &[f32],
) -> Vec<ThermalPlume> {
    // Stub: Would use QFT-Navier-Stokes operator with buoyancy term
    vec![]
}

// ═══════════════════════════════════════════════════════════════════════════
// Combined Hazard Assessment
// ═══════════════════════════════════════════════════════════════════════════

/// Composite hazard score for a given position
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HazardAssessment {
    pub lat: f64,
    pub lon: f64,
    pub alt_ft: i32,
    pub turbulence_score: f32,   // 0-1
    pub storm_score: f32,         // 0-1
    pub wake_vortex_score: f32,   // 0-1
    pub thermal_score: f32,       // 0-1
    pub combined_risk: f32,       // 0-1 (weighted average)
}

/// Planned: implement multi-hazard risk aggregation
/// Combines all atmospheric hazards into single risk metric
pub fn assess_combined_hazard(
    _lat: f64,
    _lon: f64,
    _alt_ft: i32,
    _turbulence_zones: &[crate::TurbulenceZone],
    _storm_cells: &[StormCell],
    _wake_vortices: &[WakeVortex],
    _thermals: &[ThermalPlume],
) -> HazardAssessment {
    // Stub: Would compute weighted risk score
    HazardAssessment {
        lat: _lat,
        lon: _lon,
        alt_ft: _alt_ft,
        turbulence_score: 0.0,
        storm_score: 0.0,
        wake_vortex_score: 0.0,
        thermal_score: 0.0,
        combined_risk: 0.0,
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// API Endpoints (Future)
// ═══════════════════════════════════════════════════════════════════════════

/// GET /api/storm_cells?region={...}
/// GET /api/wake_vortex?following_aircraft={icao}
/// GET /api/thermals?region={...}
/// GET /api/combined_hazard?lat={}&lon={}&alt={}
///
/// These would be added to the Actix data service when implemented

// ═══════════════════════════════════════════════════════════════════════════
// Documentation Note
// ═══════════════════════════════════════════════════════════════════════════

/// **IMPLEMENTATION ROADMAP:**
///
/// 1. **Storm Layer** (2-3 weeks)
///    - Integrate NEXRAD API
///    - Parse GOES-R satellite IR imagery
///    - Render storm cells as colored polygons on map
///    - Test: Hurricane or severe thunderstorm scenario
///
/// 2. **Wake Vortex Layer** (1-2 weeks)
///    - Implement circulation decay model
///    - Track aircraft pairs (leading/following)
///    - Visualize vortex trails as fading lines
///    - Test: Heavy aircraft approach sequence
///
/// 3. **Thermal Layer** (2-3 weeks)
///    - Add QFT-NS buoyancy term to Field World
///    - Query terrain elevation data
///    - Compute mountain wave zones
///    - Test: Low-altitude flight over mountains
///
/// 4. **Combined Hazard** (1 week)
///    - Weight each hazard by severity + proximity
///    - Generate composite risk heatmap
///    - Provide route optimizer API
///    - Test: Multi-hazard routing scenario
///
/// **TOTAL ESTIMATE:** 6-9 weeks for all extended layers

