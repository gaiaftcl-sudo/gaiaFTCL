//! vChip (GAIA-1 Virtual Chip) MCP Tools
//!
//! Quantum-like computation tools for the vQbit processor.

use crate::McpTool;
use anyhow::Result;
use serde::{Deserialize, Serialize};
use serde_json::json;

/// vChip tools handler
pub struct VChipTools {
    base_url: String,
    client: reqwest::Client,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct VqExecutionResult {
    pub coherence: f32,
    pub measurements: Vec<bool>,
    pub attractor: Option<Uum8dCoord>,
    pub cycles: u64,
    pub virtue_delta: [f32; 8],
}

#[derive(Debug, Serialize, Deserialize)]
pub struct Uum8dCoord {
    pub coords: [u32; 8],
}

impl VChipTools {
    pub fn new(base_url: &str) -> Self {
        Self {
            base_url: base_url.to_string(),
            client: reqwest::Client::new(),
        }
    }

    /// Get tool definitions for vChip
    pub fn get_tool_definitions(&self) -> Vec<McpTool> {
        vec![
            McpTool {
                name: "vchip_init".into(),
                description: "Initialize vQbit register with n qubits in |0⟩ state".into(),
                input_schema: json!({
                    "type": "object",
                    "properties": {
                        "n_qubits": {
                            "type": "integer",
                            "description": "Number of qubits to initialize (max 2048)",
                            "default": 8
                        }
                    },
                    "required": []
                }),
            },
            McpTool {
                name: "vchip_run_program".into(),
                description:
                    "Execute a quantum program on the GAIA-1 vChip and get collapse results".into(),
                input_schema: json!({
                    "type": "object",
                    "properties": {
                        "program_type": {
                            "type": "string",
                            "enum": ["bell", "ghz", "qft", "grover", "vqe", "coherence_test", "virtue_eval", "custom"],
                            "description": "Type of quantum program to run"
                        },
                        "n_qubits": {
                            "type": "integer",
                            "description": "Number of qubits (default: 8)"
                        },
                        "depth": {
                            "type": "integer",
                            "description": "Circuit depth for VQE (default: 4)"
                        },
                        "virtue_weights": {
                            "type": "array",
                            "items": {"type": "number"},
                            "description": "8 virtue weights for virtue_eval program"
                        }
                    },
                    "required": ["program_type"]
                }),
            },
            McpTool {
                name: "vchip_collapse".into(),
                description: "Collapse vQbit state to 8D attractor by measuring specified qubits"
                    .into(),
                input_schema: json!({
                    "type": "object",
                    "properties": {
                        "targets": {
                            "type": "array",
                            "items": {"type": "integer"},
                            "description": "Qubit indices to measure (empty = measure all)"
                        }
                    },
                    "required": []
                }),
            },
            McpTool {
                name: "vchip_coherence".into(),
                description: "Get current coherence (purity) of the vQbit state".into(),
                input_schema: json!({
                    "type": "object",
                    "properties": {},
                    "required": []
                }),
            },
            McpTool {
                name: "vchip_bell_state".into(),
                description: "Create a Bell state (maximally entangled 2-qubit state)".into(),
                input_schema: json!({
                    "type": "object",
                    "properties": {},
                    "required": []
                }),
            },
            McpTool {
                name: "vchip_grover".into(),
                description: "Run Grover's search algorithm to amplify marked states".into(),
                input_schema: json!({
                    "type": "object",
                    "properties": {
                        "n_qubits": {
                            "type": "integer",
                            "description": "Number of qubits in search space",
                            "default": 4
                        },
                        "iterations": {
                            "type": "integer",
                            "description": "Number of Grover iterations (optimal ≈ π/4 * √N)",
                            "default": 2
                        }
                    },
                    "required": []
                }),
            },
            McpTool {
                name: "vchip_status".into(),
                description: "Get vChip status including backend, stats, and current state info"
                    .into(),
                input_schema: json!({
                    "type": "object",
                    "properties": {},
                    "required": []
                }),
            },
        ]
    }

    /// Call a vChip tool
    pub async fn call(&self, name: &str, args: serde_json::Value) -> Result<serde_json::Value> {
        match name {
            "vchip_init" => self.init(args).await,
            "vchip_run_program" => self.run_program(args).await,
            "vchip_collapse" => self.collapse(args).await,
            "vchip_coherence" => self.coherence().await,
            "vchip_bell_state" => self.bell_state().await,
            "vchip_grover" => self.grover(args).await,
            "vchip_status" => self.status().await,
            _ => Err(anyhow::anyhow!("Unknown vchip tool: {name}")),
        }
    }

    async fn init(&self, args: serde_json::Value) -> Result<serde_json::Value> {
        let n_qubits = args.get("n_qubits").and_then(|v| v.as_i64()).unwrap_or(8) as usize;

        let response = self
            .client
            .post(format!("{}/init", self.base_url))
            .json(&json!({"n_qubits": n_qubits}))
            .send()
            .await;

        match response {
            Ok(resp) if resp.status().is_success() => Ok(json!({
                "success": true,
                "n_qubits": n_qubits,
                "state_size": 1 << n_qubits,
                "message": format!("Initialized {} vQbits in |0⟩ state", n_qubits)
            })),
            Ok(resp) => {
                let status = resp.status();
                let text = resp.text().await.unwrap_or_default();
                Err(anyhow::anyhow!("vChip init failed: {status} - {text}"))
            }
            Err(e) => {
                // NO SIMULATION - FAIL HARD
                // The vChip service MUST be available for quantum operations
                Err(anyhow::anyhow!(
                    "vChip service unavailable: {e} - NO SIMULATION ALLOWED"
                ))
            }
        }
    }

