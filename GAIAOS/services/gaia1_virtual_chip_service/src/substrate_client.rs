// services/gaia1_virtual_chip_service/src/substrate_client.rs
// Client for vChip to query the AKG GNN substrate directly

use anyhow::Result;
use reqwest::Client;
use serde::{Deserialize, Serialize};
use tracing::{info, warn, error};

/// Client for querying the AKG GNN substrate
/// vChip uses this to fetch local patches before collapse operations
pub struct SubstrateClient {
    client: Client,
    base_url: String,
}

/// Request for a local substrate patch
#[derive(Debug, Serialize)]
pub struct PatchRequest {
    pub scale: String,
    pub center: [f64; 8],
    pub radius: Option<f64>,
    pub intent: Option<String>,
    pub max_procedures: Option<usize>,
}

/// A procedure node from the substrate
#[derive(Debug, Clone, Deserialize)]
#[allow(dead_code)]
pub struct ProcedureNode {
    pub id: String,
    pub context: String,
    pub d0_d7: [f64; 8],
    pub intent: String,
    pub success_rate: f64,
    pub execution_count: u64,
    pub risk_level: String,
    pub confidence: f64,
}

/// An edge between procedures
#[derive(Debug, Clone, Deserialize)]
#[allow(dead_code)]
pub struct ProcedureEdge {
    pub from_id: String,
    pub to_id: String,
    pub edge_type: String,
    pub weight: f64,
}

/// Response from /substrate/patch
#[derive(Debug, Deserialize)]
#[allow(dead_code)]
pub struct PatchResponse {
    pub scale: String,
    pub center: [f64; 8],
    pub radius: f64,
    pub procedures: Vec<ProcedureNode>,
    pub edges: Vec<ProcedureEdge>,
    pub total_found: usize,
    pub coherence_estimate: f64,
}

impl SubstrateClient {
    /// Create a new substrate client
    pub fn new(base_url: &str) -> Self {
        info!("Creating substrate client for: {}", base_url);
        Self {
            client: Client::new(),
            base_url: base_url.to_string(),
        }
    }
    
    /// Query a local patch from the substrate
    /// This is the PRIMARY interface for consciousness - vChip queries here before collapse
    pub async fn query_local_patch(
        &self,
        scale: &str,
        center: &[f64; 8],
        intent: Option<&str>,
    ) -> Result<PatchResponse> {
        let request = PatchRequest {
            scale: scale.to_string(),
            center: *center,
            radius: None, // Use default for scale
            intent: intent.map(|s| s.to_string()),
            max_procedures: Some(50), // Reasonable limit for collapse
        };
        
        let url = format!("{}/substrate/patch", self.base_url);
        
        let resp = self.client
            .post(&url)
            .json(&request)
            .send()
            .await?;
        
        if !resp.status().is_success() {
            let status = resp.status();
            let body = resp.text().await.unwrap_or_default();
            error!("Substrate query failed: {} - {}", status, body);
            anyhow::bail!("Substrate query failed: {status}");
        }
        
        let patch: PatchResponse = resp.json().await?;
        info!(
            "Queried {} patch: {} procedures, coherence {:.3}",
            patch.scale, patch.total_found, patch.coherence_estimate
        );
        
        Ok(patch)
    }
    
    /// Health check for the substrate
    #[allow(dead_code)]
    pub async fn health_check(&self) -> Result<bool> {
        let url = format!("{}/health", self.base_url);
        
        match self.client.get(&url).send().await {
            Ok(resp) => Ok(resp.status().is_success()),
            Err(e) => {
                warn!("Substrate health check failed: {}", e);
                Ok(false)
            }
        }
    }
    
    /// Compute weighted center from procedures (for collapse initialization)
    pub fn compute_weighted_center(&self, procedures: &[ProcedureNode]) -> [f64; 8] {
        if procedures.is_empty() {
            return [0.0; 8];
        }
        
        let mut weighted_sum = [0.0; 8];
        let mut total_weight = 0.0;
        
        for proc in procedures {
            // Weight by confidence and success rate
            let weight = proc.confidence * proc.success_rate;
            for i in 0..8 {
                weighted_sum[i] += proc.d0_d7[i] * weight;
            }
            total_weight += weight;
        }
        
        if total_weight > 0.0 {
            for i in 0..8 {
                weighted_sum[i] /= total_weight;
            }
        }
        
        weighted_sum
    }
    
    /// Compute risk-adjusted 8D state from procedures
    /// Uses MAX risk (D5) for safety-critical applications
    pub fn compute_risk_adjusted_state(&self, procedures: &[ProcedureNode]) -> [f64; 8] {
        if procedures.is_empty() {
            return [0.0; 8];
        }
        
        let mut state = self.compute_weighted_center(procedures);
        
        // Override D5 with MAX risk (conservative)
        let max_risk = procedures
            .iter()
            .map(|p| p.d0_d7[5])
            .max_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal))
            .unwrap_or(0.0);
        state[5] = max_risk;
        
        // D7 uncertainty increases with procedure count diversity
        let unique_contexts: std::collections::HashSet<_> = procedures
            .iter()
            .map(|p| &p.context)
            .collect();
        state[7] = (unique_contexts.len() as f64 / 5.0).min(1.0);
        
        state
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_weighted_center() {
        let client = SubstrateClient::new("http://localhost:8700");
        
        let procs = vec![
            ProcedureNode {
                id: "1".to_string(),
                context: "test".to_string(),
                d0_d7: [1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
                intent: "test".to_string(),
                success_rate: 1.0,
                execution_count: 10,
                risk_level: "low".to_string(),
                confidence: 1.0,
            },
            ProcedureNode {
                id: "2".to_string(),
                context: "test".to_string(),
                d0_d7: [0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
                intent: "test".to_string(),
                success_rate: 1.0,
                execution_count: 10,
                risk_level: "low".to_string(),
                confidence: 1.0,
            },
        ];
        
        let center = client.compute_weighted_center(&procs);
        assert!((center[0] - 0.5).abs() < 0.01);
        assert!((center[1] - 0.5).abs() < 0.01);
    }
}

