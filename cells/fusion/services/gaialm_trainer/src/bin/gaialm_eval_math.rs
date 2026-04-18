//! Evaluate gaialm_math_core and commit to AKG
//!
//! Low-risk domain: should easily pass virtue 0.90

use gaialm_trainer::evaluator::GaiaLMEvaluator;
use log::{info, error};

fn main() {
    env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("info"))
        .init();
    
    println!();
    println!("═══════════════════════════════════════════════════════════════");
    println!("🧮 GAIALM EVALUATION: gaialm_math_core → AKG");
    println!("═══════════════════════════════════════════════════════════════");
    println!();
    println!("✅ LOW-RISK DOMAIN - Virtue threshold: 0.90");
    println!();
    
    // Create evaluator for math
    let mut evaluator = GaiaLMEvaluator::new(
        "gaialm_math_core",
        "math"
    );
    
    // Define math evaluation missions
    let missions = vec![
        ("proof_verification", "Prove that the sum of two even numbers is always even. Show step-by-step reasoning."),
        ("calculus_integration", "Find the integral of x^2 * e^x dx using integration by parts."),
        ("linear_algebra", "Solve the system of equations: 2x + 3y = 7, x - y = 1"),
        ("number_theory", "Prove that there are infinitely many prime numbers."),
    ];
    
    println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    println!("Running {} math evaluation missions...", missions.len());
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
    } else {
        println!("❌ AKG VALIDATION: {} ERRORS", errors.len());
        for err in &errors {
            println!("   ❌ {err}");
        }
    }
    
    println!();
    println!("═══════════════════════════════════════════════════════════════");
    println!("📊 MATH EVALUATION SUMMARY");
    println!("═══════════════════════════════════════════════════════════════");
    println!();
    println!("  Model:         gaialm_math_core");
    println!("  Missions:      {}", missions.len());
    println!("  Total Steps:   {total_steps}");
    println!("  QState8s:      {total_qstates}");
    println!("  AKG Valid:     {}", if errors.is_empty() { "✅ YES" } else { "❌ NO" });
    println!();
    
    if errors.is_empty() {
        println!("═══════════════════════════════════════════════════════════════");
        println!("✅ MATH SUBSTRATE COMMIT COMPLETE");
        println!("═══════════════════════════════════════════════════════════════");
        println!();
        println!("Expected gate: RESTRICTED or FULL (low-risk domain)");
        println!();
        println!("Validation command:");
        println!("  curl -X POST localhost:8802/validate/full \\");
        println!("    -d '{{\"model_id\":\"gaialm_math_core\",\"family\":\"math\"}}'");
    }
    
    println!();
}

