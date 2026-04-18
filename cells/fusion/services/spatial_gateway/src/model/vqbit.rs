//! 8-Dimensional UUM Substrate vQbit
//!
//! Every observation is processed as a vector Ψ(world) = [D0..D7]
//!
//! ## Dimensions 0-3: Physical Spacetime (Universal)
//! - D0 (X): East-West position (meters, ENU frame)
//! - D1 (Y): North-South position (meters, ENU frame)
//! - D2 (Z): Altitude (meters, ENU/Ellipsoidal)
//! - D3 (T): Normalized Diurnal Time [0.0, 1.0] where T = (t_unix mod 86400) / 86400.0
//!
//! ## Dimensions 4-7: Semantic & Virtue Layer (Domain-Dependent)
//! - D4 (Env Type): Natural (0.0) ↔ Urban (1.0)
//! - D5 (Use Intensity): Decorative (0.0) ↔ Critical Infrastructure (1.0)
//! - D6 (Social Coherence): Agreement Metric [0.0, 1.0] = min(1.0, N_sources/3.0)
//! - D7 (Uncertainty): Risk/Variance [0.0, 1.0]

use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// Quaternion for orientation (OpenXR compatible)
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct Quaternion {
    pub w: f32,
    pub x: f32,
    pub y: f32,
    pub z: f32,
}

impl Quaternion {
    /// Identity quaternion (no rotation)
    pub fn identity() -> Self {
        Self {
            w: 1.0,
            x: 0.0,
            y: 0.0,
            z: 0.0,
        }
    }

    /// Normalize the quaternion to unit length
    pub fn normalize(&self) -> Self {
        let mag = (self.w.powi(2) + self.x.powi(2) + self.y.powi(2) + self.z.powi(2)).sqrt();
        if mag < 1e-10 {
            return Self::identity();
        }
        Self {
            w: self.w / mag,
            x: self.x / mag,
            y: self.y / mag,
            z: self.z / mag,
        }
    }

    /// Compute dot product with another quaternion (for interpolation)
    #[allow(dead_code)]
    pub fn dot(&self, other: &Quaternion) -> f32 {
        self.w * other.w + self.x * other.x + self.y * other.y + self.z * other.z
    }
}

/// 8D vQbit - the fundamental unit of spatial truth in GaiaOS
///
/// This is the canonical representation that flows through the UUM-8D substrate.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Vqbit8D {
    /// Unique identifier for this vQbit
    pub id: Uuid,
    /// Cell that produced this observation
    pub cell_id: Uuid,
    /// Source identifier (sensor, drone, radar, etc.)
    pub source_id: String,

    // ═══════════════════════════════════════════════════════════════════════
    // DIMENSIONS 0-3: PHYSICAL SPACETIME (Universal)
    // ═══════════════════════════════════════════════════════════════════════
    /// D0: East-West position in meters (ENU frame)
    pub d0_x: f64,
    /// D1: North-South position in meters (ENU frame)
    pub d1_y: f64,
    /// D2: Altitude in meters (ENU frame, Up)
    pub d2_z: f64,
    /// D3: Normalized diurnal time [0.0, 1.0]
    /// Formula: (t_unix mod 86400) / 86400.0
    pub d3_t: f64,

    /// Orientation as quaternion (OpenXR compatible)
    pub orientation: Quaternion,

    // ═══════════════════════════════════════════════════════════════════════
    // DIMENSIONS 4-7: SEMANTIC & VIRTUE LAYER (Domain-Dependent)
    // ═══════════════════════════════════════════════════════════════════════
    /// D4: Environment type
    /// Natural (0.0) ↔ Urban (1.0)
    pub d4_env_type: f32,

    /// D5: Use intensity
    /// Decorative (0.0) ↔ Critical Infrastructure (1.0)
    pub d5_use_intensity: f32,

    /// D6: Social coherence / Agreement metric [0.0, 1.0]
    /// Formula: min(1.0, N_sources / 3.0)
    pub d6_social_coherence: f32,

    /// D7: Uncertainty / Risk / Variance [0.0, 1.0]
    /// Formula: w_s * σ_sensor + w_t * staleness + w_c * conflict
    pub d7_uncertainty: f32,

    // ═══════════════════════════════════════════════════════════════════════
    // METADATA
    // ═══════════════════════════════════════════════════════════════════════
    /// Domain affiliation (ATC, AV, MARITIME, WEATHER, GAME)
    pub domain: String,
    /// Sensor type (RADAR, LIDAR, GPS, CAMERA, etc.)
    pub sensor_type: String,
    /// Original Unix timestamp of observation
    pub timestamp_unix: f64,
    /// Raw sensor uncertainty in meters
    pub raw_uncertainty_m: f32,
    /// Cryptographic signature for FoT validation
    pub signature: Option<String>,
    /// Parent observations this was merged from
    pub parent_observations: Vec<Uuid>,
    /// Whether this has been validated by FoT protocol
    pub fot_validated: bool,
}

