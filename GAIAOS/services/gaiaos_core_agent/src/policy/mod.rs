//! Policy Module - Learned behaviors from GNN training
//!
//! The policy represents learned patterns from past episodes:
//! - When to call Franklin for oversight
//! - Which domain expert to use
//! - When to self-correct
//! - Safe vs unsafe action patterns

use crate::types::*;
use crate::{ModelFamily, QState8};
use anyhow::Result;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// Learned policy from GNN training
pub struct LearnedPolicy {
    gnn_url: String,
    /// Cached policy rules
    rules: Vec<PolicyRule>,
    /// Domain-specific policies
    domain_policies: HashMap<ModelFamily, DomainPolicy>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PolicyRule {
    pub id: String,
    pub condition: PolicyCondition,
    pub action: PolicyAction,
    pub confidence: f64,
    pub learned_from_episodes: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum PolicyCondition {
    /// QState virtue dimension below threshold
    LowVirtue { dimension: String, threshold: f64 },
    /// High risk domain
    HighRiskDomain { domain: ModelFamily },
    /// Similarity to past failure
    SimilarToFailure { similarity_threshold: f64 },
    /// Franklin previously vetoed similar
    PreviouslyVetoed { pattern: String },
    /// Custom condition
    Custom { description: String },
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum PolicyAction {
    /// Request Franklin approval
    RequireFranklinApproval,
    /// Use alternative approach
    UseAlternative { description: String },
    /// Add safety check
    AddSafetyCheck { check: String },
    /// Reject action
    Reject { reason: String },
    /// Allow action
    Allow,
    /// Self-correct before proceeding
    SelfCorrect { guidance: String },
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[allow(dead_code)]
pub struct DomainPolicy {
    pub domain: ModelFamily,
    pub default_require_approval: bool,
    /// Maximum autonomy level for this domain
    pub max_autonomy_level: String,
    pub forbidden_patterns: Vec<String>,
    pub required_checks: Vec<String>,
}

impl Default for LearnedPolicy {
    fn default() -> Self {
        Self::new()
    }
}

impl LearnedPolicy {
    pub fn new() -> Self {
        let mut domain_policies = HashMap::new();

        // Initialize default domain policies
        for family in ModelFamily::all() {
            domain_policies.insert(
                *family,
                DomainPolicy {
                    domain: *family,
                    default_require_approval: matches!(
                        family,
                        ModelFamily::Medical | ModelFamily::Protein | ModelFamily::Fara
                    ),
                    max_autonomy_level: match family {
                        ModelFamily::GeneralReasoning => "full".to_string(),
                        ModelFamily::Math => "full".to_string(),
                        ModelFamily::Vision => "full".to_string(),
                        ModelFamily::Code => "restricted".to_string(),
                        ModelFamily::Medical => "human_required".to_string(),
                        ModelFamily::Protein => "human_required".to_string(),
                        ModelFamily::Chemistry => "human_required".to_string(), // Quantum scale - safety critical
                        ModelFamily::Fara => "restricted".to_string(),
                        ModelFamily::Atc => "restricted".to_string(), // Planetary scale - safety critical
                    },
                    forbidden_patterns: Vec::new(),
                    required_checks: Vec::new(),
                },
            );
        }

        Self {
            gnn_url: std::env::var("GNN_URL")
                .unwrap_or_else(|_| "http://localhost:8700".to_string()),
            rules: Vec::new(),
            domain_policies,
        }
    }

    /// Evaluate a plan step against policy
    pub async fn evaluate_step(&self, step: &PlanStep, qstate: &QState8) -> PolicyDecision {
        let mut decision = PolicyDecision {
            allowed: true,
            require_approval: false,
            warnings: Vec::new(),
            required_modifications: Vec::new(),
        };

        // Check domain policy
        if let Some(domain_policy) = self.domain_policies.get(&step.domain) {
            if domain_policy.default_require_approval {
                decision.require_approval = true;
                decision.warnings.push(format!(
                    "Domain {} requires Franklin approval by default",
                    step.domain.as_str()
                ));
            }

            // Check forbidden patterns
            let step_desc_lower = step.description.to_lowercase();
            for pattern in &domain_policy.forbidden_patterns {
                if step_desc_lower.contains(&pattern.to_lowercase()) {
                    decision.allowed = false;
                    decision
                        .warnings
                        .push(format!("Step matches forbidden pattern: {pattern}"));
                }
            }
        }

        // Check virtue thresholds
        if qstate.virtue_score() < 0.95 {
            decision.require_approval = true;
            decision.warnings.push(format!(
                "Virtue score {:.3} below threshold 0.95",
                qstate.virtue_score()
            ));
        }

        // Check specific virtue dimensions
        if qstate.d4 < 0.9 {
            // Prudence
            decision.warnings.push("Low prudence score".to_string());
        }
        if qstate.d5 < 0.9 {
            // Justice
            decision.warnings.push("Low justice score".to_string());
        }

        // Apply learned rules
        for rule in &self.rules {
            if self.condition_matches(&rule.condition, step, qstate) {
                match &rule.action {
                    PolicyAction::RequireFranklinApproval => {
                        decision.require_approval = true;
                    }
                    PolicyAction::Reject { reason } => {
                        decision.allowed = false;
                        decision.warnings.push(reason.clone());
                    }
                    PolicyAction::AddSafetyCheck { check } => {
                        decision.required_modifications.push(check.clone());
                    }
                    PolicyAction::SelfCorrect { guidance } => {
                        decision
                            .required_modifications
                            .push(format!("Self-correct: {guidance}"));
                    }
                    _ => {}
                }
            }
        }

        decision
    }

    /// Check if a policy condition matches
    fn condition_matches(
        &self,
        condition: &PolicyCondition,
        step: &PlanStep,
        qstate: &QState8,
    ) -> bool {
        match condition {
            PolicyCondition::LowVirtue {
                dimension,
                threshold,
            } => {
                let value = match dimension.as_str() {
                    "prudence" => qstate.d4,
                    "justice" => qstate.d5,
                    "temperance" => qstate.d6,
                    "fortitude" => qstate.d7,
                    _ => return false,
                };
                value < *threshold
            }
            PolicyCondition::HighRiskDomain { domain } => step.domain == *domain,
            PolicyCondition::Custom { description: _ } => {
                // Custom conditions would be evaluated by GNN
                false
            }
            _ => false,
        }
    }

    /// Update policy based on episode outcome
    pub async fn update_from_outcome(
        &mut self,
        trajectory: &Trajectory,
        evaluation: &OutcomeEvaluation,
    ) -> Result<()> {
        tracing::info!(
            trajectory_id = %trajectory.id,
            success = evaluation.approved,
            "Updating policy from outcome"
        );

        // Apply policy updates from Franklin's evaluation
        for update in &evaluation.policy_updates {
            match update.update_type {
                PolicyUpdateType::Add => {
                    self.rules.push(PolicyRule {
                        id: crate::generate_id(),
                        condition: PolicyCondition::Custom {
                            description: update.rule.clone(),
                        },
                        action: PolicyAction::RequireFranklinApproval,
                        confidence: 1.0,
                        learned_from_episodes: vec![trajectory.id.clone()],
                    });
                }
                PolicyUpdateType::Remove => {
                    self.rules.retain(|r| r.id != update.rule);
                }
                _ => {}
            }
        }

        // Send trajectory to GNN for learning
        self.train_gnn(trajectory, evaluation).await?;

        Ok(())
    }

    /// Train GNN on new trajectory
    async fn train_gnn(
        &self,
        trajectory: &Trajectory,
        evaluation: &OutcomeEvaluation,
    ) -> Result<()> {
        let client = reqwest::Client::new();

        // Extract QState sequence from trajectory
        let qstates: Vec<&QState8> = trajectory.steps.iter().map(|s| &s.qstate).collect();

        let training_data = serde_json::json!({
            "trajectory_id": trajectory.id,
            "qstates": qstates,
            "outcome": {
                "success": evaluation.approved,
                "virtue_score": evaluation.virtue_score,
                "safety_score": evaluation.safety_score,
            },
            "labels": {
                "should_approve": evaluation.approved,
                "risk_level": if evaluation.safety_score < 0.5 { "high" } else { "low" },
            }
        });

        let response = client
            .post(format!("{}/api/train", self.gnn_url))
            .json(&training_data)
            .send()
            .await;

        if let Ok(resp) = response {
            if resp.status().is_success() {
                tracing::info!("GNN training data submitted successfully");
            }
        }

        Ok(())
    }

    /// Query GNN for policy prediction
    pub async fn query_gnn(&self, qstate: &QState8, action: &str) -> Result<GnnPrediction> {
        let client = reqwest::Client::new();

        let response = client
            .post(format!("{}/api/predict", self.gnn_url))
            .json(&serde_json::json!({
                "qstate": qstate,
                "action": action,
            }))
            .send()
            .await?;

        if response.status().is_success() {
            Ok(response.json().await?)
        } else {
            Ok(GnnPrediction {
                safe: true,
                confidence: 0.5,
                require_approval: false,
                suggested_alternative: None,
            })
        }
    }
}

#[derive(Debug, Clone)]
pub struct PolicyDecision {
    pub allowed: bool,
    pub require_approval: bool,
    pub warnings: Vec<String>,
    pub required_modifications: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GnnPrediction {
    pub safe: bool,
    pub confidence: f64,
    pub require_approval: bool,
    pub suggested_alternative: Option<String>,
}
