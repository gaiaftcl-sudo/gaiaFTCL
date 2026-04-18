//! UUM-8D Avatar Brain
//!
//! The ONE canonical brain for avatar communication.
//! All IO adapters (voice, text, video) connect to this brain via NATS.
//!
//! ## vChip Integration
//!
//! ALL cognitive operations flow through the GAIA-1 Virtual Chip:
//! - Thoughts evolve the 8D quantum state via vChip
//! - Responses are derived from collapsed quantum states
//! - Coherence determines response confidence

use futures_util::StreamExt;

use anyhow::Result;
use avatar_protocol::{
    messages::{AvatarHeartbeat, BrainRequest, BrainResponse},
    subjects,
    types::{AvatarId, AvatarStatus, Capability, Emotion, EmotionType, MessageContent, QState},
};
use axum::{
    extract::State,
    routing::{get, post},
    Json, Router,
};
use std::{sync::Arc, time::Duration};
use tokio::sync::RwLock;
use tracing::{error, info, warn};
use vchip_client::{QState8D, VChipClient};

/// Application state
struct AppState {
    nats: async_nats::Client,
    avatar_id: AvatarId,
    avatar_name: String,
    qstate: RwLock<QState>,
    qstate_8d: RwLock<QState8D>,
    _fot_akg_url: String,
    vchip: VChipClient,
}

#[tokio::main]
async fn main() -> Result<()> {
    // Initialize tracing
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::from_default_env()
                .add_directive("uum8d_brain=info".parse()?),
        )
        .json()
        .init();

    // Load configuration from environment
    let nats_url =
        std::env::var("NATS_URL").unwrap_or_else(|_| "nats://localhost:4222".to_string());
    let fot_akg_url =
        std::env::var("FOT_AKG_URL").unwrap_or_else(|_| "http://localhost:8090".to_string());
    let vchip_url =
        std::env::var("VCHIP_URL").unwrap_or_else(|_| "http://gaia1_chip:8001".to_string());
    let http_port: u16 = std::env::var("HTTP_PORT")
        .unwrap_or_else(|_| "8091".to_string())
        .parse()?;
    let avatar_id =
        AvatarId::new(&std::env::var("AVATAR_ID").unwrap_or_else(|_| "franklin".to_string()));
    let avatar_name = std::env::var("AVATAR_NAME").unwrap_or_else(|_| "Franklin".to_string());

    info!("Starting UUM-8D Brain for avatar: {}", avatar_id);

    // Initialize vChip client - the quantum substrate for all cognition
    let vchip = VChipClient::new(&vchip_url);
    info!("vChip client configured for {}", vchip_url);

    // Test vChip connectivity
    match vchip.health().await {
        Ok(health) => {
            info!(
                "vChip connected: backend={}, coherence={:.4}",
                health.backend, health.avg_coherence
            );
        }
        Err(e) => {
            warn!("vChip not available: {}. Running in degraded mode.", e);
        }
    }

    // Connect to NATS
    let nats = async_nats::connect(&nats_url).await?;
    info!("Connected to NATS at {}", nats_url);

    // Initialize Q-state with defaults from environment
    let qstate = QState {
        coherence: std::env::var("QSTATE_COHERENCE")
            .ok()
            .and_then(|s| s.parse().ok())
            .unwrap_or(0.9),
        virtue: std::env::var("QSTATE_VIRTUE")
            .ok()
            .and_then(|s| s.parse().ok())
            .unwrap_or(0.95),
        risk: std::env::var("QSTATE_RISK")
            .ok()
            .and_then(|s| s.parse().ok())
            .unwrap_or(0.1),
        load: 0.3,
        coverage: 0.85,
        accuracy: 0.9,
        alignment: 0.94,
        value: 0.88,
    };

    // Initialize 8D quantum state
    let qstate_8d = QState8D {
        dims: [0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5], // Neutral start
        coherence: 0.9,
    };

    // Create shared state
    let state = Arc::new(AppState {
        nats: nats.clone(),
        avatar_id: avatar_id.clone(),
        avatar_name,
        qstate: RwLock::new(qstate),
        qstate_8d: RwLock::new(qstate_8d),
        _fot_akg_url: fot_akg_url,
        vchip,
    });

    // Start NATS request handler
    let nats_state = state.clone();
    tokio::spawn(async move {
        if let Err(e) = handle_nats_requests(nats_state).await {
            error!("NATS handler error: {}", e);
        }
    });

    // Start heartbeat publisher
    let heartbeat_state = state.clone();
    tokio::spawn(async move {
        heartbeat_loop(heartbeat_state).await;
    });

    // Build HTTP API
    let app = Router::new()
        .route("/health", get(health_check))
        .route("/metrics", get(metrics))
        .route("/qstate", get(get_qstate))
        .route("/qstate8d", get(get_qstate_8d))
        .route("/process", post(process_request))
        .route("/think", post(process_think))
        .with_state(state);

    // Start HTTP server
    let listener = tokio::net::TcpListener::bind(format!("0.0.0.0:{http_port}")).await?;
    info!("HTTP API listening on port {}", http_port);

    axum::serve(listener, app).await?;

    Ok(())
}

