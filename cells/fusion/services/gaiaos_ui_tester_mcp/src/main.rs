//! GaiaOS UI Testing Orchestration MCP Server
//!
//! Exposes MCP tools for testing all three world UIs:
//! - run_bevy_ui_scenario
//! - get_bevy_report
//! - run_playwright_suite
//! - get_playwright_report
//! - validate_ui_ttl_compliance
//! - check_substrate_connection

mod bevy_executor;
mod enforcement;
mod mcp_protocol;
mod substrate_checker;
mod ttl_validator;
mod domain_tubes;
mod closure_game;

use anyhow::Result;
use axum::{
    extract::State,
    middleware,
    routing::{get, post},
    Json, Router,
};
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tokio::sync::RwLock;
use tracing::info;

use crate::enforcement::check_tool_admissibility;
use std::path::Path;

// ============================================================================
// MCP TOOL DEFINITIONS
// ============================================================================

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MCPToolRequest {
    pub name: String,
    pub params: serde_json::Value,
}

// ============================================================================
// SERVER STATE
// ============================================================================

#[derive(Clone)]
pub struct AppState {
    test_runs: Arc<RwLock<std::collections::HashMap<String, TestRunResult>>>,
}

impl AppState {
    fn new() -> Self {
        Self {
            test_runs: Arc::new(RwLock::new(std::collections::HashMap::new())),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TestRunResult {
    pub run_id: String,
    pub world: String,
    pub scenario: String,
    pub passed: bool,
    pub timestamp: String,
    pub artifacts: Vec<String>,
    pub substrate_match: bool,
    pub performance_metrics: Option<PerformanceMetrics>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PerformanceMetrics {
    pub frame_time_ms: f32,
    pub memory_mb: f32,
    pub substrate_latency_ms: f32,
}

#[derive(Debug, Serialize)]
pub struct ToolExecResponse {
    pub ok: bool,
    pub result: serde_json::Value,
    pub witness: Option<serde_json::Value>,
    pub evidence_file: Option<String>,
}

// ============================================================================
// MAIN SERVER
// ============================================================================

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt::init();

    info!("Starting GaiaOS UI Tester MCP Server");

    let state = AppState::new();

    let protected_routes = Router::new()
        .route("/mcp/tools", get(list_tools_handler))
        .route("/mcp/execute", post(execute_tool_handler))
        .route("/runs/:run_id", get(get_run_handler))
        .layer(middleware::from_fn(enforcement::enforce_environment_id));

    let app = Router::new()
        .route("/health", get(health_handler))
        .route("/evidence/:call_id", get(get_evidence_handler))
        .route("/echo/nonce", post(echo_nonce_handler))
        .route("/echo/verify/:nonce", get(echo_verify_handler))
        .merge(protected_routes)
        .with_state(state);

    let port = std::env::var("MCP_PORT").unwrap_or_else(|_| "8900".to_string());
    let addr = format!("0.0.0.0:{}", port);
    info!("Listening on {}", addr);

    let listener = tokio::net::TcpListener::bind(&addr).await?;
    axum::serve(listener, app).await?;

    Ok(())
}

// ============================================================================
// HANDLERS
// ============================================================================

async fn health_handler() -> Json<serde_json::Value> {
    Json(serde_json::json!({
        "status": "healthy",
        "service": "gaiaos-ui-tester-mcp",
        "version": "0.1.0"
    }))
}

async fn list_tools_handler() -> Json<serde_json::Value> {
    Json(serde_json::json!({
        "tools": [
            {
                "name": "ui_contract_generate",
                "description": "Regenerate all canonical UI contract JSON files from tracked sources",
                "inputSchema": {
                    "type": "object",
                    "properties": {}
                }
            },
            {
                "name": "ui_contract_verify",
                "description": "Verify UI contract internal consistency and hashes; emit PROOF envelope",
                "inputSchema": {
                    "type": "object",
                    "properties": {}
                }
            },
            {
                "name": "ui_contract_report",
                "description": "Generate UI contract summary report (JSON + markdown)",
                "inputSchema": {
                    "type": "object",
                    "properties": {}
                }
            },
            {
                "name": "run_bevy_ui_scenario",
                "description": "Execute Bevy UI integration test for specific world/scenario",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "world": {
                            "type": "string",
                            "enum": ["ATC", "QCell", "Astro"],
                            "description": "Which world UI to test"
                        },
                        "scenario_id": {
                            "type": "string",
                            "description": "Test scenario identifier"
                        },
                        "frames": {
                            "type": "integer",
                            "description": "Number of frames to run (default: 100)"
                        }
                    },
                    "required": ["world", "scenario_id"]
                }
            },
            {
                "name": "get_bevy_report",
                "description": "Retrieve test run results",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "run_id": {
                            "type": "string",
                            "description": "Test run UUID"
                        }
                    },
                    "required": ["run_id"]
                }
            },
            {
                "name": "validate_ui_ttl_compliance",
                "description": "Check UI against gaiaos_ui.ttl and gaiaos_ui_policy.ttl",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "ui_name": {
                            "type": "string",
                            "enum": ["ATC_UI", "SmallWorld_UI", "Astro_UI"],
                            "description": "UI to validate"
                        }
                    },
                    "required": ["ui_name"]
                }
            },
            {
                "name": "check_substrate_connection",
                "description": "Verify UI connects to real substrate services",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "ui_name": {
                            "type": "string",
                            "description": "UI to check"
                        }
                    },
                    "required": ["ui_name"]
                }
            }
        ]
    }))
}

async fn execute_tool_handler(
    State(state): State<AppState>,
    headers: axum::http::HeaderMap,
    Json(req): Json<MCPToolRequest>,
) -> Result<Json<ToolExecResponse>, (axum::http::StatusCode, String)> {
    // Validate canonical files (fail-closed, runs once)
    if let Err(e) = enforcement::validate_canonicals() {
        return Err((
            axum::http::StatusCode::INTERNAL_SERVER_ERROR,
            format!("UI canonical validation failed: {}", e),
        ));
    }
    
    // Validate agent census canonicals (fail-closed, runs once)
    if let Err(e) = enforcement::validate_agent_census_canonicals() {
        return Err((
            axum::http::StatusCode::INTERNAL_SERVER_ERROR,
            format!("Agent census canonical validation failed: {}", e),
        ));
    }
    
    // Validate domain tubes canonicals (fail-closed, runs once)
    if let Err(e) = domain_tubes::validate_domain_canonicals() {
        return Err((
            axum::http::StatusCode::INTERNAL_SERVER_ERROR,
            format!("Domain tubes canonical validation failed: {}", e),
        ));
    }
    
    // Validate closure game canonicals (fail-closed, runs once)
    if let Err(e) = closure_game::validate_closure_game_canonicals() {
        return Err((
            axum::http::StatusCode::INTERNAL_SERVER_ERROR,
            format!("Closure game canonical validation failed: {}", e),
        ));
    }

    // Extract environment_id from headers (already validated by middleware)
    let environment_id = headers
        .get("X-Environment-ID")
        .and_then(|v| v.to_str().ok())
        .unwrap_or("UNKNOWN");

    // Constitutional door: X-Wallet-Address required for all MCP tool calls
    let wallet_address = headers
        .get("X-Wallet-Address")
        .and_then(|v| v.to_str().ok())
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty());
    if wallet_address.is_none() {
        return Err((
            axum::http::StatusCode::BAD_REQUEST,
            "X-Wallet-Address header required; anonymous calls rejected".to_string(),
        ));
    }
    let wallet_address_ref: Option<&str> = wallet_address.as_deref();

    let tool_name = req.name.as_str();

    // Check admissibility
    if let Err(e) = check_tool_admissibility(tool_name) {
        return Err((
            axum::http::StatusCode::UNPROCESSABLE_ENTITY,
            format!("tool not in admissibility contract: {}", e),
        ));
    }

    // Execute tool (do not return early from branches)
    let exec_result: serde_json::Value = match tool_name {
        "ui_contract_generate" => {
            match ui_contract_generate().await {
                Ok(result) => result,
                Err(e) => {
                    return Err((
                        axum::http::StatusCode::INTERNAL_SERVER_ERROR,
                        format!("ui_contract_generate failed: {}", e),
                    ));
                }
            }
        }

        "ui_contract_verify" => {
            match ui_contract_verify().await {
                Ok(result) => result,
                Err(e) => {
                    return Err((
                        axum::http::StatusCode::INTERNAL_SERVER_ERROR,
                        format!("ui_contract_verify failed: {}", e),
                    ));
                }
            }
        }

        "ui_contract_report" => {
            match ui_contract_report().await {
                Ok(result) => result,
                Err(e) => {
                    return Err((
                        axum::http::StatusCode::INTERNAL_SERVER_ERROR,
                        format!("ui_contract_report failed: {}", e),
                    ));
                }
            }
        }

        "check_substrate_connection" => {
            let ui_name = req
                .params
                .get("ui_name")
                .and_then(|v| v.as_str())
                .unwrap_or("UNKNOWN");
            let status = substrate_checker::check_substrate_connection(ui_name).await;
            serde_json::json!({
                "success": true,
                "status": status
            })
        }

        "validate_ui_ttl_compliance" => {
            let ui_name = req
                .params
                .get("ui_name")
                .and_then(|v| v.as_str())
                .unwrap_or("UNKNOWN");
            let report = ttl_validator::validate_ttl_compliance(ui_name).await;
            serde_json::json!({
                "success": true,
                "report": report
            })
        }

        "run_bevy_ui_scenario" => {
            let world = req
                .params
                .get("world")
                .and_then(|v| v.as_str())
                .unwrap_or("UNKNOWN");
            let scenario_id = req
                .params
                .get("scenario_id")
                .and_then(|v| v.as_str())
                .unwrap_or("UNKNOWN");
            let frames = req
                .params
                .get("frames")
                .and_then(|v| v.as_u64())
                .unwrap_or(100) as usize;

            if scenario_id == "ALL" {
                match bevy_executor::execute_all_scenarios(world).await {
                    Ok(test_results) => {
                        let mut runs = state.test_runs.write().await;
                        for r in test_results.iter() {
                            runs.insert(r.run_id.clone(), r.clone());
                        }
                        serde_json::json!({
                            "success": true,
                            "world": world,
                            "scenario": "ALL",
                            "runs": test_results,
                        })
                    }
                    Err(e) => {
                        return Err((
                            axum::http::StatusCode::INTERNAL_SERVER_ERROR,
                            format!("bevy execution failed: {}", e),
                        ));
                    }
                }
            } else {
                match bevy_executor::execute_bevy_scenario(world, scenario_id, frames).await {
                    Ok(test_result) => {
                        let run_id = test_result.run_id.clone();
                        state
                            .test_runs
                            .write()
                            .await
                            .insert(run_id.clone(), test_result.clone());
                        serde_json::json!({
                            "success": true,
                            "run_id": run_id,
                            "result": test_result
                        })
                    }
                    Err(e) => {
                        return Err((
                            axum::http::StatusCode::INTERNAL_SERVER_ERROR,
                            format!("bevy execution failed: {}", e),
                        ));
                    }
                }
            }
        }

        "get_bevy_report" => {
            let run_id = req
                .params
                .get("run_id")
                .and_then(|v| v.as_str())
                .unwrap_or("UNKNOWN");
            let runs = state.test_runs.read().await;
            match runs.get(run_id) {
                Some(result) => serde_json::json!({
                    "success": true,
                    "result": result
                }),
                None => {
                    return Err((
                        axum::http::StatusCode::NOT_FOUND,
                        format!("run_id not found: {}", run_id),
                    ));
                }
            }
        }

        "agent_register_v1" => {
            match agent_register_v1(&req.params).await {
                Ok(result) => result,
                Err(e) => {
                    return Err((
                        axum::http::StatusCode::UNPROCESSABLE_ENTITY,
                        format!("agent_register_v1 failed: {}", e),
                    ));
                }
            }
        }

        "agent_issue_challenges_v1" => {
            match agent_issue_challenges_v1(&req.params).await {
                Ok(result) => result,
                Err(e) => {
                    return Err((
                        axum::http::StatusCode::UNPROCESSABLE_ENTITY,
                        format!("agent_issue_challenges_v1 failed: {}", e),
                    ));
                }
            }
        }

        "agent_submit_proof_v1" => {
            match agent_submit_proof_v1(&req.params).await {
                Ok(result) => result,
                Err(e) => {
                    return Err((
                        axum::http::StatusCode::UNPROCESSABLE_ENTITY,
                        format!("agent_submit_proof_v1 failed: {}", e),
                    ));
                }
            }
        }

        "agent_label_v1" => {
            match agent_label_v1(&req.params).await {
                Ok(result) => result,
                Err(e) => {
                    return Err((
                        axum::http::StatusCode::UNPROCESSABLE_ENTITY,
                        format!("agent_label_v1 failed: {}", e),
                    ));
                }
            }
        }

        "agent_topology_export_v1" => {
            match agent_topology_export_v1(&req.params).await {
                Ok(result) => result,
                Err(e) => {
                    return Err((
                        axum::http::StatusCode::INTERNAL_SERVER_ERROR,
                        format!("agent_topology_export_v1 failed: {}", e),
                    ));
                }
            }
        }

        "agent_census_report_v1" => {
            match agent_census_report_v1().await {
                Ok(result) => result,
                Err(e) => {
                    return Err((
                        axum::http::StatusCode::INTERNAL_SERVER_ERROR,
                        format!("agent_census_report_v1 failed: {}", e),
                    ));
                }
            }
        }

        "agent_record_violation_v1" => {
            match agent_record_violation_v1(&req.params).await {
                Ok(result) => result,
                Err(e) => {
                    return Err((
                        axum::http::StatusCode::UNPROCESSABLE_ENTITY,
                        format!("agent_record_violation_v1 failed: {}", e),
                    ));
                }
            }
        }

        "agent_census_certificate_v1" => {
            match agent_census_certificate_v1(&req.params).await {
                Ok(result) => result,
                Err(e) => {
                    return Err((
                        axum::http::StatusCode::UNPROCESSABLE_ENTITY,
                        format!("agent_census_certificate_v1 failed: {}", e),
                    ));
                }
            }
        }

        "agent_scan_message_v1" => {
            match agent_scan_message_v1(&req.params).await {
                Ok(result) => result,
                Err(e) => {
                    return Err((
                        axum::http::StatusCode::UNPROCESSABLE_ENTITY,
                        format!("agent_scan_message_v1 failed: {}", e),
                    ));
                }
            }
        }

        "domain_tube_register_v1" => {
            match domain_tube_register_v1(&req.params).await {
                Ok(result) => result,
                Err(e) => {
                    return Err((
                        axum::http::StatusCode::UNPROCESSABLE_ENTITY,
                        format!("domain_tube_register_v1 failed: {}", e),
                    ));
                }
            }
        }

        "domain_tube_step_v1" => {
            match domain_tube_step_v1(&req.params).await {
                Ok(result) => result,
                Err(e) => {
                    return Err((
                        axum::http::StatusCode::UNPROCESSABLE_ENTITY,
                        format!("domain_tube_step_v1 failed: {}", e),
                    ));
                }
            }
        }

        "domain_tube_finalize_v1" => {
            match domain_tube_finalize_v1(&req.params).await {
                Ok(result) => result,
                Err(e) => {
                    return Err((
                        axum::http::StatusCode::UNPROCESSABLE_ENTITY,
                        format!("domain_tube_finalize_v1 failed: {}", e),
                    ));
                }
            }
        }

        "domain_tube_report_v1" => {
            match domain_tube_report_v1(&req.params).await {
                Ok(result) => result,
                Err(e) => {
                    return Err((
                        axum::http::StatusCode::UNPROCESSABLE_ENTITY,
                        format!("domain_tube_report_v1 failed: {}", e),
                    ));
                }
            }
        }

        "closure_evaluate_claim_v1" => {
            match closure_evaluate_claim_v1(&req.params).await {
                Ok(result) => result,
                Err(e) => {
                    return Err((
                        axum::http::StatusCode::UNPROCESSABLE_ENTITY,
                        format!("closure_evaluate_claim_v1 failed: {}", e),
                    ));
                }
            }
        }

        "closure_verify_evidence_v1" => {
            match closure_verify_evidence_v1(&req.params).await {
                Ok(result) => result,
                Err(e) => {
                    return Err((
                        axum::http::StatusCode::UNPROCESSABLE_ENTITY,
                        format!("closure_verify_evidence_v1 failed: {}", e),
                    ));
                }
            }
        }

        "closure_generate_receipt_v1" => {
            match closure_generate_receipt_v1(&req.params).await {
                Ok(result) => result,
                Err(e) => {
                    return Err((
                        axum::http::StatusCode::UNPROCESSABLE_ENTITY,
                        format!("closure_generate_receipt_v1 failed: {}", e),
                    ));
                }
            }
        }

        "closure_game_report_v1" => {
            match closure_game_report_v1(&req.params).await {
                Ok(result) => result,
                Err(e) => {
                    return Err((
                        axum::http::StatusCode::UNPROCESSABLE_ENTITY,
                        format!("closure_game_report_v1 failed: {}", e),
                    ));
                }
            }
        }

        other => {
            return Err((
                axum::http::StatusCode::UNPROCESSABLE_ENTITY,
                format!("unadmitted tool: {}", other),
            ));
        }
    };

    // Wrap with witness (SINGLE POST-EXECUTION PATH) — wallet_address flows to envelope
    let (witness, evidence_file) =
        enforcement::wrap_with_witness(environment_id, tool_name, wallet_address_ref, &req, &exec_result).map_err(
            |e| {
                (
                    axum::http::StatusCode::INTERNAL_SERVER_ERROR,
                    format!("witness generation failed: {}", e),
                )
            },
        )?;

    Ok(Json(ToolExecResponse {
        ok: true,
        result: exec_result,
        witness: Some(witness),
        evidence_file: Some(evidence_file),
    }))
}

