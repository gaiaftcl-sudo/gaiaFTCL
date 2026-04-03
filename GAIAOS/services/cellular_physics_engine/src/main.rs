use anyhow::{Context, Result};
use axum::{
    extract::{Query, State},
    http::StatusCode,
    response::IntoResponse,
    routing::{get, post},
    Json, Router,
};
use chrono::Utc;
use human_digital_twin::{
    CellularState, LungDigitalTwin, MedicalObservation, ObservationType, PredictedObservation,
};
use serde::{Deserialize, Serialize};
use std::{net::SocketAddr, sync::Arc};
use tower_http::cors::{Any, CorsLayer};
use tracing::{info, warn};

#[derive(Clone)]
struct AppState {
    config: Config,
}

#[derive(Clone)]
struct Config {
    port: u16,
}

impl Config {
    fn from_env() -> Self {
        Self {
            port: std::env::var("PORT")
                .ok()
                .and_then(|p| p.parse().ok())
                .unwrap_or(8850),
        }
    }
}

/// Forward model: Given cellular state, predict observable biomarkers
#[derive(Debug, Deserialize)]
struct ForwardModelRequest {
    patient_id: String,
    cellular_state: CellularStateSnapshot,
    observation_type: ObservationType,
}

#[derive(Debug, Serialize, Deserialize)]
struct CellularStateSnapshot {
    glucose_consumption: f64,
    lactate_production: f64,
    oxygen_consumption: f64,
    atp_production: f64,
    cell_count: u64,
    tissue_volume_mm3: f64,
}

#[derive(Debug, Serialize)]
struct ForwardModelResponse {
    observation_type: ObservationType,
    predicted_value: f64,
    uncertainty: f64,
    physical_constraints: Vec<String>,
}

/// Ensemble Kalman Filter update request
#[derive(Debug, Deserialize)]
struct EnKFUpdateRequest {
    patient_id: String,
    ensemble: Vec<CellularStateSnapshot>,
    observation: MedicalObservation,
}

#[derive(Debug, Serialize)]
struct EnKFUpdateResponse {
    updated_ensemble: Vec<CellularStateSnapshot>,
    mean_state: CellularStateSnapshot,
    uncertainty: f64,
}

