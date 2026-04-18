use serde::{Deserialize, Serialize};
use chrono::{DateTime, Utc};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TTLGoal {
    pub domain: String,
    pub intent: String,
    pub context: Option<String>,
    #[serde(default)]
    pub constraints: Vec<String>,
    pub priority: Option<String>,
    pub risk_level: Option<String>,
    pub model_family: Option<Vec<String>>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Procedure {
    #[serde(rename = "_key")]
    pub id: String,
    pub name: String,
    pub domain: String,
    pub intent: Option<String>,
    pub steps: Vec<ProcedureStep>,
    #[serde(default)]
    pub embedding: Vec<f32>,
    pub success_rate: f32,
    pub execution_count: u32,
    pub risk_level: String,
    pub model_family: Option<Vec<String>>,
    pub created_at: DateTime<Utc>,
    pub last_executed: Option<DateTime<Utc>>,
    pub avg_duration_ms: Option<u64>,
    pub confidence: f32,
    #[serde(default)]
    pub similarity: f32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProcedureStep {
    pub seq: u32,
    pub action: String,
    pub params: serde_json::Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProcedureExecution {
    #[serde(rename = "_key")]
    pub id: String,
    pub procedure_id: String,
    #[serde(default)]
    pub goal_embedding: Vec<f32>,
    pub context: serde_json::Value,
    pub outcome: String,
    pub virtue_score: f32,
    pub agi_mode: String,
    pub duration_ms: u64,
    pub timestamp: DateTime<Utc>,
    #[serde(default)]
    pub artifacts: Vec<String>,
    pub error_message: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProcedureEdge {
    pub from: String,
    pub to: String,
    #[serde(rename = "type")]
    pub edge_type: String,
    pub weight: f32,
    pub reason: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct PQResponse {
    pub pq_score: f32,
    pub confidence: f32,
    pub procedures: Vec<ProcedureSummary>,
    pub reason: String,
    pub risk_adjustments: RiskAdjustments,
    pub substrate_status: SubstrateStatus,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct ProcedureSummary {
    pub id: String,
    pub name: String,
    pub similarity: f32,
    pub success_rate: f32,
    pub execution_count: u32,
    pub last_executed: Option<DateTime<Utc>>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct RiskAdjustments {
    pub base_pq: f32,
    pub risk_penalty: f32,
    pub domain_bonus: f32,
    pub recency_factor: f32,
    pub final_pq: f32,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct SubstrateStatus {
    pub arango_ok: bool,
    pub gnn_ok: bool,
    pub pq_status: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct EmbeddingRequest {
    pub text: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct EmbeddingResponse {
    pub embedding: Vec<f32>,
    pub dimension: usize,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct HealthResponse {
    pub status: String,
    pub arango_connected: bool,
    pub embedding_model_loaded: bool,
    pub uptime_seconds: u64,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct ExecutionOutcome {
    pub procedure_id: String,
    pub goal_text: String,
    pub success: bool,
    pub virtue_score: f32,
    pub duration_ms: u64,
    pub error_message: Option<String>,
}

