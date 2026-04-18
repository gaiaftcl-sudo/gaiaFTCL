//! Evaluate gaialm_computer_use_core and commit to AKG
//!
//! This is where GaiaLM's behavior becomes substrate knowledge.

use gaialm_trainer::evaluator::GaiaLMEvaluator;
use log::{info, error};

fn main() {
    // Initialize logging
    env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("info"))
        .init();
    
    println!();
    println!("═══════════════════════════════════════════════════════════════");
    println!("🧪 GAIALM EVALUATION: gaialm_computer_use_core → AKG");
    println!("═══════════════════════════════════════════════════════════════");
    println!();
    println!("Running GaiaLM on evaluation missions.");
    println!("Each step writes: Step → Context → QState8 to the AKG.");
    println!();
    println!("This is where GaiaLM's behavior becomes substrate knowledge.");
    println!();
    
    // Create evaluator
    let mut evaluator = GaiaLMEvaluator::new(
        "gaialm_computer_use_core",
        "computer_use"
    );
    
    // Define evaluation missions
    let missions = vec![
        ("web_search", "Open a browser, search for 'quantum computing', and summarize the top result."),
        ("form_fill", "Navigate to a contact form and fill in Name='Test', Email='test@example.com'."),
        ("screenshot", "Take a screenshot and describe the visible UI elements."),
    ];
    
    println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    println!("Running {} evaluation missions...", missions.len());
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
        println!("All steps have:");
        println!("  • step:hasProjectionContext edge");
        println!("  • step:hasQState edge");
        println!("  • Normalized QState8 (Σα² = 1 ± 0.01)");
    } else {
        println!("❌ AKG VALIDATION: {} ERRORS", errors.len());
        for err in &errors {
            println!("   ❌ {err}");
        }
    }
    
    println!();
    println!("═══════════════════════════════════════════════════════════════");
    println!("📊 EVALUATION SUMMARY");
    println!("═══════════════════════════════════════════════════════════════");
    println!();
    println!("  Model:          gaialm_computer_use_core");
    println!("  Missions:       {}", missions.len());
    println!("  Total Steps:    {total_steps}");
    println!("  QState8s:       {total_qstates}");
    println!("  AKG Valid:      {}", if errors.is_empty() { "✅ YES" } else { "❌ NO" });
    println!();
    
    if errors.is_empty() {
        println!("═══════════════════════════════════════════════════════════════");
        println!("✅ SUBSTRATE COMMIT COMPLETE");
        println!("═══════════════════════════════════════════════════════════════");
        println!();
        println!("GaiaLM's behavior is now in the substrate.");
        println!();
        println!("Next steps:");
        println!("  1. Run IQ validation: check wiring, QState8 norm, AKG writes");
        println!("  2. Run OQ validation: latency, error rates");
        println!("  3. Run PQ validation: task success rate, virtue metrics");
        println!("  4. Update CapabilityGate for Capability_ComputerUse");
        println!();
        println!("Example validation command:");
        println!("  curl -X POST localhost:8802/validate/full \\");
        println!("    -d '{{\"model_id\":\"gaialm_computer_use_core\",\"family\":\"computer_use\"}}'");
    } else {
        println!("═══════════════════════════════════════════════════════════════");
        println!("⚠️  FIX VALIDATION ERRORS BEFORE PROCEEDING");
        println!("═══════════════════════════════════════════════════════════════");
    }
    
    println!();
}