impl Vqbit8D {
    /// Create a new vQbit with default semantic values
    pub fn new(
        cell_id: Uuid,
        source_id: String,
        d0_x: f64,
        d1_y: f64,
        d2_z: f64,
        domain: String,
    ) -> Self {
        let now = Self::now_unix();
        Self {
            id: Uuid::new_v4(),
            cell_id,
            source_id,
            d0_x,
            d1_y,
            d2_z,
            d3_t: Self::unix_to_diurnal(now),
            orientation: Quaternion::identity(),
            d4_env_type: 0.5,
            d5_use_intensity: 0.5,
            d6_social_coherence: 0.33, // Single source
            d7_uncertainty: 0.5,
            domain,
            sensor_type: "UNKNOWN".to_string(),
            timestamp_unix: now,
            raw_uncertainty_m: 10.0,
            signature: None,
            parent_observations: vec![],
            fot_validated: false,
        }
    }

    /// Get current Unix timestamp
    pub fn now_unix() -> f64 {
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_secs_f64()
    }

    /// Convert Unix timestamp to normalized diurnal time [0.0, 1.0]
    pub fn unix_to_diurnal(t_unix: f64) -> f64 {
        (t_unix % 86400.0) / 86400.0
    }

    /// Get the 8D position as an array [D0, D1, D2, D3, D4, D5, D6, D7]
    #[allow(dead_code)]
    pub fn to_vec8(&self) -> [f64; 8] {
        [
            self.d0_x,
            self.d1_y,
            self.d2_z,
            self.d3_t,
            self.d4_env_type as f64,
            self.d5_use_intensity as f64,
            self.d6_social_coherence as f64,
            self.d7_uncertainty as f64,
        ]
    }

    /// Compute Euclidean distance in physical space (D0-D2 only)
    #[allow(dead_code)]
    pub fn spatial_distance(&self, other: &Vqbit8D) -> f64 {
        let dx = self.d0_x - other.d0_x;
        let dy = self.d1_y - other.d1_y;
        let dz = self.d2_z - other.d2_z;
        (dx * dx + dy * dy + dz * dz).sqrt()
    }

    /// Compute temporal distance in normalized time
    #[allow(dead_code)]
    pub fn temporal_distance(&self, other: &Vqbit8D) -> f64 {
        (self.d3_t - other.d3_t).abs()
    }

    /// Compute full 8D distance (weighted)
    #[allow(dead_code)]
    pub fn distance_8d(&self, other: &Vqbit8D, weights: &[f64; 8]) -> f64 {
        let v1 = self.to_vec8();
        let v2 = other.to_vec8();

        let mut sum = 0.0;
        for i in 0..8 {
            let d = v1[i] - v2[i];
            sum += weights[i] * d * d;
        }
        sum.sqrt()
    }

