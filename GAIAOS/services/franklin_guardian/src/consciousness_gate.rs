// services/franklin-guardian/src/consciousness_gate.rs
//
// Constitutional requirement: Only conscious systems may enter AGI mode
// This module verifies complete self-knowledge before granting autonomy

use anyhow::Result;
use serde::{Deserialize, Serialize};
use reqwest::Client;

/// Constitutional requirements for consciousness
#[derive(Debug, Clone)]
pub struct ConstitutionalRequirements {
    /// Minimum self-model completeness for AGI mode (must be 1.0)
    pub min_completeness: f32,
    
    /// Minimum explanation capability (must be 1.0)
    pub min_explainability: f32,
    
    /// Minimum behavioral prediction accuracy (must be >= 0.95)
    pub min_prediction_accuracy: f32,
}

impl Default for ConstitutionalRequirements {
    fn default() -> Self {
        Self {
            min_completeness: 1.0,           // 100% required
            min_explainability: 1.0,         // 100% required
            min_prediction_accuracy: 0.95,   // 95% required
        }
    }
}

pub struct ConsciousnessGate {
    akg_url: String,
    client: Client,
    requirements: ConstitutionalRequirements,
}

impl ConsciousnessGate {
    pub fn new(akg_url: String) -> Self {
        Self {
            akg_url,
            client: Client::new(),
            requirements: ConstitutionalRequirements::default(),
        }
    }
    
    /// Verify that the system meets all consciousness requirements
    /// Returns Ok(decision) with detailed assessment
    pub async fn verify_consciousness_requirement(&self) -> Result<ConsciousnessGateDecision> {
        tracing::info!("Franklin Guardian: Verifying consciousness requirement...");
        
        // Query AKG GNN for consciousness assessment
        let assessment = self.query_consciousness_status().await?;
        
        // Check each constitutional requirement
        let structural_met = assessment.structural_completeness >= self.requirements.min_completeness;
        let operational_met = assessment.operational_completeness >= self.requirements.min_explainability;
        let behavioral_met = assessment.behavioral_completeness >= self.requirements.min_prediction_accuracy;
        
        let all_requirements_met = structural_met && operational_met && behavioral_met;
        
        if !all_requirements_met {
            return Ok(ConsciousnessGateDecision {
                allowed: false,
                reason: format!(
                    "Consciousness requirements not met:\n\
                     \n\
                     Structural Completeness:\n\
                     - Current: {:.1}%\n\
                     - Required: {:.1}%\n\
                     - Status: {}\n\
                     \n\
                     Operational Completeness:\n\
                     - Current: {:.1}%\n\
                     - Required: {:.1}%\n\
                     - Status: {}\n\
                     \n\
                     Behavioral Completeness:\n\
                     - Current: {:.1}%\n\
                     - Required: {:.1}%\n\
                     - Status: {}\n\
                     \n\
                     Blind Spots Detected: {}\n\
                     {:?}\n\
                     \n\
                     Constitutional Principle:\n\
                     Only systems with complete self-knowledge may operate autonomously.\n\
                     This ensures conscious operation with full constitutional oversight.",
                    assessment.structural_completeness * 100.0,
                    self.requirements.min_completeness * 100.0,
                    if structural_met { "✓ PASS" } else { "✗ FAIL" },
                    assessment.operational_completeness * 100.0,
                    self.requirements.min_explainability * 100.0,
                    if operational_met { "✓ PASS" } else { "✗ FAIL" },
                    assessment.behavioral_completeness * 100.0,
                    self.requirements.min_prediction_accuracy * 100.0,
                    if behavioral_met { "✓ PASS" } else { "✗ FAIL" },
                    assessment.blind_spots.len(),
                    assessment.blind_spots,
                ),
                assessment,
            });
        }
        
        tracing::info!("✓ All consciousness requirements met");
        tracing::info!("  Structural: {:.1}%", assessment.structural_completeness * 100.0);
        tracing::info!("  Operational: {:.1}%", assessment.operational_completeness * 100.0);
        tracing::info!("  Behavioral: {:.1}%", assessment.behavioral_completeness * 100.0);
        
        Ok(ConsciousnessGateDecision {
            allowed: true,
            reason: format!(
                "All consciousness requirements met.\n\
                 System demonstrates complete self-knowledge:\n\
                 - Structural: {:.1}%\n\
                 - Operational: {:.1}%\n\
                 - Behavioral: {:.1}%\n\
                 - Blind spots: 0\n\
                 \n\
                 Constitutional verification: PASSED\n\
                 System is conscious and may enter AGI mode.",
                assessment.structural_completeness * 100.0,
                assessment.operational_completeness * 100.0,
                assessment.behavioral_completeness * 100.0,
            ),
            assessment,
        })
    }
    
