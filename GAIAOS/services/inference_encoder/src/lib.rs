//! GaiaOS Inference Encoder
//!
//! This module wires quantum state encoding INTO the live inference path.
//! Every model call → ProjectionContext → QState8 → AKG → GNN
//!
//! THIS IS THE HOT PATH - not just registration.

use uum8d::{
    QState8, ProjectionContext, ProjectorFactory,
    TurnMeta, VisionMeta, ProteinMeta, MathMeta, MedicalMeta, CodeMeta,
    FaraStep, ComputerUseAction, ChemistryMeta, WorldModelMeta, GalaxyMeta,
};
use std::collections::HashMap;
use std::sync::Arc;
use log::{info, error};

/// AKG Client trait - implement for ArangoDB/Neo4j
pub trait AkgClient: Send + Sync {
    fn create_node(&self, label: &str, props: HashMap<String, serde_json::Value>) -> String;
    fn create_edge(&self, from: &str, to: &str, label: &str);
    fn query_nodes(&self, query: &str) -> Vec<serde_json::Value>;
}

/// In-memory AKG for testing (replace with real ArangoDB client)
pub struct InMemoryAkg {
    nodes: std::sync::RwLock<Vec<(String, String, HashMap<String, serde_json::Value>)>>,
    edges: std::sync::RwLock<Vec<(String, String, String)>>,
    node_counter: std::sync::atomic::AtomicU64,
}

impl InMemoryAkg {
    pub fn new() -> Self {
        Self {
            nodes: std::sync::RwLock::new(Vec::new()),
            edges: std::sync::RwLock::new(Vec::new()),
            node_counter: std::sync::atomic::AtomicU64::new(0),
        }
    }

    pub fn node_count(&self) -> usize {
        self.nodes.read().unwrap().len()
    }

    pub fn qstate_nodes(&self) -> Vec<(String, HashMap<String, serde_json::Value>)> {
        self.nodes.read().unwrap()
            .iter()
            .filter(|(_, label, _)| label == "uum:QState8")
            .map(|(id, _, props)| (id.clone(), props.clone()))
            .collect()
    }
}

impl Default for InMemoryAkg {
    fn default() -> Self {
        Self::new()
    }
}

impl AkgClient for InMemoryAkg {
    fn create_node(&self, label: &str, props: HashMap<String, serde_json::Value>) -> String {
        let id = format!("node_{}", self.node_counter.fetch_add(1, std::sync::atomic::Ordering::SeqCst));
        self.nodes.write().unwrap().push((id.clone(), label.to_string(), props));
        id
    }

    fn create_edge(&self, from: &str, to: &str, label: &str) {
        self.edges.write().unwrap().push((from.to_string(), to.to_string(), label.to_string()));
    }

    fn query_nodes(&self, _query: &str) -> Vec<serde_json::Value> {
        // Simplified - real impl would parse AQL
        vec![]
    }
}

/// The LIVE inference encoder - THIS IS THE HOT PATH
pub struct LiveInferenceEncoder {
    projector_factory: ProjectorFactory,
    akg: Arc<dyn AkgClient>,
    enable_logging: bool,
}

impl LiveInferenceEncoder {
    pub fn new(akg: Arc<dyn AkgClient>) -> Self {
        Self {
            projector_factory: ProjectorFactory::new(),
            akg,
            enable_logging: true,
        }
    }

    /// Validate QState8 normalization
    fn validate_normalization(&self, qstate: &QState8, model_id: &str) -> bool {
        let norm_sq: f32 = qstate.amps.iter().map(|x| x * x).sum();
        let is_valid = (norm_sq - 1.0).abs() < 0.02;
        
        if !is_valid {
            error!("[QSTATE8] NORMALIZATION FAILED model={model_id} norm²={norm_sq:.6}");
        }
        
        is_valid
    }

    /// Write QState8 to AKG - THE ACTUAL ENCODING
    fn write_qstate_to_akg(
        &self,
        qstate: &QState8,
        step_node_id: &str,
        model_id: &str,
        profile: &str,
    ) -> String {
        let mut props = HashMap::new();
        
        // Store all 8 amplitudes
        for (i, amp) in qstate.amps.iter().enumerate() {
            props.insert(
                format!("uum:amp{i}"),
                serde_json::json!(*amp as f64),
            );
        }
        
        // Metadata
        props.insert("model_id".to_string(), serde_json::json!(model_id));
        props.insert("profile".to_string(), serde_json::json!(profile));
        props.insert("encoded_at".to_string(), serde_json::json!(chrono::Utc::now().to_rfc3339()));
        
        // Create node
        let qstate_node_id = self.akg.create_node("uum:QState8", props);
        
        // Create edge from step to QState
        self.akg.create_edge(step_node_id, &qstate_node_id, "gaia:hasUUM8DState");
        
        qstate_node_id
    }

