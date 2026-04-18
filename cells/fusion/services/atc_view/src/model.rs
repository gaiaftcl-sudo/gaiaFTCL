use serde::{Deserialize, Serialize};

#[derive(Debug, Deserialize)]
pub struct BboxQuery {
    pub lamin: Option<f64>,
    pub lamax: Option<f64>,
    pub lomin: Option<f64>,
    pub lomax: Option<f64>,
}

#[derive(Debug, Serialize)]
pub struct ErrorResponse {
    pub status: String,
    pub error: String,
}

#[derive(Debug, Deserialize)]
pub struct ArangoCursorResponse {
    pub result: Vec<serde_json::Value>,
}

#[derive(Debug, Deserialize, Serialize)]
pub struct PerceptionUpdate {
    pub frame_id: u64,
    pub timestamp_ms: f64,
    pub perceptions: Vec<serde_json::Value>,
    #[serde(default)]
    pub viewport: Option<serde_json::Value>,
    #[serde(default)]
    pub camera: Option<serde_json::Value>,
}

#[derive(Debug, Serialize)]
pub struct PerceptionReceipt {
    pub accepted: bool,
    pub receipt_id: String,
    pub frame_id: u64,
    pub count: usize,
    pub server_timestamp_ms: f64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub warnings: Option<Vec<String>>,
}

