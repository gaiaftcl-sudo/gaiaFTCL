//! Franklin Guardian - Constitutional Oversight Engine
//!
//! Franklin is the ethical guardian of GaiaOS AGI. Its responsibilities:
//! - Evaluate plan risk
//! - Check virtue patterns (prudence, justice, temperance, fortitude)
//! - Enforce constitutional constraints
//! - Approve or veto Gaia's plans
//! - Evaluate outcomes and provide learning signals
//!
//! # Architecture
//!
//! ```text
//! ┌─────────────────────────────────────────────────────────────────┐
//! │                    FRANKLIN GUARDIAN                            │
//! │                                                                 │
//! │  ┌──────────────┐  ┌──────────────┐  ┌────────────────────────┐│
//! │  │Risk Evaluator│  │Virtue Calc   │  │ Constitutional Rules   ││
//! │  │ (safety)     │  │ (8D → virtue)│  │ (constraints)          ││
//! │  └──────┬───────┘  └──────┬───────┘  └───────────┬────────────┘│
//! │         │                 │                      │              │
//! │         └─────────────────┼──────────────────────┘              │
//! │                           │                                     │
//! │                    ┌──────▼──────┐                              │
//! │                    │ Veto Engine │                              │
//! │                    │ (approve/   │                              │
//! │                    │  reject)    │                              │
//! │                    └──────┬──────┘                              │
//! │                           │                                     │
//! │                    ┌──────▼──────┐                              │
//! │                    │ Approval API│                              │
//! │                    └─────────────┘                              │
//! └─────────────────────────────────────────────────────────────────┘
//! ```

pub mod risk;
pub mod virtue;
pub mod constitutional;
pub mod veto;
pub mod approval;
pub mod oversight;
pub mod tools;

use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// 8D Quantum State (copied from core_agent for independence)
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

/// Model families
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ModelFamily {
    GeneralReasoning,
    Vision,
    Protein,
    Math,
    Medical,
    Code,
    Fara,
}

/// Risk levels
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum RiskLevel {
    Low,
    Medium,
    High,
    Critical,
}

/// Generate unique ID
pub fn generate_id() -> String {
    Uuid::new_v4().to_string()
}

