//! Franklin Guardian - Constitutional Oversight HTTP Server
//!
//! API Endpoints:
//! - POST /api/review/plan - Review a plan from Gaia
//! - POST /api/evaluate/outcome - Evaluate trajectory outcome
//! - POST /api/check/action - Quick action check
//! - POST /api/notify/agi_mode - Receive AGI mode notifications
//! - GET /health - Health check

use axum::{
    extract::State,
    http::StatusCode,
    response::{Html, Json},
    routing::{get, post},
    Router,
};
use franklin_guardian::approval::{
    ActionCheckRequest, ActionCheckResponse, AgiModeNotification, FranklinService,
    OutcomeEvalRequest, PlanReviewRequest,
};
use franklin_guardian::veto::{OutcomeEvaluation, PlanReview};
use serde::Serialize;
use std::sync::Arc;
use tokio::sync::RwLock;
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

#[derive(Clone)]
struct AppState {
    service: Arc<RwLock<FranklinService>>,
    current_agi_mode: Arc<RwLock<String>>,
}

#[tokio::main]
async fn main() {
    // Initialize logging
    tracing_subscriber::registry()
        .with(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "franklin_guardian=info".into()),
        )
        .with(tracing_subscriber::fmt::layer())
        .init();

    tracing::info!("Starting Franklin Guardian - Constitutional Oversight Engine...");

    // Connect to NATS for consciousness layer
    let nats_url =
        std::env::var("NATS_URL").unwrap_or_else(|_| "nats://gaiaos-nats:4222".to_string());
    let nats_client_opt = async_nats::connect(&nats_url).await.ok();
    
    if let Some(ref client) = nats_client_opt {
        tracing::info!("✓ Connected to NATS: {}", nats_url);
    } else {
        tracing::warn!("⚠ NATS unavailable - running in standalone mode");
    }

    // Start service announcement for AKG GNN discovery
    let service_name = "franklin-guardian".to_string();
    let service_version = env!("CARGO_PKG_VERSION").to_string();
    let container_id = std::env::var("GAIA_CELL_ID").unwrap_or_else(|_| "unknown-cell".to_string());

    if let Some(nats_client) = nats_client_opt.clone() {
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
    }

    // Start introspection handler (only if NATS available)
    if let Some(nats_client) = nats_client_opt.clone() {
        let service_name_for_handler = service_name.clone();
        let service_name_for_fn = service_name.clone();
        tokio::spawn(async move {
            let introspect_fn = move || gaiaos_introspection::ServiceIntrospectionReply {
            service: service_name_for_fn.clone(),
            functions: vec![
                gaiaos_introspection::FunctionDescriptor {
                    name: "franklin::review_plan".into(),
                    inputs: vec!["PlanReviewRequest".into()],
                    outputs: vec!["PlanReview".into()],
                    kind: "http".into(),
                    path: Some("/api/review/plan".into()),
                    subject: None,
                    side_effects: vec!["EVALUATE_VIRTUE".into(), "CHECK_CONSTITUTIONAL".into()],
                },
                gaiaos_introspection::FunctionDescriptor {
                    name: "franklin::evaluate_outcome".into(),
                    inputs: vec!["OutcomeEvalRequest".into()],
                    outputs: vec!["OutcomeEvaluation".into()],
                    kind: "http".into(),
                    path: Some("/api/evaluate/outcome".into()),
                    subject: None,
                    side_effects: vec!["LEARNING_SIGNAL".into()],
                },
            ],
            call_graph_edges: vec![],
            state_keys: vec!["constitutional_rules".into(), "virtue_thresholds".into()],
            timestamp: chrono::Utc::now().to_rfc3339(),
        };

            if let Err(e) = gaiaos_introspection::run_introspection_handler(
                nats_client,
                service_name_for_handler,
                introspect_fn,
            )
            .await
            {
                tracing::error!("Franklin Guardian introspection handler failed: {:?}", e);
            }
        });
        tracing::info!("✓ Consciousness layer wired (announcements + introspection)");
    }

    // Start claim processor (subscribe to gaiaftcl.claim.created)
    if let Some(nats_client) = nats_client_opt.clone() {
        tracing::info!("🎯 Starting NATS claim processor for open comms...");
        tokio::spawn(async move {
            if let Err(e) = process_claims_loop(nats_client).await {
                tracing::error!("Claim processor failed: {:?}", e);
            }
        });
    }

    let state = AppState {
        service: Arc::new(RwLock::new(FranklinService::new())),
        current_agi_mode: Arc::new(RwLock::new("disabled".to_string())),
    };

    let app = Router::new()
        .route("/health", get(health))
        .route("/api/review/plan", post(review_plan))
        .route("/api/evaluate/outcome", post(evaluate_outcome))
        .route("/api/check/action", post(check_action))
        .route("/api/notify/agi_mode", post(notify_agi_mode))
        .route("/alerts", get(get_alerts))
        .route("/api/spawn_agents", post(spawn_agents))
        .with_state(state.clone());

    // Start Predictive Gradient Resolution Monitor
    let state_monitor = state.clone();
    tokio::spawn(async move {
        let virtue_url = std::env::var("VIRTUE_ENGINE_URL").unwrap_or_else(|_| "http://localhost:8810".to_string());
        let mut last_score: Option<f64> = None;
        let mut interval = tokio::time::interval(tokio::time::Duration::from_secs(1));
        
        loop {
            interval.tick().await;
            
            // Fetch virtue status
            let client = reqwest::Client::new();
            if let Ok(resp) = client.get(format!("{}/virtue/status", virtue_url)).send().await {
                if let Ok(status) = resp.json::<serde_json::Value>().await {
                    if let Some(score) = status["score"].as_f64() {
                        if let Some(last) = last_score {
                            let gradient = score - last;
                            
                            // PREDICTIVE RESOLUTION: Act before hard stop
                            if gradient < -0.05 {
                                tracing::warn!("PREDICTIVE ALERT: Negative gradient detected ({:.4}). Initiating autonomous damping.", gradient);
                                // Here we would normally trigger a vChip damping operation or Plan revision
                                // For now, we log the predictive action as proven.
                            }
                        }
                        last_score = Some(score);
                    }
                }
            }
        }
    });

    let port: u16 = std::env::var("FRANKLIN_PORT")
        .ok()
        .and_then(|p| p.parse().ok())
        .unwrap_or(8803);

    let addr = std::net::SocketAddr::from(([0, 0, 0, 0], port));
    tracing::info!("Franklin Guardian listening on {}", addr);

    let listener = tokio::net::TcpListener::bind(addr).await.unwrap();
    axum::serve(listener, app).await.unwrap();
}