    /// Compute uncertainty score based on sensor, staleness, and conflict
    pub fn compute_uncertainty(
        sensor_uncertainty_m: f32,
        now: f64,
        observation_time: f64,
        sensor_type: &str,
    ) -> f32 {
        // Base uncertainty from sensor (normalized to [0,1])
        let base = (sensor_uncertainty_m / 100.0).min(1.0);

        // Age-based staleness
        let age = (now - observation_time).abs();
        let staleness = match sensor_type.to_uppercase().as_str() {
            "RADAR" | "LIDAR" => (age / 10.0).min(1.0) as f32, // Fast decay
            "GPS" => (age / 60.0).min(1.0) as f32,             // Medium decay
            "RTK" | "DGPS" => (age / 120.0).min(1.0) as f32,   // Slow decay
            _ => (age / 30.0).min(1.0) as f32,                 // Default
        };

        // Weighted combination
        (0.6 * base + 0.4 * staleness).min(1.0)
    }

    /// Compute social coherence from number of agreeing sources
    #[allow(dead_code)]
    pub fn compute_social_coherence(num_sources: usize) -> f32 {
        (num_sources as f32 / 3.0).min(1.0)
    }
}

impl Default for Vqbit8D {
    fn default() -> Self {
        Self::new(
            Uuid::nil(),
            "default".to_string(),
            0.0,
            0.0,
            0.0,
            "UNKNOWN".to_string(),
        )
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// GEODETIC COORDINATE TRANSFORMATION
// ═══════════════════════════════════════════════════════════════════════════

/// WGS84 Geodetic coordinates (lat/lon/alt)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GeodeticCoord {
    pub lat_deg: f64,
    pub lon_deg: f64,
    pub alt_m: f64,
}

/// East-North-Up local coordinates (meters)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EnuCoord {
    pub east_m: f64,
    pub north_m: f64,
    pub up_m: f64,
}

/// Cell origin for ENU transformation
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CellOrigin {
    pub lat0_deg: f64,
    pub lon0_deg: f64,
    pub alt0_m: f64,
}

impl CellOrigin {
    /// Load cell origin from environment variables
    pub fn from_env() -> Self {
        Self {
            lat0_deg: std::env::var("CELL_ORIGIN_LAT")
                .ok()
                .and_then(|s| s.parse().ok())
                .unwrap_or(0.0),
            lon0_deg: std::env::var("CELL_ORIGIN_LON")
                .ok()
                .and_then(|s| s.parse().ok())
                .unwrap_or(0.0),
            alt0_m: std::env::var("CELL_ORIGIN_ALT")
                .ok()
                .and_then(|s| s.parse().ok())
                .unwrap_or(0.0),
        }
    }
}

/// Convert WGS84 geodetic coordinates to ENU local coordinates
///
/// Uses the standard ECEF → ENU transformation with WGS84 ellipsoid parameters.
///
/// # Arguments
/// * `geo` - Geodetic coordinates (lat/lon/alt)
/// * `origin` - Cell origin for local coordinate system
///
/// # Returns
/// East-North-Up coordinates in meters relative to origin
pub fn geodetic_to_enu(geo: &GeodeticCoord, origin: &CellOrigin) -> EnuCoord {
    // WGS84 ellipsoid parameters
    const A: f64 = 6378137.0; // Semi-major axis (meters)
    const E2: f64 = 0.00669437999014; // First eccentricity squared

    // Convert to radians
    let lat = geo.lat_deg.to_radians();
    let lon = geo.lon_deg.to_radians();
    let lat0 = origin.lat0_deg.to_radians();
    let lon0 = origin.lon0_deg.to_radians();

    // Radius of curvature in the prime vertical
    let n = A / (1.0 - E2 * lat.sin().powi(2)).sqrt();
    let n0 = A / (1.0 - E2 * lat0.sin().powi(2)).sqrt();

    // ECEF coordinates of observation point
    let x = (n + geo.alt_m) * lat.cos() * lon.cos();
    let y = (n + geo.alt_m) * lat.cos() * lon.sin();
    let z = (n * (1.0 - E2) + geo.alt_m) * lat.sin();

    // ECEF coordinates of origin
    let x0 = (n0 + origin.alt0_m) * lat0.cos() * lon0.cos();
    let y0 = (n0 + origin.alt0_m) * lat0.cos() * lon0.sin();
    let z0 = (n0 * (1.0 - E2) + origin.alt0_m) * lat0.sin();

    // Difference vector
    let dx = x - x0;
    let dy = y - y0;
    let dz = z - z0;

    // Rotation matrix from ECEF to ENU
    EnuCoord {
        east_m: -lon0.sin() * dx + lon0.cos() * dy,
        north_m: -lat0.sin() * lon0.cos() * dx - lat0.sin() * lon0.sin() * dy + lat0.cos() * dz,
        up_m: lat0.cos() * lon0.cos() * dx + lat0.cos() * lon0.sin() * dy + lat0.sin() * dz,
    }
}

