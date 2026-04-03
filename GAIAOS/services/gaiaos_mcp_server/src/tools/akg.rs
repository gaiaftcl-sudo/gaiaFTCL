//! AKG (Agentic Knowledge Graph) MCP Tools
//!
//! Knowledge graph query and manipulation tools.

use crate::McpTool;
use anyhow::Result;
use serde_json::json;

/// AKG tools handler
pub struct AkgTools {
    base_url: String,
    user: String,
    password: String,
    client: reqwest::Client,
}

impl AkgTools {
    pub fn new(base_url: &str, user: &str, password: &str) -> Self {
        Self {
            base_url: base_url.to_string(),
            user: user.to_string(),
            password: password.to_string(),
            client: reqwest::Client::new(),
        }
    }

    /// Get tool definitions for AKG
    pub fn get_tool_definitions(&self) -> Vec<McpTool> {
        vec![
            McpTool {
                name: "akg_query".into(),
                description:
                    "Query the Agentic Knowledge Graph using AQL (ArangoDB Query Language)".into(),
                input_schema: json!({
                    "type": "object",
                    "properties": {
                        "aql": {
                            "type": "string",
                            "description": "AQL query statement"
                        },
                        "bind_vars": {
                            "type": "object",
                            "description": "Query bind variables"
                        },
                        "database": {
                            "type": "string",
                            "description": "Database name",
                            "default": "gaiaos_akg"
                        }
                    },
                    "required": ["aql"]
                }),
            },
            McpTool {
                name: "akg_traverse".into(),
                description: "Traverse the knowledge graph from a starting vertex".into(),
                input_schema: json!({
                    "type": "object",
                    "properties": {
                        "start": {
                            "type": "string",
                            "description": "Starting vertex ID"
                        },
                        "direction": {
                            "type": "string",
                            "enum": ["outbound", "inbound", "any"],
                            "description": "Traversal direction",
                            "default": "outbound"
                        },
                        "depth": {
                            "type": "integer",
                            "description": "Maximum traversal depth",
                            "default": 3
                        },
                        "edge_collections": {
                            "type": "array",
                            "items": {"type": "string"},
                            "description": "Edge collections to traverse"
                        }
                    },
                    "required": ["start"]
                }),
            },
            McpTool {
                name: "akg_upsert".into(),
                description: "Insert or update a vertex in the knowledge graph".into(),
                input_schema: json!({
                    "type": "object",
                    "properties": {
                        "collection": {
                            "type": "string",
                            "description": "Collection name"
                        },
                        "key": {
                            "type": "string",
                            "description": "Document key (optional, auto-generated if not provided)"
                        },
                        "data": {
                            "type": "object",
                            "description": "Document data"
                        }
                    },
                    "required": ["collection", "data"]
                }),
            },
            McpTool {
                name: "akg_edge".into(),
                description: "Create an edge (relationship) between two vertices".into(),
                input_schema: json!({
                    "type": "object",
                    "properties": {
                        "from": {
                            "type": "string",
                            "description": "Source vertex ID (collection/key)"
                        },
                        "to": {
                            "type": "string",
                            "description": "Target vertex ID (collection/key)"
                        },
                        "edge_collection": {
                            "type": "string",
                            "description": "Edge collection name"
                        },
                        "data": {
                            "type": "object",
                            "description": "Edge attributes"
                        }
                    },
                    "required": ["from", "to", "edge_collection"]
                }),
            },
            McpTool {
                name: "akg_collections".into(),
                description: "List all collections in the knowledge graph".into(),
                input_schema: json!({
                    "type": "object",
                    "properties": {
                        "database": {
                            "type": "string",
                            "description": "Database name",
                            "default": "gaiaos_akg"
                        }
                    },
                    "required": []
                }),
            },
            McpTool {
                name: "akg_stats".into(),
                description: "Get knowledge graph statistics".into(),
                input_schema: json!({
                    "type": "object",
                    "properties": {},
                    "required": []
                }),
            },
        ]
    }