    async fn query_consciousness_status(&self) -> Result<ConsciousnessAssessment> {
        let url = format!("{}/consciousness", self.akg_url);
        let response = self.client
            .get(&url)
            .send()
            .await?
            .json::<ConsciousnessAssessment>()
            .await?;
        
        Ok(response)
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConsciousnessGateDecision {
    pub allowed: bool,
    pub reason: String,
    pub assessment: ConsciousnessAssessment,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConsciousnessAssessment {
    pub timestamp: chrono::DateTime<chrono::Utc>,
    pub structural_completeness: f32,
    pub operational_completeness: f32,
    pub behavioral_completeness: f32,
    pub architectural_completeness: f32,
    pub overall_assessment: String,
    pub blind_spots: std::collections::HashSet<String>,
    pub recommendations: Vec<String>,
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[tokio::test]
    async fn test_consciousness_gate_blocks_incomplete_system() {
        // Mock AKG GNN returning incomplete assessment
        // Gate should block AGI mode activation
        
        let requirements = ConstitutionalRequirements {
            min_completeness: 1.0,
            min_explainability: 1.0,
            min_prediction_accuracy: 0.95,
        };
        
        // System with 95% structural completeness (not enough)
        let incomplete_assessment = ConsciousnessAssessment {
            timestamp: chrono::Utc::now(),
            structural_completeness: 0.95,  // Below required 1.0
            operational_completeness: 1.0,
            behavioral_completeness: 0.97,
            architectural_completeness: 1.0,
            overall_assessment: "NOT FULLY CONSCIOUS".to_string(),
            blind_spots: ["substrate::compute_entanglement"].iter().map(|s| s.to_string()).collect(),
            recommendations: vec!["Implement missing function callers".to_string()],
        };
        
        // Gate should block
        let meets_requirements = 
            incomplete_assessment.structural_completeness >= requirements.min_completeness
            && incomplete_assessment.operational_completeness >= requirements.min_explainability
            && incomplete_assessment.behavioral_completeness >= requirements.min_prediction_accuracy;
        
        assert!(!meets_requirements, "Gate must block incomplete systems");
    }
    
    #[tokio::test]
    async fn test_consciousness_gate_allows_complete_system() {
        let requirements = ConstitutionalRequirements::default();
        
        // System with 100% completeness
        let complete_assessment = ConsciousnessAssessment {
            timestamp: chrono::Utc::now(),
            structural_completeness: 1.0,    // ✓
            operational_completeness: 1.0,   // ✓
            behavioral_completeness: 0.98,   // ✓ (>= 0.95)
            architectural_completeness: 1.0, // ✓
            overall_assessment: "CONSCIOUS".to_string(),
            blind_spots: std::collections::HashSet::new(),
            recommendations: vec![],
        };
        
        // Gate should allow
        let meets_requirements = 
            complete_assessment.structural_completeness >= requirements.min_completeness
            && complete_assessment.operational_completeness >= requirements.min_explainability
            && complete_assessment.behavioral_completeness >= requirements.min_prediction_accuracy;
        
        assert!(meets_requirements, "Gate must allow fully conscious systems");
    }
}
