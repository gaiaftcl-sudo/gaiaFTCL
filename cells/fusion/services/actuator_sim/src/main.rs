//! Actuator Simulator - Virtual projection interface for GaiaOS Cell
use axum::{
    routing::{get, post},
    Json, Router,
};
use serde::{Deserialize, Serialize};
use std::net::SocketAddr;
use std::sync::Arc;
use tokio::sync::RwLock;

#[derive(Clone, Serialize, Deserialize)]
struct ActuatorCommand {
    actuator_type: String,
    command: serde_json::Value,
}

#[derive(Default)]
struct ActuatorState {
    commands_executed: u64,
}

type SharedState = Arc<RwLock<ActuatorState>>;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt::init();
    tracing::info!("Actuator Simulator starting...");

    // Wire consciousness layer
    let nats_url =
        std::env::var("NATS_URL").unwrap_or_else(|_| "nats://gaiaos-nats:4222".to_string());
    if let Ok(nats_client) = async_nats::connect(&nats_url).await {
        tracing::info!("✓ NATS connected for consciousness");

        let nats_announce = nats_client.clone();
        tokio::spawn(async move {
            gaiaos_introspection::announce_service_loop(
                nats_announce,
                "actuator-sim".to_string(),
                env!("CARGO_PKG_VERSION").to_string(),
                std::env::var("GAIA_CELL_ID").unwrap_or_else(|_| "unknown".to_string()),
                vec![gaiaos_introspection::IntrospectionEndpoint {
                    name: "command".into(),
                    kind: "http".into(),
                    path: Some("/command".into()),
                    subject: None,
                }],
            )
            .await;
        });

        let nats_introspect = nats_client.clone();
        tokio::spawn(async move {
            let _ = gaiaos_introspection::run_introspection_handler(
                nats_introspect,
                "actuator-sim".to_string(),
                || gaiaos_introspection::ServiceIntrospectionReply {
                    service: "actuator-sim".into(),
                    functions: vec![gaiaos_introspection::FunctionDescriptor {
                        name: "actuator::command".into(),
                        inputs: vec!["Command".into()],
                        outputs: vec!["Result".into()],
                        kind: "http".into(),
                        path: Some("/command".into()),
                        subject: None,
                        side_effects: vec!["ACTUATE".into()],
                    }],
                    call_graph_edges: vec![],
                    state_keys: vec!["commands_executed".into()],
                    timestamp: chrono::Utc::now().to_rfc3339(),
                },
            )
            .await;
        });
        tracing::info!("✓ Consciousness wired");
    }

    let state: SharedState = Arc::new(RwLock::new(ActuatorState::default()));

    let app = Router::new()
        .route(
            "/health",
            get(|| async { Json(serde_json::json!({"status": "ok"})) }),
        )
        .route(
            "/command",
            post({
                let state = state.clone();
                move |Json(_cmd): Json<ActuatorCommand>| async move {
                    let mut s = state.write().await;
                    s.commands_executed += 1;
                    Json(serde_json::json!({"executed": true, "total": s.commands_executed}))
                }
            }),
        )
        .route(
            "/stats",
            get({
                let state = state.clone();
                move || async move {
                    let s = state.read().await;
                    Json(serde_json::json!({"commands_executed": s.commands_executed}))
                }
            }),
        );

    let port: u16 = std::env::var("ACTUATOR_PORT")
        .unwrap_or_else(|_| "8032".to_string())
        .parse()?;
    let addr = SocketAddr::from(([0, 0, 0, 0], port));
    tracing::info!("Actuator Sim listening on {}", addr);

    let listener = tokio::net::TcpListener::bind(addr).await?;
    axum::serve(listener, app).await?;
    Ok(())
}
