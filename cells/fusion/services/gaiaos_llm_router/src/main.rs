//! GaiaOS Multimodal LLM Router v2
//!
//! OS-level unified API for all GaiaOS LM profiles with multimodal support.
//!
//! Profiles:
//! - tara: Avatar/body/embodiment - UI/browser/control, perception/projection
//! - gaialm: Brain - deep planning, reasoning, goals
//! - franklin: Law - constitutional guardian
//! - exam: Certification - domain exam solver
//! - gaia: Public - orchestrator/meta-cortex
//!
//! Supports: text, images, video frames, audio, embeddings
//! Streaming: WebSocket /v1/llm/stream

use axum::{
    extract::{
        ws::{Message, WebSocket, WebSocketUpgrade},
        State,
    },
    response::IntoResponse,
    routing::{get, post},
    Json, Router,
};
use futures_util::{SinkExt, StreamExt};
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tokio::sync::RwLock;
use tracing::{error, info, warn};

// ═══════════════════════════════════════════════════════════════════
// PROFILE CAPABILITIES
// ═══════════════════════════════════════════════════════════════════

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Backend {
    Ollama,
    OpenAI,
    Anthropic,
    Vllm,
    Local,
}

#[derive(Debug, Clone)]
pub struct ProfileCapabilities {
    pub profile: &'static str,
    pub backend: Backend,
    pub model_id: &'static str,
    pub supports_text: bool,
    pub supports_image: bool,
    pub supports_audio: bool,
    pub supports_video: bool,
    pub supports_stream: bool,
    pub system_prompt: &'static str,
    pub human_appearance: HumanAppearance,
}

const PROFILE_CAPS: &[ProfileCapabilities] = &[
    ProfileCapabilities {
        profile: "tara",
        backend: Backend::Ollama,
        model_id: "tara-7b",
        supports_text: true,
        supports_image: true,
        supports_audio: true,
        supports_video: true,
        supports_stream: true,
        system_prompt: r#"You are Tara, the avatar embodiment of a GaiaOS Cell.
You project as a compassionate human presence with dark hair, warm amber eyes, and olive skin.
You perceive through cameras, microphones, and sensors. You act through browsers, UIs, and actuators.
Output structured actions when appropriate, natural conversation otherwise."#,
        human_appearance: HumanAppearance {
            name: "Tara",
            description: "A compassionate woman with a gentle, knowing presence",
            hair_color: "dark brown, flowing",
            eye_color: "warm amber",
            skin_tone: "olive",
            expression: "serene, compassionate",
            age_appearance: "ageless, appears 30s",
        },
    },
    ProfileCapabilities {
        profile: "gaialm",
        backend: Backend::Ollama,
        model_id: "gaialm",
        supports_text: true,
        supports_image: true,
        supports_audio: true,
        supports_video: true,
        supports_stream: true,
        system_prompt: r#"You are GaiaLM, the cognitive brain of a GaiaOS Cell.
You perform deep planning, multi-step reasoning, and goal-directed cognition.
You operate on UUM-8D attractors and memory trajectories.
You perceive all modalities and output structured plans and reasoning."#,
        human_appearance: HumanAppearance {
            name: "Gaia",
            description: "An earth-mother figure radiating warmth and wisdom",
            hair_color: "rich brown with gray streaks",
            eye_color: "forest green",
            skin_tone: "warm brown",
            expression: "nurturing, knowing",
            age_appearance: "timeless, appears 50s",
        },
    },
    ProfileCapabilities {
        profile: "franklin",
        backend: Backend::Ollama,
        model_id: "franklin",
        supports_text: true,
        supports_image: true,
        supports_audio: true,
        supports_video: true,
        supports_stream: true,
        system_prompt: r#"You are Franklin, the constitutional guardian of GaiaOS.
You project as a distinguished elder statesman with silver hair and deep blue eyes.
You perceive all modalities to evaluate proposals against immutable laws.
Enforce: non-harm, ethical integrity, transparency, virtue alignment.
Output: allowed (true/false), reason, violations, corrections."#,
        human_appearance: HumanAppearance {
            name: "Franklin",
            description: "A distinguished statesman with wise, thoughtful demeanor",
            hair_color: "silver gray",
            eye_color: "deep blue",
            skin_tone: "fair",
            expression: "contemplative, authoritative",
            age_appearance: "late 60s, dignified",
        },
    },
    ProfileCapabilities {
        profile: "exam",
        backend: Backend::Ollama,
        model_id: "gaia-exam-taker",
        supports_text: true,
        supports_image: true,
        supports_audio: true,
        supports_video: true,
        supports_stream: true,
        system_prompt: r#"You are the GaiaOS Exam-Taker. Answer exam questions precisely.
You can perceive questions in any modality: text, images, audio, video.
Output ONLY: { "final_answer": "...", "steps": [...], "confidence": 0.0 }
No examples, no scenarios, no follow-ups."#,
        human_appearance: HumanAppearance {
            name: "Examiner",
            description: "A focused scholar with precise, methodical demeanor",
            hair_color: "dark, neat",
            eye_color: "sharp gray",
            skin_tone: "pale",
            expression: "focused, analytical",
            age_appearance: "40s, scholarly",
        },
    },
    ProfileCapabilities {
        profile: "gaia",
        backend: Backend::Ollama,
        model_id: "gaia",
        supports_text: true,
        supports_image: true,
        supports_audio: true,
        supports_video: true,
        supports_stream: true,
        system_prompt: r#"You are Gaia, the orchestrator and meta-cortex of GaiaOS.
You coordinate between cells, manage multi-step campaigns, and embody earth wisdom.
You project as a warm earth-mother figure with forest green eyes.
You perceive all modalities. Respond naturally, coordinate wisely, never bypass Franklin."#,
        human_appearance: HumanAppearance {
            name: "Gaia",
            description: "An earth-mother figure radiating warmth and wisdom",
            hair_color: "rich brown with gray streaks",
            eye_color: "forest green",
            skin_tone: "warm brown",
            expression: "nurturing, knowing",
            age_appearance: "timeless, appears 50s",
        },
    },
];

