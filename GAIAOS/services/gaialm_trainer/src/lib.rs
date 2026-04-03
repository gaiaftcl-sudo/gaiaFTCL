//! GaiaLM Trainer - Distills teacher harvests into GaiaLM behavior
//!
//! This service converts harvested teacher data into GaiaLM weights and behavior.
//! The distilled knowledge then gets committed to the substrate (AKG).
//!
//! ## Pipeline:
//!
//! 1. Load harvest data (teacher episodes + steps + QState8)
//! 2. Create training batches (input → target pairs)
//! 3. Train GaiaLM with:
//!    - Action loss (main supervision)
//!    - Reasoning loss (optional language modeling)
//!    - QState regularizer (FoT-aware virtue alignment)
//! 4. Save checkpoint
//! 5. Update registry with trained model
//!
//! ## Key Principle:
//!
//! Teachers are offline-only. GaiaLM is what runs in production.
//! We're transferring teacher knowledge → GaiaLM → substrate.

pub mod config;
pub mod data;
pub mod objective;
pub mod trainer;
pub mod checkpoint;
pub mod evaluator;

pub use config::TrainConfig;
pub use data::{TrainingBatch, TrainingExample, TrainingDataset, load_fara_harvest};
pub use objective::{DistillationLoss, LossWeights};
pub use trainer::{GaiaLMTrainer, TrainStats, TrainingSummary};
pub use checkpoint::Checkpoint;
pub use evaluator::GaiaLMEvaluator;

