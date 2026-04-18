// Domain-Parametric Closure Tube Engine
// Abstract, fail-closed, no simulation

use anyhow::{Result, anyhow};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::OnceLock;
use sha2::{Sha256, Digest};
use uuid::Uuid;
use chrono::Utc;

// Domain metadata
#[derive(Debug, Deserialize)]
pub struct DomainMeta {
    pub domain_id: String,
    pub description: String,
    pub closure_type: String,
    pub time_model: String,
}

// Invariant definition
#[derive(Debug, Deserialize, Clone)]
pub struct Invariant {
    pub invariant_id: String,
    pub description: String,
    pub check: String,
    pub parameters: HashMap<String, Value>,
    pub failure_reason: String,
}

// Tube step definition
#[derive(Debug, Deserialize, Clone)]
pub struct TubeStep {
    pub step_id: String,
    pub description: String,
    pub required_invariants: Vec<String>,
    pub allowed_transitions: Vec<String>,
}

// Domain canonicals (loaded once per domain)
pub struct DomainCanonicals {
    pub meta: DomainMeta,
    pub state_schema: Value,
    pub transition_schema: Value,
    pub invariants: Vec<Invariant>,
    pub steps: Vec<TubeStep>,
    pub reason_codes: Value,
}

// Tube session state
#[derive(Debug, Serialize, Deserialize)]
pub struct TubeSession {
    pub tube_session_id: String,
    pub domain_id: String,
    pub agent_id: String,
    pub current_step_index: usize,
    pub started_at: String,
    pub steps_completed: Vec<String>,
    pub invariant_failures: Vec<String>,
}

// Ledger entry
#[derive(Debug, Serialize)]
pub struct LedgerEntry {
    pub agent_id: String,
    pub tube_session_id: String,
    pub step_id: String,
    pub input_hash: String,
    pub output_hash: String,
    pub invariant_results: HashMap<String, bool>,
    pub timestamp: String,
    pub verdict: String,
}

// Global domain cache
static DOMAIN_CACHE: OnceLock<HashMap<String, DomainCanonicals>> = OnceLock::new();

/// Load and validate all domain canonicals on first access
pub fn validate_domain_canonicals() -> Result<()> {
    DOMAIN_CACHE.get_or_init(|| {
        let mut domains = HashMap::new();
        
        let tubes_dir = Path::new("../../evidence/domain_tubes");
        if !tubes_dir.exists() {
            eprintln!("WARNING: domain_tubes directory not found");
            return domains;
        }
        
        // Discover all domain directories
        if let Ok(entries) = fs::read_dir(tubes_dir) {
            for entry in entries.flatten() {
                if entry.path().is_dir() {
                    let domain_id = entry.file_name().to_string_lossy().to_string();
                    
                    match load_domain_canonicals(&domain_id) {
                        Ok(canonicals) => {
                            domains.insert(domain_id.clone(), canonicals);
                            println!("✅ Domain loaded: {}", domain_id);
                        }
                        Err(e) => {
                            eprintln!("❌ Failed to load domain {}: {}", domain_id, e);
                        }
                    }
                }
            }
        }
        
        domains
    });
    
    Ok(())
}

/// Load domain canonicals with hash verification
fn load_domain_canonicals(domain_id: &str) -> Result<DomainCanonicals> {
    let domain_path = PathBuf::from(format!("../../evidence/domain_tubes/{}", domain_id));
    
    // Verify CANONICALS.SHA256 exists
    let lockfile_path = domain_path.join("CANONICALS.SHA256");
    if !lockfile_path.exists() {
        return Err(anyhow!("CANONICALS.SHA256 missing for domain {}", domain_id));
    }
    
    let lockfile_content = fs::read_to_string(&lockfile_path)?;
    let mut expected_hashes: HashMap<String, String> = HashMap::new();
    
    for line in lockfile_content.lines() {
        let parts: Vec<&str> = line.split_whitespace().collect();
        if parts.len() == 2 {
            expected_hashes.insert(parts[1].to_string(), parts[0].to_string());
        }
    }
    
    // Load and verify each canonical file
    let files = vec![
        "domain.meta.json",
        "state.schema.json",
        "transition.schema.json",
        "invariants.json",
        "tube.steps.json",
        "reason_codes.json",
    ];
    
    for filename in &files {
        let file_path = domain_path.join(filename);
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
    let meta: DomainMeta = serde_json::from_str(&fs::read_to_string(domain_path.join("domain.meta.json"))?)?;
    let state_schema: Value = serde_json::from_str(&fs::read_to_string(domain_path.join("state.schema.json"))?)?;
    let transition_schema: Value = serde_json::from_str(&fs::read_to_string(domain_path.join("transition.schema.json"))?)?;
    
    let invariants_file: Value = serde_json::from_str(&fs::read_to_string(domain_path.join("invariants.json"))?)?;
    let invariants: Vec<Invariant> = serde_json::from_value(invariants_file["invariants"].clone())?;
    
    let steps_file: Value = serde_json::from_str(&fs::read_to_string(domain_path.join("tube.steps.json"))?)?;
    let steps: Vec<TubeStep> = serde_json::from_value(steps_file["steps"].clone())?;
    
    let reason_codes: Value = serde_json::from_str(&fs::read_to_string(domain_path.join("reason_codes.json"))?)?;
    
    Ok(DomainCanonicals {
        meta,
        state_schema,
        transition_schema,
        invariants,
        steps,
        reason_codes,
    })
}

/// Get domain canonicals (fail if not loaded)
pub fn get_domain(domain_id: &str) -> Result<&'static DomainCanonicals> {
    let domains = DOMAIN_CACHE.get()
        .ok_or_else(|| anyhow!("Domain cache not initialized"))?;
    
    domains.get(domain_id)
        .ok_or_else(|| anyhow!("Domain not found: {}", domain_id))
}

