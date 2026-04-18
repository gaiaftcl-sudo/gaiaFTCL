//! QFOT-GNN (Quantum Field Operations on Tiles) — Rust implementation surface
//!
//! This module provides:
//! - A bounded, deterministic baseline forecaster (no fabricated observations)
//! - Quantum basis compression (orthonormal projection)
//! - A field-graph in-memory representation built from Arango tile docs + relations
//!
//! Training/backprop is intentionally not enabled by default in this initial rollout.

pub mod compression;
pub mod engine;
pub mod field_graph;
pub mod forecast;
pub mod message_passing;


