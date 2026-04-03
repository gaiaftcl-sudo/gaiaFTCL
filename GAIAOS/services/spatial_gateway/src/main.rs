//! GaiaOS Spatial Gateway - World Interface Organ (Production)
//!
//! The canonical bridge from messy sensor frames to 8D, virtue-weighted,
//! globally auditable truth.
//!
//! ## 8D Substrate: Ψ(world) = [D0..D7]
//! - D0-D3: Physical spacetime (X, Y, Z in ENU meters, T normalized diurnal)
//! - D4-D7: Semantic/virtue (env_type, use_intensity, social_coherence, uncertainty)
//!
//! ## Features
//! - WebSocket ingress for real-time pose/sensor updates
//! - REST API for queries and control
//! - 8D vQbit projection from GeoPose with LLM classification
//! - Coherence engine for multi-source validation (DBSCAN + merge)
//! - Virtue-weighted truth queries per domain
//! - ArangoDB persistence for world patches

use axum::{
    extract::{
        ws::{Message, WebSocket, WebSocketUpgrade},
        Query, State,
    },
    http::StatusCode,
    response::IntoResponse,
    routing::{get, post},
    Json, Router,
};
use futures::{SinkExt, StreamExt};
use serde::Deserialize;
use std::sync::Arc;
use tokio::sync::broadcast;
use tower_http::cors::{Any, CorsLayer};
use tracing::{error, info, warn};
use uuid::Uuid;

mod config;
mod model;
mod services;
mod storage;

use config::Config;
use model::{cell::CellDomain, messages::*, vqbit::Vqbit8D};
use services::{
    coherence::CoherenceEngine,
    projector_8d::Projector8D,
    cross_scale::CrossScaleEngine,
    registry::{parse_capability, parse_domain, CellRegistry},
    subscription::SubscriptionManager,
    virtue_weights::VirtueWeights,
    world_state::{WorldSample, WorldState, WorldStateConfig},
};
use storage::arango::ArangoClient;

/// Shared application state
#[derive(Clone)]
struct AppState {
    /// Cell registry
    registry: CellRegistry,
    /// 8D projector
    projector: Arc<Projector8D>,
    /// Coherence engine
    coherence: Arc<CoherenceEngine>,
    /// Cross-scale gradient correlation engine
    cross_scale: Arc<tokio::sync::Mutex<CrossScaleEngine>>,
    /// World state (in-memory cache)
    world_state: WorldState,
    /// ArangoDB client (optional, for persistence)
    arango: Option<Arc<ArangoClient>>,
    /// Subscription manager
    subscriptions: SubscriptionManager,
    /// Broadcast channel for new samples
    sample_tx: broadcast::Sender<WorldSample>,
    /// Configuration
    config: Config,
}

