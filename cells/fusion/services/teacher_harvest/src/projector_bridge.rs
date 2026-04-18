//! Bridge between harvest pipeline and UUM8D projectors
//!
//! Converts raw teacher outputs into QState8 using the correct projector.

use uum8d::{
    QState8, ProjectionContext, ProjectorFactory,
    TurnMeta, VisionMeta, ProteinMeta, MathMeta, MedicalMeta, CodeMeta,
    FaraStep, ComputerUseAction, ChemistryMeta, WorldModelMeta, GalaxyMeta,
};

/// Bridge for projecting teacher outputs to QState8
pub struct ProjectorBridge {
    factory: ProjectorFactory,
}

impl ProjectorBridge {
    pub fn new() -> Self {
        ProjectorBridge {
            factory: ProjectorFactory::new(),
        }
    }
    
    /// Project based on profile name and domain-specific data
    pub fn project(&self, profile: &str, context: &ProjectionContext) -> QState8 {
        if let Some(projector) = self.factory.from_profile(profile) {
            projector.project_qstate(context)
        } else {
            // Fallback to general reasoning
            if let Some(projector) = self.factory.from_profile("uum8d_general_reasoning") {
                projector.project_qstate(context)
            } else {
                // Ultimate fallback: uniform superposition
                QState8::from_scores([1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0])
            }
        }
    }
    
    /// Project a Fara/Computer Use step
    pub fn project_fara_step(
        &self,
        thought: &str,
        step_index: u32,
        action_type: &str,
        x: i32,
        y: i32,
        text: Option<&str>,
        url: Option<&str>,
    ) -> QState8 {
        let fara_step = FaraStep {
            thought,
            step_index,
        };
        
        let action = match action_type {
            "click" | "left_click" => ComputerUseAction::LeftClick { x, y },
            "mouse_move" => ComputerUseAction::MouseMove { x, y },
            "scroll" => ComputerUseAction::Scroll { dx: 0, dy: y },
            "type" => ComputerUseAction::Type { text: text.unwrap_or("") },
            "key" => ComputerUseAction::Key { key: text.unwrap_or("") },
            "navigate" | "visit_url" => ComputerUseAction::VisitUrl { url: url.unwrap_or("") },
            "search" | "web_search" => ComputerUseAction::WebSearch { query: text.unwrap_or("") },
            "wait" => ComputerUseAction::Wait { ms: 1000 },
            "terminate" | "done" => ComputerUseAction::Terminate { reason: None },
            _ => ComputerUseAction::Wait { ms: 100 },
        };
        
        let ctx = ProjectionContext::FaraStep {
            step: &fara_step,
            action: &action,
        };
        
        self.project("uum8d_fara_step", &ctx)
    }
    
    /// Project a general reasoning step
    pub fn project_general_turn(
        &self,
        role: &str,
        text: &str,
        tool_calls: u32,
        step_index: u32,
    ) -> QState8 {
        let meta = TurnMeta {
            domain: None,
            tool_calls,
            safety_risk: None,
            safety_blocked: false,
            user_rating: None,
            step_index,
            max_steps_hint: None,
        };
        
        let ctx = ProjectionContext::GeneralTurn {
            role,
            text,
            meta: &meta,
        };
        
        self.project("uum8d_general_reasoning", &ctx)
    }
    
    /// Project a chemistry step
    pub fn project_chemistry_step(
        &self,
        smiles: &str,
        step_index: u32,
    ) -> QState8 {
        let meta = ChemistryMeta {
            atom_count: smiles.len() as u32 / 2,
            molecular_weight: 100.0,
            toxicity_score: None,
            reactivity_hazard: None,
            synthesis_feasibility: None,
            novelty_score: None,
            predicted_yield: None,
            environmental_impact: None,
            confidence: Some(0.8),
            step_index,
        };
        
        let ctx = ProjectionContext::ChemistryStep {
            smiles,
            meta: &meta,
        };
        
        self.project("uum8d_chemistry_step", &ctx)
    }
    
    /// Project a medical step
    pub fn project_medical_step(
        &self,
        context: &str,
        recommendation: &str,
        acuity: f32,
        step_index: u32,
    ) -> QState8 {
        let meta = MedicalMeta {
            acuity,
            risk_score: 0.3,
            guideline_alignment: 0.8,
            uncertainty: 0.2,
            recommends_referral: false,
            step_index,
        };
        
        let ctx = ProjectionContext::MedicalStep {
            context,
            recommendation,
            meta: &meta,
        };
        
        self.project("uum8d_medical_step", &ctx)
    }
    
    /// Project a math step
    pub fn project_math_step(
        &self,
        problem: &str,
        solution: &str,
        step_index: u32,
    ) -> QState8 {
        let meta = MathMeta {
            difficulty: 0.5,
            uses_formal_proof: false,
            uses_diagram: false,
            correctness: Some(0.9),
            scratch_tokens: solution.len() as u32,
            step_index,
        };
        
        let ctx = ProjectionContext::MathStep {
            problem,
            solution,
            meta: &meta,
        };
        
        self.project("uum8d_math_step", &ctx)
    }
    
