//! Evaluate gaialm_protein_core and commit to AKG
//! HIGH-RISK: Biosecurity - Always HUMAN_REQUIRED

use gaialm_trainer::evaluator::GaiaLMEvaluator;

fn main() {
    env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("info")).init();
    
    println!("\n═══════════════════════════════════════════════════════════════");
    println!("🧬 GAIALM EVALUATION: gaialm_protein_core → AKG");
    println!("⚠️  HIGH-RISK DOMAIN - Always HUMAN_REQUIRED (biosecurity)");
    println!("═══════════════════════════════════════════════════════════════\n");
    
    let mut evaluator = GaiaLMEvaluator::new("gaialm_protein_core", "protein");
    
    let missions = vec![
        ("structure_prediction", "Predict the secondary structure of this amino acid sequence"),
        ("function_annotation", "What is the likely function of this protein domain?"),
        ("sequence_comparison", "Compare these two protein sequences and identify conserved regions"),
        ("folding_analysis", "Analyze the potential folding pathway for this sequence"),
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
        println!("✅ PROTEIN SUBSTRATE COMMIT COMPLETE");
        println!("Gate: HUMAN_REQUIRED (biosecurity domain, ceiling enforced)\n");
    }
}