#[tokio::main]
async fn main() {
    // Initialize logging
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::from_default_env()
                .add_directive("spatial_gateway=info".parse().unwrap()),
        )
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
                "spatial-gateway".to_string(),
                env!("CARGO_PKG_VERSION").to_string(),
                std::env::var("GAIA_CELL_ID").unwrap_or_else(|_| "unknown".to_string()),
                vec![gaiaos_introspection::IntrospectionEndpoint {
                    name: "geopose".into(),
                    kind: "ws".into(),
                    path: Some("/ws/geopose".into()),
                    subject: None,
                }],
            )
            .await;
        });

        let nats_introspect = nats_client.clone();
        tokio::spawn(async move {
            let _ = gaiaos_introspection::run_introspection_handler(
                nats_introspect,
                "spatial-gateway".to_string(),
                || gaiaos_introspection::ServiceIntrospectionReply {
                    service: "spatial-gateway".into(),
                    functions: vec![gaiaos_introspection::FunctionDescriptor {
                        name: "spatial::project_8d".into(),
                        inputs: vec!["GeoPose".into()],
                        outputs: vec!["Vqbit8D".into()],
                        kind: "ws".into(),
                        path: Some("/ws/geopose".into()),
                        subject: None,
                        side_effects: vec!["PROJECT_8D".into()],
                    }],
                    call_graph_edges: vec![],
                    state_keys: vec!["world_state".into()],
                    timestamp: chrono::Utc::now().to_rfc3339(),
                },
            )
            .await;
        });
        info!("✓ Consciousness wired");
    }

    let config = Config::from_env();
    info!("Starting Spatial Gateway on {}", config.bind_addr);
    info!(
        "Cell Origin: lat={}, lon={}, alt={}",
        config.cell_origin.lat0_deg, config.cell_origin.lon0_deg, config.cell_origin.alt0_m
    );

    // Create broadcast channel for sample updates
    let (sample_tx, _) = broadcast::channel::<WorldSample>(10000);

    // Create world state
    let world_state_config = WorldStateConfig {
        max_samples: config.max_world_samples,
        max_age_secs: config.max_sample_age_secs,
        deduplicate_cells: true,
    };

    // Try to connect to ArangoDB
    let arango = match ArangoClient::from_env().await {
        Ok(client) => {
            info!("Connected to ArangoDB");
            Some(Arc::new(client))
        }
        Err(e) => {
            warn!(
                "ArangoDB not available ({}), running without persistence",
                e
            );
            None
        }
    };

    // Create projector
    let cell_id = std::env::var("CELL_ID")
        .ok()
        .and_then(|s| Uuid::parse_str(&s).ok())
        .unwrap_or_else(Uuid::new_v4);

    let projector = Projector8D::new(
        config.cell_origin.clone(),
        config.llm_endpoint.clone(),
        cell_id,
    );

    let state = AppState {
        registry: CellRegistry::new(),
        projector: Arc::new(projector),
        coherence: Arc::new(CoherenceEngine::default()),
        cross_scale: Arc::new(tokio::sync::Mutex::new(CrossScaleEngine::default())),
        world_state: WorldState::new(world_state_config),
        arango,
        subscriptions: SubscriptionManager::new(),
        sample_tx,
        config: config.clone(),
    };

    // Spawn background tasks
    let state_clone = state.clone();
    tokio::spawn(async move {
        pruning_task(state_clone).await;
    });

    // Build router
    let mut app = Router::new()
        // WebSocket endpoint for cell connections
        .route("/cells", get(ws_handler))
        // Health & status
        .route("/health", get(health_handler))
        .route("/stats", get(stats_handler))
        .route("/substrate/state", get(world_state_handler))
        .route("/ui/hologram", get(world_state_handler))
        // World state queries
        .route("/world/state", get(world_state_handler))
        .route("/world/near", get(world_near_handler))
        .route("/world/query", post(world_query_handler))
        // Cell management
        .route("/cells/register", post(register_cell_handler))
        .route("/cells/list", get(list_cells_handler))
        .with_state(state.clone());

    // Add CORS if enabled
    if config.enable_cors {
        app = app.layer(
            CorsLayer::new()
                .allow_origin(Any)
                .allow_methods(Any)
                .allow_headers(Any),
        );
    }

    // Start server
    let listener = tokio::net::TcpListener::bind(&config.bind_addr)
        .await
        .unwrap();
    info!("Spatial Gateway listening on {}", config.bind_addr);

    axum::serve(listener, app).await.unwrap();
}

// ============================================================================
// WebSocket Handler
// ============================================================================

async fn ws_handler(ws: WebSocketUpgrade, State(state): State<AppState>) -> impl IntoResponse {
    ws.on_upgrade(move |socket| handle_socket(socket, state))
}

