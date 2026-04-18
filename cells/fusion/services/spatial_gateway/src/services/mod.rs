//! Services for the Spatial Gateway
//! 
//! Core services:
//! - registry: Cell registration and session management
//! - projector_8d: GeoPose → 8D vQbit projection with LLM classification
//! - coherence: Multi-source coherence computation (DBSCAN + merge)
//! - world_state: Live truth field storage (in-memory cache)
//! - query_engine: Virtue-weighted truth queries
//! - virtue_weights: Domain-specific virtue configurations
//! - subscription: Streaming subscription management

pub mod registry;
pub mod projector_8d;
pub mod coherence;
pub mod cross_scale;
pub mod world_state;
pub mod query_engine;
pub mod virtue_weights;
pub mod subscription;

