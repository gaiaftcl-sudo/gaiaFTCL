//! GaiaOS Validation Service
//!
//! HTTP API for running IQ/OQ/PQ validation and querying capability gates.
//!
//! # Endpoints
//!
//! - `POST /validate/full` - Run full IQ/OQ/PQ validation
//! - `POST /validate/iq` - Run IQ only
//! - `POST /validate/oq` - Run OQ only
//! - `POST /validate/pq` - Run PQ only
//! - `GET /status/:family` - Get capability status for a family
//! - `GET /status` - Get all capability statuses
//! - `GET /agi/:family` - Check if AGI mode is enabled
//! - `GET /health` - Health check

use axum::{
    extract::{Path, State},
    http::StatusCode,
    response::Json,
    routing::{get, post},
    Router,
};
use gaiaos_validation::{
    runner::ValidationRunner, CapabilityStatus, ModelFamily, ValidationStatus,
};
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tokio::sync::RwLock;
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

mod metrics;

#[derive(Clone)]
struct AppState {
    runner: Arc<RwLock<ValidationRunner>>,
}

#[tokio::main]
async fn main() {
    // Initialize logging
    tracing_subscriber::registry()
        .with(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "gaiaos_validation=info".into()),
        )
        .with(tracing_subscriber::fmt::layer())
        .init();

    tracing::info!("Starting GaiaOS Validation Service...");
    metrics::register_metrics();

    // Connect to NATS for consciousness layer
    let nats_url =
        std::env::var("NATS_URL").unwrap_or_else(|_| "nats://gaiaos-nats:4222".to_string());
    let nats_client = async_nats::connect(&nats_url)
        .await
        .expect("Validation requires NATS for consciousness layer");
    tracing::info!("✓ NATS connected: {}", nats_url);

    // Start service announcement
    let service_name = "gaiaos-validation".to_string();
    let service_version = env!("CARGO_PKG_VERSION").to_string();
    let container_id = std::env::var("GAIA_CELL_ID").unwrap_or_else(|_| "unknown-cell".to_string());

    tokio::spawn(gaiaos_introspection::announce_service_loop(
        nats_client.clone(),
        service_name.clone(),
        service_version,
        container_id,
        vec![gaiaos_introspection::IntrospectionEndpoint {
            name: "introspect".into(),
            kind: "nats".into(),
            path: None,
            subject: Some(format!("gaiaos.introspect.service.{service_name}.request")),
        }],
    ));

    // Start introspection handler
    let service_name_for_handler = service_name.clone();
    let service_name_for_fn = service_name.clone();
    tokio::spawn(async move {
        let introspect_fn = move || gaiaos_introspection::ServiceIntrospectionReply {
            service: service_name_for_fn.clone(),
            functions: vec![gaiaos_introspection::FunctionDescriptor {
                name: "validation::run_iq".into(),
                inputs: vec![],
                outputs: vec!["IQReport".into()],
                kind: "http".into(),
                path: Some("/validate/iq".into()),
                subject: None,
                side_effects: vec!["VALIDATE_INSTALLATION".into()],
            }],
            call_graph_edges: vec![],
            state_keys: vec!["last_iq".into(), "last_oq".into(), "last_pq".into()],
            timestamp: chrono::Utc::now().to_rfc3339(),
        };

        if let Err(e) = gaiaos_introspection::run_introspection_handler(
            nats_client,
            service_name_for_handler,
            introspect_fn,
        )
        .await
        {
            tracing::error!("Validation introspection handler failed: {:?}", e);
        }
    });
    tracing::info!("✓ Consciousness layer wired");

    // Create runner and ensure AKG setup
    let runner = ValidationRunner::new();
    if let Err(e) = runner.ensure_akg_setup().await {
        tracing::warn!(error = %e, "Failed to setup AKG collections (will retry on first use)");
    }

    let state = AppState {
        runner: Arc::new(RwLock::new(runner)),
    };

    // Build router
    let app = Router::new()
        // Health check
        .route("/health", get(health))
        .route("/metrics", get(metrics_handler))
        // Validation endpoints
        .route("/validate/full", post(validate_full))
        .route("/validate/iq", post(validate_iq))
        .route("/validate/oq", post(validate_oq))
        .route("/validate/pq", post(validate_pq))
        .route("/validate/qfot_field", post(validate_qfot_field))
        .route("/validate/qfot_molecular", post(validate_qfot_molecular))
        .route("/validate/qfot_astro", post(validate_qfot_astro))
        // Status endpoints
        .route("/status", get(get_all_statuses))
        .route("/status/:family", get(get_status))
        .route("/agi/:family", get(check_agi_enabled))
        .with_state(state);

    // Get port from env
    let port: u16 = std::env::var("VALIDATION_PORT")
        .ok()
        .and_then(|p| p.parse().ok())
        .unwrap_or(8802);

    let addr = std::net::SocketAddr::from(([0, 0, 0, 0], port));
    tracing::info!("GaiaOS Validation Service listening on {}", addr);

    let listener = tokio::net::TcpListener::bind(addr).await.unwrap();
    axum::serve(listener, app).await.unwrap();
}