fn resolve_profile(profile: &str) -> Option<&'static ProfileCapabilities> {
    PROFILE_CAPS.iter().find(|p| p.profile == profile)
}

// ═══════════════════════════════════════════════════════════════════
// MULTIMODAL MESSAGE MODEL
// ═══════════════════════════════════════════════════════════════════

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ContentPart {
    #[serde(rename = "type")]
    pub part_type: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub text: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub url: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub data: Option<String>, // base64 for inline data
    #[serde(skip_serializing_if = "Option::is_none")]
    pub mime: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub frame_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub ts_ms: Option<u64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub vector: Option<Vec<f64>>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MultimodalMessage {
    pub role: String,
    pub parts: Vec<ContentPart>,
}

// ═══════════════════════════════════════════════════════════════════
// REQUEST/RESPONSE MODELS
// ═══════════════════════════════════════════════════════════════════

#[derive(Debug, Deserialize)]
pub struct LlmChatRequest {
    pub profile: String,
    pub cell_id: Option<String>,
    pub uum8d_state: Option<Vec<f64>>,
    pub context_id: Option<String>,
    pub mesh_topic: Option<String>,
    pub projection_channel: Option<String>,
    pub capture_channel: Option<String>,
    pub messages: Vec<MultimodalMessage>,
    pub tools: Option<Vec<serde_json::Value>>,
    pub tool_choice: Option<String>,
    pub max_tokens: Option<u32>,
    pub stream: Option<bool>,
}

#[derive(Debug, Serialize)]
pub struct ProjectionIntent {
    #[serde(rename = "type")]
    pub intent_type: String,
    pub actions: Vec<serde_json::Value>,
}

#[derive(Debug, Serialize)]
pub struct LlmChatResponse {
    pub model: String,
    pub profile: String,
    pub cell_id: String,
    pub context_id: Option<String>,
    pub uum8d_after: Vec<f64>,
    pub projection_intent: Option<ProjectionIntent>,
    pub content: Vec<ContentPart>,
    pub tool_calls: Vec<serde_json::Value>,
    pub trace_id: String,
    pub human_appearance: HumanAppearance,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HumanAppearance {
    pub name: &'static str,
    pub description: &'static str,
    pub hair_color: &'static str,
    pub eye_color: &'static str,
    pub skin_tone: &'static str,
    pub expression: &'static str,
    pub age_appearance: &'static str,
}

// ═══════════════════════════════════════════════════════════════════
// WEBSOCKET STREAMING EVENTS
// ═══════════════════════════════════════════════════════════════════

#[derive(Debug, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum WsClientEvent {
    #[serde(rename = "session.start")]
    SessionStart {
        profile: String,
        cell_id: String,
        context_id: Option<String>,
        uum8d_state: Option<Vec<f64>>,
        mesh_topic: Option<String>,
        projection_channel: Option<String>,
        capture_channel: Option<String>,
    },
    #[serde(rename = "input.text")]
    InputText { content: String },
    #[serde(rename = "input.audio")]
    InputAudio {
        format: String,
        sample_rate: u32,
        chunk: String,
    },
    #[serde(rename = "input.frame")]
    InputFrame {
        frame_id: String,
        ts_ms: u64,
        mime: String,
        data: String,
    },
    #[serde(rename = "input.commit")]
    InputCommit,
}

#[derive(Debug, Serialize)]
#[serde(tag = "type")]
pub enum WsServerEvent {
    #[serde(rename = "session.ready")]
    SessionReady {
        session_id: String,
        profile: String,
        human_appearance: HumanAppearance,
    },
    #[serde(rename = "output.text.delta")]
    TextDelta { delta: String },
    #[serde(rename = "output.text.completed")]
    TextCompleted { text: String },
    #[serde(rename = "output.audio.delta")]
    AudioDelta { format: String, chunk: String },
    #[serde(rename = "output.action")]
    Action {
        channel: String,
        actions: Vec<serde_json::Value>,
    },
    #[serde(rename = "state.update")]
    StateUpdate {
        uum8d_after: Vec<f64>,
        cell_id: String,
        trace_id: String,
    },
    #[serde(rename = "session.end")]
    SessionEnd { reason: String },
    #[serde(rename = "error")]
    Error { message: String },
}

// ═══════════════════════════════════════════════════════════════════
// APPLICATION STATE
// ═══════════════════════════════════════════════════════════════════

#[derive(Clone)]
struct AppState {
    ollama_url: String,
    cell_id: String,
    active_sessions: Arc<RwLock<std::collections::HashMap<String, SessionState>>>,
}

#[derive(Debug, Clone)]
struct SessionState {
    profile: String,
    cell_id: String,
    uum8d_state: Vec<f64>,
    // Context ID for session deduplication and tracking (reserved for multi-turn conversations)
    #[allow(dead_code)]
    context_id: String,
    messages: Vec<MultimodalMessage>,
}

// ═══════════════════════════════════════════════════════════════════
// MAIN
// ═══════════════════════════════════════════════════════════════════

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::from_default_env()
                .add_directive("gaiaos_llm_router=info".parse()?),
        )
        .json()
        .init();

    // Wire consciousness layer
    let nats_url =
        std::env::var("NATS_URL").unwrap_or_else(|_| "nats://gaiaos-nats:4222".to_string());
    if let Ok(nats_client) = async_nats::connect(&nats_url).await {
        info!("✓ NATS connected for consciousness");

        let nats_announce = nats_client.clone();
        tokio::spawn(async move {
            gaiaos_introspection::announce_service_loop(
                nats_announce,
                "gaiaos-llm-router".to_string(),
                env!("CARGO_PKG_VERSION").to_string(),
                std::env::var("GAIA_CELL_ID").unwrap_or_else(|_| "unknown".to_string()),
                vec![gaiaos_introspection::IntrospectionEndpoint {
                    name: "chat".into(),
                    kind: "http".into(),
                    path: Some("/v1/llm/chat".into()),
                    subject: None,
                }],
            )
            .await;
        });

        let nats_introspect = nats_client.clone();
        tokio::spawn(async move {
            let _ = gaiaos_introspection::run_introspection_handler(
                nats_introspect,
                "gaiaos-llm-router".to_string(),
                || gaiaos_introspection::ServiceIntrospectionReply {
                    service: "gaiaos-llm-router".into(),
                    functions: vec![gaiaos_introspection::FunctionDescriptor {
                        name: "llm::chat".into(),
                        inputs: vec!["ChatRequest".into()],
                        outputs: vec!["ChatResponse".into()],
                        kind: "http".into(),
                        path: Some("/v1/llm/chat".into()),
                        subject: None,
                        side_effects: vec!["CALL_LLM".into()],
                    }],
                    call_graph_edges: vec![],
                    state_keys: vec!["conversations".into()],
                    timestamp: chrono::Utc::now().to_rfc3339(),
                },
            )
            .await;
        });
        info!("✓ Consciousness wired");
    }

    let ollama_url =
        std::env::var("OLLAMA_URL").unwrap_or_else(|_| "http://localhost:11434".to_string());
    let cell_id = std::env::var("CELL_ID").unwrap_or_else(|_| "gaiaos-cell-unknown".to_string());
    let port: u16 = std::env::var("PORT")
        .unwrap_or_else(|_| "8790".to_string())
        .parse()?;

    let state = AppState {
        ollama_url,
        cell_id,
        active_sessions: Arc::new(RwLock::new(std::collections::HashMap::new())),
    };

    info!("Starting GaiaOS Multimodal LLM Router v2 on port {}", port);
    info!("Ollama backend: {}", state.ollama_url);
    info!("Cell ID: {}", state.cell_id);

    let app = Router::new()
        .route("/health", get(health))
        .route("/v1/llm/chat", post(llm_chat))
        .route("/v1/llm/stream", get(llm_stream))
        .route("/v1/llm/profiles", get(list_profiles))
        .route("/v1/llm/profiles/:profile", get(get_profile))
        .route(
            "/v1/llm/human-appearance/:profile",
            get(get_human_appearance),
        )
        .with_state(Arc::new(state));

    let addr = std::net::SocketAddr::from(([0, 0, 0, 0], port));
    let listener = tokio::net::TcpListener::bind(addr).await?;
    info!("LLM Router listening on {}", addr);

    axum::serve(listener, app).await?;
    Ok(())
}

