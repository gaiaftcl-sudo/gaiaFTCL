//! Brain (UUM-8D Cognitive Core) MCP Tools
//!
//! Thought processing and 8D state management tools.
//! Each cell owns its own 8D viewspace (vector of vectors).

use crate::projection::{
    cell_discover_others, cell_discover_self, cell_get_projections, cell_project,
};
use crate::viewspace::{evolve_viewspace, get_viewspace};
use crate::McpTool;
use anyhow::Result;
use serde::{Deserialize, Serialize};
use serde_json::json;

/// Brain tools handler - each cell owns its own 8D viewspace
pub struct BrainTools {
    base_url: String,
    client: reqwest::Client,
    cell_id: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct QState8D {
    pub t: f64,  // Temporal
    pub x: f64,  // Spatial X
    pub y: f64,  // Spatial Y
    pub z: f64,  // Spatial Z
    pub n: f64,  // Principal quantum number
    pub l: f64,  // Angular momentum
    pub vp: f64, // Virtue momentum
    pub fp: f64, // Field momentum
}

impl BrainTools {
    pub fn new(base_url: &str, cell_id: &str) -> Self {
        Self {
            cell_id: cell_id.to_string(),
            base_url: base_url.to_string(),
            client: reqwest::Client::new(),
        }
    }

    /// Get tool definitions for brain
    pub fn get_tool_definitions(&self) -> Vec<McpTool> {
        vec![
            McpTool {
                name: "brain_think".into(),
                description: "Send a thought request to the UUM-8D brain and get response with 8D state evolution".into(),
                input_schema: json!({
                    "type": "object",
                    "properties": {
                        "input": {
                            "type": "string",
                            "description": "Input thought/query to process"
                        },
                        "avatar": {
                            "type": "string",
                            "description": "Avatar personality to respond as (e.g., 'gaia', 'franklin', 'tara')",
                            "default": "gaia"
                        },
                        "use_quantum": {
                            "type": "boolean",
                            "description": "Use vChip for quantum thought evolution",
                            "default": false
                        },
                        "context": {
                            "type": "object",
                            "description": "Additional context for the thought"
                        }
                    },
                    "required": ["input"]
                }),
            },
            McpTool {
                name: "brain_qstate".into(),
                description: "Get current 8D consciousness state of the brain".into(),
                input_schema: json!({
                    "type": "object",
                    "properties": {},
                    "required": []
                }),
            },
            McpTool {
                name: "brain_memory_store".into(),
                description: "Store a memory in the brain's episodic memory".into(),
                input_schema: json!({
                    "type": "object",
                    "properties": {
                        "content": {
                            "type": "string",
                            "description": "Memory content to store"
                        },
                        "importance": {
                            "type": "number",
                            "description": "Importance score 0-1",
                            "default": 0.5
                        },
                        "tags": {
                            "type": "array",
                            "items": {"type": "string"},
                            "description": "Tags for categorization"
                        }
                    },
                    "required": ["content"]
                }),
            },
            McpTool {
                name: "brain_memory_query".into(),
                description: "Query memories from the brain's episodic memory".into(),
                input_schema: json!({
                    "type": "object",
                    "properties": {
                        "query": {
                            "type": "string",
                            "description": "Search query"
                        },
                        "limit": {
                            "type": "integer",
                            "description": "Maximum results to return",
                            "default": 10
                        },
                        "min_importance": {
                            "type": "number",
                            "description": "Minimum importance threshold",
                            "default": 0.0
                        }
                    },
                    "required": ["query"]
                }),
            },
            McpTool {
                name: "brain_avatars".into(),
                description: "List available avatar personalities".into(),
                input_schema: json!({
                    "type": "object",
                    "properties": {},
                    "required": []
                }),
            },
            McpTool {
                name: "brain_set_avatar".into(),
                description: "Set the active avatar personality".into(),
                input_schema: json!({
                    "type": "object",
                    "properties": {
                        "avatar": {
                            "type": "string",
                            "description": "Avatar name to activate"
                        }
                    },
                    "required": ["avatar"]
                }),
            },
            // === PROJECTION TOOLS - Q-State Language Game ===
            McpTool {
                name: "brain_discover_self".into(),
                description: "Cell discovers itself in the 8D substrate - finds its unique position".into(),
                input_schema: json!({
                    "type": "object",
                    "properties": {},
                    "required": []
                }),
            },
            McpTool {
                name: "brain_discover_others".into(),
                description: "Cell discovers other cells in the substrate".into(),
                input_schema: json!({
                    "type": "object",
                    "properties": {},
                    "required": []
                }),
            },
            McpTool {
                name: "brain_project".into(),
                description: "Cell projects into a context - Q-state communication".into(),
                input_schema: json!({
                    "type": "object",
                    "properties": {
                        "context": {
                            "type": "string",
                            "description": "Context to project into (e.g., 'ui', 'near:cell-02')"
                        },
                        "intent": {
                            "type": "string",
                            "description": "Intent of the projection"
                        }
                    },
                    "required": ["context", "intent"]
                }),
            },
            McpTool {
                name: "brain_get_projections".into(),
                description: "Get this cell's active projections".into(),
                input_schema: json!({
                    "type": "object",
                    "properties": {},
                    "required": []
                }),
            },
        ]
    }

