use anyhow::{Context, Result};
use log::{info, warn};
use reqwest::Client;
use serde_json::{json, Value};

use crate::models::*;

/// ArangoDB client for knowledge graph storage
#[allow(dead_code)]
pub struct ArangoClient {
    client: Client,
    base_url: String,
    db_name: String,
    auth: String,
}

#[allow(dead_code)]
impl ArangoClient {
    pub async fn new(url: &str, db_name: &str, user: &str, password: &str) -> Result<Self> {
        info!("Connecting to ArangoDB at: {url}");

        let client = Client::new();
        let auth = base64::encode(format!("{user}:{password}"));

        // Test connection
        let test_url = format!("{url}/_api/version");
        let resp = client
            .get(&test_url)
            .header("Authorization", format!("Basic {auth}"))
            .send()
            .await
            .context("Failed to connect to ArangoDB")?;

        if !resp.status().is_success() {
            anyhow::bail!("ArangoDB connection failed: {}", resp.status());
        }

        let version: Value = resp.json().await?;
        info!(
            "✓ Connected to ArangoDB {}",
            version["version"].as_str().unwrap_or("unknown")
        );

        Ok(Self {
            client,
            base_url: url.to_string(),
            db_name: db_name.to_string(),
            auth,
        })
    }

    pub async fn health_check(&self) -> Result<bool> {
        let url = format!("{}/_api/version", self.base_url);
        match self
            .client
            .get(&url)
            .header("Authorization", format!("Basic {}", self.auth))
            .send()
            .await
        {
            Ok(resp) => Ok(resp.status().is_success()),
            Err(e) => {
                warn!("ArangoDB health check failed: {e}");
                Ok(false)
            }
        }
    }

    /// Execute an AQL query with bind variables
    async fn aql_query<T: serde::de::DeserializeOwned>(
        &self,
        aql: &str,
        bind_vars: Value,
    ) -> Result<Vec<T>> {
        let url = format!("{}/_db/{}/_api/cursor", self.base_url, self.db_name);

        let body = json!({
            "query": aql,
            "bindVars": bind_vars,
            "batchSize": 1000
        });

        let resp = self
            .client
            .post(&url)
            .header("Authorization", format!("Basic {}", self.auth))
            .header("Content-Type", "application/json")
            .json(&body)
            .send()
            .await
            .context("AQL query request failed")?;

        if !resp.status().is_success() {
            let error: Value = resp.json().await.unwrap_or(json!({}));
            anyhow::bail!(
                "AQL query failed: {}",
                error["errorMessage"].as_str().unwrap_or("unknown error")
            );
        }

        let result: Value = resp.json().await?;
        let results: Vec<T> =
            serde_json::from_value(result["result"].clone()).unwrap_or_else(|_| Vec::new());

        Ok(results)
    }

    pub async fn query_procedures(
        &self,
        domain: &str,
        embedding: &[f32],
        threshold: f32,
        limit: usize,
    ) -> Result<Vec<Procedure>> {
        // Query procedures by domain and compute similarity
        let aql = r#"
            FOR proc IN procedures
                FILTER proc.domain == @domain 
                    OR STARTS_WITH(proc.domain, CONCAT(@domain, "."))
                LET dot = LENGTH(proc.embedding) > 0 ? SUM(
                    FOR i IN 0..MIN([LENGTH(proc.embedding), LENGTH(@embedding)])-1
                        RETURN proc.embedding[i] * @embedding[i]
                ) : 0
                LET norm_proc = LENGTH(proc.embedding) > 0 ? SQRT(SUM(
                    FOR val IN proc.embedding
                        RETURN val * val
                )) : 0
                LET norm_query = @norm_query
                LET similarity = norm_proc > 0 AND norm_query > 0 
                    ? dot / (norm_proc * norm_query) 
                    : 0.5
                FILTER similarity >= @threshold OR LENGTH(proc.embedding) == 0
                SORT similarity DESC, proc.success_rate DESC, proc.execution_count DESC
                LIMIT @limit
                RETURN MERGE(proc, {similarity: similarity})
        "#;

        let norm_query: f32 = embedding.iter().map(|x| x * x).sum::<f32>().sqrt();

        let bind_vars = json!({
            "domain": domain,
            "embedding": embedding,
            "norm_query": norm_query,
            "threshold": threshold,
            "limit": limit as i64,
        });

        self.aql_query(aql, bind_vars).await
    }