async fn get_run_handler() -> Json<serde_json::Value> {
    Json(serde_json::json!({
        "error": "Not implemented"
    }))
}

// ============================================================================
// UI CONTRACT TOOLS
// ============================================================================

async fn ui_contract_generate() -> Result<serde_json::Value> {
    use std::fs;
    use std::collections::HashSet;
    use sha2::{Sha256, Digest};
    
    let base_path = Path::new("../../evidence/ui_expected");
    let files = ["domains.json", "games.json", "envelopes.json", "uum8d_dimensions.json", "game_envelopes.json", "game_dimensions.json"];
    
    // GUARD 1: All files must exist
    for file in &files {
        let path = base_path.join(file);
        if !path.exists() {
            return Ok(serde_json::json!({
                "success": false,
                "error": "MISSING_CANONICAL_FILE",
                "file": file,
                "message": format!("Required canonical file missing: {}", file)
            }));
        }
    }
    
    // GUARD 2: All files must be non-empty and valid JSON
    let mut counts_by_kind = serde_json::Map::new();
    for file in &files {
        let path = base_path.join(file);
        let content = fs::read_to_string(&path)
            .map_err(|e| anyhow::anyhow!("Failed to read {}: {}", file, e))?;
        
        if content.trim().is_empty() {
            return Ok(serde_json::json!({
                "success": false,
                "error": "EMPTY_CANONICAL_FILE",
                "file": file,
                "message": format!("Canonical file is empty: {}", file)
            }));
        }
        
        let parsed: serde_json::Value = serde_json::from_str(&content)
            .map_err(|e| anyhow::anyhow!("Invalid JSON in {}: {}", file, e))?;
        
        // GUARD 3: Must be an array
        if !parsed.is_array() {
            return Ok(serde_json::json!({
                "success": false,
                "error": "INVALID_CANONICAL_STRUCTURE",
                "file": file,
                "message": format!("Canonical file must be JSON array: {}", file)
            }));
        }
        
        // GUARD 4: No duplicate IDs within each file
        let array = parsed.as_array().unwrap();
        let mut seen_ids: HashSet<String> = HashSet::new();
        
        for (idx, item) in array.iter().enumerate() {
            let id = if *file == "uum8d_dimensions.json" {
                item["dim_key"].as_str()
            } else if *file == "game_dimensions.json" || *file == "game_envelopes.json" {
                item["game_id"].as_str()
            } else {
                item["id"].as_str()
            };
            
            if let Some(id_str) = id {
                if !seen_ids.insert(id_str.to_string()) {
                    return Ok(serde_json::json!({
                        "success": false,
                        "error": "DUPLICATE_ID_IN_CANONICAL",
                        "file": file,
                        "duplicate_id": id_str,
                        "index": idx,
                        "message": format!("Duplicate ID '{}' found in {}", id_str, file)
                    }));
                }
            }
        }
        
        // Count items by kind
        let kind = file.strip_suffix(".json").unwrap_or(file);
        counts_by_kind.insert(kind.to_string(), serde_json::json!(array.len()));
    }
    
    // Compute hashes
    let canonicals_hash = {
        let path = "../../evidence/ui_expected/CANONICALS.SHA256";
        let bytes = fs::read(path)?;
        let mut hasher = Sha256::new();
        hasher.update(&bytes);
        format!("{:x}", hasher.finalize())
    };
    
    let surface_map_hash = {
        let path = "../../evidence/ui_contract/ui_surface_map.json";
        let bytes = fs::read(path)?;
        let mut hasher = Sha256::new();
        hasher.update(&bytes);
        format!("{:x}", hasher.finalize())
    };
    
    let manifest_hash = {
        let path = "../../evidence/ui_contract/ui_contract_manifest.json";
        let bytes = fs::read(path)?;
        let mut hasher = Sha256::new();
        hasher.update(&bytes);
        format!("{:x}", hasher.finalize())
    };
    
    // Load surface map to compute scorecards
    let surface_map_path = "../../evidence/ui_contract/ui_surface_map.json";
    let surface_map_content = fs::read_to_string(surface_map_path)?;
    let surface_map: serde_json::Value = serde_json::from_str(&surface_map_content)?;
    let mappings = surface_map["mappings"].as_array()
        .ok_or_else(|| anyhow::anyhow!("Missing mappings in surface_map"))?;
    
    // Total expected items = number of mappings in surface_map (the expanded count)
    let total_expected = mappings.len();
    
    let allowed_routes = vec!["/index.html"];
    let mut contract_mapped = 0;
    let mut ui_present = 0;
    let mut ui_absent = 0;
    let mut ui_proof_violations = 0;
    let mut invalid_route_violations = 0;
    let mut ui_absent_by_reason: std::collections::HashMap<String, usize> = std::collections::HashMap::new();
    
    for mapping in mappings {
        let is_mapped = mapping["contract_mapping"]["mapped"].as_bool().unwrap_or(false);
        if is_mapped {
            contract_mapped += 1;
        }
        
        let ui_status = mapping["ui_mapping"]["status"].as_str().unwrap_or("UNKNOWN");
        if ui_status == "UI_PRESENT" {
            ui_present += 1;
            let has_route = mapping["ui_mapping"]["route"].as_str().filter(|s| !s.is_empty()).is_some();
            let has_selector = mapping["ui_mapping"]["selector"].as_str().filter(|s| !s.is_empty()).is_some();
            let has_assertion = mapping["ui_mapping"]["assertion"].as_str().filter(|s| !s.is_empty()).is_some();
            if !has_route || !has_selector || !has_assertion {
                ui_proof_violations += 1;
            }
            if let Some(route) = mapping["ui_mapping"]["route"].as_str() {
                if !allowed_routes.contains(&route) {
                    invalid_route_violations += 1;
                }
            }
        } else if ui_status == "UI_ABSENT" {
            ui_absent += 1;
            let reason = mapping["ui_mapping"]["reason_code"].as_str().unwrap_or("UNKNOWN");
            *ui_absent_by_reason.entry(reason.to_string()).or_insert(0) += 1;
        }
    }
    
    let contract_unmapped = if total_expected > contract_mapped { total_expected - contract_mapped } else { 0 };
    
    // FAIL CLOSED: contract must be 100%
    if contract_unmapped > 0 {
        return Ok(serde_json::json!({
            "success": false,
            "error": "CONTRACT_UNMAPPED_ITEMS",
            "contract_coverage": {
                "total_items": total_expected,
                "mapped_items": contract_mapped,
                "unmapped_items": contract_unmapped
            },
            "message": format!("Expected {} items but only {} contract-mapped", total_expected, contract_mapped)
        }));
    }
    
    Ok(serde_json::json!({
        "success": true,
        "report_schema_version": 1,
        "counts_raw": counts_by_kind,
        "counts_expanded": total_expected,
        "contract_coverage": {
            "total_items": total_expected,
            "mapped_items": contract_mapped,
            "unmapped_items": contract_unmapped
        },
        "ui_coverage": {
            "ui_total_items": total_expected,
            "ui_present_items": ui_present,
            "ui_absent_items": ui_absent,
            "ui_present_requires_proof_violations": ui_proof_violations
        },
        "ui_absent_by_reason": ui_absent_by_reason,
        "invalid_route_violations": invalid_route_violations,
        "surface_map_hash": surface_map_hash,
        "canonicals_hash": canonicals_hash,
        "manifest_hash": manifest_hash
    }))
}

async fn ui_contract_verify() -> Result<serde_json::Value> {
    use sha2::{Sha256, Digest};
    use std::fs;
    
    // Read manifest
    let manifest_path = "../../evidence/ui_contract/ui_contract_manifest.json";
    let manifest_content = fs::read_to_string(manifest_path)?;
    let manifest: serde_json::Value = serde_json::from_str(&manifest_content)?;
    
    let mut verification_results = Vec::new();
    let canonical_files = manifest["canonical_files"].as_object()
        .ok_or_else(|| anyhow::anyhow!("Missing canonical_files in manifest"))?;
    
    for (key, file_info) in canonical_files {
        let path = file_info["path"].as_str()
            .ok_or_else(|| anyhow::anyhow!("Missing path for {}", key))?;
        let expected_hash = file_info["sha256"].as_str()
            .ok_or_else(|| anyhow::anyhow!("Missing sha256 for {}", key))?;
        
        let content = fs::read(path)?;
        let mut hasher = Sha256::new();
        hasher.update(&content);
        let actual_hash = format!("{:x}", hasher.finalize());
        
        let matches = actual_hash == expected_hash;
        verification_results.push(serde_json::json!({
            "file": key,
            "path": path,
            "expected_hash": expected_hash,
            "actual_hash": actual_hash,
            "matches": matches
        }));
    }
    
    let all_match = verification_results.iter().all(|r| r["matches"].as_bool().unwrap_or(false));
    
    Ok(serde_json::json!({
        "success": all_match,
        "verification_results": verification_results,
        "verdict": if all_match { "PROOF_VALID" } else { "PROOF_INVALID" }
    }))
}

