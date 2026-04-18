//! 8D Projector Service (Production Version)
//!
//! Converts GeoPose payloads into full 8D vQbits for the UUM substrate.
//!
//! ## Projection Pipeline
//! 1. GeoPose (WGS84) → ENU local coordinates (D0-D2)
//! 2. Unix timestamp → Normalized diurnal time (D3)
//! 3. LLM classification → Environment type (D4), Use intensity (D5)
//! 4. Initial social coherence (D6 = 0.33 for single source)
//! 5. Sensor + staleness → Uncertainty (D7)

use crate::model::messages::{GeoPosePayload, Position};
use crate::model::vqbit::{geodetic_to_enu, CellOrigin, GeodeticCoord, Quaternion, Vqbit8D};
use uuid::Uuid;

/// Projection errors
#[derive(Debug)]
#[allow(dead_code)]
pub enum ProjectionError {
    NetworkError(String),
    ParsingError(String),
    /// Reserved for input validation errors
    InvalidInput(String),
}

impl std::fmt::Display for ProjectionError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::NetworkError(e) => write!(f, "Network error: {e}"),
            Self::ParsingError(e) => write!(f, "Parsing error: {e}"),
            Self::InvalidInput(e) => write!(f, "Invalid input: {e}"),
        }
    }
}

/// 8D Projector - converts sensor data to vQbits
pub struct Projector8D {
    /// Cell origin for ENU transformation
    cell_origin: CellOrigin,
    /// LLM endpoint for semantic classification
    #[allow(dead_code)]
    llm_endpoint: String,
    /// HTTP client for LLM calls
    #[allow(dead_code)]
    http: reqwest::Client,
    /// Cell ID
    cell_id: Uuid,
}

impl Projector8D {
    /// Create a new projector
    pub fn new(cell_origin: CellOrigin, llm_endpoint: String, cell_id: Uuid) -> Self {
        Self {
            cell_origin,
            llm_endpoint,
            http: reqwest::Client::new(),
            cell_id,
        }
    }

    /// Create from environment variables
    #[allow(dead_code)]
    pub fn from_env() -> Self {
        let cell_id = std::env::var("CELL_ID")
            .ok()
            .and_then(|s| Uuid::parse_str(&s).ok())
            .unwrap_or_else(Uuid::new_v4);

        let llm_endpoint = std::env::var("LLM_ENDPOINT")
            .unwrap_or_else(|_| "http://gaiaos-llm-router:11434/api/generate".to_string());

        Self::new(CellOrigin::from_env(), llm_endpoint, cell_id)
    }

    /// Project a GeoPose to a full 8D vQbit
    #[allow(dead_code)]
    pub async fn project(
        &self,
        geopose: &GeoPosePayload,
        source_id: String,
        domain: String,
        sensor_type: String,
    ) -> Result<Vqbit8D, ProjectionError> {
        // Step 1: Convert WGS84 to ENU (D0-D2)
        let geo = GeodeticCoord {
            lat_deg: geopose.position.lat,
            lon_deg: geopose.position.lon,
            alt_m: geopose.position.alt,
        };
        let enu = geodetic_to_enu(&geo, &self.cell_origin);

        // Step 2: Compute normalized diurnal time (D3)
        let now = Vqbit8D::now_unix();
        let d3_t = Vqbit8D::unix_to_diurnal(now);

        // Step 3: Classify semantics via LLM (D4, D5)
        let (d4_env, d5_use) = self
            .classify_semantics(&geopose.position, &domain)
            .await
            .unwrap_or((0.5, 0.5)); // Default on failure

        // Step 4: Compute uncertainty (D7)
        let observation_time = now; // Use current time if not in payload
        let d7_uncertainty = Vqbit8D::compute_uncertainty(
            geopose.uncertainty_m,
            now,
            observation_time,
            &sensor_type,
        );

        // Step 5: Build vQbit
        Ok(Vqbit8D {
            id: Uuid::new_v4(),
            cell_id: self.cell_id,
            source_id,

            // D0-D3: Physical spacetime
            d0_x: enu.east_m,
            d1_y: enu.north_m,
            d2_z: enu.up_m,
            d3_t,

            // Orientation
            orientation: Quaternion {
                w: geopose.orientation.w,
                x: geopose.orientation.x,
                y: geopose.orientation.y,
                z: geopose.orientation.z,
            }
            .normalize(),

            // D4-D7: Semantic/virtue layer
            d4_env_type: d4_env,
            d5_use_intensity: d5_use,
            d6_social_coherence: 0.33, // Single source
            d7_uncertainty,

            // Metadata
            domain,
            sensor_type,
            timestamp_unix: now,
            raw_uncertainty_m: geopose.uncertainty_m,
            signature: None,
            parent_observations: vec![],
            fot_validated: false,
        })
    }

