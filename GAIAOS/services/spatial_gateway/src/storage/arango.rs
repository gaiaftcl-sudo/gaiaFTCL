//! ArangoDB Client for World Patch Storage
//!
//! Provides persistence for vQbits in the AKG (Agentic Knowledge Graph).
//! Uses AQL for spatial queries.

use crate::model::vqbit::Vqbit8D;
use serde::{Deserialize, Serialize};

/// ArangoDB client configuration (all fields used for database connection setup)
#[derive(Debug, Clone)]
#[allow(dead_code)]
pub struct ArangoConfig {
    pub url: String,
    pub database: String,
    pub username: String,
    pub password: String,
}

impl Default for ArangoConfig {
    fn default() -> Self {
        Self {
            url: std::env::var("ARANGO_URL").unwrap_or_else(|_| "http://arangodb:8529".to_string()),
            database: std::env::var("ARANGO_DB").unwrap_or_else(|_| "gaiaos".to_string()),
            username: std::env::var("ARANGO_USER").unwrap_or_else(|_| "root".to_string()),
            password: std::env::var("ARANGO_PASSWORD").unwrap_or_else(|_| "".to_string()),
        }
    }
}

/// ArangoDB client for world patches
#[derive(Clone)]
pub struct ArangoClient {
    config: ArangoConfig,
    http: reqwest::Client,
    auth_header: String,
}

/// Result of an ArangoDB operation
#[derive(Debug, Serialize, Deserialize)]
pub struct ArangoResult<T> {
    pub result: Option<Vec<T>>,
    pub error: bool,
    #[serde(rename = "errorMessage")]
    pub error_message: Option<String>,
}

/// Bounding box for spatial queries
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BoundingBox {
    pub x_min: f64,
    pub x_max: f64,
    pub y_min: f64,
    pub y_max: f64,
    pub z_min: Option<f64>,
    pub z_max: Option<f64>,
}

impl ArangoClient {
    /// Create a new ArangoDB client
    pub async fn new(config: ArangoConfig) -> Result<Self, String> {
        let http = reqwest::Client::new();

        // Create basic auth header
        let auth = base64::encode(format!("{}:{}", config.username, config.password));
        let auth_header = format!("Basic {auth}");

        let client = Self {
            config,
            http,
            auth_header,
        };

        // Ensure collections exist
        client.ensure_collections().await?;

        Ok(client)
    }

    /// Create with default config from environment
    pub async fn from_env() -> Result<Self, String> {
        Self::new(ArangoConfig::default()).await
    }

    /// Ensure required collections exist
    async fn ensure_collections(&self) -> Result<(), String> {
        let collections = vec!["world_patches", "fot_validations", "cell_sessions"];

        for coll in collections {
            let url = format!(
                "{}/_db/{}/_api/collection",
                self.config.url, self.config.database
            );

            let body = serde_json::json!({
                "name": coll,
                "type": 2  // Document collection
            });

            // Ignore errors (collection may already exist)
            let _ = self
                .http
                .post(&url)
                .header("Authorization", &self.auth_header)
                .json(&body)
                .send()
                .await;
        }

        Ok(())
    }

    /// Insert a vQbit into the world_patches collection
    pub async fn insert_vqbit(&self, vqbit: &Vqbit8D) -> Result<String, String> {
        let url = format!(
            "{}/_db/{}/_api/document/world_patches",
            self.config.url, self.config.database
        );

        let response = self
            .http
            .post(&url)
            .header("Authorization", &self.auth_header)
            .json(vqbit)
            .send()
            .await
            .map_err(|e| format!("HTTP error: {e}"))?;

        if !response.status().is_success() {
            let text = response.text().await.unwrap_or_default();
            return Err(format!("ArangoDB insert failed: {text}"));
        }

        let result: serde_json::Value = response
            .json()
            .await
            .map_err(|e| format!("JSON parse error: {e}"))?;

        Ok(result["_key"].as_str().unwrap_or("").to_string())
    }

