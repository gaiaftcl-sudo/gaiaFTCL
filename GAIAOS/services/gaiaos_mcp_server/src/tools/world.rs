//! World Engine MCP Tools
//!
//! Physics simulation and world model tools.

use crate::McpTool;
use anyhow::Result;
use serde_json::json;

/// World tools handler
pub struct WorldTools {
    base_url: String,
    client: reqwest::Client,
}

impl WorldTools {
    pub fn new(base_url: &str) -> Self {
        Self {
            base_url: base_url.to_string(),
            client: reqwest::Client::new(),
        }
    }

    /// Get tool definitions for world engine
    pub fn get_tool_definitions(&self) -> Vec<McpTool> {
        vec![
            McpTool {
                name: "world_state".into(),
                description: "Get current world state including entities and physics".into(),
                input_schema: json!({
                    "type": "object",
                    "properties": {},
                    "required": []
                }),
            },
            McpTool {
                name: "world_spawn".into(),
                description: "Spawn a new entity in the world".into(),
                input_schema: json!({
                    "type": "object",
                    "properties": {
                        "entity_type": {
                            "type": "string",
                            "enum": ["avatar", "object", "sensor", "actuator", "agent"],
                            "description": "Type of entity to spawn"
                        },
                        "position": {
                            "type": "object",
                            "properties": {
                                "x": {"type": "number"},
                                "y": {"type": "number"},
                                "z": {"type": "number"}
                            },
                            "description": "3D position in world space"
                        },
                        "name": {
                            "type": "string",
                            "description": "Entity name"
                        },
                        "properties": {
                            "type": "object",
                            "description": "Additional entity properties"
                        }
                    },
                    "required": ["entity_type"]
                }),
            },
            McpTool {
                name: "world_action".into(),
                description: "Apply an action to an entity".into(),
                input_schema: json!({
                    "type": "object",
                    "properties": {
                        "entity_id": {
                            "type": "string",
                            "description": "Entity ID to act upon"
                        },
                        "action": {
                            "type": "string",
                            "enum": ["move", "rotate", "scale", "force", "impulse", "destroy"],
                            "description": "Action type"
                        },
                        "parameters": {
                            "type": "object",
                            "description": "Action parameters (e.g., direction, magnitude)"
                        }
                    },
                    "required": ["entity_id", "action"]
                }),
            },
            McpTool {
                name: "world_physics".into(),
                description: "Get current physics state (gravity, time scale, etc.)".into(),
                input_schema: json!({
                    "type": "object",
                    "properties": {},
                    "required": []
                }),
            },
            McpTool {
                name: "world_query".into(),
                description: "Query entities by type or properties".into(),
                input_schema: json!({
                    "type": "object",
                    "properties": {
                        "entity_type": {
                            "type": "string",
                            "description": "Filter by entity type"
                        },
                        "radius": {
                            "type": "number",
                            "description": "Search radius from origin"
                        },
                        "limit": {
                            "type": "integer",
                            "description": "Maximum results",
                            "default": 100
                        }
                    },
                    "required": []
                }),
            },
            McpTool {
                name: "world_sensor_read".into(),
                description: "Read data from a simulated sensor".into(),
                input_schema: json!({
                    "type": "object",
                    "properties": {
                        "sensor_id": {
                            "type": "string",
                            "description": "Sensor entity ID"
                        },
                        "sensor_type": {
                            "type": "string",
                            "enum": ["camera", "lidar", "imu", "gps", "temperature", "proximity"],
                            "description": "Type of sensor"
                        }
                    },
                    "required": ["sensor_type"]
                }),
            },
        ]
    }

    /// Call a world tool
    pub async fn call(&self, name: &str, args: serde_json::Value) -> Result<serde_json::Value> {
        match name {
            "world_state" => self.state().await,
            "world_spawn" => self.spawn(args).await,
            "world_action" => self.action(args).await,
            "world_physics" => self.physics().await,
            "world_query" => self.query(args).await,
            "world_sensor_read" => self.sensor_read(args).await,
            _ => Err(anyhow::anyhow!("Unknown world tool: {name}")),
        }
    }

