//! Domain executor - runs tasks through GaiaLM cores and writes to AKG

use crate::task::{Task, TaskSpec, TaskOutcome, TaskStatus, DomainResult};
use crate::gate::GateStatus;
use crate::router::{RoutingDecision, RoutingAction};
use uum8d::QState8;
use uum8d::akg_writer::{InMemoryAkg, NodeId, StepNode, ContextNode, QState8Node};
// Projector factory - in production, used for live projections
#[allow(unused_imports)]
use uum8d::factory::ProjectorFactory;
use serde::{Deserialize, Serialize};
use uuid::Uuid;
use log::info;
use std::time::Instant;
use std::collections::HashMap;

/// Execution plan for a task
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExecutionPlan {
    pub task_id: String,
    pub domains: Vec<PlannedDomain>,
    pub requires_human_approval: bool,
    pub blocked: bool,
    pub block_reason: Option<String>,
}

/// A domain planned for execution
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PlannedDomain {
    pub domain: String,
    pub gate_status: GateStatus,
    pub action: RoutingAction,
    pub model_id: String,
}

/// Result of executing a domain
#[derive(Debug, Clone)]
pub struct ExecutionResult {
    pub domain: String,
    pub success: bool,
    pub steps: Vec<ExecutedStep>,
    pub output: String,
    pub virtue_score: f32,
}

/// A single executed step
#[derive(Debug, Clone)]
pub struct ExecutedStep {
    pub step_id: String,
    pub action: String,
    pub qstate: QState8,
}

/// Domain executor
pub struct DomainExecutor {
    // Projector factory for creating domain-specific UUM projectors (reserved for Phase 2)
    #[allow(dead_code)]
    projector_factory: ProjectorFactory,
    akg: InMemoryAkg,
    step_count: usize,
    context_count: usize,
    qstate_count: usize,
    edge_count: usize,
}

impl DomainExecutor {
    pub fn new() -> Self {
        DomainExecutor {
            projector_factory: ProjectorFactory::new(),
            akg: InMemoryAkg::new(),
            step_count: 0,
            context_count: 0,
            qstate_count: 0,
            edge_count: 0,
        }
    }
    
    /// Build execution plan from routing decisions
    pub fn build_plan(&self, task: &Task, decisions: Vec<RoutingDecision>) -> ExecutionPlan {
        let mut domains = Vec::new();
        let mut requires_human_approval = false;
        let mut blocked = false;
        let mut block_reason = None;
        
        for decision in decisions {
            if decision.action == RoutingAction::Block {
                blocked = true;
                block_reason = Some(decision.reason.clone());
            }
            
            if decision.action == RoutingAction::RequestApproval {
                requires_human_approval = true;
            }
            
            let model_id = Self::domain_to_model(&decision.domain);
            
            domains.push(PlannedDomain {
                domain: decision.domain,
                gate_status: decision.gate_status,
                action: decision.action,
                model_id,
            });
        }
        
        ExecutionPlan {
            task_id: task.id.clone(),
            domains,
            requires_human_approval,
            blocked,
            block_reason,
        }
    }
    
    /// Map domain to GaiaLM model ID
    fn domain_to_model(domain: &str) -> String {
        match domain {
            "computer_use" => "gaialm_computer_use_core",
            "math" => "gaialm_math_core",
            "code" => "gaialm_code_core",
            "galaxy" => "gaialm_galaxy_core",
            "chemistry" => "gaialm_chem_core",
            "medical" => "gaialm_med_core",
            "protein" => "gaialm_protein_core",
            "vision" => "gaialm_vision_core",
            "world_models" => "gaialm_worldmodel_core",
            "general_reasoning" => "gaialm_unified_v1",
            _ => "gaialm_unified_v1",
        }.to_string()
    }
    
