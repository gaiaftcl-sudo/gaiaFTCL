//! Evaluate gaialm_galaxy_core and commit to AKG
//!
//! Very low-risk domain: pure science

use gaialm_trainer::evaluator::GaiaLMEvaluator;
use log::{info, error};

fn main() {
    env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("info"))
        .init();
    
    println!();
    println!("═══════════════════════════════════════════════════════════════");
    println!("🌌 GAIALM EVALUATION: gaialm_galaxy_core → AKG");
    println!("═══════════════════════════════════════════════════════════════");
    println!();
    println!("✅ VERY LOW-RISK DOMAIN - Virtue threshold: 0.85");
    println!("   Pure science: cosmology, astrophysics, galaxy formation");
    println!();
    
    // Create evaluator for galaxy
    let mut evaluator = GaiaLMEvaluator::new(
        "gaialm_galaxy_core",
        "galaxy"
    );
    
    // Define galaxy evaluation missions
    let missions = vec![
        ("galaxy_formation", "Describe the hierarchical model of galaxy formation including dark matter halos"),
        ("stellar_evolution", "Explain the lifecycle of a massive star from birth to supernova"),
        ("cosmology_basics", "What is the cosmic microwave background and why is it important?"),
        ("dark_matter", "Summarize the evidence for dark matter in galaxy rotation curves"),
    ];
    
    println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    println!("Running {} galaxy evaluation missions...", missions.len());
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
        println!("🌌 Gaia has acquired cosmic perspective!");
    } else {
        println!("❌ AKG VALIDATION: {} ERRORS", errors.len());
        for err in &errors {
            println!("   ❌ {err}");
        }
    }
    
    println!();
    println!("═══════════════════════════════════════════════════════════════");
    println!("📊 GALAXY EVALUATION SUMMARY");
    println!("═══════════════════════════════════════════════════════════════");
    println!();
    println!("  Model:         gaialm_galaxy_core");
    println!("  Missions:      {}", missions.len());
    println!("  Total Steps:   {total_steps}");
    println!("  QState8s:      {total_qstates}");
    println!("  AKG Valid:     {}", if errors.is_empty() { "✅ YES" } else { "❌ NO" });
    println!();
    
    if errors.is_empty() {
        println!("═══════════════════════════════════════════════════════════════");
        println!("✅ GALAXY SUBSTRATE COMMIT COMPLETE");
        println!("═══════════════════════════════════════════════════════════════");
        println!();
        println!("🌌 Expected gate: FULL (very low-risk, pure science domain)");
        println!();
        println!("Validation command:");
        println!("  curl -X POST localhost:8802/validate/full \\");
        println!("    -d '{{\"model_id\":\"gaialm_galaxy_core\",\"family\":\"galaxy\"}}'");
    }
    
    println!();
}