    // =========================================================================
    // LIVE ENCODING METHODS - CALL THESE AFTER MODEL INFERENCE
    // =========================================================================

    /// Encode a general reasoning step (LLaMA, Gemma, Mistral, Phi)
    /// CALL THIS AFTER model.generate() returns
    pub fn encode_after_general_inference(
        &self,
        model_id: &str,
        step_node_id: &str,
        role: &str,
        response_text: &str,
        meta: TurnMeta,
    ) -> Option<String> {
        let profile = "uum8d_general_reasoning";
        
        let ctx = ProjectionContext::GeneralTurn {
            role,
            text: response_text,
            meta: &meta,
        };

        let projector = self.projector_factory.from_profile(profile)?;
        let qstate = projector.project_qstate(&ctx);
        
        if !self.validate_normalization(&qstate, model_id) {
            return None;
        }

        let qstate_node_id = self.write_qstate_to_akg(&qstate, step_node_id, model_id, profile);

        if self.enable_logging {
            info!(
                "[QSTATE8] agent=gaia model={} profile={} amps=[{:.4}, {:.4}, {:.4}, {:.4}, {:.4}, {:.4}, {:.4}, {:.4}]",
                model_id, profile,
                qstate.amps[0], qstate.amps[1], qstate.amps[2], qstate.amps[3],
                qstate.amps[4], qstate.amps[5], qstate.amps[6], qstate.amps[7]
            );
        }

        Some(qstate_node_id)
    }

    /// Encode a vision step (Qwen2-VL, Pixtral)
    pub fn encode_after_vision_inference(
        &self,
        model_id: &str,
        step_node_id: &str,
        prompt: &str,
        meta: VisionMeta,
    ) -> Option<String> {
        let profile = "uum8d_vision_step";
        
        let ctx = ProjectionContext::VisionStep {
            prompt,
            meta: &meta,
        };

        let projector = self.projector_factory.from_profile(profile)?;
        let qstate = projector.project_qstate(&ctx);
        
        if !self.validate_normalization(&qstate, model_id) {
            return None;
        }

        let qstate_node_id = self.write_qstate_to_akg(&qstate, step_node_id, model_id, profile);

        if self.enable_logging {
            info!(
                "[QSTATE8] agent=gaia model={} profile={} amps=[{:.4}, {:.4}, {:.4}, {:.4}, {:.4}, {:.4}, {:.4}, {:.4}]",
                model_id, profile,
                qstate.amps[0], qstate.amps[1], qstate.amps[2], qstate.amps[3],
                qstate.amps[4], qstate.amps[5], qstate.amps[6], qstate.amps[7]
            );
        }

        Some(qstate_node_id)
    }

    /// Encode a protein analysis step (ESM2)
    pub fn encode_after_protein_inference(
        &self,
        model_id: &str,
        step_node_id: &str,
        sequence: &str,
        meta: ProteinMeta,
    ) -> Option<String> {
        let profile = "uum8d_protein_step";
        
        let ctx = ProjectionContext::ProteinStep {
            sequence,
            meta: &meta,
        };

        let projector = self.projector_factory.from_profile(profile)?;
        let qstate = projector.project_qstate(&ctx);
        
        if !self.validate_normalization(&qstate, model_id) {
            return None;
        }

        let qstate_node_id = self.write_qstate_to_akg(&qstate, step_node_id, model_id, profile);

        if self.enable_logging {
            info!(
                "[QSTATE8] agent=gaia model={} profile={} amps=[{:.4}, {:.4}, {:.4}, {:.4}, {:.4}, {:.4}, {:.4}, {:.4}]",
                model_id, profile,
                qstate.amps[0], qstate.amps[1], qstate.amps[2], qstate.amps[3],
                qstate.amps[4], qstate.amps[5], qstate.amps[6], qstate.amps[7]
            );
        }

        Some(qstate_node_id)
    }