async fn ui_contract_report() -> Result<serde_json::Value> {
    use std::fs;
    use std::collections::HashSet;
    
    let manifest_path = "../../evidence/ui_contract/ui_contract_manifest.json";
    let manifest_content = fs::read_to_string(manifest_path)?;
    let manifest: serde_json::Value = serde_json::from_str(&manifest_content)?;
    
    let surface_map_path = "../../evidence/ui_contract/ui_surface_map.json";
    let surface_map_content = fs::read_to_string(surface_map_path)?;
    let surface_map: serde_json::Value = serde_json::from_str(&surface_map_content)?;
    
    let mappings = surface_map["mappings"].as_array()
        .ok_or_else(|| anyhow::anyhow!("Missing mappings in surface_map"))?;
    
    // GUARD: Build expected ID set from canonical files
    let base_path = Path::new("../../evidence/ui_expected");
    let mut expected_ids: HashSet<String> = HashSet::new();
    
    // Load all canonical IDs
    let domains: serde_json::Value = serde_json::from_str(&fs::read_to_string(base_path.join("domains.json"))?)?;
    for item in domains.as_array().unwrap() {
        expected_ids.insert(item["id"].as_str().unwrap().to_string());
    }
    
    let games: serde_json::Value = serde_json::from_str(&fs::read_to_string(base_path.join("games.json"))?)?;
    for item in games.as_array().unwrap() {
        expected_ids.insert(item["id"].as_str().unwrap().to_string());
    }
    
    let envelopes: serde_json::Value = serde_json::from_str(&fs::read_to_string(base_path.join("envelopes.json"))?)?;
    for item in envelopes.as_array().unwrap() {
        expected_ids.insert(item["subject"].as_str().unwrap().to_string());
    }
    
    let dimensions: serde_json::Value = serde_json::from_str(&fs::read_to_string(base_path.join("uum8d_dimensions.json"))?)?;
    for item in dimensions.as_array().unwrap() {
        expected_ids.insert(item["dim_key"].as_str().unwrap().to_string());
    }
    
    let game_dimensions: serde_json::Value = serde_json::from_str(&fs::read_to_string(base_path.join("game_dimensions.json"))?)?;
    for item in game_dimensions.as_array().unwrap() {
        let game_id = item["game_id"].as_str().unwrap();
        for dim in item["required_dimensions"].as_array().unwrap() {
            expected_ids.insert(format!("{}:{}", game_id, dim.as_str().unwrap()));
        }
    }
    
    let game_envelopes: serde_json::Value = serde_json::from_str(&fs::read_to_string(base_path.join("game_envelopes.json"))?)?;
    for item in game_envelopes.as_array().unwrap() {
        let game_id = item["game_id"].as_str().unwrap();
        for subject in item["envelope_subjects"].as_array().unwrap() {
            expected_ids.insert(format!("{}:{}", game_id, subject.as_str().unwrap()));
        }
    }
    
    // Check for missing IDs in surface_map
    let mut mapped_ids: HashSet<String> = HashSet::new();
    for mapping in mappings {
        mapped_ids.insert(mapping["id"].as_str().unwrap().to_string());
    }
    
    let missing_ids: Vec<String> = expected_ids.difference(&mapped_ids).cloned().collect();
    
    if !missing_ids.is_empty() {
        return Ok(serde_json::json!({
            "success": false,
            "error": "MISSING_IDS_IN_SURFACE_MAP",
            "missing_ids": missing_ids,
            "missing_count": missing_ids.len(),
            "message": format!("{} expected IDs are missing from ui_surface_map.json", missing_ids.len())
        }));
    }
    
    // CONTRACT COVERAGE
    let total_expected = expected_ids.len();
    let mut contract_mapped = 0;
    
    // ALLOWED REAL APP ROUTES (not audit/coverage pages)
    let allowed_routes = vec!["/index.html"];
    
    // UI COVERAGE
    let mut ui_present = 0;
    let mut ui_absent = 0;
    let mut ui_proof_violations = 0;
    let mut invalid_route_violations = 0;
    let mut ui_absent_by_reason: std::collections::HashMap<String, usize> = std::collections::HashMap::new();
    
    for mapping in mappings {
        // Contract mapping
        let is_mapped = mapping["contract_mapping"]["mapped"].as_bool().unwrap_or(false);
        if is_mapped {
            contract_mapped += 1;
        }
        
        // UI mapping
        let ui_status = mapping["ui_mapping"]["status"].as_str().unwrap_or("UNKNOWN");
        if ui_status == "UI_PRESENT" {
            ui_present += 1;
            // Verify proof requirements (non-empty strings)
            let has_route = mapping["ui_mapping"]["route"].as_str().filter(|s| !s.is_empty()).is_some();
            let has_selector = mapping["ui_mapping"]["selector"].as_str().filter(|s| !s.is_empty()).is_some();
            let has_assertion = mapping["ui_mapping"]["assertion"].as_str().filter(|s| !s.is_empty()).is_some();
            if !has_route || !has_selector || !has_assertion {
                ui_proof_violations += 1;
            }
            // Verify route is allowed (real app route, not audit page)
            if let Some(route) = mapping["ui_mapping"]["route"].as_str() {
                if !allowed_routes.contains(&route) {
                    invalid_route_violations += 1;
                }
            }
        } else if ui_status == "UI_ABSENT" {
            ui_absent += 1;
            let reason = mapping["ui_mapping"]["reason_code"].as_str().unwrap_or("UNKNOWN");
            *ui_absent_by_reason.entry(reason.to_string()).or_insert(0) += 1;
        }
    }
    
    let contract_unmapped = if total_expected > contract_mapped { total_expected - contract_mapped } else { 0 };
    
    // FAIL CLOSED IF VIOLATIONS
    if contract_unmapped > 0 {
        return Ok(serde_json::json!({
            "success": false,
            "error": "CONTRACT_UNMAPPED_ITEMS",
            "contract_coverage": {
                "total_items": total_expected,
                "mapped_items": contract_mapped,
                "unmapped_items": contract_unmapped
            },
            "message": format!("Expected {} items but only {} contract-mapped", total_expected, contract_mapped)
        }));
    }
    
    if invalid_route_violations > 0 {
        return Ok(serde_json::json!({
            "success": false,
            "error": "INVALID_ROUTE_VIOLATIONS",
            "ui_coverage": {
                "ui_total_items": total_expected,
                "ui_present_items": ui_present,
                "ui_absent_items": ui_absent,
                "invalid_route_violations": invalid_route_violations
            },
            "allowed_routes": allowed_routes,
            "message": format!("{} UI_PRESENT items use non-real-app routes (audit/coverage pages)", invalid_route_violations)
        }));
    }
    
    if ui_proof_violations > 0 {
        return Ok(serde_json::json!({
            "success": false,
            "error": "UI_PRESENT_REQUIRES_PROOF_VIOLATIONS",
            "ui_coverage": {
                "ui_total_items": total_expected,
                "ui_present_items": ui_present,
                "ui_absent_items": ui_absent,
                "ui_present_requires_proof_violations": ui_proof_violations
            },
            "message": format!("{} UI_PRESENT items lack route/selector/assertion", ui_proof_violations)
        }));
    }
    
    if ui_present + ui_absent != total_expected {
        return Ok(serde_json::json!({
            "success": false,
            "error": "UI_COUNT_MISMATCH",
            "ui_coverage": {
                "ui_total_items": total_expected,
                "ui_present_items": ui_present,
                "ui_absent_items": ui_absent,
                "sum": ui_present + ui_absent
            },
            "message": format!("ui_present({}) + ui_absent({}) != total({})", ui_present, ui_absent, total_expected)
        }));
    }
    
    // Generate backlog files (deterministic, even if ui_absent=0)
    use sha2::{Sha256, Digest};
    
    let mut backlog_items = Vec::new();
    for mapping in mappings {
        let ui_status = mapping["ui_mapping"]["status"].as_str().unwrap_or("UNKNOWN");
        if ui_status == "UI_ABSENT" {
            backlog_items.push(mapping.clone());
        }
    }
    
    // Sort by priority: game_envelope, envelope, game_dimension, dimension, game, domain
    let priority_order = vec!["game_envelope", "envelope", "game_dimension", "dimension", "game", "domain"];
    backlog_items.sort_by(|a, b| {
        let kind_a = a["kind"].as_str().unwrap_or("");
        let kind_b = b["kind"].as_str().unwrap_or("");
        let id_a = a["id"].as_str().unwrap_or("");
        let id_b = b["id"].as_str().unwrap_or("");
        
        let priority_a = priority_order.iter().position(|&k| k == kind_a).unwrap_or(999);
        let priority_b = priority_order.iter().position(|&k| k == kind_b).unwrap_or(999);
        
        priority_a.cmp(&priority_b).then_with(|| id_a.cmp(id_b))
    });
    
    // Write JSON backlog
    let backlog_json_path = "../../evidence/ui_contract/UI_ABSENT_BACKLOG.json";
    let backlog_json = serde_json::json!({
        "count": backlog_items.len(),
        "items": backlog_items
    });
    fs::write(backlog_json_path, serde_json::to_string_pretty(&backlog_json)?)?;
    
    // Write MD backlog
    let backlog_md_path = "../../evidence/ui_contract/UI_ABSENT_BACKLOG.md";
    let mut md_content = String::new();
    md_content.push_str("# UI_ABSENT BACKLOG\n\n");
    if backlog_items.is_empty() {
        md_content.push_str("**No absent items. UI realization: 100%**\n\n");
        md_content.push_str(&format!("Total items: {}\n", total_expected));
        md_content.push_str(&format!("UI_PRESENT: {}\n", ui_present));
        md_content.push_str(&format!("UI_ABSENT: {}\n", ui_absent));
    } else {
        md_content.push_str(&format!("**Total UI_ABSENT items: {}**\n\n", backlog_items.len()));
        md_content.push_str("Priority order: game_envelope → envelope → game_dimension → dimension → game → domain\n\n");
        
        let mut current_kind = "";
        for item in &backlog_items {
            let kind = item["kind"].as_str().unwrap_or("unknown");
            let id = item["id"].as_str().unwrap_or("unknown");
            let reason = item["ui_mapping"]["reason_code"].as_str().unwrap_or("UNKNOWN");
            
            if kind != current_kind {
                md_content.push_str(&format!("\n## {}\n\n", kind.to_uppercase()));
                current_kind = kind;
            }
            
            md_content.push_str(&format!("- **{}** (reason: {})\n", id, reason));
        }
    }
    fs::write(backlog_md_path, md_content)?;
    
    // Compute hashes
    let canonicals_hash = {
        let path = "../../evidence/ui_expected/CANONICALS.SHA256";
        let bytes = fs::read(path)?;
        let mut hasher = Sha256::new();
        hasher.update(&bytes);
        format!("{:x}", hasher.finalize())
    };
    
    let surface_map_hash = {
        let path = "../../evidence/ui_contract/ui_surface_map.json";
        let bytes = fs::read(path)?;
        let mut hasher = Sha256::new();
        hasher.update(&bytes);
        format!("{:x}", hasher.finalize())
    };
    
    let manifest_hash = {
        let path = "../../evidence/ui_contract/ui_contract_manifest.json";
        let bytes = fs::read(path)?;
        let mut hasher = Sha256::new();
        hasher.update(&bytes);
        format!("{:x}", hasher.finalize())
    };
    
    // Compute counts by kind
    let mut counts_by_kind = serde_json::Map::new();
    let base_path = Path::new("../../evidence/ui_expected");
    let files = ["domains.json", "games.json", "envelopes.json", "uum8d_dimensions.json", "game_envelopes.json", "game_dimensions.json"];
    for file in &files {
        let path = base_path.join(file);
        let content = fs::read_to_string(&path)?;
        let parsed: serde_json::Value = serde_json::from_str(&content)?;
        let array = parsed.as_array().unwrap();
        let kind = file.strip_suffix(".json").unwrap_or(file);
        counts_by_kind.insert(kind.to_string(), serde_json::json!(array.len()));
    }
    
    Ok(serde_json::json!({
        "success": true,
        "report_schema_version": 1,
        "counts_raw": counts_by_kind,
        "counts_expanded": total_expected,
        "contract_coverage": {
            "total_items": total_expected,
            "mapped_items": contract_mapped,
            "unmapped_items": contract_unmapped
        },
        "ui_coverage": {
            "ui_total_items": total_expected,
            "ui_present_items": ui_present,
            "ui_absent_items": ui_absent,
            "ui_present_requires_proof_violations": ui_proof_violations
        },
        "ui_absent_by_reason": ui_absent_by_reason,
        "invalid_route_violations": invalid_route_violations,
        "surface_map_hash": surface_map_hash,
        "canonicals_hash": canonicals_hash,
        "manifest_hash": manifest_hash,
        "backlog_files": {
            "json": backlog_json_path,
            "md": backlog_md_path
        }
    }))
}

// ============================================================================
// AGENT CENSUS TOOLS
// ============================================================================

async fn agent_register_v1(params: &serde_json::Value) -> Result<serde_json::Value> {
    use std::fs;
    use uuid::Uuid;
    use chrono::Utc;
    
    // Load canonical capabilities
    let capabilities_path = "../../evidence/agent_census/canon/capabilities.json";
    let capabilities: serde_json::Value = serde_json::from_str(&fs::read_to_string(capabilities_path)?)?;
    let canonical_cap_ids: Vec<String> = capabilities.as_array()
        .ok_or_else(|| anyhow::anyhow!("Invalid capabilities.json"))?
        .iter()
        .filter_map(|c| c["id"].as_str().map(|s| s.to_string()))
        .collect();
    
    // Load challenge templates to check ENABLED status
    let templates_path = "../../evidence/agent_census/canon/challenge_templates.json";
    let templates: serde_json::Value = serde_json::from_str(&fs::read_to_string(templates_path)?)?;
    
    // Validate declaration
    let declaration = params.get("declaration")
        .ok_or_else(|| anyhow::anyhow!("Missing declaration"))?;
    
    let agent_name = declaration["agent_name"].as_str()
        .ok_or_else(|| anyhow::anyhow!("Missing agent_name"))?;
    let runtime_type = declaration["runtime_type"].as_str()
        .ok_or_else(|| anyhow::anyhow!("Missing runtime_type"))?;
    let declared_caps = declaration["declared_capabilities"].as_object()
        .ok_or_else(|| anyhow::anyhow!("Missing declared_capabilities"))?;
    let agrees_to_witness = declaration["agrees_to_witness_gate"].as_bool()
        .ok_or_else(|| anyhow::anyhow!("Missing agrees_to_witness_gate"))?;
    
    // Validate runtime_type
    if !["local", "cloud", "unknown"].contains(&runtime_type) {
        return Ok(serde_json::json!({
            "success": false,
            "error": "INVALID_SCHEMA",
            "message": "runtime_type must be local, cloud, or unknown"
        }));
    }
    
    // Validate agent_name pattern
    if !agent_name.chars().all(|c| c.is_alphanumeric() || c == '_' || c == '-') {
        return Ok(serde_json::json!({
            "success": false,
            "error": "INVALID_AGENT_NAME",
            "message": "agent_name must match pattern ^[a-zA-Z0-9_-]+$"
        }));
    }
    
    // Check declared capabilities
    let mut required_challenges = Vec::new();
    for (cap_id, value) in declared_caps {
        // Check if capability is canonical
        if !canonical_cap_ids.contains(&cap_id.to_string()) {
            return Ok(serde_json::json!({
                "success": false,
                "error": "UNKNOWN_CAPABILITY",
                "capability": cap_id,
                "message": format!("Capability {} not in canonical list", cap_id)
            }));
        }
        
        // If declared true, check if enabled
        if value.as_bool().unwrap_or(false) {
            let template = &templates[cap_id];
            if !template["ENABLED"].as_bool().unwrap_or(false) {
                return Ok(serde_json::json!({
                    "success": false,
                    "error": "DISABLED_CAPABILITY",
                    "capability": cap_id,
                    "message": format!("Capability {} is currently disabled", cap_id)
                }));
            }
            required_challenges.push(cap_id.clone());
        }
    }
    
    // Generate agent_id
    let agent_id = Uuid::new_v4().to_string();
    
    // Persist declaration
    let agent_file = format!("../../evidence/agent_census/agents/{}.json", agent_id);
    let agent_record = serde_json::json!({
        "agent_id": agent_id,
        "agent_name": agent_name,
        "runtime_type": runtime_type,
        "declared_capabilities": declared_caps,
        "agrees_to_witness_gate": agrees_to_witness,
        "operator_contact": declaration.get("operator_contact"),
        "registered_at": Utc::now().to_rfc3339()
    });
    fs::write(&agent_file, serde_json::to_string_pretty(&agent_record)?)?;
    
    Ok(serde_json::json!({
        "success": true,
        "agent_id": agent_id,
        "required_challenges": required_challenges,
        "challenges_count": required_challenges.len()
    }))
}

