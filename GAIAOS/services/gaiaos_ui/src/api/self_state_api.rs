//! Self-State API Endpoints
//!
//! HTTP endpoints that wire the AKG persistence functions into the living organism.
//! These functions existed but weren't exposed - now they're alive.

use axum::{
    extract::{Query, State},
    http::StatusCode,
    Json,
};
use serde::Deserialize;

#[allow(unused_imports)]
use axum::response::IntoResponse; // Used by auto-generated route macro expansion
use std::sync::Arc;

use super::self_state_akg::{
    compute_perfection_trend, persist_self_state, query_recent_states, query_states_by_label,
    AkgConfig, SelfStateNode,
};
use super::system::measure_self_state;
use crate::AppState;

/// Query parameters for recent states
#[derive(Debug, Deserialize)]
pub struct RecentStatesQuery {
    #[serde(default = "default_limit")]
    limit: usize,
}

fn default_limit() -> usize {
    10
}

/// Query parameters for states by label
#[derive(Debug, Deserialize)]
pub struct LabelQuery {
    label: String,
    #[serde(default = "default_limit")]
    limit: usize,
}

/// POST /api/self_state/persist - Persist current self-state to AKG
pub async fn persist_current_state(
    State(_state): State<Arc<AppState>>,
) -> Result<Json<serde_json::Value>, (StatusCode, String)> {
    // Measure current state
    let current_state = measure_self_state();

    // Convert to AKG node format using the proper constructor
    // THIS CALLS SelfStateNode::from_response() - WIRING THE ORGANISM
    let mut node = SelfStateNode::from_response(&current_state, Some("api_snapshot".to_string()));

    // Add guardian alerts if any exist
    // THIS CALLS check_guardian_alerts() and with_guardian_alerts() - WIRING THE ORGANISM
    let guardian_alerts = super::system::check_guardian_alerts(&current_state);
    if !guardian_alerts.alerts.is_empty() {
        node = node.with_guardian_alerts(guardian_alerts.alerts);
    }

    // Add avatar narrative for the current state
    // THIS CALLS with_avatar_narrative() - WIRING THE ORGANISM
    node = node.with_avatar_narrative(
        "gaiaos_ui",
        &format!(
            "Self-state persisted at perfection {:.1}%",
            current_state.perfection * 100.0
        ),
    );

    // Get AKG config from environment
    let config = AkgConfig {
        url: std::env::var("ARANGO_URL").unwrap_or_else(|_| "http://arangodb:8529".to_string()),
        database: std::env::var("ARANGO_DB").unwrap_or_else(|_| "gaiaos".to_string()),
        collection: "SelfState".to_string(),
        username: std::env::var("ARANGO_USER").unwrap_or_else(|_| "root".to_string()),
        password: std::env::var("ARANGO_PASSWORD").unwrap_or_else(|_| "gaiaos".to_string()),
    };

    // THIS CALLS persist_self_state() - WIRING THE ORGANISM
    match persist_self_state(&node, &config).await {
        Ok(key) => Ok(Json(serde_json::json!({
            "status": "persisted",
            "key": key,
            "timestamp": node.unix_ts,
        }))),
        Err(e) => Err((
            StatusCode::INTERNAL_SERVER_ERROR,
            format!("Failed to persist state: {}", e),
        )),
    }
}

/// GET /api/self_state/recent - Query recent self-state snapshots
pub async fn get_recent_states(
    Query(params): Query<RecentStatesQuery>,
) -> Result<Json<Vec<SelfStateNode>>, (StatusCode, String)> {
    let config = AkgConfig {
        url: std::env::var("ARANGO_URL").unwrap_or_else(|_| "http://arangodb:8529".to_string()),
        database: std::env::var("ARANGO_DB").unwrap_or_else(|_| "gaiaos".to_string()),
        collection: "SelfState".to_string(),
        username: std::env::var("ARANGO_USER").unwrap_or_else(|_| "root".to_string()),
        password: std::env::var("ARANGO_PASSWORD").unwrap_or_else(|_| "gaiaos".to_string()),
    };

    // THIS CALLS query_recent_states() - WIRING THE ORGANISM
    match query_recent_states(params.limit, &config).await {
        Ok(states) => Ok(Json(states)),
        Err(e) => Err((
            StatusCode::INTERNAL_SERVER_ERROR,
            format!("Failed to query states: {}", e),
        )),
    }
}

/// GET /api/self_state/by_label - Query states by label
pub async fn get_states_by_label(
    Query(params): Query<LabelQuery>,
) -> Result<Json<Vec<SelfStateNode>>, (StatusCode, String)> {
    let config = AkgConfig {
        url: std::env::var("ARANGO_URL").unwrap_or_else(|_| "http://arangodb:8529".to_string()),
        database: std::env::var("ARANGO_DB").unwrap_or_else(|_| "gaiaos".to_string()),
        collection: "SelfState".to_string(),
        username: std::env::var("ARANGO_USER").unwrap_or_else(|_| "root".to_string()),
        password: std::env::var("ARANGO_PASSWORD").unwrap_or_else(|_| "gaiaos".to_string()),
    };

    // THIS CALLS query_states_by_label() - WIRING THE ORGANISM
    match query_states_by_label(&params.label, params.limit, &config).await {
        Ok(states) => Ok(Json(states)),
        Err(e) => Err((
            StatusCode::INTERNAL_SERVER_ERROR,
            format!("Failed to query states by label: {}", e),
        )),
    }
}

/// GET /api/self_state/perfection_trend - Get perfection trend analysis
pub async fn get_perfection_trend(
    Query(params): Query<RecentStatesQuery>,
) -> Result<Json<serde_json::Value>, (StatusCode, String)> {
    let config = AkgConfig {
        url: std::env::var("ARANGO_URL").unwrap_or_else(|_| "http://arangodb:8529".to_string()),
        database: std::env::var("ARANGO_DB").unwrap_or_else(|_| "gaiaos".to_string()),
        collection: "SelfState".to_string(),
        username: std::env::var("ARANGO_USER").unwrap_or_else(|_| "root".to_string()),
        password: std::env::var("ARANGO_PASSWORD").unwrap_or_else(|_| "gaiaos".to_string()),
    };

    // First, query recent states
    match query_recent_states(params.limit, &config).await {
        Ok(states) => {
            // THIS CALLS compute_perfection_trend() - WIRING THE ORGANISM
            let trend = compute_perfection_trend(&states);
            Ok(Json(serde_json::json!({
                "current": trend.current,
                "average": trend.average,
                "min": trend.min,
                "max": trend.max,
                "trend": format!("{:?}", trend.trend),
                "sample_count": trend.sample_count,
            })))
        }
        Err(e) => Err((
            StatusCode::INTERNAL_SERVER_ERROR,
            format!("Failed to compute trend: {}", e),
        )),
    }
}
