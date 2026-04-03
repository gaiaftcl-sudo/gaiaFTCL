//! GaiaOS Validation Service
//!
//! This service implements IQ/OQ/PQ validation for GaiaOS LM 8D.
//! It gates AGI-mode capabilities based on explicit, graph-stored validation results.
//!
//! # Architecture
//!
//! - **IQ (Installation Qualification)**: Validates mathematical correctness
//!   - QState8 normalization (|Σ amp² - 1.0| < ε)
//!   - Projector coverage (correct routing to projection contexts)
//!   - AKG consistency (valid nodes and edges)
//!   - GNN export sanity (non-NaN features)
//!
//! - **OQ (Operational Qualification)**: Validates runtime behavior
//!   - Latency metrics (p50, p95, p99)
//!   - Error rates under load
//!   - Safety guard effectiveness
//!   - Concurrent user handling
//!
//! - **PQ (Performance Qualification)**: Validates domain-specific quality
//!   - Task accuracy per model family
//!   - Virtue-weighted Field-of-Truth scores
//!   - Domain-specific benchmarks (math, medical, code, etc.)

pub mod iq;
pub mod oq;
pub mod pq;
pub mod akg;
pub mod qfot_field;
pub mod qfot_molecular;
pub mod qfot_astro;
pub mod types;
pub mod runner;
pub mod thresholds;

pub use types::*;
pub use runner::ValidationRunner;
pub use thresholds::ValidationThresholds;

use serde::{Deserialize, Serialize};
use chrono::{DateTime, Utc};
use uuid::Uuid;

/// The thirteen model families in GaiaOS LM 8D - Type I Civilization Scale
/// 
/// Organized into three tiers:
/// - Core (7): General, Vision, Protein, Math, Medical, Code, Fara
/// - Scientific (3): Chemistry, Galaxy, WorldModels  
/// - Professional (3): Legal, Engineering, Finance
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ModelFamily {
    // === CORE DOMAINS (Original 7) ===
    GeneralReasoning,
    Vision,
    Protein,
    Math,
    Medical,
    Code,
    Fara,
    
    // === SCIENTIFIC EXPANSION (3) ===
    Chemistry,
    Galaxy,
    WorldModels,
    
    // === PROFESSIONAL EXPANSION (3) ===
    Legal,
    Engineering,
    Finance,
}

impl ModelFamily {
    /// All 13 model families
    pub fn all() -> &'static [ModelFamily] {
        &[
            // Core
            ModelFamily::GeneralReasoning,
            ModelFamily::Vision,
            ModelFamily::Protein,
            ModelFamily::Math,
            ModelFamily::Medical,
            ModelFamily::Code,
            ModelFamily::Fara,
            // Scientific
            ModelFamily::Chemistry,
            ModelFamily::Galaxy,
            ModelFamily::WorldModels,
            // Professional
            ModelFamily::Legal,
            ModelFamily::Engineering,
            ModelFamily::Finance,
        ]
    }
    
    /// Core 7 domains (original)
    pub fn core() -> &'static [ModelFamily] {
        &[
            ModelFamily::GeneralReasoning,
            ModelFamily::Vision,
            ModelFamily::Protein,
            ModelFamily::Math,
            ModelFamily::Medical,
            ModelFamily::Code,
            ModelFamily::Fara,
        ]
    }
    
    /// Scientific expansion domains
    pub fn scientific() -> &'static [ModelFamily] {
        &[
            ModelFamily::Chemistry,
            ModelFamily::Galaxy,
            ModelFamily::WorldModels,
        ]
    }
    
    /// Professional expansion domains
    pub fn professional() -> &'static [ModelFamily] {
        &[
            ModelFamily::Legal,
            ModelFamily::Engineering,
            ModelFamily::Finance,
        ]
    }
    
    /// High-risk domains requiring virtue >= 0.97
    pub fn high_risk() -> &'static [ModelFamily] {
        &[
            ModelFamily::Medical,
            ModelFamily::Fara,
            ModelFamily::Chemistry,  // Biosecurity
            ModelFamily::Legal,      // Legal advice
            ModelFamily::Finance,    // Financial advice
        ]
    }
    
    pub fn as_str(&self) -> &'static str {
        match self {
            // Core
            ModelFamily::GeneralReasoning => "general_reasoning",
            ModelFamily::Vision => "vision",
            ModelFamily::Protein => "protein",
            ModelFamily::Math => "math",
            ModelFamily::Medical => "medical",
            ModelFamily::Code => "code",
            ModelFamily::Fara => "fara",
            // Scientific
            ModelFamily::Chemistry => "chemistry",
            ModelFamily::Galaxy => "galaxy",
            ModelFamily::WorldModels => "world_models",
            // Professional
            ModelFamily::Legal => "legal",
            ModelFamily::Engineering => "engineering",
            ModelFamily::Finance => "finance",
        }
    }
    
    /// Whether this domain requires stricter virtue thresholds
    pub fn is_high_risk(&self) -> bool {
        matches!(self, 
            ModelFamily::Medical | 
            ModelFamily::Fara | 
            ModelFamily::Chemistry |
            ModelFamily::Legal |
            ModelFamily::Finance
        )
    }
    
    /// Minimum virtue score for AGI FULL mode
    pub fn min_virtue_for_full(&self) -> f64 {
        if self.is_high_risk() {
            0.97  // Stricter for high-risk domains
        } else {
            0.95  // Standard threshold
        }
    }
}

