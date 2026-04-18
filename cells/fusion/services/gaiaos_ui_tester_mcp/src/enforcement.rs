//! MCP Enforcement Layer
//!
//! Implements:
//! 1. Environment ID validation
//! 2. Witness generation (SHA-256)
//! 3. Admissibility checking
//! 4. Canonical file integrity validation

use anyhow::{bail, Result};
use axum::{extract::Request, http::StatusCode, middleware::Next, response::Response};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use sha2::{Digest, Sha256};
use std::collections::HashSet;
use std::fs;
use std::path::Path;
use std::sync::OnceLock;
use tracing::{error, info};
use uuid::Uuid;

// ============================================================================
// ENVIRONMENT ID VALIDATION
// ============================================================================

#[derive(Debug, Deserialize)]
struct AllowedEnvironments {
    allowed_environment_ids: Vec<String>,
}

pub fn validate_environment_id(env_id: &str) -> Result<()> {
    let allowed_path = "/app/evidence/environments/allowed_environment_ids.json";
    let fallback_path = "../../evidence/environments/allowed_environment_ids.json";

    let path = if Path::new(allowed_path).exists() {
        allowed_path
    } else if Path::new(fallback_path).exists() {
        fallback_path
    } else {
        bail!(
            "Environment authority file not found (tried {} and {})",
            allowed_path,
            fallback_path
        );
    };

    let contents = fs::read_to_string(path)?;
    let allowed: AllowedEnvironments = serde_json::from_str(&contents)?;

    if allowed
        .allowed_environment_ids
        .contains(&env_id.to_string())
    {
        Ok(())
    } else {
        bail!("environment_id not admitted")
    }
}

// ============================================================================
// CANONICAL FILE INTEGRITY VALIDATION
// ============================================================================

static CANONICALS_VALIDATED: OnceLock<Result<(), String>> = OnceLock::new();

/// Validates canonical files on first call (fail-closed)
/// Returns Ok(()) if all checks pass, Err(reason) otherwise
pub fn validate_canonicals() -> Result<(), String> {
    CANONICALS_VALIDATED
        .get_or_init(|| {
            let lockfile_path = "../../evidence/ui_expected/CANONICALS.SHA256";
            
            // 1. Verify lockfile exists
            if !Path::new(lockfile_path).exists() {
                return Err("CANONICALS.SHA256 lockfile not found".to_string());
            }
            
            // 2. Read lockfile and verify each file
            let lockfile_contents = fs::read_to_string(lockfile_path)
                .map_err(|e| format!("Failed to read lockfile: {}", e))?;
            
            for line in lockfile_contents.lines() {
                let parts: Vec<&str> = line.split_whitespace().collect();
                if parts.len() != 2 {
                    continue;
                }
                let (expected_hash, lockfile_path) = (parts[0], parts[1]);
                
                // Prepend ../../ to make path relative to server working directory
                let file_path = format!("../../{}", lockfile_path);
                
                // Verify file exists
                if !Path::new(&file_path).exists() {
                    return Err(format!("Canonical file missing: {}", file_path));
                }
                
                // Verify hash matches
                let contents = fs::read(&file_path)
                    .map_err(|e| format!("Failed to read {}: {}", file_path, e))?;
                let mut hasher = Sha256::new();
                hasher.update(&contents);
                let computed_hash = format!("{:x}", hasher.finalize());
                
                if computed_hash != expected_hash {
                    return Err(format!("Hash mismatch for {}: expected {}, got {}", 
                        file_path, expected_hash, computed_hash));
                }
                
                // 3. Verify JSON parses and is non-empty
                let json_str = String::from_utf8(contents)
                    .map_err(|e| format!("Invalid UTF-8 in {}: {}", file_path, e))?;
                let json_value: Value = serde_json::from_str(&json_str)
                    .map_err(|e| format!("Invalid JSON in {}: {}", file_path, e))?;
                
                if json_value.is_null() || (json_value.is_array() && json_value.as_array().unwrap().is_empty()) {
                    return Err(format!("Canonical file is empty: {}", file_path));
                }
                
                // 4. Check for duplicate IDs within the file
                if let Some(arr) = json_value.as_array() {
                    let mut ids = HashSet::new();
                    for item in arr {
                        if let Some(obj) = item.as_object() {
                            // Support multiple ID field names
                            let id_value = obj.get("id")
                                .or_else(|| obj.get("subject"))
                                .or_else(|| obj.get("dim_key"))
                                .or_else(|| obj.get("game_id"));
                            
                            if let Some(id) = id_value.and_then(|v| v.as_str()) {
                                if !ids.insert(id.to_string()) {
                                    return Err(format!("Duplicate ID '{}' in {}", id, file_path));
                                }
                            }
                        }
                    }
                }
            }
            
            Ok(())
        })
        .clone()
}

