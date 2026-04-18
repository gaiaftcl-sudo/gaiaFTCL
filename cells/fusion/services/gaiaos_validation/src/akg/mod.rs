//! AKG (ARC Knowledge Graph) Writer
//!
//! Writes validation results as first-class nodes in the AKG.
//! These nodes are queryable by the orchestrator to determine AGI mode eligibility.

use crate::{ModelFamily, CapabilityStatus, AutonomyLevel};
use crate::types::{IQRun, OQRun, PQRun};
use anyhow::Result;
use chrono::{DateTime, Utc};
use serde::Deserialize;

/// AKG Writer - persists validation results to ArangoDB
pub struct AkgWriter {
    arango_url: String,
    database: String,
}

impl Default for AkgWriter {
    fn default() -> Self {
        Self::new()
    }
}

impl AkgWriter {
    pub fn new() -> Self {
        Self {
            arango_url: std::env::var("ARANGO_URL")
                .unwrap_or_else(|_| "http://localhost:8529".to_string()),
            database: std::env::var("ARANGO_DB")
                .unwrap_or_else(|_| "gaiaos".to_string()),
        }
    }
    
    /// Write an IQ run result to the AKG
    pub async fn write_iq_run(&self, iq_run: &IQRun) -> Result<String> {
        let doc = serde_json::to_value(iq_run)?;
        self.insert_document("iq_runs", doc).await
    }
    
    /// Write an OQ run result to the AKG
    pub async fn write_oq_run(&self, oq_run: &OQRun) -> Result<String> {
        let doc = serde_json::to_value(oq_run)?;
        self.insert_document("oq_runs", doc).await
    }
    
    /// Write a PQ run result to the AKG
    pub async fn write_pq_run(&self, pq_run: &PQRun) -> Result<String> {
        let doc = serde_json::to_value(pq_run)?;
        self.insert_document("pq_runs", doc).await
    }
    
    /// Update or create a capability gate for a model family
    pub async fn update_capability_gate(&self, status: &CapabilityStatus) -> Result<String> {
        let gate_key = format!("gate_{}", status.family.as_str());
        
        let doc = serde_json::json!({
            "_key": gate_key,
            "family": status.family,
            "iq_pass": status.iq_pass,
            "oq_pass": status.oq_pass,
            "pq_pass": status.pq_pass,
            "virtue_score": status.virtue_score,
            "autonomy_level": status.autonomy_level,
            "agi_mode_enabled": status.agi_mode_enabled(),
            "last_validated": status.last_validated,
            "valid_until": status.valid_until,
        });
        
        self.upsert_document("capability_gates", &gate_key, doc).await
    }
    
    /// Get the latest validation status for a model family
    pub async fn get_capability_status(&self, family: ModelFamily) -> Result<Option<CapabilityStatus>> {
        let gate_key = format!("gate_{}", family.as_str());
        
        let client = reqwest::Client::new();
        let response = client
            .get(format!(
                "{}/_db/{}/_api/document/capability_gates/{}",
                self.arango_url, self.database, gate_key
            ))
            .send()
            .await?;
        
        if response.status().is_success() {
            let doc: CapabilityGateDoc = response.json().await?;
            Ok(Some(doc.into()))
        } else {
            Ok(None)
        }
    }
    
    /// Get latest IQ run for a model
    pub async fn get_latest_iq(&self, model_id: &str) -> Result<Option<IQRun>> {
        self.get_latest_run("iq_runs", model_id).await
    }
    
    /// Get latest OQ run for a model
    pub async fn get_latest_oq(&self, model_id: &str) -> Result<Option<OQRun>> {
        self.get_latest_run("oq_runs", model_id).await
    }
    
    /// Get latest PQ run for a model
    pub async fn get_latest_pq(&self, model_id: &str) -> Result<Option<PQRun>> {
        self.get_latest_run("pq_runs", model_id).await
    }
    
    /// Get all capability gate statuses
    pub async fn get_all_capability_statuses(&self) -> Result<Vec<CapabilityStatus>> {
        let client = reqwest::Client::new();
        
        let query = r#"
            FOR gate IN capability_gates
                RETURN gate
        "#;
        
        let response = client
            .post(format!("{}/_db/{}/_api/cursor", self.arango_url, self.database))
            .json(&serde_json::json!({
                "query": query
            }))
            .send()
            .await?;
        
        if response.status().is_success() {
            #[derive(Deserialize)]
            struct QueryResult {
                result: Vec<CapabilityGateDoc>,
            }
            
            let result: QueryResult = response.json().await?;
            Ok(result.result.into_iter().map(|d| d.into()).collect())
        } else {
            Ok(Vec::new())
        }
    }
    
