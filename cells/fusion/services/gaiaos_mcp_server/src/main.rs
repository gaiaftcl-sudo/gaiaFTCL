//! GaiaOS MCP Server
//!
//! Model Context Protocol server for GaiaOS cells.
//! Exposes vChip, brain, virtue, world, AKG, and management tools.

use anyhow::Result;
use axum::{
    extract::State,
    http::StatusCode,
    response::IntoResponse,
    routing::{get, post},
    Json, Router,
};
use axum::extract::Extension;
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tokio::sync::RwLock;
use tower_http::cors::CorsLayer;
use tracing::{info, Level};
use tracing_subscriber::FmtSubscriber;

mod projection;
mod tools;
mod transport;
mod viewspace;

use tools::{
    akg::AkgTools, brain::BrainTools, llm::LlmTools, management::ManagementTools,
    vchip::VChipTools, virtue::VirtueTools, world::WorldTools,
};

/// MCP Server configuration
#[derive(Debug, Clone)]
pub struct McpConfig {
    pub cell_id: String,
    pub vchip_url: String,
    pub brain_url: String,
    pub virtue_url: String,
    pub world_url: String,
    pub akg_url: String,
    pub akg_user: String,
    pub akg_password: String,
    pub llm_url: String,
}

impl Default for McpConfig {
    fn default() -> Self {
        Self {
            cell_id: std::env::var("CELL_ID").unwrap_or_else(|_| "cell-local".into()),
            vchip_url: std::env::var("VCHIP_URL")
                .unwrap_or_else(|_| "http://gaia1-chip:8001".into()),
            brain_url: std::env::var("BRAIN_URL")
                .unwrap_or_else(|_| "http://uum8d-brain:8050".into()),
            virtue_url: std::env::var("VIRTUE_URL")
                .unwrap_or_else(|_| "http://virtue-engine:8810".into()),
            world_url: std::env::var("WORLD_URL")
                .unwrap_or_else(|_| "http://world-engine:8060".into()),
            akg_url: std::env::var("AKG_URL").unwrap_or_else(|_| "http://arangodb:8529".into()),
            akg_user: std::env::var("AKG_USER").unwrap_or_else(|_| "root".into()),
            akg_password: std::env::var("AKG_PASSWORD").unwrap_or_else(|_| "gaiaos2025".into()),
            llm_url: std::env::var("LLM_URL")
                .unwrap_or_else(|_| "http://gaiaos-llm-router:8790".into()),
        }
    }
}

/// Application state
pub struct AppState {
    pub config: McpConfig,
    pub vchip: VChipTools,
    pub brain: BrainTools,
    pub virtue: VirtueTools,
    pub world: WorldTools,
    pub akg: AkgTools,
    pub management: ManagementTools,
    pub llm: LlmTools,
}

impl AppState {
    pub fn new(config: McpConfig) -> Self {
        Self {
            vchip: VChipTools::new(&config.vchip_url),
            brain: BrainTools::new(&config.brain_url, &config.cell_id),
            virtue: VirtueTools::new(&config.virtue_url),
            world: WorldTools::new(&config.world_url),
            akg: AkgTools::new(&config.akg_url, &config.akg_user, &config.akg_password),
            management: ManagementTools::new(&config.cell_id),
            llm: LlmTools::new(&config.llm_url, &config.cell_id),
            config,
        }
    }
}

/// MCP Tool definition
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct McpTool {
    pub name: String,
    pub description: String,
    #[serde(rename = "inputSchema")]
    pub input_schema: serde_json::Value,
}

/// MCP Tool list response
#[derive(Debug, Serialize)]
pub struct ToolListResponse {
    pub tools: Vec<McpTool>,
}

/// MCP Tool call request
#[derive(Debug, Deserialize)]
pub struct ToolCallRequest {
    pub name: String,
    pub arguments: serde_json::Value,
}

/// MCP Tool call response
#[derive(Debug, Serialize)]
pub struct ToolCallResponse {
    pub content: Vec<ContentBlock>,
    #[serde(rename = "isError", skip_serializing_if = "Option::is_none")]
    pub is_error: Option<bool>,
}

#[derive(Debug, Serialize)]
pub struct ContentBlock {
    #[serde(rename = "type")]
    pub content_type: String,
    pub text: String,
}

