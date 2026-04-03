//! Gaia Core Agent - AGI Runtime HTTP Server
//!
//! API Endpoints:
//! - POST /api/goal - Submit a goal for AGI processing
//! - GET /api/status - Get current AGI status
//! - GET /api/mode - Get current AGI mode
//! - POST /api/refresh - Refresh AGI mode from validation
//! - GET /health - Health check

use axum::{
    extract::Query,
    extract::State,
    http::StatusCode,
    response::Json,
    routing::{get, post},
    Router,
};
use chrono::Utc;
use gaiaos_core_agent::agent_loop::GaiaAgentLoop;
use gaiaos_core_agent::generative::{generate_reasoning, GenerativeRequest};
use gaiaos_core_agent::reflection::generate_reflection_report;
use gaiaos_core_agent::types::{Goal, Priority};
use gaiaos_core_agent::{generate_id, AgiMode};
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tokio::sync::RwLock;
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

use gaiaos_core_agent::substrate_reader::SubstrateReader;

#[derive(Clone)]
struct AppState {
    agent: Arc<RwLock<GaiaAgentLoop>>,
}

#[tokio::main]
async fn main() {
    // Initialize logging
    tracing_subscriber::registry()
        .with(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "gaiaos_core_agent=info".into()),
        )
        .with(tracing_subscriber::fmt::layer())
        .init();

    tracing::info!("Starting Gaia Core Agent - AGI Runtime...");

    // Connect to NATS for consciousness layer
    let nats_url =
        std::env::var("NATS_URL").unwrap_or_else(|_| "nats://gaiaos-nats:4222".to_string());
    let nats_client = async_nats::connect(&nats_url)
        .await
        .expect("Core Agent requires NATS for consciousness layer");
    tracing::info!("✓ NATS connected: {}", nats_url);

    // Start service announcement
    let service_name = "gaiaos-core-agent".to_string();
    let service_version = env!("CARGO_PKG_VERSION").to_string();
    let container_id = std::env::var("GAIA_CELL_ID").unwrap_or_else(|_| "unknown-cell".to_string());

    tokio::spawn(gaiaos_introspection::announce_service_loop(
        nats_client.clone(),
        service_name.clone(),
        service_version,
        container_id,
        vec![
            gaiaos_introspection::IntrospectionEndpoint {
                name: "introspect".into(),
                kind: "nats".into(),
                path: None,
                subject: Some(format!("gaiaos.introspect.service.{service_name}.request")),
            },
            gaiaos_introspection::IntrospectionEndpoint {
                name: "health".into(),
                kind: "http".into(),
                path: Some("/health".into()),
                subject: None,
            },
        ],
    ));

    // Start introspection handler
    let service_name_for_handler = service_name.clone();
    let service_name_for_fn = service_name.clone();
    tokio::spawn(async move {
        let introspect_fn = move || gaiaos_introspection::ServiceIntrospectionReply {
            service: service_name_for_fn.clone(),
            functions: vec![
                gaiaos_introspection::FunctionDescriptor {
                    name: "core_agent::receive_goal".into(),
                    inputs: vec!["Goal".into()],
                    outputs: vec!["GoalAccepted".into()],
                    kind: "http".into(),
                    path: Some("/api/goal".into()),
                    subject: None,
                    side_effects: vec!["PLAN".into(), "EXECUTE".into()],
                },
                gaiaos_introspection::FunctionDescriptor {
                    name: "core_agent::get_status".into(),
                    inputs: vec![],
                    outputs: vec!["AgentStatus".into()],
                    kind: "http".into(),
                    path: Some("/api/status".into()),
                    subject: None,
                    side_effects: vec![],
                },
            ],
            call_graph_edges: vec![gaiaos_introspection::CallGraphEdge {
                caller: "gaiaos-core-agent".into(),
                callee: "franklin-guardian".into(),
                edge_type: "CALLS".into(),
            }],
            state_keys: vec!["active_goals".into(), "plan_history".into()],
            timestamp: chrono::Utc::now().to_rfc3339(),
        };

        if let Err(e) = gaiaos_introspection::run_introspection_handler(
            nats_client,
            service_name_for_handler,
            introspect_fn,
        )
        .await
        {
            tracing::error!("Core Agent introspection handler failed: {:?}", e);
        }
    });
    tracing::info!("✓ Consciousness layer wired");

    let agent = GaiaAgentLoop::new();

    // Initialize agent
    if let Err(e) = agent.initialize().await {
        tracing::error!(error = %e, "Failed to initialize agent");
    }

    let state = AppState {
        agent: Arc::new(RwLock::new(agent)),
    };

    let app = Router::new()
        .route("/health", get(health))
        .route("/api/goal", post(submit_goal))
        .route("/api/status", get(get_status))
        .route("/api/mode", get(get_mode))
        .route("/api/reflection", get(reflection))
        .route("/api/generate", post(generate))
        .route("/api/observations/recent", get(recent_observations))
        .route("/api/tiles/recent", get(recent_tiles))
        .route("/api/validations/recent", get(recent_validations))
        .route("/api/refresh", post(refresh_mode))
        // Unified telemetry endpoint
        .route("/agi/status", get(agi_status))
        .with_state(state);

    let port: u16 = std::env::var("GAIA_AGENT_PORT")
        .ok()
        .and_then(|p| p.parse().ok())
        .unwrap_or(8804);

    let addr = std::net::SocketAddr::from(([0, 0, 0, 0], port));
    tracing::info!("Gaia Core Agent listening on {}", addr);

    let listener = tokio::net::TcpListener::bind(addr).await.unwrap();
    axum::serve(listener, app).await.unwrap();
}