/// Simulate forward model: cellular state → observable biomarker
async fn simulate_forward_model(
    cellular_state: &CellularStateSnapshot,
    observation_type: ObservationType,
) -> Result<PredictedObservation> {
    match observation_type {
        ObservationType::CtDNA => {
            // Estimate ctDNA frequency from cell count and mutations
            // Assumption: 1% of tumor cells shed DNA into bloodstream per day
            // Total circulating DNA ~1000 genome equivalents
            let shedding_rate = 0.01;
            let total_circulating_dna = 1000.0;
            let tumor_dna = cellular_state.cell_count as f64 * shedding_rate;
            let ctdna_frequency = tumor_dna / (tumor_dna + total_circulating_dna);
            
            // Uncertainty from shedding rate variability (±50%)
            let uncertainty = ctdna_frequency * 0.5;
            
            Ok(PredictedObservation {
                observation_type,
                value: ctdna_frequency,
                uncertainty,
                physical_constraints: vec![
                    "ctDNA frequency ≤ 1.0".to_string(),
                    "Shedding rate: 0.5-2% per day".to_string(),
                ],
            })
        }
        ObservationType::PETScan => {
            // Calculate SUV (standardized uptake value) from glucose consumption
            // SUV = (tissue activity / injected dose) * body weight
            // Typical: healthy tissue SUV ~1-2, cancer SUV ~5-15
            
            let glucose_uptake_rate = cellular_state.glucose_consumption * cellular_state.cell_count as f64;
            let tissue_volume_l = cellular_state.tissue_volume_mm3 / 1e6; // mm³ to L
            let activity_concentration = glucose_uptake_rate / tissue_volume_l;
            
            // Normalize to SUV scale (healthy baseline = 1.5)
            let baseline_activity = 10.0; // nmol/L/hour
            let suv = activity_concentration / baseline_activity * 1.5;
            
            // Uncertainty from PET scanner resolution (±15%)
            let uncertainty = suv * 0.15;
            
            Ok(PredictedObservation {
                observation_type,
                value: suv,
                uncertainty,
                physical_constraints: vec![
                    "SUV > 0".to_string(),
                    "Healthy tissue SUV: 1-2".to_string(),
                    "Cancer SUV: 5-15".to_string(),
                ],
            })
        }
        ObservationType::Temperature => {
            // Calculate heat production from metabolic activity
            // ATP hydrolysis releases ~50 kJ/mol
            // Body heat dissipation ~100 W for whole body
            
            let atp_production_rate = cellular_state.atp_production * cellular_state.cell_count as f64;
            let heat_kj_per_hour = atp_production_rate * 50.0 / 1e9; // nmol to mol
            let heat_watts = heat_kj_per_hour / 3.6; // kJ/hour to W
            
            // Temperature elevation (very small for localized tumor)
            let tissue_mass_kg = cellular_state.tissue_volume_mm3 / 1e6; // assume density ~1 g/cm³
            let specific_heat = 4.18; // kJ/(kg·K)
            let delta_temp = heat_watts / (tissue_mass_kg * specific_heat * 1000.0);
            
            // Uncertainty from blood flow cooling (±50%)
            let uncertainty = delta_temp * 0.5;
            
            Ok(PredictedObservation {
                observation_type,
                value: delta_temp,
                uncertainty,
                physical_constraints: vec![
                    "Temperature elevation < 1°C (blood cooling)".to_string(),
                    "Metabolic heat production ∝ ATP synthesis".to_string(),
                ],
            })
        }
        ObservationType::BloodGlucose => {
            // Glucose consumption affects blood levels
            let glucose_consumption_mmol_per_hour = cellular_state.glucose_consumption * cellular_state.cell_count as f64 / 1e6;
            
            // Normal blood glucose: 4-6 mmol/L
            // Total blood volume: ~5 L
            // Tumor effect is usually negligible unless very large
            let blood_volume_l = 5.0;
            let glucose_depletion = glucose_consumption_mmol_per_hour / blood_volume_l;
            
            let baseline_glucose = 5.0; // mmol/L
            let blood_glucose = baseline_glucose - glucose_depletion;
            
            let uncertainty = 0.5; // ±0.5 mmol/L measurement error
            
            Ok(PredictedObservation {
                observation_type,
                value: blood_glucose,
                uncertainty,
                physical_constraints: vec![
                    "Blood glucose: 3-10 mmol/L".to_string(),
                    "Tumor glucose consumption << liver production".to_string(),
                ],
            })
        }
        ObservationType::BloodLactate => {
            // Lactate production from Warburg effect
            let lactate_production_mmol_per_hour = cellular_state.lactate_production * cellular_state.cell_count as f64 / 1e6;
            
            // Normal blood lactate: 0.5-2 mmol/L
            // Elevated in cancer due to Warburg effect
            let blood_volume_l = 5.0;
            let lactate_elevation = lactate_production_mmol_per_hour / blood_volume_l;
            
            let baseline_lactate = 1.0; // mmol/L
            let blood_lactate = baseline_lactate + lactate_elevation;
            
            let uncertainty = 0.3; // ±0.3 mmol/L
            
            Ok(PredictedObservation {
                observation_type,
                value: blood_lactate,
                uncertainty,
                physical_constraints: vec![
                    "Blood lactate: 0.5-5 mmol/L".to_string(),
                    "Elevated lactate indicates Warburg effect".to_string(),
                ],
            })
        }
        ObservationType::TumorMarker => {
            // Generic tumor marker (e.g., CEA, CA-125)
            // Assume marker production proportional to tumor burden
            let marker_production_per_cell = 1.0; // arbitrary units
            let marker_level = cellular_state.cell_count as f64 * marker_production_per_cell / 1e9;
            
            let uncertainty = marker_level * 0.3; // ±30%
            
            Ok(PredictedObservation {
                observation_type,
                value: marker_level,
                uncertainty,
                physical_constraints: vec![
                    "Marker level ∝ tumor burden".to_string(),
                    "Half-life: days to weeks".to_string(),
                ],
            })
        }
    }
}

/// Validate physics constraints
fn validate_physics_constraints(state: &CellularStateSnapshot) -> Vec<String> {
    let mut violations = Vec::new();
    
    // Check ATP production matches oxygen consumption (P/O ratio ~2.5)
    let expected_atp = state.oxygen_consumption * 2.5;
    let atp_error = (state.atp_production - expected_atp).abs() / expected_atp;
    if atp_error > 0.2 {
        violations.push(format!(
            "ATP/O2 ratio violation: expected {:.2}, got {:.2} (error {:.1}%)",
            expected_atp, state.atp_production, atp_error * 100.0
        ));
    }
    
    // Check Warburg index is reasonable
    if state.oxygen_consumption > 0.0 {
        let warburg_index = state.lactate_production / state.oxygen_consumption;
        if warburg_index > 10.0 {
            violations.push(format!(
                "Warburg index too high: {:.2} (max ~10 for aggressive cancer)",
                warburg_index
            ));
        }
    }
    
    // Check glucose consumption is positive
    if state.glucose_consumption < 0.0 {
        violations.push("Negative glucose consumption".to_string());
    }
    
    violations
}