// ============================================================================
// WITNESS GENERATION
// ============================================================================

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MCPCallEvidence {
    pub call_id: String,
    pub timestamp: String,
    pub tool: String,
    pub environment_id: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub wallet_address: Option<String>,
    pub args: serde_json::Value,
    pub result: serde_json::Value,
    #[serde(skip_serializing)]
    pub witness: String,
}

// Validate agent census canonicals (separate OnceLock)
static AGENT_CENSUS_VALIDATED: OnceLock<Result<(), String>> = OnceLock::new();

pub fn validate_agent_census_canonicals() -> Result<(), String> {
    AGENT_CENSUS_VALIDATED
        .get_or_init(|| {
            let lockfile_path = "../../evidence/agent_census/canon/CANONICALS.SHA256";
            
            if !Path::new(lockfile_path).exists() {
                return Err(format!("Agent census lockfile missing: {}", lockfile_path));
            }
            
            let lockfile_content = fs::read_to_string(lockfile_path)
                .map_err(|e| format!("Failed to read agent census lockfile: {}", e))?;
            
            for line in lockfile_content.lines() {
                let line = line.trim();
                if line.is_empty() {
                    continue;
                }
                
                let parts: Vec<&str> = line.split_whitespace().collect();
                if parts.len() != 2 {
                    return Err(format!("Invalid lockfile format in agent census: {}", line));
                }
                
                let (expected_hash, lockfile_path) = (parts[0], parts[1]);
                let file_path = format!("../../{}", lockfile_path);
                
                if !Path::new(&file_path).exists() {
                    return Err(format!("Agent census canonical file missing: {}", file_path));
                }
                
                let contents = fs::read(&file_path)
                    .map_err(|e| format!("Failed to read {}: {}", file_path, e))?;
                
                let mut hasher = Sha256::new();
                hasher.update(&contents);
                let actual_hash = format!("{:x}", hasher.finalize());
                
                if actual_hash != expected_hash {
                    return Err(format!("Hash mismatch for {}: expected {}, got {}", 
                        file_path, expected_hash, actual_hash));
                }
                
                let json_str = String::from_utf8(contents)
                    .map_err(|e| format!("Invalid UTF-8 in {}: {}", file_path, e))?;
                let json_value: Value = serde_json::from_str(&json_str)
                    .map_err(|e| format!("Invalid JSON in {}: {}", file_path, e))?;
                
                if json_value.is_null() {
                    return Err(format!("Agent census canonical file is empty: {}", file_path));
                }
            }
            
            Ok(())
        })
        .clone()
}

pub fn generate_witness(payload: &serde_json::Value) -> String {
    let canonical = serde_json::to_string(payload).unwrap_or_default();
    let mut hasher = Sha256::new();
    hasher.update(canonical.as_bytes());
    let hash = hasher.finalize();
    format!("sha256:{:x}", hash)
}

pub fn save_evidence(evidence: &MCPCallEvidence) -> Result<String> {
    let timestamp = chrono::Utc::now().format("%Y-%m-%dT%H-%M-%S-%3fZ");
    let dir = format!("../../evidence/mcp_calls/{}", timestamp);
    fs::create_dir_all(&dir)?;

    let file_path = format!("{}/{}.json", dir, evidence.call_id);
    let json = serde_json::to_string_pretty(evidence)?;
    fs::write(&file_path, json)?;

    Ok(file_path)
}

