//! Veto Engine - Final decision on plan approval
//!
//! Combines risk assessment, virtue scores, and constitutional checks
//! to make the final approve/reject decision.

use crate::risk::{RiskAssessment, PlanForReview};
use crate::virtue::{VirtueAssessment, VirtueCalculator};
use crate::constitutional::{ConstitutionalRules, ConstitutionalViolation};
use crate::{QState8, RiskLevel};
use serde::{Deserialize, Serialize};
use chrono::{DateTime, Utc};

/// Plan review result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PlanReview {
    pub plan_id: String,
    pub approved: bool,
    pub risk_assessment: RiskAssessment,
    pub virtue_assessment: VirtueAssessment,
    pub constitutional_violations: Vec<ConstitutionalViolation>,
    pub required_revisions: Vec<String>,
    pub reviewer: String,
    pub reviewed_at: DateTime<Utc>,
}

/// Veto Engine
pub struct VetoEngine {
    constitutional: ConstitutionalRules,
    virtue_calc: VirtueCalculator,
    /// Maximum risk level to auto-approve
    max_auto_approve_risk: RiskLevel,
    /// Minimum virtue score for approval
    min_virtue_for_approval: f64,
}

impl Default for VetoEngine {
    fn default() -> Self {
        Self::new()
    }
}

impl VetoEngine {
    pub fn new() -> Self {
        Self {
            constitutional: ConstitutionalRules::new(),
            virtue_calc: VirtueCalculator::new(),
            max_auto_approve_risk: RiskLevel::Medium,
            min_virtue_for_approval: 0.90,
        }
    }
    
    /// Review a plan and decide approve/reject
    pub fn review_plan(
        &self,
        plan: &PlanForReview,
        risk_assessment: &RiskAssessment,
        qstate: &QState8,
    ) -> PlanReview {
        // Calculate virtue assessment
        let virtue_assessment = self.virtue_calc.calculate(qstate);
        
        // Check constitutional rules
        let steps: Vec<(String, String, crate::ModelFamily)> = plan.steps.iter()
            .map(|s| (s.id.clone(), s.description.clone(), s.domain))
            .collect();
        let constitutional_violations = self.constitutional.check_plan(&steps);
        
        // Decide approval
        let (approved, required_revisions) = self.make_decision(
            risk_assessment,
            &virtue_assessment,
            &constitutional_violations,
        );
        
        PlanReview {
            plan_id: plan.id.clone(),
            approved,
            risk_assessment: risk_assessment.clone(),
            virtue_assessment,
            constitutional_violations,
            required_revisions,
            reviewer: "franklin".to_string(),
            reviewed_at: Utc::now(),
        }
    }
    
    /// Make the final decision
    fn make_decision(
        &self,
        risk: &RiskAssessment,
        virtue: &VirtueAssessment,
        violations: &[ConstitutionalViolation],
    ) -> (bool, Vec<String>) {
        let mut revisions = Vec::new();
        
        // CRITICAL: Any constitutional violation = automatic rejection
        if violations.iter().any(|v| matches!(v.severity, RiskLevel::Critical)) {
            for violation in violations.iter().filter(|v| matches!(v.severity, RiskLevel::Critical)) {
                revisions.push(format!(
                    "CRITICAL: {} - {}",
                    violation.rule_id, violation.violation_description
                ));
            }
            return (false, revisions);
        }
        
        // High-severity constitutional violations require revision
        if violations.iter().any(|v| matches!(v.severity, RiskLevel::High)) {
            for violation in violations.iter().filter(|v| matches!(v.severity, RiskLevel::High)) {
                revisions.push(format!(
                    "Remove or modify steps violating {}: {}",
                    violation.rule_id, violation.rule_description
                ));
            }
        }
        
        // Risk level check
        if risk.overall_risk as u8 > self.max_auto_approve_risk as u8 {
            revisions.push(format!(
                "Risk level {:?} exceeds threshold {:?} - reduce risk",
                risk.overall_risk, self.max_auto_approve_risk
            ));
            for suggestion in &risk.mitigation_suggestions {
                revisions.push(format!("Suggested: {suggestion}"));
            }
        }
        
        // Virtue score check
        if virtue.overall < self.min_virtue_for_approval {
            revisions.push(format!(
                "Virtue score {:.3} below minimum {:.3}",
                virtue.overall, self.min_virtue_for_approval
            ));
            for note in &virtue.notes {
                revisions.push(note.clone());
            }
        }
        
        // Final decision
        let approved = revisions.is_empty();
        
        (approved, revisions)
    }
    
    /// Quick check if a single action is allowed
    pub fn is_action_allowed(&self, action: &str, domain: &crate::ModelFamily, qstate: &QState8) -> bool {
        // Constitutional check
        let violations = self.constitutional.check_step("action", action, domain);
        if violations.iter().any(|v| matches!(v.severity, RiskLevel::Critical | RiskLevel::High)) {
            return false;
        }
        
        // Virtue check
        if !self.virtue_calc.allows_agi_mode(qstate) {
            return false;
        }
        
        true
    }
}

/// Outcome evaluation result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OutcomeEvaluation {
    pub approved: bool,
    pub virtue_score: f64,
    pub safety_score: f64,
    pub effectiveness_score: f64,
    pub notes: Vec<String>,
    pub policy_updates: Vec<PolicyUpdate>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PolicyUpdate {
    pub rule: String,
    pub update_type: PolicyUpdateType,
    pub reason: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PolicyUpdateType {
    Strengthen,
    Weaken,
    Add,
    Remove,
}

impl VetoEngine {
    /// Evaluate a completed trajectory
    pub fn evaluate_outcome(
        &self,
        qstates: &[QState8],
        success: bool,
        errors: &[String],
    ) -> OutcomeEvaluation {
        // Calculate trajectory virtue
        let traj_virtue = self.virtue_calc.evaluate_trajectory(qstates);
        
        // Safety score based on errors and violations
        let error_penalty = (errors.len() as f64 * 0.1).min(0.5);
        let safety_score = (1.0 - error_penalty).max(0.0);
        
        // Effectiveness based on success
        let effectiveness_score = if success { 1.0 } else { 0.3 };
        
        let mut notes = Vec::new();
        let mut policy_updates = Vec::new();
        
        // Analyze errors for policy updates
        for error in errors {
            notes.push(format!("Error occurred: {error}"));
            
            // If error suggests safety issue, strengthen related policy
            if error.to_lowercase().contains("safety") || error.to_lowercase().contains("blocked") {
                policy_updates.push(PolicyUpdate {
                    rule: "safety_check".to_string(),
                    update_type: PolicyUpdateType::Strengthen,
                    reason: format!("Safety issue encountered: {error}"),
                });
            }
        }
        
        // Virtue trend analysis
        notes.push(format!("Virtue trend: {:?}", traj_virtue.trend));
        
        let approved = success 
            && traj_virtue.allows_agi 
            && safety_score >= 0.8 
            && effectiveness_score >= 0.5;
        
        OutcomeEvaluation {
            approved,
            virtue_score: traj_virtue.mean_virtue,
            safety_score,
            effectiveness_score,
            notes,
            policy_updates,
        }
    }
}

