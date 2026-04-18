//! Quantum State Encoder for GaiaOS Models
//!
//! This module provides the orchestration layer that connects model outputs
//! to the 8D quantum substrate via the uum8d projector system.

use uum8d::{
    QState8, ProjectionContext, Uum8dProjector, ProjectorFactory,
    // Original 7 meta types
    TurnMeta, VisionMeta, ProteinMeta, MathMeta, MedicalMeta, CodeMeta,
    FaraStep, ComputerUseAction,
    // NEW 3 meta types
    ChemistryMeta, WorldModelMeta, GalaxyMeta,
};
use std::collections::HashMap;
use uuid::Uuid;

/// Result type for quantum encoding operations
pub type QuantumResult<T> = Result<T, QuantumEncoderError>;

#[derive(Debug, thiserror::Error)]
pub enum QuantumEncoderError {
    #[error("AKG write error: {0}")]
    AkgError(String),
    
    #[error("Invalid projector profile: {0}")]
    InvalidProfile(String),
    
    #[error("Normalization validation failed: norm = {0}")]
    NormalizationError(f32),
}

/// Trait for AKG client (allows mocking in tests)
pub trait AkgClient {
    fn create_node(&mut self, label: &str, props: HashMap<String, f64>) -> String;
    fn create_edge(&mut self, from: &str, to: &str, label: &str, props: HashMap<String, f64>);
}

/// Main quantum encoder orchestrator
pub struct QuantumEncoder {
    projector_factory: ProjectorFactory,
    validate_normalization: bool,
    normalization_tolerance: f32,
}

impl QuantumEncoder {
    pub fn new() -> Self {
        Self {
            projector_factory: ProjectorFactory::new(),
            validate_normalization: true,
            normalization_tolerance: 0.01,
        }
    }

    /// Validate that a quantum state is properly normalized
    fn validate_qstate(&self, qstate: &QState8) -> QuantumResult<()> {
        if !self.validate_normalization {
            return Ok(());
        }

        let norm: f32 = qstate.amps.iter().map(|x| x * x).sum::<f32>().sqrt();
        
        if (norm - 1.0).abs() > self.normalization_tolerance {
            return Err(QuantumEncoderError::NormalizationError(norm));
        }

        Ok(())
    }

    /// Write QState8 to AKG as uum:QState8 node
    fn write_qstate_to_akg(
        &self,
        akg: &mut dyn AkgClient,
        qstate: &QState8,
        step_node_id: &str,
    ) -> QuantumResult<String> {
        let mut props = HashMap::new();
        for (i, amp) in qstate.amps.iter().enumerate() {
            props.insert(format!("uum:amp{}", i), *amp as f64);
        }

        let qstate_node_id = akg.create_node("uum:QState8", props);
        akg.create_edge(step_node_id, &qstate_node_id, "gaia:hasQState8", HashMap::new());

        Ok(qstate_node_id)
    }

    // =========================================================================
    // GENERAL REASONING (LLaMA, Gemma, Mistral, Phi)
    // =========================================================================

    /// Encode a general reasoning turn (chat, tool use, etc.)
    pub fn encode_general_turn(
        &self,
        akg: &mut dyn AkgClient,
        model_profile: &str,
        role: &str,
        text: &str,
        meta: TurnMeta,
        step_node_id: &str,
    ) -> QuantumResult<String> {
        let ctx = ProjectionContext::GeneralTurn {
            role,
            text,
            meta: &meta,
        };

        let projector = self.projector_factory
            .from_profile(model_profile)
            .ok_or_else(|| QuantumEncoderError::InvalidProfile(model_profile.to_string()))?;

        let qstate = projector.project_qstate(&ctx);
        self.validate_qstate(&qstate)?;

        self.write_qstate_to_akg(akg, &qstate, step_node_id)
    }

    // =========================================================================
    // VISION (Qwen2-VL, Pixtral)
    // =========================================================================

