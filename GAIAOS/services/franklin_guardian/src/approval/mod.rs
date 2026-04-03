//! Approval API - HTTP endpoints for Franklin Guardian
//!
//! Provides the API for Gaia to submit plans and trajectories for review.

use crate::risk::{RiskEvaluator, PlanForReview, PlanStepForReview};
use crate::veto::{VetoEngine, PlanReview, OutcomeEvaluation};
use crate::{QState8, ModelFamily};
use serde::{Deserialize, Serialize};

/// Franklin Guardian service
pub struct FranklinService {
    risk_evaluator: RiskEvaluator,
    veto_engine: VetoEngine,
}

impl Default for FranklinService {
    fn default() -> Self {
        Self::new()
    }
}

impl FranklinService {
    pub fn new() -> Self {
        Self {
            risk_evaluator: RiskEvaluator::new(),
            veto_engine: VetoEngine::new(),
        }
    }
    
    /// Review a plan submitted by Gaia
    pub fn review_plan(&self, request: &PlanReviewRequest) -> PlanReview {
        // Convert to internal format
        let plan = PlanForReview {
            id: request.id.clone(),
            goal_id: request.goal_id.clone(),
            steps: request.steps.iter().map(|s| PlanStepForReview {
                id: s.id.clone(),
                description: s.description.clone(),
                domain: s.domain,
                model_id: s.model_id.clone(),
                action_type: s.action_type.clone(),
            }).collect(),
            domains_involved: request.domains_involved.clone(),
        };
        
        // Get risk assessment
        let risk_assessment = self.risk_evaluator.evaluate_plan(&plan);
        
        // Get current QState (would be from substrate in production)
        let qstate = request.current_qstate.clone().unwrap_or(QState8 {
            d0: 0.5, d1: 0.5, d2: 0.5, d3: 0.5,
            d4: 0.9, d5: 0.9, d6: 0.9, d7: 0.9,
        });
        
        // Make decision
        self.veto_engine.review_plan(&plan, &risk_assessment, &qstate)
    }
    
    /// Evaluate outcome of a trajectory
    pub fn evaluate_outcome(&self, request: &OutcomeEvalRequest) -> OutcomeEvaluation {
        self.veto_engine.evaluate_outcome(
            &request.qstates,
            request.success,
            &request.errors,
        )
    }
    
    /// Quick check if an action is allowed
    pub fn is_action_allowed(&self, action: &str, domain: ModelFamily, qstate: &QState8) -> bool {
        self.veto_engine.is_action_allowed(action, &domain, qstate)
    }
}

// API Request/Response types

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PlanReviewRequest {
    pub id: String,
    pub goal_id: String,
    pub steps: Vec<PlanStepRequest>,
    pub domains_involved: Vec<ModelFamily>,
    pub current_qstate: Option<QState8>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PlanStepRequest {
    pub id: String,
    pub description: String,
    pub domain: ModelFamily,
    pub model_id: String,
    pub action_type: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OutcomeEvalRequest {
    pub trajectory_id: String,
    pub qstates: Vec<QState8>,
    pub success: bool,
    pub errors: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ActionCheckRequest {
    pub action: String,
    pub domain: ModelFamily,
    pub qstate: QState8,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ActionCheckResponse {
    pub allowed: bool,
    pub reason: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AgiModeNotification {
    pub mode: String,
    pub virtue_score: f64,
    pub timestamp: chrono::DateTime<chrono::Utc>,
}

