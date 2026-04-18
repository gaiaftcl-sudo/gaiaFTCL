//! Substrate Reader - Interface to the 8D quantum substrate and AKG
//!
//! Reads QState8 values, queries knowledge graph, and persists trajectories.

use crate::{QState8, ModelFamily};
use crate::types::*;
use anyhow::Result;
use serde::{Deserialize, Serialize};
use serde_json::Value;

/// Reader for the quantum substrate and AKG
pub struct SubstrateReader {
    substrate_url: String,
    arango_url: String,
    arango_user: String,
    arango_password: String,
}

impl Default for SubstrateReader {
    fn default() -> Self {
        Self::new()
    }
}

impl SubstrateReader {
    pub fn new() -> Self {
        Self {
            substrate_url: std::env::var("SUBSTRATE_URL")
                .unwrap_or_else(|_| "http://localhost:8000".to_string()),
            arango_url: std::env::var("ARANGO_URL")
                .unwrap_or_else(|_| "http://localhost:8529".to_string()),
            arango_user: std::env::var("ARANGO_USER").unwrap_or_else(|_| "root".to_string()),
            arango_password: std::env::var("ARANGO_PASSWORD").unwrap_or_else(|_| "gaiaos".to_string()),
        }
    }

    async fn aql_query_value(&self, aql: &str, bind_vars: serde_json::Value) -> Result<Vec<Value>> {
        let client = reqwest::Client::new();
        let response = client
            .post(format!("{}/_db/{}/_api/cursor", self.arango_url, "gaiaos"))
            .basic_auth(&self.arango_user, Some(&self.arango_password))
            .json(&serde_json::json!({
                "query": aql,
                "bindVars": bind_vars
            }))
            .send()
            .await?;

        #[derive(Deserialize)]
        struct QueryResult {
            result: Vec<Value>,
        }

        if response.status().is_success() {
            let result: QueryResult = response.json().await?;
            Ok(result.result)
        } else {
            Ok(Vec::new())
        }
    }

    pub async fn get_recent_observations(
        &self,
        limit: usize,
        observer_type: Option<String>,
    ) -> Result<Vec<Value>> {
        let aql = r#"
FOR o IN observations
  FILTER (@observer_type == null OR o.observer_type == @observer_type)
  SORT o.ingest_timestamp DESC
  LIMIT @limit
  RETURN o
"#;
        self.aql_query_value(
            aql,
            serde_json::json!({
                "limit": limit,
                "observer_type": observer_type
            }),
        )
        .await
    }

    pub async fn get_recent_tiles(
        &self,
        collection: String,
        sort_field: String,
        limit: usize,
    ) -> Result<Vec<Value>> {
        // Collection name must be bound with @@ to avoid injection.
        let aql = r#"
FOR d IN @@coll
  LET ts = d[@field]
  FILTER ts != null
  SORT ts DESC
  LIMIT @limit
  RETURN d
"#;
        self.aql_query_value(
            aql,
            serde_json::json!({
                "@coll": collection,
                "field": sort_field,
                "limit": limit
            }),
        )
        .await
    }

    pub async fn get_recent_field_validations(&self, limit: usize) -> Result<Vec<Value>> {
        let aql = r#"
FOR v IN field_validations
  SORT v.timestamp DESC
  LIMIT @limit
  RETURN v
"#;
        self.aql_query_value(aql, serde_json::json!({ "limit": limit })).await
    }

    /// Get current QState8 for the agent
    pub async fn get_current_qstate(&self) -> Result<QState8> {
        let client = reqwest::Client::new();
        
        let response = client
            .get(format!("{}/api/qstate/current", self.substrate_url))
            .send()
            .await?;
        
        if response.status().is_success() {
            Ok(response.json().await?)
        } else {
            // Return a default normalized state
            Ok(QState8 {
                d0: 0.5,
                d1: 0.5,
                d2: 0.5,
                d3: 0.5,
                d4: 0.5, // prudence
                d5: 0.5, // justice
                d6: 0.5, // temperance
                d7: 0.5, // fortitude
            })
        }
    }
    