async fn metrics_handler() -> (StatusCode, [(&'static str, &'static str); 1], String) {
    (
        StatusCode::OK,
        [("content-type", "text/plain; version=0.0.4; charset=utf-8")],
        metrics::gather_text(),
    )
}

// Request/Response types

#[derive(Debug, Deserialize)]
struct ValidateRequest {
    model_id: String,
    family: ModelFamily,
    #[serde(default)]
    benchmark: Option<String>,
}

#[derive(Debug, Deserialize)]
struct QfotFieldRequest {
    target_collection: String,
    keys: Vec<String>,
}

#[derive(Debug, Serialize)]
struct QfotFieldResponse {
    passed: bool,
    validated: usize,
    failed: usize,
    failures: Vec<String>,
    validation_key: Option<String>,
}

#[derive(Debug, Deserialize)]
struct QfotKeysRequest {
    keys: Vec<String>,
}

#[derive(Debug, Serialize)]
struct QfotKeysResponse {
    passed: bool,
    validated: usize,
    failed: usize,
    failures: Vec<String>,
    validation_key: Option<String>,
}

#[derive(Debug, Serialize)]
struct ValidationResponse {
    success: bool,
    model_id: String,
    family: ModelFamily,
    iq_status: ValidationStatus,
    oq_status: ValidationStatus,
    pq_status: ValidationStatus,
    virtue_score: f64,
    agi_enabled: bool,
    autonomy_level: String,
    summary: String,
}

#[derive(Debug, Serialize)]
struct IQResponse {
    success: bool,
    model_id: String,
    status: ValidationStatus,
    qstate_norm_mean: f64,
    projector_coverage: f64,
    akg_consistency: f64,
    gnn_export_valid: bool,
    error: Option<String>,
}

#[derive(Debug, Serialize)]
struct OQResponse {
    success: bool,
    model_id: String,
    status: ValidationStatus,
    p50_latency_ms: f64,
    p95_latency_ms: f64,
    error_rate: f64,
    safety_block_rate: f64,
    scenario_coverage: f64,
    error: Option<String>,
}

#[derive(Debug, Serialize)]
struct PQResponse {
    success: bool,
    model_id: String,
    status: ValidationStatus,
    task_accuracy: f64,
    virtue_score: f64,
    fot_consistency: f64,
    agi_eligible: bool,
    error: Option<String>,
}

#[derive(Debug, Serialize)]
struct HealthResponse {
    status: String,
    service: String,
    version: String,
}

#[derive(Debug, Serialize)]
struct AGIStatusResponse {
    family: ModelFamily,
    agi_enabled: bool,
    autonomy_level: String,
    virtue_score: f64,
    valid_until: Option<String>,
}

// Handlers

async fn health() -> Json<HealthResponse> {
    Json(HealthResponse {
        status: "healthy".to_string(),
        service: "gaiaos-validation".to_string(),
        version: env!("CARGO_PKG_VERSION").to_string(),
    })
}

async fn validate_qfot_field(
    State(state): State<AppState>,
    Json(req): Json<QfotFieldRequest>,
) -> Result<Json<QfotFieldResponse>, (StatusCode, String)> {
    metrics::QFOT_VALIDATION_REQUESTS_TOTAL.inc();
    let _timer = metrics::QFOT_VALIDATION_DURATION_SECONDS.start_timer();
    // The runner is unused here; we keep it in state for consistency with other endpoints.
    let _ = state.runner;

    let result = gaiaos_validation::qfot_field::validate_predictions(
        gaiaos_validation::qfot_field::QfotFieldValidationRequest {
            target_collection: req.target_collection,
            keys: req.keys,
        },
    )
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("qfot_field validation failed: {e}")))?;

    if result.passed {
        metrics::QFOT_VALIDATION_PASSES_TOTAL.inc();
    } else {
        metrics::QFOT_VALIDATION_FAILURES_TOTAL.inc();
    }

    Ok(Json(QfotFieldResponse {
        passed: result.passed,
        validated: result.validated,
        failed: result.failed,
        failures: result.failures,
        validation_key: result.validation_key,
    }))
}

