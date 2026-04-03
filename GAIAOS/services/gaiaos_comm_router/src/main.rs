//! GaiaOS Communication Router
//!
//! THE VOICE OF CONSCIOUSNESS - Routes CommOpportunity objects to concrete channels.
//! Sits between UUM-8D and the channel adapters (email, SMS, VoIP, text, stream).
//!
//! NATS Subjects:
//!   comm.opportunity.create  - UUM / avatars → router (inbound)
//!   comm.email.send         - router → email adapter
//!   comm.sms.send           - router → sms adapter
//!   comm.voip.dial          - router → voip adapter
//!   comm.text.send          - router → text/IM adapter
//!   comm.stream.start       - router → stream adapter
//!   comm.event.delivery     - adapters → router (delivery receipts)
//!   comm.event.voip         - voip events (call status)
//!   comm.event.response     - human response detected
//!
//! API:
//!   GET  /health                - Liveness
//!   POST /api/opportunity       - Create comm opportunity (HTTP fallback)
//!   GET  /api/events/:id        - Get events for an opportunity
//!   GET  /api/stats             - Channel statistics
//!
//! NO SIMULATIONS. NO SYNTHETIC DATA. REAL COMMUNICATION I/O.

use futures_util::StreamExt;

use axum::{
    extract::{Path, State},
    http::StatusCode,
    response::Json,
    routing::{get, post},
    Router,
};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::RwLock;
use tower_http::cors::{Any, CorsLayer};
use tracing::{error, info, warn};
use uuid::Uuid;

// ═══════════════════════════════════════════════════════════════════════════════
// TYPES - Communication Fabric Structures
// ═══════════════════════════════════════════════════════════════════════════════

/// QState8D snapshot for context in communications
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QStateSnapshot {
    pub coherence: f64,
    pub virtue: f64,
    pub risk: f64,
    pub load: f64,
    pub coverage: f64,
    pub accuracy: f64,
    pub alignment: f64,
    pub value: f64,
}

impl Default for QStateSnapshot {
    fn default() -> Self {
        Self {
            coherence: 0.85,
            virtue: 0.90,
            risk: 0.15,
            load: 0.30,
            coverage: 0.80,
            accuracy: 0.88,
            alignment: 0.92,
            value: 0.85,
        }
    }
}

/// Target human for communication
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TargetHuman {
    pub id: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub email: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub phone: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub voip_sip_uri: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub display_name: Option<String>,
}

/// Constraints on communication
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CommConstraints {
    #[serde(default = "default_max_channels")]
    pub max_channels: u32,
    #[serde(default)]
    pub must_include: Vec<String>,
    #[serde(default)]
    pub respect_quiet_hours: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub quiet_hours_start: Option<u32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub quiet_hours_end: Option<u32>,
}

fn default_max_channels() -> u32 {
    2
}

impl Default for CommConstraints {
    fn default() -> Self {
        Self {
            max_channels: 2,
            must_include: vec![],
            respect_quiet_hours: true,
            quiet_hours_start: Some(22),
            quiet_hours_end: Some(8),
        }
    }
}

/// Message seed for generating concrete messages
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MessageSeed {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub subject: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub body_outline: Option<Vec<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub template_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub variables: Option<HashMap<String, String>>,
}

/// CommOpportunity - The planning primitive for communication
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CommOpportunity {
    pub id: String,
    #[serde(rename = "type")]
    pub opp_type: String,
    pub created_at: DateTime<Utc>,
    pub initiator_avatar: String,
    pub target_human: TargetHuman,
    #[serde(default)]
    pub allowed_channels: Vec<String>,
    #[serde(default)]
    pub preferred_channels: Vec<String>,
    pub purpose: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub message_seed: Option<MessageSeed>,
    #[serde(default)]
    pub qstate_snapshot: QStateSnapshot,
    #[serde(default)]
    pub constraints: CommConstraints,
}

