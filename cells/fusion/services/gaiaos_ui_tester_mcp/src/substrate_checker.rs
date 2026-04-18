//! Substrate Connection Checker
//! Verifies UIs connect to real substrate services (no mocks)

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SubstrateStatus {
    pub ui_name: String,
    pub akg_gnn_connected: bool,
    pub nats_connected: bool,
    pub arango_connected: bool,
    pub vchip_connected: bool,
    pub virtue_engine_connected: bool,
    pub mocked: bool,
    pub details: Vec<String>,
}

impl SubstrateStatus {
    pub fn unknown() -> Self {
        Self {
            ui_name: "unknown".to_string(),
            akg_gnn_connected: false,
            nats_connected: false,
            arango_connected: false,
            vchip_connected: false,
            virtue_engine_connected: false,
            mocked: true,
            details: vec!["Status unknown - UI not running".to_string()],
        }
    }
}

pub async fn check_substrate_connection(ui_name: &str) -> SubstrateStatus {
    tracing::info!("Checking substrate connection for {}", ui_name);

    match ui_name {
        "ATC_UI" => check_atc_substrate().await,
        "SmallWorld_UI" => check_smallworld_substrate().await,
        "Astro_UI" => check_astro_substrate().await,
        _ => SubstrateStatus::unknown(),
    }
}

async fn check_atc_substrate() -> SubstrateStatus {
    let mut status = SubstrateStatus {
        ui_name: "ATC_UI".to_string(),
        akg_gnn_connected: false,
        nats_connected: false,
        arango_connected: false,
        vchip_connected: false,
        virtue_engine_connected: false,
        mocked: false,
        details: Vec::new(),
    };

    // Check AKG GNN
    status.akg_gnn_connected = check_endpoint("http://localhost:8700/health").await;
    if status.akg_gnn_connected {
        status
            .details
            .push("✅ AKG GNN (8700) reachable".to_string());
    } else {
        status
            .details
            .push("❌ AKG GNN (8700) not reachable".to_string());
        status.mocked = true;
    }

    // Check NATS
    status.nats_connected = check_nats_connection().await;
    if status.nats_connected {
        status.details.push("✅ NATS (4222) connected".to_string());
    } else {
        status
            .details
            .push("❌ NATS (4222) not connected".to_string());
    }

    // Check ArangoDB
    status.arango_connected = check_endpoint("http://localhost:8529/_api/version").await;
    if status.arango_connected {
        status
            .details
            .push("✅ ArangoDB (8529) reachable".to_string());
    } else {
        status
            .details
            .push("❌ ArangoDB (8529) not reachable".to_string());
        status.mocked = true;
    }

    // Check vChip
    status.vchip_connected = check_endpoint("http://localhost:8001/health").await;
    if status.vchip_connected {
        status.details.push("✅ vChip (8001) reachable".to_string());
    } else {
        status
            .details
            .push("⚠️  vChip (8001) not reachable (optional for ATC)".to_string());
    }

    status
}

async fn check_smallworld_substrate() -> SubstrateStatus {
    let mut status = SubstrateStatus {
        ui_name: "SmallWorld_UI".to_string(),
        akg_gnn_connected: false,
        nats_connected: false,
        arango_connected: false,
        vchip_connected: false,
        virtue_engine_connected: false,
        mocked: false,
        details: Vec::new(),
    };

    // Check AKG GNN (vQbit clusters)
    status.akg_gnn_connected = check_endpoint("http://localhost:8700/health").await;
    if status.akg_gnn_connected {
        status
            .details
            .push("✅ AKG GNN (8700) for vQbit data".to_string());
    } else {
        status
            .details
            .push("❌ AKG GNN (8700) not reachable".to_string());
        status.mocked = true;
    }

    // Check Virtue Engine (CRITICAL for toxicity)
    status.virtue_engine_connected = check_endpoint("http://localhost:8810/health").await;
    if status.virtue_engine_connected {
        status
            .details
            .push("✅ Virtue Engine (8810) for toxicity scoring".to_string());
    } else {
        status
            .details
            .push("🔴 CRITICAL: Virtue Engine (8810) not reachable".to_string());
        status.mocked = true;
    }

    // Check vChip (quantum coherence)
    status.vchip_connected = check_endpoint("http://localhost:8001/health").await;
    if status.vchip_connected {
        status
            .details
            .push("✅ vChip (8001) for quantum ops".to_string());
    } else {
        status
            .details
            .push("❌ vChip (8001) not reachable".to_string());
    }

    status
}

async fn check_astro_substrate() -> SubstrateStatus {
    let status = SubstrateStatus {
        ui_name: "Astro_UI".to_string(),
        akg_gnn_connected: false,
        nats_connected: false,
        arango_connected: false,
        vchip_connected: false,
        virtue_engine_connected: false,
        mocked: true, // Not implemented yet
        details: vec!["⚠️  Astro UI not yet implemented".to_string()],
    };

    status
}

async fn check_endpoint(url: &str) -> bool {
    match reqwest::get(url).await {
        Ok(response) => response.status().is_success(),
        Err(_) => false,
    }
}

async fn check_nats_connection() -> bool {
    // Try to connect to NATS
    match async_nats::connect("nats://localhost:4222").await {
        Ok(_) => true,
        Err(_) => false,
    }
}
