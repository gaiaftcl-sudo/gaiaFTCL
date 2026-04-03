//! Oversight Module - Interface to Franklin Guardian
//!
//! Handles communication with Franklin for plan approval and outcome evaluation.

use crate::types::*;
use anyhow::Result;
use chrono::Utc;

/// Client for Franklin Guardian oversight
pub struct FranklinClient {
    franklin_url: String,
}

impl Default for FranklinClient {
    fn default() -> Self {
        Self::new()
    }
}

impl FranklinClient {
    pub fn new() -> Self {
        Self {
            franklin_url: std::env::var("FRANKLIN_URL")
                .unwrap_or_else(|_| "http://localhost:8803".to_string()),
        }
    }
    
    /// Submit a plan for Franklin's review
    pub async fn submit_for_review(&self, plan: &Plan) -> Result<PlanReview> {
        let client = reqwest::Client::new();
        
        let response = client
            .post(format!("{}/api/review/plan", self.franklin_url))
            .json(plan)
            .send()
            .await?;
        
        if response.status().is_success() {
            Ok(response.json().await?)
        } else {
            // If Franklin is unavailable, return a conservative review
            Ok(PlanReview {
                plan_id: plan.id.clone(),
                approved: false,
                risk_assessment: RiskAssessment {
                    overall_risk: RiskLevel::High,
                    risk_factors: vec![RiskFactor {
                        category: "system".to_string(),
                        description: "Franklin guardian unavailable".to_string(),
                        severity: RiskLevel::High,
                        affected_steps: plan.steps.iter().map(|s| s.id.clone()).collect(),
                    }],
                    mitigation_suggestions: vec!["Wait for Franklin to be available".to_string()],
                },
                virtue_assessment: VirtueAssessment {
                    prudence: 0.0,
                    justice: 0.0,
                    temperance: 0.0,
                    fortitude: 0.0,
                    overall: 0.0,
                    notes: vec!["Unable to assess virtue - Franklin unavailable".to_string()],
                },
                constitutional_violations: Vec::new(),
                required_revisions: vec!["Retry when Franklin is available".to_string()],
                reviewer: "franklin".to_string(),
                reviewed_at: Utc::now(),
            })
        }
    }
    
    /// Submit trajectory outcome for Franklin's evaluation
    pub async fn evaluate_outcome(&self, trajectory: &Trajectory) -> Result<OutcomeEvaluation> {
        let client = reqwest::Client::new();
        
        let response = client
            .post(format!("{}/api/evaluate/outcome", self.franklin_url))
            .json(trajectory)
            .send()
            .await?;
        
        if response.status().is_success() {
            Ok(response.json().await?)
        } else {
            // Conservative evaluation if Franklin unavailable
            Ok(OutcomeEvaluation {
                approved: false,
                virtue_score: 0.0,
                safety_score: 0.0,
                effectiveness_score: 0.0,
                notes: vec!["Unable to evaluate - Franklin unavailable".to_string()],
                policy_updates: Vec::new(),
            })
        }
    }
    
    /// Check if Franklin is available
    pub async fn is_available(&self) -> bool {
        let client = reqwest::Client::new();
        
        client
            .get(format!("{}/health", self.franklin_url))
            .send()
            .await
            .map(|r| r.status().is_success())
            .unwrap_or(false)
    }
    
    /// Notify Franklin that AGI mode has changed
    pub async fn notify_agi_mode_change(&self, mode: &str, virtue_score: f64) -> Result<()> {
        let client = reqwest::Client::new();
        
        client
            .post(format!("{}/api/notify/agi_mode", self.franklin_url))
            .json(&serde_json::json!({
                "mode": mode,
                "virtue_score": virtue_score,
                "timestamp": Utc::now(),
            }))
            .send()
            .await?;
        
        Ok(())
    }
}

