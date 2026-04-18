//! Teacher Harvest Pipeline
//!
//! This service harvests knowledge from teacher models (external LLMs)
//! and stores it in the HARVEST DB for later distillation into GaiaLM.
//!
//! **CRITICAL**: This service NEVER touches GaiaOS production runtime.
//! Teachers are offline-only. Their output goes to harvest_db, not AKG.
//!
//! ## Pipeline Flow:
//!
//! 1. Read teacher list from `config/agi_model_registry.json`
//! 2. Filter: role == "teacher" && runtime_allowed == false
//! 3. For each teacher:
//!    - Spin up inference backend (vLLM, etc.)
//!    - Run missions/tasks
//!    - For each step:
//!      - Build ProjectionContext
//!      - Call projector → QState8
//!      - Write to HARVEST DB
//!
//! ## Output:
//!
//! - `harvest_episodes` - Task-level records
//! - `harvest_steps` - Step-level records with raw I/O
//! - `harvest_qstates` - QState8 vectors per step

pub mod config;
pub mod db;
pub mod harvester;
pub mod mission;
pub mod projector_bridge;

pub use config::HarvestConfig;
pub use db::{HarvestDb, HarvestEpisode, HarvestStep, HarvestQState};
pub use harvester::TeacherHarvester;
pub use mission::Mission;