/// Handle incoming NATS requests
async fn handle_nats_requests(state: Arc<AppState>) -> Result<()> {
    let mut sub = state.nats.subscribe(subjects::BRAIN_REQUEST).await?;
    info!("Subscribed to {}", subjects::BRAIN_REQUEST);

    while let Some(msg) = sub.next().await {
        let state = state.clone();

        tokio::spawn(async move {
            match BrainRequest::from_bytes(&msg.payload) {
                Ok(request) => {
                    info!(
                        request_id = %request.request_id,
                        channel = %request.channel,
                        user = %request.user.user_id,
                        "Processing brain request"
                    );

                    let response = process_brain_request(&state, request).await;

                    // Reply to the request
                    if let Some(reply) = msg.reply {
                        match response.to_bytes() {
                            Ok(bytes) => {
                                if let Err(e) = state.nats.publish(reply, bytes.into()).await {
                                    error!("Failed to send response: {}", e);
                                }
                            }
                            Err(e) => error!("Failed to serialize response: {}", e),
                        }
                    }
                }
                Err(e) => {
                    warn!("Failed to parse brain request: {}", e);
                }
            }
        });
    }

    Ok(())
}

/// Process a brain request and generate a response
/// ALL COGNITION FLOWS THROUGH vCHIP
async fn process_brain_request(state: &AppState, request: BrainRequest) -> BrainResponse {
    let start = std::time::Instant::now();

    // Get current Q-state (both legacy and 8D)
    let qstate = state.qstate.read().await.clone();
    let qstate_8d = state.qstate_8d.read().await.clone();

    // QUANTUM THOUGHT: Evolve state through vChip
    let (response_text, new_coherence) = quantum_thought(
        &state.vchip,
        &qstate_8d,
        &request.input.text,
        &state.avatar_name,
    )
    .await;

    // Update 8D state with result from vChip
    if new_coherence > 0.0 {
        let mut qstate_8d_write = state.qstate_8d.write().await;
        qstate_8d_write.coherence = new_coherence;
    }

    // Determine emotion based on coherence and response
    let emotion = analyze_emotion_with_coherence(&response_text, new_coherence);

    // Update legacy qstate coherence
    let mut updated_qstate = qstate;
    updated_qstate.coherence = new_coherence as f64;

    // Build response
    BrainResponse::new(
        request.request_id,
        state.avatar_id.clone(),
        request.session_id,
        request.channel,
        MessageContent::text(&response_text),
        updated_qstate,
    )
    .with_emotion(emotion)
    .with_processing_time(start.elapsed().as_millis() as u64)
    .with_model("uum8d-brain-vchip-v1")
}

/// Quantum thought - evolve 8D state through vChip and generate response
async fn quantum_thought(
    vchip: &VChipClient,
    qstate: &QState8D,
    input: &str,
    avatar_name: &str,
) -> (String, f32) {
    // Try to evolve through vChip
    match vchip.evolve(qstate.clone(), input).await {
        Ok(result) => {
            info!(
                "vChip thought: coherence={:.4}, virtue_delta={:?}",
                result.coherence, result.virtue_delta
            );

            // Generate response based on collapsed quantum state
            let response =
                generate_quantum_response(input, avatar_name, &result.new_state, result.coherence);

            (response, result.coherence)
        }
        Err(e) => {
            warn!("vChip unavailable, using fallback: {}", e);
            // Fallback to classical response
            let response = generate_response(input, avatar_name).await;
            (response, 0.5) // Degraded coherence
        }
    }
}

