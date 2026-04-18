//! GaiaOS Dimensional Viewer
//! 
//! Quantum 8D → 3D projection service with virtue gating.
//! 
//! ## Architecture
//! 
//! ```text
//! ┌─────────────────────────────────────────────────────────────────┐
//! │                   gaiaos-dimensional-viewer                     │
//! │  ┌──────────────┐    ┌──────────────┐    ┌─────────────────┐   │
//! │  │   Substrate  │───▶│  Projection  │───▶│  Virtue Gate    │   │
//! │  │   Client     │    │   Operator   │    │  (Franklin)     │   │
//! │  └──────────────┘    └──────────────┘    └─────────────────┘   │
//! │         ▲                   │                    │             │
//! │         │                   ▼                    ▼             │
//! │  ┌──────┴──────┐    ┌──────────────┐    ┌─────────────────┐   │
//! │  │  Quantum    │    │   ViewResponse │    │  WebSocket/REST │   │
//! │  │  Substrate  │    │   + Coherence  │    │  API            │   │
//! │  │  (8D data)  │    │   Tracking     │    │  (port 8750)    │   │
//! │  └─────────────┘    └──────────────┘    └─────────────────┘   │
//! └─────────────────────────────────────────────────────────────────┘
//! ```
//! 
//! ## Key Features
//! 
//! - **Quantum-Native:** Reads 8D coordinates from substrate
//! - **Virtue-Gated:** All projections validated by Franklin Guardian
//! - **Coherence-Tracked:** Every projection reports information loss
//! - **Performance-Specified:** 10K points/sec, <100ms latency

use anyhow::Result;
use std::net::SocketAddr;
use std::sync::Arc;
use tracing::{info, Level};
use tracing_subscriber::FmtSubscriber;

mod api;
mod clients;
mod models;
mod pipeline;
mod quantum_projection;

use api::AppState;
use clients::{FranklinClient, SubstrateClient};
use pipeline::ViewerPipeline;

#[tokio::main]
async fn main() -> Result<()> {
    // Initialize logging
    FmtSubscriber::builder()
        .with_max_level(Level::INFO)
        .with_target(true)
        .init();

    // Load environment
    dotenvy::dotenv().ok();

    info!("Starting GaiaOS Dimensional Viewer");

    // Parse configuration from environment
    let port: u16 = std::env::var("DIMENSIONAL_VIEWER_PORT")
        .unwrap_or_else(|_| "8750".into())
        .parse()
        .expect("Invalid DIMENSIONAL_VIEWER_PORT");

    let substrate_url = std::env::var("SUBSTRATE_URL")
        .unwrap_or_else(|_| "http://gaiaos-substrate:8000".into());

    let guardian_url = std::env::var("FRANKLIN_GUARDIAN_URL")
        .unwrap_or_else(|_| "http://gaiaos-franklin-guardian:8803".into());

    let default_virtue_threshold: f32 = std::env::var("DEFAULT_VIRTUE_THRESHOLD")
        .unwrap_or_else(|_| "0.90".into())
        .parse()
        .expect("Invalid DEFAULT_VIRTUE_THRESHOLD");

    let static_dir = std::env::var("DIMENSIONAL_VIEWER_STATIC_DIR")
        .unwrap_or_else(|_| "/app/static".into());

    let default_dims: [usize; 3] = std::env::var("DEFAULT_DIMENSION_MAP")
        .unwrap_or_else(|_| "0,2,5".into())
        .split(',')
        .map(|s| s.trim().parse().expect("Invalid dimension"))
        .collect::<Vec<_>>()
        .try_into()
        .expect("Need exactly 3 dimensions");

    info!("Configuration:");
    info!("  Port: {}", port);
    info!("  Substrate URL: {}", substrate_url);
    info!("  Franklin Guardian URL: {}", guardian_url);
    info!("  Default Virtue Threshold: {}", default_virtue_threshold);
    info!("  Default Dimension Map: {:?}", default_dims);
    info!("  Static Dir: {}", static_dir);

    // Connect to external services
    let substrate_client = SubstrateClient::connect(substrate_url).await?;
    let guardian_client = FranklinClient::connect(guardian_url).await?;

    // Create pipeline
    let pipeline = Arc::new(ViewerPipeline::new(
        substrate_client,
        guardian_client,
        default_dims,
        default_virtue_threshold,
    ));

    // Check dependencies
    let deps = pipeline.check_dependencies().await;
    info!("Dependency status: substrate={}, guardian={}", deps.substrate, deps.franklin_guardian);

    // Create application state
    let state = AppState {
        pipeline,
        static_dir,
    };

    // Build router
    let app = api::create_router(state);

    // Start server
    let addr = SocketAddr::from(([0, 0, 0, 0], port));
    info!("Dimensional Viewer listening on http://{}", addr);

    let listener = tokio::net::TcpListener::bind(addr).await?;
    axum::serve(listener, app).await?;

    Ok(())
}