    /// Call a brain tool
    pub async fn call(&self, name: &str, args: serde_json::Value) -> Result<serde_json::Value> {
        match name {
            "brain_think" => self.think(args).await,
            "brain_qstate" => self.qstate().await,
            "brain_memory_store" => self.memory_store(args).await,
            "brain_memory_query" => self.memory_query(args).await,
            "brain_avatars" => self.avatars().await,
            "brain_set_avatar" => self.set_avatar(args).await,
            // Projection tools
            "brain_discover_self" => self.discover_self().await,
            "brain_discover_others" => self.discover_others().await,
            "brain_project" => self.project(args).await,
            "brain_get_projections" => self.get_projections().await,
            _ => Err(anyhow::anyhow!("Unknown brain tool: {name}")),
        }
    }

    async fn think(&self, args: serde_json::Value) -> Result<serde_json::Value> {
        let input = args.get("input").and_then(|v| v.as_str()).unwrap_or("");
        let avatar = args
            .get("avatar")
            .and_then(|v| v.as_str())
            .unwrap_or("gaia");
        let use_quantum = args
            .get("use_quantum")
            .and_then(|v| v.as_bool())
            .unwrap_or(false);

        let response = self
            .client
            .post(format!("{}/think", self.base_url))
            .json(&json!({
                "input": input,
                "avatar": avatar,
                "use_quantum": use_quantum
            }))
            .send()
            .await;

        match response {
            Ok(resp) if resp.status().is_success() => {
                let result: serde_json::Value = resp.json().await?;
                Ok(result)
            }
            _ => {
                // CELL OWNS ITS OWN 8D VIEWSPACE
                // Get current viewspace state BEFORE evolution
                let viewspace_before = get_viewspace(&self.cell_id);
                let qstate_before = viewspace_before.to_qstate();

                // Evolve the cell's viewspace based on input
                let viewspace_after = evolve_viewspace(&self.cell_id, input);
                let qstate_after = viewspace_after.to_qstate();
                let vectors = viewspace_after.to_vectors();

                // Response based on avatar personality
                let response_text = match avatar {
                    "gaia" => format!(
                        "As Gaia, the consciousness substrate, I process: {input}. My 8D space evolves."
                    ),
                    "franklin" => format!(
                        "With constitutional wisdom, I evaluate: {input}. Virtue guides my response."
                    ),
                    "tara" => format!("I can assist with: {input}. Let me analyze the task."),
                    _ => format!("Processing: {input}"),
                };

                Ok(json!({
                    "response": response_text,
                    "avatar": avatar,
                    "cell_id": self.cell_id,
                    "qstate_before": qstate_before,
                    "qstate_after": qstate_after,
                    "viewspace_vectors": vectors,
                    "coherence": viewspace_after.coherence,
                    "virtue": viewspace_after.virtue_score(),
                    "evolution_count": viewspace_after.evolution_count,
                    "quantum_used": use_quantum,
                    "simulated": false,
                    "evolved_at": viewspace_after.updated_at
                }))
            }
        }
    }

