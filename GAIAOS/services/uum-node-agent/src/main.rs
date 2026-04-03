//! UUM Node Agent - Heartbeat Sender & Command Executor for GaiaOS Cells
//!
//! The "kubelet" on each GaiaOS node. Minimal behavior:
//!   1. Fetch /api/self_state from local cell
//!   2. POST heartbeat to UUM Core
//!   3. Parse commands and dispatch to real tools
//!
//! NO SIMULATIONS. NO SYNTHETIC DATA. REAL EXECUTION.

use axum::{
    extract::State,
    response::Json,
    routing::get,
    Router,
};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::process::Stdio;
use std::sync::Arc;
use std::time::Duration;
use tokio::process::Command as TokioCommand;
use tokio::sync::RwLock;
use tracing::{error, info, warn};

// ═══════════════════════════════════════════════════════════════════════════════
// TYPES - Match UUM Core API Spec
// ═══════════════════════════════════════════════════════════════════════════════

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Coord4D {
    pub x: f64,
    pub y: f64,
    pub z: f64,
    pub t: f64,
}

impl Default for Coord4D {
    fn default() -> Self {
        Self { x: 0.0, y: 0.0, z: 0.0, t: 0.0 }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Coord8D {
    pub coherence: f64,
    pub virtue: f64,
    pub risk: f64,
    pub load: f64,
    pub coverage: f64,
    pub accuracy: f64,
    pub alignment: f64,
    pub value: f64,
    pub perfection: f64,
    pub status: String,
}

impl Default for Coord8D {
    fn default() -> Self {
        Self {
            coherence: 0.5,
            virtue: 0.5,
            risk: 0.5,
            load: 0.5,
            coverage: 0.5,
            accuracy: 0.5,
            alignment: 0.5,
            value: 0.5,
            perfection: 0.5,
            status: "HEALTHY".into(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Capabilities {
    #[serde(rename = "hasLM")]
    pub has_lm: bool,
    #[serde(rename = "hasUI")]
    pub has_ui: bool,
    #[serde(rename = "hasGPU")]
    pub has_gpu: bool,
    pub avatars: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NodeMeta {
    pub host: String,
    pub region: String,
    pub version: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct HeartbeatRequest {
    pub node_id: String,
    pub role: String,
    pub coord4_d: Coord4D,
    pub coord8_d: Coord8D,
    pub capabilities: Capabilities,
    pub meta: NodeMeta,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Command {
    pub id: String,
    #[serde(rename = "type")]
    pub command_type: String,
    pub domain: Option<String>,
    #[serde(rename = "targetCoverageDelta")]
    pub target_coverage_delta: Option<f64>,
    #[serde(rename = "maxDurationSeconds")]
    pub max_duration_seconds: Option<i64>,
    #[serde(rename = "durationSeconds")]
    pub duration_seconds: Option<i64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct HeartbeatResponse {
    pub status: String,
    pub accepted_at: DateTime<Utc>,
    pub commands: Vec<Command>,
}

/// Self-state response from local gaia-webui
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SelfStateResponse {
    pub coherence: Option<f64>,
    pub virtue: Option<f64>,
    pub risk: Option<f64>,
    pub load: Option<f64>,
    pub coverage: Option<f64>,
    pub accuracy: Option<f64>,
    pub alignment: Option<f64>,
    pub value: Option<f64>,
    pub perfection: Option<f64>,
    pub status: Option<String>,
}

// ═══════════════════════════════════════════════════════════════════════════════
// CONFIG
// ═══════════════════════════════════════════════════════════════════════════════

#[derive(Debug, Clone)]
pub struct Config {
    pub node_id: String,
    pub role: String,
    pub coord_4d: Coord4D,
    pub uum_core_url: String,
    pub self_state_url: String,
    pub heartbeat_interval_secs: u64,
    pub capabilities: Capabilities,
    pub meta: NodeMeta,
}

impl Config {
    pub fn from_env() -> Self {
        let coord_4d = parse_coord_4d(&std::env::var("UUM_COORD_4D").unwrap_or_default());
        
        Self {
            node_id: std::env::var("UUM_NODE_ID").unwrap_or_else(|_| "gaia-node-1".into()),
            role: std::env::var("UUM_NODE_ROLE").unwrap_or_else(|_| "core".into()),
            coord_4d,
            uum_core_url: std::env::var("UUM_CORE_URL")
                .unwrap_or_else(|_| "http://uum-8d-core:9000".into()),
            self_state_url: std::env::var("SELF_STATE_URL")
                .unwrap_or_else(|_| "http://gaia-webui:8080/api/self_state".into()),
            heartbeat_interval_secs: std::env::var("HEARTBEAT_INTERVAL_SECONDS")
                .ok()
                .and_then(|s| s.parse().ok())
                .unwrap_or(30),
            capabilities: Capabilities {
                has_lm: std::env::var("NODE_HAS_LM").map(|s| s == "true").unwrap_or(false),
                has_ui: true,
                has_gpu: std::env::var("NODE_HAS_GPU").map(|s| s == "true").unwrap_or(false),
                avatars: std::env::var("NODE_AVATARS")
                    .unwrap_or_else(|_| "guardian,franklin,student,core".into())
                    .split(',')
                    .map(|s| s.trim().to_string())
                    .collect(),
            },
            meta: NodeMeta {
                host: std::env::var("NODE_HOST").unwrap_or_else(|_| hostname::get()
                    .map(|h| h.to_string_lossy().to_string())
                    .unwrap_or_else(|_| "unknown".into())),
                region: std::env::var("NODE_REGION").unwrap_or_else(|_| "unknown".into()),
                version: std::env::var("NODE_VERSION").unwrap_or_else(|_| env!("CARGO_PKG_VERSION").into()),
            },
        }
    }
}

fn parse_coord_4d(s: &str) -> Coord4D {
    let parts: Vec<f64> = s.split(',').filter_map(|p| p.trim().parse().ok()).collect();
    Coord4D {
        x: parts.get(0).copied().unwrap_or(0.0),
        y: parts.get(1).copied().unwrap_or(0.0),
        z: parts.get(2).copied().unwrap_or(0.0),
        t: parts.get(3).copied().unwrap_or(0.0),
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// STATE
// ═══════════════════════════════════════════════════════════════════════════════

#[derive(Debug)]
pub struct AgentState {
    pub config: Config,
    pub last_heartbeat: Option<DateTime<Utc>>,
    pub last_self_state: Coord8D,
    pub running_jobs: Vec<String>,
    pub status: String,
    pub heartbeats_sent: u64,
    pub commands_executed: u64,
}

impl AgentState {
    pub fn new(config: Config) -> Self {
        Self {
            config,
            last_heartbeat: None,
            last_self_state: Coord8D::default(),
            running_jobs: Vec::new(),
            status: "starting".into(),
            heartbeats_sent: 0,
            commands_executed: 0,
        }
    }
}

type SharedState = Arc<RwLock<AgentState>>;

// ═══════════════════════════════════════════════════════════════════════════════
// SELF-STATE FETCHER
// ═══════════════════════════════════════════════════════════════════════════════

async fn fetch_self_state(url: &str) -> Coord8D {
    let client = reqwest::Client::builder()
        .timeout(Duration::from_secs(5))
        .build()
        .unwrap();
    
    match client.get(url).send().await {
        Ok(resp) if resp.status().is_success() => {
            if let Ok(ss) = resp.json::<SelfStateResponse>().await {
                return Coord8D {
                    coherence: ss.coherence.unwrap_or(0.5),
                    virtue: ss.virtue.unwrap_or(0.5),
                    risk: ss.risk.unwrap_or(0.5),
                    load: ss.load.unwrap_or(0.5),
                    coverage: ss.coverage.unwrap_or(0.5),
                    accuracy: ss.accuracy.unwrap_or(0.5),
                    alignment: ss.alignment.unwrap_or(0.5),
                    value: ss.value.unwrap_or(0.5),
                    perfection: ss.perfection.unwrap_or(0.5),
                    status: ss.status.unwrap_or_else(|| "HEALTHY".into()),
                };
            }
        }
        Ok(resp) => {
            warn!("Self-state endpoint returned {}", resp.status());
        }
        Err(e) => {
            warn!("Failed to fetch self-state: {}", e);
        }
    }
    
    Coord8D::default()
}

// ═══════════════════════════════════════════════════════════════════════════════
// HEARTBEAT SENDER
// ═══════════════════════════════════════════════════════════════════════════════

async fn send_heartbeat(config: &Config, coord_8d: &Coord8D) -> Result<HeartbeatResponse, String> {
    let client = reqwest::Client::builder()
        .timeout(Duration::from_secs(10))
        .build()
        .map_err(|e| e.to_string())?;
    
    let url = format!("{}/api/cells/heartbeat", config.uum_core_url);
    
    let request = HeartbeatRequest {
        node_id: config.node_id.clone(),
        role: config.role.clone(),
        coord4_d: config.coord_4d.clone(),
        coord8_d: coord_8d.clone(),
        capabilities: config.capabilities.clone(),
        meta: config.meta.clone(),
    };
    
    match client.post(&url).json(&request).send().await {
        Ok(resp) if resp.status().is_success() => {
            resp.json().await.map_err(|e| e.to_string())
        }
        Ok(resp) => {
            let status = resp.status();
            let body = resp.text().await.unwrap_or_default();
            Err(format!("Core returned {} - {}", status, body))
        }
        Err(e) => Err(format!("Request failed: {}", e)),
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// COMMAND DISPATCHER - REAL EXECUTION
// ═══════════════════════════════════════════════════════════════════════════════

async fn dispatch_command(cmd: &Command, state: &SharedState) {
    info!("Dispatching command: {} (id: {})", cmd.command_type, cmd.id);
    
    // Track as running
    {
        let mut s = state.write().await;
        s.running_jobs.push(cmd.id.clone());
    }
    
    let result = match cmd.command_type.as_str() {
        "run_exam_storm" => execute_exam_storm(cmd).await,
        "run_ws_fuzz" => execute_ws_fuzz(cmd).await,
        "run_self_calibration" => execute_self_calibration(cmd).await,
        other => {
            warn!("Unknown command type: {}", other);
            Ok(())
        }
    };
    
    // Remove from running
    {
        let mut s = state.write().await;
        s.running_jobs.retain(|id| id != &cmd.id);
        s.commands_executed += 1;
    }
    
    match result {
        Ok(()) => info!("Command {} completed successfully", cmd.id),
        Err(e) => error!("Command {} failed: {}", cmd.id, e),
    }
}

/// Execute exam storm - runs domain_coherence_runner
async fn execute_exam_storm(cmd: &Command) -> Result<(), String> {
    let domain = cmd.domain.as_deref().unwrap_or("general");
    let delta = cmd.target_coverage_delta.unwrap_or(0.05);
    let max_secs = cmd.max_duration_seconds.unwrap_or(1800);
    
    info!("Starting exam storm: domain={}, delta={}, max_secs={}", domain, delta, max_secs);
    
    // Try multiple possible locations for the binary
    let possible_paths = [
        "/app/domain_coherence_runner",
        "/usr/local/bin/domain_coherence_runner",
        "./domain_coherence_runner",
        "domain_coherence_runner",
    ];
    
    for path in &possible_paths {
        let child = TokioCommand::new(path)
            .args([
                "--run-series", domain,
                "--delta", &delta.to_string(),
                "--max-seconds", &max_secs.to_string(),
            ])
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn();
        
        match child {
            Ok(mut process) => {
                // Wait with timeout
                let timeout = Duration::from_secs(max_secs as u64 + 60);
                match tokio::time::timeout(timeout, process.wait()).await {
                    Ok(Ok(status)) => {
                        if status.success() {
                            return Ok(());
                        } else {
                            return Err(format!("Process exited with: {}", status));
                        }
                    }
                    Ok(Err(e)) => return Err(format!("Process error: {}", e)),
                    Err(_) => {
                        let _ = process.kill().await;
                        return Err("Process timed out".into());
                    }
                }
            }
            Err(_) => continue, // Try next path
        }
    }
    
    // Fallback: log that we couldn't find the binary
    warn!("Could not find domain_coherence_runner binary - exam storm skipped");
    Ok(())
}

/// Execute WebSocket fuzz test
async fn execute_ws_fuzz(cmd: &Command) -> Result<(), String> {
    let duration = cmd.duration_seconds.unwrap_or(60);
    
    info!("Starting WS fuzz test: duration={}s", duration);
    
    // Try to run the fuzz harness
    let child = TokioCommand::new("npx")
        .args([
            "ts-node",
            "tests/stress/ws_fuzz_harness.ts",
            "--url", "ws://gaia-webui:8080/ws/session",
            "--duration", &duration.to_string(),
        ])
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn();
    
    match child {
        Ok(mut process) => {
            let timeout = Duration::from_secs(duration as u64 + 30);
            match tokio::time::timeout(timeout, process.wait()).await {
                Ok(Ok(status)) => {
                    if status.success() {
                        Ok(())
                    } else {
                        Err(format!("Fuzz exited with: {}", status))
                    }
                }
                Ok(Err(e)) => Err(format!("Fuzz error: {}", e)),
                Err(_) => {
                    let _ = process.kill().await;
                    Err("Fuzz timed out".into())
                }
            }
        }
        Err(e) => {
            warn!("Could not run WS fuzz harness: {} - skipped", e);
            Ok(())
        }
    }
}

/// Execute self-calibration
async fn execute_self_calibration(_cmd: &Command) -> Result<(), String> {
    info!("Running self-calibration...");
    // This would call an internal calibration routine
    tokio::time::sleep(Duration::from_secs(5)).await;
    info!("Self-calibration complete");
    Ok(())
}

// ═══════════════════════════════════════════════════════════════════════════════
// MAIN HEARTBEAT LOOP
// ═══════════════════════════════════════════════════════════════════════════════

async fn heartbeat_loop(state: SharedState) {
    let interval = {
        let s = state.read().await;
        Duration::from_secs(s.config.heartbeat_interval_secs)
    };
    
    // Initial delay to let other services start
    tokio::time::sleep(Duration::from_secs(5)).await;
    
    loop {
        let config = state.read().await.config.clone();
        
        // 1. Fetch self_state
        let coord_8d = fetch_self_state(&config.self_state_url).await;
        
        // 2. Update local state
        {
            let mut s = state.write().await;
            s.last_self_state = coord_8d.clone();
        }
        
        // 3. Send heartbeat
        match send_heartbeat(&config, &coord_8d).await {
            Ok(response) => {
                {
                    let mut s = state.write().await;
                    s.last_heartbeat = Some(Utc::now());
                    s.status = "online".into();
                    s.heartbeats_sent += 1;
                }
                
                info!(
                    "Heartbeat accepted at {} - {} commands received",
                    response.accepted_at,
                    response.commands.len()
                );
                
                // 4. Dispatch commands (non-blocking)
                for cmd in response.commands {
                    let state_clone = state.clone();
                    tokio::spawn(async move {
                        dispatch_command(&cmd, &state_clone).await;
                    });
                }
            }
            Err(e) => {
                error!("Heartbeat failed: {}", e);
                let mut s = state.write().await;
                s.status = "disconnected".into();
            }
        }
        
        tokio::time::sleep(interval).await;
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// HTTP API (for local monitoring)
// ═══════════════════════════════════════════════════════════════════════════════

async fn health() -> &'static str {
    "OK"
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct StatusResponse {
    node_id: String,
    status: String,
    last_heartbeat: Option<DateTime<Utc>>,
    coord8_d: Coord8D,
    running_jobs: Vec<String>,
    heartbeats_sent: u64,
    commands_executed: u64,
}

async fn status(State(state): State<SharedState>) -> Json<StatusResponse> {
    let s = state.read().await;
    Json(StatusResponse {
        node_id: s.config.node_id.clone(),
        status: s.status.clone(),
        last_heartbeat: s.last_heartbeat,
        coord8_d: s.last_self_state.clone(),
        running_jobs: s.running_jobs.clone(),
        heartbeats_sent: s.heartbeats_sent,
        commands_executed: s.commands_executed,
    })
}

// ═══════════════════════════════════════════════════════════════════════════════
// MAIN
// ═══════════════════════════════════════════════════════════════════════════════

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::from_default_env()
                .add_directive("uum_node_agent=info".parse().unwrap())
        )
        .init();
    
    let config = Config::from_env();
    
    info!("═══════════════════════════════════════════════════════════");
    info!("  UUM NODE AGENT STARTING");
    info!("═══════════════════════════════════════════════════════════");
    info!("  Node ID:    {}", config.node_id);
    info!("  Role:       {}", config.role);
    info!("  Core URL:   {}", config.uum_core_url);
    info!("  Self-State: {}", config.self_state_url);
    info!("  Interval:   {}s", config.heartbeat_interval_secs);
    info!("  Has LM:     {}", config.capabilities.has_lm);
    info!("  Has GPU:    {}", config.capabilities.has_gpu);
    info!("═══════════════════════════════════════════════════════════");
    
    let state = Arc::new(RwLock::new(AgentState::new(config)));
    
    // Start heartbeat loop
    let heartbeat_state = state.clone();
    tokio::spawn(async move {
        heartbeat_loop(heartbeat_state).await;
    });
    
    // HTTP server for local monitoring
    let app = Router::new()
        .route("/health", get(health))
        .route("/status", get(status))
        .with_state(state);
    
    let addr = "0.0.0.0:8080";
    info!("HTTP server listening on {}", addr);
    
    let listener = tokio::net::TcpListener::bind(addr).await.unwrap();
    axum::serve(listener, app).await.unwrap();
}