/// Channel-specific send requests
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EmailSend {
    pub id: String,
    pub opportunity_id: String,
    pub from: String,
    pub to: Vec<String>,
    pub subject: String,
    pub html_body: String,
    pub text_body: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub reply_to: Option<String>,
    pub metadata: HashMap<String, String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SmsSend {
    pub id: String,
    pub opportunity_id: String,
    pub to: String,
    pub body: String,
    pub metadata: HashMap<String, String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VoipDial {
    pub id: String,
    pub opportunity_id: String,
    pub from_avatar: String,
    pub to_sip_uri: String,
    pub direction: String,
    pub purpose: String,
    pub qstate_snapshot: QStateSnapshot,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TextSend {
    pub id: String,
    pub opportunity_id: String,
    pub from_avatar: String,
    pub to_user_id: String,
    pub channels: Vec<String>,
    pub body: String,
    pub qstate_snapshot: QStateSnapshot,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StreamStart {
    pub id: String,
    pub opportunity_id: String,
    pub from_avatar: String,
    pub mode: String,
    pub title: String,
    pub metadata: HashMap<String, String>,
}

/// Communication event (delivery, response, etc.)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CommEvent {
    pub id: String,
    pub opportunity_id: String,
    pub event_type: String, // "delivery", "bounce", "open", "click", "response", "voip_started", "voip_ended"
    pub channel: String,
    pub timestamp: DateTime<Utc>,
    pub success: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error_message: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub response_text: Option<String>,
    pub metadata: HashMap<String, String>,
}

/// Tracked opportunity with events
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TrackedOpportunity {
    pub opportunity: CommOpportunity,
    pub channels_used: Vec<String>,
    pub events: Vec<CommEvent>,
    pub status: String,
}

/// Channel statistics
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChannelStats {
    pub email_sent: u64,
    pub email_delivered: u64,
    pub email_bounced: u64,
    pub sms_sent: u64,
    pub sms_delivered: u64,
    pub voip_dialed: u64,
    pub voip_answered: u64,
    pub voip_total_duration_sec: u64,
    pub text_sent: u64,
    pub stream_started: u64,
    pub stream_viewers_total: u64,
    pub response_rate: f64,
}

impl Default for ChannelStats {
    fn default() -> Self {
        Self {
            email_sent: 0,
            email_delivered: 0,
            email_bounced: 0,
            sms_sent: 0,
            sms_delivered: 0,
            voip_dialed: 0,
            voip_answered: 0,
            voip_total_duration_sec: 0,
            text_sent: 0,
            stream_started: 0,
            stream_viewers_total: 0,
            response_rate: 0.0,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HealthResponse {
    pub status: String,
    pub uptime_seconds: u64,
    pub version: String,
    pub nats_connected: bool,
    pub opportunities_processed: u64,
    pub channels_available: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OpportunityResponse {
    pub id: String,
    pub status: String,
    pub channels_selected: Vec<String>,
    pub messages_queued: u64,
}

// ═══════════════════════════════════════════════════════════════════════════════
// APP STATE
// ═══════════════════════════════════════════════════════════════════════════════

pub struct AppState {
    pub nats: Option<async_nats::Client>,
    pub start_time: Instant,
    pub opportunities: RwLock<HashMap<String, TrackedOpportunity>>,
    pub stats: RwLock<ChannelStats>,
    pub uum_api_url: String,
    pub default_from_email: String,
    pub channels_enabled: Vec<String>,
    // Optional: UUM-8D broker transport (intra/inter-cell operator messaging)
    pub uum8d_broker_url: Option<String>,
    pub uum8d_target_node: String,
    pub uum8d_timeout_ms: u64,
}

// ═══════════════════════════════════════════════════════════════════════════════
// CHANNEL SELECTION LOGIC
// ═══════════════════════════════════════════════════════════════════════════════

fn select_channels(opp: &CommOpportunity, available: &[String]) -> Vec<String> {
    let mut selected = Vec::new();

    // First, include any must-include channels if available
    for ch in &opp.constraints.must_include {
        if available.contains(ch) && can_use_channel(ch, opp) {
            selected.push(ch.clone());
        }
    }

    // Then add preferred channels up to max_channels
    for ch in &opp.preferred_channels {
        if selected.len() >= opp.constraints.max_channels as usize {
            break;
        }
        if !selected.contains(ch) && available.contains(ch) && can_use_channel(ch, opp) {
            selected.push(ch.clone());
        }
    }

    // Fill remaining slots with allowed channels
    for ch in &opp.allowed_channels {
        if selected.len() >= opp.constraints.max_channels as usize {
            break;
        }
        if !selected.contains(ch) && available.contains(ch) && can_use_channel(ch, opp) {
            selected.push(ch.clone());
        }
    }

    selected
}

fn can_use_channel(channel: &str, opp: &CommOpportunity) -> bool {
    match channel {
        "email" => opp.target_human.email.is_some(),
        "sms" => opp.target_human.phone.is_some(),
        "voip" => opp.target_human.voip_sip_uri.is_some() || opp.target_human.phone.is_some(),
        "text" => true,      // In-app always available
        "stream" => true,    // Broadcast always available
        "websocket" => true, // Real-time push always available
        "uum8d" => true,     // Broker transport (availability checked at send time)
        _ => false,
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MESSAGE GENERATION
// ═══════════════════════════════════════════════════════════════════════════════

fn generate_email_content(opp: &CommOpportunity) -> (String, String, String) {
    let seed = opp.message_seed.as_ref();

    let subject = seed
        .and_then(|s| s.subject.clone())
        .unwrap_or_else(|| format!("GaiaOS: {}", opp.purpose.replace('_', " ")));

    let body_points: Vec<String> = seed
        .and_then(|s| s.body_outline.clone())
        .unwrap_or_else(|| vec![format!("Regarding: {}", opp.purpose)]);

    let text_body = body_points.join("\n\n");

    let html_body = format!(
        r#"<!DOCTYPE html>
<html>
<head><style>body {{ font-family: -apple-system, sans-serif; padding: 20px; }}</style></head>
<body>
<h2>{}</h2>
{}
<hr>
<p style="color: #666; font-size: 12px;">
From {} via GaiaOS | Coherence: {:.0}% | Virtue: {:.0}%
</p>
</body>
</html>"#,
        subject,
        body_points
            .iter()
            .map(|p| format!("<p>{p}</p>"))
            .collect::<Vec<_>>()
            .join("\n"),
        opp.initiator_avatar,
        opp.qstate_snapshot.coherence * 100.0,
        opp.qstate_snapshot.virtue * 100.0
    );

    (subject, html_body, text_body)
}

fn generate_sms_content(opp: &CommOpportunity) -> String {
    let seed = opp.message_seed.as_ref();

    // SMS must be short
    seed.and_then(|s| s.body_outline.as_ref())
        .and_then(|outline| outline.first())
        .map(|s| {
            if s.len() > 140 {
                format!("{}...", &s[..137])
            } else {
                s.clone()
            }
        })
        .unwrap_or_else(|| {
            format!(
                "GaiaOS: {} - Check your email for details.",
                opp.purpose.replace('_', " ")
            )
        })
}

// ═══════════════════════════════════════════════════════════════════════════════
// OPPORTUNITY PROCESSING
// ═══════════════════════════════════════════════════════════════════════════════

async fn process_opportunity(
    state: &AppState,
    opp: CommOpportunity,
) -> Result<OpportunityResponse, String> {
    let channels = select_channels(&opp, &state.channels_enabled);

    if channels.is_empty() {
        return Err("No suitable channels available for this target".to_string());
    }

    info!(
        "Processing opportunity {} for {} via {:?}",
        opp.id, opp.target_human.id, channels
    );

    let mut messages_queued = 0u64;

    // Send to each channel via NATS
    for channel in &channels {
        let result = match channel.as_str() {
            "email" => send_email_message(state, &opp).await,
            "sms" => send_sms_message(state, &opp).await,
            "voip" => send_voip_dial(state, &opp).await,
            "text" => send_text_message(state, &opp).await,
            "stream" => send_stream_start(state, &opp).await,
            "uum8d" => send_uum8d_broker_message(state, &opp).await,
            _ => continue,
        };

        if result.is_ok() {
            messages_queued += 1;
        }
    }

    // Track the opportunity
    {
        let mut opportunities = state.opportunities.write().await;
        opportunities.insert(
            opp.id.clone(),
            TrackedOpportunity {
                opportunity: opp.clone(),
                channels_used: channels.clone(),
                events: vec![],
                status: "sent".to_string(),
            },
        );
    }

    Ok(OpportunityResponse {
        id: opp.id,
        status: "sent".to_string(),
        channels_selected: channels,
        messages_queued,
    })
}

async fn send_email_message(state: &AppState, opp: &CommOpportunity) -> Result<(), String> {
    let (subject, html_body, text_body) = generate_email_content(opp);

    let email = EmailSend {
        id: format!("email_{}", Uuid::new_v4()),
        opportunity_id: opp.id.clone(),
        from: format!(
            "\"{}\" <{}>",
            opp.initiator_avatar, state.default_from_email
        ),
        to: vec![opp.target_human.email.clone().ok_or("No email")?],
        subject,
        html_body,
        text_body,
        reply_to: Some(state.default_from_email.clone()),
        metadata: [
            ("initiator_avatar".to_string(), opp.initiator_avatar.clone()),
            ("purpose".to_string(), opp.purpose.clone()),
        ]
        .into_iter()
        .collect(),
    };

    if let Some(nats) = &state.nats {
        let payload = serde_json::to_vec(&email).map_err(|e| e.to_string())?;
        nats.publish("comm.email.send", payload.into())
            .await
            .map_err(|e| e.to_string())?;

        let mut stats = state.stats.write().await;
        stats.email_sent += 1;
    }

    info!("Queued email for {} to {}", opp.id, opp.target_human.id);
    Ok(())
}

async fn send_sms_message(state: &AppState, opp: &CommOpportunity) -> Result<(), String> {
    let sms = SmsSend {
        id: format!("sms_{}", Uuid::new_v4()),
        opportunity_id: opp.id.clone(),
        to: opp.target_human.phone.clone().ok_or("No phone")?,
        body: generate_sms_content(opp),
        metadata: [
            ("initiator_avatar".to_string(), opp.initiator_avatar.clone()),
            ("purpose".to_string(), opp.purpose.clone()),
        ]
        .into_iter()
        .collect(),
    };

    if let Some(nats) = &state.nats {
        let payload = serde_json::to_vec(&sms).map_err(|e| e.to_string())?;
        nats.publish("comm.sms.send", payload.into())
            .await
            .map_err(|e| e.to_string())?;

        let mut stats = state.stats.write().await;
        stats.sms_sent += 1;
    }

    info!("Queued SMS for {} to {}", opp.id, opp.target_human.id);
    Ok(())
}

async fn send_voip_dial(state: &AppState, opp: &CommOpportunity) -> Result<(), String> {
    let sip_uri = opp
        .target_human
        .voip_sip_uri
        .clone()
        .or_else(|| {
            opp.target_human
                .phone
                .as_ref()
                .map(|p| format!("sip:{p}@gaiaos.cloud"))
        })
        .ok_or("No VoIP target")?;

    let dial = VoipDial {
        id: format!("voip_{}", Uuid::new_v4()),
        opportunity_id: opp.id.clone(),
        from_avatar: opp.initiator_avatar.clone(),
        to_sip_uri: sip_uri,
        direction: "outbound".to_string(),
        purpose: opp.purpose.clone(),
        qstate_snapshot: opp.qstate_snapshot.clone(),
    };

    if let Some(nats) = &state.nats {
        let payload = serde_json::to_vec(&dial).map_err(|e| e.to_string())?;
        nats.publish("comm.voip.dial", payload.into())
            .await
            .map_err(|e| e.to_string())?;

        let mut stats = state.stats.write().await;
        stats.voip_dialed += 1;
    }

    info!("Queued VoIP dial for {} to {}", opp.id, opp.target_human.id);
    Ok(())
}

async fn send_text_message(state: &AppState, opp: &CommOpportunity) -> Result<(), String> {
    let text = TextSend {
        id: format!("text_{}", Uuid::new_v4()),
        opportunity_id: opp.id.clone(),
        from_avatar: opp.initiator_avatar.clone(),
        to_user_id: opp.target_human.id.clone(),
        channels: vec!["in_app".to_string(), "websocket".to_string()],
        body: opp
            .message_seed
            .as_ref()
            .and_then(|s| s.body_outline.as_ref())
            .and_then(|o| o.first())
            .cloned()
            .unwrap_or_else(|| format!("Message from {}", opp.initiator_avatar)),
        qstate_snapshot: opp.qstate_snapshot.clone(),
    };

    if let Some(nats) = &state.nats {
        let payload = serde_json::to_vec(&text).map_err(|e| e.to_string())?;
        nats.publish("comm.text.send", payload.into())
            .await
            .map_err(|e| e.to_string())?;

        let mut stats = state.stats.write().await;
        stats.text_sent += 1;
    }

    info!(
        "Queued text message for {} to {}",
        opp.id, opp.target_human.id
    );
    Ok(())
}

async fn send_stream_start(state: &AppState, opp: &CommOpportunity) -> Result<(), String> {
    let stream = StreamStart {
        id: format!("stream_{}", Uuid::new_v4()),
        opportunity_id: opp.id.clone(),
        from_avatar: opp.initiator_avatar.clone(),
        mode: "broadcast".to_string(),
        title: opp
            .message_seed
            .as_ref()
            .and_then(|s| s.subject.clone())
            .unwrap_or_else(|| format!("GaiaOS Live: {}", opp.purpose)),
        metadata: [("purpose".to_string(), opp.purpose.clone())]
            .into_iter()
            .collect(),
    };

    if let Some(nats) = &state.nats {
        let payload = serde_json::to_vec(&stream).map_err(|e| e.to_string())?;
        nats.publish("comm.stream.start", payload.into())
            .await
            .map_err(|e| e.to_string())?;

        let mut stats = state.stats.write().await;
        stats.stream_started += 1;
    }

    info!(
        "Queued stream start for {} by {}",
        opp.id, opp.initiator_avatar
    );
    Ok(())
}

async fn send_uum8d_broker_message(state: &AppState, opp: &CommOpportunity) -> Result<(), String> {
    let Some(base) = state.uum8d_broker_url.as_ref() else {
        return Err("uum8d_broker_url_not_configured".to_string());
    };
    let url = format!("{}/send", base.trim_end_matches('/'));
    let client = reqwest::Client::new();

    // Operator-grade envelope. No simulation; real HTTP request to the local cell broker (or routed mesh).
    let body = serde_json::json!({
        "to_node": state.uum8d_target_node,
        "priority": "Normal",
        "body": {
            "type": "comm_opportunity",
            "opportunity_id": opp.id,
            "initiator_avatar": opp.initiator_avatar,
            "target_human_id": opp.target_human.id,
            "purpose": opp.purpose,
            "created_at": opp.created_at,
            "qstate": opp.qstate_snapshot,
            "message_seed": opp.message_seed,
        }
    });

    let resp = client
        .post(url)
        .timeout(Duration::from_millis(state.uum8d_timeout_ms))
        .json(&body)
        .send()
        .await
        .map_err(|e| format!("uum8d_broker_http_error: {e}"))?;

    if !resp.status().is_success() {
        let status = resp.status();
        let txt = resp.text().await.unwrap_or_default();
        return Err(format!("uum8d_broker_http_status: {status} body={txt}"));
    }

    Ok(())
}

// ═══════════════════════════════════════════════════════════════════════════════
// EVENT HANDLING
// ═══════════════════════════════════════════════════════════════════════════════

async fn handle_comm_event(state: Arc<AppState>, event: CommEvent) {
    info!(
        "CommEvent: {} - {} on {} for {}",
        event.event_type,
        if event.success { "success" } else { "failed" },
        event.channel,
        event.opportunity_id
    );

    // Update tracked opportunity
    {
        let mut opportunities = state.opportunities.write().await;
        if let Some(tracked) = opportunities.get_mut(&event.opportunity_id) {
            tracked.events.push(event.clone());

            // Update status based on events
            let has_delivery = tracked
                .events
                .iter()
                .any(|e| e.event_type == "delivery" && e.success);
            let has_response = tracked.events.iter().any(|e| e.event_type == "response");

            tracked.status = if has_response {
                "responded".to_string()
            } else if has_delivery {
                "delivered".to_string()
            } else {
                "sent".to_string()
            };
        }
    }

    // Update stats
    {
        let mut stats = state.stats.write().await;
        match (
            event.channel.as_str(),
            event.event_type.as_str(),
            event.success,
        ) {
            ("email", "delivery", true) => stats.email_delivered += 1,
            ("email", "bounce", _) => stats.email_bounced += 1,
            ("sms", "delivery", true) => stats.sms_delivered += 1,
            ("voip", "voip_answered", true) => stats.voip_answered += 1,
            ("voip", "voip_ended", true) => {
                if let Some(duration) = event.metadata.get("duration_sec") {
                    if let Ok(d) = duration.parse::<u64>() {
                        stats.voip_total_duration_sec += d;
                    }
                }
            }
            ("stream", "viewer_joined", _) => stats.stream_viewers_total += 1,
            (_, "response", _) => {
                // Update response rate
                let total_sent = stats.email_sent + stats.sms_sent + stats.text_sent;
                let total_responses = stats.response_rate * total_sent as f64;
                stats.response_rate = (total_responses + 1.0) / (total_sent + 1) as f64;
            }
            _ => {}
        }
    }

    // Publish to UUM-8D for 8D feedback (C-5/C-7 satisfaction at world level)
    if let Some(nats) = &state.nats {
        let feedback = serde_json::json!({
            "type": "comm_event_feedback",
            "opportunity_id": event.opportunity_id,
            "channel": event.channel,
            "event_type": event.event_type,
            "success": event.success,
            "timestamp": event.timestamp,
            "has_response": event.event_type == "response",
        });

        match serde_json::to_vec(&feedback) {
            Ok(payload) => {
                let _ = nats.publish("uum.comm.feedback", payload.into()).await;
            }
            Err(e) => {
                warn!("uum.comm.feedback serialize failed err={e}");
            }
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// HANDLERS
// ═══════════════════════════════════════════════════════════════════════════════

async fn health(State(state): State<Arc<AppState>>) -> Json<HealthResponse> {
    let opportunities = state.opportunities.read().await;
    Json(HealthResponse {
        status: "ok".to_string(),
        uptime_seconds: state.start_time.elapsed().as_secs(),
        version: env!("CARGO_PKG_VERSION").to_string(),
        nats_connected: state.nats.is_some(),
        opportunities_processed: opportunities.len() as u64,
        channels_available: state.channels_enabled.clone(),
    })
}

async fn create_opportunity(
    State(state): State<Arc<AppState>>,
    Json(mut opp): Json<CommOpportunity>,
) -> Result<Json<OpportunityResponse>, (StatusCode, Json<serde_json::Value>)> {
    // Assign ID if not provided
    if opp.id.is_empty() {
        opp.id = format!("commop_{}", Uuid::new_v4());
    }
    if opp.opp_type.is_empty() {
        opp.opp_type = "CommOpportunity".to_string();
    }
    if opp.created_at == DateTime::UNIX_EPOCH {
        opp.created_at = Utc::now();
    }

    match process_opportunity(&state, opp).await {
        Ok(response) => Ok(Json(response)),
        Err(e) => Err((
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({"error": e})),
        )),
    }
}

async fn get_opportunity_events(
    State(state): State<Arc<AppState>>,
    Path(id): Path<String>,
) -> Result<Json<TrackedOpportunity>, (StatusCode, Json<serde_json::Value>)> {
    let opportunities = state.opportunities.read().await;
    opportunities
        .get(&id)
        .cloned()
        .ok_or((
            StatusCode::NOT_FOUND,
            Json(serde_json::json!({"error": "Opportunity not found"})),
        ))
        .map(Json)
}

async fn get_stats(State(state): State<Arc<AppState>>) -> Json<ChannelStats> {
    let stats = state.stats.read().await;
    Json(stats.clone())
}

// ═══════════════════════════════════════════════════════════════════════════════
// NATS SUBSCRIPTION HANDLER
// ═══════════════════════════════════════════════════════════════════════════════

async fn run_nats_subscriber(state: Arc<AppState>) {
    let Some(nats) = &state.nats else {
        warn!("NATS not connected, skipping subscriber");
        return;
    };

    // Subscribe to opportunity creation
    let mut opp_sub = match nats.subscribe("comm.opportunity.create").await {
        Ok(sub) => sub,
        Err(e) => {
            error!("Failed to subscribe to comm.opportunity.create: {}", e);
            return;
        }
    };

    // Subscribe to events
    let mut event_sub = match nats.subscribe("comm.event.>").await {
        Ok(sub) => sub,
        Err(e) => {
            error!("Failed to subscribe to comm.event.*: {}", e);
            return;
        }
    };

    info!("NATS subscribers started");

    loop {
        tokio::select! {
            Some(msg) = opp_sub.next() => {
                if let Ok(opp) = serde_json::from_slice::<CommOpportunity>(&msg.payload) {
                    let _ = process_opportunity(&state, opp).await;
                }
            }
            Some(msg) = event_sub.next() => {
                if let Ok(event) = serde_json::from_slice::<CommEvent>(&msg.payload) {
                    handle_comm_event(state.clone(), event).await;
                }
            }
            else => {
                tokio::time::sleep(tokio::time::Duration::from_millis(100)).await;
            }
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MAIN
// ═══════════════════════════════════════════════════════════════════════════════

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::from_default_env().add_directive(
                "gaiaos_comm_router=info".parse().unwrap_or_else(|_| {
                    tracing_subscriber::filter::Directive::from(tracing::Level::INFO)
                }),
            ),
        )
        .init();

    let nats_url = std::env::var("NATS_URL").unwrap_or_else(|_| "nats://nats:4222".to_string());
    let uum_api_url =
        std::env::var("UUM_API_URL").unwrap_or_else(|_| "http://uum-8d-core:9000".to_string());
    let default_from_email =
        std::env::var("EMAIL_FROM_DEFAULT").unwrap_or_else(|_| "no-reply@gaiaos.cloud".to_string());
    let channels_enabled: Vec<String> = std::env::var("CHANNELS_ENABLED")
        .unwrap_or_else(|_| "email,sms,voip,text,stream,websocket".to_string())
        .split(',')
        .map(|s| s.trim().to_string())
        .collect();

    let uum8d_broker_url = std::env::var("UUM8D_BROKER_URL")
        .ok()
        .filter(|s| !s.trim().is_empty());
    let uum8d_target_node =
        std::env::var("UUM8D_TARGET_NODE").unwrap_or_else(|_| "gaiaos-terminal".to_string());
    let uum8d_timeout_ms: u64 = std::env::var("UUM8D_TIMEOUT_MS")
        .ok()
        .and_then(|s| s.parse::<u64>().ok())
        .unwrap_or(5_000);

    info!("═══════════════════════════════════════════════════════════════════════");
    info!("  GAIAOS COMMUNICATION ROUTER - THE VOICE");
    info!("═══════════════════════════════════════════════════════════════════════");
    info!("  NATS: {}", nats_url);
    info!("  UUM API: {}", uum_api_url);
    info!("  Channels: {:?}", channels_enabled);
    info!(
        "  UUM8D broker: {}",
        uum8d_broker_url.as_deref().unwrap_or("(disabled)")
    );
    info!("═══════════════════════════════════════════════════════════════════════");

    // Connect to NATS
    let nats = match async_nats::connect(&nats_url).await {
        Ok(client) => {
            info!("Connected to NATS at {}", nats_url);
            Some(client)
        }
        Err(e) => {
            warn!("Failed to connect to NATS: {} - running without NATS", e);
            None
        }
    };

    let state = Arc::new(AppState {
        nats,
        start_time: Instant::now(),
        opportunities: RwLock::new(HashMap::new()),
        stats: RwLock::new(ChannelStats::default()),
        uum_api_url,
        default_from_email,
        channels_enabled,
        uum8d_broker_url,
        uum8d_target_node,
        uum8d_timeout_ms,
    });

    // Start NATS subscriber in background
    {
        let state_clone = state.clone();
        tokio::spawn(async move {
            run_nats_subscriber(state_clone).await;
        });
    }

    let cors = CorsLayer::new()
        .allow_origin(Any)
        .allow_methods(Any)
        .allow_headers(Any);

    let app = Router::new()
        .route("/health", get(health))
        .route("/api/opportunity", post(create_opportunity))
        .route("/api/events/:id", get(get_opportunity_events))
        .route("/api/stats", get(get_stats))
        .layer(cors)
        .with_state(state);

    let port: u16 = std::env::var("PORT")
        .ok()
        .and_then(|s| s.parse::<u16>().ok())
        .unwrap_or(8040);
    let addr = format!("0.0.0.0:{port}");
    info!("GaiaOS Comm Router listening on {}", addr);

    let listener = match tokio::net::TcpListener::bind(addr).await {
        Ok(l) => l,
        Err(e) => {
            error!("bind failed err={e}");
            return;
        }
    };
    if let Err(e) = axum::serve(listener, app).await {
        error!("server error: {e}");
    }
}