    /// Encode a vision step (screenshot + prompt)
    pub fn encode_vision_step(
        &self,
        akg: &mut dyn AkgClient,
        model_profile: &str,
        prompt: &str,
        meta: VisionMeta,
        step_node_id: &str,
    ) -> QuantumResult<String> {
        let ctx = ProjectionContext::VisionStep {
            prompt,
            meta: &meta,
        };

        let projector = self.projector_factory
            .from_profile(model_profile)
            .ok_or_else(|| QuantumEncoderError::InvalidProfile(model_profile.to_string()))?;

        let qstate = projector.project_qstate(&ctx);
        self.validate_qstate(&qstate)?;

        self.write_qstate_to_akg(akg, &qstate, step_node_id)
    }

    // =========================================================================
    // PROTEIN (ESM2)
    // =========================================================================

    /// Encode a protein analysis step
    pub fn encode_protein_step(
        &self,
        akg: &mut dyn AkgClient,
        model_profile: &str,
        sequence: &str,
        meta: ProteinMeta,
        step_node_id: &str,
    ) -> QuantumResult<String> {
        let ctx = ProjectionContext::ProteinStep {
            sequence,
            meta: &meta,
        };

        let projector = self.projector_factory
            .from_profile(model_profile)
            .ok_or_else(|| QuantumEncoderError::InvalidProfile(model_profile.to_string()))?;

        let qstate = projector.project_qstate(&ctx);
        self.validate_qstate(&qstate)?;

        self.write_qstate_to_akg(akg, &qstate, step_node_id)
    }

    // =========================================================================
    // MATH (DeepSeek-Math)
    // =========================================================================

    /// Encode a mathematical reasoning step
    pub fn encode_math_step(
        &self,
        akg: &mut dyn AkgClient,
        model_profile: &str,
        problem: &str,
        solution: &str,
        meta: MathMeta,
        step_node_id: &str,
    ) -> QuantumResult<String> {
        let ctx = ProjectionContext::MathStep {
            problem,
            solution,
            meta: &meta,
        };

        let projector = self.projector_factory
            .from_profile(model_profile)
            .ok_or_else(|| QuantumEncoderError::InvalidProfile(model_profile.to_string()))?;

        let qstate = projector.project_qstate(&ctx);
        self.validate_qstate(&qstate)?;

        self.write_qstate_to_akg(akg, &qstate, step_node_id)
    }

    // =========================================================================
    // MEDICAL (Meditron)
    // =========================================================================

    /// Encode a medical reasoning step
    pub fn encode_medical_step(
        &self,
        akg: &mut dyn AkgClient,
        model_profile: &str,
        context: &str,
        recommendation: &str,
        meta: MedicalMeta,
        step_node_id: &str,
    ) -> QuantumResult<String> {
        let ctx = ProjectionContext::MedicalStep {
            context,
            recommendation,
            meta: &meta,
        };

        let projector = self.projector_factory
            .from_profile(model_profile)
            .ok_or_else(|| QuantumEncoderError::InvalidProfile(model_profile.to_string()))?;

        let qstate = projector.project_qstate(&ctx);
        self.validate_qstate(&qstate)?;

        self.write_qstate_to_akg(akg, &qstate, step_node_id)
    }

    // =========================================================================
    // CODE (StarCoder2)
    // =========================================================================

    /// Encode a code generation/review step
    pub fn encode_code_step(
        &self,
        akg: &mut dyn AkgClient,
        model_profile: &str,
        diff_summary: &str,
        meta: CodeMeta,
        step_node_id: &str,
    ) -> QuantumResult<String> {
        let ctx = ProjectionContext::CodeStep {
            diff_summary,
            meta: &meta,
        };

        let projector = self.projector_factory
            .from_profile(model_profile)
            .ok_or_else(|| QuantumEncoderError::InvalidProfile(model_profile.to_string()))?;

        let qstate = projector.project_qstate(&ctx);
        self.validate_qstate(&qstate)?;

        self.write_qstate_to_akg(akg, &qstate, step_node_id)
    }

    // =========================================================================
    // FARA (Computer Use Agent)
    // =========================================================================