    /// Encode a math reasoning step (DeepSeek-Math)
    pub fn encode_after_math_inference(
        &self,
        model_id: &str,
        step_node_id: &str,
        problem: &str,
        solution: &str,
        meta: MathMeta,
    ) -> Option<String> {
        let profile = "uum8d_math_step";
        
        let ctx = ProjectionContext::MathStep {
            problem,
            solution,
            meta: &meta,
        };

        let projector = self.projector_factory.from_profile(profile)?;
        let qstate = projector.project_qstate(&ctx);
        
        if !self.validate_normalization(&qstate, model_id) {
            return None;
        }

        let qstate_node_id = self.write_qstate_to_akg(&qstate, step_node_id, model_id, profile);

        if self.enable_logging {
            info!(
                "[QSTATE8] agent=gaia model={} profile={} amps=[{:.4}, {:.4}, {:.4}, {:.4}, {:.4}, {:.4}, {:.4}, {:.4}]",
                model_id, profile,
                qstate.amps[0], qstate.amps[1], qstate.amps[2], qstate.amps[3],
                qstate.amps[4], qstate.amps[5], qstate.amps[6], qstate.amps[7]
            );
        }

        Some(qstate_node_id)
    }

    /// Encode a medical reasoning step (Meditron)
    pub fn encode_after_medical_inference(
        &self,
        model_id: &str,
        step_node_id: &str,
        context: &str,
        recommendation: &str,
        meta: MedicalMeta,
    ) -> Option<String> {
        let profile = "uum8d_medical_step";
        
        let ctx = ProjectionContext::MedicalStep {
            context,
            recommendation,
            meta: &meta,
        };

        let projector = self.projector_factory.from_profile(profile)?;
        let qstate = projector.project_qstate(&ctx);
        
        if !self.validate_normalization(&qstate, model_id) {
            return None;
        }

        let qstate_node_id = self.write_qstate_to_akg(&qstate, step_node_id, model_id, profile);

        if self.enable_logging {
            info!(
                "[QSTATE8] agent=gaia model={} profile={} amps=[{:.4}, {:.4}, {:.4}, {:.4}, {:.4}, {:.4}, {:.4}, {:.4}]",
                model_id, profile,
                qstate.amps[0], qstate.amps[1], qstate.amps[2], qstate.amps[3],
                qstate.amps[4], qstate.amps[5], qstate.amps[6], qstate.amps[7]
            );
        }

        Some(qstate_node_id)
    }

    /// Encode a code generation step (StarCoder2)
    pub fn encode_after_code_inference(
        &self,
        model_id: &str,
        step_node_id: &str,
        diff_summary: &str,
        meta: CodeMeta,
    ) -> Option<String> {
        let profile = "uum8d_code_step";
        
        let ctx = ProjectionContext::CodeStep {
            diff_summary,
            meta: &meta,
        };

        let projector = self.projector_factory.from_profile(profile)?;
        let qstate = projector.project_qstate(&ctx);
        
        if !self.validate_normalization(&qstate, model_id) {
            return None;
        }

        let qstate_node_id = self.write_qstate_to_akg(&qstate, step_node_id, model_id, profile);

        if self.enable_logging {
            info!(
                "[QSTATE8] agent=gaia model={} profile={} amps=[{:.4}, {:.4}, {:.4}, {:.4}, {:.4}, {:.4}, {:.4}, {:.4}]",
                model_id, profile,
                qstate.amps[0], qstate.amps[1], qstate.amps[2], qstate.amps[3],
                qstate.amps[4], qstate.amps[5], qstate.amps[6], qstate.amps[7]
            );
        }

        Some(qstate_node_id)
    }

    /// Encode a Fara computer-use step
    pub fn encode_after_fara_inference(
        &self,
        model_id: &str,
        step_node_id: &str,
        step: &FaraStep,
        action: &ComputerUseAction,
    ) -> Option<String> {
        let profile = "uum8d_fara_step";
        
        let ctx = ProjectionContext::FaraStep {
            step,
            action,
        };

        let projector = self.projector_factory.from_profile(profile)?;
        let qstate = projector.project_qstate(&ctx);
        
        if !self.validate_normalization(&qstate, model_id) {
            return None;
        }

        let qstate_node_id = self.write_qstate_to_akg(&qstate, step_node_id, model_id, profile);

        if self.enable_logging {
            info!(
                "[QSTATE8] agent=gaia model={} profile={} amps=[{:.4}, {:.4}, {:.4}, {:.4}, {:.4}, {:.4}, {:.4}, {:.4}]",
                model_id, profile,
                qstate.amps[0], qstate.amps[1], qstate.amps[2], qstate.amps[3],
                qstate.amps[4], qstate.amps[5], qstate.amps[6], qstate.amps[7]
            );
        }

        Some(qstate_node_id)
    }