    /// Classify D4 (env_type) and D5 (use_intensity) via LLM
    #[allow(dead_code)]
    async fn classify_semantics(
        &self,
        pos: &Position,
        domain: &str,
    ) -> Result<(f32, f32), ProjectionError> {
        // Build prompt for semantic classification
        let prompt = format!(
            r#"You are a spatial classification system. Given a geographic location, classify it.

Location: Latitude {:.6}, Longitude {:.6}
Domain: {}

Respond with ONLY valid JSON (no markdown, no explanation):
{{"env_type": <float 0-1 where 0=natural/wilderness, 1=urban/built>, "use_intensity": <float 0-1 where 0=decorative/passive, 1=critical infrastructure>}}"#,
            pos.lat, pos.lon, domain
        );

        // Call LLM endpoint
        let response = self
            .http
            .post(&self.llm_endpoint)
            .json(&serde_json::json!({
                "model": "gaialm",
                "prompt": prompt,
                "stream": false,
                "options": {
                    "temperature": 0.1,
                    "num_predict": 100
                }
            }))
            .timeout(std::time::Duration::from_secs(5))
            .send()
            .await
            .map_err(|e| ProjectionError::NetworkError(e.to_string()))?;

        if !response.status().is_success() {
            return Err(ProjectionError::NetworkError(format!(
                "LLM returned status {}",
                response.status()
            )));
        }

        let result: serde_json::Value = response
            .json()
            .await
            .map_err(|e| ProjectionError::ParsingError(e.to_string()))?;

        // Parse LLM response
        let response_text = result["response"]
            .as_str()
            .ok_or_else(|| ProjectionError::ParsingError("No response field".to_string()))?;

        // Try to parse JSON from response
        let parsed: serde_json::Value = serde_json::from_str(response_text.trim())
            .map_err(|e| ProjectionError::ParsingError(format!("Invalid JSON: {e}")))?;

        let env_type = parsed["env_type"].as_f64().unwrap_or(0.5) as f32;
        let use_intensity = parsed["use_intensity"].as_f64().unwrap_or(0.5) as f32;

        Ok((env_type.clamp(0.0, 1.0), use_intensity.clamp(0.0, 1.0)))
    }

    /// Project with default semantic values (no LLM call)
    pub fn project_fast(
        &self,
        geopose: &GeoPosePayload,
        source_id: String,
        domain: String,
        sensor_type: String,
    ) -> Vqbit8D {
        let geo = GeodeticCoord {
            lat_deg: geopose.position.lat,
            lon_deg: geopose.position.lon,
            alt_m: geopose.position.alt,
        };
        let enu = geodetic_to_enu(&geo, &self.cell_origin);

        let now = Vqbit8D::now_unix();

        // Use domain-based defaults for D4/D5
        let (d4_env, d5_use) = self.domain_defaults(&domain);

        let d7_uncertainty =
            Vqbit8D::compute_uncertainty(geopose.uncertainty_m, now, now, &sensor_type);

        Vqbit8D {
            id: Uuid::new_v4(),
            cell_id: self.cell_id,
            source_id,
            d0_x: enu.east_m,
            d1_y: enu.north_m,
            d2_z: enu.up_m,
            d3_t: Vqbit8D::unix_to_diurnal(now),
            orientation: Quaternion {
                w: geopose.orientation.w,
                x: geopose.orientation.x,
                y: geopose.orientation.y,
                z: geopose.orientation.z,
            }
            .normalize(),
            d4_env_type: d4_env,
            d5_use_intensity: d5_use,
            d6_social_coherence: 0.33,
            d7_uncertainty,
            domain,
            sensor_type,
            timestamp_unix: now,
            raw_uncertainty_m: geopose.uncertainty_m,
            signature: None,
            parent_observations: vec![],
            fot_validated: false,
        }
    }