// ═══════════════════════════════════════════════════════════════════
// HTTP HANDLERS
// ═══════════════════════════════════════════════════════════════════

async fn health() -> impl IntoResponse {
    (
        StatusCode::OK,
        Json(serde_json::json!({
            "status": "ok",
            "component": "cellular-physics-engine",
            "timestamp": Utc::now().timestamp()
        })),
    )
}

async fn forward_model_handler(
    State(_state): State<Arc<AppState>>,
    Json(req): Json<ForwardModelRequest>,
) -> Result<Json<ForwardModelResponse>, StatusCode> {
    // Validate physics first
    let violations = validate_physics_constraints(&req.cellular_state);
    if !violations.is_empty() {
        warn!("Physics violations for patient {}: {:?}", req.patient_id, violations);
    }
    
    // Run forward model
    let prediction = simulate_forward_model(&req.cellular_state, req.observation_type)
        .await
        .map_err(|e| {
            warn!("Forward model error: {}", e);
            StatusCode::INTERNAL_SERVER_ERROR
        })?;
    
    Ok(Json(ForwardModelResponse {
        observation_type: prediction.observation_type,
        predicted_value: prediction.value,
        uncertainty: prediction.uncertainty,
        physical_constraints: prediction.physical_constraints,
    }))
}

async fn enkf_update_handler(
    State(_state): State<Arc<AppState>>,
    Json(req): Json<EnKFUpdateRequest>,
) -> Result<Json<EnKFUpdateResponse>, StatusCode> {
    // Ensemble Kalman Filter update
    // This is a simplified version - full implementation would use proper EnKF algorithm
    
    let ensemble_size = req.ensemble.len();
    if ensemble_size == 0 {
        return Err(StatusCode::BAD_REQUEST);
    }
    
    // Calculate ensemble mean
    let mean_glucose = req.ensemble.iter().map(|s| s.glucose_consumption).sum::<f64>() / ensemble_size as f64;
    let mean_lactate = req.ensemble.iter().map(|s| s.lactate_production).sum::<f64>() / ensemble_size as f64;
    let mean_oxygen = req.ensemble.iter().map(|s| s.oxygen_consumption).sum::<f64>() / ensemble_size as f64;
    let mean_atp = req.ensemble.iter().map(|s| s.atp_production).sum::<f64>() / ensemble_size as f64;
    
    let mean_state = CellularStateSnapshot {
        glucose_consumption: mean_glucose,
        lactate_production: mean_lactate,
        oxygen_consumption: mean_oxygen,
        atp_production: mean_atp,
        cell_count: req.ensemble[0].cell_count,
        tissue_volume_mm3: req.ensemble[0].tissue_volume_mm3,
    };
    
    // Calculate ensemble spread (uncertainty)
    let variance = req.ensemble.iter()
        .map(|s| (s.glucose_consumption - mean_glucose).powi(2))
        .sum::<f64>() / ensemble_size as f64;
    let uncertainty = variance.sqrt();
    
    // For now, return ensemble unchanged (full EnKF would update based on observation)
    // TODO: Implement proper EnKF update step
    
    Ok(Json(EnKFUpdateResponse {
        updated_ensemble: req.ensemble,
        mean_state,
        uncertainty,
    }))
}

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(
            std::env::var("RUST_LOG").unwrap_or_else(|_| "info,cellular_physics_engine=debug".to_string()),
        )
        .init();
    
    let config = Config::from_env();
    let state = Arc::new(AppState { config: config.clone() });
    
    let cors = CorsLayer::new()
        .allow_origin(Any)
        .allow_headers(Any)
        .allow_methods(Any);
    
    let app = Router::new()
        .route("/health", get(health))
        .route("/api/physics/forward_model", post(forward_model_handler))
        .route("/api/physics/enkf_update", post(enkf_update_handler))
        .with_state(state)
        .layer(cors);
    
    let addr = SocketAddr::from(([0, 0, 0, 0], config.port));
    info!("🧬 Cellular Physics Engine listening on http://{}", addr);
    info!("📡 Endpoints:");
    info!("   POST /api/physics/forward_model - Simulate observable from cellular state");
    info!("   POST /api/physics/enkf_update - Ensemble Kalman Filter update");
    
    let listener = tokio::net::TcpListener::bind(addr).await?;
    axum::serve(listener, app).await?;
    
    Ok(())
}

