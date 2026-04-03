//! GaiaOS AGI Orchestrator - Main entry point
//!
//! This is the "front door" to GaiaOS AGI capabilities.

use gaia_orchestrator::{
    GateChecker,
    DomainRouter,
    DomainExecutor,
};
use std::path::PathBuf;

fn main() {
    env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("info"))
        .init();
    
    println!();
    println!("═══════════════════════════════════════════════════════════════");
    println!("🧠 GAIAOS AGI ORCHESTRATOR");
    println!("═══════════════════════════════════════════════════════════════");
    println!();
    println!("Starting orchestrator service...");
    
    // Load capability gates
    let manifest_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let ttl_path = manifest_dir
        .parent().unwrap()
        .parent().unwrap()
        .join("ontology/gaiaos_validation_instances.ttl");
    
    let gate_checker = match GateChecker::from_ttl(&ttl_path) {
        Ok(gc) => gc,
        Err(e) => {
            eprintln!("Failed to load gates: {e}");
            GateChecker::default()
        }
    };
    
    gate_checker.print_summary();
    
    // Create router and executor
    let _router = DomainRouter::new(gate_checker);
    let _executor = DomainExecutor::new();
    
    println!();
    println!("Orchestrator initialized.");
    println!("In production, this would start an HTTP API server.");
    println!();
    println!("To test, run: cargo run --bin test_orchestrator");
    println!();
}