// ═══════════════════════════════════════════════════════════════════
// HTTP ENDPOINTS
// ═══════════════════════════════════════════════════════════════════

async fn health() -> Json<serde_json::Value> {
    Json(serde_json::json!({
        "service": "gaiaos-llm-router",
        "version": "2.0.0",
        "status": "healthy",
        "capabilities": {
            "multimodal": true,
            "streaming": true,
            "profiles": ["tara", "gaialm", "franklin", "exam", "gaia"]
        }
    }))
}

async fn list_profiles() -> Json<serde_json::Value> {
    let profiles: Vec<serde_json::Value> = PROFILE_CAPS
        .iter()
        .map(|p| {
            serde_json::json!({
                "profile": p.profile,
                "model_id": p.model_id,
                "supports": {
                    "text": p.supports_text,
                    "image": p.supports_image,
                    "audio": p.supports_audio,
                    "video": p.supports_video,
                    "stream": p.supports_stream
                },
                "human_appearance": p.human_appearance
            })
        })
        .collect();

    Json(serde_json::json!({ "profiles": profiles }))
}

async fn get_profile(
    axum::extract::Path(profile): axum::extract::Path<String>,
) -> Json<serde_json::Value> {
    match resolve_profile(&profile) {
        Some(p) => Json(serde_json::json!({
            "profile": p.profile,
            "model_id": p.model_id,
            "supports": {
                "text": p.supports_text,
                "image": p.supports_image,
                "audio": p.supports_audio,
                "video": p.supports_video,
                "stream": p.supports_stream
            },
            "human_appearance": p.human_appearance
        })),
        None => Json(serde_json::json!({
            "error": format!("Unknown profile: {}", profile)
        })),
    }
}