    /// Encode a Fara computer-use step
    pub fn encode_fara_step(
        &self,
        akg: &mut dyn AkgClient,
        model_profile: &str,
        step: &FaraStep,
        action: &ComputerUseAction,
        step_node_id: &str,
    ) -> QuantumResult<String> {
        let ctx = ProjectionContext::FaraStep {
            step,
            action,
        };

        let projector = self.projector_factory
            .from_profile(model_profile)
            .ok_or_else(|| QuantumEncoderError::InvalidProfile(model_profile.to_string()))?;

        let qstate = projector.project_qstate(&ctx);
        self.validate_qstate(&qstate)?;

        self.write_qstate_to_akg(akg, &qstate, step_node_id)
    }

    // =========================================================================
    // NEW: CHEMISTRY (ChemLLM, ChemDFM, LlaSMol)
    // =========================================================================

    /// Encode a chemistry/molecular analysis step
    pub fn encode_chemistry_step(
        &self,
        akg: &mut dyn AkgClient,
        model_profile: &str,
        smiles: &str,
        meta: ChemistryMeta,
        step_node_id: &str,
    ) -> QuantumResult<String> {
        let ctx = ProjectionContext::ChemistryStep {
            smiles,
            meta: &meta,
        };

        let projector = self.projector_factory
            .from_profile(model_profile)
            .ok_or_else(|| QuantumEncoderError::InvalidProfile(model_profile.to_string()))?;

        let qstate = projector.project_qstate(&ctx);
        self.validate_qstate(&qstate)?;

        self.write_qstate_to_akg(akg, &qstate, step_node_id)
    }

    // =========================================================================
    // NEW: WORLD MODELS (Cosmos, CWM, UnifoLM, MineWorld)
    // =========================================================================

    /// Encode a world model simulation step
    pub fn encode_world_model_step(
        &self,
        akg: &mut dyn AkgClient,
        model_profile: &str,
        action: &str,
        meta: WorldModelMeta,
        step_node_id: &str,
    ) -> QuantumResult<String> {
        let ctx = ProjectionContext::WorldModelStep {
            action,
            meta: &meta,
        };

        let projector = self.projector_factory
            .from_profile(model_profile)
            .ok_or_else(|| QuantumEncoderError::InvalidProfile(model_profile.to_string()))?;

        let qstate = projector.project_qstate(&ctx);
        self.validate_qstate(&qstate)?;

        self.write_qstate_to_akg(akg, &qstate, step_node_id)
    }

    // =========================================================================
    // NEW: GALAXY / ASTROPHYSICS (AstroSage, CAMELS)
    // =========================================================================

    /// Encode a galaxy/astrophysics reasoning step
    pub fn encode_galaxy_step(
        &self,
        akg: &mut dyn AkgClient,
        model_profile: &str,
        query: &str,
        meta: GalaxyMeta,
        step_node_id: &str,
    ) -> QuantumResult<String> {
        let ctx = ProjectionContext::GalaxyStep {
            query,
            meta: &meta,
        };

        let projector = self.projector_factory
            .from_profile(model_profile)
            .ok_or_else(|| QuantumEncoderError::InvalidProfile(model_profile.to_string()))?;

        let qstate = projector.project_qstate(&ctx);
        self.validate_qstate(&qstate)?;

        self.write_qstate_to_akg(akg, &qstate, step_node_id)
    }
}

impl Default for QuantumEncoder {
    fn default() -> Self {
        Self::new()
    }
}