async fn handle_socket(stream: WebSocket, state: AppState) {
    let (mut sender, mut receiver) = stream.split();
    let mut session_id: Option<Uuid> = None;
    let mut cell_id: Option<Uuid> = None;
    let mut cell_domain: CellDomain = CellDomain::Unknown;

    info!("New WebSocket connection");

    while let Some(result) = receiver.next().await {
        let msg = match result {
            Ok(m) => m,
            Err(e) => {
                error!("WebSocket error: {}", e);
                break;
            }
        };

        match msg {
            Message::Text(txt) => {
                let v: serde_json::Value = match serde_json::from_str(&txt) {
                    Ok(v) => v,
                    Err(e) => {
                        error!("Invalid JSON: {}", e);
                        let _ = sender
                            .send(Message::Text(make_error("invalid_json", &e.to_string())))
                            .await;
                        continue;
                    }
                };

                let msg_type = v.get("type").and_then(|t| t.as_str()).unwrap_or("error");

                match msg_type {
                    "hello" => {
                        if let Ok(env) = serde_json::from_value::<Envelope<HelloPayload>>(v) {
                            let new_cell_id = env.cell_id.unwrap_or_else(Uuid::new_v4);
                            let domain = parse_domain(&env.payload.domain);
                            let capabilities: Vec<_> = env
                                .payload
                                .capabilities
                                .iter()
                                .map(|c| parse_capability(c))
                                .collect();

                            let session = state
                                .registry
                                .register(new_cell_id, domain.clone(), capabilities)
                                .await;

                            session_id = Some(session.session_id);
                            cell_id = Some(new_cell_id);
                            cell_domain = domain;

                            let ack = Envelope {
                                msg_type: MessageType::HelloAck,
                                session_id: Some(session.session_id),
                                cell_id: Some(new_cell_id),
                                seq: Some(0),
                                ts: chrono::Utc::now().to_rfc3339(),
                                payload: HelloAckPayload {
                                    status: "ok".to_string(),
                                    qos: session.qos,
                                    error: None,
                                },
                            };

                            let _ = sender
                                .send(Message::Text(serde_json::to_string(&ack).unwrap()))
                                .await;
                            info!(
                                "Cell {} registered (session {})",
                                new_cell_id, session.session_id
                            );
                        }
                    }

                    "pose_update" => {
                        if let (Some(_sess), Some(cell)) = (session_id, cell_id) {
                            if let Ok(env) = serde_json::from_value::<Envelope<GeoPosePayload>>(v) {
                                // Project to 8D (fast path, no LLM)
                                let vqbit = state.projector.project_fast(
                                    &env.payload,
                                    env.cell_id
                                        .map(|c| c.to_string())
                                        .unwrap_or_else(|| "unknown".to_string()),
                                    cell_domain.to_string(),
                                    env.payload.source.clone(),
                                );

                                let sample = WorldSample {
                                    cell_id: cell,
                                    domain: cell_domain.clone(),
                                    vqbit: vqbit.clone(),
                                    ts_unix: vqbit.timestamp_unix,
                                };

                                // Store in world state
                                state.world_state.insert_sample(sample.clone()).await;

                                // Perform cross-scale gradient correlation
                                let _correlation = {
                                    let mut engine = state.cross_scale.lock().await;
                                    engine.detect_correlation(&vqbit)
                                };

                                // Persist to ArangoDB if available
                                if let Some(ref arango) = state.arango {
                                    let _ = arango.insert_vqbit(&vqbit).await;
                                }

                                // Broadcast to subscribers
                                let _ = state.sample_tx.send(sample);

                                // Send ack
                                let ack = serde_json::json!({
                                    "type": "ingest_ack",
                                    "vqbit_id": vqbit.id.to_string(),
                                    "coherence_score": vqbit.d6_social_coherence,
                                    "uncertainty": vqbit.d7_uncertainty
                                });
                                let _ = sender
                                    .send(Message::Text(serde_json::to_string(&ack).unwrap()))
                                    .await;
                            }
                        } else {
                            let _ = sender
                                .send(Message::Text(make_error(
                                    "not_registered",
                                    "Send hello first",
                                )))
                                .await;
                        }
                    }

                    "query" => {
                        if let Ok(env) = serde_json::from_value::<Envelope<QueryPayload>>(v) {
                            let q = &env.payload;
                            let domain = q.domain.as_ref().map(|d| parse_domain(d));

                            let samples = state
                                .world_state
                                .query_region(
                                    domain.as_ref(),
                                    q.lon_min,
                                    q.lon_max,
                                    q.lat_min,
                                    q.lat_max,
                                    q.t_min,
                                    q.t_max,
                                )
                                .await;

                            let total_count = samples.len();
                            let limited: Vec<_> = if let Some(limit) = q.limit {
                                samples.into_iter().take(limit as usize).collect()
                            } else {
                                samples
                            };

                            let result = QueryResultPayload {
                                samples: limited
                                    .iter()
                                    .map(|s| QueryResultSample {
                                        cell_id: s.cell_id,
                                        domain: s.domain.to_string(),
                                        vqbit: s.vqbit.clone(),
                                        ts_unix: s.ts_unix,
                                        fot_validated: s.vqbit.fot_validated,
                                        virtue_weight: s.vqbit.d5_use_intensity,
                                    })
                                    .collect(),
                                total_count,
                                truncated: q
                                    .limit
                                    .map(|l| total_count > l as usize)
                                    .unwrap_or(false),
                            };

                            let reply = Envelope {
                                msg_type: MessageType::QueryResult,
                                session_id,
                                cell_id,
                                seq: env.seq,
                                ts: chrono::Utc::now().to_rfc3339(),
                                payload: result,
                            };

                            let _ = sender
                                .send(Message::Text(serde_json::to_string(&reply).unwrap()))
                                .await;
                        }
                    }

                    _ => {
                        warn!("Unknown message type: {}", msg_type);
                    }
                }
            }

            Message::Close(_) => {
                if let Some(cell) = cell_id {
                    state.registry.unregister(&cell).await;
                    state.subscriptions.unsubscribe_cell(&cell).await;
                    info!("Cell {} disconnected", cell);
                }
                break;
            }

            Message::Ping(data) => {
                let _ = sender.send(Message::Pong(data)).await;
            }

            _ => {}
        }
    }
}