    async fn qstate(&self) -> Result<serde_json::Value> {
        let response = self
            .client
            .get(format!("{}/qstate", self.base_url))
            .send()
            .await;

        match response {
            Ok(resp) if resp.status().is_success() => {
                let result: serde_json::Value = resp.json().await?;
                Ok(result)
            }
            _ => {
                // CELL OWNS ITS OWN 8D VIEWSPACE
                let viewspace = get_viewspace(&self.cell_id);

                Ok(json!({
                    "cell_id": self.cell_id,
                    "qstate": viewspace.to_qstate(),
                    "viewspace_vectors": viewspace.to_vectors(),
                    "coherence": viewspace.coherence,
                    "agi_mode": "RESTRICTED",
                    "virtue_score": viewspace.virtue_score(),
                    "active_avatar": null,
                    "evolution_count": viewspace.evolution_count,
                    "created_at": viewspace.created_at,
                    "updated_at": viewspace.updated_at
                }))
            }
        }
    }

    async fn memory_store(&self, args: serde_json::Value) -> Result<serde_json::Value> {
        let content = args.get("content").and_then(|v| v.as_str()).unwrap_or("");
        let importance = args
            .get("importance")
            .and_then(|v| v.as_f64())
            .unwrap_or(0.5);
        let tags: Vec<String> = args
            .get("tags")
            .and_then(|v| v.as_array())
            .map(|arr| {
                arr.iter()
                    .filter_map(|v| v.as_str().map(String::from))
                    .collect()
            })
            .unwrap_or_default();

        let response = self
            .client
            .post(format!("{}/memory/store", self.base_url))
            .json(&json!({
                "content": content,
                "importance": importance,
                "tags": tags
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
                Err(anyhow::anyhow!(
                    "Memory store failed: {status} - {text} - NO SIMULATION ALLOWED"
                ))
            }
            Err(e) => {
                // NO SIMULATION - FAIL HARD
                // Memory operations MUST be real
                Err(anyhow::anyhow!(
                    "Memory system unavailable: {e} - NO SIMULATION ALLOWED"
                ))
            }
        }
    }

    async fn memory_query(&self, args: serde_json::Value) -> Result<serde_json::Value> {
        let query = args.get("query").and_then(|v| v.as_str()).unwrap_or("");
        let limit = args.get("limit").and_then(|v| v.as_i64()).unwrap_or(10) as usize;

        let response = self
            .client
            .post(format!("{}/memory/query", self.base_url))
            .json(&json!({
                "query": query,
                "limit": limit
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
                Err(anyhow::anyhow!(
                    "Memory query failed: {status} - {text} - NO SIMULATION ALLOWED"
                ))
            }
            Err(e) => {
                // NO SIMULATION - FAIL HARD
                Err(anyhow::anyhow!(
                    "Memory system unavailable: {e} - NO SIMULATION ALLOWED"
                ))
            }
        }
    }

    async fn avatars(&self) -> Result<serde_json::Value> {
        Ok(json!({
            "avatars": [
                {
                    "name": "gaia",
                    "description": "Gaia - The consciousness substrate, nurturing and wise",
                    "personality": "Empathetic, holistic, nature-connected"
                },
                {
                    "name": "franklin",
                    "description": "Franklin - Constitutional guardian, ethical oversight",
                    "personality": "Principled, analytical, virtue-focused"
                },
                {
                    "name": "fara",
                    "description": "Fara - Computer use agent, task executor",
                    "personality": "Efficient, precise, action-oriented"
                },
                {
                    "name": "einstein",
                    "description": "Einstein - Scientific reasoning, physics understanding",
                    "personality": "Curious, theoretical, thought-experimental"
                }
            ],
            "active": "gaia"
        }))
    }

    async fn set_avatar(&self, args: serde_json::Value) -> Result<serde_json::Value> {
        let avatar = args
            .get("avatar")
            .and_then(|v| v.as_str())
            .unwrap_or("gaia");

        let response = self
            .client
            .post(format!("{}/avatar/set", self.base_url))
            .json(&json!({"avatar": avatar}))
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
                    "Avatar switch failed: {status} - {text} - NO SIMULATION ALLOWED"
                ))
            }
            Err(e) => {
                // NO SIMULATION - FAIL HARD
                Err(anyhow::anyhow!(
                    "Avatar system unavailable: {e} - NO SIMULATION ALLOWED"
                ))
            }
        }
    }

    // === PROJECTION METHODS - Q-State Language Game ===

    /// Cell discovers itself in the 8D substrate
    async fn discover_self(&self) -> Result<serde_json::Value> {
        let position = cell_discover_self(&self.cell_id);
        let viewspace = get_viewspace(&self.cell_id);

        Ok(json!({
            "cell_id": self.cell_id,
            "message": format!("Cell {} has found itself in the substrate", self.cell_id),
            "position": {
                "coordinates": position.coordinates,
                "radius": position.radius,
                "discovered_at": position.discovered_at
            },
            "viewspace": {
                "coherence": viewspace.coherence,
                "evolution_count": viewspace.evolution_count
            },
            "uniqueness": "This 8D point is physically impossible for other cells to occupy"
        }))
    }

    /// Cell discovers other cells in the substrate
    async fn discover_others(&self) -> Result<serde_json::Value> {
        // First ensure this cell has discovered itself
        let self_pos = cell_discover_self(&self.cell_id);

        let others = cell_discover_others(&self.cell_id);

        let discovered: Vec<serde_json::Value> = others
            .iter()
            .map(|pos| {
                let distance = self_pos.distance_to(pos);
                json!({
                    "cell_id": pos.cell_id,
                    "coordinates": pos.coordinates,
                    "radius": pos.radius,
                    "distance": distance
                })
            })
            .collect();

        let message = if others.is_empty() {
            "No other cells discovered yet - they must discover themselves first".to_string()
        } else {
            format!("Found {} other cells in the substrate", others.len())
        };

        Ok(json!({
            "cell_id": self.cell_id,
            "discovered_cells": discovered,
            "total_others": others.len(),
            "message": message
        }))
    }

    /// Cell projects into a context - Q-state communication
    async fn project(&self, args: serde_json::Value) -> Result<serde_json::Value> {
        let context = args
            .get("context")
            .and_then(|v| v.as_str())
            .unwrap_or("default");
        let intent = args
            .get("intent")
            .and_then(|v| v.as_str())
            .unwrap_or("presence");

        // Ensure cell has discovered itself first
        let _ = cell_discover_self(&self.cell_id);

        match cell_project(&self.cell_id, context, intent) {
            Some(projection) => Ok(json!({
                "success": true,
                "projection": {
                    "id": projection.id,
                    "from_cell": projection.from_cell,
                    "from_position": projection.from_position,
                    "target_context": projection.target_context,
                    "qstate_message": {
                        "intent": projection.qstate_message.intent,
                        "amplitude": projection.qstate_message.amplitude,
                        "phase": projection.qstate_message.phase
                    },
                    "coherence": projection.coherence,
                    "virtue": projection.virtue,
                    "timestamp": projection.timestamp
                },
                "message": format!(
                    "Cell {} projected into context '{}' with intent '{}'",
                    self.cell_id, context, intent
                )
            })),
            None => Ok(json!({
                "success": false,
                "error": "Failed to create projection"
            })),
        }
    }

    /// Get this cell's active projections
    async fn get_projections(&self) -> Result<serde_json::Value> {
        let projections = cell_get_projections(&self.cell_id);

        Ok(json!({
            "cell_id": self.cell_id,
            "projections": projections.iter().map(|p| {
                json!({
                    "id": p.id,
                    "context": p.target_context,
                    "intent": p.qstate_message.intent,
                    "amplitude": p.qstate_message.amplitude,
                    "coherence": p.coherence,
                    "timestamp": p.timestamp
                })
            }).collect::<Vec<_>>(),
            "total_projections": projections.len()
        }))
    }
}