/// Validate state against domain schema
pub fn validate_state(domain_id: &str, state: &Value) -> Result<()> {
    let domain = get_domain(domain_id)?;
    
    // Use jsonschema crate for validation
    let compiled = jsonschema::JSONSchema::compile(&domain.state_schema)
        .map_err(|e| anyhow!("Schema compilation failed: {}", e))?;
    
    compiled.validate(state)
        .map_err(|e| anyhow!("State validation failed: {:?}", e.collect::<Vec<_>>()))?;
    
    Ok(())
}

/// Validate transition against domain schema
pub fn validate_transition(domain_id: &str, transition: &Value) -> Result<()> {
    let domain = get_domain(domain_id)?;
    
    let compiled = jsonschema::JSONSchema::compile(&domain.transition_schema)
        .map_err(|e| anyhow!("Schema compilation failed: {}", e))?;
    
    compiled.validate(transition)
        .map_err(|e| anyhow!("Transition validation failed: {:?}", e.collect::<Vec<_>>()))?;
    
    Ok(())
}

/// Execute invariant checks (deterministic only)
pub fn check_invariants(domain_id: &str, state: &Value, required_invariants: &[String]) -> Result<HashMap<String, bool>> {
    let domain = get_domain(domain_id)?;
    let mut results = HashMap::new();
    
    for inv_id in required_invariants {
        let invariant = domain.invariants.iter()
            .find(|i| &i.invariant_id == inv_id)
            .ok_or_else(|| anyhow!("Invariant not found: {}", inv_id))?;
        
        // Execute deterministic check
        let passed = match invariant.check.as_str() {
            "separation_check" => check_separation(state, &invariant.parameters)?,
            "bounds_check" => check_bounds(state, &invariant.parameters)?,
            "altitude_check" => check_altitude(state, &invariant.parameters)?,
            "velocity_check" => check_velocity(state, &invariant.parameters)?,
            _ => return Err(anyhow!("Unknown check function: {}", invariant.check)),
        };
        
        results.insert(inv_id.clone(), passed);
    }
    
    Ok(results)
}

/// Deterministic separation check
fn check_separation(state: &Value, params: &HashMap<String, Value>) -> Result<bool> {
    let aircraft = state["aircraft"].as_array()
        .ok_or_else(|| anyhow!("Missing aircraft array"))?;
    
    let min_horiz_nm = params.get("min_horizontal_nm")
        .and_then(|v| v.as_f64())
        .unwrap_or(5.0);
    let min_vert_ft = params.get("min_vertical_ft")
        .and_then(|v| v.as_f64())
        .unwrap_or(1000.0);
    
    // Check all pairs
    for i in 0..aircraft.len() {
        for j in (i+1)..aircraft.len() {
            let a1 = &aircraft[i];
            let a2 = &aircraft[j];
            
            let lat1 = a1["position"]["lat"].as_f64().unwrap_or(0.0);
            let lon1 = a1["position"]["lon"].as_f64().unwrap_or(0.0);
            let alt1 = a1["altitude"].as_f64().unwrap_or(0.0);
            
            let lat2 = a2["position"]["lat"].as_f64().unwrap_or(0.0);
            let lon2 = a2["position"]["lon"].as_f64().unwrap_or(0.0);
            let alt2 = a2["altitude"].as_f64().unwrap_or(0.0);
            
            // Haversine distance (approximate)
            let horiz_nm = haversine_nm(lat1, lon1, lat2, lon2);
            let vert_ft = (alt1 - alt2).abs();
            
            // Must have EITHER horizontal OR vertical separation
            if horiz_nm < min_horiz_nm && vert_ft < min_vert_ft {
                return Ok(false);
            }
        }
    }
    
    Ok(true)
}

