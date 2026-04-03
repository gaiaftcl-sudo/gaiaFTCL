//! Validation Runner
//!
//! Orchestrates IQ, OQ, PQ validation and updates capability gates.

use crate::{ModelFamily, CapabilityStatus, AutonomyLevel, ValidationStatus};
use crate::types::{IQRun, OQRun, PQRun};
use crate::thresholds::ValidationThresholds;
use crate::iq::IQRunner;
use crate::oq::OQRunner;
use crate::pq::PQRunner;
use crate::akg::AkgWriter;
use anyhow::Result;
use chrono::{Utc, Duration};
use std::collections::HashMap;

/// Combined validation runner for a model family
pub struct ValidationRunner {
    akg_writer: AkgWriter,
}

impl Default for ValidationRunner {
    fn default() -> Self {
        Self::new()
    }
}

impl ValidationRunner {
    pub fn new() -> Self {
        Self {
            akg_writer: AkgWriter::new(),
        }
    }
    
    /// Run full IQ/OQ/PQ validation for a model
    pub async fn run_full_validation(
        &self,
        model_id: &str,
        family: ModelFamily,
    ) -> Result<ValidationResult> {
        let thresholds = ValidationThresholds::for_family(family);
        
        tracing::info!(
            model_id = model_id,
            family = ?family,
            "Starting full validation"
        );
        
        // Run IQ
        let iq_runner = IQRunner::new(thresholds.iq.clone());
        let iq_run = iq_runner.run(model_id, family).await?;
        self.akg_writer.write_iq_run(&iq_run).await?;
        
        tracing::info!(
            model_id = model_id,
            iq_status = ?iq_run.meta.status,
            "IQ validation complete"
        );
        
        // Run OQ
        let oq_runner = OQRunner::new(thresholds.oq.clone());
        let oq_run = oq_runner.run(model_id, family).await?;
        self.akg_writer.write_oq_run(&oq_run).await?;
        
        tracing::info!(
            model_id = model_id,
            oq_status = ?oq_run.meta.status,
            "OQ validation complete"
        );
        
        // Run PQ
        let pq_runner = PQRunner::new(thresholds.pq.clone());
        let pq_run = pq_runner.run(model_id, family, "default").await?;
        self.akg_writer.write_pq_run(&pq_run).await?;
        
        tracing::info!(
            model_id = model_id,
            pq_status = ?pq_run.meta.status,
            virtue_score = pq_run.aggregate_virtue_score,
            "PQ validation complete"
        );
        
        // Update capability gate
        let status = CapabilityStatus {
            family,
            iq_pass: iq_run.meta.status == ValidationStatus::Pass,
            oq_pass: oq_run.meta.status == ValidationStatus::Pass,
            pq_pass: pq_run.meta.status == ValidationStatus::Pass,
            virtue_score: pq_run.aggregate_virtue_score,
            autonomy_level: AutonomyLevel::Disabled, // Will be calculated
            last_validated: Utc::now(),
            valid_until: Utc::now() + Duration::hours(24), // 24 hour validity
        };
        
        let mut status = status;
        status.autonomy_level = status.calculate_autonomy();
        
        self.akg_writer.update_capability_gate(&status).await?;
        
        tracing::info!(
            model_id = model_id,
            family = ?family,
            agi_mode = status.agi_mode_enabled(),
            autonomy = ?status.autonomy_level,
            "Capability gate updated"
        );
        
        Ok(ValidationResult {
            model_id: model_id.to_string(),
            family,
            iq_run,
            oq_run,
            pq_run,
            capability_status: status,
        })
    }
    
    /// Run only IQ validation
    pub async fn run_iq(&self, model_id: &str, family: ModelFamily) -> Result<IQRun> {
        let thresholds = ValidationThresholds::for_family(family);
        let iq_runner = IQRunner::new(thresholds.iq);
        let iq_run = iq_runner.run(model_id, family).await?;
        self.akg_writer.write_iq_run(&iq_run).await?;
        Ok(iq_run)
    }
    
    /// Run only OQ validation
    pub async fn run_oq(&self, model_id: &str, family: ModelFamily) -> Result<OQRun> {
        let thresholds = ValidationThresholds::for_family(family);
        let oq_runner = OQRunner::new(thresholds.oq);
        let oq_run = oq_runner.run(model_id, family).await?;
        self.akg_writer.write_oq_run(&oq_run).await?;
        Ok(oq_run)
    }
    
    /// Run only PQ validation
    pub async fn run_pq(&self, model_id: &str, family: ModelFamily, benchmark: &str) -> Result<PQRun> {
        let thresholds = ValidationThresholds::for_family(family);
        let pq_runner = PQRunner::new(thresholds.pq);
        let pq_run = pq_runner.run(model_id, family, benchmark).await?;
        self.akg_writer.write_pq_run(&pq_run).await?;
        Ok(pq_run)
    }
    
    /// Get current capability status for all families
    pub async fn get_all_statuses(&self) -> Result<HashMap<ModelFamily, CapabilityStatus>> {
        let statuses = self.akg_writer.get_all_capability_statuses().await?;
        let mut map = HashMap::new();
        for status in statuses {
            map.insert(status.family, status);
        }
        Ok(map)
    }
    
    /// Check if AGI mode is enabled for a family
    pub async fn is_agi_enabled(&self, family: ModelFamily) -> Result<bool> {
        if let Some(status) = self.akg_writer.get_capability_status(family).await? {
            Ok(status.agi_mode_enabled() && status.valid_until > Utc::now())
        } else {
            Ok(false)
        }
    }
    
    /// Ensure AKG collections exist
    pub async fn ensure_akg_setup(&self) -> Result<()> {
        self.akg_writer.ensure_collections().await
    }
}

/// Result of a full validation run
#[derive(Debug)]
pub struct ValidationResult {
    pub model_id: String,
    pub family: ModelFamily,
    pub iq_run: IQRun,
    pub oq_run: OQRun,
    pub pq_run: PQRun,
    pub capability_status: CapabilityStatus,
}

impl ValidationResult {
    /// Check if all validations passed
    pub fn all_passed(&self) -> bool {
        self.iq_run.meta.status == ValidationStatus::Pass
            && self.oq_run.meta.status == ValidationStatus::Pass
            && self.pq_run.meta.status == ValidationStatus::Pass
    }
    
    /// Check if AGI mode is eligible
    pub fn agi_eligible(&self) -> bool {
        self.capability_status.agi_mode_enabled()
    }
    
    /// Get summary string
    pub fn summary(&self) -> String {
        format!(
            "Validation for {} ({}): IQ={:?}, OQ={:?}, PQ={:?}, Virtue={:.3}, AGI={}",
            self.model_id,
            self.family.as_str(),
            self.iq_run.meta.status,
            self.oq_run.meta.status,
            self.pq_run.meta.status,
            self.capability_status.virtue_score,
            if self.agi_eligible() { "ENABLED" } else { "DISABLED" }
        )
    }
}

