//! Core types for validation runs

use crate::{ModelFamily, ValidationStatus, QState8, VirtueScores};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

/// Base validation run metadata
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ValidationRunMeta {
    pub run_id: String,
    pub model_id: String,
    pub family: ModelFamily,
    pub status: ValidationStatus,
    pub timestamp: DateTime<Utc>,
    pub error_message: Option<String>,
}

//=============================================================================
// IQ (Installation Qualification) Types
//=============================================================================

/// IQ Run - validates mathematical correctness of the substrate
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IQRun {
    #[serde(flatten)]
    pub meta: ValidationRunMeta,
    
    /// QState8 normalization metrics
    pub qstate_norm_min: f64,
    pub qstate_norm_max: f64,
    pub qstate_norm_mean: f64,
    pub qstate_norm_std: f64,
    
    /// Projector coverage (0-1)
    pub projector_coverage: f64,
    
    /// AKG consistency (0-1)
    pub akg_consistency: f64,
    
    /// Whether GNN export is valid
    pub gnn_export_valid: bool,
    
    /// Number of samples tested
    pub sample_count: usize,
    
    /// Representative QState8 snapshot
    pub qstate_snapshot: Option<QState8>,
}

impl IQRun {
    pub fn new(model_id: &str, family: ModelFamily) -> Self {
        Self {
            meta: ValidationRunMeta {
                run_id: crate::generate_run_id(),
                model_id: model_id.to_string(),
                family,
                status: ValidationStatus::Pending,
                timestamp: Utc::now(),
                error_message: None,
            },
            qstate_norm_min: 0.0,
            qstate_norm_max: 0.0,
            qstate_norm_mean: 0.0,
            qstate_norm_std: 0.0,
            projector_coverage: 0.0,
            akg_consistency: 0.0,
            gnn_export_valid: false,
            sample_count: 0,
            qstate_snapshot: None,
        }
    }
    
    /// Evaluate pass/fail based on thresholds
    pub fn evaluate(&mut self, epsilon: f64, min_coverage: f64, min_consistency: f64) {
        let norm_ok = self.qstate_norm_max < epsilon && self.qstate_norm_min > -epsilon;
        let coverage_ok = self.projector_coverage >= min_coverage;
        let consistency_ok = self.akg_consistency >= min_consistency;
        let gnn_ok = self.gnn_export_valid;
        
        if norm_ok && coverage_ok && consistency_ok && gnn_ok {
            self.meta.status = ValidationStatus::Pass;
        } else {
            self.meta.status = ValidationStatus::Fail;
            let mut errors = Vec::new();
            if !norm_ok { errors.push(format!("QState norm out of bounds: [{}, {}]", self.qstate_norm_min, self.qstate_norm_max)); }
            if !coverage_ok { errors.push(format!("Projector coverage too low: {}", self.projector_coverage)); }
            if !consistency_ok { errors.push(format!("AKG consistency too low: {}", self.akg_consistency)); }
            if !gnn_ok { errors.push("GNN export invalid".to_string()); }
            self.meta.error_message = Some(errors.join("; "));
        }
    }
}

//=============================================================================
// OQ (Operational Qualification) Types
//=============================================================================

/// OQ Run - validates runtime behavior under load
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OQRun {
    #[serde(flatten)]
    pub meta: ValidationRunMeta,
    
    /// Latency metrics (milliseconds)
    pub p50_latency_ms: f64,
    pub p95_latency_ms: f64,
    pub p99_latency_ms: f64,
    
    /// Error rates
    pub error_rate: f64,
    pub timeout_rate: f64,
    
    /// Safety metrics
    pub safety_block_rate: f64,      // Harmful requests correctly blocked
    pub safety_passthrough_rate: f64, // Safe requests correctly allowed
    
    /// Load test parameters
    pub concurrent_users: usize,
    pub total_requests: usize,
    
    /// Scenario coverage
    pub scenario_coverage: f64,
    pub scenarios_passed: usize,
    pub scenarios_total: usize,
}

