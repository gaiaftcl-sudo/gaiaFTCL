//! Task specification and outcomes

use serde::{Deserialize, Serialize};
use uuid::Uuid;
use chrono::{DateTime, Utc};

/// A task submitted to the GaiaOS orchestrator
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Task {
    pub id: String,
    pub spec: TaskSpec,
    pub created_at: DateTime<Utc>,
    pub status: TaskStatus,
}

impl Task {
    pub fn new(spec: TaskSpec) -> Self {
        Task {
            id: format!("task_{}", Uuid::new_v4().simple()),
            spec,
            created_at: Utc::now(),
            status: TaskStatus::Pending,
        }
    }
}

/// Task specification
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TaskSpec {
    /// Human-readable description of what to do
    pub description: String,
    
    /// Optional explicit domain hints (if known)
    pub domain_hints: Vec<String>,
    
    /// Priority level (1-10, higher = more urgent)
    pub priority: u8,
    
    /// Maximum execution time in seconds
    pub timeout_seconds: Option<u64>,
    
    /// Whether human approval is pre-granted for certain actions
    pub human_approval_granted: Vec<String>,
    
    /// Context from previous tasks
    pub context: Option<TaskContext>,
}

impl Default for TaskSpec {
    fn default() -> Self {
        TaskSpec {
            description: String::new(),
            domain_hints: Vec::new(),
            priority: 5,
            timeout_seconds: Some(300),
            human_approval_granted: Vec::new(),
            context: None,
        }
    }
}

/// Context from previous task executions
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TaskContext {
    pub previous_task_ids: Vec<String>,
    pub accumulated_knowledge: Vec<String>,
}

/// Current status of a task
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum TaskStatus {
    Pending,
    ClassifyingDomains,
    CheckingGates,
    AwaitingHumanApproval { domains: Vec<String> },
    Executing { domain: String },
    Completed,
    Failed { reason: String },
    Blocked { reason: String },
}

/// Domain requirement for a task
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DomainRequirement {
    pub domain: String,
    pub confidence: f32,
    pub reason: String,
    pub is_primary: bool,
}

/// Outcome of task execution
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TaskOutcome {
    pub task_id: String,
    pub status: TaskStatus,
    pub domains_used: Vec<String>,
    pub steps_executed: usize,
    pub qstates_written: usize,
    pub results: Vec<DomainResult>,
    pub duration_ms: u64,
    pub requires_followup: bool,
}

/// Result from a single domain execution
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DomainResult {
    pub domain: String,
    pub success: bool,
    pub output: String,
    pub steps: usize,
    pub gate_status_used: String,
    pub virtue_score: f32,
}

impl std::fmt::Display for TaskOutcome {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        writeln!(f, "═══════════════════════════════════════════")?;
        writeln!(f, "📋 TASK OUTCOME")?;
        writeln!(f, "═══════════════════════════════════════════")?;
        writeln!(f, "  Task ID:     {}", self.task_id)?;
        writeln!(f, "  Status:      {:?}", self.status)?;
        writeln!(f, "  Domains:     {:?}", self.domains_used)?;
        writeln!(f, "  Steps:       {}", self.steps_executed)?;
        writeln!(f, "  QState8s:    {}", self.qstates_written)?;
        writeln!(f, "  Duration:    {}ms", self.duration_ms)?;
        writeln!(f, "═══════════════════════════════════════════")
    }
}

