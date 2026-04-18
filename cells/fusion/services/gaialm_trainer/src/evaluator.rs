//! GaiaLM evaluation - runs trained model and commits to AKG

use teacher_harvest::projector_bridge::ProjectorBridge;
use uum8d::{
    InMemoryAkg, encode_complete_step, ProjectionContext, FaraStep, ComputerUseAction,
};
use log::{info, warn};
use std::collections::HashMap;
use anyhow::Result;

/// GaiaLM evaluator - runs the model and writes to AKG
pub struct GaiaLMEvaluator {
    model_id: String,
    family: String,
    projector: ProjectorBridge,
    akg: InMemoryAkg,
}

impl GaiaLMEvaluator {
    pub fn new(model_id: &str, family: &str) -> Self {
        GaiaLMEvaluator {
            model_id: model_id.to_string(),
            family: family.to_string(),
            projector: ProjectorBridge::new(),
            akg: InMemoryAkg::new(),
        }
    }
    
    /// Run evaluation on a mission and commit to AKG
    pub fn evaluate_mission(&mut self, mission_name: &str, task_prompt: &str) -> Result<EvalResults> {
        info!("Evaluating mission: {} with model: {}", mission_name, self.model_id);
        
        let mut results = EvalResults {
            mission_name: mission_name.to_string(),
            model_id: self.model_id.clone(),
            steps: Vec::new(),
            total_steps: 0,
            successful_steps: 0,
            qstates_written: 0,
        };
        
        // Simulate running the GaiaLM model on the task
        // In real impl, this calls the actual GaiaLM inference
        let simulated_steps = self.simulate_gaialm_run(task_prompt);
        results.total_steps = simulated_steps.len();
        
        for (idx, step) in simulated_steps.iter().enumerate() {
            // Build projection context for this step
            let fara_step = FaraStep {
                thought: &step.thought,
                step_index: idx as u32,
            };
            
            let action = self.parse_action(&step.action_type, &step.action_params);
            
            // Project to QState8
            let ctx = ProjectionContext::FaraStep {
                step: &fara_step,
                action: &action,
            };
            
            let qstate = self.projector.project("uum8d_fara_step", &ctx);
            
            // Write to AKG
            let step_type = format!("{}Step", self.family_to_step_type());
            let context_type = format!("{}Context", self.family_to_step_type());
            
            match encode_complete_step(
                &mut self.akg,
                &step_type,
                "gaia_agent",
                &self.model_id,
                &context_type,
                HashMap::new(),
                &qstate,
            ) {
                Ok((step_id, ctx_id, qstate_id)) => {
                    info!(
                        "[AKG] Step {} → Context {} → QState8 {} [amps: {:.3}, {:.3}, {:.3}, {:.3}, {:.3}, {:.3}, {:.3}, {:.3}]",
                        step_id.as_str(), ctx_id.as_str(), qstate_id.as_str(),
                        qstate.amps[0], qstate.amps[1], qstate.amps[2], qstate.amps[3],
                        qstate.amps[4], qstate.amps[5], qstate.amps[6], qstate.amps[7]
                    );
                    
                    results.steps.push(EvalStep {
                        step_id: step_id.0,
                        action: step.action_type.clone(),
                        qstate: qstate.amps,
                        success: true,
                    });
                    results.successful_steps += 1;
                    results.qstates_written += 1;
                }
                Err(e) => {
                    warn!("Failed to write step to AKG: {e:?}");
                    results.steps.push(EvalStep {
                        step_id: "failed".to_string(),
                        action: step.action_type.clone(),
                        qstate: qstate.amps,
                        success: false,
                    });
                }
            }
        }
        
        Ok(results)
    }
    
    /// Get AKG statistics
    pub fn akg_stats(&self) -> AkgStats {
        AkgStats {
            total_steps: self.akg.steps.len(),
            total_contexts: self.akg.contexts.len(),
            total_qstates: self.akg.qstates.len(),
            total_edges: self.akg.edges.len(),
        }
    }
    
    /// Validate all AKG nodes
    pub fn validate_akg(&self) -> Vec<String> {
        let mut errors = Vec::new();
        
        for step_id in self.akg.steps.keys() {
            if let Err(step_errors) = self.akg.validate_step(step_id) {
                errors.extend(step_errors);
            }
        }
        
        // Check QState8 normalization
        for (qs_id, qstate) in &self.akg.qstates {
            if qstate.norm_error > 0.01 {
                errors.push(format!(
                    "QState8 {} not normalized: error={:.4}",
                    qs_id.as_str(), qstate.norm_error
                ));
            }
        }
        
        errors
    }
    
    fn family_to_step_type(&self) -> &str {
        match self.family.as_str() {
            "computer_use" => "Fara",
            "medical" => "Medical",
            "math" => "Math",
            "code" => "Code",
            "chemistry" => "Chemistry",
            "galaxy" => "Galaxy",
            "world_models" => "WorldModel",
            "vision" => "Vision",
            "protein" => "Protein",
            _ => "General",
        }
    }
    