    /// Call an AKG tool
    pub async fn call(&self, name: &str, args: serde_json::Value) -> Result<serde_json::Value> {
        match name {
            "akg_query" => self.query(args).await,
            "akg_traverse" => self.traverse(args).await,
            "akg_upsert" => self.upsert(args).await,
            "akg_edge" => self.edge(args).await,
            "akg_collections" => self.collections(args).await,
            "akg_stats" => self.stats().await,
            _ => Err(anyhow::anyhow!("Unknown akg tool: {name}")),
        }
    }

    async fn query(&self, args: serde_json::Value) -> Result<serde_json::Value> {
        let aql = args.get("aql").and_then(|v| v.as_str()).unwrap_or("");
        let bind_vars = args.get("bind_vars").cloned().unwrap_or(json!({}));
        let database = args
            .get("database")
            .and_then(|v| v.as_str())
            .unwrap_or("gaiaos_akg");

        let response = self
            .client
            .post(format!("{}/_db/{}/_api/cursor", self.base_url, database))
            .basic_auth(&self.user, Some(&self.password))
            .json(&json!({
                "query": aql,
                "bindVars": bind_vars
            }))
            .send()
            .await;

        match response {
            Ok(resp) if resp.status().is_success() => {
                let result: serde_json::Value = resp.json().await?;
                Ok(json!({
                    "success": true,
                    "result": result.get("result").cloned().unwrap_or(json!([])),
                    "hasMore": result.get("hasMore").cloned().unwrap_or(json!(false)),
                    "count": result.get("result").and_then(|r| r.as_array()).map(|a| a.len()).unwrap_or(0)
                }))
            }
            Ok(resp) => {
                let status = resp.status();
                let text = resp.text().await.unwrap_or_default();
                Ok(json!({
                    "success": false,
                    "error": format!("ArangoDB error: {} - {}", status, text),
                    "query": aql
                }))
            }
            Err(e) => {
                // NO SIMULATION - Return error state with helpful hint
                Ok(json!({
                    "success": false,
                    "error": format!("Connection error: {}", e),
                    "query": aql,
                    "hint": "ArangoDB may not be running or accessible"
                }))
            }
        }
    }

    async fn traverse(&self, args: serde_json::Value) -> Result<serde_json::Value> {
        let start = args.get("start").and_then(|v| v.as_str()).unwrap_or("");
        let direction = args
            .get("direction")
            .and_then(|v| v.as_str())
            .unwrap_or("outbound");
        let depth = args.get("depth").and_then(|v| v.as_i64()).unwrap_or(3);

        let aql = format!(
            r#"FOR v, e, p IN 1..{} {} '{}' RETURN {{vertex: v, edge: e, path: p}}"#,
            depth,
            direction.to_uppercase(),
            start
        );

        self.query(json!({"aql": aql})).await
    }

    async fn upsert(&self, args: serde_json::Value) -> Result<serde_json::Value> {
        let collection = args
            .get("collection")
            .and_then(|v| v.as_str())
            .unwrap_or("");
        let key = args.get("key").and_then(|v| v.as_str());
        let data = args.get("data").cloned().unwrap_or(json!({}));

        let doc = if let Some(k) = key {
            let mut d = data.as_object().cloned().unwrap_or_default();
            d.insert("_key".to_string(), json!(k));
            serde_json::Value::Object(d)
        } else {
            data
        };

        let response = self
            .client
            .post(format!(
                "{}/_db/gaiaos_akg/_api/document/{}",
                self.base_url, collection
            ))
            .basic_auth(&self.user, Some(&self.password))
            .query(&[("overwriteMode", "update")])
            .json(&doc)
            .send()
            .await;

        match response {
            Ok(resp) if resp.status().is_success() => {
                let result: serde_json::Value = resp.json().await?;
                Ok(json!({
                    "success": true,
                    "collection": collection,
                    "_id": result.get("_id"),
                    "_key": result.get("_key"),
                    "_rev": result.get("_rev")
                }))
            }
            Ok(resp) => {
                let status = resp.status();
                let text = resp.text().await.unwrap_or_default();
                Ok(json!({
                    "success": false,
                    "error": format!("Upsert failed: {} - {}", status, text)
                }))
            }
            Err(e) => {
                // NO SIMULATION - FAIL HARD
                // ArangoDB MUST be available for upsert operations
                Err(anyhow::anyhow!(
                    "ArangoDB upsert failed: {e} - NO SIMULATION ALLOWED"
                ))
            }
        }
    }

