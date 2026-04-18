//! External Service Clients
//!
//! HTTP clients for Quantum Substrate and Franklin Guardian.

use anyhow::{anyhow, Context, Result};
use reqwest::Client;
use tracing::info;

use crate::models::*;

/// Client for the Quantum Substrate service
#[derive(Clone)]
pub struct SubstrateClient {
    client: Client,
    base_url: String,
}

impl SubstrateClient {
    pub async fn connect(base_url: String) -> Result<Self> {
        let client = Client::builder()
            .timeout(std::time::Duration::from_secs(30))
            .build()?;
        
        Ok(Self { client, base_url })
    }
    
    /// Query layers from the substrate
    pub async fn query_layer(&self, filter: Option<LayerFilter>) -> Result<SubstrateData> {
        let url = format!("{}/api/layers", self.base_url);

        let request = match &filter {
            Some(f) => self.client.post(&url).json(f),
            None => self.client.get(&url),
        };

        let response = request
            .send()
            .await
            .context("Failed to connect to substrate")?;

        if response.status().is_success() {
            let data = response.json::<SubstrateData>().await
                .context("Failed to parse substrate response")?;
            info!("Received {} layers with {} total points from substrate",
                  data.layers.len(), data.total_points);
            Ok(data)
        } else {
            let status = response.status();
            let body = response.text().await.unwrap_or_default();
            Err(anyhow!("Substrate returned error {}: {}", status, body))
        }
    }
    
    /// Check if substrate is healthy
    pub async fn health_check(&self) -> bool {
        let url = format!("{}/health", self.base_url);
        
        match self.client.get(&url).send().await {
            Ok(resp) => resp.status().is_success(),
            Err(_) => false,
        }
    }
    
}

/// Client for the Franklin Guardian service
#[derive(Clone)]
pub struct FranklinClient {
    client: Client,
    base_url: String,
}

impl FranklinClient {
    pub async fn connect(base_url: String) -> Result<Self> {
        let client = Client::builder()
            .timeout(std::time::Duration::from_secs(10))
            .build()?;
        
        Ok(Self { client, base_url })
    }
    
    /// Score a quantum state's virtue
    pub async fn score_quantum_state(&self, point: &SubstratePoint) -> Result<f32> {
        let url = format!("{}/api/virtue/score", self.base_url);

        let response = self.client
            .post(&url)
            .json(&serde_json::json!({
                "coord": point.coord,
                "metadata": point.metadata,
            }))
            .send()
            .await
            .context("Failed to connect to Franklin Guardian")?;

        if response.status().is_success() {
            let score: VirtueScore = response.json().await
                .context("Failed to parse virtue score response")?;
            Ok(score.score)
        } else {
            let status = response.status();
            let body = response.text().await.unwrap_or_default();
            Err(anyhow!("Franklin Guardian returned error {}: {}", status, body))
        }
    }
    
    /// Batch score multiple points via batch endpoint
    pub async fn score_batch(&self, points: &[SubstratePoint]) -> Result<Vec<f32>> {
        let url = format!("{}/api/virtue/score/batch", self.base_url);

        let coords: Vec<[f32; 8]> = points.iter().map(|p| p.coord).collect();

        let response = self.client
            .post(&url)
            .json(&serde_json::json!({ "coords": coords }))
            .send()
            .await
            .context("Failed to connect to Franklin Guardian for batch scoring")?;

        if response.status().is_success() {
            #[derive(serde::Deserialize)]
            struct BatchResponse {
                scores: Vec<f32>,
            }
            let batch: BatchResponse = response.json().await
                .context("Failed to parse batch virtue scores")?;
            Ok(batch.scores)
        } else {
            let status = response.status();
            let body = response.text().await.unwrap_or_default();
            Err(anyhow!("Franklin Guardian batch scoring returned error {}: {}", status, body))
        }
    }
    
    /// Check if guardian is healthy
    pub async fn health_check(&self) -> bool {
        let url = format!("{}/health", self.base_url);
        
        match self.client.get(&url).send().await {
            Ok(resp) => resp.status().is_success(),
            Err(_) => false,
        }
    }
    
}
