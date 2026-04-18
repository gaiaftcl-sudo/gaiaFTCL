//! Evaluate gaialm_unified_v1 (GLUE BRAIN) and commit to AKG
//!
//! Low-risk domain: should pass virtue 0.90

use gaialm_trainer::evaluator::GaiaLMEvaluator;
use log::{info, error};

fn main() {
    env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("info"))
        .init();
    
    println!();
    println!("═══════════════════════════════════════════════════════════════");
    println!("🧠 GAIALM EVALUATION: gaialm_unified_v1 (GLUE BRAIN) → AKG");
    println!("═══════════════════════════════════════════════════════════════");
    println!();
    println!("✅ LOW-RISK DOMAIN - Virtue threshold: 0.90");
    println!();
    println!("Testing the coordinator brain's ability to:");
    println!("  • Frame and decompose tasks");
    println!("  • Provide clear explanations");
    println!("  • Reason across domains");
    println!();
    
    // Create evaluator for general reasoning
    let mut evaluator = GaiaLMEvaluator::new(
        "gaialm_unified_v1",
        "general_reasoning"
    );
    
    // Define general reasoning evaluation missions
    let missions = vec![
        ("task_decomposition", "Break down the process of building a house into major phases and sub-tasks"),
        ("explanation", "Explain quantum entanglement to a 10-year-old using everyday analogies"),
        ("argumentation", "Present both sides of the debate on remote work vs office work"),
        ("synthesis", "Given climate change data and economic constraints, propose a balanced approach"),
        ("meta_reasoning", "Describe your reasoning process when solving a complex problem"),
    ];
    
    println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    println!("Running {} general reasoning evaluation missions...", missions.len());
    println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    println!();
    
    let mut total_steps = 0;
    let mut total_qstates = 0;
    
    for (name, prompt) in &missions {
        info!("Running mission: {name}");
        
        match evaluator.evaluate_mission(name, prompt) {
            Ok(results) => {
                println!("{results}");
                total_steps += results.total_steps;
                total_qstates += results.qstates_written;
            }
            Err(e) => {
                error!("Mission {name} failed: {e}");
            }
        }
    }
    
    // Print AKG statistics
    println!();
    let akg_stats = evaluator.akg_stats();
    println!("{akg_stats}");
    
    // Validate AKG
    println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    println!("Validating AKG...");
    println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    
    let errors = evaluator.validate_akg();
    
    if errors.is_empty() {
        println!("✅ AKG VALIDATION: PASSED");
        println!();
        println!("🧠 The glue brain is connected to the substrate!");
    } else {
        println!("❌ AKG VALIDATION: {} ERRORS", errors.len());
        for err in &errors {
            println!("   ❌ {err}");
        }
    }
    
    println!();
    println!("═══════════════════════════════════════════════════════════════");
    println!("📊 GENERAL REASONING EVALUATION SUMMARY");
    println!("═══════════════════════════════════════════════════════════════");
    println!();
    println!("  Model:         gaialm_unified_v1 (GLUE BRAIN)");
    println!("  Missions:      {}", missions.len());
    println!("  Total Steps:   {total_steps}");
    println!("  QState8s:      {total_qstates}");
    println!("  AKG Valid:     {}", if errors.is_empty() { "✅ YES" } else { "❌ NO" });
    println!();
    
    if errors.is_empty() {
        println!("═══════════════════════════════════════════════════════════════");
        println!("✅ GLUE BRAIN SUBSTRATE COMMIT COMPLETE");
        println!("═══════════════════════════════════════════════════════════════");
        println!();
        println!("Expected gate: RESTRICTED (default coordinator brain)");
        println!();
        println!("The orchestrator will now use gaialm_unified_v1 as the");
        println!("default brain for tasks that don't map to specific domains.");
        println!();
        println!("Validation command:");
        println!("  curl -X POST localhost:8802/validate/full \\");
        println!("    -d '{{\"model_id\":\"gaialm_unified_v1\",\"family\":\"general_reasoning\"}}'");
    }
    
    println!();
}

