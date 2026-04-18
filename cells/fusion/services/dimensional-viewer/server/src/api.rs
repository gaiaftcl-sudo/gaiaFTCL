//! HTTP and WebSocket API for Dimensional Viewer
//! 
//! Provides:
//! - Static file serving for the Bevy WASM client
//! - REST endpoints for projection
//! - WebSocket endpoint for real-time streaming

use axum::{
    extract::{
        ws::{Message, WebSocket, WebSocketUpgrade},
        State,
    },
    http::StatusCode,
    response::{IntoResponse, Response},
    routing::{get, post},
    Json, Router,
};
use futures_util::{SinkExt, StreamExt};
use std::sync::Arc;
use std::time::Duration;
use tower_http::{
    cors::{Any, CorsLayer},
    services::ServeDir,
    trace::TraceLayer,
};
use tracing::{debug, error, info};

use crate::models::*;
use crate::pipeline::ViewerPipeline;

/// Application state shared across handlers
#[derive(Clone)]
pub struct AppState {
    pub pipeline: Arc<ViewerPipeline>,
    pub static_dir: String,
}

/// Create the main router with all routes
pub fn create_router(state: AppState) -> Router {
    let cors = CorsLayer::new()
        .allow_origin(Any)
        .allow_methods(Any)
        .allow_headers(Any);

    Router::new()
        // Health and info
        .route("/health", get(health_check))
        .route("/api/dependencies", get(dependencies))
        
        // Projection API
        .route("/api/project", post(project_view))
        
        // WebSocket streaming
        .route("/ws", get(ws_handler))
        
        // Metrics
        .route("/metrics/coherence", get(coherence_metrics))
        
        // Fallback to static files
        .fallback_service(ServeDir::new(&state.static_dir).append_index_html_on_directories(true))
        
        // Middleware
        .layer(cors)
        .layer(TraceLayer::new_for_http())
        .with_state(state)
}

/// GET /health - Health check endpoint
async fn health_check(State(state): State<AppState>) -> Json<HealthResponse> {
    let deps = state.pipeline.check_dependencies().await;
    
    Json(HealthResponse {
        status: "healthy".to_string(),
        service: "dimensional-viewer".to_string(),
        version: env!("CARGO_PKG_VERSION").to_string(),
        substrate_connected: deps.substrate == "ok",
        guardian_connected: deps.franklin_guardian == "ok",
    })
}

/// GET /api/dependencies - Check dependency status
async fn dependencies(State(state): State<AppState>) -> Json<DependencyStatus> {
    Json(state.pipeline.check_dependencies().await)
}

/// POST /api/project - Generate a projected view
async fn project_view(
    State(state): State<AppState>,
    Json(request): Json<ViewRequest>,
) -> Result<Json<ViewResponse>, ApiError> {
    // Validate request
    if request.virtue_threshold < 0.0 || request.virtue_threshold > 1.0 {
        return Err(ApiError::InvalidVirtueThreshold(request.virtue_threshold));
    }
    
    for &dim in &request.dimension_map {
        if dim >= 8 {
            return Err(ApiError::InvalidDimensionIndex(dim));
        }
    }
    
    // Generate view
    let response = state.pipeline
        .generate_view(request)
        .await
        .map_err(|e| ApiError::Internal(e.to_string()))?;
    
    Ok(Json(response))
}

/// GET /metrics/coherence - Coherence metrics from recent projections
async fn coherence_metrics(State(state): State<AppState>) -> Json<CoherenceMetrics> {
    let metrics = state.pipeline.get_coherence_metrics().await;
    Json(metrics)
}

/// WebSocket upgrade handler
async fn ws_handler(
    ws: WebSocketUpgrade,
    State(state): State<AppState>,
) -> Response {
    ws.on_upgrade(|socket| handle_websocket(socket, state))
}

/// Handle an individual WebSocket connection
async fn handle_websocket(socket: WebSocket, state: AppState) {
    let (mut sender, mut receiver) = socket.split();
    
    info!("WebSocket client connected");
    
    // Default view request for streaming
    let default_request = ViewRequest {
        cell_id: "cell-001".to_string(),
        layer_filter: None,
        dimension_map: [0, 2, 5],
        virtue_threshold: 0.90,
        max_points: 1000,
    };
    
    // Send initial view
    if let Ok(view) = state.pipeline.generate_view(default_request.clone()).await {
        if let Ok(json) = serde_json::to_string(&view) {
            let _ = sender.send(Message::Text(json)).await;
        }
    }
    
    // Spawn task to stream updates
    let stream_state = state.clone();
    let mut stream_task = tokio::spawn(async move {
        let mut interval = tokio::time::interval(Duration::from_millis(100));
        
        loop {
            interval.tick().await;
            
            // Generate incremental update
            let request = ViewRequest {
                cell_id: "cell-001".to_string(),
                layer_filter: None,
                dimension_map: [0, 2, 5],
                virtue_threshold: 0.90,
                max_points: 500, // Smaller for streaming
            };
            
            match stream_state.pipeline.generate_view(request).await {
                Ok(view) => {
                    if let Ok(json) = serde_json::to_string(&view) {
                        if sender.send(Message::Text(json)).await.is_err() {
                            break;
                        }
                    }
                }
                Err(e) => {
                    error!("Stream generation error: {}", e);
                }
            }
        }
    });
    
    // Handle incoming messages
    let mut recv_task = tokio::spawn(async move {
        while let Some(Ok(msg)) = receiver.next().await {
            match msg {
                Message::Text(text) => {
                    debug!("Received: {}", text);
                    // Could handle view configuration updates here
                }
                Message::Close(_) => {
                    info!("WebSocket client disconnected");
                    break;
                }
                _ => {}
            }
        }
    });
    
    // Wait for either task to complete
    tokio::select! {
        _ = &mut stream_task => recv_task.abort(),
        _ = &mut recv_task => stream_task.abort(),
    }
}

/// API error types
#[derive(Debug)]
pub enum ApiError {
    InvalidVirtueThreshold(f32),
    InvalidDimensionIndex(usize),
    Internal(String),
}

impl IntoResponse for ApiError {
    fn into_response(self) -> Response {
        let (status, error, code) = match self {
            ApiError::InvalidVirtueThreshold(v) => (
                StatusCode::BAD_REQUEST,
                format!("Virtue threshold must be 0.0-1.0, got {}", v),
                "INVALID_VIRTUE_THRESHOLD",
            ),
            ApiError::InvalidDimensionIndex(i) => (
                StatusCode::BAD_REQUEST,
                format!("Dimension index must be < 8, got {}", i),
                "INVALID_DIMENSION_INDEX",
            ),
            ApiError::Internal(msg) => (
                StatusCode::INTERNAL_SERVER_ERROR,
                msg,
                "INTERNAL_ERROR",
            ),
        };
        
        let body = Json(ErrorResponse {
            error,
            code: code.to_string(),
        });
        
        (status, body).into_response()
    }
}
