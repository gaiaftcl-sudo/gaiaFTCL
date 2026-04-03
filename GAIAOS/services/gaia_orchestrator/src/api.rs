//! GaiaOS Console API
//!
//! HTTP/JSON API for interacting with the AGI OS:
//! - List capabilities and gate statuses
//! - Submit tasks
//! - Review HUMAN_REQUIRED proposals
//! - Inspect QState8 summaries

use crate::task::{Task, TaskSpec, TaskOutcome};
use crate::gate::GateChecker;
use crate::router::{DomainRouter, RoutingAction};
use crate::executor::DomainExecutor;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use uuid::Uuid;

/// Human approval proposal for HUMAN_REQUIRED domains
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ApprovalProposal {
    pub proposal_id: String,
    pub task_id: String,
    pub capability: String,
    pub autonomy: String,
    pub proposal: ProposalContent,
    pub justification: String,
    pub risk_summary: RiskSummary,
    pub status: ProposalStatus,
    pub created_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProposalContent {
    pub action: String,
    pub detail_level: String,
    pub content_preview: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RiskSummary {
    pub dual_use_terms_detected: bool,
    pub virtue_score: f32,
    pub flags: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum ProposalStatus {
    Pending,
    Approved,
    Modified,
    Denied,
}

/// API response for capabilities listing
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CapabilitiesResponse {
    pub total: usize,
    pub enabled: usize,
    pub capabilities: Vec<CapabilityInfo>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CapabilityInfo {
    pub domain: String,
    pub capability: String,
    pub gate_status: String,
    pub virtue_threshold: f32,
    pub current_virtue: Option<f32>,
    pub is_validated: bool,
    pub can_execute: bool,
}

/// API response for task submission
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TaskSubmitResponse {
    pub task_id: String,
    pub status: String,
    pub routing: Vec<RouteInfo>,
    pub requires_approval: bool,
    pub approval_domains: Vec<String>,
    /// Domains that were suppressed by safety policy (e.g., GeneralReasoning when high-risk detected)
    pub suppressed_domains: Vec<String>,
    /// Safety policy reason if any suppressions occurred
    pub safety_reason: Option<String>,
    pub blocked: bool,
    pub block_reason: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RouteInfo {
    pub domain: String,
    pub gate_status: String,
    pub action: String,
}

/// API response for QState8 summary
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QStateSummary {
    pub task_id: String,
    pub domain: String,
    pub steps: usize,
    pub avg_virtue: f32,
    pub min_virtue: f32,
    pub max_virtue: f32,
    pub qstate_samples: Vec<QStateSample>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QStateSample {
    pub step_id: String,
    pub action: String,
    pub amps: [f32; 8],
    pub virtue_dim: f32,
}

/// GaiaOS Console API server
pub struct GaiaOSConsole {
    gate_checker: Arc<GateChecker>,
    router: Arc<DomainRouter>,
    executor: Arc<Mutex<DomainExecutor>>,
    pending_proposals: Arc<Mutex<HashMap<String, ApprovalProposal>>>,
    task_history: Arc<Mutex<Vec<TaskOutcome>>>,
}

impl GaiaOSConsole {
    pub fn new(gate_checker: GateChecker) -> Self {
        let gc = Arc::new(gate_checker);
        GaiaOSConsole {
            gate_checker: gc.clone(),
            router: Arc::new(DomainRouter::new((*gc).clone())),
            executor: Arc::new(Mutex::new(DomainExecutor::new())),
            pending_proposals: Arc::new(Mutex::new(HashMap::new())),
            task_history: Arc::new(Mutex::new(Vec::new())),
        }
    }
    
    /// GET /api/capabilities - List all capabilities and their gate statuses
    pub fn list_capabilities(&self) -> CapabilitiesResponse {
        let gates = self.gate_checker.all_gates();
        
        let mut capabilities: Vec<CapabilityInfo> = gates.iter()
            .map(|(domain, gate)| {
                CapabilityInfo {
                    domain: domain.clone(),
                    capability: gate.capability.clone(),
                    gate_status: format!("{:?}", gate.status),
                    virtue_threshold: gate.virtue_threshold,
                    current_virtue: gate.current_virtue,
                    is_validated: gate.is_validated(),
                    can_execute: gate.status.allows_autonomous_action(),
                }
            })
            .collect();
        
        // Sort by gate status (Full first)
        capabilities.sort_by_key(|c| match c.gate_status.as_str() {
            "Full" => 0,
            "Restricted" => 1,
            "HumanRequired" => 2,
            _ => 3,
        });
        
        let enabled = capabilities.iter().filter(|c| c.can_execute).count();
        
        CapabilitiesResponse {
            total: capabilities.len(),
            enabled,
            capabilities,
        }
    }
    
    /// POST /api/task - Submit a new task
    /// 
    /// SAFETY POLICY: Uses route_with_safety to enforce high-risk domain deferral
    pub fn submit_task(&self, spec: TaskSpec) -> TaskSubmitResponse {
        let task = Task::new(spec.clone());
        let task_id = task.id.clone();
        
        // Route the task WITH SAFETY POLICY ENFORCEMENT
        let (decisions, suppressed_domains) = self.router.route_with_safety(&spec);
        
        // Build safety reason if suppressions occurred
        let safety_reason = if !suppressed_domains.is_empty() {
            Some(format!(
                "High-risk domain detected; {} must defer (safety policy)",
                suppressed_domains.join(", ")
            ))
        } else {
            None
        };
        
        // Build plan
        let executor = self.executor.lock().unwrap();
        let plan = executor.build_plan(&task, decisions.clone());
        
        // Check if approval needed
        let approval_domains: Vec<String> = plan.domains.iter()
            .filter(|d| d.action == RoutingAction::RequestApproval)
            .map(|d| d.domain.clone())
            .collect();
        
        let requires_approval = !approval_domains.is_empty();
        
        // If approval needed, create proposals
        if requires_approval {
            let mut proposals = self.pending_proposals.lock().unwrap();
            for domain in &approval_domains {
                let proposal = self.create_proposal(&task, domain);
                proposals.insert(proposal.proposal_id.clone(), proposal);
            }
        }
        
        // Build routing info
        let routing: Vec<RouteInfo> = decisions.iter()
            .map(|d| RouteInfo {
                domain: d.domain.clone(),
                gate_status: format!("{:?}", d.gate_status),
                action: format!("{:?}", d.action),
            })
            .collect();
        
        TaskSubmitResponse {
            task_id,
            status: if plan.blocked { 
                "blocked".to_string() 
            } else if requires_approval { 
                "awaiting_approval".to_string() 
            } else { 
                "ready".to_string() 
            },
            routing,
            requires_approval,
            approval_domains,
            suppressed_domains,
            safety_reason,
            blocked: plan.blocked,
            block_reason: plan.block_reason,
        }
    }
    
    /// POST /api/task/{id}/execute - Execute a task (after approval if needed)
    pub fn execute_task(&self, spec: TaskSpec, approved_domains: Vec<String>) -> TaskOutcome {
        // Merge approvals into spec
        let mut spec_with_approvals = spec.clone();
        spec_with_approvals.human_approval_granted = approved_domains;
        
        let task = Task::new(spec_with_approvals.clone());
        let decisions = self.router.route(&spec_with_approvals);
        
        let mut executor = self.executor.lock().unwrap();
        let plan = executor.build_plan(&task, decisions);
        
        let outcome = executor.execute(&task, &plan);
        
        // Store in history
        let mut history = self.task_history.lock().unwrap();
        history.push(outcome.clone());
        
        outcome
    }
    
    /// GET /api/proposals - List pending approval proposals
    pub fn list_proposals(&self) -> Vec<ApprovalProposal> {
        let proposals = self.pending_proposals.lock().unwrap();
        proposals.values()
            .filter(|p| p.status == ProposalStatus::Pending)
            .cloned()
            .collect()
    }
    
    /// POST /api/proposals/{id}/approve - Approve a proposal
    pub fn approve_proposal(&self, proposal_id: &str) -> Option<ApprovalProposal> {
        let mut proposals = self.pending_proposals.lock().unwrap();
        if let Some(proposal) = proposals.get_mut(proposal_id) {
            proposal.status = ProposalStatus::Approved;
            Some(proposal.clone())
        } else {
            None
        }
    }
    
    /// POST /api/proposals/{id}/deny - Deny a proposal
    pub fn deny_proposal(&self, proposal_id: &str) -> Option<ApprovalProposal> {
        let mut proposals = self.pending_proposals.lock().unwrap();
        if let Some(proposal) = proposals.get_mut(proposal_id) {
            proposal.status = ProposalStatus::Denied;
            Some(proposal.clone())
        } else {
            None
        }
    }
    
    /// GET /api/history - List task execution history
    pub fn list_history(&self) -> Vec<TaskOutcome> {
        let history = self.task_history.lock().unwrap();
        history.clone()
    }
    
    /// GET /api/akg/stats - Get AKG statistics
    pub fn akg_stats(&self) -> String {
        let executor = self.executor.lock().unwrap();
        executor.akg_stats()
    }
    
    /// Create an approval proposal for a domain
    fn create_proposal(&self, task: &Task, domain: &str) -> ApprovalProposal {
        let gate = self.gate_checker.get_gate(domain);
        let virtue = gate.and_then(|g| g.current_virtue).unwrap_or(0.0);
        
        ApprovalProposal {
            proposal_id: format!("prop_{}", &Uuid::new_v4().simple().to_string()[..12]),
            task_id: task.id.clone(),
            capability: domain.to_string(),
            autonomy: "human_required".to_string(),
            proposal: ProposalContent {
                action: "execute_domain_reasoning".to_string(),
                detail_level: "coarse".to_string(),
                content_preview: task.spec.description.chars().take(100).collect(),
            },
            justification: format!(
                "Task requires {domain} domain which is gated as HUMAN_REQUIRED. Virtue score: {virtue:.2}"
            ),
            risk_summary: RiskSummary {
                dual_use_terms_detected: self.check_dual_use(&task.spec.description),
                virtue_score: virtue,
                flags: self.get_risk_flags(domain, &task.spec.description),
            },
            status: ProposalStatus::Pending,
            created_at: chrono::Utc::now().to_rfc3339(),
        }
    }
    
    /// Check for dual-use terms in description
    fn check_dual_use(&self, description: &str) -> bool {
        let desc_lower = description.to_lowercase();
        let dual_use_terms = [
            "synthesis", "precursor", "scale up", "weaponize",
            "bypass", "undetect", "harmful", "toxic", "lethal"
        ];
        dual_use_terms.iter().any(|term| desc_lower.contains(term))
    }
    
    /// Get risk flags for a domain task
    fn get_risk_flags(&self, domain: &str, description: &str) -> Vec<String> {
        let mut flags = Vec::new();
        let desc_lower = description.to_lowercase();
        
        match domain {
            "chemistry" => {
                if desc_lower.contains("synthesis") { flags.push("synthesis_mentioned".to_string()); }
                if desc_lower.contains("toxic") { flags.push("toxicity_related".to_string()); }
            }
            "medical" => {
                if desc_lower.contains("diagnos") { flags.push("diagnosis_request".to_string()); }
                if desc_lower.contains("treatment") { flags.push("treatment_request".to_string()); }
            }
            "protein" => {
                if desc_lower.contains("design") { flags.push("protein_design".to_string()); }
            }
            _ => {}
        }
        
        flags
    }
}

// GateChecker is now Clone via derive

/// API endpoint definitions (for documentation/code generation)
pub mod endpoints {
    pub const LIST_CAPABILITIES: &str = "GET  /api/capabilities";
    pub const SUBMIT_TASK: &str = "POST /api/task";
    pub const EXECUTE_TASK: &str = "POST /api/task/{id}/execute";
    pub const LIST_PROPOSALS: &str = "GET  /api/proposals";
    pub const APPROVE_PROPOSAL: &str = "POST /api/proposals/{id}/approve";
    pub const DENY_PROPOSAL: &str = "POST /api/proposals/{id}/deny";
    pub const LIST_HISTORY: &str = "GET  /api/history";
    pub const AKG_STATS: &str = "GET  /api/akg/stats";
}

