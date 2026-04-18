// services/akg_gnn/src/context_manager.rs
// Scale-aware context management for unified 8D substrate

use std::collections::HashMap;

/// Configuration for a specific scale context
#[derive(Debug, Clone)]
pub struct ScaleConfig {
    pub name: String,
    pub default_patch_radius: f64,
    pub distance_weights: [f64; 8],
    pub unit_labels: [&'static str; 8],
    pub normalization_factors: [f64; 8],
}

/// Manages scale contexts (quantum, planetary, astronomical)
pub struct ContextManager {
    configs: HashMap<String, ScaleConfig>,
}

impl ContextManager {
    pub fn new() -> Self {
        let mut configs = HashMap::new();
        
        // Quantum Scale (Angstroms, femtoseconds)
        configs.insert("quantum".to_string(), ScaleConfig {
            name: "quantum".to_string(),
            default_patch_radius: 20.0, // 20 Angstroms
            distance_weights: [
                1.0,  // D0: X position
                1.0,  // D1: Y position
                1.0,  // D2: Z position
                0.5,  // D3: Time (less critical for static structures)
                0.8,  // D4: Intent (reaction type)
                1.2,  // D5: Risk (stability critical)
                1.0,  // D6: Compliance (physical laws)
                0.7,  // D7: Uncertainty
            ],
            unit_labels: ["Å", "Å", "Å", "fs", "enum", "0-1", "0-1", "0-1"],
            normalization_factors: [1.0, 1.0, 1.0, 1e-15, 1.0, 1.0, 1.0, 1.0],
        });
        
        // Planetary Scale (degrees, meters, seconds)
        configs.insert("planetary".to_string(), ScaleConfig {
            name: "planetary".to_string(),
            default_patch_radius: 100_000.0, // 100 km
            distance_weights: [
                1.0,  // D0: Longitude
                1.0,  // D1: Latitude
                0.8,  // D2: Altitude (less discriminating)
                1.5,  // D3: Time (CRITICAL for ATC!)
                0.7,  // D4: Intent
                1.3,  // D5: Risk (collision critical)
                1.0,  // D6: Compliance
                0.6,  // D7: Uncertainty
            ],
            unit_labels: ["deg", "deg", "m", "s", "enum", "0-1", "0-1", "0-1"],
            normalization_factors: [1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0],
        });
        
        // Astronomical Scale (hours, degrees, AU, days)
        configs.insert("astronomical".to_string(), ScaleConfig {
            name: "astronomical".to_string(),
            default_patch_radius: 1.0, // 1 AU
            distance_weights: [
                1.0,  // D0: Right Ascension
                1.0,  // D1: Declination
                1.2,  // D2: Distance (critical for orbital mechanics)
                0.3,  // D3: Time (less urgent at cosmic scales)
                0.5,  // D4: Intent
                1.5,  // D5: Risk (debris, conjunctions)
                0.8,  // D6: Compliance
                0.4,  // D7: Uncertainty
            ],
            unit_labels: ["h", "deg", "AU", "days", "enum", "0-1", "0-1", "0-1"],
            normalization_factors: [15.0, 1.0, 1.496e11, 86400.0, 1.0, 1.0, 1.0, 1.0],
        });
        
        Self { configs }
    }
    
    /// Get configuration for a specific scale
    pub fn get_scale_config(&self, scale: &str) -> Option<ScaleConfig> {
        self.configs.get(scale).cloned()
    }
    
    /// List all available contexts
    pub fn list_contexts(&self) -> Vec<String> {
        self.configs.keys().cloned().collect()
    }
    
    /// Normalize coordinates from external units to internal representation
    pub fn normalize_coords(&self, scale: &str, coords: &[f64; 8]) -> [f64; 8] {
        let config = match self.configs.get(scale) {
            Some(c) => c,
            None => return *coords,
        };
        
        let mut normalized = [0.0; 8];
        for i in 0..8 {
            normalized[i] = coords[i] / config.normalization_factors[i];
        }
        normalized
    }
    
    /// Denormalize coordinates from internal to external units
    pub fn denormalize_coords(&self, scale: &str, coords: &[f64; 8]) -> [f64; 8] {
        let config = match self.configs.get(scale) {
            Some(c) => c,
            None => return *coords,
        };
        
        let mut denormalized = [0.0; 8];
        for i in 0..8 {
            denormalized[i] = coords[i] * config.normalization_factors[i];
        }
        denormalized
    }
    
    /// Compute weighted 8D distance between two points
    pub fn weighted_distance(&self, scale: &str, a: &[f64; 8], b: &[f64; 8]) -> f64 {
        let weights = match self.configs.get(scale) {
            Some(c) => c.distance_weights,
            None => [1.0; 8],
        };
        
        let mut sum = 0.0;
        for i in 0..8 {
            let diff = a[i] - b[i];
            sum += weights[i] * diff * diff;
        }
        sum.sqrt()
    }
    
    /// Check if a point is within radius of center (weighted distance)
    pub fn within_patch(&self, scale: &str, center: &[f64; 8], point: &[f64; 8], radius: f64) -> bool {
        self.weighted_distance(scale, center, point) <= radius
    }
}

impl Default for ContextManager {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_list_contexts() {
        let cm = ContextManager::new();
        let contexts = cm.list_contexts();
        assert!(contexts.contains(&"quantum".to_string()));
        assert!(contexts.contains(&"planetary".to_string()));
        assert!(contexts.contains(&"astronomical".to_string()));
    }
    
    #[test]
    fn test_weighted_distance_time_critical() {
        let cm = ContextManager::new();
        
        // Two points differing only in time
        let a = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0];
        let b = [0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0]; // 1 unit time difference
        
        // Planetary should weight time more heavily
        let planetary_dist = cm.weighted_distance("planetary", &a, &b);
        let quantum_dist = cm.weighted_distance("quantum", &a, &b);
        
        assert!(planetary_dist > quantum_dist, 
            "Planetary should penalize time differences more: {planetary_dist} vs {quantum_dist}");
    }
}