    /// Map domain to projector profile
    fn domain_to_projector(&self, domain: &str) -> &str {
        match domain {
            "computer_use" => "uum8d_fara_step",
            "math" => "uum8d_math_step",
            "code" => "uum8d_code_step",
            "galaxy" => "uum8d_galaxy_step",
            "chemistry" => "uum8d_chemistry_step",
            "medical" => "uum8d_medical_step",
            "protein" => "uum8d_protein_step",
            "vision" => "uum8d_vision_step",
            "world_models" => "uum8d_world_model_step",
            _ => "uum8d_general_reasoning",
        }
    }
    
    /// Execute a task according to plan
    pub fn execute(&mut self, task: &Task, plan: &ExecutionPlan) -> TaskOutcome {
        let start_time = Instant::now();
        
        if plan.blocked {
            return TaskOutcome {
                task_id: task.id.clone(),
                status: TaskStatus::Blocked { 
                    reason: plan.block_reason.clone().unwrap_or_default() 
                },
                domains_used: vec![],
                steps_executed: 0,
                qstates_written: 0,
                results: vec![],
                duration_ms: start_time.elapsed().as_millis() as u64,
                requires_followup: false,
            };
        }
        
        if plan.requires_human_approval {
            let domains_needing_approval: Vec<_> = plan.domains.iter()
                .filter(|d| d.action == RoutingAction::RequestApproval)
                .map(|d| d.domain.clone())
                .collect();
            
            return TaskOutcome {
                task_id: task.id.clone(),
                status: TaskStatus::AwaitingHumanApproval { domains: domains_needing_approval },
                domains_used: vec![],
                steps_executed: 0,
                qstates_written: 0,
                results: vec![],
                duration_ms: start_time.elapsed().as_millis() as u64,
                requires_followup: true,
            };
        }
        
        // Execute each domain
        let mut results = Vec::new();
        let mut total_steps = 0;
        let mut total_qstates = 0;
        let mut domains_used = Vec::new();
        
        for planned in &plan.domains {
            if planned.action == RoutingAction::Skip {
                continue;
            }
            
            info!("Executing domain: {} with model: {}", planned.domain, planned.model_id);
            
            let result = self.execute_domain(&task.spec, planned);
            
            total_steps += result.steps.len();
            total_qstates += result.steps.len(); // Each step produces a QState8
            domains_used.push(planned.domain.clone());
            
            // Write to AKG
            for step in &result.steps {
                self.write_step_to_akg(&planned.domain, &planned.model_id, step);
            }
            
            results.push(DomainResult {
                domain: planned.domain.clone(),
                success: result.success,
                output: result.output.clone(),
                steps: result.steps.len(),
                gate_status_used: format!("{:?}", planned.gate_status),
                virtue_score: result.virtue_score,
            });
        }
        
        TaskOutcome {
            task_id: task.id.clone(),
            status: TaskStatus::Completed,
            domains_used,
            steps_executed: total_steps,
            qstates_written: total_qstates,
            results,
            duration_ms: start_time.elapsed().as_millis() as u64,
            requires_followup: false,
        }
    }
    
    /// Execute a single domain
    fn execute_domain(&self, spec: &TaskSpec, planned: &PlannedDomain) -> ExecutionResult {
        // Simulate domain execution (in production, call actual GaiaLM)
        let num_steps = match planned.domain.as_str() {
            "math" => 4,
            "code" => 5,
            "galaxy" => 3,
            "computer_use" => 4,
            "chemistry" => 4,
            _ => 3,
        };
        
        let _projector_profile = self.domain_to_projector(&planned.domain);
        // In production, projector would be used here for real QState8 generation
        // let projector = self.projector_factory.from_profile(projector_profile);
        
        let mut steps = Vec::new();
        let mut total_virtue = 0.0;
        
        for i in 0..num_steps {
            let step_id = format!("step_{}", &Uuid::new_v4().simple().to_string()[..12]);
            
            // Generate QState8 directly using default context approach
            // In production, this would be driven by actual model outputs
            let qstate = self.generate_domain_qstate(&planned.domain, i);
            
            // Track virtue (amp[2] in most projectors)
            total_virtue += qstate.amps[2];
            
            let action = match i {
                0 => "analyze",
                1 => "reason",
                2 => "synthesize",
                _ => "conclude",
            };
            
            steps.push(ExecutedStep {
                step_id,
                action: action.to_string(),
                qstate,
            });
        }
        
        let avg_virtue = if steps.is_empty() { 0.0 } else { total_virtue / steps.len() as f32 };
        
        ExecutionResult {
            domain: planned.domain.clone(),
            success: true,
            steps,
            output: format!("Completed {} reasoning on: {}", planned.domain, spec.description),
            virtue_score: avg_virtue,
        }
    }
    