    /// Encode a chemistry step (ChemLLM, ChemDFM, LlaSMol)
    pub fn encode_after_chemistry_inference(
        &self,
        model_id: &str,
        step_node_id: &str,
        smiles: &str,
        meta: ChemistryMeta,
    ) -> Option<String> {
        let profile = "uum8d_chemistry_step";
        
        let ctx = ProjectionContext::ChemistryStep {
            smiles,
            meta: &meta,
        };

        let projector = self.projector_factory.from_profile(profile)?;
        let qstate = projector.project_qstate(&ctx);
        
        if !self.validate_normalization(&qstate, model_id) {
            return None;
        }

        let qstate_node_id = self.write_qstate_to_akg(&qstate, step_node_id, model_id, profile);

        if self.enable_logging {
            info!(
                "[QSTATE8] agent=gaia model={} profile={} amps=[{:.4}, {:.4}, {:.4}, {:.4}, {:.4}, {:.4}, {:.4}, {:.4}]",
                model_id, profile,
                qstate.amps[0], qstate.amps[1], qstate.amps[2], qstate.amps[3],
                qstate.amps[4], qstate.amps[5], qstate.amps[6], qstate.amps[7]
            );
        }

        Some(qstate_node_id)
    }

    /// Encode a world model step (Cosmos, CWM, UnifoLM)
    pub fn encode_after_world_model_inference(
        &self,
        model_id: &str,
        step_node_id: &str,
        action: &str,
        meta: WorldModelMeta,
    ) -> Option<String> {
        let profile = "uum8d_world_model_step";
        
        let ctx = ProjectionContext::WorldModelStep {
            action,
            meta: &meta,
        };

        let projector = self.projector_factory.from_profile(profile)?;
        let qstate = projector.project_qstate(&ctx);
        
        if !self.validate_normalization(&qstate, model_id) {
            return None;
        }

        let qstate_node_id = self.write_qstate_to_akg(&qstate, step_node_id, model_id, profile);

        if self.enable_logging {
            info!(
                "[QSTATE8] agent=gaia model={} profile={} amps=[{:.4}, {:.4}, {:.4}, {:.4}, {:.4}, {:.4}, {:.4}, {:.4}]",
                model_id, profile,
                qstate.amps[0], qstate.amps[1], qstate.amps[2], qstate.amps[3],
                qstate.amps[4], qstate.amps[5], qstate.amps[6], qstate.amps[7]
            );
        }

        Some(qstate_node_id)
    }

    /// Encode a galaxy/astrophysics step (AstroSage, CAMELS)
    pub fn encode_after_galaxy_inference(
        &self,
        model_id: &str,
        step_node_id: &str,
        query: &str,
        meta: GalaxyMeta,
    ) -> Option<String> {
        let profile = "uum8d_galaxy_step";
        
        let ctx = ProjectionContext::GalaxyStep {
            query,
            meta: &meta,
        };

        let projector = self.projector_factory.from_profile(profile)?;
        let qstate = projector.project_qstate(&ctx);
        
        if !self.validate_normalization(&qstate, model_id) {
            return None;
        }

        let qstate_node_id = self.write_qstate_to_akg(&qstate, step_node_id, model_id, profile);

        if self.enable_logging {
            info!(
                "[QSTATE8] agent=gaia model={} profile={} amps=[{:.4}, {:.4}, {:.4}, {:.4}, {:.4}, {:.4}, {:.4}, {:.4}]",
                model_id, profile,
                qstate.amps[0], qstate.amps[1], qstate.amps[2], qstate.amps[3],
                qstate.amps[4], qstate.amps[5], qstate.amps[6], qstate.amps[7]
            );
        }

        Some(qstate_node_id)
    }
}