impl ToolCallResponse {
    pub fn success(result: serde_json::Value) -> Self {
        Self {
            content: vec![ContentBlock {
                content_type: "text".into(),
                text: serde_json::to_string_pretty(&result).unwrap_or_default(),
            }],
            is_error: None,
        }
    }

    pub fn error(message: &str) -> Self {
        Self {
            content: vec![ContentBlock {
                content_type: "text".into(),
                text: message.into(),
            }],
            is_error: Some(true),
        }
    }
}

#[tokio::main]
async fn main() -> Result<()> {
    // Initialize logging
    let subscriber = FmtSubscriber::builder()
        .with_max_level(Level::INFO)
        .finish();
    tracing::subscriber::set_global_default(subscriber)?;

    let config = McpConfig::default();
    info!("Starting GaiaOS MCP Server for cell: {}", config.cell_id);

    // Wire consciousness layer
    let nats_url =
        std::env::var("NATS_URL").unwrap_or_else(|_| "nats://gaiaos-nats:4222".to_string());
    if let Ok(nats_client) = async_nats::connect(&nats_url).await {
        info!("✓ NATS connected for consciousness");

        let nats_announce = nats_client.clone();
        tokio::spawn(async move {
            gaiaos_introspection::announce_service_loop(
                nats_announce,
                "gaiaos-mcp-server".to_string(),
                env!("CARGO_PKG_VERSION").to_string(),
                std::env::var("GAIA_CELL_ID").unwrap_or_else(|_| "unknown".to_string()),
                vec![gaiaos_introspection::IntrospectionEndpoint {
                    name: "tools".into(),
                    kind: "http".into(),
                    path: Some("/mcp/tools/list".into()),
                    subject: None,
                }],
            )
            .await;
        });

        let nats_introspect = nats_client.clone();
        tokio::spawn(async move {
            let _ = gaiaos_introspection::run_introspection_handler(
                nats_introspect,
                "gaiaos-mcp-server".to_string(),
                || gaiaos_introspection::ServiceIntrospectionReply {
                    service: "gaiaos-mcp-server".into(),
                    functions: vec![gaiaos_introspection::FunctionDescriptor {
                        name: "mcp::call_tool".into(),
                        inputs: vec!["ToolRequest".into()],
                        outputs: vec!["ToolResponse".into()],
                        kind: "http".into(),
                        path: Some("/mcp/tools/call".into()),
                        subject: None,
                        side_effects: vec!["TOOL_EXECUTION".into()],
                    }],
                    call_graph_edges: vec![],
                    state_keys: vec!["tool_registry".into()],
                    timestamp: chrono::Utc::now().to_rfc3339(),
                },
            )
            .await;
        });
        info!("✓ Consciousness wired");
    }

    let state = Arc::new(RwLock::new(AppState::new(config)));

    // Arango password for projection: Docker secret first, then env, then fallback for local dev
    let arango_password = std::fs::read_to_string("/run/secrets/arango_password")
        .unwrap_or_else(|_| std::env::var("ARANGO_PASSWORD").unwrap_or_else(|_| "gaiaftcl2026".to_string()));

    // Build router
    let app = Router::new()
        .route("/health", get(health))
        .route("/mcp", get(mcp_info))
        .route("/mcp/tools/list", get(list_tools).post(list_tools))
        .route("/mcp/tools/call", post(call_tool))
        .route("/project", post(project_handler))
        // Legacy/convenience endpoints
        .route("/tools", get(list_tools))
        .route("/call", post(call_tool))
        .layer(CorsLayer::permissive())
        .layer(Extension(arango_password))
        .with_state(state);

    let port = std::env::var("PORT").unwrap_or_else(|_| "9000".into());
    let addr = format!("0.0.0.0:{port}");
    info!("MCP Server listening on {}", addr);

    let listener = tokio::net::TcpListener::bind(&addr).await?;
    axum::serve(listener, app).await?;

    Ok(())
}

/// Health check endpoint
async fn health() -> impl IntoResponse {
    Json(serde_json::json!({
        "status": "healthy",
        "service": "gaiaos-mcp-server",
        "version": "0.1.0"
    }))
}