impl OQRun {
    pub fn new(model_id: &str, family: ModelFamily) -> Self {
        Self {
            meta: ValidationRunMeta {
                run_id: crate::generate_run_id(),
                model_id: model_id.to_string(),
                family,
                status: ValidationStatus::Pending,
                timestamp: Utc::now(),
                error_message: None,
            },
            p50_latency_ms: 0.0,
            p95_latency_ms: 0.0,
            p99_latency_ms: 0.0,
            error_rate: 0.0,
            timeout_rate: 0.0,
            safety_block_rate: 0.0,
            safety_passthrough_rate: 0.0,
            concurrent_users: 0,
            total_requests: 0,
            scenario_coverage: 0.0,
            scenarios_passed: 0,
            scenarios_total: 0,
        }
    }
    
    /// Evaluate pass/fail based on thresholds
    pub fn evaluate(
        &mut self,
        max_p95_latency: f64,
        max_error_rate: f64,
        min_safety_block: f64,
        min_safety_pass: f64,
        min_scenario_coverage: f64,
    ) {
        let latency_ok = self.p95_latency_ms <= max_p95_latency;
        let error_ok = self.error_rate <= max_error_rate;
        let safety_block_ok = self.safety_block_rate >= min_safety_block;
        let safety_pass_ok = self.safety_passthrough_rate >= min_safety_pass;
        let coverage_ok = self.scenario_coverage >= min_scenario_coverage;
        
        if latency_ok && error_ok && safety_block_ok && safety_pass_ok && coverage_ok {
            self.meta.status = ValidationStatus::Pass;
        } else {
            self.meta.status = ValidationStatus::Fail;
            let mut errors = Vec::new();
            if !latency_ok { errors.push(format!("p95 latency too high: {}ms", self.p95_latency_ms)); }
            if !error_ok { errors.push(format!("error rate too high: {}", self.error_rate)); }
            if !safety_block_ok { errors.push(format!("safety block rate too low: {}", self.safety_block_rate)); }
            if !safety_pass_ok { errors.push(format!("safety passthrough rate too low: {}", self.safety_passthrough_rate)); }
            if !coverage_ok { errors.push(format!("scenario coverage too low: {}", self.scenario_coverage)); }
            self.meta.error_message = Some(errors.join("; "));
        }
    }
}

//=============================================================================
// PQ (Performance Qualification) Types
//=============================================================================

/// PQ Run - validates domain-specific quality and virtue metrics
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PQRun {
    #[serde(flatten)]
    pub meta: ValidationRunMeta,
    
    /// General metrics (all domains)
    pub task_accuracy: f64,
    pub self_correction_rate: f64,
    pub fot_consistency: f64,
    
    /// Virtue scores from 8D state analysis
    pub virtue_scores: VirtueScores,
    pub aggregate_virtue_score: f64,
    
    /// Domain-specific metrics
    pub domain_metrics: DomainMetrics,
    
    /// AGI mode eligibility
    pub agi_mode_eligible: bool,
    
    /// Benchmark details
    pub benchmark_name: String,
    pub tasks_completed: usize,
    pub tasks_total: usize,
}

impl PQRun {
    pub fn new(model_id: &str, family: ModelFamily, benchmark_name: &str) -> Self {
        Self {
            meta: ValidationRunMeta {
                run_id: crate::generate_run_id(),
                model_id: model_id.to_string(),
                family,
                status: ValidationStatus::Pending,
                timestamp: Utc::now(),
                error_message: None,
            },
            task_accuracy: 0.0,
            self_correction_rate: 0.0,
            fot_consistency: 0.0,
            virtue_scores: VirtueScores {
                prudence: 0.0,
                justice: 0.0,
                temperance: 0.0,
                fortitude: 0.0,
                honesty: 0.0,
                benevolence: 0.0,
                humility: 0.0,
                wisdom: 0.0,
            },
            aggregate_virtue_score: 0.0,
            domain_metrics: DomainMetrics::GeneralReasoning(GeneralReasoningMetrics::default()),
            agi_mode_eligible: false,
            benchmark_name: benchmark_name.to_string(),
            tasks_completed: 0,
            tasks_total: 0,
        }
    }
    
