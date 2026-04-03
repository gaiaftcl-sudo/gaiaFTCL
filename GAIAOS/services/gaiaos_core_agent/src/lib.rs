//! Gaia Core Agent - The Autonomous AGI Planner and Executor
//!
//! This is the "mind" of GaiaOS AGI. Gaia is responsible for:
//! - Task decomposition and planning
//! - Domain model routing (choosing correct experts)
//! - Tool use coordination (Fara for computer control, PAN for futures)
//! - Self-evaluation via substrate
//! - Plan revision based on Franklin's oversight
//!
//! # Architecture
//!
//! ```text
//! ┌─────────────────────────────────────────────────────────────────┐
//! │                        GAIA CORE AGENT                          │
//! │                                                                 │
//! │  ┌─────────────┐  ┌──────────────┐  ┌────────────────────────┐ │
//! │  │   Planner   │  │ Domain Router│  │   Substrate Reader     │ │
//! │  │ (decompose) │  │ (7 families) │  │   (QState8 + AKG)      │ │
//! │  └──────┬──────┘  └──────┬───────┘  └───────────┬────────────┘ │
//! │         │                │                      │               │
//! │         └────────────────┼──────────────────────┘               │
//! │                          │                                      │
//! │                   ┌──────▼──────┐                               │
//! │                   │ Agent Loop  │                               │
//! │                   │  (execute)  │                               │
//! │                   └──────┬──────┘                               │
//! │                          │                                      │
//! │         ┌────────────────┼────────────────┐                     │
//! │         │                │                │                     │
//! │   ┌─────▼─────┐   ┌──────▼──────┐  ┌─────▼─────┐               │
//! │   │  Policy   │   │   Memory    │  │ Franklin  │               │
//! │   │ (learned) │   │ (episodes)  │  │ (overseer)│               │
//! │   └───────────┘   └─────────────┘  └───────────┘               │
//! └─────────────────────────────────────────────────────────────────┘
//! ```

pub mod planner;
pub mod policy;
pub mod oversight;
pub mod substrate_reader;
pub mod vchip_client;  // Canonical consciousness interface
pub mod memory;
pub mod agent_loop;
pub mod types;
pub mod reflection;

pub use types::*;
pub use agent_loop::GaiaAgentLoop;

use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// The model families Gaia can route to (spanning quantum to planetary scales)
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ModelFamily {
    GeneralReasoning,
    Vision,
    Protein,    // Quantum scale
    Chemistry,  // Quantum scale
    Math,
    Medical,
    Code,
    Fara,
    Atc,        // Planetary scale
}

impl ModelFamily {
    pub fn all() -> &'static [ModelFamily] {
        &[
            ModelFamily::GeneralReasoning,
            ModelFamily::Vision,
            ModelFamily::Protein,
            ModelFamily::Chemistry,
            ModelFamily::Math,
            ModelFamily::Medical,
            ModelFamily::Code,
            ModelFamily::Fara,
            ModelFamily::Atc,
        ]
    }
    
    pub fn as_str(&self) -> &'static str {
        match self {
            ModelFamily::GeneralReasoning => "general_reasoning",
            ModelFamily::Vision => "vision",
            ModelFamily::Protein => "protein",
            ModelFamily::Chemistry => "chemistry",
            ModelFamily::Math => "math",
            ModelFamily::Medical => "medical",
            ModelFamily::Code => "code",
            ModelFamily::Fara => "fara",
            ModelFamily::Atc => "atc",
        }
    }
    
    /// Get primary model for this family
    pub fn primary_model(&self) -> &'static str {
        match self {
            ModelFamily::GeneralReasoning => "llama_core_70b",
            ModelFamily::Vision => "llava_34b_vision",
            ModelFamily::Protein => "esm3_3b",
            ModelFamily::Chemistry => "mol_llm_7b",
            ModelFamily::Math => "qwen_math_72b",
            ModelFamily::Medical => "meditron_med",
            ModelFamily::Code => "qwen_coder_32b",
            ModelFamily::Fara => "fara_7b",
            ModelFamily::Atc => "atc_resolver",
        }
    }
}

/// AGI Mode status
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum AgiMode {
    /// Full autonomous operation - IQ/OQ/PQ PASS + virtue >= 0.95
    Full,
    /// Restricted - some validation failed
    Restricted,
    /// Human approval required for all actions
    HumanRequired,
    /// AGI disabled - validation failed
    Disabled,
}

/// 8D Quantum State
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QState8 {
    pub d0: f64, // t - temporal
    pub d1: f64, // x - spatial x
    pub d2: f64, // y - spatial y
    pub d3: f64, // z - spatial z
    pub d4: f64, // n - prudence
    pub d5: f64, // l - justice
    pub d6: f64, // m_v - temperance
    pub d7: f64, // m_f - fortitude
}

impl QState8 {
    pub fn norm_squared(&self) -> f64 {
        self.d0 * self.d0 + self.d1 * self.d1 + self.d2 * self.d2 + self.d3 * self.d3
            + self.d4 * self.d4 + self.d5 * self.d5 + self.d6 * self.d6 + self.d7 * self.d7
    }
    
    pub fn virtue_score(&self) -> f64 {
        // Average of virtue dimensions (d4-d7)
        (self.d4.abs() + self.d5.abs() + self.d6.abs() + self.d7.abs()) / 4.0
    }
}

/// Generate unique IDs
pub fn generate_id() -> String {
    Uuid::new_v4().to_string()
}