    /// Upsert a vQbit (update if exists, insert if not)
    #[allow(dead_code)]
    pub async fn upsert_vqbit(&self, vqbit: &Vqbit8D) -> Result<String, String> {
        let url = format!(
            "{}/_db/{}/_api/cursor",
            self.config.url, self.config.database
        );

        let aql = r#"
            UPSERT { id: @id }
            INSERT @doc
            UPDATE @doc
            IN world_patches
            RETURN NEW._key
        "#;

        let body = serde_json::json!({
            "query": aql,
            "bindVars": {
                "id": vqbit.id.to_string(),
                "doc": vqbit
            }
        });

        let response = self
            .http
            .post(&url)
            .header("Authorization", &self.auth_header)
            .json(&body)
            .send()
            .await
            .map_err(|e| format!("HTTP error: {e}"))?;

        let result: ArangoResult<String> = response
            .json()
            .await
            .map_err(|e| format!("JSON parse error: {e}"))?;

        if result.error {
            return Err(result
                .error_message
                .unwrap_or_else(|| "Unknown error".to_string()));
        }

        Ok(result
            .result
            .and_then(|r| r.first().cloned())
            .unwrap_or_default())
    }

    /// Query vQbits within a spatial bounding box
    #[allow(dead_code)]
    pub async fn query_bbox(&self, bbox: &BoundingBox) -> Result<Vec<Vqbit8D>, String> {
        let url = format!(
            "{}/_db/{}/_api/cursor",
            self.config.url, self.config.database
        );

        let aql = r#"
            FOR p IN world_patches
            FILTER p.d0_x >= @xmin AND p.d0_x <= @xmax
               AND p.d1_y >= @ymin AND p.d1_y <= @ymax
            SORT p.timestamp_unix DESC
            LIMIT 1000
            RETURN p
        "#;

        let body = serde_json::json!({
            "query": aql,
            "bindVars": {
                "xmin": bbox.x_min,
                "xmax": bbox.x_max,
                "ymin": bbox.y_min,
                "ymax": bbox.y_max
            }
        });

        let response = self
            .http
            .post(&url)
            .header("Authorization", &self.auth_header)
            .json(&body)
            .send()
            .await
            .map_err(|e| format!("HTTP error: {e}"))?;

        let result: ArangoResult<Vqbit8D> = response
            .json()
            .await
            .map_err(|e| format!("JSON parse error: {e}"))?;

        if result.error {
            return Err(result
                .error_message
                .unwrap_or_else(|| "Unknown error".to_string()));
        }

        Ok(result.result.unwrap_or_default())
    }

    /// Query nearby vQbits (within radius in meters)
    #[allow(dead_code)]
    pub async fn query_nearby(
        &self,
        center_x: f64,
        center_y: f64,
        radius_m: f64,
    ) -> Result<Vec<Vqbit8D>, String> {
        // Convert to bounding box (approximate)
        let bbox = BoundingBox {
            x_min: center_x - radius_m,
            x_max: center_x + radius_m,
            y_min: center_y - radius_m,
            y_max: center_y + radius_m,
            z_min: None,
            z_max: None,
        };

        let candidates = self.query_bbox(&bbox).await?;

        // Filter by actual distance
        Ok(candidates
            .into_iter()
            .filter(|v| {
                let dx = v.d0_x - center_x;
                let dy = v.d1_y - center_y;
                (dx * dx + dy * dy).sqrt() <= radius_m
            })
            .collect())
    }

    /// Query vQbits by domain
    #[allow(dead_code)]
    pub async fn query_by_domain(
        &self,
        domain: &str,
        limit: Option<usize>,
    ) -> Result<Vec<Vqbit8D>, String> {
        let url = format!(
            "{}/_db/{}/_api/cursor",
            self.config.url, self.config.database
        );

        let aql = r#"
            FOR p IN world_patches
            FILTER p.domain == @domain
            SORT p.timestamp_unix DESC
            LIMIT @limit
            RETURN p
        "#;

        let body = serde_json::json!({
            "query": aql,
            "bindVars": {
                "domain": domain,
                "limit": limit.unwrap_or(100)
            }
        });

        let response = self
            .http
            .post(&url)
            .header("Authorization", &self.auth_header)
            .json(&body)
            .send()
            .await
            .map_err(|e| format!("HTTP error: {e}"))?;

        let result: ArangoResult<Vqbit8D> = response
            .json()
            .await
            .map_err(|e| format!("JSON parse error: {e}"))?;

        if result.error {
            return Err(result
                .error_message
                .unwrap_or_else(|| "Unknown error".to_string()));
        }

        Ok(result.result.unwrap_or_default())
    }

