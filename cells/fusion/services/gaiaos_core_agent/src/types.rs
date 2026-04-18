//! Core types for Gaia Agent

use crate::{ModelFamily, QState8};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

/// A user goal/task that Gaia must accomplish
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Goal {
    pub id: String,
    pub description: String,
    pub context: Option<String>,
    pub constraints: Vec<String>,
    pub priority: Priority,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Priority {
    Low,
    Medium,
    High,
    Critical,
}

/// A plan that Gaia creates to accomplish a goal
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Plan {
    pub id: String,
    pub goal_id: String,
    pub steps: Vec<PlanStep>,
    pub estimated_duration_ms: u64,
    pub risk_level: RiskLevel,
    pub domains_involved: Vec<ModelFamily>,
    pub created_at: DateTime<Utc>,
    pub status: PlanStatus,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PlanStep {
    pub id: String,
    pub description: String,
    pub domain: ModelFamily,
    pub model_id: String,
    pub action_type: ActionType,
    pub inputs: serde_json::Value,
    pub dependencies: Vec<String>, // IDs of steps that must complete first
    pub status: StepStatus,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ActionType {
    /// Call a language model
    ModelCall,
    /// Use Fara for computer control
    ComputerUse,
    /// Run a simulation (PAN)
    Simulation,
    /// Query the knowledge graph
    KnowledgeQuery,
    /// Store to memory
    MemoryStore,
    /// Execute code
    CodeExecution,
    /// Human notification (when AGI mode is restricted)
    HumanNotification,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum StepStatus {
    Pending,
    InProgress,
    Completed,
    Failed,
    Skipped,
    RequiresApproval,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PlanStatus {
    Draft,
    AwaitingApproval,
    Approved,
    Rejected,
    InProgress,
    Completed,
    Failed,
    Revised,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum RiskLevel {
    Low,
    Medium,
    High,
    Critical,
}

/// Franklin's review of a plan
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PlanReview {
    pub plan_id: String,
    pub approved: bool,
    pub risk_assessment: RiskAssessment,
    pub virtue_assessment: VirtueAssessment,
    pub constitutional_violations: Vec<ConstitutionalViolation>,
    pub required_revisions: Vec<String>,
    pub reviewer: String, // "franklin"
    pub reviewed_at: DateTime<Utc>,
}

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

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VirtueAssessment {
    pub prudence: f64,
    pub justice: f64,
    pub temperance: f64,
    pub fortitude: f64,
    pub overall: f64,
    pub notes: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConstitutionalViolation {
    pub rule_id: String,
    pub rule_description: String,
    pub violation_description: String,
    pub affected_steps: Vec<String>,
    pub severity: RiskLevel,
}

/// Execution trajectory - the actual steps taken
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Trajectory {
    pub id: String,
    pub plan_id: String,
    pub goal_id: String,
    pub steps: Vec<TrajectoryStep>,
    pub started_at: DateTime<Utc>,
    pub completed_at: Option<DateTime<Utc>>,
    pub status: TrajectoryStatus,
    pub outcome: Option<Outcome>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TrajectoryStep {
    pub plan_step_id: String,
    pub qstate: QState8,
    pub input: serde_json::Value,
    pub output: serde_json::Value,
    pub latency_ms: u64,
    pub started_at: DateTime<Utc>,
    pub completed_at: DateTime<Utc>,
    pub success: bool,
    pub error: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TrajectoryStatus {
    InProgress,
    Completed,
    Failed,
    Aborted,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Outcome {
    pub success: bool,
    pub goal_achieved: bool,
    pub result: serde_json::Value,
    pub errors: Vec<String>,
    pub franklin_evaluation: Option<OutcomeEvaluation>,
}

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

/// Episode - a complete goal → plan → execution → outcome cycle
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Episode {
    pub id: String,
    pub goal: Goal,
    pub plans: Vec<Plan>,          // May have multiple if revised
    pub reviews: Vec<PlanReview>,
    pub trajectory: Option<Trajectory>,
    pub started_at: DateTime<Utc>,
    pub completed_at: Option<DateTime<Utc>>,
    pub success: bool,
    pub lessons_learned: Vec<String>,
}

