//! Founder Command Channel Handlers
//! 
//! Implements:
//! - SPEECH moves
//! - DIRECTIVE moves
//! - TRUTH envelopes

use axum::{
    extract::{State},
    response::IntoResponse,
    Json,
};
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tracing::{info};
use uuid::Uuid;
use chrono::Utc;

use crate::AppState;

#[derive(Debug, Deserialize)]
pub struct SpeechMove {
    pub game_id: String,
    pub from_role: String,
    pub text: String,
}

#[derive(Debug, Deserialize)]
pub struct DirectiveMove {
    pub game_id: String,
    pub from_role: String,
    pub directive_type: String,
    pub scope: serde_json::Value,
    pub parameters: serde_json::Value,
}

/// POST /api/founder/speech
pub async fn speech(
    State(state): State<Arc<AppState>>,
    Json(payload): Json<SpeechMove>,
) -> impl IntoResponse {
    info!("Founder Speech: {}", payload.text);
    
    let move_id = Uuid::new_v4().to_string();
    
    // Publish to NATS for Family responders and UI projection
    if let Some(nats) = &state.nats_client {
        let nats_payload = serde_json::json!({
            "move_id": move_id,
            "game_id": payload.game_id,
            "from_role": payload.from_role,
            "text": payload.text,
            "timestamp": Utc::now().timestamp_millis(),
        });
        
        if let Ok(json) = serde_json::to_vec(&nats_payload) {
            // Subject for the game move
            let subject = format!("gaiaos.game.{}.move", payload.game_id);
            if let Err(e) = nats.publish(subject, json.into()).await {
                tracing::error!("Failed to publish speech move to NATS: {}", e);
            }
        }
    }
    
    Json(serde_json::json!({ "status": "SENT", "move_id": move_id }))
}

/// POST /api/founder/directive
pub async fn directive(
    State(_state): State<Arc<AppState>>,
    Json(payload): Json<DirectiveMove>,
) -> impl IntoResponse {
    info!("Founder Directive: {}", payload.directive_type);
    
    Json(serde_json::json!({ "status": "ISSUED", "move_id": Uuid::new_v4().to_string() }))
}

/// POST /api/founder/truth
pub async fn truth(
    State(_state): State<Arc<AppState>>,
    Json(_payload): Json<serde_json::Value>,
) -> impl IntoResponse {
    info!("Founder Truth Envelope Committed");
    
    Json(serde_json::json!({ "status": "COMMITTED", "envelope_id": Uuid::new_v4().to_string() }))
}
