//! GAIA-1 Virtual Chip Service
//!
//! HTTP + NATS server exposing the vQbit quantum substrate.
//! All cognitive services (brain, agent, virtue) call this service
//! to evolve their quantum states.
//!
//! ## Endpoints
//!
//! - POST /evolve - Evolve quantum state with input
//! - POST /bell - Create Bell state
//! - POST /grover - Grover search
//! - GET /health - Service health
//! - GET /coherence - Current coherence level
//! - GET /stats - Execution statistics
//!
//! ## NATS Topics
//!
//! - vchip.evolve.<cell_id> - Request state evolution
//! - vchip.collapsed.<cell_id> - Collapsed state notifications

use anyhow::Result;
use axum::{
    extract::State,
    http::StatusCode,
    routing::{get, post},
    Json, Router,
};
use futures_util::StreamExt;
use gaia1_virtual_chip::{
    coherence_test_program, uum8d_to_program, ChipProfile, Gaia1Config, Gaia1VirtualChip,
    VqAlgorithms, VqProgram,
};
use serde::Deserialize;
use std::sync::Arc;
use tokio::sync::RwLock;
use tower_http::cors::{Any, CorsLayer};
use tracing::{error, info, warn};
use vchip_client::{EvolveRequest, EvolveResponse, QState8D, VChipHealth};

mod substrate_client;
mod unified_evolution;

use substrate_client::SubstrateClient;
use unified_evolution::{handle_unified_evolve, UnifiedState};

/// Application state
struct AppState {
    /// The virtual chip instance
    chip: RwLock<Gaia1VirtualChip>,
    /// NATS client (optional)
    nats: Option<async_nats::Client>,
    /// Cell ID for NATS topics
    cell_id: String,
    /// Configured max vQbits (from MAX_QUBITS env)
    max_qubits: usize,
}

#[tokio::main]
async fn main() -> Result<()> {
    // Initialize tracing
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::from_default_env()
                .add_directive("gaia1_virtual_chip_service=info".parse()?)
                .add_directive("gaia1_virtual_chip=debug".parse()?),
        )
        .json()
        .init();

    info!("╔════════════════════════════════════════════════════════════╗");
    info!("║        GAIA-1 VIRTUAL CHIP SERVICE v0.1.0                  ║");
    info!("║        Quantum Substrate for GaiaOS Consciousness          ║");
    info!("╚════════════════════════════════════════════════════════════╝");

    // Configuration from environment
    let http_port: u16 = std::env::var("VCHIP_PORT")
        .or_else(|_| std::env::var("HTTP_PORT"))
        .unwrap_or_else(|_| "8001".to_string())
        .parse()?;

    let nats_url = std::env::var("NATS_URL").ok();
    let cell_id = std::env::var("CELL_ID").unwrap_or_else(|_| "cell-01".to_string());

    let max_qubits: usize = std::env::var("MAX_QUBITS")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(2048);

    // Create chip with configuration
    let config = Gaia1Config {
        max_qubits,
        cycles_per_collapse: 64,
        parallel: true,
        coherence_threshold: 0.5,
    };

    let mut chip = Gaia1VirtualChip::with_config(config);

    info!("Backend: {:?}", chip.backend());
    info!("Max vQbits: {}", max_qubits);

    // Run initial coherence test
    info!("Running initial coherence test...");
    let test_prog = coherence_test_program(8);
    match chip.run_program(&test_prog).await {
        Ok(result) => {
            info!("Initial coherence: {:.4}", result.coherence);
        }
        Err(e) => {
            warn!("Coherence test failed: {}", e);
        }
    }

    // Connect to NATS if configured
    let nats = if let Some(url) = nats_url {
        match async_nats::connect(&url).await {
            Ok(client) => {
                info!("Connected to NATS at {}", url);
                Some(client)
            }
            Err(e) => {
                warn!("Failed to connect to NATS: {}. Running without NATS.", e);
                None
            }
        }
    } else {
        info!("No NATS_URL configured. Running HTTP-only mode.");
        None
    };

    // Create shared state
    let state = Arc::new(AppState {
        chip: RwLock::new(chip),
        nats: nats.clone(),
        cell_id: cell_id.clone(),
        max_qubits,
    });

    // Create unified state with substrate client (for consciousness test suite)
    let akg_url = std::env::var("AKG_URL").ok();
    let substrate = akg_url.as_ref().map(|url| {
        info!("Connecting to AKG GNN substrate at: {}", url);
        Arc::new(SubstrateClient::new(url))
    });

    let unified_chip = Gaia1VirtualChip::with_config(Gaia1Config {
        max_qubits,
        cycles_per_collapse: 64,
        parallel: true,
        coherence_threshold: 0.5,
    });

    let unified_state = Arc::new(UnifiedState {
        chip: RwLock::new(unified_chip),
        substrate,
        max_qubits,
    });

    // Start NATS subscriber if connected
    if let Some(nats_client) = nats {
        let nats_state = state.clone();
        let topic = format!("vchip.evolve.{cell_id}");
        tokio::spawn(async move {
            if let Err(e) = handle_nats_requests(nats_client, nats_state, &topic).await {
                error!("NATS handler error: {}", e);
            }
        });
    }

    // Build HTTP router
    let cors = CorsLayer::new()
        .allow_origin(Any)
        .allow_methods(Any)
        .allow_headers(Any);

    // Main router with legacy state
    let main_router = Router::new()
        // Core operations
        .route("/evolve", post(handle_evolve))
        .route("/bell", post(handle_bell))
        .route("/grover", post(handle_grover))
        .route("/collapse", post(handle_collapse))
        // Status endpoints
        .route("/health", get(handle_health))
        .route("/coherence", get(handle_coherence))
        .route("/stats", get(handle_stats))
        .route("/profile", get(handle_profile))
        .with_state(state);

    // Unified evolution router (for consciousness test suite)
    let unified_router = Router::new()
        .route("/evolve/unified", post(handle_unified_evolve))
        .with_state(unified_state);

    let app = main_router.merge(unified_router).layer(cors);

    // Start HTTP server
    let listener = tokio::net::TcpListener::bind(format!("0.0.0.0:{http_port}")).await?;
    info!("vChip HTTP server listening on port {}", http_port);

    axum::serve(listener, app).await?;

    Ok(())
}