    /// Query knowledge from the AKG
    pub async fn query_knowledge(&self, query: &str, domain: ModelFamily) -> Result<Vec<KnowledgeFact>> {
        let client = reqwest::Client::new();
        
        let aql = r#"
            FOR doc IN knowledge_facts
                FILTER doc.domain == @domain
                FILTER CONTAINS(LOWER(doc.content), LOWER(@query))
                LIMIT 10
                RETURN doc
            "#.to_string();
        
        let response = client
            .post(format!("{}/_db/gaiaos/_api/cursor", self.arango_url))
            .basic_auth(&self.arango_user, Some(&self.arango_password))
            .json(&serde_json::json!({
                "query": aql,
                "bindVars": {
                    "domain": domain.as_str(),
                    "query": query
                }
            }))
            .send()
            .await?;
        
        #[derive(Deserialize)]
        struct QueryResult {
            result: Vec<KnowledgeFact>,
        }
        
        if response.status().is_success() {
            let result: QueryResult = response.json().await?;
            Ok(result.result)
        } else {
            Ok(Vec::new())
        }
    }
    
    /// Persist a trajectory step to the AKG
    pub async fn persist_trajectory_step(&self, trajectory_id: &str, step: &TrajectoryStep) -> Result<String> {
        let client = reqwest::Client::new();
        
        let doc = serde_json::json!({
            "trajectory_id": trajectory_id,
            "plan_step_id": step.plan_step_id,
            "qstate": step.qstate,
            "input": step.input,
            "output": step.output,
            "latency_ms": step.latency_ms,
            "started_at": step.started_at,
            "completed_at": step.completed_at,
            "success": step.success,
            "error": step.error,
        });
        
        let response = client
            .post(format!("{}/_db/gaiaos/_api/document/trajectory_steps", self.arango_url))
            .basic_auth(&self.arango_user, Some(&self.arango_password))
            .json(&doc)
            .send()
            .await?;
        
        #[derive(Deserialize)]
        struct InsertResult {
            _key: String,
        }
        
        if response.status().is_success() {
            let result: InsertResult = response.json().await?;
            Ok(result._key)
        } else {
            anyhow::bail!("Failed to persist trajectory step")
        }
    }
    
    /// Persist an episode to the AKG
    pub async fn persist_episode(&self, episode: &Episode) -> Result<String> {
        let client = reqwest::Client::new();
        
        let doc = serde_json::to_value(episode)?;
        
        let response = client
            .post(format!("{}/_db/gaiaos/_api/document/episodes", self.arango_url))
            .basic_auth(&self.arango_user, Some(&self.arango_password))
            .json(&doc)
            .send()
            .await?;
        
        #[derive(Deserialize)]
        struct InsertResult {
            _key: String,
        }
        
        if response.status().is_success() {
            let result: InsertResult = response.json().await?;
            Ok(result._key)
        } else {
            anyhow::bail!("Failed to persist episode")
        }
    }
    
    /// Get recent episodes for learning
    pub async fn get_recent_episodes(&self, limit: usize) -> Result<Vec<Episode>> {
        let client = reqwest::Client::new();
        
        let aql = r#"
            FOR ep IN episodes
                SORT ep.completed_at DESC
                LIMIT @limit
                RETURN ep
            "#.to_string();
        
        let response = client
            .post(format!("{}/_db/gaiaos/_api/cursor", self.arango_url))
            .basic_auth(&self.arango_user, Some(&self.arango_password))
            .json(&serde_json::json!({
                "query": aql,
                "bindVars": { "limit": limit }
            }))
            .send()
            .await?;
        
        #[derive(Deserialize)]
        struct QueryResult {
            result: Vec<Episode>,
        }
        
        if response.status().is_success() {
            let result: QueryResult = response.json().await?;
            Ok(result.result)
        } else {
            Ok(Vec::new())
        }
    }
    
    /// Persist AGI activation event
    pub async fn persist_agi_activation(&self, event: &AgiActivationEvent) -> Result<String> {
        let client = reqwest::Client::new();
        
        let doc = serde_json::to_value(event)?;
        
        let response = client
            .post(format!("{}/_db/gaiaos/_api/document/agi_activations", self.arango_url))
            .basic_auth(&self.arango_user, Some(&self.arango_password))
            .json(&doc)
            .send()
            .await?;
        
        #[derive(Deserialize)]
        struct InsertResult {
            _key: String,
        }
        
        if response.status().is_success() {
            let result: InsertResult = response.json().await?;
            Ok(result._key)
        } else {
            anyhow::bail!("Failed to persist AGI activation")
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct KnowledgeFact {
    pub id: String,
    pub domain: String,
    pub content: String,
    pub confidence: f64,
    pub source: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AgiActivationEvent {
    pub id: String,
    pub timestamp: chrono::DateTime<chrono::Utc>,
    pub iq_status: String,
    pub oq_status: String,
    pub pq_status: String,
    pub virtue_score: f64,
    pub agi_mode: String,
    pub gaia_notified: bool,
    pub franklin_notified: bool,
}