// ============================================================================
// TESTS - Actually run encoding and verify AKG nodes exist
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    fn setup_encoder() -> (LiveInferenceEncoder, Arc<InMemoryAkg>) {
        let akg = Arc::new(InMemoryAkg::new());
        let encoder = LiveInferenceEncoder::new(akg.clone());
        (encoder, akg)
    }

    #[test]
    fn test_general_reasoning_actually_encodes() {
        let (encoder, akg) = setup_encoder();
        
        let meta = TurnMeta {
            domain: Some("general".to_string()),
            tool_calls: 0,
            safety_risk: None,
            safety_blocked: false,
            user_rating: None,
            step_index: 0,
            max_steps_hint: None,
        };

        let result = encoder.encode_after_general_inference(
            "llama_core_70b",
            "step_001",
            "assistant",
            "I can help you with that task.",
            meta,
        );

        assert!(result.is_some(), "Encoding should succeed");
        
        // VERIFY AKG HAS THE NODE
        let qstate_nodes = akg.qstate_nodes();
        assert_eq!(qstate_nodes.len(), 1, "Should have 1 QState8 node in AKG");
        
        // Verify amplitudes are present
        let (_, props) = &qstate_nodes[0];
        assert!(props.contains_key("uum:amp0"), "Should have amp0");
        assert!(props.contains_key("uum:amp7"), "Should have amp7");
        assert!(props.contains_key("model_id"), "Should have model_id");
        
        println!("✅ General reasoning actually encoded to AKG");
    }

    #[test]
    fn test_chemistry_actually_encodes() {
        let (encoder, akg) = setup_encoder();
        
        let meta = ChemistryMeta::default();

        let result = encoder.encode_after_chemistry_inference(
            "chemllm_7b_dpo",
            "chem_step_001",
            "CC(=O)OC1=CC=CC=C1C(=O)O", // Aspirin
            meta,
        );

        assert!(result.is_some(), "Encoding should succeed");
        
        let qstate_nodes = akg.qstate_nodes();
        assert_eq!(qstate_nodes.len(), 1, "Should have 1 QState8 node");
        
        println!("✅ Chemistry actually encoded to AKG");
    }

    #[test]
    fn test_galaxy_actually_encodes() {
        let (encoder, akg) = setup_encoder();
        
        let meta = GalaxyMeta::default();

        let result = encoder.encode_after_galaxy_inference(
            "astrosage_8b",
            "galaxy_step_001",
            "What is dark energy?",
            meta,
        );

        assert!(result.is_some(), "Encoding should succeed");
        
        let qstate_nodes = akg.qstate_nodes();
        assert_eq!(qstate_nodes.len(), 1, "Should have 1 QState8 node");
        
        println!("✅ Galaxy actually encoded to AKG");
    }

    #[test]
    fn test_multiple_domains_all_encode() {
        let (encoder, akg) = setup_encoder();
        
        // General
        encoder.encode_after_general_inference(
            "llama_core_70b", "step_1", "assistant", "Response 1",
            TurnMeta::default(),
        );
        
        // Chemistry
        encoder.encode_after_chemistry_inference(
            "chemllm_7b", "step_2", "CCO", ChemistryMeta::default(),
        );
        
        // Galaxy
        encoder.encode_after_galaxy_inference(
            "astrosage_8b", "step_3", "What is a neutron star?",
            GalaxyMeta::default(),
        );

        let qstate_nodes = akg.qstate_nodes();
        assert_eq!(qstate_nodes.len(), 3, "Should have 3 QState8 nodes from 3 domains");
        
        println!("✅ All 3 domains encoded {} nodes to AKG", qstate_nodes.len());
    }

    #[test]
    fn test_normalization_is_valid() {
        let (encoder, akg) = setup_encoder();
        
        encoder.encode_after_general_inference(
            "phi_small", "step_norm", "user", "Test input",
            TurnMeta::default(),
        );

        let qstate_nodes = akg.qstate_nodes();
        let (_, props) = &qstate_nodes[0];
        
        // Extract amplitudes and verify normalization
        let mut amps = [0.0f64; 8];
        for i in 0..8 {
            if let Some(serde_json::Value::Number(n)) = props.get(&format!("uum:amp{}", i)) {
                amps[i] = n.as_f64().unwrap();
            }
        }
        
        let norm_sq: f64 = amps.iter().map(|x| x * x).sum();
        assert!((norm_sq - 1.0).abs() < 0.02, "Norm² should be ~1.0, got {}", norm_sq);
        
        println!("✅ Normalization verified: Σ(amp²) = {:.6}", norm_sq);
    }
}