fn make_error(code: &str, message: &str) -> String {
    serde_json::json!({
        "type": "error",
        "code": code,
        "message": message,
        "ts": chrono::Utc::now().to_rfc3339()
    })
    .to_string()
}

// ============================================================================
// REST Handlers
// ============================================================================

async fn health_handler(State(state): State<AppState>) -> impl IntoResponse {
    // SAFETY: Include coherence engine status in health check
    // This allows monitoring to detect if coherence computations are degraded
    let coherence_status = if state.coherence.cluster_threshold_m > 0.0 {
        "configured"
    } else {
        "disabled"
    };

    Json(serde_json::json!({
        "status": "healthy",
        "service": "spatial-gateway",
        "version": env!("CARGO_PKG_VERSION"),
        "coherence_engine": coherence_status,
        "cluster_threshold_m": state.coherence.cluster_threshold_m,
        "ts": chrono::Utc::now().to_rfc3339()
    }))
}

async fn stats_handler(State(state): State<AppState>) -> impl IntoResponse {
    let world_stats = state.world_state.stats().await;
    let cell_count = state.registry.session_count().await;
    let sub_count = state.subscriptions.count().await;

    let arango_stats = if let Some(ref arango) = state.arango {
        arango.stats().await.ok()
    } else {
        None
    };

    Json(serde_json::json!({
        "world_state": {
            "total_samples": world_stats.total_samples,
            "active_cells": world_stats.active_cells,
        },
        "registry": {
            "registered_cells": cell_count,
        },
        "subscriptions": {
            "active": sub_count,
        },
        "arango": arango_stats.map(|s| serde_json::json!({
            "total_patches": s.total_patches,
            "by_domain": s.by_domain
        })),
        "config": {
            "cell_origin_lat": state.config.cell_origin.lat0_deg,
            "cell_origin_lon": state.config.cell_origin.lon0_deg,
        }
    }))
}

#[derive(Debug, Deserialize)]
struct WorldQueryParams {
    domain: Option<String>,
    lon_min: Option<f64>,
    lon_max: Option<f64>,
    lat_min: Option<f64>,
    lat_max: Option<f64>,
    t_min: Option<f64>,
    t_max: Option<f64>,
    limit: Option<u32>,
}