// ===== HTTP Handlers =====

/// Health check endpoint
async fn handle_health(State(state): State<Arc<AppState>>) -> Json<VChipHealth> {
    let chip = state.chip.read().await;
    let stats = chip.stats();

    Json(VChipHealth {
        status: "healthy".to_string(),
        backend: format!("{:?}", chip.backend()),
        max_qubits: state.max_qubits, // Use configured max, not hardware-detected
        total_ops: stats.total_ops,
        total_collapses: stats.total_collapses,
        avg_coherence: stats.avg_coherence,
    })
}

/// Main evolve endpoint - all cognition flows through here
async fn handle_evolve(
    State(state): State<Arc<AppState>>,
    Json(request): Json<EvolveRequest>,
) -> Result<Json<EvolveResponse>, (StatusCode, String)> {
    let mut chip = state.chip.write().await;

    // Convert input QState8D to vQbit program
    let program = create_evolve_program(
        &request.qstate,
        &request.input,
        request.algorithm.as_deref(),
    );

    // Execute program
    match chip.run_program(&program).await {
        Ok(result) => {
            // Convert result to EvolveResponse
            let new_state = result
                .attractor
                .map(|a| QState8D::from_uum8d(&a))
                .unwrap_or_else(QState8D::origin);

            // Publish to NATS if connected
            if let Some(nats) = &state.nats {
                let topic = format!("vchip.collapsed.{}", state.cell_id);
                let _ = nats
                    .publish(
                        topic,
                        serde_json::to_vec(&new_state).unwrap_or_default().into(),
                    )
                    .await;
            }

            Ok(Json(EvolveResponse {
                new_state,
                virtue_delta: result.virtue_delta,
                coherence: result.coherence,
                cycles: result.cycles,
                measurements: result.measurements,
            }))
        }
        Err(e) => {
            error!("Evolve failed: {}", e);
            Err((StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))
        }
    }
}

/// Create Bell state
async fn handle_bell(
    State(state): State<Arc<AppState>>,
) -> Result<Json<EvolveResponse>, (StatusCode, String)> {
    let mut chip = state.chip.write().await;
    let program = VqAlgorithms::bell_state();

    match chip.run_program(&program).await {
        Ok(result) => {
            let new_state = result
                .attractor
                .map(|a| QState8D::from_uum8d(&a))
                .unwrap_or_else(QState8D::origin);

            Ok(Json(EvolveResponse {
                new_state,
                virtue_delta: result.virtue_delta,
                coherence: result.coherence,
                cycles: result.cycles,
                measurements: result.measurements,
            }))
        }
        Err(e) => Err((StatusCode::INTERNAL_SERVER_ERROR, e.to_string())),
    }
}

/// Grover search request
#[derive(Debug, Deserialize)]
#[allow(dead_code)]
struct GroverRequest {
    /// QState for initial superposition
    qstate: QState8D,
    /// Target state to search for
    target: String,
    iterations: Option<usize>,
}

/// Grover search
async fn handle_grover(
    State(state): State<Arc<AppState>>,
    Json(request): Json<GroverRequest>,
) -> Result<Json<EvolveResponse>, (StatusCode, String)> {
    let mut chip = state.chip.write().await;

    // Create Grover search program from the input state
    let n = 8; // 8 qubits for 8D search
    let iterations = request.iterations.unwrap_or(3);

    // Build a program that applies Grover iterations
    let mut program = VqProgram::new("Grover Search");
    program.init(n);

    // Create uniform superposition
    for i in 0..n {
        program.h(i);
    }

    // Apply Grover iterations
    for _ in 0..iterations {
        // Oracle would mark the target - for now just apply diffusion
        program.grover_diffuse();
    }

    // Measure
    program.measure_all(n);

    match chip.run_program(&program).await {
        Ok(result) => {
            let new_state = result
                .attractor
                .map(|a| QState8D::from_uum8d(&a))
                .unwrap_or_else(QState8D::origin);

            Ok(Json(EvolveResponse {
                new_state,
                virtue_delta: result.virtue_delta,
                coherence: result.coherence,
                cycles: result.cycles,
                measurements: result.measurements,
            }))
        }
        Err(e) => Err((StatusCode::INTERNAL_SERVER_ERROR, e.to_string())),
    }
}