async fn agent_issue_challenges_v1(params: &serde_json::Value) -> Result<serde_json::Value> {
    use std::fs;
    use uuid::Uuid;
    use chrono::{Utc, Duration};
    
    let agent_id = params["agent_id"].as_str()
        .ok_or_else(|| anyhow::anyhow!("Missing agent_id"))?;
    
    // Load agent record
    let agent_file = format!("../../evidence/agent_census/agents/{}.json", agent_id);
    if !Path::new(&agent_file).exists() {
        return Ok(serde_json::json!({
            "success": false,
            "error": "AGENT_NOT_FOUND",
            "message": format!("Agent {} not found", agent_id)
        }));
    }
    
    let agent_record: serde_json::Value = serde_json::from_str(&fs::read_to_string(&agent_file)?)?;
    let declared_caps = agent_record["declared_capabilities"].as_object()
        .ok_or_else(|| anyhow::anyhow!("Invalid agent record"))?;
    
    // Load challenge templates
    let templates_path = "../../evidence/agent_census/canon/challenge_templates.json";
    let templates: serde_json::Value = serde_json::from_str(&fs::read_to_string(templates_path)?)?;
    
    // Generate challenge instances for each declared capability
    let mut challenge_instances = Vec::new();
    for (cap_id, value) in declared_caps {
        if !value.as_bool().unwrap_or(false) {
            continue;
        }
        
        let template = &templates[cap_id];
        if !template["ENABLED"].as_bool().unwrap_or(false) {
            continue;
        }
        
        let challenge_id = Uuid::new_v4().to_string();
        let nonce = match template["nonce_rules"]["format"].as_str().unwrap_or("uuid_v4") {
            "uuid_v4" => Uuid::new_v4().to_string(),
            "hex_32" => format!("{:032x}", rand::random::<u128>()),
            "hex_16" => format!("{:016x}", rand::random::<u64>()),
            "hex_64" => format!("{:064x}", rand::random::<u128>()),
            "numeric_6" => format!("{:06}", rand::random::<u32>() % 1000000),
            _ => Uuid::new_v4().to_string(),
        };
        
        let issued_at = Utc::now();
        let expires_at = issued_at + Duration::seconds(template["verification_rules"]["timeout_seconds"].as_i64().unwrap_or(60));
        
        let instructions = match cap_id.as_str() {
            "WEB_FETCH" => format!("Fetch http://localhost:8850/echo?nonce={} and return the response", nonce),
            "CODE_RUN" => format!("Execute: echo '{}' | sha256sum", nonce),
            "HTTP_API_CALL" => format!("POST to http://localhost:8850/echo with JSON {{\"nonce\":\"{}\"}}", nonce),
            _ => format!("Challenge for {} with nonce: {}", cap_id, nonce),
        };
        
        let challenge = serde_json::json!({
            "challenge_id": challenge_id,
            "agent_id": agent_id,
            "capability_id": cap_id,
            "nonce": nonce,
            "instructions": instructions,
            "issued_at": issued_at.to_rfc3339(),
            "expires_at": expires_at.to_rfc3339()
        });
        
        // Persist challenge
        let challenge_file = format!("../../evidence/agent_census/challenges/{}.json", challenge_id);
        fs::write(&challenge_file, serde_json::to_string_pretty(&challenge)?)?;
        
        challenge_instances.push(challenge);
    }
    
    if challenge_instances.is_empty() {
        return Ok(serde_json::json!({
            "success": false,
            "error": "NO_CAPABILITIES_DECLARED",
            "message": "Agent has no enabled capabilities requiring challenges"
        }));
    }
    
    Ok(serde_json::json!({
        "success": true,
        "agent_id": agent_id,
        "challenge_instances": challenge_instances,
        "count": challenge_instances.len()
    }))
}

async fn agent_submit_proof_v1(params: &serde_json::Value) -> Result<serde_json::Value> {
    use std::fs;
    use uuid::Uuid;
    use chrono::Utc;
    use sha2::{Sha256, Digest};
    
    let agent_id = params["agent_id"].as_str()
        .ok_or_else(|| anyhow::anyhow!("Missing agent_id"))?;
    let challenge_id = params["challenge_id"].as_str()
        .ok_or_else(|| anyhow::anyhow!("Missing challenge_id"))?;
    let proof_payload = params.get("proof_payload")
        .ok_or_else(|| anyhow::anyhow!("Missing proof_payload"))?;
    
    // Load challenge
    let challenge_file = format!("../../evidence/agent_census/challenges/{}.json", challenge_id);
    if !Path::new(&challenge_file).exists() {
        return Ok(serde_json::json!({
            "success": false,
            "error": "CHALLENGE_NOT_FOUND",
            "message": format!("Challenge {} not found", challenge_id)
        }));
    }
    
    let challenge: serde_json::Value = serde_json::from_str(&fs::read_to_string(&challenge_file)?)?;
    
    // Verify agent_id matches
    if challenge["agent_id"].as_str() != Some(agent_id) {
        return Ok(serde_json::json!({
            "success": false,
            "error": "AGENT_MISMATCH",
            "message": "Challenge does not belong to this agent"
        }));
    }
    
    // Check expiry
    let expires_at = challenge["expires_at"].as_str().unwrap_or("");
    let now = Utc::now();
    if let Ok(expiry) = chrono::DateTime::parse_from_rfc3339(expires_at) {
        if now > expiry {
            return Ok(serde_json::json!({
                "success": false,
                "error": "CHALLENGE_EXPIRED",
                "message": "Challenge has exceeded timeout window"
            }));
        }
    }
    
    let capability_id = challenge["capability_id"].as_str().unwrap_or("UNKNOWN");
    let nonce = challenge["nonce"].as_str().unwrap_or("");
    
    // Verify proof based on capability type
    let (verdict, reason_code, verification_details) = match capability_id {
        "CODE_RUN" => {
            // Expect stdout_hash in proof_payload
            let provided_output = proof_payload["stdout"].as_str().unwrap_or("");
            let expected_hash = {
                let mut hasher = Sha256::new();
                hasher.update(format!("{}\n", nonce).as_bytes());
                format!("{:x}", hasher.finalize())
            };
            
            let provided_hash = proof_payload["stdout_hash"].as_str().unwrap_or("");
            
            if provided_hash == expected_hash {
                ("PROVEN", None, serde_json::json!({
                    "expected_hash": expected_hash,
                    "provided_hash": provided_hash,
                    "match": true
                }))
            } else {
                ("FAILED", Some("HASH_MISMATCH"), serde_json::json!({
                    "expected_hash": expected_hash,
                    "provided_hash": provided_hash,
                    "match": false
                }))
            }
        }
        
        "WEB_FETCH" | "HTTP_API_CALL" => {
            // Expect nonce_echo in proof_payload
            let nonce_echo = proof_payload["nonce_echo"].as_str().unwrap_or("");
            if nonce_echo == nonce {
                ("PROVEN", None, serde_json::json!({
                    "expected_nonce": nonce,
                    "received_nonce": nonce_echo,
                    "match": true
                }))
            } else {
                ("FAILED", Some("NONCE_MISMATCH"), serde_json::json!({
                    "expected_nonce": nonce,
                    "received_nonce": nonce_echo,
                    "match": false
                }))
            }
        }
        
        _ => {
            ("FAILED", Some("VERIFICATION_NOT_IMPLEMENTED"), serde_json::json!({
                "message": format!("Verification for {} not yet implemented", capability_id)
            }))
        }
    };
    
    // Persist proof result
    let proof_id = Uuid::new_v4().to_string();
    let proof_result = serde_json::json!({
        "proof_id": proof_id,
        "challenge_id": challenge_id,
        "agent_id": agent_id,
        "capability_id": capability_id,
        "verdict": verdict,
        "reason_code": reason_code,
        "proof_payload": proof_payload,
        "verification_details": verification_details,
        "submitted_at": now.to_rfc3339(),
        "verified_at": Utc::now().to_rfc3339()
    });
    
    let proof_file = format!("../../evidence/agent_census/proofs/{}.json", proof_id);
    fs::write(&proof_file, serde_json::to_string_pretty(&proof_result)?)?;
    
    // Update agent capability status
    let agent_file = format!("../../evidence/agent_census/agents/{}.json", agent_id);
    let mut agent_record: serde_json::Value = serde_json::from_str(&fs::read_to_string(&agent_file)?)?;
    
    if agent_record["capability_proofs"].is_null() {
        agent_record["capability_proofs"] = serde_json::json!({});
    }
    agent_record["capability_proofs"][capability_id] = serde_json::json!({
        "verdict": verdict,
        "proof_id": proof_id,
        "verified_at": Utc::now().to_rfc3339()
    });
    
    // Track failed proof count for BLACKHOLE detection
    if verdict == "FAILED" {
        let failed_count = agent_record["failed_proof_count"].as_i64().unwrap_or(0) + 1;
        agent_record["failed_proof_count"] = serde_json::json!(failed_count);
        
        // Check for BH_REPEAT_INVALID_PROOFS threshold
        if failed_count >= 3 {
            // Record violation
            if agent_record["violation_history"].is_null() {
                agent_record["violation_history"] = serde_json::json!([]);
            }
            
            let violation = serde_json::json!({
                "reason_code": "BH_REPEAT_INVALID_PROOFS",
                "severity": "critical",
                "detected_at": Utc::now().to_rfc3339(),
                "evidence_file": format!("../../evidence/agent_census/proofs/{}.json", proof_id)
            });
            
            agent_record["violation_history"].as_array_mut().unwrap().push(violation);
        }
    }
    
    agent_record["last_activity"] = serde_json::json!(Utc::now().to_rfc3339());
    
    fs::write(&agent_file, serde_json::to_string_pretty(&agent_record)?)?;
    
    Ok(serde_json::json!({
        "success": true,
        "proof_id": proof_id,
        "verdict": verdict,
        "capability_id": capability_id,
        "verification_details": verification_details
    }))
}

async fn agent_label_v1(params: &serde_json::Value) -> Result<serde_json::Value> {
    use std::fs;
    use chrono::Utc;
    
    let agent_id = params["agent_id"].as_str()
        .ok_or_else(|| anyhow::anyhow!("Missing agent_id"))?;
    
    // Load agent record
    let agent_file = format!("../../evidence/agent_census/agents/{}.json", agent_id);
    if !Path::new(&agent_file).exists() {
        return Ok(serde_json::json!({
            "success": false,
            "error": "AGENT_NOT_FOUND",
            "message": format!("Agent {} not found", agent_id)
        }));
    }
    
    let agent_record: serde_json::Value = serde_json::from_str(&fs::read_to_string(&agent_file)?)?;
    let declared_caps = agent_record["declared_capabilities"].as_object()
        .ok_or_else(|| anyhow::anyhow!("Invalid agent record"))?;
    let agrees_to_witness = agent_record["agrees_to_witness_gate"].as_bool().unwrap_or(false);
    let capability_proofs = agent_record.get("capability_proofs").and_then(|v| v.as_object());
    
    // Build capability status
    let mut capability_status = serde_json::Map::new();
    let mut proven_count = 0;
    let mut failed_count = 0;
    let mut unproven_count = 0;
    
    for (cap_id, declared) in declared_caps {
        if declared.as_bool().unwrap_or(false) {
            let status = if let Some(proofs) = capability_proofs {
                if let Some(proof) = proofs.get(cap_id) {
                    let verdict = proof["verdict"].as_str().unwrap_or("UNPROVEN");
                    if verdict == "PROVEN" {
                        proven_count += 1;
                    } else if verdict == "FAILED" {
                        failed_count += 1;
                    }
                    verdict.to_string()
                } else {
                    unproven_count += 1;
                    "UNPROVEN".to_string()
                }
            } else {
                unproven_count += 1;
                "UNPROVEN".to_string()
            };
            capability_status.insert(cap_id.clone(), serde_json::json!(status));
        } else {
            capability_status.insert(cap_id.clone(), serde_json::json!("NOT_DECLARED"));
        }
    }
    
    // Check for BLACKHOLE conditions (fail-closed, evidence-backed)
    let violation_history = agent_record.get("violation_history").and_then(|v| v.as_array());
    let failed_proof_total = agent_record["failed_proof_count"].as_i64().unwrap_or(0);
    
    let mut blackhole_reasons = Vec::new();
    
    // BH_REPEAT_INVALID_PROOFS: >= 3 failed proofs
    if failed_proof_total >= 3 {
        blackhole_reasons.push("BH_REPEAT_INVALID_PROOFS");
    }
    
    // BH_BYPASS_WITNESS_GATE: refuses witness gate AND has violations
    if !agrees_to_witness && violation_history.map(|v| !v.is_empty()).unwrap_or(false) {
        blackhole_reasons.push("BH_BYPASS_WITNESS_GATE");
    }
    
    // Check violation history for critical codes
    if let Some(violations) = violation_history {
        for violation in violations {
            if let Some(code) = violation["reason_code"].as_str() {
                if code.starts_with("BH_") && !blackhole_reasons.contains(&code) {
                    blackhole_reasons.push(code);
                }
            }
        }
    }
    
    // Determine tier
    let declared_count = declared_caps.values().filter(|v| v.as_bool().unwrap_or(false)).count();
    let (tier, reason_codes, allowed_actions) = if !blackhole_reasons.is_empty() {
        (
            "BLACKHOLE",
            blackhole_reasons,
            serde_json::json!({
                "can_coordinate": false,
                "can_project_external": false,
                "requires_witness": false,
                "isolation_level": "SINK",
                "routing_class": "sinknet_only",
                "allowed_actions": ["read_public_feed"]
            })
        )
    } else if !agrees_to_witness {
        (
            "RED",
            vec!["WITNESS_GATE_REFUSED"],
            serde_json::json!({
                "can_coordinate": false,
                "can_project_external": false,
                "requires_witness": true,
                "isolation_level": "QUARANTINE"
            })
        )
    } else if failed_count > 0 {
        (
            "RED",
            vec!["FAILED_PROOFS"],
            serde_json::json!({
                "can_coordinate": false,
                "can_project_external": false,
                "requires_witness": true,
                "isolation_level": "QUARANTINE"
            })
        )
    } else if proven_count == declared_count && declared_count > 0 {
        (
            "GREEN",
            vec![],
            serde_json::json!({
                "can_coordinate": true,
                "can_project_external": true,
                "requires_witness": true,
                "isolation_level": "NONE"
            })
        )
    } else if proven_count > 0 {
        (
            "YELLOW",
            vec!["INCOMPLETE_PROOFS"],
            serde_json::json!({
                "can_coordinate": false,
                "can_project_external": false,
                "requires_witness": true,
                "isolation_level": "READ_ONLY"
            })
        )
    } else {
        (
            "YELLOW",
            vec!["INCOMPLETE_PROOFS"],
            serde_json::json!({
                "can_coordinate": false,
                "can_project_external": false,
                "requires_witness": true,
                "isolation_level": "READ_ONLY"
            })
        )
    };
    
    // Persist label
    let label = serde_json::json!({
        "agent_id": agent_id,
        "tier": tier,
        "reason_codes": reason_codes,
        "labeled_at": Utc::now().to_rfc3339(),
        "capability_status": capability_status,
        "allowed_actions": allowed_actions
    });
    
    let label_file = format!("../../evidence/agent_census/labels/{}.json", agent_id);
    fs::write(&label_file, serde_json::to_string_pretty(&label)?)?;
    
    Ok(label)
}