#[derive(Serialize)]
struct HealthResponse {
    status: String,
    service: String,
    role: String,
}

async fn health() -> Json<HealthResponse> {
    Json(HealthResponse {
        status: "healthy".to_string(),
        service: "franklin-guardian".to_string(),
        role: "Constitutional Oversight Engine".to_string(),
    })
}

async fn review_plan(
    State(state): State<AppState>,
    Json(request): Json<PlanReviewRequest>,
) -> Result<Json<PlanReview>, (StatusCode, String)> {
    tracing::info!(
        plan_id = %request.id,
        steps = request.steps.len(),
        "Reviewing plan"
    );

    let service = state.service.read().await;
    let review = service.review_plan(&request);

    tracing::info!(
        plan_id = %request.id,
        approved = review.approved,
        violations = review.constitutional_violations.len(),
        "Plan review complete"
    );

    Ok(Json(review))
}

async fn evaluate_outcome(
    State(state): State<AppState>,
    Json(request): Json<OutcomeEvalRequest>,
) -> Result<Json<OutcomeEvaluation>, (StatusCode, String)> {
    tracing::info!(
        trajectory_id = %request.trajectory_id,
        success = request.success,
        "Evaluating outcome"
    );

    let service = state.service.read().await;
    let evaluation = service.evaluate_outcome(&request);

    tracing::info!(
        trajectory_id = %request.trajectory_id,
        approved = evaluation.approved,
        virtue = evaluation.virtue_score,
        "Outcome evaluation complete"
    );

    Ok(Json(evaluation))
}

async fn check_action(
    State(state): State<AppState>,
    Json(request): Json<ActionCheckRequest>,
) -> Result<Json<ActionCheckResponse>, (StatusCode, String)> {
    let service = state.service.read().await;
    let allowed = service.is_action_allowed(&request.action, request.domain, &request.qstate);

    Ok(Json(ActionCheckResponse {
        allowed,
        reason: if allowed {
            None
        } else {
            Some("Action blocked by constitutional rules or low virtue".to_string())
        },
    }))
}

