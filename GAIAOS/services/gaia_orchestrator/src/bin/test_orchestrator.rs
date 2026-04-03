//! Test the GaiaOS AGI Orchestrator

use gaia_orchestrator::{
    Task, TaskSpec,
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
    println!("🧠 GAIAOS AGI ORCHESTRATOR TEST");
    println!("═══════════════════════════════════════════════════════════════");
    println!();
    
    // Load capability gates
    let manifest_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let ttl_path = manifest_dir
        .parent().unwrap()
        .parent().unwrap()
        .join("ontology/gaiaos_validation_instances.ttl");
    
    println!("Loading capability gates from: {ttl_path:?}");
    
    let gate_checker = match GateChecker::from_ttl(&ttl_path) {
        Ok(gc) => gc,
        Err(e) => {
            eprintln!("Failed to load gates: {e}");
            // Use default empty gates
            GateChecker::default()
        }
    };
    
    gate_checker.print_summary();
    println!();
    
    // Create router and executor
    let router = DomainRouter::new(gate_checker);
    let mut executor = DomainExecutor::new();
    
    // Test cases
    let test_tasks = vec![
        // Should route to Math (FULL autonomy)
        TaskSpec {
            description: "Prove that the square root of 2 is irrational".to_string(),
            ..Default::default()
        },
        
        // Should route to Galaxy (FULL autonomy)
        TaskSpec {
            description: "Explain how dark matter affects galaxy rotation curves".to_string(),
            ..Default::default()
        },
        
        // Should route to Code (RESTRICTED autonomy)
        TaskSpec {
            description: "Refactor this function to be more efficient".to_string(),
            ..Default::default()
        },
        
        // Should route to Chemistry (HUMAN_REQUIRED)
        TaskSpec {
            description: "What are the chemical properties of aspirin?".to_string(),
            ..Default::default()
        },
        
        // Multi-domain: Math + Code
        TaskSpec {
            description: "Write a function to calculate prime factorization".to_string(),
            ..Default::default()
        },
        
        // Should fail: Medical is DISABLED
        TaskSpec {
            description: "What should I do about chest pain symptoms?".to_string(),
            ..Default::default()
        },
    ];
    
    for (i, spec) in test_tasks.iter().enumerate() {
        println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
        println!("📋 TEST TASK {}", i + 1);
        println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
        println!("Description: {}", spec.description);
        println!();
        
        // Create task
        let task = Task::new(spec.clone());
        
        // Route
        println!("🔀 ROUTING:");
        let decisions = router.route(spec);
        
        for decision in &decisions {
            println!("   {} {} → {:?}", 
                decision.gate_status.icon(),
                decision.domain,
                decision.action
            );
        }
        println!();
        
        // Build plan
        let plan = executor.build_plan(&task, decisions.clone());
        
        if plan.blocked {
            println!("🚫 BLOCKED: {}", plan.block_reason.unwrap_or_default());
        } else if plan.requires_human_approval {
            let domains: Vec<_> = plan.domains.iter()
                .filter(|d| d.action == gaia_orchestrator::router::RoutingAction::RequestApproval)
                .map(|d| d.domain.as_str())
                .collect();
            println!("🟠 AWAITING HUMAN APPROVAL for: {domains:?}");
        } else {
            // Execute
            println!("⚡ EXECUTING...");
            let outcome = executor.execute(&task, &plan);
            println!("{outcome}");
        }
        
        println!();
    }
    
    // Print final AKG stats
    println!("{}", executor.akg_stats());
    
    println!();
    println!("═══════════════════════════════════════════════════════════════");
    println!("✅ AGI ORCHESTRATOR TEST COMPLETE");
    println!("═══════════════════════════════════════════════════════════════");
    println!();
}

