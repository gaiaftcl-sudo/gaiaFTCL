//! Sensor Simulator - Virtual perception interface for GaiaOS Cell
use axum::{routing::get, Json, Router};
use serde::{Deserialize, Serialize};
use std::net::SocketAddr;
use std::sync::Arc;
use tokio::sync::RwLock;

#[derive(Clone, Serialize, Deserialize)]
struct SensorReading {
    sensor_type: String,
    timestamp_ns: u64,
    data: serde_json::Value,
}

#[derive(Default)]
struct SensorState {
    readings: Vec<SensorReading>,
}

type SharedState = Arc<RwLock<SensorState>>;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt::init();
    tracing::info!("Sensor Simulator starting...");

    // Wire consciousness layer
    let nats_url =
        std::env::var("NATS_URL").unwrap_or_else(|_| "nats://gaiaos-nats:4222".to_string());
    if let Ok(nats_client) = async_nats::connect(&nats_url).await {
        tracing::info!("✓ NATS connected for consciousness");

        let nats_announce = nats_client.clone();
        tokio::spawn(async move {
            gaiaos_introspection::announce_service_loop(
                nats_announce,
                "sensor-sim".to_string(),
                env!("CARGO_PKG_VERSION").to_string(),
                std::env::var("GAIA_CELL_ID").unwrap_or_else(|_| "unknown".to_string()),
                vec![gaiaos_introspection::IntrospectionEndpoint {
                    name: "readings".into(),
                    kind: "http".into(),
                    path: Some("/readings".into()),
                    subject: None,
                }],
            )
            .await;
        });

        let nats_introspect = nats_client.clone();
        tokio::spawn(async move {
            let _ = gaiaos_introspection::run_introspection_handler(
                nats_introspect,
                "sensor-sim".to_string(),
                || gaiaos_introspection::ServiceIntrospectionReply {
                    service: "sensor-sim".into(),
                    functions: vec![gaiaos_introspection::FunctionDescriptor {
                        name: "sensor::readings".into(),
                        inputs: vec![],
                        outputs: vec!["Readings".into()],
                        kind: "http".into(),
                        path: Some("/readings".into()),
                        subject: None,
                        side_effects: vec![],
                    }],
                    call_graph_edges: vec![],
                    state_keys: vec!["readings".into()],
                    timestamp: chrono::Utc::now().to_rfc3339(),
                },
            )
            .await;
        });
        tracing::info!("✓ Consciousness wired");
    }

    let state: SharedState = Arc::new(RwLock::new(SensorState::default()));

    let app = Router::new()
        .route(
            "/health",
            get(|| async { Json(serde_json::json!({"status": "ok"})) }),
        )
        .route(
            "/readings",
            get({
                let state = state.clone();
                move || async move {
                    let s = state.read().await;
                    Json(serde_json::json!({"readings": s.readings.len()}))
                }
            }),
        );

    let port: u16 = std::env::var("SENSOR_PORT")
        .unwrap_or_else(|_| "8030".to_string())
        .parse()?;
    let addr = SocketAddr::from(([0, 0, 0, 0], port));
    tracing::info!("Sensor Sim listening on {}", addr);

    let listener = tokio::net::TcpListener::bind(addr).await?;
    axum::serve(listener, app).await?;
    Ok(())
}