    /// Ensure required collections exist
    pub async fn ensure_collections(&self) -> Result<()> {
        let collections = [
            "iq_runs",
            "oq_runs", 
            "pq_runs",
            "capability_gates",
            "models",
            "validation_thresholds",
        ];
        
        let client = reqwest::Client::new();
        
        for collection in &collections {
            let response = client
                .post(format!(
                    "{}/_db/{}/_api/collection",
                    self.arango_url, self.database
                ))
                .json(&serde_json::json!({
                    "name": collection,
                    "type": 2  // Document collection
                }))
                .send()
                .await;
            
            // Ignore "collection already exists" errors
            if let Ok(resp) = response {
                if resp.status().is_success() || resp.status().as_u16() == 409 {
                    tracing::debug!(collection = collection, "Collection ready");
                }
            }
        }
        
        Ok(())
    }
    
    // Private helper methods
    
    async fn insert_document(&self, collection: &str, doc: serde_json::Value) -> Result<String> {
        let client = reqwest::Client::new();
        
        let response = client
            .post(format!(
                "{}/_db/{}/_api/document/{}",
                self.arango_url, self.database, collection
            ))
            .json(&doc)
            .send()
            .await?;
        
        if response.status().is_success() {
            #[derive(Deserialize)]
            struct InsertResult {
                _key: String,
            }
            let result: InsertResult = response.json().await?;
            Ok(result._key)
        } else {
            let error = response.text().await?;
            anyhow::bail!("Failed to insert document: {error}")
        }
    }
    
    async fn upsert_document(&self, collection: &str, key: &str, doc: serde_json::Value) -> Result<String> {
        let client = reqwest::Client::new();
        
        // Try update first
        let response = client
            .put(format!(
                "{}/_db/{}/_api/document/{}/{}",
                self.arango_url, self.database, collection, key
            ))
            .json(&doc)
            .send()
            .await?;
        
        if response.status().is_success() {
            return Ok(key.to_string());
        }
        
        // If not found, insert
        let response = client
            .post(format!(
                "{}/_db/{}/_api/document/{}",
                self.arango_url, self.database, collection
            ))
            .json(&doc)
            .send()
            .await?;
        
        if response.status().is_success() {
            #[derive(Deserialize)]
            struct InsertResult {
                _key: String,
            }
            let result: InsertResult = response.json().await?;
            Ok(result._key)
        } else {
            let error = response.text().await?;
            anyhow::bail!("Failed to upsert document: {error}")
        }
    }
    
    async fn get_latest_run<T: for<'de> Deserialize<'de>>(&self, collection: &str, model_id: &str) -> Result<Option<T>> {
        let client = reqwest::Client::new();
        
        let query = format!(
            r#"
            FOR run IN {collection}
                FILTER run.model_id == @model_id
                SORT run.timestamp DESC
                LIMIT 1
                RETURN run
            "#
        );
        
        let response = client
            .post(format!("{}/_db/{}/_api/cursor", self.arango_url, self.database))
            .json(&serde_json::json!({
                "query": query,
                "bindVars": {
                    "model_id": model_id
                }
            }))
            .send()
            .await?;
        
        if response.status().is_success() {
            #[derive(Deserialize)]
            struct QueryResult<T> {
                result: Vec<T>,
            }
            
            let result: QueryResult<T> = response.json().await?;
            Ok(result.result.into_iter().next())
        } else {
            Ok(None)
        }
    }
}

#[derive(Debug, Deserialize)]
struct CapabilityGateDoc {
    family: ModelFamily,
    iq_pass: bool,
    oq_pass: bool,
    pq_pass: bool,
    virtue_score: f64,
    autonomy_level: AutonomyLevel,
    last_validated: DateTime<Utc>,
    valid_until: DateTime<Utc>,
}

impl From<CapabilityGateDoc> for CapabilityStatus {
    fn from(doc: CapabilityGateDoc) -> Self {
        Self {
            family: doc.family,
            iq_pass: doc.iq_pass,
            oq_pass: doc.oq_pass,
            pq_pass: doc.pq_pass,
            virtue_score: doc.virtue_score,
            autonomy_level: doc.autonomy_level,
            last_validated: doc.last_validated,
            valid_until: doc.valid_until,
        }
    }
}

