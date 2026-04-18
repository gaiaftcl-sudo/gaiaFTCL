//! IQ (Installation Qualification) Validators
//!
//! Validates that the substrate is wired correctly:
//! - QState8 normalization
//! - Projector coverage
//! - AKG consistency
//! - GNN export sanity

mod akg_validator;
mod gnn_validator;
mod projector_validator;
mod qstate_validator;

pub use akg_validator::AkgConsistencyValidator;
pub use gnn_validator::GnnExportValidator;
pub use projector_validator::ProjectorValidator;
pub use qstate_validator::QStateValidator;

use crate::thresholds::IQThresholds;
use crate::types::IQRun;
use crate::{ModelFamily, QState8};
use anyhow::Result;
use async_trait::async_trait;

/// IQ Validator trait - all IQ checks implement this
#[async_trait]
pub trait IQValidator: Send + Sync {
    /// Run the validation and return results
    async fn validate(&self, model_id: &str, family: ModelFamily) -> Result<IQValidationResult>;

    /// Name of this validator
    fn name(&self) -> &'static str;
}

/// Result from a single IQ validation check
#[derive(Debug, Clone)]
pub struct IQValidationResult {
    pub validator_name: String,
    pub passed: bool,
    pub score: f64, // 0.0 to 1.0
    pub details: String,
    pub samples: Vec<QState8>,
}

/// Combined IQ runner that executes all IQ validators
pub struct IQRunner {
    validators: Vec<Box<dyn IQValidator>>,
    thresholds: IQThresholds,
}

impl IQRunner {
    pub fn new(thresholds: IQThresholds) -> Self {
        Self {
            validators: vec![
                Box::new(QStateValidator::new()),
                Box::new(ProjectorValidator::new()),
                Box::new(AkgConsistencyValidator::new()),
                Box::new(GnnExportValidator::new()),
            ],
            thresholds,
        }
    }

    /// Run all IQ validators and produce an IQRun result
    pub async fn run(&self, model_id: &str, family: ModelFamily) -> Result<IQRun> {
        let mut iq_run = IQRun::new(model_id, family);

        let mut all_samples = Vec::new();
        let mut total_score = 0.0;
        let mut validator_count = 0;

        for validator in &self.validators {
            match validator.validate(model_id, family).await {
                Ok(result) => {
                    tracing::info!(
                        validator = validator.name(),
                        passed = result.passed,
                        score = result.score,
                        "IQ validation complete"
                    );

                    all_samples.extend(result.samples);
                    total_score += result.score;
                    validator_count += 1;

                    // Map results to IQRun fields
                    match validator.name() {
                        "QStateValidator" => {
                            // Extract norm stats from samples
                            if !all_samples.is_empty() {
                                let norms: Vec<f64> = all_samples
                                    .iter()
                                    .map(|s| (s.norm_squared() - 1.0).abs())
                                    .collect();
                                iq_run.qstate_norm_min =
                                    norms.iter().cloned().fold(f64::INFINITY, f64::min);
                                iq_run.qstate_norm_max =
                                    norms.iter().cloned().fold(f64::NEG_INFINITY, f64::max);
                                iq_run.qstate_norm_mean =
                                    norms.iter().sum::<f64>() / norms.len() as f64;
                                iq_run.qstate_norm_std = {
                                    let mean = iq_run.qstate_norm_mean;
                                    let variance =
                                        norms.iter().map(|x| (x - mean).powi(2)).sum::<f64>()
                                            / norms.len() as f64;
                                    variance.sqrt()
                                };
                            }
                        }
                        "ProjectorValidator" => {
                            iq_run.projector_coverage = result.score;
                        }
                        "AkgConsistencyValidator" => {
                            iq_run.akg_consistency = result.score;
                        }
                        "GnnExportValidator" => {
                            iq_run.gnn_export_valid = result.passed;
                        }
                        _ => {}
                    }
                }
                Err(e) => {
                    tracing::error!(
                        validator = validator.name(),
                        error = %e,
                        "IQ validation failed"
                    );
                    iq_run.meta.error_message = Some(format!("{} failed: {}", validator.name(), e));
                }
            }
        }

        iq_run.sample_count = all_samples.len();
        if let Some(sample) = all_samples.first() {
            iq_run.qstate_snapshot = Some(sample.clone());
        }

        // Log aggregate score for audit trail (THIS USES total_score and validator_count)
        if validator_count > 0 {
            let average_score = total_score / validator_count as f64;
            tracing::info!(
                model_id = model_id,
                family = ?family,
                aggregate_score = average_score,
                validator_count = validator_count,
                "IQ validation aggregate score computed"
            );
        }

        // Evaluate pass/fail
        iq_run.evaluate(
            self.thresholds.qstate_norm_epsilon,
            self.thresholds.min_projector_coverage,
            self.thresholds.min_akg_consistency,
        );

        Ok(iq_run)
    }
}