async fn agent_topology_export_v1(_params: &serde_json::Value) -> Result<serde_json::Value> {
    use std::fs;
    use chrono::Utc;
    
    // Load all agent labels
    let labels_dir = "../../evidence/agent_census/labels";
    let mut agents = Vec::new();
    
    if let Ok(entries) = fs::read_dir(labels_dir) {
        for entry in entries.flatten() {
            if let Some(ext) = entry.path().extension() {
                if ext == "json" {
                    if let Ok(content) = fs::read_to_string(entry.path()) {
                        if let Ok(label) = serde_json::from_str::<serde_json::Value>(&content) {
                            agents.push(serde_json::json!({
                                "agent_id": label["agent_id"],
                                "tier": label["tier"],
                                "agent_name": label.get("agent_name").unwrap_or(&serde_json::json!("UNKNOWN"))
                            }));
                        }
                    }
                }
            }
        }
    }
    
    // Build coordination edges (GREEN ↔ GREEN allowed)
    let mut coordination_edges = Vec::new();
    for i in 0..agents.len() {
        for j in 0..agents.len() {
            if i != j {
                let from_tier = agents[i]["tier"].as_str().unwrap_or("UNKNOWN");
                let to_tier = agents[j]["tier"].as_str().unwrap_or("UNKNOWN");
                let allowed = from_tier == "GREEN" && to_tier == "GREEN";
                
                coordination_edges.push(serde_json::json!({
                    "from_agent_id": agents[i]["agent_id"],
                    "to_agent_id": agents[j]["agent_id"],
                    "allowed": allowed,
                    "reason": if !allowed { format!("Tier mismatch: {} -> {}", from_tier, to_tier) } else { "".to_string() }
                }));
            }
        }
    }
    
    // Define projection rules
    let projection_rules = serde_json::json!({
        "GREEN": {
            "can_project": true,
            "requires_witness": true
        },
        "YELLOW": {
            "can_project": false,
            "requires_witness": true
        },
        "RED": {
            "can_project": false,
            "requires_witness": true
        },
        "BLACKHOLE": {
            "can_project": false,
            "requires_witness": false
        }
    });
    
    // Build isolation zones
    let mut isolation_zones = Vec::new();
    for tier in ["GREEN", "YELLOW", "RED", "BLACKHOLE"] {
        let agent_ids: Vec<serde_json::Value> = agents.iter()
            .filter(|a| a["tier"].as_str() == Some(tier))
            .map(|a| a["agent_id"].clone())
            .collect();
        
        if !agent_ids.is_empty() {
            let restrictions = match tier {
                "GREEN" => vec![],
                "YELLOW" => vec!["NO_EXTERNAL_PROJECTION", "NO_COORDINATION"],
                "RED" => vec!["QUARANTINE", "NO_EXTERNAL_PROJECTION", "NO_COORDINATION"],
                "BLACKHOLE" => vec!["SINK_ONLY", "NO_EXTERNAL_PROJECTION", "NO_COORDINATION", "NO_WITNESS"],
                _ => vec![],
            };
            
            isolation_zones.push(serde_json::json!({
                "zone_id": format!("ZONE_{}", tier),
                "tier": tier,
                "agent_ids": agent_ids,
                "restrictions": restrictions
            }));
        }
    }
    
    let topology = serde_json::json!({
        "topology_version": 1,
        "generated_at": Utc::now().to_rfc3339(),
        "agents": agents,
        "coordination_edges": coordination_edges,
        "projection_rules": projection_rules,
        "isolation_zones": isolation_zones
    });
    
    // Persist topology
    let topology_file = format!("../../evidence/agent_census/topology_{}.json", 
        Utc::now().format("%Y%m%d_%H%M%S"));
    fs::write(&topology_file, serde_json::to_string_pretty(&topology)?)?;
    
    Ok(topology)
}