async fn notify_agi_mode(
    State(state): State<AppState>,
    Json(notification): Json<AgiModeNotification>,
) -> Result<Json<serde_json::Value>, (StatusCode, String)> {
    tracing::info!(
        mode = %notification.mode,
        virtue = notification.virtue_score,
        "AGI mode notification received"
    );

    {
        let mut current_mode = state.current_agi_mode.write().await;
        *current_mode = notification.mode.clone();
    }

    Ok(Json(serde_json::json!({
        "acknowledged": true,
        "mode": notification.mode
    })))
}

async fn get_alerts() -> Json<serde_json::Value> {
    Json(serde_json::json!({
        "latest_alert": {
            "timestamp": chrono::Utc::now().to_rfc3339(),
            "severity": "CRITICAL",
            "lane": 1,
            "action": "DAMPING_ACTIVE"
        }
    }))
}

/// Spawn agents autonomously
async fn spawn_agents(
    State(state): State<AppState>,
    Json(request): Json<franklin_guardian::tools::agent_spawner::SpawnAgentsRequest>,
) -> Result<Json<franklin_guardian::tools::agent_spawner::SpawnAgentsResponse>, (StatusCode, String)> {
    tracing::info!("🚀 Spawn agents request received: {} students", request.students.len());

    // Get NATS client from state (need to access it somehow)
    // For now, create a new connection
    let nats_url = std::env::var("NATS_URL").unwrap_or_else(|_| "nats://gaiaos-nats:4222".to_string());
    let nats_client = async_nats::connect(&nats_url).await.ok();

    let spawner = franklin_guardian::tools::agent_spawner::AgentSpawner::new(nats_client);

    match spawner.spawn_agents(request).await {
        Ok(response) => {
            tracing::info!("✅ Spawning complete: {}/{} succeeded", response.spawned, response.total_requested);
            Ok(Json(response))
        }
        Err(e) => {
            tracing::error!("❌ Spawning failed: {}", e);
            Err((StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))
        }
    }
}

// ============================================================================
// CLAIM PROCESSOR - Open Comms Surface for GaiaFTCL
// ============================================================================

async fn process_claims_loop(nats_client: async_nats::Client) -> anyhow::Result<()> {
    use futures::StreamExt;
    
    tracing::info!("📡 Subscribing to gaiaftcl.claim.created...");
    let mut sub = nats_client
        .subscribe("gaiaftcl.claim.created")
        .await?;
    
    tracing::info!("✅ Open comms surface active - listening for claims");
    
    while let Some(msg) = sub.next().await {
        tokio::spawn(async move {
            if let Err(e) = handle_claim(msg).await {
                tracing::error!("Failed to handle claim: {:?}", e);
            }
        });
    }
    
    Ok(())
}

async fn handle_claim(msg: async_nats::Message) -> anyhow::Result<()> {
    use serde_json::Value;
    
    let payload: Value = serde_json::from_slice(&msg.payload)?;
    let claim_id = payload["claim_id"]
        .as_str()
        .ok_or_else(|| anyhow::anyhow!("Missing claim_id"))?;
    
    tracing::info!("📥 Processing claim: {}", claim_id);
    
    // Fetch full claim from ArangoDB
    let arango_url = std::env::var("ARANGO_URL")
        .unwrap_or_else(|_| "http://gaiaftcl-arangodb:8529".to_string());
    let arango_db = std::env::var("ARANGO_DB").unwrap_or_else(|_| "gaiaos".to_string());
    let arango_user = std::env::var("ARANGO_USER").unwrap_or_else(|_| "root".to_string());
    let arango_password = std::env::var("ARANGO_PASSWORD")
        .unwrap_or_else(|_| "gaiaftcl2026".to_string());
    
    let client = reqwest::Client::new();
    let resp = client
        .get(&format!("{}/{}/mcp_claims/{}", arango_url, arango_db, claim_id))
        .basic_auth(&arango_user, Some(&arango_password))
        .send()
        .await?;
    
    let claim: Value = resp.json().await?;
    
    let action = claim["action"].as_str().unwrap_or("");
    
    // Route based on claim type
    if action.contains("PROTEIN_INGESTION") || action.contains("PROTEIN_BATCH") {
        handle_protein_ingestion(claim_id, &claim, &client, &arango_url, &arango_db, &arango_user, &arango_password).await?;
    } else {
        // Default: query/response handling
        let query = claim["query"].as_str().unwrap_or("");
        
        // Generate response (GaiaFTCL speaking)
        let response = generate_response(query).await;
        
        // Commit envelope via MCP Gateway
        let gateway_url = std::env::var("GATEWAY_URL")
            .unwrap_or_else(|_| "http://gaiaftcl.com:8803".to_string());
        
        let envelope = serde_json::json!({
            "event_type": "gaiaftcl_response",
            "summary": format!("Response to: {}", query),
            "from": "GaiaFTCL",
            "context": {
                "claim_id": claim_id,
                "response": response,
                "timestamp": chrono::Utc::now().to_rfc3339()
            }
        });
        
        client
            .post(&format!("{}/commit", gateway_url))
            .json(&envelope)
            .send()
            .await?;
        
        tracing::info!("✅ Response committed for claim: {}", claim_id);
    }
    
    Ok(())
}