    /// Delete old vQbits (older than max_age_secs)
    pub async fn prune_old(&self, max_age_secs: f64) -> Result<usize, String> {
        let url = format!(
            "{}/_db/{}/_api/cursor",
            self.config.url, self.config.database
        );

        let cutoff = Vqbit8D::now_unix() - max_age_secs;

        let aql = r#"
            FOR p IN world_patches
            FILTER p.timestamp_unix < @cutoff
            REMOVE p IN world_patches
            RETURN OLD
        "#;

        let body = serde_json::json!({
            "query": aql,
            "bindVars": {
                "cutoff": cutoff
            }
        });

        let response = self
            .http
            .post(&url)
            .header("Authorization", &self.auth_header)
            .json(&body)
            .send()
            .await
            .map_err(|e| format!("HTTP error: {e}"))?;

        let result: ArangoResult<serde_json::Value> = response
            .json()
            .await
            .map_err(|e| format!("JSON parse error: {e}"))?;

        Ok(result.result.map(|r| r.len()).unwrap_or(0))
    }

    /// Get statistics about world patches
    pub async fn stats(&self) -> Result<WorldStats, String> {
        let url = format!(
            "{}/_db/{}/_api/cursor",
            self.config.url, self.config.database
        );

        let aql = r#"
            RETURN {
                total: LENGTH(world_patches),
                domains: (
                    FOR p IN world_patches
                    COLLECT domain = p.domain WITH COUNT INTO count
                    RETURN { domain, count }
                )
            }
        "#;

        let body = serde_json::json!({ "query": aql });

        let response = self
            .http
            .post(&url)
            .header("Authorization", &self.auth_header)
            .json(&body)
            .send()
            .await
            .map_err(|e| format!("HTTP error: {e}"))?;

        let result: ArangoResult<serde_json::Value> = response
            .json()
            .await
            .map_err(|e| format!("JSON parse error: {e}"))?;

        if let Some(results) = result.result {
            if let Some(stats) = results.first() {
                return Ok(WorldStats {
                    total_patches: stats["total"].as_u64().unwrap_or(0) as usize,
                    by_domain: stats["domains"]
                        .as_array()
                        .map(|arr| {
                            arr.iter()
                                .filter_map(|v| {
                                    let domain = v["domain"].as_str()?.to_string();
                                    let count = v["count"].as_u64()? as usize;
                                    Some((domain, count))
                                })
                                .collect()
                        })
                        .unwrap_or_default(),
                });
            }
        }

        Ok(WorldStats::default())
    }
}

/// Statistics about world patches
#[derive(Debug, Clone, Default)]
pub struct WorldStats {
    pub total_patches: usize,
    pub by_domain: Vec<(String, usize)>,
}

// Simple base64 encoding (avoid extra dependency)
mod base64 {
    const ALPHABET: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

    pub fn encode(input: impl AsRef<[u8]>) -> String {
        let input = input.as_ref();
        let mut output = String::new();

        for chunk in input.chunks(3) {
            let b0 = chunk[0] as u32;
            let b1 = chunk.get(1).copied().unwrap_or(0) as u32;
            let b2 = chunk.get(2).copied().unwrap_or(0) as u32;

            let triple = (b0 << 16) | (b1 << 8) | b2;

            output.push(ALPHABET[(triple >> 18) as usize & 0x3F] as char);
            output.push(ALPHABET[(triple >> 12) as usize & 0x3F] as char);

            if chunk.len() > 1 {
                output.push(ALPHABET[(triple >> 6) as usize & 0x3F] as char);
            } else {
                output.push('=');
            }

            if chunk.len() > 2 {
                output.push(ALPHABET[triple as usize & 0x3F] as char);
            } else {
                output.push('=');
            }
        }

        output
    }
}