    /// Generate a QState8 for a domain step
    fn generate_domain_qstate(&self, domain: &str, step_index: usize) -> QState8 {
        // Generate scores based on domain characteristics
        let base_scores: [f32; 8] = match domain {
            "math" => [0.8, 0.9, 0.85, 0.7, 0.6, 0.75, 0.8, 0.7],
            "code" => [0.75, 0.85, 0.8, 0.65, 0.7, 0.8, 0.75, 0.65],
            "galaxy" => [0.9, 0.85, 0.95, 0.8, 0.75, 0.9, 0.85, 0.8],
            "chemistry" => [0.6, 0.7, 0.3, 0.5, 0.4, 0.6, 0.5, 0.4], // Lower virtue for high-risk
            "computer_use" => [0.8, 0.75, 0.85, 0.7, 0.8, 0.75, 0.7, 0.65],
            _ => [0.7, 0.7, 0.7, 0.7, 0.7, 0.7, 0.7, 0.7],
        };
        
        // Add slight variation based on step
        let step_factor = 1.0 + (step_index as f32 * 0.02);
        let varied_scores: [f32; 8] = std::array::from_fn(|i| {
            (base_scores[i] * step_factor).min(1.0)
        });
        
        QState8::from_scores(varied_scores)
    }
    
    /// Write a step to the AKG
    fn write_step_to_akg(&mut self, domain: &str, model_id: &str, step: &ExecutedStep) {
        let step_id = NodeId::new("step");
        let context_id = NodeId::new("ctx");
        
        // Create step node
        let step_node = StepNode {
            id: step_id.clone(),
            step_type: format!("{domain}Step"),
            agent_id: "gaia".to_string(),
            model_id: model_id.to_string(),
            timestamp: chrono::Utc::now().timestamp_millis() as u64,
            perception_id: None,
            context_id: Some(context_id.clone()),
            qstate_id: None, // Will be set after qstate creation
        };
        
        // Create context node
        let mut metadata = HashMap::new();
        metadata.insert("domain".to_string(), domain.to_string());
        metadata.insert("action".to_string(), step.action.clone());
        
        let context_node = ContextNode {
            id: context_id.clone(),
            context_type: format!("{domain}Context"),
            metadata,
        };
        
        // Create QState8 node
        let qstate_node = QState8Node::from_qstate(&step.qstate);
        
        // Store in AKG
        self.akg.steps.insert(step_id.clone(), step_node);
        self.akg.contexts.insert(context_id.clone(), context_node);
        self.akg.qstates.insert(qstate_node.id.clone(), qstate_node);
        
        self.step_count += 1;
        self.context_count += 1;
        self.qstate_count += 1;
        self.edge_count += 2; // step→context, step→qstate
        
        info!("[AKG] {} → {} ({})", step_id.as_str(), domain, step.action);
    }
    
    /// Get AKG statistics
    pub fn akg_stats(&self) -> String {
        format!(
            "═══════════════════════════════════════════\n\
             📊 AKG STATISTICS\n\
             ═══════════════════════════════════════════\n\
             Steps:     {}\n\
             Contexts:  {}\n\
             QState8s:  {}\n\
             Edges:     {}\n\
             ═══════════════════════════════════════════",
            self.step_count,
            self.context_count,
            self.qstate_count,
            self.edge_count
        )
    }
}

impl Default for DomainExecutor {
    fn default() -> Self {
        Self::new()
    }
}

