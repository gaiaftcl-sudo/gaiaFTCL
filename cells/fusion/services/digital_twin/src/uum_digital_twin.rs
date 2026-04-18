/*!
 * UUM 8D Coordinates - Updated for Digital Twin Cell
 * 
 * Adds methods required by digital_twin cell:
 * - from_lat_lon_alt() - Constructor
 * - update_from_lat_lon_alt() - Update coordinates
 * - lat_deg(), lon_deg(), alt_m() - Accessors
 */

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

/// UUM 8D coordinates for an entity
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UUM8D {
    /// D0: Longitude (X) - normalized to [-1, 1]
    pub d0_lon: f64,
    
    /// D1: Latitude (Y) - normalized to [-1, 1]
    pub d1_lat: f64,
    
    /// D2: Altitude (Z) - normalized to [0, 1]
    pub d2_alt: f64,
    
    /// D3: Time (T) - normalized flow parameter
    pub d3_time: f64,
    
    /// D4: Intent - derived from heading/destination
    pub d4_intent: f64,
    
    /// D5: Risk - conflict proximity score
    pub d5_risk: f64,
    
    /// D6: Compliance - regulatory adherence
    pub d6_comply: f64,
    
    /// D7: Uncertainty - measurement confidence
    pub d7_uncert: f64,
    
    // Raw values for reconstruction
    lat_deg_raw: f64,
    lon_deg_raw: f64,
    alt_m_raw: f64,
}

impl UUM8D {
    /// Create UUM8D from latitude, longitude, altitude
    pub fn from_lat_lon_alt(
        lat_deg: f64,
        lon_deg: f64,
        alt_m: f64,
        timestamp: DateTime<Utc>,
    ) -> Self {
        let mut uum = Self {
            d0_lon: 0.0,
            d1_lat: 0.0,
            d2_alt: 0.0,
            d3_time: 0.0,
            d4_intent: 0.5,  // Unknown intent initially
            d5_risk: 0.0,
            d6_comply: 1.0,  // Assume compliant initially
            d7_uncert: 0.1,  // Low uncertainty initially
            lat_deg_raw: lat_deg,
            lon_deg_raw: lon_deg,
            alt_m_raw: alt_m,
        };
        
        uum.update_spatial_coords(lat_deg, lon_deg, alt_m, timestamp);
        uum
    }
    
    /// Update UUM8D coordinates from physical location
    pub fn update_from_lat_lon_alt(
        &mut self,
        lat_deg: f64,
        lon_deg: f64,
        alt_m: f64,
        timestamp: DateTime<Utc>,
        heading_deg_true: f64,
    ) {
        self.lat_deg_raw = lat_deg;
        self.lon_deg_raw = lon_deg;
        self.alt_m_raw = alt_m;
        
        self.update_spatial_coords(lat_deg, lon_deg, alt_m, timestamp);
        
        // Update intent based on heading (simplified)
        self.d4_intent = (heading_deg_true % 360.0) / 360.0;
    }
    
    fn update_spatial_coords(
        &mut self,
        lat_deg: f64,
        lon_deg: f64,
        alt_m: f64,
        timestamp: DateTime<Utc>,
    ) {
        // D0: Longitude [-1, 1]
        self.d0_lon = (lon_deg + 180.0) / 360.0 * 2.0 - 1.0;
        
        // D1: Latitude [-1, 1]
        self.d1_lat = (lat_deg + 90.0) / 180.0 * 2.0 - 1.0;
        
        // D2: Altitude [0, 1] (normalized to FL600 = 18,288m)
        const MAX_ALT_M: f64 = 18288.0;
        self.d2_alt = (alt_m / MAX_ALT_M).max(0.0).min(1.0);
        
        // D3: Time [0, 1] (daily cycle)
        let seconds_of_day = timestamp.num_seconds_from_midnight() as f64;
        self.d3_time = seconds_of_day / 86400.0;
    }
    
    /// Get latitude in degrees
    pub fn lat_deg(&self) -> f64 {
        self.lat_deg_raw
    }
    
    /// Get longitude in degrees
    pub fn lon_deg(&self) -> f64 {
        self.lon_deg_raw
    }
    
    /// Get altitude in meters
    pub fn alt_m(&self) -> f64 {
        self.alt_m_raw
    }
    
    /// Get altitude in feet
    pub fn alt_ft(&self) -> f64 {
        self.alt_m_raw * 3.28084
    }
    
    /// Get flight level (altitude / 100ft)
    pub fn flight_level(&self) -> u32 {
        (self.alt_ft() / 100.0).round() as u32
    }
}

impl Default for UUM8D {
    fn default() -> Self {
        Self {
            d0_lon: 0.0,
            d1_lat: 0.0,
            d2_alt: 0.0,
            d3_time: 0.0,
            d4_intent: 0.5,
            d5_risk: 0.0,
            d6_comply: 1.0,
            d7_uncert: 0.1,
            lat_deg_raw: 0.0,
            lon_deg_raw: 0.0,
            alt_m_raw: 0.0,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_uum8d_from_lat_lon_alt() {
        let uum = UUM8D::from_lat_lon_alt(
            40.6413,   // JFK latitude
            -73.7781,  // JFK longitude
            10668.0,   // 35,000ft in meters
            Utc::now(),
        );
        
        assert_eq!(uum.lat_deg(), 40.6413);
        assert_eq!(uum.lon_deg(), -73.7781);
        assert_eq!(uum.alt_m(), 10668.0);
        assert!((uum.alt_ft() - 35000.0).abs() < 10.0);
    }
    
    #[test]
    fn test_uum8d_update() {
        let mut uum = UUM8D::from_lat_lon_alt(40.0, -74.0, 10000.0, Utc::now());
        
        uum.update_from_lat_lon_alt(
            41.0,
            -75.0,
            11000.0,
            Utc::now(),
            90.0, // heading east
        );
        
        assert_eq!(uum.lat_deg(), 41.0);
        assert_eq!(uum.lon_deg(), -75.0);
        assert_eq!(uum.alt_m(), 11000.0);
    }
    
    #[test]
    fn test_uum8d_normalization() {
        let uum = UUM8D::from_lat_lon_alt(0.0, 0.0, 0.0, Utc::now());
        
        // Lon 0° should map to ~0.0 in normalized space
        assert!((uum.d0_lon - 0.0).abs() < 0.1);
        
        // Lat 0° should map to ~0.0 in normalized space
        assert!((uum.d1_lat - 0.0).abs() < 0.1);
        
        // Alt 0m should map to 0.0
        assert_eq!(uum.d2_alt, 0.0);
    }
}