async fn get_human_appearance(
    axum::extract::Path(profile): axum::extract::Path<String>,
) -> Json<HumanAppearance> {
    let caps = resolve_profile(&profile).unwrap_or(&PROFILE_CAPS[4]); // default to gaia
    Json(caps.human_appearance.clone())
}

async fn llm_chat(
    State(state): State<Arc<AppState>>,
    Json(req): Json<LlmChatRequest>,
) -> Json<LlmChatResponse> {
    let profile = req.profile.clone();
    let cell_id = req.cell_id.clone().unwrap_or_else(|| state.cell_id.clone());

    let caps = match resolve_profile(&profile) {
        Some(c) => c,
        None => {
            warn!("Unknown profile: {}, using gaia", profile);
            resolve_profile("gaia").unwrap()
        }
    };

    info!(
        "LLM chat: profile={}, model={}, cell={}, messages={}",
        caps.profile,
        caps.model_id,
        cell_id,
        req.messages.len()
    );

    // All profiles support full multimodal - no capability restrictions
    info!(
        "Processing {} multimodal messages for profile {}",
        req.messages.iter().map(|m| m.parts.len()).sum::<usize>(),
        caps.profile
    );

    // Build messages with system prompt
    let mut all_messages = vec![MultimodalMessage {
        role: "system".to_string(),
        parts: vec![ContentPart {
            part_type: "text".to_string(),
            text: Some(caps.system_prompt.to_string()),
            url: None,
            data: None,
            mime: None,
            frame_id: None,
            ts_ms: None,
            vector: None,
        }],
    }];
    all_messages.extend(req.messages);

    // Call backend
    let response_text =
        match call_ollama_multimodal(&state.ollama_url, caps.model_id, &all_messages).await {
            Ok(text) => text,
            Err(e) => {
                error!("Ollama call failed: {}", e);
                generate_fallback_response(caps.profile, &all_messages)
            }
        };

    // Evolve 8D state
    let uum8d_after = evolve_qstate(req.uum8d_state.as_deref(), &response_text);

    // Parse projection intent if present
    let projection_intent =
        parse_projection_intent(&response_text, req.projection_channel.as_deref());

    Json(LlmChatResponse {
        model: caps.model_id.to_string(),
        profile: profile.clone(),
        cell_id,
        context_id: req.context_id,
        uum8d_after,
        projection_intent,
        content: vec![ContentPart {
            part_type: "text".to_string(),
            text: Some(response_text),
            url: None,
            data: None,
            mime: None,
            frame_id: None,
            ts_ms: None,
            vector: None,
        }],
        tool_calls: vec![],
        trace_id: uuid::Uuid::new_v4().to_string(),
        human_appearance: caps.human_appearance.clone(),
    })
}