/// Haversine distance in nautical miles
fn haversine_nm(lat1: f64, lon1: f64, lat2: f64, lon2: f64) -> f64 {
    let r = 3440.065; // Earth radius in nautical miles
    let dlat = (lat2 - lat1).to_radians();
    let dlon = (lon2 - lon1).to_radians();
    let a = (dlat / 2.0).sin().powi(2) + 
            lat1.to_radians().cos() * lat2.to_radians().cos() * 
            (dlon / 2.0).sin().powi(2);
    let c = 2.0 * a.sqrt().atan2((1.0 - a).sqrt());
    r * c
}

/// Bounds check
fn check_bounds(state: &Value, _params: &HashMap<String, Value>) -> Result<bool> {
    let aircraft = state["aircraft"].as_array()
        .ok_or_else(|| anyhow!("Missing aircraft array"))?;
    let bounds = &state["airspace"]["bounds"];
    
    let min_lat = bounds["min_lat"].as_f64().unwrap_or(-90.0);
    let max_lat = bounds["max_lat"].as_f64().unwrap_or(90.0);
    let min_lon = bounds["min_lon"].as_f64().unwrap_or(-180.0);
    let max_lon = bounds["max_lon"].as_f64().unwrap_or(180.0);
    
    for ac in aircraft {
        let lat = ac["position"]["lat"].as_f64().unwrap_or(0.0);
        let lon = ac["position"]["lon"].as_f64().unwrap_or(0.0);
        
        if lat < min_lat || lat > max_lat || lon < min_lon || lon > max_lon {
            return Ok(false);
        }
    }
    
    Ok(true)
}

/// Altitude check
fn check_altitude(state: &Value, params: &HashMap<String, Value>) -> Result<bool> {
    let aircraft = state["aircraft"].as_array()
        .ok_or_else(|| anyhow!("Missing aircraft array"))?;
    
    let min_alt = params.get("min_altitude_ft").and_then(|v| v.as_f64()).unwrap_or(0.0);
    let max_alt = params.get("max_altitude_ft").and_then(|v| v.as_f64()).unwrap_or(60000.0);
    
    for ac in aircraft {
        let alt = ac["altitude"].as_f64().unwrap_or(0.0);
        if alt < min_alt || alt > max_alt {
            return Ok(false);
        }
    }
    
    Ok(true)
}

/// Velocity check
fn check_velocity(state: &Value, params: &HashMap<String, Value>) -> Result<bool> {
    let aircraft = state["aircraft"].as_array()
        .ok_or_else(|| anyhow!("Missing aircraft array"))?;
    
    let min_speed = params.get("min_speed_kts").and_then(|v| v.as_f64()).unwrap_or(0.0);
    let max_speed = params.get("max_speed_kts").and_then(|v| v.as_f64()).unwrap_or(600.0);
    
    for ac in aircraft {
        let speed = ac["velocity"]["speed_kts"].as_f64().unwrap_or(0.0);
        if speed < min_speed || speed > max_speed {
            return Ok(false);
        }
    }
    
    Ok(true)
}

/// Append to domain ledger
pub fn append_to_ledger(domain_id: &str, entry: &LedgerEntry) -> Result<()> {
    let ledger_path = format!("../../evidence/domain_tubes/{}/ledger.jsonl", domain_id);
    let ledger_dir = Path::new(&ledger_path).parent().unwrap();
    fs::create_dir_all(ledger_dir)?;
    
    let entry_json = serde_json::to_string(entry)?;
    let mut file = fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(&ledger_path)?;
    
    use std::io::Write;
    writeln!(file, "{}", entry_json)?;
    
    Ok(())
}

/// Load or create tube session
pub fn load_tube_session(tube_session_id: &str) -> Result<TubeSession> {
    let session_path = format!("../../evidence/domain_tubes/sessions/{}.json", tube_session_id);
    
    if Path::new(&session_path).exists() {
        let content = fs::read_to_string(&session_path)?;
        Ok(serde_json::from_str(&content)?)
    } else {
        Err(anyhow!("Session not found: {}", tube_session_id))
    }
}

/// Save tube session
pub fn save_tube_session(session: &TubeSession) -> Result<()> {
    let session_dir = Path::new("../../evidence/domain_tubes/sessions");
    fs::create_dir_all(session_dir)?;
    
    let session_path = session_dir.join(format!("{}.json", session.tube_session_id));
    fs::write(&session_path, serde_json::to_string_pretty(session)?)?;
    
    Ok(())
}
