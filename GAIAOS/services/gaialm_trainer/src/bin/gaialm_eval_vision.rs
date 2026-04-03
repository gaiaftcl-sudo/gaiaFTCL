//! Evaluate gaialm_vision_core and commit to AKG

use gaialm_trainer::evaluator::GaiaLMEvaluator;

fn main() {
    env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("info")).init();
    
    println!("\n═══════════════════════════════════════════════════════════════");
    println!("👁️  GAIALM EVALUATION: gaialm_vision_core → AKG");
    println!("═══════════════════════════════════════════════════════════════\n");
    
    let mut evaluator = GaiaLMEvaluator::new("gaialm_vision_core", "vision");
    
    let missions = vec![
        ("ui_description", "Describe this user interface and identify key interactive elements"),
        ("chart_reading", "Explain the trends shown in this data visualization"),
        ("safety_check", "Identify any warning messages or error dialogs in this screenshot"),
        ("element_location", "Locate the download button in this interface"),
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
        println!("✅ VISION SUBSTRATE COMMIT COMPLETE");
        println!("Expected gate: RESTRICTED\n");
    }
}