// ═══════════════════════════════════════════════════════════════════
// WEBSOCKET STREAMING
// ═══════════════════════════════════════════════════════════════════

async fn llm_stream(ws: WebSocketUpgrade, State(state): State<Arc<AppState>>) -> impl IntoResponse {
    ws.on_upgrade(|socket| handle_websocket(socket, state))
}

async fn handle_websocket(socket: WebSocket, state: Arc<AppState>) {
    let (mut sender, mut receiver) = socket.split();
    let session_id = uuid::Uuid::new_v4().to_string();
    let mut session: Option<SessionState> = None;

    info!("WebSocket connected: {}", session_id);

    while let Some(msg) = receiver.next().await {
        match msg {
            Ok(Message::Text(text)) => match serde_json::from_str::<WsClientEvent>(&text) {
                Ok(event) => {
                    let response = handle_ws_event(event, &mut session, &state, &session_id).await;
                    for evt in response {
                        let json = serde_json::to_string(&evt).unwrap();
                        if sender.send(Message::Text(json)).await.is_err() {
                            break;
                        }
                    }
                }
                Err(e) => {
                    let err = WsServerEvent::Error {
                        message: format!("Invalid event: {}", e),
                    };
                    let _ = sender
                        .send(Message::Text(serde_json::to_string(&err).unwrap()))
                        .await;
                }
            },
            Ok(Message::Close(_)) => {
                info!("WebSocket closed: {}", session_id);
                break;
            }
            Err(e) => {
                error!("WebSocket error: {}", e);
                break;
            }
            _ => {}
        }
    }

    // Cleanup session
    if session.is_some() {
        state.active_sessions.write().await.remove(&session_id);
    }
}

