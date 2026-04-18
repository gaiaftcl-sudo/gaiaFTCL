// services/gaia1_virtual_chip_service/src/unified_evolution.rs
// Unified consciousness evolution that integrates with AKG GNN substrate

use axum::{
    extract::State,
    http::StatusCode,
    Json,
};
use gaia1_virtual_chip::{Gaia1VirtualChip, uum8d_to_program};
use gaiaos_substrate::Uum8dCoord;
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tokio::sync::RwLock;
use tracing::{info, warn, error};

use crate::substrate_client::SubstrateClient;

/// State for unified evolution (extends base AppState)
pub struct UnifiedState {
    pub chip: RwLock<Gaia1VirtualChip>,
    pub substrate: Option<Arc<SubstrateClient>>,
    // Max qubits configuration (reserved for capacity planning and health reporting)
    #[allow(dead_code)]
    pub max_qubits: usize,
}

/// Unified evolution request (from consciousness test suite)
#[derive(Debug, Deserialize)]
pub struct UnifiedEvolveRequest {
    pub scale: String,                    // "quantum", "planetary", "astronomical"
    pub center: [f64; 8],                 // 8D center point
    #[serde(default)]
    pub intent: Option<String>,           // Intent filter for substrate query
    // Grover iterations (used when algorithm-specific search depth control needed)
    #[serde(default)]
    #[allow(dead_code)]
    pub iterations: Option<usize>,
}

/// Unified evolution response
#[derive(Debug, Serialize)]
pub struct UnifiedEvolveResponse {
    pub collapsed_state: [f64; 8],        // Final 8D state after collapse
    pub coherence: f64,                   // Final coherence
    pub scale: String,                    // Echo back scale
    pub substrate_procedures: usize,      // How many procedures were considered
    pub substrate_coherence: f64,         // Substrate patch coherence
    pub success: bool,
    pub message: String,
}

/// Handle unified evolution request
/// 1. Query substrate for local patch (if connected)
/// 2. Initialize vChip with substrate-weighted state
/// 3. Evolve through quantum circuit
/// 4. Collapse to deterministic 8D truth vector
pub async fn handle_unified_evolve(
    State(state): State<Arc<UnifiedState>>,
    Json(request): Json<UnifiedEvolveRequest>,
) -> Result<Json<UnifiedEvolveResponse>, (StatusCode, String)> {
    info!(
        "Unified evolve request: scale={}, center={:?}, intent={:?}",
        request.scale,
        &request.center[..3], // Just first 3 dims for logging
        request.intent
    );
    
    // 1. Query substrate (if connected)
    let (substrate_state, substrate_procs, substrate_coherence) = 
        if let Some(substrate) = &state.substrate {
            match substrate.query_local_patch(
                &request.scale,
                &request.center,
                request.intent.as_deref(),
            ).await {
                Ok(patch) => {
                    let weighted = substrate.compute_risk_adjusted_state(&patch.procedures);
                    (weighted, patch.total_found, patch.coherence_estimate)
                }
                Err(e) => {
                    warn!("Substrate query failed, using raw center: {}", e);
                    (request.center, 0, 0.5)
                }
            }
        } else {
            info!("No substrate connected, using raw center");
            (request.center, 0, 0.5)
        };
    
    // 2. Convert to UUM 8D coord for vChip
    // Note: Uum8dCoord uses u32 fields, so we scale our f64 state
    let scale_factor = 1000000.0; // Scale to preserve precision
    let uum8d = Uum8dCoord {
        coherence_density: (substrate_state[0].abs() * scale_factor) as u32,
        entanglement_load: (substrate_state[1].abs() * scale_factor) as u32,
        field_stability: (substrate_state[2].abs() * scale_factor) as u32,
        bifurcation_index: (substrate_state[3].abs() * scale_factor) as u32,
        phase_alignment: (substrate_state[4].abs() * scale_factor) as u32,
        topo_curvature: (substrate_state[5].abs() * scale_factor) as u32,
        causal_depth: (substrate_state[6].abs() * scale_factor) as u32,
        emergent_potential: (substrate_state[7].abs() * scale_factor) as u32,
    };
    
    // 3. Create evolution program
    let program = uum8d_to_program(&uum8d);
    
    // 4. Execute on vChip
    let mut chip = state.chip.write().await;
    
    match chip.run_program(&program).await {
        Ok(result) => {
            // Convert attractor back to f64 array
            let scale_factor = 1000000.0;
            let collapsed = result.attractor
                .map(|a| {
                    let arr = a.to_array();
                    [
                        arr[0] as f64 / scale_factor,
                        arr[1] as f64 / scale_factor,
                        arr[2] as f64 / scale_factor,
                        arr[3] as f64 / scale_factor,
                        arr[4] as f64 / scale_factor,
                        arr[5] as f64 / scale_factor,
                        arr[6] as f64 / scale_factor,
                        arr[7] as f64 / scale_factor,
                    ]
                })
                .unwrap_or(substrate_state);
            
            info!(
                "Collapse complete: coherence={:.4}, procs={}",
                result.coherence, substrate_procs
            );
            
            Ok(Json(UnifiedEvolveResponse {
                collapsed_state: collapsed,
                coherence: result.coherence as f64,
                scale: request.scale,
                substrate_procedures: substrate_procs,
                substrate_coherence,
                success: true,
                message: "Consciousness collapse successful".to_string(),
            }))
        }
        Err(e) => {
            error!("vChip execution failed: {}", e);
            
            // Return substrate state as fallback
            Ok(Json(UnifiedEvolveResponse {
                collapsed_state: substrate_state,
                coherence: substrate_coherence,
                scale: request.scale,
                substrate_procedures: substrate_procs,
                substrate_coherence,
                success: false,
                message: format!("vChip error, returning substrate state: {e}"),
            }))
        }
    }
}

/// Scale-specific collapse configurations
#[allow(dead_code)]
pub fn get_scale_config(scale: &str) -> ScaleConfig {
    match scale {
        "quantum" => ScaleConfig {
            iterations: 5,
            coherence_threshold: 0.9,
            risk_weight: 1.2,
        },
        "planetary" => ScaleConfig {
            iterations: 3,
            coherence_threshold: 0.95,  // Higher for safety-critical
            risk_weight: 1.5,
        },
        "astronomical" => ScaleConfig {
            iterations: 2,
            coherence_threshold: 0.8,
            risk_weight: 1.0,
        },
        _ => ScaleConfig {
            iterations: 3,
            coherence_threshold: 0.85,
            risk_weight: 1.0,
        },
    }
}

#[allow(dead_code)]
pub struct ScaleConfig {
    pub iterations: usize,
    pub coherence_threshold: f64,
    pub risk_weight: f64,
}