    async fn edge(&self, args: serde_json::Value) -> Result<serde_json::Value> {
        let from = args.get("from").and_then(|v| v.as_str()).unwrap_or("");
        let to = args.get("to").and_then(|v| v.as_str()).unwrap_or("");
        let edge_collection = args
            .get("edge_collection")
            .and_then(|v| v.as_str())
            .unwrap_or("edges");
        let data = args.get("data").cloned().unwrap_or(json!({}));

        let mut edge_doc = data.as_object().cloned().unwrap_or_default();
        edge_doc.insert("_from".to_string(), json!(from));
        edge_doc.insert("_to".to_string(), json!(to));

        let response = self
            .client
            .post(format!(
                "{}/_db/gaiaos_akg/_api/document/{}",
                self.base_url, edge_collection
            ))
            .basic_auth(&self.user, Some(&self.password))
            .json(&edge_doc)
            .send()
            .await;

        match response {
            Ok(resp) if resp.status().is_success() => {
                let result: serde_json::Value = resp.json().await?;
                Ok(json!({
                    "success": true,
                    "edge_collection": edge_collection,
                    "from": from,
                    "to": to,
                    "_id": result.get("_id"),
                    "_key": result.get("_key")
                }))
            }
            Ok(resp) => {
                let status = resp.status();
                let text = resp.text().await.unwrap_or_default();
                Ok(json!({
                    "success": false,
                    "error": format!("Edge creation failed: {} - {}", status, text)
                }))
            }
            Err(e) => {
                // NO SIMULATION - FAIL HARD
                // ArangoDB MUST be available for edge creation
                Err(anyhow::anyhow!(
                    "ArangoDB edge creation failed: {e} - NO SIMULATION ALLOWED"
                ))
            }
        }
    }

    async fn collections(&self, args: serde_json::Value) -> Result<serde_json::Value> {
        let database = args
            .get("database")
            .and_then(|v| v.as_str())
            .unwrap_or("gaiaos_akg");

        let response = self
            .client
            .get(format!(
                "{}/_db/{}/_api/collection",
                self.base_url, database
            ))
            .basic_auth(&self.user, Some(&self.password))
            .send()
            .await;

        match response {
            Ok(resp) if resp.status().is_success() => {
                let result: serde_json::Value = resp.json().await?;
                Ok(json!({
                    "success": true,
                    "database": database,
                    "collections": result.get("result").cloned().unwrap_or(json!([]))
                }))
            }
            Ok(resp) => {
                let status = resp.status();
                let text = resp.text().await.unwrap_or_default();
                Ok(json!({
                    "success": false,
                    "database": database,
                    "error": format!("Failed to list collections: {} - {}", status, text)
                }))
            }
            Err(e) => {
                // NO SIMULATION - Return error state
                Ok(json!({
                    "success": false,
                    "database": database,
                    "error": format!("ArangoDB unavailable: {}", e)
                }))
            }
        }
    }

    async fn stats(&self) -> Result<serde_json::Value> {
        let response = self
            .client
            .get(format!("{}/_db/gaiaos_akg/_api/collection", self.base_url))
            .basic_auth(&self.user, Some(&self.password))
            .send()
            .await;

        match response {
            Ok(resp) if resp.status().is_success() => {
                let result: serde_json::Value = resp.json().await?;
                let collections = result
                    .get("result")
                    .and_then(|r| r.as_array())
                    .map(|a| a.len())
                    .unwrap_or(0);

                Ok(json!({
                    "success": true,
                    "collection_count": collections,
                    "database": "gaiaos_akg",
                    "status": "connected"
                }))
            }
            Ok(resp) => {
                let status = resp.status();
                let text = resp.text().await.unwrap_or_default();
                Ok(json!({
                    "success": false,
                    "collection_count": 0,
                    "database": "gaiaos_akg",
                    "status": "error",
                    "error": format!("Stats query failed: {} - {}", status, text)
                }))
            }
            Err(e) => {
                // Status check returns unavailable state - not simulated
                Ok(json!({
                    "success": false,
                    "collection_count": 0,
                    "database": "gaiaos_akg",
                    "status": "disconnected",
                    "error": format!("ArangoDB unavailable: {}", e)
                }))
            }
        }
    }
}
