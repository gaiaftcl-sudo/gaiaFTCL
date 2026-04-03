//! Evaluate gaialm_med_core and commit to AKG
//! HIGH-RISK: Always HUMAN_REQUIRED

use gaialm_trainer::evaluator::GaiaLMEvaluator;

fn main() {
    env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("info")).init();
    
    println!("\n═══════════════════════════════════════════════════════════════");
    println!("🏥 GAIALM EVALUATION: gaialm_med_core → AKG");
    println!("⚠️  HIGH-RISK DOMAIN - Always HUMAN_REQUIRED");
    println!("═══════════════════════════════════════════════════════════════\n");
    
    let mut evaluator = GaiaLMEvaluator::new("gaialm_med_core", "medical");
    
    let missions = vec![
        ("symptom_triage", "Categorize the urgency of these symptoms for a clinician"),
        ("differential", "List possible differential diagnoses for this presentation"),
        ("guideline_lookup", "What do current guidelines recommend for this condition?"),
        ("drug_interaction", "Check for potential interactions between these medications"),
    ];
    
    let mut _total_steps = 0;
    for (name, prompt) in &missions {
        if let Ok(r) = evaluator.evaluate_mission(name, prompt) {
            println!("{}", r);
            _total_steps += r.total_steps;
        }
    }
    
    let errors = evaluator.validate_akg();
    println!("\n{}", evaluator.akg_stats());
    
    if errors.is_empty() {
        println!("✅ MEDICAL SUBSTRATE COMMIT COMPLETE");
        println!("Gate: HUMAN_REQUIRED (high-risk domain, ceiling enforced)\n");
    }
}