    /// Get default D4/D5 values based on domain
    fn domain_defaults(&self, domain: &str) -> (f32, f32) {
        match domain.to_uppercase().as_str() {
            "ATC" => (0.2, 0.95),           // Airports are built, critical
            "AV" => (0.7, 0.6),             // Roads vary, moderate intensity
            "MARITIME" => (0.1, 0.5),       // Mostly water, moderate
            "WEATHER" => (0.5, 0.3),        // Neutral, passive
            "GAME" => (0.5, 0.1),           // Varies, decorative
            "INFRASTRUCTURE" => (0.9, 0.9), // Urban, critical
            _ => (0.5, 0.5),                // Default
        }
    }
}

/// Source trust calculation based on sensor type
#[allow(dead_code)]
pub fn calculate_source_trust(sensor_type: &str, uncertainty_m: f32) -> f32 {
    // Base trust from sensor type
    let sensor_trust = match sensor_type.to_uppercase().as_str() {
        "RTK" => 0.99,
        "DGPS" => 0.95,
        "LIDAR" => 0.90,
        "RADAR" => 0.85,
        "GPS" | "GNSS" => 0.75,
        "CAMERA" | "VISION" => 0.70,
        "IMU" => 0.65,
        "WIFI" => 0.50,
        "CELL" | "CELLULAR" => 0.40,
        _ => 0.60,
    };

    // Adjust by uncertainty
    let uncertainty_factor = if uncertainty_m <= 0.1 {
        1.0
    } else if uncertainty_m <= 1.0 {
        0.95
    } else if uncertainty_m <= 5.0 {
        0.85
    } else if uncertainty_m <= 10.0 {
        0.70
    } else {
        0.50
    };

    let result: f32 = sensor_trust * uncertainty_factor;
    result.clamp(0.0, 1.0)
}

/// Convert lat/lon to approximate meters (Haversine)
#[allow(dead_code)]
pub fn haversine_distance(lat1: f64, lon1: f64, lat2: f64, lon2: f64) -> f64 {
    const EARTH_RADIUS_M: f64 = 6_371_000.0;

    let lat1_rad = lat1.to_radians();
    let lat2_rad = lat2.to_radians();
    let dlat = (lat2 - lat1).to_radians();
    let dlon = (lon2 - lon1).to_radians();

    let a =
        (dlat / 2.0).sin().powi(2) + lat1_rad.cos() * lat2_rad.cos() * (dlon / 2.0).sin().powi(2);
    let c = 2.0 * a.sqrt().atan2((1.0 - a).sqrt());

    EARTH_RADIUS_M * c
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_haversine() {
        // NYC to LA approximately 3944 km
        let dist = haversine_distance(40.7128, -74.0060, 34.0522, -118.2437);
        assert!(dist > 3_900_000.0 && dist < 4_000_000.0);
    }

    #[test]
    fn test_source_trust() {
        assert!(calculate_source_trust("RTK", 0.02) > 0.95);
        assert!(calculate_source_trust("GPS", 5.0) < 0.70);
        assert!(calculate_source_trust("WIFI", 50.0) < 0.40);
    }
}