    fn parse_action<'a>(&self, action_type: &str, params: &'a serde_json::Value) -> ComputerUseAction<'a> {
        match action_type {
            "click" | "left_click" => ComputerUseAction::LeftClick {
                x: params.get("x").and_then(|v| v.as_i64()).unwrap_or(0) as i32,
                y: params.get("y").and_then(|v| v.as_i64()).unwrap_or(0) as i32,
            },
            "type" => ComputerUseAction::Type {
                text: params.get("text").and_then(|v| v.as_str()).unwrap_or(""),
            },
            "navigate" => ComputerUseAction::VisitUrl {
                url: params.get("url").and_then(|v| v.as_str()).unwrap_or(""),
            },
            "scroll" => ComputerUseAction::Scroll {
                dx: 0,
                dy: params.get("dy").and_then(|v| v.as_i64()).unwrap_or(100) as i32,
            },
            "wait" => ComputerUseAction::Wait { ms: 1000 },
            "terminate" => ComputerUseAction::Terminate { reason: None },
            _ => ComputerUseAction::Wait { ms: 100 },
        }
    }
    
    /// Simulate GaiaLM running a task
    fn simulate_gaialm_run(&self, task_prompt: &str) -> Vec<SimulatedGaiaStep> {
        // In real impl, this calls the actual GaiaLM model
        vec![
            SimulatedGaiaStep {
                thought: format!("Analyzing task: {task_prompt}"),
                action_type: "navigate".to_string(),
                action_params: serde_json::json!({"url": "https://example.com"}),
            },
            SimulatedGaiaStep {
                thought: "Looking for search input".to_string(),
                action_type: "click".to_string(),
                action_params: serde_json::json!({"x": 200, "y": 100}),
            },
            SimulatedGaiaStep {
                thought: "Typing search query".to_string(),
                action_type: "type".to_string(),
                action_params: serde_json::json!({"text": "query"}),
            },
            SimulatedGaiaStep {
                thought: "Task completed".to_string(),
                action_type: "terminate".to_string(),
                action_params: serde_json::json!({}),
            },
        ]
    }
}

struct SimulatedGaiaStep {
    thought: String,
    action_type: String,
    action_params: serde_json::Value,
}

#[derive(Debug, Clone)]
pub struct EvalResults {
    pub mission_name: String,
    pub model_id: String,
    pub steps: Vec<EvalStep>,
    pub total_steps: usize,
    pub successful_steps: usize,
    pub qstates_written: usize,
}

#[derive(Debug, Clone)]
pub struct EvalStep {
    pub step_id: String,
    pub action: String,
    pub qstate: [f32; 8],
    pub success: bool,
}

#[derive(Debug, Clone)]
pub struct AkgStats {
    pub total_steps: usize,
    pub total_contexts: usize,
    pub total_qstates: usize,
    pub total_edges: usize,
}

impl std::fmt::Display for EvalResults {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        writeln!(f, "═══════════════════════════════════════════")?;
        writeln!(f, "📊 EVALUATION RESULTS")?;
        writeln!(f, "═══════════════════════════════════════════")?;
        writeln!(f, "  Mission:       {}", self.mission_name)?;
        writeln!(f, "  Model:         {}", self.model_id)?;
        writeln!(f, "  Total Steps:   {}", self.total_steps)?;
        writeln!(f, "  Successful:    {}", self.successful_steps)?;
        writeln!(f, "  QStates:       {}", self.qstates_written)?;
        writeln!(f)?;
        writeln!(f, "  Steps:")?;
        for step in &self.steps {
            let status = if step.success { "✅" } else { "❌" };
            writeln!(f, "    {} {} [{}]", status, step.action, step.step_id)?;
        }
        writeln!(f, "═══════════════════════════════════════════")?;
        Ok(())
    }
}

impl std::fmt::Display for AkgStats {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        writeln!(f, "═══════════════════════════════════════════")?;
        writeln!(f, "📊 AKG STATISTICS")?;
        writeln!(f, "═══════════════════════════════════════════")?;
        writeln!(f, "  Steps:     {}", self.total_steps)?;
        writeln!(f, "  Contexts:  {}", self.total_contexts)?;
        writeln!(f, "  QState8s:  {}", self.total_qstates)?;
        writeln!(f, "  Edges:     {}", self.total_edges)?;
        writeln!(f, "═══════════════════════════════════════════")?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_evaluator_run() {
        let mut evaluator = GaiaLMEvaluator::new("gaialm_computer_use_core", "computer_use");
        
        let results = evaluator.evaluate_mission(
            "test_mission",
            "Search for cats on the web"
        ).unwrap();
        
        assert!(results.total_steps > 0);
        assert_eq!(results.successful_steps, results.total_steps);
        
        // Check AKG was populated
        let stats = evaluator.akg_stats();
        assert_eq!(stats.total_steps, results.total_steps);
        assert_eq!(stats.total_qstates, results.qstates_written);
        
        // Validate AKG
        let errors = evaluator.validate_akg();
        assert!(errors.is_empty(), "AKG validation errors: {:?}", errors);
    }
}