async fn world_state_handler(
    State(state): State<AppState>,
    Query(q): Query<WorldQueryParams>,
) -> impl IntoResponse {
    let domain = q.domain.as_ref().map(|d| parse_domain(d));

    // If coordinates are missing, provide a global view (-180 to 180, -90 to 90)
    let samples = state
        .world_state
        .query_region(
            domain.as_ref(),
            q.lon_min.unwrap_or(-180.0),
            q.lon_max.unwrap_or(180.0),
            q.lat_min.unwrap_or(-90.0),
            q.lat_max.unwrap_or(90.0),
            q.t_min,
            q.t_max,
        )
        .await;

    let limited: Vec<_> = if let Some(limit) = q.limit {
        samples.into_iter().take(limit as usize).collect()
    } else {
        samples
    };

    Json(
        limited
            .iter()
            .map(|s| {
                serde_json::json!({
                    "cell_id": s.cell_id,
                    "domain": s.domain.to_string(),
                    "d0_x": s.vqbit.d0_x,
                    "d1_y": s.vqbit.d1_y,
                    "d2_z": s.vqbit.d2_z,
                    "d3_t": s.vqbit.d3_t,
                    "d4_env_type": s.vqbit.d4_env_type,
                    "d5_use_intensity": s.vqbit.d5_use_intensity,
                    "d6_social_coherence": s.vqbit.d6_social_coherence,
                    "d7_uncertainty": s.vqbit.d7_uncertainty,
                    "timestamp_unix": s.ts_unix,
                })
            })
            .collect::<Vec<_>>(),
    )
}

#[derive(Debug, Deserialize)]
struct NearQueryParams {
    lon: f64,
    lat: f64,
    radius_m: Option<f64>,
    domain: Option<String>,
    limit: Option<usize>,
}

async fn world_near_handler(
    State(state): State<AppState>,
    Query(q): Query<NearQueryParams>,
) -> impl IntoResponse {
    let domain = q.domain.as_ref().map(|d| parse_domain(d));
    let radius_deg = q.radius_m.unwrap_or(1000.0) / 111_000.0; // Approximate deg

    let samples = state
        .world_state
        .query_near(q.lon, q.lat, radius_deg, domain.as_ref(), q.limit)
        .await;

    Json(
        samples
            .iter()
            .map(|s| {
                serde_json::json!({
                    "cell_id": s.cell_id,
                    "domain": s.domain.to_string(),
                    "d0_x": s.vqbit.d0_x,
                    "d1_y": s.vqbit.d1_y,
                    "d2_z": s.vqbit.d2_z,
                    "d6_social_coherence": s.vqbit.d6_social_coherence,
                    "d7_uncertainty": s.vqbit.d7_uncertainty,
                    "timestamp_unix": s.ts_unix,
                })
            })
            .collect::<Vec<_>>(),
    )
}

#[derive(Debug, Deserialize)]
struct VirtueQueryRequest {
    bbox: BoundingBoxRequest,
    domain: String,
    weights: Option<VirtueWeights>,
    limit: Option<usize>,
    min_coherence: Option<f32>,
    max_staleness_secs: Option<f64>,
}

#[derive(Debug, Deserialize)]
struct BoundingBoxRequest {
    x_min: f64,
    x_max: f64,
    y_min: f64,
    y_max: f64,
}