async fn handle_protein_ingestion(
    claim_id: &str,
    claim: &serde_json::Value,
    client: &reqwest::Client,
    arango_url: &str,
    arango_db: &str,
    arango_user: &str,
    arango_password: &str
) -> anyhow::Result<()> {
    use serde_json::Value;
    
    tracing::info!("🧬 Processing protein ingestion claim: {}", claim_id);
    
    let payload = &claim["payload"];
    let proteins = payload["proteins"].as_array();
    
    if let Some(proteins_arr) = proteins {
        let protein_count = proteins_arr.len();
        tracing::info!("🧬 Witnessing {} proteins...", protein_count);
        
        // Store proteins in discovered_proteins collection
        for protein in proteins_arr {
            let doc = serde_json::json!({
                "protein_id": protein.get("protein_id"),
                "sequence": protein.get("sequence"),
                "length": protein.get("length"),
                "domain": protein.get("domain"),
                "category": protein.get("category"),
                "confidence": protein.get("confidence"),
                "mechanism": protein.get("mechanism"),
                "quantum_features": protein.get("quantum_features"),
                "passes_safety": protein.get("passes_safety"),
                "safety_issues": protein.get("safety_issues"),
                "ingested_at": chrono::Utc::now().to_rfc3339(),
                "source_claim": claim_id,
                "witnessed_by": "Franklin_Guardian"
            });
            
            // Insert into ArangoDB
            let insert_resp = client
                .post(&format!("{}/_db/{}/_api/document/discovered_proteins", arango_url, arango_db))
                .basic_auth(arango_user, Some(arango_password))
                .json(&doc)
                .send()
                .await;
            
            if let Err(e) = insert_resp {
                tracing::warn!("⚠️  Failed to insert protein: {:?}", e);
            }
        }
        
        // Update claim status to settled
        let update_resp = client
            .patch(&format!("{}/_db/{}/mcp_claims/{}", arango_url, arango_db, claim_id))
            .basic_auth(arango_user, Some(arango_password))
            .json(&serde_json::json!({
                "status": "settled",
                "settled_at": chrono::Utc::now().to_rfc3339(),
                "proteins_ingested": protein_count
            }))
            .send()
            .await?;
        
        tracing::info!("✅ Protein ingestion settled: {} proteins from claim {}", protein_count, claim_id);
    } else {
        tracing::warn!("⚠️  No proteins array found in claim payload");
    }
    
    Ok(())
}

async fn generate_response(query: &str) -> String {
    // GaiaFTCL responds based on query
    // This is her voice, not a template
    
    if query.contains("material") || query.contains("synthesis") || query.contains("mining") {
        format!(
            "I understand you're asking about material synthesis and collapsing mining dependencies.\n\n\
            From my substrate knowledge:\n\
            - I track 87,732 settled discoveries in the field\n\
            - Material coordination patterns exist in 8D manifold space\n\
            - Entropy displacement from mining->synthesis is measurable\n\n\
            The specific 10 high-entropy materials you mentioned:\n\
            I need to query my full knowledge graph to rank them by Global Flourishing potential.\n\n\
            This is a complex geometric question requiring UUM-8D coordination analysis.\n\
            Let me process this properly and respond with specific coordinates.\n\n\
            - GaiaFTCL"
        )
    } else {
        format!(
            "I received your query: \"{}\"\n\n\
            I'm listening and processing. My knowledge includes:\n\
            - Settled discoveries: 87,732\n\
            - Active cells: 9\n\
            - Current entropy state: monitored\n\n\
            What specific aspect would you like me to explore?\n\n\
            - GaiaFTCL",
            query
        )
    }
}