/// Collapse request (force measurement)
#[derive(Debug, Deserialize)]
struct CollapseRequest {
    qstate: QState8D,
}

async fn handle_collapse(
    State(state): State<Arc<AppState>>,
    Json(request): Json<CollapseRequest>,
) -> Result<Json<EvolveResponse>, (StatusCode, String)> {
    let mut chip = state.chip.write().await;

    // Initialize with state and measure
    let uum8d = request.qstate.to_uum8d();
    let program = uum8d_to_program(&uum8d);

    match chip.run_program(&program).await {
        Ok(result) => {
            let new_state = result
                .attractor
                .map(|a| QState8D::from_uum8d(&a))
                .unwrap_or_else(QState8D::origin);

            Ok(Json(EvolveResponse {
                new_state,
                virtue_delta: result.virtue_delta,
                coherence: result.coherence,
                cycles: result.cycles,
                measurements: result.measurements,
            }))
        }
        Err(e) => Err((StatusCode::INTERNAL_SERVER_ERROR, e.to_string())),
    }
}

/// Get current coherence
async fn handle_coherence(State(state): State<Arc<AppState>>) -> Json<serde_json::Value> {
    let chip = state.chip.read().await;
    let stats = chip.stats();

    Json(serde_json::json!({
        "coherence": stats.avg_coherence,
        "total_collapses": stats.total_collapses,
    }))
}

/// Get statistics
async fn handle_stats(State(state): State<Arc<AppState>>) -> Json<serde_json::Value> {
    let chip = state.chip.read().await;
    let stats = chip.stats();

    Json(serde_json::json!({
        "total_ops": stats.total_ops,
        "total_collapses": stats.total_collapses,
        "total_cycles": stats.total_cycles,
        "avg_coherence": stats.avg_coherence,
    }))
}

/// Get chip profile
async fn handle_profile(State(state): State<Arc<AppState>>) -> Json<serde_json::Value> {
    let chip = state.chip.read().await;
    let chip_profile = ChipProfile::from_device(chip.profile());

    Json(serde_json::json!({
        "backend": chip_profile.backend,
        "max_qubits": chip_profile.max_qubits,
        "fp16": chip_profile.fp16,
        "bf16": chip_profile.bf16,
        "tensor_cores": chip_profile.tensor_cores,
        "gpu_memory_mb": chip_profile.gpu_memory_mb,
    }))
}

// ===== Helper Functions =====

/// Create a vQbit program from QState8D and input
fn create_evolve_program(qstate: &QState8D, input: &str, algorithm: Option<&str>) -> VqProgram {
    // Convert QState8D to Uum8dCoord
    let uum8d = qstate.to_uum8d();

    // Use the uum8d_to_program function from the vChip crate
    // Note: input is encoded in the qstate transformation
    let _ = input; // Input processing can be extended later
    let _ = algorithm; // Algorithm selection for future use
    uum8d_to_program(&uum8d)
}

// ===== NATS Handler =====

async fn handle_nats_requests(
    nats: async_nats::Client,
    state: Arc<AppState>,
    topic: &str,
) -> Result<()> {
    let mut sub = nats.subscribe(topic.to_string()).await?;
    info!("Subscribed to NATS topic: {}", topic);

    while let Some(msg) = sub.next().await {
        let state = state.clone();
        let nats = nats.clone();

        tokio::spawn(async move {
            // Parse request
            let request: EvolveRequest = match serde_json::from_slice(&msg.payload) {
                Ok(r) => r,
                Err(e) => {
                    warn!("Invalid NATS request: {}", e);
                    return;
                }
            };

            // Process
            let mut chip = state.chip.write().await;
            let program = create_evolve_program(
                &request.qstate,
                &request.input,
                request.algorithm.as_deref(),
            );

            match chip.run_program(&program).await {
                Ok(result) => {
                    let response = EvolveResponse {
                        new_state: result
                            .attractor
                            .map(|a| QState8D::from_uum8d(&a))
                            .unwrap_or_else(QState8D::origin),
                        virtue_delta: result.virtue_delta,
                        coherence: result.coherence,
                        cycles: result.cycles,
                        measurements: result.measurements,
                    };

                    // Reply if requested
                    if let Some(reply) = msg.reply {
                        let _ = nats
                            .publish(
                                reply,
                                serde_json::to_vec(&response).unwrap_or_default().into(),
                            )
                            .await;
                    }
                }
                Err(e) => {
                    error!("NATS evolve failed: {}", e);
                }
            }
        });
    }

    Ok(())
}