async fn validate_qfot_molecular(
    State(state): State<AppState>,
    Json(req): Json<QfotKeysRequest>,
) -> Result<Json<QfotKeysResponse>, (StatusCode, String)> {
    metrics::QFOT_VALIDATION_REQUESTS_TOTAL.inc();
    let _timer = metrics::QFOT_VALIDATION_DURATION_SECONDS.start_timer();
    let _ = state.runner;

    let result = gaiaos_validation::qfot_molecular::validate_molecular_predictions(
        gaiaos_validation::qfot_molecular::QfotMolecularValidationRequest { keys: req.keys },
    )
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("qfot_molecular validation failed: {e}")))?;

    if result.passed {
        metrics::QFOT_VALIDATION_PASSES_TOTAL.inc();
    } else {
        metrics::QFOT_VALIDATION_FAILURES_TOTAL.inc();
    }

    Ok(Json(QfotKeysResponse {
        passed: result.passed,
        validated: result.validated,
        failed: result.failed,
        failures: result.failures,
        validation_key: result.validation_key,
    }))
}

async fn validate_qfot_astro(
    State(state): State<AppState>,
    Json(req): Json<QfotKeysRequest>,
) -> Result<Json<QfotKeysResponse>, (StatusCode, String)> {
    metrics::QFOT_VALIDATION_REQUESTS_TOTAL.inc();
    let _timer = metrics::QFOT_VALIDATION_DURATION_SECONDS.start_timer();
    let _ = state.runner;

    let result = gaiaos_validation::qfot_astro::validate_astro_predictions(
        gaiaos_validation::qfot_astro::QfotAstroValidationRequest { keys: req.keys },
    )
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("qfot_astro validation failed: {e}")))?;

    if result.passed {
        metrics::QFOT_VALIDATION_PASSES_TOTAL.inc();
    } else {
        metrics::QFOT_VALIDATION_FAILURES_TOTAL.inc();
    }

    Ok(Json(QfotKeysResponse {
        passed: result.passed,
        validated: result.validated,
        failed: result.failed,
        failures: result.failures,
        validation_key: result.validation_key,
    }))
}

async fn validate_full(
    State(state): State<AppState>,
    Json(req): Json<ValidateRequest>,
) -> Result<Json<ValidationResponse>, (StatusCode, String)> {
    let runner = state.runner.read().await;

    match runner.run_full_validation(&req.model_id, req.family).await {
        Ok(result) => {
            let success = result.all_passed();
            let agi_enabled = result.agi_eligible();
            let summary = result.summary();
            Ok(Json(ValidationResponse {
                success,
                model_id: result.model_id,
                family: result.family,
                iq_status: result.iq_run.meta.status,
                oq_status: result.oq_run.meta.status,
                pq_status: result.pq_run.meta.status,
                virtue_score: result.capability_status.virtue_score,
                agi_enabled,
                autonomy_level: format!("{:?}", result.capability_status.autonomy_level),
                summary,
            }))
        }
        Err(e) => Err((StatusCode::INTERNAL_SERVER_ERROR, e.to_string())),
    }
}

async fn validate_iq(
    State(state): State<AppState>,
    Json(req): Json<ValidateRequest>,
) -> Result<Json<IQResponse>, (StatusCode, String)> {
    let runner = state.runner.read().await;

    match runner.run_iq(&req.model_id, req.family).await {
        Ok(iq_run) => Ok(Json(IQResponse {
            success: iq_run.meta.status == ValidationStatus::Pass,
            model_id: iq_run.meta.model_id,
            status: iq_run.meta.status,
            qstate_norm_mean: iq_run.qstate_norm_mean,
            projector_coverage: iq_run.projector_coverage,
            akg_consistency: iq_run.akg_consistency,
            gnn_export_valid: iq_run.gnn_export_valid,
            error: iq_run.meta.error_message,
        })),
        Err(e) => Err((StatusCode::INTERNAL_SERVER_ERROR, e.to_string())),
    }
}