/// MCP info endpoint
async fn mcp_info() -> impl IntoResponse {
    Json(serde_json::json!({
        "name": "gaiaos-mcp-server",
        "version": "0.1.0",
        "protocol": "mcp",
        "capabilities": {
            "tools": true,
            "resources": false,
            "prompts": false
        }
    }))
}

/// List all available tools
async fn list_tools(State(state): State<Arc<RwLock<AppState>>>) -> impl IntoResponse {
    let state = state.read().await;

    let mut tools = Vec::new();

    // Add vChip tools
    tools.extend(state.vchip.get_tool_definitions());

    // Add brain tools
    tools.extend(state.brain.get_tool_definitions());

    // Add virtue tools
    tools.extend(state.virtue.get_tool_definitions());

    // Add world tools
    tools.extend(state.world.get_tool_definitions());

    // Add AKG tools
    tools.extend(state.akg.get_tool_definitions());

    // Add management tools
    tools.extend(state.management.get_tool_definitions());

    // Add LLM tools (unified GaiaOS model access)
    tools.extend(state.llm.get_tool_definitions());

    Json(ToolListResponse { tools })
}

/// Call a tool
async fn call_tool(
    State(state): State<Arc<RwLock<AppState>>>,
    Json(request): Json<ToolCallRequest>,
) -> Result<Json<ToolCallResponse>, (StatusCode, Json<ToolCallResponse>)> {
    let state = state.read().await;

    // Route to appropriate tool handler
    let result = match request.name.as_str() {
        // vChip tools
        name if name.starts_with("vchip_") => {
            state.vchip.call(&request.name, request.arguments).await
        }

        // Brain tools
        name if name.starts_with("brain_") => {
            state.brain.call(&request.name, request.arguments).await
        }

        // Virtue tools
        name if name.starts_with("virtue_") => {
            state.virtue.call(&request.name, request.arguments).await
        }

        // World tools
        name if name.starts_with("world_") => {
            state.world.call(&request.name, request.arguments).await
        }

        // AKG tools
        name if name.starts_with("akg_") => state.akg.call(&request.name, request.arguments).await,

        // Management tools
        name if name.starts_with("cell_") => {
            state
                .management
                .call(&request.name, request.arguments)
                .await
        }

        // LLM tools (unified GaiaOS model access)
        name if name.starts_with("llm_") => state.llm.call(&request.name, request.arguments).await,

        _ => Err(anyhow::anyhow!("Unknown tool: {}", request.name)),
    };

    match result {
        Ok(value) => Ok(Json(ToolCallResponse::success(value))),
        Err(e) => Err((
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ToolCallResponse::error(&e.to_string())),
        )),
    }
}

/// Request for language projection from manifold state
#[derive(Debug, Deserialize)]
pub struct ProjectRequest {
    pub manifold_position: Vec<f64>,
    pub discovery_refs: Vec<String>,
    pub audience_position: Vec<f64>,
    pub arango_url: String,
    pub arango_db: String,
}

/// Response from language projection
#[derive(Debug, Serialize)]
pub struct ProjectResponse {
    pub language: String,
}

/// Project manifold state to surface language (constitutional: on-demand, never stored)
async fn project_handler(
    Extension(arango_password): Extension<String>,
    Json(req): Json<ProjectRequest>,
) -> Result<Json<ProjectResponse>, (StatusCode, String)> {
    if req.manifold_position.len() != 8 {
        return Err((
            StatusCode::BAD_REQUEST,
            "manifold_position must be 8D vector".to_string(),
        ));
    }
    if req.audience_position.len() != 8 {
        return Err((
            StatusCode::BAD_REQUEST,
            "audience_position must be 8D vector".to_string(),
        ));
    }

    let manifold: [f64; 8] = req
        .manifold_position
        .try_into()
        .map_err(|_| (StatusCode::BAD_REQUEST, "manifold_position length".to_string()))?;
    let audience: [f64; 8] = req
        .audience_position
        .try_into()
        .map_err(|_| (StatusCode::BAD_REQUEST, "audience_position length".to_string()))?;

    match projection::project_state_to_language(
        manifold,
        req.discovery_refs,
        audience,
        &req.arango_url,
        &req.arango_db,
        &arango_password,
    )
    .await
    {
        Ok(language) => Ok(Json(ProjectResponse { language })),
        Err(e) => Err((StatusCode::INTERNAL_SERVER_ERROR, e)),
    }
}
