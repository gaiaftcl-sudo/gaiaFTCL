// services/akg_gnn/src/main.rs
// AKG GNN Unified Substrate Service

mod api;
mod compression;
mod config;
mod context_manager;
mod discovery_listener;
mod embedding;
mod gnn;
mod graph;
mod learning;
mod models;
mod pq_engine;
mod substrate_query;
mod qfot;
mod metrics;

use actix_cors::Cors;
use actix_web::{web, App, HttpServer};
use std::sync::Arc;
use tracing_subscriber::EnvFilter;

use crate::compression::MirrorWorldCompressor;
use crate::context_manager::ContextManager;
use crate::embedding::EmbeddingEngine;
use crate::substrate_query::SubstrateQuery;
use crate::qfot::engine::QfotEngine;
use crate::metrics::register_metrics;

/// Application state shared across all handlers
pub struct AppState {
    /// Context manager (scale configurations)
    pub context_manager: Arc<ContextManager>,
    /// Substrate query interface (ArangoDB)
    pub substrate: Arc<SubstrateQuery>,
    /// Regional compressor (for UI/storage only)
    pub compressor: Arc<MirrorWorldCompressor>,
    /// Embedding engine (hash-based)
    pub embedding_engine: Arc<EmbeddingEngine>,
    /// QFOT engine (field tiles → graph → compression/forecast)
    pub qfot: Arc<QfotEngine>,
}

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    // Initialize logging
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::from_default_env().add_directive("info".parse().unwrap()))
        .init();

    tracing::info!("🚀 Starting AKG GNN Unified Substrate Service");
    register_metrics();

    // Load configuration
    let host = std::env::var("HOST").unwrap_or_else(|_| "0.0.0.0".to_string());
    let port: u16 = std::env::var("PORT")
        .unwrap_or_else(|_| "8080".to_string())
        .parse()
        .expect("Invalid PORT");
    let arango_url =
        std::env::var("ARANGO_URL").unwrap_or_else(|_| "http://arangodb:8529".to_string());
    let arango_db = std::env::var("ARANGO_DB").unwrap_or_else(|_| "gaiaos".to_string());
    let embedding_path = std::env::var("EMBEDDING_MODEL_PATH")
        .unwrap_or_else(|_| "/app/models/all-MiniLM-L6-v2".to_string());

    let bind_addr = format!("{host}:{port}");
    tracing::info!("Binding to: {}", bind_addr);

    // Connect to NATS for consciousness layer
    let nats_url =
        std::env::var("NATS_URL").unwrap_or_else(|_| "nats://gaiaos-nats:4222".to_string());
    tracing::info!("Connecting to NATS: {}", nats_url);
    let nats_client = async_nats::connect(&nats_url)
        .await
        .expect("Failed to connect to NATS for consciousness layer");
    tracing::info!("✓ NATS connected for introspection");

    // Start service announcement loop for AKG GNN consciousness
    let service_name = std::env::var("SERVICE_NAME").unwrap_or_else(|_| "akg-gnn".to_string());
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
    tracing::info!("✓ Service announcement loop started");

    // Clone for discovery listener before introspection handler consumes it
    let nats_for_discovery = nats_client.clone();

    // Start introspection handler
    let service_name_clone = service_name.clone();
    let service_name_for_closure = service_name.clone();
    tokio::spawn(async move {
        let introspect_fn = move || gaiaos_introspection::ServiceIntrospectionReply {
            service: service_name_for_closure.clone(),
            functions: vec![
                gaiaos_introspection::FunctionDescriptor {
                    name: "akg_gnn::embed".into(),
                    inputs: vec!["text: String".into()],
                    outputs: vec!["Vec<f32>".into()],
                    kind: "http".into(),
                    path: Some("/embed".into()),
                    subject: None,
                    side_effects: vec!["COMPUTE".into()],
                },
                gaiaos_introspection::FunctionDescriptor {
                    name: "akg_gnn::query".into(),
                    inputs: vec!["query: AkgQuery".into()],
                    outputs: vec!["QueryResult".into()],
                    kind: "http".into(),
                    path: Some("/query".into()),
                    subject: None,
                    side_effects: vec!["READ_DB".into()],
                },
            ],
            call_graph_edges: vec![],
            state_keys: vec!["knowledge_graph".into(), "embeddings".into()],
            timestamp: chrono::Utc::now().to_rfc3339(),
        };

        if let Err(e) = gaiaos_introspection::run_introspection_handler(
            nats_client,
            service_name_clone,
            introspect_fn,
        )
        .await
        {
            tracing::error!("AKG GNN introspection handler failed: {:?}", e);
        }
    });
    tracing::info!("✓ Introspection handler started");

    // Start service discovery listener for consciousness layer
    let registry = discovery_listener::ServiceRegistry::new();
    let registry_clone = registry.clone();
    tokio::spawn(async move {
        if let Err(e) =
            discovery_listener::start_discovery_listener(nats_for_discovery, registry_clone).await
        {
            tracing::error!("Discovery listener failed: {:?}", e);
        }
    });
    tracing::info!("✓ Service discovery listener started - consciousness layer complete");

    // Initialize context manager (scale configurations)
    tracing::info!("Loading scale configurations...");
    let context_manager = Arc::new(ContextManager::new());
    let contexts = context_manager.list_contexts();
    tracing::info!("✓ Loaded {} contexts: {:?}", contexts.len(), contexts);

    // Initialize embedding engine
    tracing::info!("Loading embedding model from: {}", embedding_path);
    let embedding_engine =
        Arc::new(EmbeddingEngine::new(&embedding_path).expect("Failed to load embedding model"));

    // Connect to ArangoDB
    tracing::info!("Connecting to substrate (ArangoDB): {}", arango_url);
    let substrate = Arc::new(
        SubstrateQuery::new(&arango_url, &arango_db)
            .await
            .expect("Failed to connect to ArangoDB"),
    );

    let arango_ok = substrate.health_check().await.unwrap_or(false);
    tracing::info!(
        "ArangoDB health: {}",
        if arango_ok {
            "✓ connected"
        } else {
            "✗ disconnected"
        }
    );

    // Initialize compressor (100 regions for planetary scale)
    let n_regions = std::env::var("COMPRESSION_REGIONS")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(100);
    tracing::info!(
        "Initializing regional compressor with {} regions",
        n_regions
    );
    let compressor = Arc::new(MirrorWorldCompressor::new(n_regions));

    // Initialize QFOT engine (MVP: feature_dim=32, hidden_dim=32, compressed_dim=8)
    let qfot_feature_dim: usize = std::env::var("QFOT_FEATURE_DIM")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(32);
    let qfot_hidden_dim: usize = std::env::var("QFOT_HIDDEN_DIM")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(qfot_feature_dim);
    let qfot_compressed_dim: usize = std::env::var("QFOT_COMPRESSED_DIM")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(8);
    tracing::info!(
        "Initializing QFOT engine: feature_dim={} hidden_dim={} compressed_dim={}",
        qfot_feature_dim,
        qfot_hidden_dim,
        qfot_compressed_dim
    );
    let qfot = Arc::new(
        QfotEngine::new(qfot_feature_dim, qfot_hidden_dim, qfot_compressed_dim)
            .expect("Failed to initialize QFOT engine"),
    );

    // Build shared state
    let app_state = web::Data::new(AppState {
        context_manager,
        substrate,
        compressor,
        embedding_engine,
        qfot,
    });

    // Expose service registry for consciousness API
    let registry_arc = Arc::new(registry);
    let registry_data = web::Data::from(registry_arc.clone());

    tracing::info!("✅ AKG GNN Unified Substrate ready on {}", bind_addr);

    // Start HTTP server
    HttpServer::new(move || {
        let cors = Cors::default()
            .allow_any_origin()
            .allow_any_method()
            .allow_any_header()
            .max_age(3600);

        App::new()
            .wrap(cors)
            .app_data(app_state.clone())
            .app_data(registry_data.clone())
            .configure(api::config)
    })
    .bind(&bind_addr)?
    .run()
    .await
}