// ============================================================================
// ADMISSIBILITY CHECKING
// ============================================================================

const ADMITTED_TOOLS: &[&str] = &[
    "ui_contract_generate",
    "ui_contract_verify",
    "ui_contract_report",
    "run_bevy_ui_scenario",
    "get_bevy_report",
    "validate_ui_ttl_compliance",
    "check_substrate_connection",
    "agent_register_v1",
    "agent_issue_challenges_v1",
    "agent_submit_proof_v1",
    "agent_label_v1",
    "agent_topology_export_v1",
    "agent_census_report_v1",
    "agent_record_violation_v1",
    "agent_census_certificate_v1",
    "agent_scan_message_v1",
    "domain_tube_register_v1",
    "domain_tube_step_v1",
    "domain_tube_finalize_v1",
    "domain_tube_report_v1",
    "closure_evaluate_claim_v1",
    "closure_verify_evidence_v1",
    "closure_generate_receipt_v1",
    "closure_game_report_v1",
];

pub fn check_tool_admissibility(tool_name: &str) -> Result<()> {
    if ADMITTED_TOOLS.contains(&tool_name) {
        Ok(())
    } else {
        bail!("tool not in admissibility contract")
    }
}

// ============================================================================
// MIDDLEWARE
// ============================================================================

pub async fn enforce_environment_id(request: Request, next: Next) -> Result<Response, StatusCode> {
    let env_id = request
        .headers()
        .get("X-Environment-ID")
        .and_then(|v| v.to_str().ok());

    match env_id {
        Some(id) => match validate_environment_id(id) {
            Ok(_) => {
                info!("Environment ID validated: {}", id);
                Ok(next.run(request).await)
            }
            Err(e) => {
                error!("Environment ID rejected: {} - {}", id, e);
                Err(StatusCode::FORBIDDEN)
            }
        },
        None => {
            error!("Missing X-Environment-ID header");
            Err(StatusCode::BAD_REQUEST)
        }
    }
}

// ============================================================================
// WITNESS WRAPPER (moved from witness_wrapper.rs)
// ============================================================================

pub fn wrap_with_witness<T: Serialize, R: Serialize>(
    environment_id: &str,
    tool_name: &str,
    wallet_address: Option<&str>,
    request: &R,
    result: &T,
) -> Result<(Value, String)> {
    let call_id = Uuid::new_v4().to_string();
    let timestamp = chrono::Utc::now().to_rfc3339();

    // Serialize result to JSON for witness generation
    let result_json = serde_json::to_value(result)?;
    let request_json = serde_json::to_value(request)?;

    // Create evidence record WITHOUT witness first
    let evidence = MCPCallEvidence {
        call_id: call_id.clone(),
        timestamp: timestamp.clone(),
        tool: tool_name.to_string(),
        environment_id: environment_id.to_string(),
        wallet_address: wallet_address.map(|s| s.to_string()),
        args: request_json,
        result: result_json.clone(),
        witness: String::new(), // Placeholder
    };

    // Serialize evidence to exact bytes that will be saved
    let evidence_json = serde_json::to_string_pretty(&evidence)?;
    let evidence_bytes = evidence_json.as_bytes();

    // Generate witness from EXACT evidence bytes
    let mut hasher = Sha256::new();
    hasher.update(evidence_bytes);
    let hash = hasher.finalize();
    let witness_hash = format!("sha256:{:x}", hash);

    // Update evidence with computed witness
    let evidence = MCPCallEvidence {
        call_id: call_id.clone(),
        timestamp: timestamp.clone(),
        tool: tool_name.to_string(),
        environment_id: environment_id.to_string(),
        wallet_address: wallet_address.map(|s| s.to_string()),
        args: evidence.args,
        result: result_json.clone(),
        witness: witness_hash.clone(),
    };

    // Save evidence to disk
    let evidence_path = save_evidence(&evidence)?;

    // Build witness metadata
    let witness_metadata = serde_json::json!({
        "call_id": call_id,
        "timestamp": timestamp,
        "hash": witness_hash,
        "algorithm": "sha256"
    });

    Ok((witness_metadata, evidence_path))
}
