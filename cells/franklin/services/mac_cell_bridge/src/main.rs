//! MVP: connect to NATS, publish one liveness message on a fixed subject, exit 0.
//! No Arango, no JetStream consumer in v0.

use std::time::Duration;

use chrono::Utc;
use serde::Serialize;

const DEFAULT_NATS: &str = "nats://127.0.0.1:4222";
const LIVENESS_SUBJECT: &str = "gaiaftcl.mac_cell_bridge.liveness";

#[derive(Serialize)]
struct LivenessBody {
    ok: bool,
    ts: String,
    component: &'static str,
}

#[tokio::main]
async fn main() {
    if let Err(e) = run().await {
        eprintln!("mac_cell_bridge: {e}");
        std::process::exit(1);
    }
}

async fn run() -> Result<(), String> {
    let url = std::env::var("NATS_URL").unwrap_or_else(|_| DEFAULT_NATS.to_string());
    let client = async_nats::connect(&url).await.map_err(|e| e.to_string())?;
    let body = LivenessBody {
        ok: true,
        ts: Utc::now().to_rfc3339(),
        component: "mac_cell_bridge",
    };
    let payload = serde_json::to_vec(&body).map_err(|e| e.to_string())?;
    client
        .publish(LIVENESS_SUBJECT, payload.into())
        .await
        .map_err(|e| e.to_string())?;
    client.flush().await.map_err(|e| e.to_string())?;
    eprintln!("mac_cell_bridge: published to {LIVENESS_SUBJECT}");
    tokio::time::sleep(Duration::from_millis(10)).await;
    drop(client);
    Ok(())
}