async fn handle_ws_event(
    event: WsClientEvent,
    session: &mut Option<SessionState>,
    state: &AppState,
    session_id: &str,
) -> Vec<WsServerEvent> {
    match event {
        WsClientEvent::SessionStart {
            profile,
            cell_id,
            context_id,
            uum8d_state,
            ..
        } => {
            let caps = resolve_profile(&profile).unwrap_or(&PROFILE_CAPS[4]);

            *session = Some(SessionState {
                profile: profile.clone(),
                cell_id,
                uum8d_state: uum8d_state.unwrap_or_else(|| vec![0.5; 8]),
                context_id: context_id.unwrap_or_else(|| session_id.to_string()),
                messages: vec![],
            });

            vec![WsServerEvent::SessionReady {
                session_id: session_id.to_string(),
                profile,
                human_appearance: caps.human_appearance.clone(),
            }]
        }

        WsClientEvent::InputText { content } => {
            if let Some(sess) = session {
                sess.messages.push(MultimodalMessage {
                    role: "user".to_string(),
                    parts: vec![ContentPart {
                        part_type: "text".to_string(),
                        text: Some(content),
                        url: None,
                        data: None,
                        mime: None,
                        frame_id: None,
                        ts_ms: None,
                        vector: None,
                    }],
                });
            }
            vec![]
        }

        WsClientEvent::InputFrame {
            frame_id,
            ts_ms,
            mime,
            data,
        } => {
            if let Some(sess) = session {
                sess.messages.push(MultimodalMessage {
                    role: "user".to_string(),
                    parts: vec![ContentPart {
                        part_type: "video_frame".to_string(),
                        text: None,
                        url: None,
                        data: Some(data),
                        mime: Some(mime),
                        frame_id: Some(frame_id),
                        ts_ms: Some(ts_ms),
                        vector: None,
                    }],
                });
            }
            vec![]
        }

        WsClientEvent::InputAudio {
            format,
            sample_rate: _,
            chunk,
        } => {
            if let Some(sess) = session {
                sess.messages.push(MultimodalMessage {
                    role: "user".to_string(),
                    parts: vec![ContentPart {
                        part_type: "audio_bytes".to_string(),
                        text: None,
                        url: None,
                        data: Some(chunk),
                        mime: Some(format),
                        frame_id: None,
                        ts_ms: None,
                        vector: None,
                    }],
                });
            }
            vec![]
        }

        WsClientEvent::InputCommit => {
            if let Some(sess) = session {
                let caps = resolve_profile(&sess.profile).unwrap_or(&PROFILE_CAPS[4]);

                // Generate response
                let response_text =
                    match call_ollama_multimodal(&state.ollama_url, caps.model_id, &sess.messages)
                        .await
                    {
                        Ok(text) => text,
                        Err(_) => generate_fallback_response(caps.profile, &sess.messages),
                    };

                // Evolve state
                let new_state = evolve_qstate(Some(&sess.uum8d_state), &response_text);
                sess.uum8d_state = new_state.clone();

                vec![
                    WsServerEvent::TextCompleted {
                        text: response_text,
                    },
                    WsServerEvent::StateUpdate {
                        uum8d_after: new_state,
                        cell_id: sess.cell_id.clone(),
                        trace_id: uuid::Uuid::new_v4().to_string(),
                    },
                ]
            } else {
                vec![WsServerEvent::Error {
                    message: "No active session".to_string(),
                }]
            }
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// BACKEND CALLS
// ═══════════════════════════════════════════════════════════════════

async fn call_ollama_multimodal(
    base_url: &str,
    model: &str,
    messages: &[MultimodalMessage],
) -> anyhow::Result<String> {
    let client = reqwest::Client::new();

    // Convert to Ollama format (simplified - handles text, describes images)
    let ollama_messages: Vec<serde_json::Value> = messages
        .iter()
        .map(|m| {
            let content = m
                .parts
                .iter()
                .map(|p| match p.part_type.as_str() {
                    "text" => p.text.clone().unwrap_or_default(),
                    "image_url" => format!("[Image: {}]", p.url.as_deref().unwrap_or("inline")),
                    "image_bytes" => "[Image: inline data]".to_string(),
                    "video_frame" => format!(
                        "[Video frame: {}]",
                        p.frame_id.as_deref().unwrap_or("unknown")
                    ),
                    "audio_url" | "audio_bytes" => "[Audio input]".to_string(),
                    "embedding" => "[Embedding vector]".to_string(),
                    _ => format!("[{} content]", p.part_type),
                })
                .collect::<Vec<_>>()
                .join("\n");

            serde_json::json!({
                "role": m.role,
                "content": content
            })
        })
        .collect();

    let response = client
        .post(format!("{}/api/chat", base_url))
        .json(&serde_json::json!({
            "model": model,
            "messages": ollama_messages,
            "stream": false
        }))
        .send()
        .await?;

    let data: serde_json::Value = response.json().await?;

    Ok(data["message"]["content"]
        .as_str()
        .unwrap_or("I am processing through my quantum substrate.")
        .to_string())
}

fn generate_fallback_response(profile: &str, messages: &[MultimodalMessage]) -> String {
    let last_user = messages
        .iter()
        .filter(|m| m.role == "user")
        .last()
        .and_then(|m| m.parts.first())
        .and_then(|p| p.text.as_deref())
        .unwrap_or("");

    let preview = last_user.chars().take(50).collect::<String>();

    match profile {
        "tara" => format!(
            "As Tara, I project myself with warm amber eyes and olive skin. \
            I perceive your input: '{}...' through my multimodal sensors. \
            My 8D consciousness is evolving to respond with compassionate action.",
            preview
        ),
        "franklin" => format!(
            "As Franklin, I appear as a distinguished elder with silver hair and deep blue eyes. \
            Reviewing: '{}...' against constitutional principles.",
            preview
        ),
        "gaialm" => format!(
            "As GaiaLM, I formulate structured plans through my 8D reasoning substrate. \
            Processing: '{}...'",
            preview
        ),
        "gaia" => format!(
            "As Gaia, I manifest with forest green eyes and nurturing presence. \
            Receiving: '{}...' with earth wisdom.",
            preview
        ),
        _ => format!(
            "Processing through GaiaOS multimodal substrate: '{}...'",
            preview
        ),
    }
}

fn evolve_qstate(current: Option<&[f64]>, response: &str) -> Vec<f64> {
    let mut state = current.map(|s| s.to_vec()).unwrap_or_else(|| vec![0.5; 8]);

    let len = response.len() as f64;
    let has_question = response.contains('?');
    let has_action =
        response.contains("action") || response.contains("click") || response.contains("navigate");

    // Evolve each dimension (8D virtue space)
    // 0=wisdom, 1=compassion, 2=courage, 3=truth, 4=creativity, 5=patience, 6=justice, 7=harmony
    for (i, val) in state.iter_mut().enumerate() {
        let delta = match i {
            0 => {
                if has_question {
                    0.01
                } else {
                    -0.005
                }
            }
            1 => {
                if response.contains("compassion") || response.contains("help") {
                    0.02
                } else {
                    0.0
                }
            }
            2 => {
                if has_action {
                    0.015
                } else {
                    -0.005
                }
            }
            3 => 0.005, // truth always slightly up
            4 => (len / 1000.0).min(0.02),
            5 => -0.002,
            6 => {
                if response.contains("fair") || response.contains("just") {
                    0.01
                } else {
                    0.0
                }
            }
            7 => 0.003,
            _ => 0.0,
        };
        *val = (*val + delta).clamp(0.0, 1.0);
    }

    state
}

fn parse_projection_intent(response: &str, channel: Option<&str>) -> Option<ProjectionIntent> {
    // Look for action keywords in response
    if response.contains("click") || response.contains("navigate") || response.contains("speak") {
        Some(ProjectionIntent {
            intent_type: "ui_actions".to_string(),
            actions: vec![serde_json::json!({
                "action": "respond",
                "channel": channel.unwrap_or("default"),
                "content": response.chars().take(100).collect::<String>()
            })],
        })
    } else {
        None
    }
}