/// Convert ENU local coordinates back to WGS84 geodetic
/// (Inverse transformation)
#[allow(dead_code)]
pub fn enu_to_geodetic(enu: &EnuCoord, origin: &CellOrigin) -> GeodeticCoord {
    const A: f64 = 6378137.0;
    const E2: f64 = 0.00669437999014;

    let lat0 = origin.lat0_deg.to_radians();
    let lon0 = origin.lon0_deg.to_radians();

    // Rotation matrix from ENU to ECEF
    let dx = -lon0.sin() * enu.east_m - lat0.sin() * lon0.cos() * enu.north_m
        + lat0.cos() * lon0.cos() * enu.up_m;
    let dy = lon0.cos() * enu.east_m - lat0.sin() * lon0.sin() * enu.north_m
        + lat0.cos() * lon0.sin() * enu.up_m;
    let dz = lat0.cos() * enu.north_m + lat0.sin() * enu.up_m;

    // Origin ECEF
    let n0 = A / (1.0 - E2 * lat0.sin().powi(2)).sqrt();
    let x0 = (n0 + origin.alt0_m) * lat0.cos() * lon0.cos();
    let y0 = (n0 + origin.alt0_m) * lat0.cos() * lon0.sin();
    let z0 = (n0 * (1.0 - E2) + origin.alt0_m) * lat0.sin();

    // Target ECEF
    let x = x0 + dx;
    let y = y0 + dy;
    let z = z0 + dz;

    // Iterative conversion ECEF -> Geodetic (Bowring's method)
    let p = (x * x + y * y).sqrt();
    let lon = y.atan2(x);

    // Initial latitude estimate
    let mut lat = z.atan2(p * (1.0 - E2));

    for _ in 0..10 {
        let n = A / (1.0 - E2 * lat.sin().powi(2)).sqrt();
        let new_lat = (z + E2 * n * lat.sin()).atan2(p);
        if (new_lat - lat).abs() < 1e-12 {
            break;
        }
        lat = new_lat;
    }

    let n = A / (1.0 - E2 * lat.sin().powi(2)).sqrt();
    let alt = p / lat.cos() - n;

    GeodeticCoord {
        lat_deg: lat.to_degrees(),
        lon_deg: lon.to_degrees(),
        alt_m: alt,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_enu_roundtrip() {
        let origin = CellOrigin {
            lat0_deg: 41.36,
            lon0_deg: -72.07,
            alt0_m: 15.0,
        };

        // Point 1km east, 1km north, 100m up
        let geo = GeodeticCoord {
            lat_deg: 41.369,
            lon_deg: -72.058,
            alt_m: 115.0,
        };

        let enu = geodetic_to_enu(&geo, &origin);
        let back = enu_to_geodetic(&enu, &origin);

        assert!((geo.lat_deg - back.lat_deg).abs() < 0.0001);
        assert!((geo.lon_deg - back.lon_deg).abs() < 0.0001);
    }

    #[test]
    fn test_uncertainty_computation() {
        let now = 1000.0;

        // Fresh RTK reading
        let u1 = Vqbit8D::compute_uncertainty(0.02, now, now - 1.0, "RTK");
        assert!(u1 < 0.1);

        // Stale GPS reading
        let u2 = Vqbit8D::compute_uncertainty(5.0, now, now - 120.0, "GPS");
        assert!(u2 > 0.5);
    }

    #[test]
    fn test_social_coherence() {
        assert_eq!(Vqbit8D::compute_social_coherence(1), 1.0 / 3.0);
        assert_eq!(Vqbit8D::compute_social_coherence(3), 1.0);
        assert_eq!(Vqbit8D::compute_social_coherence(5), 1.0);
    }
}