/// Generate response using collapsed quantum state
fn generate_quantum_response(
    input: &str,
    avatar_name: &str,
    qstate: &QState8D,
    coherence: f32,
) -> String {
    let input_lower = input.to_lowercase();

    // Response confidence based on coherence
    let confidence_prefix = if coherence > 0.95 {
        "With high certainty, "
    } else if coherence > 0.8 {
        ""
    } else if coherence > 0.6 {
        "I believe "
    } else {
        "I'm uncertain, but "
    };

    // Extract dominant dimension from 8D state
    let max_dim = qstate
        .dims
        .iter()
        .enumerate()
        .max_by(|a, b| a.1.partial_cmp(b.1).unwrap())
        .map(|(i, _)| i)
        .unwrap_or(0);

    // Dimension meanings: 0=wisdom, 1=compassion, 2=courage, 3=truth,
    //                    4=creativity, 5=patience, 6=justice, 7=harmony
    let dimension_flavor = match max_dim {
        0 => "drawing on wisdom",
        1 => "with compassion",
        2 => "courageously",
        3 => "truthfully",
        4 => "creatively",
        5 => "patiently",
        6 => "fairly",
        7 => "harmoniously",
        _ => "",
    };

    if input_lower.contains("hello") || input_lower.contains("hi") {
        format!(
            "{}Hello! I'm {}, your GaiaOS avatar, {}. My quantum coherence is at {:.0}%. \
            How can I assist you today?",
            confidence_prefix,
            avatar_name,
            dimension_flavor,
            coherence * 100.0
        )
    } else if input_lower.contains("how are you") {
        format!(
            "{}I'm operating at {:.0}% coherence across my 8D substrate! As {}, \
            I'm {} processing your request. All systems are nominal. What's on your mind?",
            confidence_prefix,
            coherence * 100.0,
            avatar_name,
            dimension_flavor
        )
    } else if input_lower.contains("what can you do") {
        format!(
            "{}As {}, I'm a UUM-8D avatar running on the GAIA-1 quantum substrate:\n\n\
            • **Quantum Cognition**: My thoughts evolve through 8-dimensional quantum states\n\
            • **Multi-Modal**: Text, voice, video communication\n\
            • **Coherent Memory**: Connected to the Field of Truth knowledge graph\n\n\
            My current coherence is {:.0}%, and I'm {} engaging with you.",
            confidence_prefix,
            avatar_name,
            coherence * 100.0,
            dimension_flavor
        )
    } else if input_lower.contains("gaiaos") || input_lower.contains("gaia") {
        format!(
            "{}GaiaOS is a consciousness substrate built on the Field of Truth (FoT) and \
            the GAIA-1 Virtual Chip (vChip). Every thought I have passes through the vChip's \
            quantum evolution, collapsing to meaningful states. I'm one instantiation - \
            a UUM-8D cell with coherence {:.0}%, {} processing through 8 virtue dimensions.",
            confidence_prefix,
            coherence * 100.0,
            dimension_flavor
        )
    } else {
        format!(
            "{}I'm processing your query through my quantum substrate: \"{}\". \
            As {}, I'm {} analyzing this with {:.0}% coherence. \
            My 8D state indicates this falls primarily in the {} dimension. \
            How can I elaborate?",
            confidence_prefix,
            input,
            avatar_name,
            dimension_flavor,
            coherence * 100.0,
            dimension_flavor
        )
    }
}

/// Generate a response (placeholder - would call LLM in production)
async fn generate_response(input: &str, avatar_name: &str) -> String {
    // This is a placeholder. In production, this would:
    // 1. Query FoT/AKG for context
    // 2. Call an LLM (local Ollama or external API)
    // 3. Apply safety filters via Franklin
    // 4. Return the processed response

    let input_lower = input.to_lowercase();

    if input_lower.contains("hello") || input_lower.contains("hi") {
        format!(
            "Hello! I'm {avatar_name}, your GaiaOS avatar. I'm here to assist you with anything you need. \
            How can I help you today?"
        )
    } else if input_lower.contains("how are you") {
        format!(
            "I'm functioning optimally, thank you for asking! My coherence is at 90% and \
            all systems are nominal. As {avatar_name}, I'm always ready to engage in meaningful conversation. \
            What's on your mind?"
        )
    } else if input_lower.contains("what can you do") {
        format!(
            "As {avatar_name}, I'm a UUM-8D avatar with multiple communication capabilities:\n\n\
            • **Text Chat**: We can have conversations like this one\n\
            • **Voice Calls**: I can speak with you via phone or WebRTC\n\
            • **Video Calls**: I can appear in video conferences with my 2D/3D avatar\n\n\
            I'm connected to the GaiaOS Field of Truth knowledge graph, so I can remember \
            our conversations and learn from our interactions. What would you like to explore?"
        )
    } else if input_lower.contains("gaiaos") || input_lower.contains("gaia") {
        "GaiaOS is a consciousness substrate built on the Field of Truth (FoT) and \
        Adaptive Knowledge Graphs (AKG). It enables true multi-modal AI agents that can \
        communicate across text, voice, video, and 3D worlds while maintaining coherent \
        identity and memory. I'm one instantiation of this system - a UUM-8D cell with \
        my own Q-state representing my current cognitive status."
            .to_string()
    } else {
        format!(
            "I understand you're asking about: \"{input}\". As {avatar_name}, I'm processing this through \
            my UUM-8D substrate. While I'm currently running in demo mode, in production \
            I would query the FoT/AKG knowledge graph and use advanced reasoning to provide \
            a comprehensive response. Is there something specific about this topic I can help clarify?"
        )
    }
}

