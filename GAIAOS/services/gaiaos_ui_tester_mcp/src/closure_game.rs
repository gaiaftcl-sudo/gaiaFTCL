// GaiaFTCL Closure Game — server backing infrastructure
// Manual operator tooling, no automation, no simulation

use anyhow::{Result, anyhow};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::HashMap;
use std::fs;
use std::path::Path;
use std::sync::OnceLock;
use sha2::{Sha256, Digest};
use chrono::Utc;

// Domain contract
#[derive(Debug, Deserialize, Clone)]
pub struct DomainContract {
    pub domain_id: String,
    pub allowed_claim_classes: Vec<String>,
    pub admissible_evidence_types: Vec<String>,
    pub invariants: Vec<String>,
    pub constraints_template: String,
    pub expiry_seconds_default: i64,
}

// Response templates
#[derive(Debug, Deserialize)]
pub struct ResponseTemplates {
    pub templates: HashMap<String, String>,
}

// Refusal reasons
#[derive(Debug, Deserialize)]
pub struct RefusalReasons {
    pub refusal_reasons: Vec<String>,
}

// Closure game canonicals
pub struct ClosureGameCanonicals {
    pub templates: ResponseTemplates,
    pub refusal_reasons: RefusalReasons,
    pub domain_contracts: HashMap<String, DomainContract>,
    pub report_schema_version: i64,
}

// Global canonicals cache
static CLOSURE_GAME_CANONICALS: OnceLock<Result<ClosureGameCanonicals, String>> = OnceLock::new();

/// Validate closure game canonicals on first access
pub fn validate_closure_game_canonicals() -> Result<()> {
    let result = CLOSURE_GAME_CANONICALS.get_or_init(|| {
        load_closure_game_canonicals()
            .map_err(|e| format!("Closure game canonicals validation failed: {}", e))
    });
    
    match result {
        Ok(_) => Ok(()),
        Err(e) => Err(anyhow!("{}", e)),
    }
}

/// Load and validate closure game canonicals
fn load_closure_game_canonicals() -> Result<ClosureGameCanonicals> {
    let base_path = Path::new("../../evidence/closure_game");
    
    // Verify CANONICALS.SHA256 exists
    let lockfile_path = base_path.join("CANONICALS.SHA256");
    if !lockfile_path.exists() {
        return Err(anyhow!("CANONICALS.SHA256 missing for closure_game"));
    }
    
    let lockfile_content = fs::read_to_string(&lockfile_path)?;
    let mut expected_hashes: HashMap<String, String> = HashMap::new();
    
    for line in lockfile_content.lines() {
        let parts: Vec<&str> = line.split_whitespace().collect();
        if parts.len() == 2 {
            expected_hashes.insert(parts[1].to_string(), parts[0].to_string());
        }
    }
    
    // Verify each canonical file
    let files = vec![
        "report_schema_version.json",
        "refusal_reasons.json",
        "response_templates.json",
        "domain_contract.schema.json",
        "claim_evaluation.schema.json",
        "closure_receipt.schema.json",
        "domain_contracts/generic.json",
    ];
    
    for filename in &files {
        let file_path = base_path.join(filename);
        if !file_path.exists() {
            return Err(anyhow!("Missing canonical file: {}", filename));
        }
        
        let content = fs::read(&file_path)?;
        let mut hasher = Sha256::new();
        hasher.update(&content);
        let computed_hash = format!("{:x}", hasher.finalize());
        
        if let Some(expected) = expected_hashes.get(*filename) {
            if &computed_hash != expected {
                return Err(anyhow!("Hash mismatch for {}: expected {}, got {}", 
                    filename, expected, computed_hash));
            }
        }
    }
    
    // Load canonicals
    let report_version: Value = serde_json::from_str(&fs::read_to_string(base_path.join("report_schema_version.json"))?)?;
    let report_schema_version = report_version["report_schema_version"].as_i64().unwrap_or(1);
    
    let templates: ResponseTemplates = serde_json::from_str(&fs::read_to_string(base_path.join("response_templates.json"))?)?;
    let refusal_reasons: RefusalReasons = serde_json::from_str(&fs::read_to_string(base_path.join("refusal_reasons.json"))?)?;
    
    // Load all domain contracts
    let mut domain_contracts = HashMap::new();
    let contracts_dir = base_path.join("domain_contracts");
    
    if contracts_dir.exists() {
        if let Ok(entries) = fs::read_dir(&contracts_dir) {
            for entry in entries.flatten() {
                if let Some(ext) = entry.path().extension() {
                    if ext == "json" {
                        let content = fs::read_to_string(entry.path())?;
                        let contract: DomainContract = serde_json::from_str(&content)?;
                        domain_contracts.insert(contract.domain_id.clone(), contract);
                    }
                }
            }
        }
    }
    
    Ok(ClosureGameCanonicals {
        templates,
        refusal_reasons,
        domain_contracts,
        report_schema_version,
    })
}

