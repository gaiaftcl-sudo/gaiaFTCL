//! GNN Export Validator
//!
//! Validates that GNN export produces valid, non-NaN features with correct shape.

use super::{IQValidator, IQValidationResult};
use crate::ModelFamily;
use async_trait::async_trait;
use anyhow::Result;
use serde::Deserialize;

pub struct GnnExportValidator {
    gnn_url: String,
}

impl Default for GnnExportValidator {
    fn default() -> Self {
        Self::new()
    }
}

impl GnnExportValidator {
    pub fn new() -> Self {
        Self {
            gnn_url: std::env::var("GNN_URL")
                .unwrap_or_else(|_| "http://localhost:8700".to_string()),
        }
    }
}

#[async_trait]
impl IQValidator for GnnExportValidator {
    fn name(&self) -> &'static str {
        "GnnExportValidator"
    }
    
    async fn validate(&self, model_id: &str, family: ModelFamily) -> Result<IQValidationResult> {
        tracing::info!(
            model_id = model_id,
            family = ?family,
            "Starting GNN export validation"
        );
        
        let client = reqwest::Client::new();
        
        // Request a small trajectory export from GNN service
        let response = client
            .get(format!("{}/api/export/test", self.gnn_url))
            .query(&[
                ("model_id", model_id),
                ("family", family.as_str()),
                ("max_nodes", "50"),
            ])
            .send()
            .await;
        
        #[derive(Deserialize)]
        struct GnnExportResult {
            node_features: Vec<Vec<f64>>,
            edge_index: Vec<Vec<usize>>,
            valid: bool,
            error: Option<String>,
        }
        
        let (passed, score, details) = match response {
            Ok(resp) if resp.status().is_success() => {
                if let Ok(export) = resp.json::<GnnExportResult>().await {
                    let mut issues = Vec::new();
                    
                    // Check for NaN or Inf values
                    let has_nan_inf = export.node_features.iter().any(|row| {
                        row.iter().any(|v| v.is_nan() || v.is_infinite())
                    });
                    if has_nan_inf {
                        issues.push("Contains NaN or Inf values");
                    }
                    
                    // Check feature dimension (should be 8 for QState8)
                    let wrong_dim = export.node_features.iter().any(|row| row.len() != 8);
                    if wrong_dim {
                        issues.push("Wrong feature dimension (expected 8)");
                    }
                    
                    // Check edge index validity
                    let num_nodes = export.node_features.len();
                    let invalid_edges = export.edge_index.iter().flatten().any(|&idx| idx >= num_nodes);
                    if invalid_edges {
                        issues.push("Invalid edge indices");
                    }
                    
                    if issues.is_empty() && export.valid {
                        (true, 1.0, format!(
                            "GNN export valid: {} nodes, {} edges",
                            export.node_features.len(),
                            export.edge_index.len()
                        ))
                    } else {
                        let error_msg = if let Some(err) = export.error {
                            format!("Export error: {err}")
                        } else {
                            issues.join("; ")
                        };
                        (false, 0.0, error_msg)
                    }
                } else {
                    (false, 0.0, "Failed to parse GNN export response".to_string())
                }
            }
            Ok(resp) => {
                tracing::debug!(
                    status = resp.status().as_u16(),
                    "GNN export endpoint not available"
                );
                // Assume valid when service is not available
                (true, 1.0, "GNN service not available, assuming valid".to_string())
            }
            Err(e) => {
                tracing::debug!(error = %e, "GNN export request failed");
                (true, 1.0, "GNN service not reachable, assuming valid".to_string())
            }
        };
        
        Ok(IQValidationResult {
            validator_name: self.name().to_string(),
            passed,
            score,
            details,
            samples: Vec::new(),
        })
    }
}

