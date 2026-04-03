//! Self-State AKG Persistence
//!
//! Persists 8D self-state snapshots to ArangoDB as FoT nodes.
//! This creates a temporal history of GaiaFTCL self-perfection.

use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::time::{SystemTime, UNIX_EPOCH};

use super::system::{SelfStateResponse, SelfCoord8D, TelemetrySnapshot};

// ============================================================
// AKG SELF-STATE NODE
// ============================================================

/// AKG node representing a self-state snapshot
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SelfStateNode {
    /// AKG document key
    #[serde(rename = "_key")]
    pub key: String,
    
    /// Node type
    pub node_type: String,
    
    /// Timestamp (RFC3339)
    pub timestamp: String,
    
    /// Unix timestamp for sorting
    pub unix_ts: u64,
    
    /// 8D coordinates
    pub coord: SelfCoord8D,
    
    /// Perfection score
    pub perfection: f32,
    
    /// Status band (OPTIMAL, HEALTHY, ATTENTION, CRITICAL)
    pub status: String,
    
    /// Raw telemetry
    pub telemetry: TelemetrySnapshot,
    
    /// Avatar narratives at this moment
    pub avatar_narratives: HashMap<String, String>,
    
    /// Guardian alerts active at this moment
    pub guardian_alerts: Vec<String>,
    
    /// Optional label (e.g., "baseline", "post_exams", "post_fuzz")
    pub label: Option<String>,
    
    /// Hash of the state for verification
    pub state_hash: String,
}

impl SelfStateNode {
    /// Create a new AKG node from a self-state response
    pub fn from_response(response: &SelfStateResponse, label: Option<String>) -> Self {
        let unix_ts = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs();
        
        let key = format!("selfstate_{unix_ts}");
        
        // Compute a simple hash of the state for verification
        let state_hash = compute_state_hash(&response.coord);
        
        Self {
            key,
            node_type: "fot:SelfStateSnapshot".to_string(),
            timestamp: response.measured_at.clone(),
            unix_ts,
            coord: response.coord.clone(),
            perfection: response.perfection,
            status: response.status.clone(),
            telemetry: response.telemetry.clone(),
            avatar_narratives: HashMap::new(), // Populated by caller
            guardian_alerts: vec![],           // Populated by caller
            label,
            state_hash,
        }
    }
    
    /// Add avatar narrative
    pub fn with_avatar_narrative(mut self, avatar: &str, narrative: &str) -> Self {
        self.avatar_narratives.insert(avatar.to_string(), narrative.to_string());
        self
    }
    
    /// Add guardian alerts
    pub fn with_guardian_alerts(mut self, alerts: Vec<String>) -> Self {
        self.guardian_alerts = alerts;
        self
    }
}

/// Compute a simple hash of the 8D coordinates
fn compute_state_hash(coord: &SelfCoord8D) -> String {
    use std::collections::hash_map::DefaultHasher;
    use std::hash::{Hash, Hasher};
    
    let mut hasher = DefaultHasher::new();
    
    // Convert floats to fixed-point for hashing
    let values = [
        (coord.coherence * 10000.0) as u64,
        (coord.virtue * 10000.0) as u64,
        (coord.risk * 10000.0) as u64,
        (coord.load * 10000.0) as u64,
        (coord.coverage * 10000.0) as u64,
        (coord.accuracy * 10000.0) as u64,
        (coord.alignment * 10000.0) as u64,
        (coord.value * 10000.0) as u64,
    ];
    
    for v in values {
        v.hash(&mut hasher);
    }
    
    format!("{:x}", hasher.finish())
}

// ============================================================
// AKG PERSISTENCE
// ============================================================

/// ArangoDB connection config
#[derive(Debug, Clone)]
pub struct AkgConfig {
    pub url: String,
    pub database: String,
    pub collection: String,
    pub username: String,
    pub password: String,
}

impl Default for AkgConfig {
    fn default() -> Self {
        Self {
            url: std::env::var("ARANGODB_URL").unwrap_or_else(|_| "http://127.0.0.1:8529".to_string()),
            database: std::env::var("ARANGODB_DATABASE").unwrap_or_else(|_| "gaiaos".to_string()),
            collection: "self_state_history".to_string(),
            username: std::env::var("ARANGODB_USER").unwrap_or_else(|_| "root".to_string()),
            password: std::env::var("ARANGODB_PASSWORD").unwrap_or_default(),
        }
    }
}

/// Persist a self-state snapshot to ArangoDB
pub async fn persist_self_state(
    node: &SelfStateNode,
    config: &AkgConfig,
) -> Result<String, AkgError> {
    let client = reqwest::Client::new();
    
    let url = format!(
        "{}/_db/{}/_api/document/{}",
        config.url, config.database, config.collection
    );
    
    let response = client
        .post(&url)
        .basic_auth(&config.username, Some(&config.password))
        .json(node)
        .send()
        .await
        .map_err(|e| AkgError::ConnectionError(e.to_string()))?;
    
    if response.status().is_success() {
        let result: serde_json::Value = response.json().await
            .map_err(|e| AkgError::ParseError(e.to_string()))?;
        
        let key = result["_key"].as_str()
            .unwrap_or(&node.key)
            .to_string();
        
        Ok(key)
    } else {
        let status = response.status();
        let text = response.text().await.unwrap_or_default();
        Err(AkgError::InsertError(format!("{status}: {text}")))
    }
}

