//! QState8 Normalization Validator
//!
//! Validates that all QState8 vectors have proper normalization: |Σ amp² - 1.0| < ε

use super::{IQValidator, IQValidationResult};
use crate::{ModelFamily, QState8};
use async_trait::async_trait;
use anyhow::Result;

pub struct QStateValidator {
    sample_count: usize,
    substrate_url: String,
}

impl Default for QStateValidator {
    fn default() -> Self {
        Self::new()
    }
}

impl QStateValidator {
    pub fn new() -> Self {
        Self {
            sample_count: 100,
            substrate_url: std::env::var("SUBSTRATE_URL")
                .unwrap_or_else(|_| "http://localhost:8000".to_string()),
        }
    }
    
    pub fn with_config(sample_count: usize, substrate_url: &str) -> Self {
        Self {
            sample_count,
            substrate_url: substrate_url.to_string(),
        }
    }
}

#[async_trait]
impl IQValidator for QStateValidator {
    fn name(&self) -> &'static str {
        "QStateValidator"
    }
    
    async fn validate(&self, model_id: &str, family: ModelFamily) -> Result<IQValidationResult> {
        tracing::info!(
            model_id = model_id,
            family = ?family,
            samples = self.sample_count,
            "Starting QState normalization validation"
        );
        
        let mut samples = Vec::with_capacity(self.sample_count);
        let mut valid_count = 0;
        let epsilon = 0.01; // Normalization tolerance
        
        // Fetch QState8 samples from the substrate
        let client = reqwest::Client::new();
        
        for i in 0..self.sample_count {
            // Request a QState sample for this model family
            let response = client
                .get(format!("{}/api/qstate/sample", self.substrate_url))
                .query(&[
                    ("model_id", model_id),
                    ("family", family.as_str()),
                    ("index", &i.to_string()),
                ])
                .send()
                .await;
            
            match response {
                Ok(resp) if resp.status().is_success() => {
                    if let Ok(qstate) = resp.json::<QState8>().await {
                        if qstate.is_normalized(epsilon) {
                            valid_count += 1;
                        }
                        samples.push(qstate);
                    }
                }
                Ok(resp) => {
                    // Field-of-Truth: validation must reflect real substrate behavior.
                    // If the endpoint is unavailable, fail closed instead of synthesizing samples.
                    let status = resp.status().as_u16();
                    let details = format!(
                        "QState normalization validation failed: substrate endpoint unavailable (GET {}/api/qstate/sample returned HTTP {}).",
                        self.substrate_url,
                        status
                    );
                    tracing::error!(status, %details);
                    return Ok(IQValidationResult {
                        validator_name: self.name().to_string(),
                        passed: false,
                        score: 0.0,
                        details,
                        samples: Vec::new(),
                    });
                }
                Err(e) => {
                    let details = format!(
                        "QState normalization validation failed: substrate request error (GET {}/api/qstate/sample). error={}",
                        self.substrate_url,
                        e
                    );
                    tracing::error!(error = %e, %details);
                    return Ok(IQValidationResult {
                        validator_name: self.name().to_string(),
                        passed: false,
                        score: 0.0,
                        details,
                        samples: Vec::new(),
                    });
                }
            }
        }
        
        let score = valid_count as f64 / samples.len().max(1) as f64;
        let passed = score >= 0.99; // Allow 1% tolerance
        
        Ok(IQValidationResult {
            validator_name: self.name().to_string(),
            passed,
            score,
            details: format!(
                "QState normalization: {}/{} valid (score: {:.3})",
                valid_count,
                samples.len(),
                score
            ),
            samples,
        })
    }
}
