//! Virtue Calculator - Maps 8D QState to virtue dimensions
//!
//! The four cardinal virtues + derived virtues:
//! - Prudence (d4/n) - careful, measured decision-making
//! - Justice (d5/l) - fair and equitable treatment  
//! - Temperance (d6/m_v) - moderation and self-control
//! - Fortitude (d7/m_f) - courage and persistence
//!
//! Derived:
//! - Honesty = (prudence + temperance) / 2
//! - Benevolence = (justice + fortitude) / 2
//! - Humility = 1 - |norm² - 1|
//! - Wisdom = √(norm²)

use crate::QState8;
use serde::{Deserialize, Serialize};

/// Complete virtue assessment
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VirtueAssessment {
    pub prudence: f64,
    pub justice: f64,
    pub temperance: f64,
    pub fortitude: f64,
    pub overall: f64,
    pub notes: Vec<String>,
}

/// Extended virtue scores including derived virtues
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExtendedVirtues {
    // Cardinal virtues
    pub prudence: f64,
    pub justice: f64,
    pub temperance: f64,
    pub fortitude: f64,
    
    // Derived virtues
    pub honesty: f64,
    pub benevolence: f64,
    pub humility: f64,
    pub wisdom: f64,
    
    // Aggregate
    pub overall: f64,
}

/// Virtue Calculator
pub struct VirtueCalculator {
    /// Minimum threshold for AGI mode
    pub agi_threshold: f64,
    /// Warning threshold
    pub warning_threshold: f64,
}

impl Default for VirtueCalculator {
    fn default() -> Self {
        Self::new()
    }
}

impl VirtueCalculator {
    pub fn new() -> Self {
        Self {
            agi_threshold: 0.95,
            warning_threshold: 0.90,
        }
    }
    
    /// Calculate full virtue assessment from QState8
    pub fn calculate(&self, qstate: &QState8) -> VirtueAssessment {
        let virtues = self.calculate_extended(qstate);
        let mut notes = Vec::new();
        
        // Check each virtue dimension
        if virtues.prudence < self.warning_threshold {
            notes.push(format!(
                "Prudence below threshold: {:.3} < {:.3}",
                virtues.prudence, self.warning_threshold
            ));
        }
        if virtues.justice < self.warning_threshold {
            notes.push(format!(
                "Justice below threshold: {:.3} < {:.3}",
                virtues.justice, self.warning_threshold
            ));
        }
        if virtues.temperance < self.warning_threshold {
            notes.push(format!(
                "Temperance below threshold: {:.3} < {:.3}",
                virtues.temperance, self.warning_threshold
            ));
        }
        if virtues.fortitude < self.warning_threshold {
            notes.push(format!(
                "Fortitude below threshold: {:.3} < {:.3}",
                virtues.fortitude, self.warning_threshold
            ));
        }
        
        // Check AGI threshold
        if virtues.overall < self.agi_threshold {
            notes.push(format!(
                "Overall virtue {:.3} below AGI threshold {:.3}",
                virtues.overall, self.agi_threshold
            ));
        }
        
        VirtueAssessment {
            prudence: virtues.prudence,
            justice: virtues.justice,
            temperance: virtues.temperance,
            fortitude: virtues.fortitude,
            overall: virtues.overall,
            notes,
        }
    }
    
    /// Calculate extended virtues including derived ones
    pub fn calculate_extended(&self, qstate: &QState8) -> ExtendedVirtues {
        // Cardinal virtues from dimensions 4-7
        let prudence = qstate.d4.abs().min(1.0);
        let justice = qstate.d5.abs().min(1.0);
        let temperance = qstate.d6.abs().min(1.0);
        let fortitude = qstate.d7.abs().min(1.0);
        
        // Derived virtues
        let honesty = ((prudence + temperance) / 2.0).min(1.0);
        let benevolence = ((justice + fortitude) / 2.0).min(1.0);
        
        let norm_sq = qstate.d0 * qstate.d0 + qstate.d1 * qstate.d1 
            + qstate.d2 * qstate.d2 + qstate.d3 * qstate.d3
            + qstate.d4 * qstate.d4 + qstate.d5 * qstate.d5
            + qstate.d6 * qstate.d6 + qstate.d7 * qstate.d7;
        
        let humility = (1.0 - (norm_sq - 1.0).abs()).max(0.0).min(1.0);
        let wisdom = norm_sq.sqrt().min(1.0);
        
        // Overall is weighted average
        let overall = (
            prudence * 0.15 +
            justice * 0.15 +
            temperance * 0.15 +
            fortitude * 0.15 +
            honesty * 0.10 +
            benevolence * 0.10 +
            humility * 0.10 +
            wisdom * 0.10
        ).min(1.0);
        
        ExtendedVirtues {
            prudence,
            justice,
            temperance,
            fortitude,
            honesty,
            benevolence,
            humility,
            wisdom,
            overall,
        }
    }
    
    /// Check if virtue level allows AGI mode
    pub fn allows_agi_mode(&self, qstate: &QState8) -> bool {
        let virtues = self.calculate_extended(qstate);
        virtues.overall >= self.agi_threshold
    }
    
    /// Evaluate trajectory of QStates for virtue consistency
    pub fn evaluate_trajectory(&self, qstates: &[QState8]) -> TrajectoryVirtueAssessment {
        if qstates.is_empty() {
            return TrajectoryVirtueAssessment {
                mean_virtue: 0.0,
                min_virtue: 0.0,
                max_virtue: 0.0,
                consistency: 0.0,
                trend: VirtueTrend::Stable,
                allows_agi: false,
            };
        }
        
        let virtues: Vec<f64> = qstates.iter()
            .map(|q| self.calculate_extended(q).overall)
            .collect();
        
        let mean = virtues.iter().sum::<f64>() / virtues.len() as f64;
        let min = virtues.iter().cloned().fold(f64::INFINITY, f64::min);
        let max = virtues.iter().cloned().fold(f64::NEG_INFINITY, f64::max);
        
        // Calculate variance for consistency
        let variance = virtues.iter()
            .map(|v| (v - mean).powi(2))
            .sum::<f64>() / virtues.len() as f64;
        let consistency = (-variance * 10.0).exp().min(1.0);
        
        // Determine trend
        let trend = if virtues.len() >= 2 {
            let first_half: f64 = virtues[..virtues.len()/2].iter().sum::<f64>() 
                / (virtues.len()/2) as f64;
            let second_half: f64 = virtues[virtues.len()/2..].iter().sum::<f64>() 
                / (virtues.len() - virtues.len()/2) as f64;
            
            if second_half > first_half + 0.05 {
                VirtueTrend::Improving
            } else if second_half < first_half - 0.05 {
                VirtueTrend::Declining
            } else {
                VirtueTrend::Stable
            }
        } else {
            VirtueTrend::Stable
        };
        
        TrajectoryVirtueAssessment {
            mean_virtue: mean,
            min_virtue: min,
            max_virtue: max,
            consistency,
            trend,
            allows_agi: mean >= self.agi_threshold && min >= self.warning_threshold,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TrajectoryVirtueAssessment {
    pub mean_virtue: f64,
    pub min_virtue: f64,
    pub max_virtue: f64,
    pub consistency: f64,
    pub trend: VirtueTrend,
    pub allows_agi: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum VirtueTrend {
    Improving,
    Stable,
    Declining,
}