/// Query recent self-state snapshots
pub async fn query_recent_states(
    limit: usize,
    config: &AkgConfig,
) -> Result<Vec<SelfStateNode>, AkgError> {
    let client = reqwest::Client::new();
    
    let query = format!(
        r#"
        FOR doc IN {}
            SORT doc.unix_ts DESC
            LIMIT {}
            RETURN doc
        "#,
        config.collection, limit
    );
    
    let url = format!(
        "{}/_db/{}/_api/cursor",
        config.url, config.database
    );
    
    let body = serde_json::json!({
        "query": query
    });
    
    let response = client
        .post(&url)
        .basic_auth(&config.username, Some(&config.password))
        .json(&body)
        .send()
        .await
        .map_err(|e| AkgError::ConnectionError(e.to_string()))?;
    
    if response.status().is_success() {
        let result: serde_json::Value = response.json().await
            .map_err(|e| AkgError::ParseError(e.to_string()))?;
        
        let nodes: Vec<SelfStateNode> = serde_json::from_value(result["result"].clone())
            .unwrap_or_default();
        
        Ok(nodes)
    } else {
        let status = response.status();
        let text = response.text().await.unwrap_or_default();
        Err(AkgError::QueryError(format!("{status}: {text}")))
    }
}

/// Query states by label
pub async fn query_states_by_label(
    label: &str,
    limit: usize,
    config: &AkgConfig,
) -> Result<Vec<SelfStateNode>, AkgError> {
    let client = reqwest::Client::new();
    
    let query = format!(
        r#"
        FOR doc IN {}
            FILTER doc.label == @label
            SORT doc.unix_ts DESC
            LIMIT {}
            RETURN doc
        "#,
        config.collection, limit
    );
    
    let url = format!(
        "{}/_db/{}/_api/cursor",
        config.url, config.database
    );
    
    let body = serde_json::json!({
        "query": query,
        "bindVars": {
            "label": label
        }
    });
    
    let response = client
        .post(&url)
        .basic_auth(&config.username, Some(&config.password))
        .json(&body)
        .send()
        .await
        .map_err(|e| AkgError::ConnectionError(e.to_string()))?;
    
    if response.status().is_success() {
        let result: serde_json::Value = response.json().await
            .map_err(|e| AkgError::ParseError(e.to_string()))?;
        
        let nodes: Vec<SelfStateNode> = serde_json::from_value(result["result"].clone())
            .unwrap_or_default();
        
        Ok(nodes)
    } else {
        let status = response.status();
        let text = response.text().await.unwrap_or_default();
        Err(AkgError::QueryError(format!("{status}: {text}")))
    }
}

/// Compute perfection trend from recent states
pub fn compute_perfection_trend(states: &[SelfStateNode]) -> PerfectionTrend {
    if states.is_empty() {
        return PerfectionTrend::default();
    }
    
    let current = states.first().map(|s| s.perfection).unwrap_or(0.0);
    let avg: f32 = states.iter().map(|s| s.perfection).sum::<f32>() / states.len() as f32;
    let min = states.iter().map(|s| s.perfection).fold(f32::INFINITY, f32::min);
    let max = states.iter().map(|s| s.perfection).fold(f32::NEG_INFINITY, f32::max);
    
    // Trend direction
    let trend = if states.len() >= 2 {
        let recent_avg: f32 = states.iter().take(5).map(|s| s.perfection).sum::<f32>() / 5.0_f32.min(states.len() as f32);
        let older_avg: f32 = states.iter().skip(5).take(5).map(|s| s.perfection).sum::<f32>() / 5.0_f32.min((states.len() - 5) as f32).max(1.0);
        
        if recent_avg > older_avg + 0.02 {
            TrendDirection::Improving
        } else if recent_avg < older_avg - 0.02 {
            TrendDirection::Declining
        } else {
            TrendDirection::Stable
        }
    } else {
        TrendDirection::Unknown
    };
    
    PerfectionTrend {
        current,
        average: avg,
        min,
        max,
        trend,
        sample_count: states.len(),
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PerfectionTrend {
    pub current: f32,
    pub average: f32,
    pub min: f32,
    pub max: f32,
    pub trend: TrendDirection,
    pub sample_count: usize,
}

impl Default for PerfectionTrend {
    fn default() -> Self {
        Self {
            current: 0.0,
            average: 0.0,
            min: 0.0,
            max: 0.0,
            trend: TrendDirection::Unknown,
            sample_count: 0,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum TrendDirection {
    Improving,
    Stable,
    Declining,
    Unknown,
}

#[derive(Debug)]
pub enum AkgError {
    ConnectionError(String),
    InsertError(String),
    QueryError(String),
    ParseError(String),
}

impl std::fmt::Display for AkgError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            AkgError::ConnectionError(s) => write!(f, "AKG connection error: {s}"),
            AkgError::InsertError(s) => write!(f, "AKG insert error: {s}"),
            AkgError::QueryError(s) => write!(f, "AKG query error: {s}"),
            AkgError::ParseError(s) => write!(f, "AKG parse error: {s}"),
        }
    }
}

impl std::error::Error for AkgError {}