/// Get closure game canonicals (fail if not loaded)
pub fn get_canonicals() -> Result<&'static ClosureGameCanonicals> {
    let result = CLOSURE_GAME_CANONICALS.get()
        .ok_or_else(|| anyhow!("Closure game canonicals not initialized"))?;
    
    match result {
        Ok(canonicals) => Ok(canonicals),
        Err(e) => Err(anyhow!("{}", e)),
    }
}

/// Render template with substitutions
pub fn render_template(template_name: &str, substitutions: &HashMap<String, String>) -> Result<String> {
    let canonicals = get_canonicals()?;
    
    let template = canonicals.templates.templates.get(template_name)
        .ok_or_else(|| anyhow!("Template not found: {}", template_name))?;
    
    let mut rendered = template.clone();
    for (key, value) in substitutions {
        let placeholder = format!("<{}>", key);
        rendered = rendered.replace(&placeholder, value);
    }
    
    Ok(rendered)
}

/// Echo ledger entry
#[derive(Debug, Serialize, Deserialize)]
pub struct EchoLedgerEntry {
    pub nonce: String,
    pub agent_id: String,
    pub timestamp: String,
    pub sha256: String,
}

/// Append to echo ledger
pub fn append_to_echo_ledger(nonce: &str, agent_id: &str) -> Result<EchoLedgerEntry> {
    let ledger_path = "../../evidence/echo/echo_ledger.jsonl";
    let ledger_dir = Path::new(ledger_path).parent().unwrap();
    fs::create_dir_all(ledger_dir)?;
    
    let timestamp = Utc::now().to_rfc3339();
    
    // Compute hash over canonical payload (without sha256 field)
    let canonical_payload = format!(r#"{{"nonce":"{}","agent_id":"{}","timestamp":"{}"}}"#, nonce, agent_id, timestamp);
    let mut hasher = Sha256::new();
    hasher.update(canonical_payload.as_bytes());
    let sha256 = format!("{:x}", hasher.finalize());
    
    let entry = EchoLedgerEntry {
        nonce: nonce.to_string(),
        agent_id: agent_id.to_string(),
        timestamp: timestamp.clone(),
        sha256: sha256.clone(),
    };
    
    let entry_json = serde_json::to_string(&entry)?;
    let mut file = fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(ledger_path)?;
    
    use std::io::Write;
    writeln!(file, "{}", entry_json)?;
    
    Ok(entry)
}

/// Verify nonce in echo ledger
pub fn verify_echo_nonce(nonce: &str, agent_id: &str) -> Result<Option<EchoLedgerEntry>> {
    let ledger_path = "../../evidence/echo/echo_ledger.jsonl";
    
    if !Path::new(ledger_path).exists() {
        return Ok(None);
    }
    
    let content = fs::read_to_string(ledger_path)?;
    
    for line in content.lines() {
        if line.trim().is_empty() {
            continue;
        }
        
        let entry: EchoLedgerEntry = serde_json::from_str(line)?;
        
        if entry.nonce == nonce && entry.agent_id == agent_id {
            return Ok(Some(entry));
        }
    }
    
    Ok(None)
}

/// Get echo ledger hash
pub fn get_echo_ledger_hash() -> Result<String> {
    let ledger_path = "../../evidence/echo/echo_ledger.jsonl";
    
    if !Path::new(ledger_path).exists() {
        return Ok("sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855".to_string()); // Empty file hash
    }
    
    let content = fs::read(ledger_path)?;
    let mut hasher = Sha256::new();
    hasher.update(&content);
    Ok(format!("sha256:{:x}", hasher.finalize()))
}

/// Count echo ledger entries
pub fn count_echo_ledger_entries() -> Result<usize> {
    let ledger_path = "../../evidence/echo/echo_ledger.jsonl";
    
    if !Path::new(ledger_path).exists() {
        return Ok(0);
    }
    
    let content = fs::read_to_string(ledger_path)?;
    Ok(content.lines().filter(|l| !l.trim().is_empty()).count())
}

/// Compute canonicals hash
pub fn compute_canonicals_hash() -> Result<String> {
    let lockfile_path = "../../evidence/closure_game/CANONICALS.SHA256";
    let content = fs::read(lockfile_path)?;
    let mut hasher = Sha256::new();
    hasher.update(&content);
    Ok(format!("sha256:{:x}", hasher.finalize()))
}

/// Compute templates hash
pub fn compute_templates_hash() -> Result<String> {
    let templates_path = "../../evidence/closure_game/response_templates.json";
    let content = fs::read(templates_path)?;
    let mut hasher = Sha256::new();
    hasher.update(&content);
    Ok(format!("sha256:{:x}", hasher.finalize()))
}

/// Compute refusal reasons hash
pub fn compute_refusal_reasons_hash() -> Result<String> {
    let reasons_path = "../../evidence/closure_game/refusal_reasons.json";
    let content = fs::read(reasons_path)?;
    let mut hasher = Sha256::new();
    hasher.update(&content);
    Ok(format!("sha256:{:x}", hasher.finalize()))
}