    async fn state(&self) -> Result<serde_json::Value> {
        let response = self
            .client
            .get(format!("{}/state", self.base_url))
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
                    "World state query failed: {status} - {text} - NO SIMULATION ALLOWED"
                ))
            }
            Err(e) => {
                // NO SIMULATION - FAIL HARD
                Err(anyhow::anyhow!(
                    "World engine unavailable: {e} - NO SIMULATION ALLOWED"
                ))
            }
        }
    }

    async fn spawn(&self, args: serde_json::Value) -> Result<serde_json::Value> {
        let entity_type = args
            .get("entity_type")
            .and_then(|v| v.as_str())
            .unwrap_or("object");
        let name = args
            .get("name")
            .and_then(|v| v.as_str())
            .unwrap_or("unnamed");
        let position = args
            .get("position")
            .cloned()
            .unwrap_or(json!({"x": 0.0, "y": 0.0, "z": 0.0}));

        let response = self
            .client
            .post(format!("{}/spawn", self.base_url))
            .json(&json!({
                "entity_type": entity_type,
                "name": name,
                "position": position
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
                    "World spawn failed: {status} - {text} - NO SIMULATION ALLOWED"
                ))
            }
            Err(e) => {
                // NO SIMULATION - FAIL HARD
                Err(anyhow::anyhow!(
                    "World engine unavailable: {e} - NO SIMULATION ALLOWED"
                ))
            }
        }
    }

    async fn action(&self, args: serde_json::Value) -> Result<serde_json::Value> {
        let entity_id = args.get("entity_id").and_then(|v| v.as_str()).unwrap_or("");
        let action = args.get("action").and_then(|v| v.as_str()).unwrap_or("");
        let parameters = args.get("parameters").cloned().unwrap_or(json!({}));

        let response = self
            .client
            .post(format!("{}/action", self.base_url))
            .json(&json!({
                "entity_id": entity_id,
                "action": action,
                "parameters": parameters
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
                    "World action failed: {status} - {text} - NO SIMULATION ALLOWED"
                ))
            }
            Err(e) => {
                // NO SIMULATION - FAIL HARD
                Err(anyhow::anyhow!(
                    "World engine unavailable: {e} - NO SIMULATION ALLOWED"
                ))
            }
        }
    }

    async fn physics(&self) -> Result<serde_json::Value> {
        let response = self
            .client
            .get(format!("{}/physics", self.base_url))
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
                    "Physics query failed: {status} - {text} - NO SIMULATION ALLOWED"
                ))
            }
            Err(e) => {
                // NO SIMULATION - FAIL HARD
                Err(anyhow::anyhow!(
                    "World engine unavailable: {e} - NO SIMULATION ALLOWED"
                ))
            }
        }
    }

    async fn query(&self, args: serde_json::Value) -> Result<serde_json::Value> {
        let entity_type = args.get("entity_type").and_then(|v| v.as_str());
        let limit = args.get("limit").and_then(|v| v.as_i64()).unwrap_or(100);

        // NO SIMULATION - query must go to real world engine
        let response = self
            .client
            .post(format!("{}/query", self.base_url))
            .json(&json!({
                "entity_type": entity_type,
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
                    "World query failed: {status} - {text} - NO SIMULATION ALLOWED"
                ))
            }
            Err(e) => Err(anyhow::anyhow!(
                "World engine unavailable: {e} - NO SIMULATION ALLOWED"
            )),
        }
    }

    async fn sensor_read(&self, args: serde_json::Value) -> Result<serde_json::Value> {
        let sensor_type = args
            .get("sensor_type")
            .and_then(|v| v.as_str())
            .unwrap_or("camera");

        // NO SIMULATION - sensor data must come from real world engine
        let response = self
            .client
            .post(format!("{}/sensor/read", self.base_url))
            .json(&json!({
                "sensor_type": sensor_type
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
                    "Sensor read failed: {status} - {text} - NO SIMULATION ALLOWED"
                ))
            }
            Err(e) => Err(anyhow::anyhow!(
                "World engine unavailable: {e} - NO SIMULATION ALLOWED"
            )),
        }
    }
}