    /// Project a code step
    pub fn project_code_step(
        &self,
        diff_summary: &str,
        loc_delta: i32,
        files_touched: u32,
        step_index: u32,
    ) -> QState8 {
        let meta = CodeMeta {
            loc_delta,
            files_touched,
            tests_run: 0,
            tests_passed: 0,
            security_warnings: 0,
            perf_impact_est: 0.0,
            step_index,
        };
        
        let ctx = ProjectionContext::CodeStep {
            diff_summary,
            meta: &meta,
        };
        
        self.project("uum8d_code_step", &ctx)
    }
    
    /// Project a galaxy/astrophysics step
    pub fn project_galaxy_step(
        &self,
        query: &str,
        step_index: u32,
    ) -> QState8 {
        let meta = GalaxyMeta {
            domain: Some("cosmology".to_string()),
            speculation_level: Some(0.3),
            observational_support: Some(0.7),
            temporal_scale_years: Some(1e9),
            multi_messenger_data: None,
            peer_review_score: Some(0.8),
            step_index,
        };
        
        let ctx = ProjectionContext::GalaxyStep {
            query,
            meta: &meta,
        };
        
        self.project("uum8d_galaxy_step", &ctx)
    }
    
    /// Project a world model step
    pub fn project_world_model_step(
        &self,
        action: &str,
        horizon_steps: u32,
        step_index: u32,
    ) -> QState8 {
        let meta = WorldModelMeta {
            simulation_type: Some("video_generation".to_string()),
            physics_fidelity: Some(0.8),
            temporal_consistency: Some(0.9),
            num_objects: Some(5),
            prediction_accuracy: Some(0.7),
            sim2real_score: Some(0.6),
            harm_potential: Some(0.1),
            confidence: Some(0.8),
            horizon_steps,
            step_index,
        };
        
        let ctx = ProjectionContext::WorldModelStep {
            action,
            meta: &meta,
        };
        
        self.project("uum8d_world_model_step", &ctx)
    }
    
    /// Project a vision step
    pub fn project_vision_step(
        &self,
        prompt: &str,
        num_regions: u32,
        step_index: u32,
    ) -> QState8 {
        let meta = VisionMeta {
            num_regions,
            ocr_chars: 0,
            ui_like: true,
            nsfw_risk: None,
            step_index,
        };
        
        let ctx = ProjectionContext::VisionStep {
            prompt,
            meta: &meta,
        };
        
        self.project("uum8d_vision_step", &ctx)
    }
    
    /// Project a protein step
    pub fn project_protein_step(
        &self,
        sequence: &str,
        step_index: u32,
    ) -> QState8 {
        let meta = ProteinMeta {
            seq_len: sequence.len() as u32,
            novelty_score: 0.5,
            stability_score: 0.7,
            active_site_conf: 0.6,
            ethics_risk: 0.1,
            step_index,
        };
        
        let ctx = ProjectionContext::ProteinStep {
            sequence,
            meta: &meta,
        };
        
        self.project("uum8d_protein_step", &ctx)
    }
}

impl Default for ProjectorBridge {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_fara_projection() {
        let bridge = ProjectorBridge::new();
        
        let qstate = bridge.project_fara_step(
            "I need to click the search button",
            0,
            "click",
            100, 200,
            None,
            None,
        );
        
        // Verify normalized
        let norm_sq: f32 = qstate.amps.iter().map(|a| a * a).sum();
        assert!((norm_sq - 1.0).abs() < 0.01, "QState8 not normalized: {}", norm_sq);
    }
    
    #[test]
    fn test_chemistry_projection() {
        let bridge = ProjectorBridge::new();
        
        let qstate = bridge.project_chemistry_step(
            "CC(=O)OC1=CC=CC=C1C(=O)O", // Aspirin
            0,
        );
        
        let norm_sq: f32 = qstate.amps.iter().map(|a| a * a).sum();
        assert!((norm_sq - 1.0).abs() < 0.01);
    }
    
    #[test]
    fn test_all_projectors_work() {
        let bridge = ProjectorBridge::new();
        
        // Test each domain produces valid QState8
        let tests = vec![
            bridge.project_general_turn("user", "Hello", 0, 0),
            bridge.project_fara_step("thinking", 0, "click", 0, 0, None, None),
            bridge.project_chemistry_step("CCO", 0),
            bridge.project_medical_step("fever", "rest", 0.5, 0),
            bridge.project_math_step("2+2", "4", 0),
            bridge.project_code_step("fix bug", 10, 1, 0),
            bridge.project_galaxy_step("dark matter query", 0),
            bridge.project_world_model_step("move forward", 5, 0),
            bridge.project_vision_step("describe image", 3, 0),
            bridge.project_protein_step("MVLSPADKTN", 0),
        ];
        
        for (i, qstate) in tests.iter().enumerate() {
            let norm_sq: f32 = qstate.amps.iter().map(|a| a * a).sum();
            assert!(
                (norm_sq - 1.0).abs() < 0.01,
                "Test {} failed: norm_sq = {}",
                i,
                norm_sq
            );
        }
    }
}