    pub async fn query_procedure_edges(
        &self,
        procedure_ids: &[&str],
    ) -> Result<Vec<ProcedureEdge>> {
        if procedure_ids.is_empty() {
            return Ok(Vec::new());
        }

        let aql = r#"
            FOR edge IN procedure_edges
                FILTER edge._from IN @ids OR edge._to IN @ids
                RETURN {
                    from: SPLIT(edge._from, '/')[1],
                    to: SPLIT(edge._to, '/')[1],
                    type: edge.type,
                    weight: edge.weight,
                    reason: edge.reason
                }
        "#;

        let ids: Vec<String> = procedure_ids
            .iter()
            .map(|id| format!("procedures/{id}"))
            .collect();

        let bind_vars = json!({"ids": ids});

        self.aql_query(aql, bind_vars).await
    }

    pub async fn store_execution(&self, execution: &ProcedureExecution) -> Result<()> {
        let url = format!(
            "{}/_db/{}/_api/document/procedure_executions",
            self.base_url, self.db_name
        );

        let resp = self
            .client
            .post(&url)
            .header("Authorization", format!("Basic {}", self.auth))
            .header("Content-Type", "application/json")
            .json(execution)
            .send()
            .await
            .context("Failed to store execution")?;

        if !resp.status().is_success() {
            let error: Value = resp.json().await.unwrap_or(json!({}));
            anyhow::bail!(
                "Failed to store execution: {}",
                error["errorMessage"].as_str().unwrap_or("unknown error")
            );
        }

        Ok(())
    }

    pub async fn update_procedure_stats(
        &self,
        procedure_id: &str,
        success: bool,
        duration_ms: u64,
    ) -> Result<()> {
        let aql = if success {
            r#"
                FOR proc IN procedures
                    FILTER proc._key == @key
                    UPDATE proc WITH {
                        execution_count: proc.execution_count + 1,
                        success_rate: (proc.success_rate * proc.execution_count + 1) / (proc.execution_count + 1),
                        last_executed: @timestamp,
                        avg_duration_ms: proc.avg_duration_ms != null 
                            ? (proc.avg_duration_ms * proc.execution_count + @duration) / (proc.execution_count + 1)
                            : @duration
                    } IN procedures
            "#
        } else {
            r#"
                FOR proc IN procedures
                    FILTER proc._key == @key
                    UPDATE proc WITH {
                        execution_count: proc.execution_count + 1,
                        success_rate: (proc.success_rate * proc.execution_count) / (proc.execution_count + 1),
                        last_executed: @timestamp
                    } IN procedures
            "#
        };

        let bind_vars = json!({
            "key": procedure_id,
            "timestamp": chrono::Utc::now().to_rfc3339(),
            "duration": duration_ms as i64,
        });

        self.aql_query::<Value>(aql, bind_vars).await?;
        Ok(())
    }
}

// Base64 encoding helper
mod base64 {
    const ALPHABET: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

    /// Base64-like encoding for compact representations
    #[allow(dead_code)]
    pub fn encode(input: String) -> String {
        let bytes = input.as_bytes();
        let mut result = String::new();

        for chunk in bytes.chunks(3) {
            let mut n: u32 = 0;
            for (i, &byte) in chunk.iter().enumerate() {
                n |= (byte as u32) << (16 - i * 8);
            }

            let padding = 3 - chunk.len();
            for i in 0..(4 - padding) {
                let idx = ((n >> (18 - i * 6)) & 0x3F) as usize;
                result.push(ALPHABET[idx] as char);
            }

            for _ in 0..padding {
                result.push('=');
            }
        }

        result
    }
}