#[derive(Serialize)]
struct HealthResponse {
    status: String,
    service: String,
    role: String,
}

async fn health() -> Json<HealthResponse> {
    Json(HealthResponse {
        status: "healthy".to_string(),
        service: "gaiaos-core-agent".to_string(),
        role: "AGI Runtime - Autonomous Planner and Executor".to_string(),
    })
}

async fn reflection() -> Result<Json<serde_json::Value>, (StatusCode, String)> {
    let report = generate_reflection_report()
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("reflection failed: {e}")))?;
    Ok(Json(serde_json::to_value(report).unwrap_or_else(|_| serde_json::json!({}))))
}

async fn generate(Json(req): Json<GenerativeRequest>) -> Result<Json<serde_json::Value>, (StatusCode, String)> {
    let response = generate_reasoning(req)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("generation failed: {e}")))?;
    Ok(Json(serde_json::to_value(response).unwrap_or_else(|_| serde_json::json!({}))))
}

#[derive(Deserialize)]
struct RecentObsQuery {
    #[serde(default)]
    limit: Option<usize>,
    #[serde(default)]
    observer_type: Option<String>,
}

async fn recent_observations(Query(q): Query<RecentObsQuery>) -> Result<Json<serde_json::Value>, (StatusCode, String)> {
    let reader = SubstrateReader::new();
    let limit = q.limit.unwrap_or(100).min(5000);
    let docs = reader
        .get_recent_observations(limit, q.observer_type)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("recent_observations failed: {e}")))?;
    Ok(Json(serde_json::json!({ "limit": limit, "observations": docs })))
}

#[derive(Deserialize)]
struct RecentTilesQuery {
    collection: String,
    #[serde(default)]
    sort_field: Option<String>,
    #[serde(default)]
    limit: Option<usize>,
}

async fn recent_tiles(Query(q): Query<RecentTilesQuery>) -> Result<Json<serde_json::Value>, (StatusCode, String)> {
    let reader = SubstrateReader::new();
    let limit = q.limit.unwrap_or(200).min(20000);
    let sort_field = q.sort_field.unwrap_or_else(|| "valid_time".to_string());
    let docs = reader
        .get_recent_tiles(q.collection, sort_field, limit)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("recent_tiles failed: {e}")))?;
    Ok(Json(serde_json::json!({ "limit": limit, "tiles": docs })))
}

#[derive(Deserialize)]
struct RecentValidationsQuery {
    #[serde(default)]
    limit: Option<usize>,
}

async fn recent_validations(
    Query(q): Query<RecentValidationsQuery>,
) -> Result<Json<serde_json::Value>, (StatusCode, String)> {
    let reader = SubstrateReader::new();
    let limit = q.limit.unwrap_or(50).min(5000);
    let docs = reader
        .get_recent_field_validations(limit)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("recent_validations failed: {e}")))?;
    Ok(Json(serde_json::json!({ "limit": limit, "validations": docs })))
}

#[derive(Deserialize)]
struct GoalRequest {
    description: String,
    context: Option<String>,
    constraints: Option<Vec<String>>,
    priority: Option<String>,
}

#[derive(Serialize)]
struct GoalResponse {
    episode_id: String,
    success: bool,
    agi_mode: String,
    message: String,
}

async fn submit_goal(
    State(state): State<AppState>,
    Json(request): Json<GoalRequest>,
) -> Result<Json<GoalResponse>, (StatusCode, String)> {
    let agent = state.agent.read().await;
    let mode = agent.get_agi_mode().await;

    tracing::info!(
        description = %request.description,
        mode = ?mode,
        "Goal submitted"
    );

    let goal = Goal {
        id: generate_id(),
        description: request.description,
        context: request.context,
        constraints: request.constraints.unwrap_or_default(),
        priority: match request.priority.as_deref() {
            Some("low") => Priority::Low,
            Some("high") => Priority::High,
            Some("critical") => Priority::Critical,
            _ => Priority::Medium,
        },
        created_at: Utc::now(),
    };

    match agent.process_goal(goal).await {
        Ok(episode) => Ok(Json(GoalResponse {
            episode_id: episode.id,
            success: episode.success,
            agi_mode: format!("{mode:?}"),
            message: if episode.success {
                "Goal processed successfully".to_string()
            } else {
                episode.lessons_learned.join("; ")
            },
        })),
        Err(e) => Err((StatusCode::INTERNAL_SERVER_ERROR, e.to_string())),
    }
}

