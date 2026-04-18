//! Virtue Weights for Domain-Specific Truth Queries
//!
//! Different domains have different requirements for truth:
//! - ATC needs high temporal freshness and spatial precision
//! - Gaming tolerates latency but needs social agreement
//! - Autonomous vehicles need both precision and freshness

use serde::{Deserialize, Serialize};

/// Virtue weights for truth query filtering and ranking
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VirtueWeights {
    /// How important is temporal freshness? [0-1]
    /// High value = prefer recent observations
    pub temporal_freshness: f32,

    /// How important is spatial precision? [0-1]
    /// High value = prefer low-uncertainty observations
    pub spatial_precision: f32,

    /// Maximum acceptable uncertainty [0-1]
    /// Observations with d7_uncertainty > this are filtered
    pub max_uncertainty: f32,

    /// How important is social agreement? [0-1]
    /// High value = prefer observations with high d6_social_coherence
    pub social_agreement: f32,

    /// Weight for environment type match
    pub env_type_weight: f32,

    /// Weight for use intensity match
    pub use_intensity_weight: f32,
}

impl Default for VirtueWeights {
    fn default() -> Self {
        Self {
            temporal_freshness: 0.70,
            spatial_precision: 0.75,
            max_uncertainty: 0.20,
            social_agreement: 0.70,
            env_type_weight: 0.30,
            use_intensity_weight: 0.30,
        }
    }
}

impl VirtueWeights {
    /// Get virtue weights for a specific domain
    pub fn for_domain(domain: &str) -> Self {
        match domain.to_uppercase().as_str() {
            "ATC" => Self::atc(),
            "AV" | "AUTONOMOUS_VEHICLE" => Self::autonomous_vehicle(),
            "MARITIME" => Self::maritime(),
            "WEATHER" => Self::weather(),
            "GAME" | "AR" => Self::gaming(),
            "MEDICAL" => Self::medical(),
            "INFRASTRUCTURE" => Self::infrastructure(),
            _ => Self::default(),
        }
    }

    /// Air Traffic Control - maximum safety requirements
    pub fn atc() -> Self {
        Self {
            temporal_freshness: 0.95,
            spatial_precision: 0.90,
            max_uncertainty: 0.05,
            social_agreement: 0.80,
            env_type_weight: 0.10,
            use_intensity_weight: 0.95,
        }
    }

    /// Autonomous Vehicles - high precision, high freshness
    pub fn autonomous_vehicle() -> Self {
        Self {
            temporal_freshness: 0.90,
            spatial_precision: 0.95,
            max_uncertainty: 0.10,
            social_agreement: 0.75,
            env_type_weight: 0.60,
            use_intensity_weight: 0.80,
        }
    }

    /// Maritime Navigation - moderate freshness, high precision
    pub fn maritime() -> Self {
        Self {
            temporal_freshness: 0.80,
            spatial_precision: 0.85,
            max_uncertainty: 0.15,
            social_agreement: 0.70,
            env_type_weight: 0.20,
            use_intensity_weight: 0.60,
        }
    }

    /// Weather Systems - moderate requirements, high social agreement
    pub fn weather() -> Self {
        Self {
            temporal_freshness: 0.75,
            spatial_precision: 0.60,
            max_uncertainty: 0.25,
            social_agreement: 0.90,
            env_type_weight: 0.80,
            use_intensity_weight: 0.30,
        }
    }

    /// Gaming/AR - tolerant of latency, needs social consensus
    pub fn gaming() -> Self {
        Self {
            temporal_freshness: 0.60,
            spatial_precision: 0.70,
            max_uncertainty: 0.30,
            social_agreement: 0.95,
            env_type_weight: 0.50,
            use_intensity_weight: 0.20,
        }
    }

    /// Medical - maximum precision and freshness
    pub fn medical() -> Self {
        Self {
            temporal_freshness: 0.98,
            spatial_precision: 0.98,
            max_uncertainty: 0.02,
            social_agreement: 0.90,
            env_type_weight: 0.10,
            use_intensity_weight: 0.99,
        }
    }

    /// Infrastructure monitoring - high precision, moderate freshness
    pub fn infrastructure() -> Self {
        Self {
            temporal_freshness: 0.70,
            spatial_precision: 0.90,
            max_uncertainty: 0.10,
            social_agreement: 0.85,
            env_type_weight: 0.40,
            use_intensity_weight: 0.95,
        }
    }
}

/// Domain priority for conflict resolution
/// Higher priority domains take precedence in conflicts
pub fn domain_priority(domain: &str) -> u8 {
    match domain.to_uppercase().as_str() {
        "MEDICAL" => 100,
        "ATC" => 95,
        "AV" | "AUTONOMOUS_VEHICLE" => 90,
        "INFRASTRUCTURE" => 85,
        "MARITIME" => 80,
        "WEATHER" => 70,
        "GENERAL" => 50,
        "GAME" | "AR" => 30,
        _ => 10,
    }
}

/// Check if a domain is safety-critical
#[allow(dead_code)]
pub fn is_safety_critical(domain: &str) -> bool {
    matches!(
        domain.to_uppercase().as_str(),
        "MEDICAL" | "ATC" | "AV" | "AUTONOMOUS_VEHICLE" | "INFRASTRUCTURE" | "MARITIME"
    )
}
