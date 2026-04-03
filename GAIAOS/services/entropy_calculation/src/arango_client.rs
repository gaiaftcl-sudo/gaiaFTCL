use anyhow::{anyhow, Result};
use base64::{engine::general_purpose, Engine};
use serde_json::Value;

/// Simple ArangoDB client for entropy calculation service
pub struct ArangoClient {
    client: reqwest::Client,
    base_url: String,
    db_name: String,
    auth: String,
}

impl ArangoClient {
    pub fn new(base_url: String, db_name: String, username: String, password: String) -> Self {
        let auth = general_purpose::STANDARD.encode(format!("{}:{}", username, password));
        Self {
            client: reqwest::Client::new(),
            base_url,
            db_name,
            auth,
        }
    }

    pub fn from_env() -> Result<Self> {
        let base_url = std::env::var("ARANGO_URL").unwrap_or_else(|_| "http://localhost:8529".to_string());
        let db_name = std::env::var("ARANGO_DB").unwrap_or_else(|_| "gaiaos".to_string());
        let username = std::env::var("ARANGO_USER").unwrap_or_else(|_| "root".to_string());
        let password = std::env::var("ARANGO_PASSWORD").unwrap_or_else(|_| "gaiaos".to_string());

        Ok(Self::new(base_url, db_name, username, password))
    }

    /// Execute an AQL query
    pub async fn query(&self, query: &str, bind_vars: Value) -> Result<Value> {
        let url = format!("{base}/_db/{db}/_api/cursor", base = self.base_url, db = self.db_name);

        let body = serde_json::json!({
            "query": query,
            "bindVars": bind_vars,
            "count": true,
        });

        let resp = self
            .client
            .post(&url)
            .header("Authorization", format!("Basic {}", self.auth))
            .header("Content-Type", "application/json")
            .json(&body)
            .send()
            .await?;

        if !resp.status().is_success() {
            let status = resp.status();
            let text = resp.text().await.unwrap_or_default();
            return Err(anyhow!("Arango query error {}: {}", status, text));
        }

        let result: Value = resp.json().await?;
        Ok(result.get("result").cloned().unwrap_or(Value::Array(vec![])))
    }

    /// Insert a document into a collection
    pub async fn insert_document(&self, collection: &str, doc: &Value) -> Result<()> {
        let url = format!(
            "{base}/_db/{db}/_api/document/{coll}",
            base = self.base_url,
            db = self.db_name,
            coll = collection
        );

        let resp = self
            .client
            .post(&url)
            .header("Authorization", format!("Basic {}", self.auth))
            .header("Content-Type", "application/json")
            .json(doc)
            .send()
            .await?;

        if !resp.status().is_success() {
            let status = resp.status();
            let text = resp.text().await.unwrap_or_default();
            return Err(anyhow!("Arango insert error {}: {}", status, text));
        }

        Ok(())
    }

    /// Upsert a document (insert or update based on _key)
    pub async fn upsert_document(&self, collection: &str, doc: &Value) -> Result<()> {
        let url = format!(
            "{base}/_db/{db}/_api/document/{coll}",
            base = self.base_url,
            db = self.db_name,
            coll = collection
        );

        let resp = self
            .client
            .post(&url)
            .header("Authorization", format!("Basic {}", self.auth))
            .header("Content-Type", "application/json")
            .query(&[("overwriteMode", "update")])
            .json(doc)
            .send()
            .await?;

        if !resp.status().is_success() {
            let status = resp.status();
            let text = resp.text().await.unwrap_or_default();
            return Err(anyhow!("Arango upsert error {}: {}", status, text));
        }

        Ok(())
    }
}