    async fn run_program(&self, args: serde_json::Value) -> Result<serde_json::Value> {
        let program_type = args
            .get("program_type")
            .and_then(|v| v.as_str())
            .unwrap_or("bell");
        let n_qubits = args.get("n_qubits").and_then(|v| v.as_i64()).unwrap_or(8) as usize;
        let depth = args.get("depth").and_then(|v| v.as_i64()).unwrap_or(4) as usize;

        let response = self
            .client
            .post(format!("{}/run", self.base_url))
            .json(&json!({
                "program_type": program_type,
                "n_qubits": n_qubits,
                "depth": depth
            }))
            .send()
            .await;

        match response {
            Ok(resp) if resp.status().is_success() => {
                let result: serde_json::Value = resp.json().await?;
                Ok(result)
            }
            Ok(resp) => {
                let status = resp.status();
                let text = resp.text().await.unwrap_or_default();
                Err(anyhow::anyhow!("vChip run failed: {status} - {text}"))
            }
            Err(e) => {
                // NO SIMULATION - FAIL HARD
                // Quantum programs MUST execute on real vChip substrate
                Err(anyhow::anyhow!(
                    "vChip program execution failed: {e} - NO SIMULATION ALLOWED"
                ))
            }
        }
    }

    async fn collapse(&self, args: serde_json::Value) -> Result<serde_json::Value> {
        let targets: Vec<i64> = args
            .get("targets")
            .and_then(|v| v.as_array())
            .map(|arr| arr.iter().filter_map(|v| v.as_i64()).collect())
            .unwrap_or_default();

        let response = self
            .client
            .post(format!("{}/collapse", self.base_url))
            .json(&json!({"targets": targets}))
            .send()
            .await;

        match response {
            Ok(resp) if resp.status().is_success() => {
                let result: serde_json::Value = resp.json().await?;
                Ok(result)
            }
            Ok(resp) => {
                let status = resp.status();
                let text = resp.text().await.unwrap_or_default();
                Err(anyhow::anyhow!(
                    "vChip collapse failed: {status} - {text} - NO SIMULATION ALLOWED"
                ))
            }
            Err(e) => {
                // NO SIMULATION - FAIL HARD
                Err(anyhow::anyhow!(
                    "vChip collapse unavailable: {e} - NO SIMULATION ALLOWED"
                ))
            }
        }
    }

    async fn coherence(&self) -> Result<serde_json::Value> {
        let response = self
            .client
            .get(format!("{}/coherence", self.base_url))
            .send()
            .await;

        match response {
            Ok(resp) if resp.status().is_success() => {
                let result: serde_json::Value = resp.json().await?;
                Ok(result)
            }
            Ok(resp) => {
                let status = resp.status();
                let text = resp.text().await.unwrap_or_default();
                Err(anyhow::anyhow!(
                    "vChip coherence check failed: {status} - {text} - NO SIMULATION ALLOWED"
                ))
            }
            Err(e) => {
                // NO SIMULATION - FAIL HARD
                Err(anyhow::anyhow!(
                    "vChip coherence unavailable: {e} - NO SIMULATION ALLOWED"
                ))
            }
        }
    }

    async fn bell_state(&self) -> Result<serde_json::Value> {
        self.run_program(json!({"program_type": "bell", "n_qubits": 2}))
            .await
    }

    async fn grover(&self, args: serde_json::Value) -> Result<serde_json::Value> {
        let n_qubits = args.get("n_qubits").and_then(|v| v.as_i64()).unwrap_or(4);
        let iterations = args.get("iterations").and_then(|v| v.as_i64()).unwrap_or(2);

        self.run_program(json!({
            "program_type": "grover",
            "n_qubits": n_qubits,
            "iterations": iterations
        }))
        .await
    }

    async fn status(&self) -> Result<serde_json::Value> {
        let response = self
            .client
            .get(format!("{}/status", self.base_url))
            .send()
            .await;

        match response {
            Ok(resp) if resp.status().is_success() => {
                let result: serde_json::Value = resp.json().await?;
                Ok(result)
            }
            Ok(resp) => {
                let status = resp.status();
                let text = resp.text().await.unwrap_or_default();
                // Status check can return unavailable state without failing
                Ok(json!({
                    "backend": "unknown",
                    "max_qubits": 0,
                    "current_qubits": 0,
                    "available": false,
                    "error": format!("vChip status check failed: {} - {}", status, text)
                }))
            }
            Err(e) => {
                // Status check returns unavailable state - not simulated data
                Ok(json!({
                    "backend": "unknown",
                    "max_qubits": 0,
                    "current_qubits": 0,
                    "available": false,
                    "error": format!("vChip service unreachable: {}", e)
                }))
            }
        }
    }
}

// Removed: rand module for simulation - NO SIMULATION ALLOWED