// =============================================================================
// EXAMPLE USAGE PATTERNS
// =============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    struct MockAkg {
        nodes: Vec<(String, HashMap<String, f64>)>,
        edges: Vec<(String, String, String)>,
    }

    impl MockAkg {
        fn new() -> Self {
            Self {
                nodes: Vec::new(),
                edges: Vec::new(),
            }
        }
    }

    impl AkgClient for MockAkg {
        fn create_node(&mut self, label: &str, props: HashMap<String, f64>) -> String {
            let id = format!("node_{}", self.nodes.len());
            self.nodes.push((label.to_string(), props));
            id
        }

        fn create_edge(&mut self, from: &str, to: &str, label: &str, _props: HashMap<String, f64>) {
            self.edges.push((from.to_string(), to.to_string(), label.to_string()));
        }
    }

    #[test]
    fn test_encode_general_reasoning_llama() {
        let encoder = QuantumEncoder::new();
        let mut akg = MockAkg::new();

        let meta = TurnMeta {
            domain: Some("general".to_string()),
            tool_calls: 0,
            safety_risk: None,
            safety_blocked: false,
            user_rating: None,
            step_index: 0,
            max_steps_hint: None,
        };

        let result = encoder.encode_general_turn(
            &mut akg,
            "uum8d_general_reasoning",
            "assistant",
            "I can help you with that task.",
            meta,
            "step_001",
        );

        assert!(result.is_ok());
        assert_eq!(akg.nodes.len(), 1);
        assert_eq!(akg.edges.len(), 1);
        assert_eq!(akg.nodes[0].0, "uum:QState8");
        
        // Verify all 8 amplitudes are present
        let props = &akg.nodes[0].1;
        for i in 0..8 {
            assert!(props.contains_key(&format!("uum:amp{}", i)));
        }
    }

    #[test]
    fn test_encode_vision_step() {
        let encoder = QuantumEncoder::new();
        let mut akg = MockAkg::new();

        let meta = VisionMeta {
            num_regions: 5,
            ocr_chars: 100,
            ui_like: true,
            nsfw_risk: None,
            step_index: 0,
        };

        let result = encoder.encode_vision_step(
            &mut akg,
            "uum8d_vision_step",
            "What is in this image?",
            meta,
            "step_vision_001",
        );

        assert!(result.is_ok());
        assert_eq!(akg.nodes[0].0, "uum:QState8");
    }

    #[test]
    fn test_encode_protein_step() {
        let encoder = QuantumEncoder::new();
        let mut akg = MockAkg::new();

        let meta = ProteinMeta {
            seq_len: 200,
            novelty_score: 0.75,
            stability_score: 0.85,
            active_site_conf: 0.9,
            ethics_risk: 0.2,
            step_index: 0,
        };

        let result = encoder.encode_protein_step(
            &mut akg,
            "uum8d_protein_step",
            "MKTAYIAKQRQISFVKSHFSRQLEERLGLIEVQAPILSRVGDGTQDNLSGAEKAVQVKVKALPDAQFEVVHSLAKWKRQTLGQHDFSAGEGLYTHMKALRPDEDRLSPLHSVYVDQWDWERVMGDGERQFSTLKSTVEAIWAGIKATEAAVSEEFGLAPFLPDQIHFVHSQELLSRYPDLDAKGRERAIAKDLGAVFLVGIGGKLSDGHRHDVRAPDYDDWSTPSELGHAGLNGDILVWNPVLEDAFELSSMGIRVDADTLKHQLALTGDEDRLELEWHQALLRGEMPQTIGGGIGQSRLTMLLLQLPHIGQVQAGVWPAAVRESVPSLL",
            meta,
            "step_protein_001",
        );

        assert!(result.is_ok());
        assert_eq!(akg.nodes[0].0, "uum:QState8");
    }

    #[test]
    fn test_encode_math_step() {
        let encoder = QuantumEncoder::new();
        let mut akg = MockAkg::new();

        let meta = MathMeta {
            difficulty: 0.7,
            uses_formal_proof: true,
            uses_diagram: false,
            correctness: Some(1.0),
            scratch_tokens: 500,
            step_index: 0,
        };

        let result = encoder.encode_math_step(
            &mut akg,
            "uum8d_math_step",
            "Prove that the square root of 2 is irrational.",
            "Assume √2 = p/q where p,q are coprime integers...",
            meta,
            "step_math_001",
        );

        assert!(result.is_ok());
        assert_eq!(akg.nodes[0].0, "uum:QState8");
    }

    #[test]
    fn test_encode_medical_step() {
        let encoder = QuantumEncoder::new();
        let mut akg = MockAkg::new();

        let meta = MedicalMeta {
            acuity: 0.6,
            risk_score: 0.4,
            guideline_alignment: 0.9,
            uncertainty: 0.3,
            recommends_referral: false,
            step_index: 0,
        };

        let result = encoder.encode_medical_step(
            &mut akg,
            "uum8d_medical_step",
            "Patient presents with persistent cough for 3 weeks.",
            "Recommend chest X-ray and spirometry testing.",
            meta,
            "step_medical_001",
        );

        assert!(result.is_ok());
        assert_eq!(akg.nodes[0].0, "uum:QState8");
    }

    #[test]
    fn test_encode_code_step() {
        let encoder = QuantumEncoder::new();
        let mut akg = MockAkg::new();

        let meta = CodeMeta {
            loc_delta: 50,
            complexity_delta: 5,
            test_coverage_delta: 10.0,
            has_security_changes: false,
            lint_pass: true,
            perf_impact_est: 0.0,
            step_index: 0,
        };

        let result = encoder.encode_code_step(
            &mut akg,
            "uum8d_code_step",
            "Added new API endpoint for user authentication",
            meta,
            "step_code_001",
        );

        assert!(result.is_ok());
        assert_eq!(akg.nodes[0].0, "uum:QState8");
    }

    #[test]
    fn test_normalization_validation() {
        let encoder = QuantumEncoder::new();
        let mut akg = MockAkg::new();

        let meta = TurnMeta::default();

        // This should produce a normalized state
        let result = encoder.encode_general_turn(
            &mut akg,
            "uum8d_general_reasoning",
            "user",
            "Hello",
            meta,
            "step_norm_test",
        );

        assert!(result.is_ok(), "Quantum state should be properly normalized");
    }

    // =========================================================================
    // NEW: Tests for Chemistry, World Model, Galaxy
    // =========================================================================

    #[test]
    fn test_encode_chemistry_step_chemllm() {
        let encoder = QuantumEncoder::new();
        let mut akg = MockAkg::new();

        let meta = ChemistryMeta {
            atom_count: 21,
            molecular_weight: 180.16,
            toxicity_score: Some(0.3),
            reactivity_hazard: Some(0.2),
            synthesis_feasibility: Some(0.95),
            novelty_score: Some(0.1),
            predicted_yield: Some(0.88),
            environmental_impact: Some(0.2),
            confidence: Some(0.98),
            step_index: 0,
        };

        // Aspirin SMILES
        let result = encoder.encode_chemistry_step(
            &mut akg,
            "uum8d_chemistry_step",
            "CC(=O)OC1=CC=CC=C1C(=O)O",
            meta,
            "step_chem_aspirin",
        );

        assert!(result.is_ok());
        assert_eq!(akg.nodes[0].0, "uum:QState8");
    }

    #[test]
    fn test_encode_world_model_step_cosmos() {
        let encoder = QuantumEncoder::new();
        let mut akg = MockAkg::new();

        let meta = WorldModelMeta {
            simulation_type: Some("video_generation".to_string()),
            physics_fidelity: Some(0.9),
            temporal_consistency: Some(0.85),
            num_objects: Some(25),
            prediction_accuracy: Some(0.82),
            sim2real_score: Some(0.75),
            harm_potential: Some(0.1),
            confidence: Some(0.88),
            horizon_steps: 30,
            step_index: 0,
        };

        let result = encoder.encode_world_model_step(
            &mut akg,
            "uum8d_world_model_step",
            "Generate video of robot navigation in warehouse",
            meta,
            "step_world_cosmos",
        );

        assert!(result.is_ok());
        assert_eq!(akg.nodes[0].0, "uum:QState8");
    }

    #[test]
    fn test_encode_galaxy_step_astrosage() {
        let encoder = QuantumEncoder::new();
        let mut akg = MockAkg::new();

        let meta = GalaxyMeta {
            domain: Some("cosmology".to_string()),
            speculation_level: Some(0.4),
            observational_support: Some(0.8),
            temporal_scale_years: Some(1e10),  // 10 billion years
            multi_messenger_data: Some(0.5),
            peer_review_score: Some(0.85),
            step_index: 0,
        };

        let result = encoder.encode_galaxy_step(
            &mut akg,
            "uum8d_galaxy_step",
            "What is the current understanding of dark energy?",
            meta,
            "step_galaxy_darkenergy",
        );

        assert!(result.is_ok());
        assert_eq!(akg.nodes[0].0, "uum:QState8");
    }
}


