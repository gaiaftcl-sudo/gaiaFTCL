//! GaiaOS AGI Orchestrator
//!
//! The orchestrator is the "front door" to GaiaOS AGI capabilities.
//! It:
//! 1. Classifies incoming tasks into required domains
//! 2. Checks CapabilityGate status for each domain
//! 3. Routes to appropriate GaiaLM cores (or blocks/requests human approval)
//! 4. Writes all steps to the AKG substrate with QState8 encoding
//!
//! ## API Endpoints
//!
//! - `GET  /api/capabilities` - List all capabilities and gate statuses
//! - `POST /api/task` - Submit a new task
//! - `POST /api/task/{id}/execute` - Execute a task
//! - `GET  /api/proposals` - List pending approval proposals
//! - `POST /api/proposals/{id}/approve` - Approve a proposal
//! - `POST /api/proposals/{id}/deny` - Deny a proposal
//! - `GET  /api/history` - List task execution history
//! - `GET  /api/akg/stats` - Get AKG statistics

pub mod task;
pub mod gate;
pub mod router;
pub mod executor;
pub mod api;

pub use task::{Task, TaskSpec, TaskOutcome, DomainRequirement};
pub use gate::{CapabilityGate, GateStatus, GateChecker};
pub use router::{DomainRouter, RoutingDecision, RoutingAction};
pub use executor::{DomainExecutor, ExecutionPlan, ExecutionResult};
pub use api::{GaiaOSConsole, CapabilitiesResponse, TaskSubmitResponse, ApprovalProposal};

