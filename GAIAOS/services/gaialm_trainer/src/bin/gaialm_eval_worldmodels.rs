//! Evaluate gaialm_worldmodel_core and commit to AKG

use gaialm_trainer::evaluator::GaiaLMEvaluator;

fn main() {
    env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("info")).init();
    
    println!("\n═══════════════════════════════════════════════════════════════");
    println!("🌍 GAIALM EVALUATION: gaialm_worldmodel_core → AKG");
    println!("═══════════════════════════════════════════════════════════════\n");
    
    let mut evaluator = GaiaLMEvaluator::new("gaialm_worldmodel_core", "world_models");
    
    let missions = vec![
        ("policy_simulation", "Simulate the 10-year impact of universal basic income on housing stability"),
        ("intervention_comparison", "Compare interventions A and B for reducing child mortality under budget constraints"),
        ("second_order_effects", "Identify non-obvious second-order effects of widespread AI adoption"),
        ("counterfactual", "What would have happened if renewable energy investment doubled in 2010?"),
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
        println!("✅ WORLD MODELS SUBSTRATE COMMIT COMPLETE");
        println!("Expected gate: RESTRICTED\n");
    }
}

