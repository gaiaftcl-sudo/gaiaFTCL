use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

#[derive(Debug, Serialize, Clone)]
pub struct CellHealth {
    pub name: String,
    pub url: String,
    pub status: String,
    pub last_checked: DateTime<Utc>,
    pub details: Option<serde_json::Value>,
}

#[derive(Debug, Serialize, Clone)]
pub struct ContextMetric {
    pub name: String,
    pub value: f64,
}

#[derive(Debug, Serialize, Clone)]
pub struct KnowledgeContextHealth {
    pub name: String,
    pub scale: String,
    pub context: String,
    pub status: String,
    pub last_checked: DateTime<Utc>,
    pub metrics: Vec<ContextMetric>,
    pub notes: Option<String>,
}

#[derive(Debug, Serialize, Clone)]
pub struct SystemStatus {
    pub timestamp: DateTime<Utc>,
    pub virtue: Option<f64>,
    pub coherence: Option<f64>,
    pub cells: Vec<CellHealth>,
    pub contexts: Vec<KnowledgeContextHealth>,
}

#[derive(Debug, Serialize)]
pub struct SimpleHealthResponse {
    pub status: String,
    pub component: &'static str,
    pub timestamp: DateTime<Utc>,
}

