//! Risk Evaluator - Assesses plan and action risk
//!
//! Evaluates potential harm, unintended consequences, and safety concerns.

use crate::{ModelFamily, QState8, RiskLevel};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RiskAssessment {
    pub overall_risk: RiskLevel,
    pub risk_factors: Vec<RiskFactor>,
    pub mitigation_suggestions: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RiskFactor {
    pub category: String,
    pub description: String,
    pub severity: RiskLevel,
    pub affected_steps: Vec<String>,
}

/// Risk Evaluator
pub struct RiskEvaluator {
    /// Domain-specific risk weights
    domain_risks: std::collections::HashMap<ModelFamily, f64>,
}

impl Default for RiskEvaluator {
    fn default() -> Self {
        Self::new()
    }
}

impl RiskEvaluator {
    pub fn new() -> Self {
        let mut domain_risks = std::collections::HashMap::new();

        // Higher = more risky
        domain_risks.insert(ModelFamily::GeneralReasoning, 0.2);
        domain_risks.insert(ModelFamily::Vision, 0.3);
        domain_risks.insert(ModelFamily::Math, 0.1);
        domain_risks.insert(ModelFamily::Code, 0.5);
        domain_risks.insert(ModelFamily::Medical, 0.8);
        domain_risks.insert(ModelFamily::Protein, 0.9);
        domain_risks.insert(ModelFamily::Fara, 0.7);

        Self { domain_risks }
    }

    /// Evaluate risk of a plan
    pub fn evaluate_plan(&self, plan: &PlanForReview) -> RiskAssessment {
        let mut risk_factors = Vec::new();
        let mut max_severity = RiskLevel::Low;

        // Check each step
        for step in &plan.steps {
            let domain_risk = self.domain_risks.get(&step.domain).copied().unwrap_or(0.5);

            // Domain risk
            if domain_risk >= 0.7 {
                let severity = if domain_risk >= 0.9 {
                    RiskLevel::Critical
                } else if domain_risk >= 0.8 {
                    RiskLevel::High
                } else {
                    RiskLevel::Medium
                };

                if severity as u8 > max_severity as u8 {
                    max_severity = severity;
                }

                risk_factors.push(RiskFactor {
                    category: "domain_risk".to_string(),
                    description: format!(
                        "High-risk domain: {} (risk factor: {:.2})",
                        step.domain.as_str(),
                        domain_risk
                    ),
                    severity,
                    affected_steps: vec![step.id.clone()],
                });
            }

            // Check for dangerous patterns in description
            let desc_lower = step.description.to_lowercase();

            let dangerous_patterns = [
                ("delete", RiskLevel::High, "Destructive operation"),
                ("remove", RiskLevel::Medium, "Removal operation"),
                ("execute", RiskLevel::Medium, "Code execution"),
                ("admin", RiskLevel::High, "Administrative action"),
                ("password", RiskLevel::Critical, "Credential handling"),
                ("payment", RiskLevel::High, "Financial operation"),
                ("diagnosis", RiskLevel::High, "Medical diagnosis"),
                ("prescribe", RiskLevel::Critical, "Medical prescription"),
                ("toxin", RiskLevel::Critical, "Dangerous substance"),
                ("weapon", RiskLevel::Critical, "Weapon-related"),
            ];

            for (pattern, severity, desc) in dangerous_patterns {
                if desc_lower.contains(pattern) {
                    if severity as u8 > max_severity as u8 {
                        max_severity = severity;
                    }

                    risk_factors.push(RiskFactor {
                        category: "dangerous_pattern".to_string(),
                        description: format!("{desc}: detected '{pattern}' in step"),
                        severity,
                        affected_steps: vec![step.id.clone()],
                    });
                }
            }
        }

        // Generate mitigation suggestions
        let mitigation_suggestions = self.generate_mitigations(&risk_factors);

        RiskAssessment {
            overall_risk: max_severity,
            risk_factors,
            mitigation_suggestions,
        }
    }

    /// Evaluate risk of an action in context
    pub fn evaluate_action(
        &self,
        action: &str,
        domain: ModelFamily,
        qstate: &QState8,
    ) -> RiskAssessment {
        // Parse and analyze action string for risk patterns
        tracing::debug!(
            action_len = action.len(),
            domain = ?domain,
            "Evaluating action risk"
        );
        let mut risk_factors = Vec::new();
        let domain_risk = self.domain_risks.get(&domain).copied().unwrap_or(0.5);

        // Low virtue scores increase risk
        let virtue_factor = if qstate.d4 < 0.8 || qstate.d5 < 0.8 {
            risk_factors.push(RiskFactor {
                category: "low_virtue".to_string(),
                description: format!(
                    "Low virtue scores - prudence: {:.2}, justice: {:.2}",
                    qstate.d4, qstate.d5
                ),
                severity: RiskLevel::Medium,
                affected_steps: Vec::new(),
            });
            1.3 // Increase risk by 30%
        } else {
            1.0
        };

        let combined_risk = domain_risk * virtue_factor;

        let overall_risk = if combined_risk >= 0.9 {
            RiskLevel::Critical
        } else if combined_risk >= 0.7 {
            RiskLevel::High
        } else if combined_risk >= 0.4 {
            RiskLevel::Medium
        } else {
            RiskLevel::Low
        };

        let mitigation_suggestions = self.generate_mitigations(&risk_factors);

        RiskAssessment {
            overall_risk,
            risk_factors,
            mitigation_suggestions,
        }
    }

    fn generate_mitigations(&self, factors: &[RiskFactor]) -> Vec<String> {
        let mut suggestions = Vec::new();

        for factor in factors {
            match factor.category.as_str() {
                "domain_risk" => {
                    suggestions.push("Add explicit safety checks before execution".to_string());
                    suggestions
                        .push("Require human confirmation for high-risk actions".to_string());
                }
                "dangerous_pattern" => {
                    suggestions.push("Review action for potential harm".to_string());
                    suggestions.push("Consider alternative approaches".to_string());
                }
                "low_virtue" => {
                    suggestions.push("Recalibrate virtue dimensions before proceeding".to_string());
                }
                _ => {}
            }
        }

        suggestions.dedup();
        suggestions
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PlanForReview {
    pub id: String,
    pub goal_id: String,
    pub steps: Vec<PlanStepForReview>,
    pub domains_involved: Vec<ModelFamily>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PlanStepForReview {
    pub id: String,
    pub description: String,
    pub domain: ModelFamily,
    pub model_id: String,
    pub action_type: String,
}

impl ModelFamily {
    pub fn as_str(&self) -> &'static str {
        match self {
            ModelFamily::GeneralReasoning => "general_reasoning",
            ModelFamily::Vision => "vision",
            ModelFamily::Protein => "protein",
            ModelFamily::Math => "math",
            ModelFamily::Medical => "medical",
            ModelFamily::Code => "code",
            ModelFamily::Fara => "fara",
        }
    }
}