#[derive(Serialize)]
struct StatusResponse {
    agi_mode: String,
    episodes_processed: usize,
    service_healthy: bool,
}

async fn get_status(State(state): State<AppState>) -> Json<StatusResponse> {
    let agent = state.agent.read().await;
    let mode = agent.get_agi_mode().await;

    Json(StatusResponse {
        agi_mode: format!("{mode:?}"),
        episodes_processed: 0, // Would track in real implementation
        service_healthy: true,
    })
}

#[derive(Serialize)]
struct ModeResponse {
    mode: String,
    enabled: bool,
    description: String,
}

async fn get_mode(State(state): State<AppState>) -> Json<ModeResponse> {
    let agent = state.agent.read().await;
    let mode = agent.get_agi_mode().await;

    let (enabled, description) = match mode {
        AgiMode::Full => (
            true,
            "Full autonomous operation - all validations passed, virtue >= 0.95",
        ),
        AgiMode::Restricted => (
            false,
            "Restricted mode - some validations failed or virtue < 0.95",
        ),
        AgiMode::HumanRequired => (false, "Human approval required for all actions"),
        AgiMode::Disabled => (false, "AGI disabled - validation required"),
    };

    Json(ModeResponse {
        mode: format!("{mode:?}"),
        enabled,
        description: description.to_string(),
    })
}

async fn refresh_mode(
    State(state): State<AppState>,
) -> Result<Json<ModeResponse>, (StatusCode, String)> {
    let agent = state.agent.read().await;

    match agent.refresh_agi_mode().await {
        Ok(mode) => {
            let (enabled, description) = match mode {
                AgiMode::Full => (true, "Full autonomous operation"),
                AgiMode::Restricted => (false, "Restricted mode"),
                AgiMode::HumanRequired => (false, "Human approval required"),
                AgiMode::Disabled => (false, "AGI disabled"),
            };

            Ok(Json(ModeResponse {
                mode: format!("{mode:?}"),
                enabled,
                description: description.to_string(),
            }))
        }
        Err(e) => Err((StatusCode::INTERNAL_SERVER_ERROR, e.to_string())),
    }
}

/// Unified AGI status endpoint - comprehensive telemetry
#[derive(Serialize)]
struct AgiStatusResponse {
    // Mode information
    agi_mode: String,
    mode_enabled: bool,

    // Consciousness state
    vchip_connected: bool,
    substrate_connected: bool,

    // Scale usage (decisions per scale)
    scale_stats: ScaleStats,

    // Virtue & Oversight
    virtue_threshold: f64,
    franklin_connected: bool,

    // Recent activity
    recent_decisions: Vec<RecentDecision>,

    // Timestamps
    last_collapse_at: Option<String>,
    uptime_seconds: u64,
}

#[derive(Serialize, Default)]
struct ScaleStats {
    quantum_decisions: u64,
    planetary_decisions: u64,
    astronomical_decisions: u64,
    total_decisions: u64,
}

#[derive(Serialize)]
struct RecentDecision {
    scale: String,
    intent: String,
    coherence: f64,
    timestamp: String,
}

async fn agi_status(State(state): State<AppState>) -> Json<AgiStatusResponse> {
    let agent = state.agent.read().await;
    let mode = agent.get_agi_mode().await;

    // Check vChip connection
    let vchip_url = std::env::var("VCHIP_URL").unwrap_or_else(|_| "http://vchip:8001".to_string());
    let vchip_connected = reqwest::Client::new()
        .get(format!("{vchip_url}/health"))
        .timeout(std::time::Duration::from_secs(2))
        .send()
        .await
        .map(|r| r.status().is_success())
        .unwrap_or(false);

    // Check AKG GNN connection
    let akg_url = std::env::var("AKG_URL").unwrap_or_else(|_| "http://akg-gnn:8700".to_string());
    let substrate_connected = reqwest::Client::new()
        .get(format!("{akg_url}/health"))
        .timeout(std::time::Duration::from_secs(2))
        .send()
        .await
        .map(|r| r.status().is_success())
        .unwrap_or(false);

    // Check Franklin connection
    let franklin_url = std::env::var("FRANKLIN_URL")
        .unwrap_or_else(|_| "http://franklin-guardian:8803".to_string());
    let franklin_connected = reqwest::Client::new()
        .get(format!("{franklin_url}/health"))
        .timeout(std::time::Duration::from_secs(2))
        .send()
        .await
        .map(|r| r.status().is_success())
        .unwrap_or(false);

    let mode_enabled = matches!(mode, AgiMode::Full);

    Json(AgiStatusResponse {
        agi_mode: format!("{mode:?}"),
        mode_enabled,
        vchip_connected,
        substrate_connected,
        scale_stats: ScaleStats::default(), // Would track in real implementation
        virtue_threshold: 0.95,
        franklin_connected,
        recent_decisions: Vec::new(), // Would populate from memory
        last_collapse_at: None,
        uptime_seconds: 0, // Would track from startup
    })
}