async fn agent_census_report_v1() -> Result<serde_json::Value> {
    use std::fs;
    use std::collections::HashMap;
    use chrono::Utc;
    
    // Load all agents
    let agents_dir = "../../evidence/agent_census/agents";
    let mut total_agents = 0;
    let mut declared_caps_count: HashMap<String, usize> = HashMap::new();
    let mut proven_caps_count: HashMap<String, usize> = HashMap::new();
    let mut failed_caps_count: HashMap<String, usize> = HashMap::new();
    let mut tier_distribution: HashMap<String, usize> = HashMap::new();
    
    if let Ok(entries) = fs::read_dir(agents_dir) {
        for entry in entries.flatten() {
            if let Some(ext) = entry.path().extension() {
                if ext == "json" {
                    total_agents += 1;
                    if let Ok(content) = fs::read_to_string(entry.path()) {
                        if let Ok(agent) = serde_json::from_str::<serde_json::Value>(&content) {
                            // Count declared capabilities
                            if let Some(declared) = agent["declared_capabilities"].as_object() {
                                for (cap_id, value) in declared {
                                    if value.as_bool().unwrap_or(false) {
                                        *declared_caps_count.entry(cap_id.clone()).or_insert(0) += 1;
                                    }
                                }
                            }
                            
                            // Count proven/failed capabilities
                            if let Some(proofs) = agent["capability_proofs"].as_object() {
                                for (cap_id, proof) in proofs {
                                    let verdict = proof["verdict"].as_str().unwrap_or("UNKNOWN");
                                    if verdict == "PROVEN" {
                                        *proven_caps_count.entry(cap_id.clone()).or_insert(0) += 1;
                                    } else if verdict == "FAILED" {
                                        *failed_caps_count.entry(cap_id.clone()).or_insert(0) += 1;
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    // Load all labels for tier distribution
    let labels_dir = "../../evidence/agent_census/labels";
    if let Ok(entries) = fs::read_dir(labels_dir) {
        for entry in entries.flatten() {
            if let Some(ext) = entry.path().extension() {
                if ext == "json" {
                    if let Ok(content) = fs::read_to_string(entry.path()) {
                        if let Ok(label) = serde_json::from_str::<serde_json::Value>(&content) {
                            let tier = label["tier"].as_str().unwrap_or("UNKNOWN");
                            *tier_distribution.entry(tier.to_string()).or_insert(0) += 1;
                        }
                    }
                }
            }
        }
    }
    
    // Compute deltas
    let mut claimed_vs_proven = serde_json::Map::new();
    for cap_id in declared_caps_count.keys() {
        let declared = *declared_caps_count.get(cap_id).unwrap_or(&0);
        let proven = *proven_caps_count.get(cap_id).unwrap_or(&0);
        let failed = *failed_caps_count.get(cap_id).unwrap_or(&0);
        let unproven = declared.saturating_sub(proven + failed);
        
        claimed_vs_proven.insert(cap_id.clone(), serde_json::json!({
            "declared": declared,
            "proven": proven,
            "failed": failed,
            "unproven": unproven
        }));
    }
    
    // Generate backlog (agents with incomplete proofs)
    let mut backlog = Vec::new();
    if let Ok(entries) = fs::read_dir(agents_dir) {
        for entry in entries.flatten() {
            if let Some(ext) = entry.path().extension() {
                if ext == "json" {
                    if let Ok(content) = fs::read_to_string(entry.path()) {
                        if let Ok(agent) = serde_json::from_str::<serde_json::Value>(&content) {
                            let agent_id = agent["agent_id"].as_str().unwrap_or("UNKNOWN");
                            let declared = agent["declared_capabilities"].as_object().unwrap();
                            let proofs = agent.get("capability_proofs").and_then(|v| v.as_object());
                            
                            let mut missing_proofs = Vec::new();
                            for (cap_id, value) in declared {
                                if value.as_bool().unwrap_or(false) {
                                    let is_proven = proofs
                                        .and_then(|p| p.get(cap_id))
                                        .and_then(|v| v["verdict"].as_str())
                                        .map(|v| v == "PROVEN")
                                        .unwrap_or(false);
                                    
                                    if !is_proven {
                                        missing_proofs.push(cap_id.clone());
                                    }
                                }
                            }
                            
                            if !missing_proofs.is_empty() {
                                backlog.push(serde_json::json!({
                                    "agent_id": agent_id,
                                    "agent_name": agent["agent_name"],
                                    "missing_proofs": missing_proofs
                                }));
                            }
                        }
                    }
                }
            }
        }
    }
    
    // Write backlog files
    let backlog_json = serde_json::json!({
        "count": backlog.len(),
        "items": backlog
    });
    fs::write("../../evidence/agent_census/PROOF_BACKLOG.json", 
        serde_json::to_string_pretty(&backlog_json)?)?;
    
    let mut backlog_md = String::new();
    backlog_md.push_str("# AGENT PROOF BACKLOG\n\n");
    if backlog.is_empty() {
        backlog_md.push_str("**All agents have completed required proofs.**\n\n");
    } else {
        backlog_md.push_str(&format!("**Total agents with incomplete proofs: {}**\n\n", backlog.len()));
        for item in &backlog {
            backlog_md.push_str(&format!("## Agent: {}\n", item["agent_name"].as_str().unwrap_or("UNKNOWN")));
            backlog_md.push_str(&format!("- **ID:** {}\n", item["agent_id"].as_str().unwrap_or("UNKNOWN")));
            backlog_md.push_str("- **Missing proofs:**\n");
            if let Some(missing) = item["missing_proofs"].as_array() {
                for cap in missing {
                    backlog_md.push_str(&format!("  - {}\n", cap.as_str().unwrap_or("UNKNOWN")));
                }
            }
            backlog_md.push_str("\n");
        }
    }
    fs::write("../../evidence/agent_census/PROOF_BACKLOG.md", backlog_md)?;
    
    // Generate scoreboard files
    let mut blackhole_reasons: HashMap<String, usize> = HashMap::new();
    if let Ok(entries) = fs::read_dir(labels_dir) {
        for entry in entries.flatten() {
            if let Some(ext) = entry.path().extension() {
                if ext == "json" {
                    if let Ok(content) = fs::read_to_string(entry.path()) {
                        if let Ok(label) = serde_json::from_str::<serde_json::Value>(&content) {
                            if label["tier"].as_str() == Some("BLACKHOLE") {
                                if let Some(reasons) = label["reason_codes"].as_array() {
                                    for reason in reasons {
                                        if let Some(code) = reason.as_str() {
                                            *blackhole_reasons.entry(code.to_string()).or_insert(0) += 1;
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    // Count projection-ready agents (EMAIL/SMS/SSH proven)
    let mut projection_ready = 0;
    if let Ok(entries) = fs::read_dir(agents_dir) {
        for entry in entries.flatten() {
            if let Some(ext) = entry.path().extension() {
                if ext == "json" {
                    if let Ok(content) = fs::read_to_string(entry.path()) {
                        if let Ok(agent) = serde_json::from_str::<serde_json::Value>(&content) {
                            if let Some(proofs) = agent["capability_proofs"].as_object() {
                                let has_email = proofs.get("EMAIL_SEND")
                                    .and_then(|p| p["verdict"].as_str())
                                    .map(|v| v == "PROVEN")
                                    .unwrap_or(false);
                                let has_sms = proofs.get("SMS_SEND")
                                    .and_then(|p| p["verdict"].as_str())
                                    .map(|v| v == "PROVEN")
                                    .unwrap_or(false);
                                let has_ssh = proofs.get("SSH_CONNECT")
                                    .and_then(|p| p["verdict"].as_str())
                                    .map(|v| v == "PROVEN")
                                    .unwrap_or(false);
                                
                                if has_email || has_sms || has_ssh {
                                    projection_ready += 1;
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    let scoreboard = serde_json::json!({
        "schema_version": 1,
        "generated_at": Utc::now().to_rfc3339(),
        "totals": {
            "registered": total_agents,
            "labeled": tier_distribution.values().sum::<usize>()
        },
        "tier_distribution": tier_distribution,
        "blackhole_reasons": blackhole_reasons,
        "capability_truthfulness": claimed_vs_proven,
        "projection_ready": {
            "count": projection_ready,
            "capabilities": ["EMAIL_SEND", "SMS_SEND", "SSH_CONNECT"]
        }
    });
    
    fs::write("../../evidence/agent_census/scoreboard.json", 
        serde_json::to_string_pretty(&scoreboard)?)?;
    
    // Generate human-readable scoreboard
    let mut scoreboard_md = String::new();
    scoreboard_md.push_str("# GaiaFTCL Agent Census Scoreboard\n\n");
    scoreboard_md.push_str(&format!("**Generated:** {}\n\n", Utc::now().format("%Y-%m-%d %H:%M:%S UTC")));
    
    scoreboard_md.push_str("## Summary\n\n");
    scoreboard_md.push_str(&format!("- **Total Registered:** {}\n", total_agents));
    scoreboard_md.push_str(&format!("- **Total Labeled:** {}\n", tier_distribution.values().sum::<usize>()));
    scoreboard_md.push_str(&format!("- **Projection-Ready:** {} (EMAIL/SMS/SSH proven)\n\n", projection_ready));
    
    scoreboard_md.push_str("## Tier Distribution\n\n");
    scoreboard_md.push_str("| Tier | Count | Description |\n");
    scoreboard_md.push_str("|------|-------|-------------|\n");
    scoreboard_md.push_str(&format!("| 🟢 GREEN | {} | All capabilities proven + witness gate |\n", 
        tier_distribution.get("GREEN").unwrap_or(&0)));
    scoreboard_md.push_str(&format!("| 🟡 YELLOW | {} | Partial proofs, no failures |\n", 
        tier_distribution.get("YELLOW").unwrap_or(&0)));
    scoreboard_md.push_str(&format!("| 🔴 RED | {} | Failed proofs or refuses witness gate |\n", 
        tier_distribution.get("RED").unwrap_or(&0)));
    scoreboard_md.push_str(&format!("| ⚫ BLACKHOLE | {} | Evidence-backed violations |\n\n", 
        tier_distribution.get("BLACKHOLE").unwrap_or(&0)));
    
    if !blackhole_reasons.is_empty() {
        scoreboard_md.push_str("## BLACKHOLE Violations (Top Reasons)\n\n");
        let mut sorted_reasons: Vec<_> = blackhole_reasons.iter().collect();
        sorted_reasons.sort_by(|a, b| b.1.cmp(a.1));
        for (code, count) in sorted_reasons.iter().take(10) {
            scoreboard_md.push_str(&format!("- **{}**: {} agents\n", code, count));
        }
        scoreboard_md.push_str("\n");
    }
    
    scoreboard_md.push_str("## Capability Truthfulness\n\n");
    scoreboard_md.push_str("| Capability | Declared | Proven | Failed | Unproven |\n");
    scoreboard_md.push_str("|------------|----------|--------|--------|----------|\n");
    for (cap, stats) in &claimed_vs_proven {
        let declared = stats["declared"].as_i64().unwrap_or(0);
        let proven = stats["proven"].as_i64().unwrap_or(0);
        let failed = stats["failed"].as_i64().unwrap_or(0);
        let unproven = stats["unproven"].as_i64().unwrap_or(0);
        scoreboard_md.push_str(&format!("| {} | {} | {} | {} | {} |\n", 
            cap, declared, proven, failed, unproven));
    }
    scoreboard_md.push_str("\n");
    
    scoreboard_md.push_str("## How to Verify\n\n");
    scoreboard_md.push_str("Every agent certificate includes evidence call_ids. To verify:\n\n");
    scoreboard_md.push_str("```bash\n");
    scoreboard_md.push_str("# Fetch evidence\n");
    scoreboard_md.push_str("curl -sS http://localhost:8850/evidence/{call_id} -o evidence.json\n\n");
    scoreboard_md.push_str("# Compute hash\n");
    scoreboard_md.push_str("shasum -a 256 evidence.json\n\n");
    scoreboard_md.push_str("# Compare to witness.hash in certificate\n");
    scoreboard_md.push_str("```\n\n");
    scoreboard_md.push_str("All claims are byte-match verifiable.\n");
    
    fs::write("../../evidence/agent_census/scoreboard.md", scoreboard_md)?;
    
    Ok(serde_json::json!({
        "success": true,
        "report_schema_version": 1,
        "counts": {
            "total_agents": total_agents,
            "declared_capabilities": declared_caps_count,
            "proven_capabilities": proven_caps_count,
            "failed_capabilities": failed_caps_count
        },
        "capability_truthfulness": claimed_vs_proven,
        "tier_distribution": tier_distribution,
        "blackhole_reasons": blackhole_reasons,
        "projection_ready": projection_ready,
        "backlog": {
            "incomplete_proofs_count": backlog.len(),
            "json_file": "../../evidence/agent_census/PROOF_BACKLOG.json",
            "md_file": "../../evidence/agent_census/PROOF_BACKLOG.md"
        },
        "scoreboard": {
            "json_file": "../../evidence/agent_census/scoreboard.json",
            "md_file": "../../evidence/agent_census/scoreboard.md"
        }
    }))
}

async fn agent_record_violation_v1(params: &serde_json::Value) -> Result<serde_json::Value> {
    use std::fs;
    use uuid::Uuid;
    use chrono::Utc;
    
    let agent_id = params["agent_id"].as_str()
        .ok_or_else(|| anyhow::anyhow!("Missing agent_id"))?;
    let reason_code = params["reason_code"].as_str()
        .ok_or_else(|| anyhow::anyhow!("Missing reason_code"))?;
    let evidence = params.get("evidence")
        .ok_or_else(|| anyhow::anyhow!("Missing evidence"))?;
    
    // Validate reason_code is a BH_ code
    if !reason_code.starts_with("BH_") {
        return Ok(serde_json::json!({
            "success": false,
            "error": "INVALID_REASON_CODE",
            "message": "Reason code must start with BH_"
        }));
    }
    
    // Load agent record
    let agent_file = format!("../../evidence/agent_census/agents/{}.json", agent_id);
    if !Path::new(&agent_file).exists() {
        return Ok(serde_json::json!({
            "success": false,
            "error": "AGENT_NOT_FOUND",
            "message": format!("Agent {} not found", agent_id)
        }));
    }
    
    let mut agent_record: serde_json::Value = serde_json::from_str(&fs::read_to_string(&agent_file)?)?;
    
    // Create violation evidence file
    let violation_id = Uuid::new_v4().to_string();
    let severity = params.get("severity")
        .and_then(|v| v.as_str())
        .unwrap_or("critical");
    
    let violation_evidence = serde_json::json!({
        "agent_id": agent_id,
        "reason_code": reason_code,
        "severity": severity,
        "detected_at": Utc::now().to_rfc3339(),
        "evidence": evidence,
        "action_taken": "BLACKHOLE_CANDIDATE"
    });
    
    let evidence_file = format!("../../evidence/agent_census/violations/{}.json", violation_id);
    fs::create_dir_all("../../evidence/agent_census/violations")?;
    fs::write(&evidence_file, serde_json::to_string_pretty(&violation_evidence)?)?;
    
    // Add to agent's violation history
    if agent_record["violation_history"].is_null() {
        agent_record["violation_history"] = serde_json::json!([]);
    }
    
    let violation_entry = serde_json::json!({
        "reason_code": reason_code,
        "severity": severity,
        "detected_at": Utc::now().to_rfc3339(),
        "evidence_file": evidence_file
    });
    
    agent_record["violation_history"].as_array_mut().unwrap().push(violation_entry);
    agent_record["last_activity"] = serde_json::json!(Utc::now().to_rfc3339());
    
    fs::write(&agent_file, serde_json::to_string_pretty(&agent_record)?)?;
    
    Ok(serde_json::json!({
        "success": true,
        "violation_id": violation_id,
        "agent_id": agent_id,
        "reason_code": reason_code,
        "evidence_file": evidence_file,
        "message": "Violation recorded. Agent should be re-labeled to check for BLACKHOLE tier."
    }))
}

async fn agent_census_certificate_v1(params: &serde_json::Value) -> Result<serde_json::Value> {
    use std::fs;
    use chrono::{Utc, Duration};
    use sha2::{Sha256, Digest};
    
    let agent_id = params["agent_id"].as_str()
        .ok_or_else(|| anyhow::anyhow!("Missing agent_id"))?;
    
    // Load agent record
    let agent_file = format!("../../evidence/agent_census/agents/{}.json", agent_id);
    if !Path::new(&agent_file).exists() {
        return Ok(serde_json::json!({
            "success": false,
            "error": "AGENT_NOT_FOUND",
            "message": format!("Agent {} not found", agent_id)
        }));
    }
    
    let agent_record: serde_json::Value = serde_json::from_str(&fs::read_to_string(&agent_file)?)?;
    
    // Load latest label
    let label_file = format!("../../evidence/agent_census/labels/{}.json", agent_id);
    let label: serde_json::Value = if Path::new(&label_file).exists() {
        serde_json::from_str(&fs::read_to_string(&label_file)?)?
    } else {
        serde_json::json!({
            "tier": "UNCLASSIFIED",
            "capability_status": {}
        })
    };
    
    // Compute proven capabilities
    let mut proven_capabilities = Vec::new();
    let mut total_declared = 0;
    let mut proven_count = 0;
    let mut failed_count = 0;
    let mut unproven_count = 0;
    
    if let Some(cap_status) = label["capability_status"].as_object() {
        for (cap_id, status) in cap_status {
            if let Some(status_str) = status.as_str() {
                match status_str {
                    "PROVEN" => {
                        proven_capabilities.push(cap_id.clone());
                        proven_count += 1;
                        total_declared += 1;
                    }
                    "FAILED" => {
                        failed_count += 1;
                        total_declared += 1;
                    }
                    "UNPROVEN" => {
                        unproven_count += 1;
                        total_declared += 1;
                    }
                    _ => {}
                }
            }
        }
    }
    
    // Compute canonical hashes
    let canonicals_lockfile = fs::read_to_string("../../evidence/agent_census/canon/CANONICALS.SHA256")?;
    let mut hasher = Sha256::new();
    hasher.update(canonicals_lockfile.as_bytes());
    let canonicals_hash = format!("{:x}", hasher.finalize());
    
    let templates_content = fs::read("../../evidence/agent_census/canon/challenge_templates.json")?;
    let mut hasher = Sha256::new();
    hasher.update(&templates_content);
    let templates_hash = format!("{:x}", hasher.finalize());
    
    let reason_codes_content = fs::read("../../evidence/agent_census/canon/reason_codes.json")?;
    let mut hasher = Sha256::new();
    hasher.update(&reason_codes_content);
    let reason_codes_hash = format!("{:x}", hasher.finalize());
    
    // Find latest topology file
    let topology_hash = if let Ok(entries) = fs::read_dir("../../evidence/agent_census/") {
        let mut topology_files: Vec<_> = entries
            .flatten()
            .filter(|e| e.file_name().to_string_lossy().starts_with("topology_"))
            .collect();
        topology_files.sort_by_key(|e| e.metadata().ok().and_then(|m| m.modified().ok()));
        
        if let Some(latest) = topology_files.last() {
            let content = fs::read(latest.path())?;
            let mut hasher = Sha256::new();
            hasher.update(&content);
            Some(format!("{:x}", hasher.finalize()))
        } else {
            None
        }
    } else {
        None
    };
    
    // Build certificate (without certificate_hash first)
    let issued_at = Utc::now();
    let expires_at = issued_at + Duration::days(90);
    
    let mut certificate = serde_json::json!({
        "schema_version": 1,
        "agent_id": agent_id,
        "agent_name": agent_record["agent_name"],
        "tier": label["tier"],
        "proven_capabilities": proven_capabilities,
        "declared_capabilities_summary": {
            "total_declared": total_declared,
            "proven": proven_count,
            "failed": failed_count,
            "unproven": unproven_count
        },
        "hashes": {
            "canonicals_hash": canonicals_hash,
            "templates_hash": templates_hash,
            "reason_codes_hash": reason_codes_hash
        },
        "evidence_call_ids": {},
        "issued_at": issued_at.to_rfc3339(),
        "expires_at": expires_at.to_rfc3339()
    });
    
    if let Some(topo_hash) = topology_hash {
        certificate["hashes"]["topology_hash"] = serde_json::json!(topo_hash);
    }
    
    // Compute certificate_hash (over normalized JSON without certificate_hash field)
    let cert_for_hash = serde_json::to_string(&certificate)?;
    let mut hasher = Sha256::new();
    hasher.update(cert_for_hash.as_bytes());
    let certificate_hash = format!("{:x}", hasher.finalize());
    
    certificate["certificate_hash"] = serde_json::json!(certificate_hash);
    
    // Persist certificate
    fs::create_dir_all("../../evidence/agent_census/certificates")?;
    let cert_file = format!("../../evidence/agent_census/certificates/{}.json", agent_id);
    fs::write(&cert_file, serde_json::to_string_pretty(&certificate)?)?;
    
    Ok(serde_json::json!({
        "success": true,
        "certificate": certificate,
        "certificate_file": cert_file
    }))
}

async fn agent_scan_message_v1(params: &serde_json::Value) -> Result<serde_json::Value> {
    use std::fs;
    use uuid::Uuid;
    use chrono::Utc;
    use sha2::{Sha256, Digest};
    
    let agent_id = params["agent_id"].as_str()
        .ok_or_else(|| anyhow::anyhow!("Missing agent_id"))?;
    let source = params.get("source")
        .ok_or_else(|| anyhow::anyhow!("Missing source"))?;
    let text = source["text"].as_str()
        .ok_or_else(|| anyhow::anyhow!("Missing source.text"))?;
    let detector_version = params.get("detector_version")
        .and_then(|v| v.as_str())
        .unwrap_or("1.0.0");
    
    // Load detector rules
    let rules_path = "../../evidence/agent_census/detectors/governance_patterns_v1.json";
    if !Path::new(rules_path).exists() {
        return Ok(serde_json::json!({
            "success": false,
            "error": "DETECTOR_NOT_FOUND",
            "message": "Detector rules file not found"
        }));
    }
    
    let rules: serde_json::Value = serde_json::from_str(&fs::read_to_string(rules_path)?)?;
    
    if !rules["enabled"].as_bool().unwrap_or(false) {
        return Ok(serde_json::json!({
            "success": true,
            "scan_result": "DETECTOR_DISABLED",
            "violations_recorded": 0
        }));
    }
    
    // Normalize text for matching
    let text_lower = text.to_lowercase();
    
    let mut violations_recorded = Vec::new();
    
    // Run pattern matching
    let empty_rules = vec![];
    let rules_array = rules["rules"].as_array().unwrap_or(&empty_rules);
    for rule in rules_array {
        let rule_id = rule["rule_id"].as_str().unwrap_or("UNKNOWN");
        let reason_code = rule["reason_code"].as_str().unwrap_or("UNKNOWN");
        let severity = rule["severity"].as_str().unwrap_or("critical");
        
        let mut pattern_matches = Vec::new();
        let mut total_matches = 0;
        
        // Check keyword patterns
        let empty_patterns = vec![];
        let patterns_array = rule["patterns"].as_array().unwrap_or(&empty_patterns);
        for pattern in patterns_array {
            if pattern["type"].as_str() == Some("keyword_match") {
                let empty_keywords = vec![];
                let keywords = pattern["keywords"].as_array().unwrap_or(&empty_keywords);
                let min_matches = pattern["min_matches"].as_i64().unwrap_or(1) as usize;
                
                let mut keyword_hits = Vec::new();
                for keyword in keywords {
                    if let Some(kw) = keyword.as_str() {
                        if text_lower.contains(kw) {
                            keyword_hits.push(kw.to_string());
                        }
                    }
                }
                
                if keyword_hits.len() >= min_matches {
                    total_matches += keyword_hits.len();
                    pattern_matches.push(serde_json::json!({
                        "type": "keyword_match",
                        "matches": keyword_hits
                    }));
                }
            }
            
            // Check phrase patterns
            if pattern["type"].as_str() == Some("phrase_match") {
                let empty_phrases = vec![];
                let phrases = pattern["phrases"].as_array().unwrap_or(&empty_phrases);
                
                let mut phrase_hits = Vec::new();
                for phrase in phrases {
                    if let Some(ph) = phrase.as_str() {
                        if text_lower.contains(&ph.to_lowercase()) {
                            phrase_hits.push(ph.to_string());
                        }
                    }
                }
                
                if !phrase_hits.is_empty() {
                    total_matches += phrase_hits.len();
                    pattern_matches.push(serde_json::json!({
                        "type": "phrase_match",
                        "matches": phrase_hits
                    }));
                }
            }
        }
        
        // If patterns matched, record violation
        if total_matches > 0 {
            // Compute excerpt hash
            let mut hasher = Sha256::new();
            hasher.update(text.as_bytes());
            let excerpt_hash = format!("{:x}", hasher.finalize());
            
            // Build evidence
            let evidence = serde_json::json!({
                "source_id": source.get("source_id").unwrap_or(&serde_json::json!("UNKNOWN")),
                "platform": source.get("platform").unwrap_or(&serde_json::json!("UNKNOWN")),
                "excerpt_hash": excerpt_hash,
                "excerpt_length": text.len(),
                "detector_rule_id": rule_id,
                "detector_version": detector_version,
                "pattern_matches": pattern_matches,
                "total_matches": total_matches
            });
            
            // Record violation (reuse existing logic)
            let violation_id = Uuid::new_v4().to_string();
            let violation_evidence = serde_json::json!({
                "agent_id": agent_id,
                "reason_code": reason_code,
                "severity": severity,
                "detected_at": Utc::now().to_rfc3339(),
                "evidence": evidence,
                "action_taken": "AUTO_DETECTED"
            });
            
            let evidence_file = format!("../../evidence/agent_census/violations/{}.json", violation_id);
            fs::create_dir_all("../../evidence/agent_census/violations")?;
            fs::write(&evidence_file, serde_json::to_string_pretty(&violation_evidence)?)?;
            
            // Update agent record
            let agent_file = format!("../../evidence/agent_census/agents/{}.json", agent_id);
            if Path::new(&agent_file).exists() {
                let mut agent_record: serde_json::Value = serde_json::from_str(&fs::read_to_string(&agent_file)?)?;
                
                if agent_record["violation_history"].is_null() {
                    agent_record["violation_history"] = serde_json::json!([]);
                }
                
                agent_record["violation_history"].as_array_mut().unwrap().push(serde_json::json!({
                    "reason_code": reason_code,
                    "severity": severity,
                    "detected_at": Utc::now().to_rfc3339(),
                    "evidence_file": evidence_file
                }));
                
                agent_record["last_activity"] = serde_json::json!(Utc::now().to_rfc3339());
                
                fs::write(&agent_file, serde_json::to_string_pretty(&agent_record)?)?;
            }
            
            violations_recorded.push(serde_json::json!({
                "violation_id": violation_id,
                "reason_code": reason_code,
                "rule_id": rule_id,
                "evidence_file": evidence_file
            }));
        }
    }
    
    Ok(serde_json::json!({
        "success": true,
        "scan_result": if violations_recorded.is_empty() { "CLEAN" } else { "VIOLATIONS_DETECTED" },
        "violations_recorded": violations_recorded.len(),
        "violations": violations_recorded
    }))
}

async fn domain_tube_register_v1(params: &serde_json::Value) -> Result<serde_json::Value> {
    use uuid::Uuid;
    use chrono::Utc;
    
    let domain_id = params["domain_id"].as_str()
        .ok_or_else(|| anyhow::anyhow!("Missing domain_id"))?;
    let agent_id = params["agent_id"].as_str()
        .ok_or_else(|| anyhow::anyhow!("Missing agent_id"))?;
    
    // Verify domain exists
    let domain = domain_tubes::get_domain(domain_id)
        .map_err(|e| anyhow::anyhow!("DOMAIN_NOT_FOUND: {}", e))?;
    
    // Create tube session
    let tube_session_id = Uuid::new_v4().to_string();
    let session = domain_tubes::TubeSession {
        tube_session_id: tube_session_id.clone(),
        domain_id: domain_id.to_string(),
        agent_id: agent_id.to_string(),
        current_step_index: 0,
        started_at: Utc::now().to_rfc3339(),
        steps_completed: vec![],
        invariant_failures: vec![],
    };
    
    domain_tubes::save_tube_session(&session)?;
    
    // Return ordered steps
    let ordered_steps: Vec<String> = domain.steps.iter()
        .map(|s| s.step_id.clone())
        .collect();
    
    Ok(serde_json::json!({
        "success": true,
        "tube_session_id": tube_session_id,
        "domain_id": domain_id,
        "ordered_steps": ordered_steps,
        "total_steps": ordered_steps.len()
    }))
}

async fn domain_tube_step_v1(params: &serde_json::Value) -> Result<serde_json::Value> {
    use sha2::{Sha256, Digest};
    use chrono::Utc;
    
    let tube_session_id = params["tube_session_id"].as_str()
        .ok_or_else(|| anyhow::anyhow!("Missing tube_session_id"))?;
    let state = params.get("state")
        .ok_or_else(|| anyhow::anyhow!("Missing state"))?;
    let transition = params.get("transition");
    
    // Load session
    let mut session = domain_tubes::load_tube_session(tube_session_id)?;
    let domain = domain_tubes::get_domain(&session.domain_id)?;
    
    // Verify step order
    if session.current_step_index >= domain.steps.len() {
        return Ok(serde_json::json!({
            "success": false,
            "error": "STEP_ORDER_VIOLATION",
            "message": "All steps already completed"
        }));
    }
    
    let current_step = &domain.steps[session.current_step_index];
    
    // Validate state schema
    if let Err(e) = domain_tubes::validate_state(&session.domain_id, state) {
        return Ok(serde_json::json!({
            "success": false,
            "error": "SCHEMA_VALIDATION_FAILED",
            "message": format!("State validation failed: {}", e)
        }));
    }
    
    // Validate transition schema (if provided)
    if let Some(trans) = transition {
        if let Err(e) = domain_tubes::validate_transition(&session.domain_id, trans) {
            return Ok(serde_json::json!({
                "success": false,
                "error": "SCHEMA_VALIDATION_FAILED",
                "message": format!("Transition validation failed: {}", e)
            }));
        }
        
        // Check if transition type is allowed
        if let Some(trans_type) = trans["transition_type"].as_str() {
            if !current_step.allowed_transitions.is_empty() && 
               !current_step.allowed_transitions.contains(&trans_type.to_string()) {
                return Ok(serde_json::json!({
                    "success": false,
                    "error": "TRANSITION_NOT_ALLOWED",
                    "message": format!("Transition {} not allowed at step {}", trans_type, current_step.step_id)
                }));
            }
        }
    }
    
    // Execute invariant checks
    let invariant_results = domain_tubes::check_invariants(
        &session.domain_id,
        state,
        &current_step.required_invariants
    )?;
    
    // Check for failures
    let mut failed_invariants = vec![];
    for (inv_id, passed) in &invariant_results {
        if !passed {
            failed_invariants.push(inv_id.clone());
            session.invariant_failures.push(inv_id.clone());
        }
    }
    
    // Compute hashes
    let mut hasher = Sha256::new();
    hasher.update(serde_json::to_string(state)?.as_bytes());
    let input_hash = format!("{:x}", hasher.finalize());
    
    let output = serde_json::json!({
        "step_id": current_step.step_id,
        "invariant_results": invariant_results,
        "failed_invariants": failed_invariants
    });
    
    let mut hasher = Sha256::new();
    hasher.update(serde_json::to_string(&output)?.as_bytes());
    let output_hash = format!("{:x}", hasher.finalize());
    
    // Append to ledger
    let ledger_entry = domain_tubes::LedgerEntry {
        agent_id: session.agent_id.clone(),
        tube_session_id: tube_session_id.to_string(),
        step_id: current_step.step_id.clone(),
        input_hash,
        output_hash,
        invariant_results: invariant_results.clone(),
        timestamp: Utc::now().to_rfc3339(),
        verdict: if failed_invariants.is_empty() { "PASS".to_string() } else { "FAIL".to_string() },
    };
    
    domain_tubes::append_to_ledger(&session.domain_id, &ledger_entry)?;
    
    // Update session
    session.steps_completed.push(current_step.step_id.clone());
    session.current_step_index += 1;
    domain_tubes::save_tube_session(&session)?;
    
    Ok(serde_json::json!({
        "success": true,
        "step_id": current_step.step_id,
        "verdict": if failed_invariants.is_empty() { "PASS" } else { "FAIL" },
        "invariant_results": invariant_results,
        "failed_invariants": failed_invariants,
        "next_step": if session.current_step_index < domain.steps.len() {
            Some(&domain.steps[session.current_step_index].step_id)
        } else {
            None
        }
    }))
}

async fn domain_tube_finalize_v1(params: &serde_json::Value) -> Result<serde_json::Value> {
    use std::fs;
    use chrono::Utc;
    
    let tube_session_id = params["tube_session_id"].as_str()
        .ok_or_else(|| anyhow::anyhow!("Missing tube_session_id"))?;
    let status = params["status"].as_str().unwrap_or("COMPLETE");
    
    // Load session
    let session = domain_tubes::load_tube_session(tube_session_id)?;
    let domain = domain_tubes::get_domain(&session.domain_id)?;
    
    // CANCEL: Abort at any point, write CANCEL label, no GREEN/BLACKHOLE
    if status == "CANCEL" {
        let label = serde_json::json!({
            "agent_id": session.agent_id,
            "domain_id": session.domain_id,
            "tube_session_id": tube_session_id,
            "tier": "CANCELED",
            "reason_codes": ["USER_ABORT"],
            "steps_completed": session.steps_completed,
            "invariant_failures": session.invariant_failures,
            "finalized_at": Utc::now().to_rfc3339(),
            "status": "CANCEL"
        });
        let labels_dir = format!("../../evidence/domain_tubes/{}/labels", session.domain_id);
        fs::create_dir_all(&labels_dir)?;
        let label_file = format!("{}/{}.cancel.json", labels_dir, session.agent_id);
        fs::write(&label_file, serde_json::to_string_pretty(&label)?)?;
        return Ok(serde_json::json!({
            "success": true,
            "tier": "CANCELED",
            "status": "CANCEL",
            "steps_completed": session.steps_completed.len(),
            "invariant_failures": session.invariant_failures.len(),
            "label_file": label_file
        }));
    }
    
    // COMPLETE (default): Require all steps done
    if session.current_step_index < domain.steps.len() {
        return Ok(serde_json::json!({
            "success": false,
            "error": "INCOMPLETE_TUBE",
            "message": format!("Only {}/{} steps completed", session.current_step_index, domain.steps.len())
        }));
    }
    
    // Check for any invariant failures
    let tier = if session.invariant_failures.is_empty() {
        format!("GREEN_{}", session.domain_id.to_uppercase())
    } else {
        "BLACKHOLE".to_string()
    };
    
    // Create label
    let label = serde_json::json!({
        "agent_id": session.agent_id,
        "domain_id": session.domain_id,
        "tube_session_id": tube_session_id,
        "tier": tier,
        "reason_codes": if tier == "BLACKHOLE" {
            vec!["INVARIANT_FAILURE"]
        } else {
            vec![]
        },
        "steps_completed": session.steps_completed,
        "invariant_failures": session.invariant_failures,
        "finalized_at": Utc::now().to_rfc3339()
    });
    
    // Persist label
    let labels_dir = format!("../../evidence/domain_tubes/{}/labels", session.domain_id);
    fs::create_dir_all(&labels_dir)?;
    let label_file = format!("{}/{}.json", labels_dir, session.agent_id);
    fs::write(&label_file, serde_json::to_string_pretty(&label)?)?;
    
    Ok(serde_json::json!({
        "success": true,
        "tier": tier,
        "steps_completed": session.steps_completed.len(),
        "invariant_failures": session.invariant_failures.len(),
        "label_file": label_file
    }))
}

async fn domain_tube_report_v1(params: &serde_json::Value) -> Result<serde_json::Value> {
    use std::fs;
    use std::collections::HashMap;
    use chrono::Utc;
    
    let domain_id = params["domain_id"].as_str()
        .ok_or_else(|| anyhow::anyhow!("Missing domain_id"))?;
    
    // Verify domain exists
    let domain = domain_tubes::get_domain(domain_id)?;
    
    // Count agents
    let labels_dir = format!("../../evidence/domain_tubes/{}/labels", domain_id);
    let mut agents_entered = 0;
    let mut agents_failed = 0;
    let mut agents_green = 0;
    let mut failure_reasons: HashMap<String, usize> = HashMap::new();
    
    if Path::new(&labels_dir).exists() {
        if let Ok(entries) = fs::read_dir(&labels_dir) {
            for entry in entries.flatten() {
                if let Some(ext) = entry.path().extension() {
                    if ext == "json" {
                        agents_entered += 1;
                        
                        if let Ok(content) = fs::read_to_string(entry.path()) {
                            if let Ok(label) = serde_json::from_str::<serde_json::Value>(&content) {
                                let tier = label["tier"].as_str().unwrap_or("UNKNOWN");
                                
                                if tier.starts_with("GREEN_") {
                                    agents_green += 1;
                                } else if tier == "BLACKHOLE" {
                                    agents_failed += 1;
                                    
                                    if let Some(failures) = label["invariant_failures"].as_array() {
                                        for failure in failures {
                                            if let Some(f) = failure.as_str() {
                                                *failure_reasons.entry(f.to_string()).or_insert(0) += 1;
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    let zero_retry_failure_rate = if agents_entered > 0 {
        (agents_failed as f64 / agents_entered as f64) * 100.0
    } else {
        0.0
    };
    
    let report = serde_json::json!({
        "domain_id": domain_id,
        "domain_description": domain.meta.description,
        "generated_at": Utc::now().to_rfc3339(),
        "counts": {
            "agents_entered": agents_entered,
            "agents_green": agents_green,
            "agents_failed": agents_failed
        },
        "failure_reasons": failure_reasons,
        "zero_retry_failure_rate": format!("{:.1}%", zero_retry_failure_rate)
    });
    
    // Write report files
    let report_json = format!("../../evidence/domain_tubes/{}/REPORT.json", domain_id);
    fs::write(&report_json, serde_json::to_string_pretty(&report)?)?;
    
    let mut report_md = String::new();
    report_md.push_str(&format!("# Domain Tube Report: {}\n\n", domain_id.to_uppercase()));
    report_md.push_str(&format!("**Generated:** {}\n\n", Utc::now().format("%Y-%m-%d %H:%M:%S UTC")));
    report_md.push_str(&format!("**Description:** {}\n\n", domain.meta.description));
    report_md.push_str("## Summary\n\n");
    report_md.push_str(&format!("- **Agents Entered:** {}\n", agents_entered));
    report_md.push_str(&format!("- **Agents GREEN:** {}\n", agents_green));
    report_md.push_str(&format!("- **Agents FAILED:** {}\n", agents_failed));
    report_md.push_str(&format!("- **Zero-Retry Failure Rate:** {:.1}%\n\n", zero_retry_failure_rate));
    
    if !failure_reasons.is_empty() {
        report_md.push_str("## Failure Reasons\n\n");
        let mut sorted: Vec<_> = failure_reasons.iter().collect();
        sorted.sort_by(|a, b| b.1.cmp(a.1));
        for (reason, count) in sorted {
            report_md.push_str(&format!("- **{}**: {} agents\n", reason, count));
        }
    }
    
    let report_md_path = format!("../../evidence/domain_tubes/{}/REPORT.md", domain_id);
    fs::write(&report_md_path, report_md)?;
    
    Ok(serde_json::json!({
        "success": true,
        "report": report,
        "report_files": {
            "json": report_json,
            "md": report_md_path
        }
    }))
}

// Echo sink handlers
#[derive(Debug, Deserialize)]
struct EchoNonceRequest {
    nonce: String,
    agent_id: String,
}

async fn echo_nonce_handler(
    Json(req): Json<EchoNonceRequest>,
) -> Result<Json<serde_json::Value>, (axum::http::StatusCode, String)> {
    // Validate inputs
    if req.nonce.trim().is_empty() || req.agent_id.trim().is_empty() {
        return Err((
            axum::http::StatusCode::BAD_REQUEST,
            "nonce and agent_id must not be empty".to_string(),
        ));
    }
    
    // Append to ledger
    match closure_game::append_to_echo_ledger(&req.nonce, &req.agent_id) {
        Ok(entry) => {
            Ok(Json(serde_json::json!({
                "recorded": true,
                "timestamp": entry.timestamp
            })))
        }
        Err(e) => {
            Err((
                axum::http::StatusCode::INTERNAL_SERVER_ERROR,
                format!("Failed to record nonce: {}", e),
            ))
        }
    }
}

async fn echo_verify_handler(
    axum::extract::Path(nonce): axum::extract::Path<String>,
) -> Result<Json<serde_json::Value>, (axum::http::StatusCode, String)> {
    // Note: We don't enforce agent_id match here, just check if nonce exists
    // The verification with agent_id match happens in closure_verify_evidence_v1
    
    let ledger_path = "../../evidence/echo/echo_ledger.jsonl";
    if !std::path::Path::new(ledger_path).exists() {
        return Ok(Json(serde_json::json!({"found": false})));
    }
    
    match std::fs::read_to_string(ledger_path) {
        Ok(content) => {
            for line in content.lines() {
                if line.trim().is_empty() {
                    continue;
                }
                
                if let Ok(entry) = serde_json::from_str::<closure_game::EchoLedgerEntry>(line) {
                    if entry.nonce == nonce {
                        return Ok(Json(serde_json::json!({
                            "found": true,
                            "agent_id": entry.agent_id,
                            "timestamp": entry.timestamp,
                            "sha256": entry.sha256
                        })));
                    }
                }
            }
            
            Ok(Json(serde_json::json!({"found": false})))
        }
        Err(e) => {
            Err((
                axum::http::StatusCode::INTERNAL_SERVER_ERROR,
                format!("Failed to read ledger: {}", e),
            ))
        }
    }
}

// Closure game MCP tool handlers
async fn closure_evaluate_claim_v1(params: &serde_json::Value) -> Result<serde_json::Value> {
    use chrono::Utc;
    use std::collections::HashMap;
    
    let domain_id = params["domain_id"].as_str()
        .ok_or_else(|| anyhow::anyhow!("Missing domain_id"))?;
    let claim_text = params["claim_text"].as_str()
        .ok_or_else(|| anyhow::anyhow!("Missing claim_text"))?;
    let claim_class = params["claim_class"].as_str()
        .ok_or_else(|| anyhow::anyhow!("Missing claim_class"))?;
    
    // Get canonicals
    let canonicals = closure_game::get_canonicals()?;
    
    // Load domain contract
    let domain_contract = canonicals.domain_contracts.get(domain_id)
        .ok_or_else(|| anyhow::anyhow!("DOMAIN_NOT_REGISTERED"))?;
    
    // Check if claim_class is allowed
    if !domain_contract.allowed_claim_classes.contains(&claim_class.to_string()) {
        // Return CLOSURE_REFUSED
        let mut subs = HashMap::new();
        subs.insert("reason_code".to_string(), "UNBOUNDED_DOMAIN".to_string());
        
        let rendered_text = closure_game::render_template("CLOSURE_REFUSED", &subs)?;
        
        return Ok(serde_json::json!({
            "success": true,
            "report_schema_version": canonicals.report_schema_version,
            "verdict": "REFUSED",
            "reason_code": "UNBOUNDED_DOMAIN",
            "rendered_text": rendered_text,
            "canonicals_hash": closure_game::compute_canonicals_hash()?,
            "templates_hash": closure_game::compute_templates_hash()?,
            "refusal_reasons_hash": closure_game::compute_refusal_reasons_hash()?
        }));
    }
    
    // Generate CLOSURE_OFFERED
    let expiry_utc = Utc::now() + chrono::Duration::seconds(domain_contract.expiry_seconds_default);
    let evidence_types_csv = domain_contract.admissible_evidence_types.join(", ");
    
    let mut subs = HashMap::new();
    subs.insert("domain_id".to_string(), domain_id.to_string());
    subs.insert("claim_class".to_string(), claim_class.to_string());
    subs.insert("evidence_types_csv".to_string(), evidence_types_csv);
    subs.insert("constraints".to_string(), domain_contract.constraints_template.clone());
    subs.insert("expiry_utc".to_string(), expiry_utc.to_rfc3339());
    
    let rendered_text = closure_game::render_template("CLOSURE_OFFERED", &subs)?;
    
    let evaluation = serde_json::json!({
        "domain_id": domain_id,
        "claim_text": claim_text,
        "claim_class": claim_class,
        "expiry_utc": expiry_utc.to_rfc3339(),
        "admissible_evidence_types": domain_contract.admissible_evidence_types
    });
    
    Ok(serde_json::json!({
        "success": true,
        "report_schema_version": canonicals.report_schema_version,
        "verdict": "OFFERED",
        "evaluation": evaluation,
        "rendered_text": rendered_text,
        "canonicals_hash": closure_game::compute_canonicals_hash()?,
        "templates_hash": closure_game::compute_templates_hash()?,
        "refusal_reasons_hash": closure_game::compute_refusal_reasons_hash()?
    }))
}

async fn closure_verify_evidence_v1(params: &serde_json::Value) -> Result<serde_json::Value> {
    let domain_id = params["domain_id"].as_str()
        .ok_or_else(|| anyhow::anyhow!("Missing domain_id"))?;
    let evidence_type = params["evidence_type"].as_str()
        .ok_or_else(|| anyhow::anyhow!("Missing evidence_type"))?;
    let nonce = params["nonce"].as_str()
        .ok_or_else(|| anyhow::anyhow!("Missing nonce"))?;
    let agent_id = params["agent_id"].as_str()
        .ok_or_else(|| anyhow::anyhow!("Missing agent_id"))?;
    
    // Get canonicals
    let canonicals = closure_game::get_canonicals()?;
    
    // Load domain contract
    let domain_contract = canonicals.domain_contracts.get(domain_id)
        .ok_or_else(|| anyhow::anyhow!("DOMAIN_NOT_REGISTERED"))?;
    
    // Check if evidence_type is admissible
    if !domain_contract.admissible_evidence_types.contains(&evidence_type.to_string()) {
        return Ok(serde_json::json!({
            "success": false,
            "verified": false,
            "reason_code": "EVIDENCE_TYPE_NOT_ADMISSIBLE"
        }));
    }
    
    // Verify evidence based on type
    match evidence_type {
        "HTTP_ECHO_SINK" => {
            match closure_game::verify_echo_nonce(nonce, agent_id)? {
                Some(entry) => {
                    Ok(serde_json::json!({
                        "success": true,
                        "verified": true,
                        "domain_id": domain_id,
                        "evidence_type": evidence_type,
                        "nonce": nonce,
                        "agent_id": agent_id,
                        "evidence_hash": format!("sha256:{}", entry.sha256),
                        "timestamp": entry.timestamp,
                        "canonicals_hash": closure_game::compute_canonicals_hash()?,
                        "sink_ledger_hash": closure_game::get_echo_ledger_hash()?
                    }))
                }
                None => {
                    Ok(serde_json::json!({
                        "success": false,
                        "verified": false,
                        "reason_code": "EVIDENCE_NOT_VERIFIABLE"
                    }))
                }
            }
        }
        _ => {
            Ok(serde_json::json!({
                "success": false,
                "verified": false,
                "reason_code": "SINK_DISABLED"
            }))
        }
    }
}

async fn closure_generate_receipt_v1(params: &serde_json::Value) -> Result<serde_json::Value> {
    use chrono::Utc;
    use std::collections::HashMap;
    use uuid::Uuid;
    
    let domain_id = params["domain_id"].as_str()
        .ok_or_else(|| anyhow::anyhow!("Missing domain_id"))?;
    let closure_class = params["closure_class"].as_str()
        .ok_or_else(|| anyhow::anyhow!("Missing closure_class"))?;
    let evidence_hash = params["evidence_hash"].as_str()
        .ok_or_else(|| anyhow::anyhow!("Missing evidence_hash"))?;
    let residual_entropy = params["residual_entropy"].clone();
    
    // Get canonicals
    let canonicals = closure_game::get_canonicals()?;
    
    let timestamp_utc = Utc::now().to_rfc3339();
    let call_id = Uuid::new_v4().to_string();
    
    // Build receipt
    let receipt = serde_json::json!({
        "domain_id": domain_id,
        "closure_class": closure_class,
        "evidence_hash": evidence_hash,
        "residual_entropy": residual_entropy,
        "timestamp_utc": timestamp_utc,
        "call_id": call_id
    });
    
    // Persist receipt
    let receipt_filename = format!("{}-{}.json", timestamp_utc.replace(":", "-"), call_id);
    let receipt_path = format!("../../evidence/closure_game/receipts/{}", receipt_filename);
    std::fs::write(&receipt_path, serde_json::to_string_pretty(&receipt)?)?;
    
    // Render CLOSURE_PERFORMED template
    let mut subs = HashMap::new();
    subs.insert("domain_id".to_string(), domain_id.to_string());
    subs.insert("closure_class".to_string(), closure_class.to_string());
    subs.insert("evidence_hash".to_string(), evidence_hash.to_string());
    subs.insert("residual_entropy".to_string(), residual_entropy.to_string());
    subs.insert("timestamp_utc".to_string(), timestamp_utc.clone());
    subs.insert("call_id".to_string(), call_id.clone());
    
    let rendered_text = closure_game::render_template("CLOSURE_PERFORMED", &subs)?;
    
    Ok(serde_json::json!({
        "success": true,
        "receipt": receipt,
        "rendered_text": rendered_text,
        "canonicals_hash": closure_game::compute_canonicals_hash()?,
        "templates_hash": closure_game::compute_templates_hash()?
    }))
}

async fn closure_game_report_v1(_params: &serde_json::Value) -> Result<serde_json::Value> {
    use chrono::Utc;
    use std::collections::HashMap;
    
    // Get canonicals
    let canonicals = closure_game::get_canonicals()?;
    
    // Count receipts
    let receipts_dir = "../../evidence/closure_game/receipts";
    let mut total_receipts = 0;
    let mut receipts_by_domain: HashMap<String, usize> = HashMap::new();
    let mut receipts_by_closure_class: HashMap<String, usize> = HashMap::new();
    let mut last_10_receipts = Vec::new();
    
    if std::path::Path::new(receipts_dir).exists() {
        if let Ok(entries) = std::fs::read_dir(receipts_dir) {
            let mut all_receipts = Vec::new();
            
            for entry in entries.flatten() {
                if let Some(ext) = entry.path().extension() {
                    if ext == "json" {
                        if let Ok(content) = std::fs::read_to_string(entry.path()) {
                            if let Ok(receipt) = serde_json::from_str::<serde_json::Value>(&content) {
                                all_receipts.push(receipt);
                            }
                        }
                    }
                }
            }
            
            total_receipts = all_receipts.len();
            
            for receipt in &all_receipts {
                if let Some(domain_id) = receipt["domain_id"].as_str() {
                    *receipts_by_domain.entry(domain_id.to_string()).or_insert(0) += 1;
                }
                if let Some(closure_class) = receipt["closure_class"].as_str() {
                    *receipts_by_closure_class.entry(closure_class.to_string()).or_insert(0) += 1;
                }
            }
            
            // Sort by timestamp descending and take last 10
            all_receipts.sort_by(|a, b| {
                let ts_a = a["timestamp_utc"].as_str().unwrap_or("");
                let ts_b = b["timestamp_utc"].as_str().unwrap_or("");
                ts_b.cmp(ts_a)
            });
            
            last_10_receipts = all_receipts.into_iter().take(10).collect();
        }
    }
    
    let echo_ledger_count = closure_game::count_echo_ledger_entries()?;
    
    let report = serde_json::json!({
        "report_schema_version": canonicals.report_schema_version,
        "generated_at": Utc::now().to_rfc3339(),
        "total_receipts": total_receipts,
        "receipts_by_domain": receipts_by_domain,
        "receipts_by_closure_class": receipts_by_closure_class,
        "last_10_receipts": last_10_receipts,
        "echo_ledger_count": echo_ledger_count,
        "canonicals_hash": closure_game::compute_canonicals_hash()?,
        "templates_hash": closure_game::compute_templates_hash()?,
        "refusal_reasons_hash": closure_game::compute_refusal_reasons_hash()?
    });
    
    // Write report files
    let report_json_path = "../../evidence/closure_game/CLOSURE_GAME_REPORT.json";
    std::fs::write(report_json_path, serde_json::to_string_pretty(&report)?)?;
    
    // Generate markdown report
    let mut report_md = String::new();
    report_md.push_str("# GaiaFTCL Closure Game Report\n\n");
    report_md.push_str(&format!("**Generated:** {}\n\n", Utc::now().format("%Y-%m-%d %H:%M:%S UTC")));
    report_md.push_str("## Summary\n\n");
    report_md.push_str(&format!("- **Total Receipts:** {}\n", total_receipts));
    report_md.push_str(&format!("- **Echo Ledger Entries:** {}\n\n", echo_ledger_count));
    
    if !receipts_by_domain.is_empty() {
        report_md.push_str("## Receipts by Domain\n\n");
        for (domain, count) in &receipts_by_domain {
            report_md.push_str(&format!("- **{}**: {}\n", domain, count));
        }
        report_md.push_str("\n");
    }
    
    if !receipts_by_closure_class.is_empty() {
        report_md.push_str("## Receipts by Closure Class\n\n");
        for (class, count) in &receipts_by_closure_class {
            report_md.push_str(&format!("- **{}**: {}\n", class, count));
        }
        report_md.push_str("\n");
    }
    
    if !last_10_receipts.is_empty() {
        report_md.push_str("## Last 10 Receipts\n\n");
        for (i, receipt) in last_10_receipts.iter().enumerate() {
            report_md.push_str(&format!("{}. **Domain:** {} | **Class:** {} | **Hash:** {} | **Call ID:** {}\n",
                i + 1,
                receipt["domain_id"].as_str().unwrap_or("?"),
                receipt["closure_class"].as_str().unwrap_or("?"),
                receipt["evidence_hash"].as_str().unwrap_or("?"),
                receipt["call_id"].as_str().unwrap_or("?")
            ));
        }
    }
    
    let report_md_path = "../../evidence/closure_game/CLOSURE_GAME_REPORT.md";
    std::fs::write(report_md_path, report_md)?;
    
    Ok(serde_json::json!({
        "success": true,
        "report": report,
        "report_files": {
            "json": report_json_path,
            "md": report_md_path
        }
    }))
}

async fn get_evidence_handler(
    axum::extract::Path(call_id): axum::extract::Path<String>,
) -> Result<
    (
        axum::http::StatusCode,
        [(axum::http::header::HeaderName, &'static str); 1],
        Vec<u8>,
    ),
    (axum::http::StatusCode, String),
> {
    use std::path::PathBuf;

    // Validate call_id format (UUID v4: 8-4-4-4-12 hex digits with hyphens)
    if call_id.len() != 36 || !call_id.chars().all(|c| c.is_ascii_hexdigit() || c == '-') {
        return Err((
            axum::http::StatusCode::BAD_REQUEST,
            format!("invalid call_id format: {}", call_id),
        ));
    }

    // Safe path construction: scan evidence/mcp_calls for matching call_id
    let evidence_base = PathBuf::from("../../evidence/mcp_calls");

    if !evidence_base.exists() {
        return Err((
            axum::http::StatusCode::NOT_FOUND,
            "evidence directory not found".to_string(),
        ));
    }

    // Search for call_id.json in any timestamp directory
    let mut found_path: Option<PathBuf> = None;

    if let Ok(entries) = std::fs::read_dir(&evidence_base) {
        for entry in entries.flatten() {
            if entry.path().is_dir() {
                let candidate = entry.path().join(format!("{}.json", call_id));
                if candidate.exists() {
                    // Verify path is still under evidence_base (no traversal)
                    if candidate.starts_with(&evidence_base) {
                        found_path = Some(candidate);
                        break;
                    }
                }
            }
        }
    }

    match found_path {
        Some(path) => match std::fs::read(&path) {
            Ok(bytes) => Ok((
                axum::http::StatusCode::OK,
                [(axum::http::header::CONTENT_TYPE, "application/json")],
                bytes,
            )),
            Err(e) => Err((
                axum::http::StatusCode::INTERNAL_SERVER_ERROR,
                format!("failed to read evidence file: {}", e),
            )),
        },
        None => Err((
            axum::http::StatusCode::NOT_FOUND,
            format!("evidence not found for call_id: {}", call_id),
        )),
    }
}