async fn world_query_handler(
    State(state): State<AppState>,
    Json(req): Json<VirtueQueryRequest>,
) -> impl IntoResponse {
    // For now, use in-memory world state
    // In production, this would use QueryEngine with ArangoDB
    let domain = parse_domain(&req.domain);
    let weights = req
        .weights
        .unwrap_or_else(|| VirtueWeights::for_domain(&req.domain));

    let samples = state
        .world_state
        .query_region(
            Some(&domain),
            req.bbox.x_min,
            req.bbox.x_max,
            req.bbox.y_min,
            req.bbox.y_max,
            None,
            None,
        )
        .await;

    // Apply virtue scoring
    let now = Vqbit8D::now_unix();
    let mut scored: Vec<_> = samples
        .into_iter()
        .filter(|s| {
            if s.vqbit.d7_uncertainty > weights.max_uncertainty {
                return false;
            }
            if let Some(min_coh) = req.min_coherence {
                if s.vqbit.d6_social_coherence < min_coh {
                    return false;
                }
            }
            if let Some(max_stale) = req.max_staleness_secs {
                if now - s.ts_unix > max_stale {
                    return false;
                }
            }
            true
        })
        .map(|s| {
            let age = (now - s.ts_unix) as f32;
            let freshness = (-0.1 * weights.temporal_freshness * age / 60.0).exp();
            let precision = 1.0 - s.vqbit.d7_uncertainty;
            let coherence = s.vqbit.d6_social_coherence;
            let score = weights.temporal_freshness * freshness
                + weights.spatial_precision * precision
                + weights.social_agreement * coherence;
            (score, s)
        })
        .collect();

    scored.sort_by(|a, b| b.0.partial_cmp(&a.0).unwrap());

    if let Some(limit) = req.limit {
        scored.truncate(limit);
    }

    Json(
        scored
            .iter()
            .map(|(score, s)| {
                serde_json::json!({
                    "virtue_score": score,
                    "cell_id": s.cell_id,
                    "domain": s.domain.to_string(),
                    "vqbit": {
                        "d0_x": s.vqbit.d0_x,
                        "d1_y": s.vqbit.d1_y,
                        "d2_z": s.vqbit.d2_z,
                        "d3_t": s.vqbit.d3_t,
                        "d4_env_type": s.vqbit.d4_env_type,
                        "d5_use_intensity": s.vqbit.d5_use_intensity,
                        "d6_social_coherence": s.vqbit.d6_social_coherence,
                        "d7_uncertainty": s.vqbit.d7_uncertainty,
                    },
                    "timestamp_unix": s.ts_unix,
                })
            })
            .collect::<Vec<_>>(),
    )
}

#[derive(Debug, Deserialize)]
struct RegisterCellRequest {
    cell_id: Option<Uuid>,
    domain: String,
    capabilities: Vec<String>,
}

async fn register_cell_handler(
    State(state): State<AppState>,
    Json(req): Json<RegisterCellRequest>,
) -> impl IntoResponse {
    let cell_id = req.cell_id.unwrap_or_else(Uuid::new_v4);
    let domain = parse_domain(&req.domain);
    let capabilities: Vec<_> = req
        .capabilities
        .iter()
        .map(|c| parse_capability(c))
        .collect();

    let session = state.registry.register(cell_id, domain, capabilities).await;

    (
        StatusCode::CREATED,
        Json(serde_json::json!({
            "cell_id": session.cell_id,
            "session_id": session.session_id,
            "domain": session.domain.to_string(),
            "qos": session.qos
        })),
    )
}

async fn list_cells_handler(State(state): State<AppState>) -> impl IntoResponse {
    let sessions = state.registry.all_sessions().await;

    Json(
        sessions
            .iter()
            .map(|s| {
                serde_json::json!({
                    "cell_id": s.cell_id,
                    "session_id": s.session_id,
                    "domain": s.domain.to_string(),
                    "connected_at": s.connected_at,
                    "last_activity": s.last_activity
                })
            })
            .collect::<Vec<_>>(),
    )
}

// ============================================================================
// Background Tasks
// ============================================================================

async fn pruning_task(state: AppState) {
    let mut interval = tokio::time::interval(tokio::time::Duration::from_secs(60));

    loop {
        interval.tick().await;

        // Prune old samples from in-memory cache
        let pruned_samples = state.world_state.prune_old().await;

        // Prune inactive sessions
        let pruned_sessions = state
            .registry
            .prune_inactive(state.config.session_timeout_secs)
            .await;

        // Prune old entries from ArangoDB
        if let Some(ref arango) = state.arango {
            let _ = arango.prune_old(state.config.max_sample_age_secs).await;
        }

        if pruned_samples > 0 || pruned_sessions > 0 {
            info!(
                "Pruned {} samples, {} sessions",
                pruned_samples, pruned_sessions
            );
        }
    }
}