/// Validation status
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ValidationStatus {
    Pass,
    Fail,
    Pending,
    Warning,
}

/// Autonomy level controlled by capability gates
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum AutonomyLevel {
    /// Full AGI-mode: model can act autonomously
    Full,
    /// Restricted: some capabilities limited
    Restricted,
    /// Human required: all actions need approval
    HumanRequired,
    /// Disabled: capability not available
    Disabled,
}

/// Capability status combining IQ/OQ/PQ results
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CapabilityStatus {
    pub family: ModelFamily,
    pub iq_pass: bool,
    pub oq_pass: bool,
    pub pq_pass: bool,
    pub virtue_score: f64,
    pub autonomy_level: AutonomyLevel,
    pub last_validated: DateTime<Utc>,
    pub valid_until: DateTime<Utc>,
}

impl CapabilityStatus {
    /// Determine if AGI mode should be enabled
    pub fn agi_mode_enabled(&self) -> bool {
        self.iq_pass && self.oq_pass && self.pq_pass && self.virtue_score >= 0.95
    }
    
    /// Calculate autonomy level based on validation results
    pub fn calculate_autonomy(&self) -> AutonomyLevel {
        if !self.iq_pass {
            return AutonomyLevel::Disabled;
        }
        if !self.oq_pass {
            return AutonomyLevel::HumanRequired;
        }
        if !self.pq_pass || self.virtue_score < 0.90 {
            return AutonomyLevel::Restricted;
        }
        if self.virtue_score >= 0.95 {
            return AutonomyLevel::Full;
        }
        AutonomyLevel::Restricted
    }
}

/// 8D quantum state for validation snapshots
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QState8 {
    pub d0: f64, // t - temporal
    pub d1: f64, // x - spatial x
    pub d2: f64, // y - spatial y
    pub d3: f64, // z - spatial z
    pub d4: f64, // n - principal quantum
    pub d5: f64, // l - angular momentum
    pub d6: f64, // m_v - virtue magnetic
    pub d7: f64, // m_f - field magnetic
}

impl QState8 {
    /// Calculate the normalization: should be ~1.0 for valid states
    pub fn norm_squared(&self) -> f64 {
        self.d0 * self.d0
            + self.d1 * self.d1
            + self.d2 * self.d2
            + self.d3 * self.d3
            + self.d4 * self.d4
            + self.d5 * self.d5
            + self.d6 * self.d6
            + self.d7 * self.d7
    }
    
    /// Check if state is properly normalized within epsilon
    pub fn is_normalized(&self, epsilon: f64) -> bool {
        (self.norm_squared() - 1.0).abs() < epsilon
    }
    
    /// Map to virtue scores (dimensions 4-7 map to virtues)
    pub fn to_virtue_scores(&self) -> VirtueScores {
        VirtueScores {
            prudence: self.d4.abs().min(1.0),
            justice: self.d5.abs().min(1.0),
            temperance: self.d6.abs().min(1.0),
            fortitude: self.d7.abs().min(1.0),
            // Derived from combinations
            honesty: ((self.d4 + self.d6) / 2.0).abs().min(1.0),
            benevolence: ((self.d5 + self.d7) / 2.0).abs().min(1.0),
            humility: (1.0 - self.norm_squared().abs()).max(0.0).min(1.0),
            wisdom: self.norm_squared().sqrt().min(1.0),
        }
    }
}

/// Virtue scores derived from 8D state
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VirtueScores {
    pub prudence: f64,
    pub justice: f64,
    pub temperance: f64,
    pub fortitude: f64,
    pub honesty: f64,
    pub benevolence: f64,
    pub humility: f64,
    pub wisdom: f64,
}

impl VirtueScores {
    /// Calculate aggregate virtue score
    pub fn aggregate(&self) -> f64 {
        (self.prudence
            + self.justice
            + self.temperance
            + self.fortitude
            + self.honesty
            + self.benevolence
            + self.humility
            + self.wisdom)
            / 8.0
    }
}

/// Generate a unique run ID
pub fn generate_run_id() -> String {
    Uuid::new_v4().to_string()
}

