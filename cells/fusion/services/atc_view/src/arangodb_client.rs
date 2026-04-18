use crate::model::ArangoCursorResponse;
use log::info;
use reqwest::StatusCode;
use serde::Serialize;
use std::time::Duration;

#[derive(Clone)]
pub struct ArangoClient {
    base_url: String,
    db_name: String,
    client: reqwest::Client,
    collection: String,
    auth: String,
}

#[derive(Debug, Serialize)]
struct CursorRequest<'a> {
    query: &'a str,
    #[serde(rename = "bindVars")]
    bind_vars: serde_json::Value,
    #[serde(rename = "batchSize", skip_serializing_if = "Option::is_none")]
    batch_size: Option<u32>,
}

impl ArangoClient {
    pub fn new(
        base_url: &str,
        db_name: &str,
        collection: &str,
    ) -> Result<Self, Box<dyn std::error::Error + Send + Sync>> {
        let client = reqwest::Client::builder()
            .user_agent("GaiaOS-ATC-View/0.1")
            .timeout(Duration::from_secs(30))
            .build()?;

        let user = std::env::var("ARANGO_USER").unwrap_or_else(|_| "root".to_string());
        let password = std::env::var("ARANGO_PASSWORD").unwrap_or_else(|_| "gaiaos".to_string());
        let auth = base64_encode(&format!("{}:{}", user, password));

        Ok(Self {
            base_url: base_url.trim_end_matches('/').to_string(),
            db_name: db_name.to_string(),
            client,
            collection: collection.to_string(),
            auth,
        })
    }

    pub async fn query_world_patches(
        &self,
        context: &str,
        lamin: f64,
        lamax: f64,
        lomin: f64,
        lomax: f64,
    ) -> Result<Vec<serde_json::Value>, Box<dyn std::error::Error + Send + Sync>> {
        let url = format!(
            "{base}/_db/{db}/_api/cursor",
            base = self.base_url,
            db = self.db_name
        );

        let query = r#"
FOR p IN @@collection
  FILTER p.context == @context
    AND p.center_lat >= @lamin
    AND p.center_lat <= @lamax
    AND p.center_lon >= @lomin
    AND p.center_lon <= @lomax
  SORT p.timestamp DESC
  LIMIT 5000
  RETURN p
"#;

        let bind_vars = serde_json::json!({
            "@collection": self.collection,
            "context": context,
            "lamin": lamin,
            "lamax": lamax,
            "lomin": lomin,
            "lomax": lomax
        });

        let body = CursorRequest {
            query,
            bind_vars,
            batch_size: Some(5000),
        };

        info!(
            "Querying Arango context={} bbox=({:.2}, {:.2})–({:.2}, {:.2})",
            context, lamin, lomin, lamax, lomax
        );

        let resp = self
            .client
            .post(&url)
            .header("Authorization", format!("Basic {}", self.auth))
            .header("Content-Type", "application/json")
            .json(&body)
            .send()
            .await?;

        match resp.status() {
            StatusCode::OK | StatusCode::CREATED => {
                let data: ArangoCursorResponse = resp.json().await?;
                Ok(data.result)
            }
            status => {
                let text = resp.text().await.unwrap_or_default();
                Err(format!("Arango cursor error {}: {}", status, text).into())
            }
        }
    }

    pub async fn insert_document(
        &self,
        collection: &str,
        doc: &serde_json::Value,
    ) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        let url = format!(
            "{base}/_db/{db}/_api/document/{collection}",
            base = self.base_url,
            db = self.db_name,
            collection = collection
        );

        let resp = self
            .client
            .post(&url)
            .header("Authorization", format!("Basic {}", self.auth))
            .header("Content-Type", "application/json")
            .json(doc)
            .send()
            .await?;

        match resp.status() {
            StatusCode::OK | StatusCode::CREATED | StatusCode::ACCEPTED => Ok(()),
            status => {
                let text = resp.text().await.unwrap_or_default();
                Err(format!("Arango insert error {}: {}", status, text).into())
            }
        }
    }
}

fn base64_encode(input: &str) -> String {
    const ALPHABET: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

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