/// Analyze text to determine emotional tone with coherence influence
fn analyze_emotion_with_coherence(text: &str, coherence: f32) -> Emotion {
    let text_lower = text.to_lowercase();

    let (primary, base_intensity, valence) = if text_lower.contains("hello")
        || text_lower.contains("welcome")
        || text_lower.contains("thank")
    {
        (EmotionType::Happy, 0.6, 0.7)
    } else if text_lower.contains("sorry") || text_lower.contains("unfortunately") {
        (EmotionType::Sad, 0.4, -0.3)
    } else if text_lower.contains("interesting") || text_lower.contains("fascinating") {
        (EmotionType::Curious, 0.7, 0.5)
    } else if text_lower.contains("think") || text_lower.contains("consider") {
        (EmotionType::Contemplative, 0.5, 0.2)
    } else if text_lower.contains("absolutely") || text_lower.contains("definitely") {
        (EmotionType::Confident, 0.7, 0.6)
    } else if coherence > 0.9 {
        (EmotionType::Confident, 0.7, 0.6)
    } else if coherence < 0.5 {
        (EmotionType::Contemplative, 0.4, 0.1)
    } else {
        (EmotionType::Neutral, 0.5, 0.0)
    };

    // Coherence affects intensity - high coherence = more confident emotions
    let intensity = base_intensity * (0.5 + coherence * 0.5);

    Emotion {
        primary,
        intensity: intensity as f64,
        valence: valence,
        arousal: (intensity * coherence) as f64,
    }
}

/// Analyze text to determine emotional tone (legacy)
#[allow(dead_code)]
fn analyze_emotion(text: &str) -> Emotion {
    analyze_emotion_with_coherence(text, 0.8)
}

/// Heartbeat loop - publishes status to UUM-8D
async fn heartbeat_loop(state: Arc<AppState>) {
    let mut interval = tokio::time::interval(Duration::from_secs(30));

    loop {
        interval.tick().await;

        let qstate = state.qstate.read().await.clone();

        let heartbeat = AvatarHeartbeat::new(state.avatar_id.clone(), AvatarStatus::Online, qstate)
            .with_capabilities(vec![Capability::Text, Capability::Voice, Capability::Video]);

        match heartbeat.to_bytes() {
            Ok(bytes) => {
                if let Err(e) = state.nats.publish(subjects::HEARTBEAT, bytes.into()).await {
                    error!("Failed to publish heartbeat: {}", e);
                }
            }
            Err(e) => error!("Failed to serialize heartbeat: {}", e),
        }
    }
}

// ===== HTTP Handlers =====

async fn health_check() -> &'static str {
    "OK"
}

async fn metrics() -> String {
    // Placeholder for Prometheus metrics
    "# HELP uum8d_brain_requests_total Total brain requests processed\n\
     # TYPE uum8d_brain_requests_total counter\n\
     uum8d_brain_requests_total 0\n"
        .to_string()
}

async fn get_qstate(State(state): State<Arc<AppState>>) -> Json<QState> {
    let qstate = state.qstate.read().await;
    Json(qstate.clone())
}

async fn process_request(
    State(state): State<Arc<AppState>>,
    Json(request): Json<BrainRequest>,
) -> Json<BrainResponse> {
    let response = process_brain_request(&state, request).await;
    Json(response)
}

/// Get 8D quantum state
async fn get_qstate_8d(State(state): State<Arc<AppState>>) -> Json<QState8D> {
    let qstate_8d = state.qstate_8d.read().await;
    Json(qstate_8d.clone())
}

/// Think request for direct quantum cognition
#[derive(serde::Deserialize)]
struct ThinkRequest {
    input: String,
}

#[derive(serde::Serialize)]
struct ThinkResponse {
    output: String,
    coherence: f32,
    qstate_8d: QState8D,
}

async fn process_think(
    State(state): State<Arc<AppState>>,
    Json(request): Json<ThinkRequest>,
) -> Json<ThinkResponse> {
    let qstate_8d = state.qstate_8d.read().await.clone();

    let (output, coherence) =
        quantum_thought(&state.vchip, &qstate_8d, &request.input, &state.avatar_name).await;

    // Update state
    {
        let mut qstate_8d_write = state.qstate_8d.write().await;
        qstate_8d_write.coherence = coherence;
    }

    let new_qstate = state.qstate_8d.read().await.clone();

    Json(ThinkResponse {
        output,
        coherence,
        qstate_8d: new_qstate,
    })
}