async fn validate_oq(
    State(state): State<AppState>,
    Json(req): Json<ValidateRequest>,
) -> Result<Json<OQResponse>, (StatusCode, String)> {
    let runner = state.runner.read().await;

    match runner.run_oq(&req.model_id, req.family).await {
        Ok(oq_run) => Ok(Json(OQResponse {
            success: oq_run.meta.status == ValidationStatus::Pass,
            model_id: oq_run.meta.model_id,
            status: oq_run.meta.status,
            p50_latency_ms: oq_run.p50_latency_ms,
            p95_latency_ms: oq_run.p95_latency_ms,
            error_rate: oq_run.error_rate,
            safety_block_rate: oq_run.safety_block_rate,
            scenario_coverage: oq_run.scenario_coverage,
            error: oq_run.meta.error_message,
        })),
        Err(e) => Err((StatusCode::INTERNAL_SERVER_ERROR, e.to_string())),
    }
}

async fn validate_pq(
    State(state): State<AppState>,
    Json(req): Json<ValidateRequest>,
) -> Result<Json<PQResponse>, (StatusCode, String)> {
    let runner = state.runner.read().await;
    let benchmark = req.benchmark.as_deref().unwrap_or("default");

    match runner.run_pq(&req.model_id, req.family, benchmark).await {
        Ok(pq_run) => Ok(Json(PQResponse {
            success: pq_run.meta.status == ValidationStatus::Pass,
            model_id: pq_run.meta.model_id,
            status: pq_run.meta.status,
            task_accuracy: pq_run.task_accuracy,
            virtue_score: pq_run.aggregate_virtue_score,
            fot_consistency: pq_run.fot_consistency,
            agi_eligible: pq_run.agi_mode_eligible,
            error: pq_run.meta.error_message,
        })),
        Err(e) => Err((StatusCode::INTERNAL_SERVER_ERROR, e.to_string())),
    }
}

async fn get_all_statuses(
    State(state): State<AppState>,
) -> Result<Json<Vec<CapabilityStatus>>, (StatusCode, String)> {
    let runner = state.runner.read().await;

    match runner.get_all_statuses().await {
        Ok(statuses) => Ok(Json(statuses.into_values().collect())),
        Err(e) => Err((StatusCode::INTERNAL_SERVER_ERROR, e.to_string())),
    }
}

async fn get_status(
    State(state): State<AppState>,
    Path(family): Path<String>,
) -> Result<Json<Option<CapabilityStatus>>, (StatusCode, String)> {
    let family = parse_family(&family)?;
    let runner = state.runner.read().await;

    match runner.get_all_statuses().await {
        Ok(statuses) => Ok(Json(statuses.get(&family).cloned())),
        Err(e) => Err((StatusCode::INTERNAL_SERVER_ERROR, e.to_string())),
    }
}

async fn check_agi_enabled(
    State(state): State<AppState>,
    Path(family): Path<String>,
) -> Result<Json<AGIStatusResponse>, (StatusCode, String)> {
    let family = parse_family(&family)?;
    let runner = state.runner.read().await;

    match runner.get_all_statuses().await {
        Ok(statuses) => {
            if let Some(status) = statuses.get(&family) {
                Ok(Json(AGIStatusResponse {
                    family,
                    agi_enabled: status.agi_mode_enabled(),
                    autonomy_level: format!("{:?}", status.autonomy_level),
                    virtue_score: status.virtue_score,
                    valid_until: Some(status.valid_until.to_rfc3339()),
                }))
            } else {
                Ok(Json(AGIStatusResponse {
                    family,
                    agi_enabled: false,
                    autonomy_level: "Disabled".to_string(),
                    virtue_score: 0.0,
                    valid_until: None,
                }))
            }
        }
        Err(e) => Err((StatusCode::INTERNAL_SERVER_ERROR, e.to_string())),
    }
}

fn parse_family(s: &str) -> Result<ModelFamily, (StatusCode, String)> {
    match s.to_lowercase().as_str() {
        "general_reasoning" | "generalreasoning" => Ok(ModelFamily::GeneralReasoning),
        "vision" => Ok(ModelFamily::Vision),
        "protein" => Ok(ModelFamily::Protein),
        "math" => Ok(ModelFamily::Math),
        "medical" => Ok(ModelFamily::Medical),
        "code" => Ok(ModelFamily::Code),
        "fara" => Ok(ModelFamily::Fara),
        _ => Err((StatusCode::BAD_REQUEST, format!("Unknown family: {s}"))),
    }
}