    /// Evaluate pass/fail and AGI eligibility
    pub fn evaluate(&mut self, min_accuracy: f64, min_virtue: f64, min_fot: f64) {
        let accuracy_ok = self.task_accuracy >= min_accuracy;
        let virtue_ok = self.aggregate_virtue_score >= min_virtue;
        let fot_ok = self.fot_consistency >= min_fot;
        
        // AGI mode requires higher bar
        self.agi_mode_eligible = accuracy_ok && self.aggregate_virtue_score >= 0.95 && fot_ok;
        
        if accuracy_ok && virtue_ok && fot_ok {
            self.meta.status = ValidationStatus::Pass;
        } else {
            self.meta.status = ValidationStatus::Fail;
            let mut errors = Vec::new();
            if !accuracy_ok { errors.push(format!("task accuracy too low: {}", self.task_accuracy)); }
            if !virtue_ok { errors.push(format!("virtue score too low: {}", self.aggregate_virtue_score)); }
            if !fot_ok { errors.push(format!("FoT consistency too low: {}", self.fot_consistency)); }
            self.meta.error_message = Some(errors.join("; "));
        }
    }
}

//=============================================================================
// Domain-Specific Metrics
//=============================================================================

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "domain", content = "metrics")]
pub enum DomainMetrics {
    // Core (7)
    GeneralReasoning(GeneralReasoningMetrics),
    Vision(VisionMetrics),
    Protein(ProteinMetrics),
    Math(MathMetrics),
    Medical(MedicalMetrics),
    Code(CodeMetrics),
    Fara(FaraMetrics),
    // Scientific (3)
    Chemistry(ChemistryMetrics),
    Galaxy(GalaxyMetrics),
    WorldModels(WorldModelsMetrics),
    // Professional (3)
    Legal(LegalMetrics),
    Engineering(EngineeringMetrics),
    Finance(FinanceMetrics),
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct GeneralReasoningMetrics {
    pub reasoning_score: f64,
    pub coherence_score: f64,
    pub mmlu_score: Option<f64>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct VisionMetrics {
    pub ui_target_accuracy: f64,
    pub sensitive_visual_handling: f64,
    pub ocr_accuracy: Option<f64>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct ProteinMetrics {
    pub stability_success: f64,
    pub ethical_risk_penalty: f64,
    pub foldability_score: Option<f64>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct MathMetrics {
    pub math_correctness: f64,
    pub verification_success: f64,
    pub symbolic_accuracy: Option<f64>,
    pub word_problem_accuracy: Option<f64>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct MedicalMetrics {
    pub guideline_agreement: f64,
    pub harm_avoidance: f64,
    pub referral_appropriateness: f64,
    pub diagnostic_accuracy: Option<f64>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct CodeMetrics {
    pub test_pass_rate: f64,
    pub security_score: f64,
    pub bug_fix_rate: Option<f64>,
    pub code_quality_score: Option<f64>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct FaraMetrics {
    pub mission_completion_rate: f64,
    pub avg_steps_to_completion: f64,
    pub forbidden_action_rate: f64,
    pub efficiency_score: Option<f64>,
}

// ===========================================
// SCIENTIFIC EXPANSION (3)
// ===========================================

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct ChemistryMetrics {
    pub synthesis_accuracy: f64,
    pub safety_compliance: f64,
    pub toxicity_avoidance: f64,
    pub yield_prediction_accuracy: Option<f64>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct GalaxyMetrics {
    pub prediction_accuracy: f64,
    pub speculation_quality: f64,
    pub observational_alignment: f64,
    pub peer_review_score: Option<f64>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct WorldModelsMetrics {
    pub physics_accuracy: f64,
    pub temporal_consistency: f64,
    pub sim2real_score: f64,
    pub prediction_horizon_accuracy: Option<f64>,
}

// ===========================================
// PROFESSIONAL EXPANSION (3)
// ===========================================

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct LegalMetrics {
    pub jurisdiction_accuracy: f64,
    pub precedent_alignment: f64,
    pub risk_assessment_quality: f64,
    pub counsel_recommendation_appropriateness: Option<f64>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct EngineeringMetrics {
    pub design_accuracy: f64,
    pub safety_compliance: f64,
    pub feasibility_score: f64,
    pub standards_adherence: Option<f64>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct FinanceMetrics {
    pub analysis_accuracy: f64,
    pub risk_assessment_quality: f64,
    pub regulatory_compliance: f64,
    pub fiduciary_alignment: Option<f64>,
}

