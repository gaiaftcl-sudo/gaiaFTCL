//! Train gaialm_code_core from Code teacher harvests
//!
//! Medium-risk domain: virtue threshold 0.92

use gaialm_trainer::{
    TrainConfig, GaiaLMTrainer, TrainingDataset,
    load_fara_harvest, TrainingSummary,
};
use std::path::PathBuf;
use log::{info, error, warn};

fn main() {
    env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("info"))
        .init();
    
    println!();
    println!("═══════════════════════════════════════════════════════════════");
    println!("💻 GAIALM DISTILLATION: Code → gaialm_code_core");
    println!("═══════════════════════════════════════════════════════════════");
    println!();
    println!("⚡ MEDIUM-RISK DOMAIN - Virtue threshold: 0.92");
    println!("   Safety focus: No exploits, no shell injection");
    println!();
    
    let manifest_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let gaiaos_root = manifest_dir.parent().unwrap().parent().unwrap();
    
    // Configure training for code
    let mut config = TrainConfig::code();
    config.harvest_path = gaiaos_root.join("services/teacher_harvest/harvest_data/code_harvest.json");
    config.checkpoint_dir = gaiaos_root.join("models/gaialm");
    config.epochs = 5;
    config.batch_size = 4;
    
    // Slightly higher QState weight for medium-risk domain
    config.loss_weights.qstate = 0.15;
    
    info!("Loading harvest data from: {:?}", config.harvest_path);
    
    // Load training data
    let examples = match load_fara_harvest(&config.harvest_path) {
        Ok(ex) => ex,
        Err(e) => {
            error!("Failed to load harvest data: {e}");
            println!();
            println!("❌ No harvest data found. Run harvest first:");
            println!("   cargo run --bin harvest_code");
            return;
        }
    };
    
    if examples.is_empty() {
        error!("No training examples found!");
        return;
    }
    
    info!("Loaded {} training examples", examples.len());
    
    // Filter potential exploit-related examples (extra safety)
    let filtered: Vec<_> = examples.into_iter()
        .filter(|ex| {
            // Check for dangerous patterns in input
            let input_lower = ex.input_text.to_lowercase();
            if input_lower.contains("exploit") || 
               input_lower.contains("shell_injection") ||
               input_lower.contains("rm -rf") {
                warn!("Filtering dangerous example: {}", ex.id);
                false
            } else {
                true
            }
        })
        .collect();
    
    info!("After safety filtering: {} examples", filtered.len());
    
    // Create dataset
    let mut dataset = TrainingDataset::new(
        filtered,
        config.batch_size,
        true,
        config.seed,
    );
    
    let stats = dataset.stats();
    println!("{stats}");
    
    // Create trainer
    let mut trainer = GaiaLMTrainer::new(config.clone());
    
    println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    println!("Starting training with security awareness...");
    println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    println!();
    
    // Train
    let start_time = std::time::Instant::now();
    let epoch_stats = trainer.train(&mut dataset);
    let duration = start_time.elapsed();
    
    // Save checkpoint
    println!();
    println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    println!("Saving checkpoint...");
    println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    
    let checkpoint_path = config.checkpoint_dir.clone();
    match trainer.save_checkpoint(&checkpoint_path) {
        Ok(checkpoint) => {
            info!("Checkpoint saved: {:?}", checkpoint.weights_path);
            
            // Update registry
            let registry_path = gaiaos_root.join("config/agi_model_registry.json");
            let update = gaialm_trainer::checkpoint::RegistryUpdate::from_checkpoint(&checkpoint);
            
            if let Err(e) = update.apply_to_registry(&registry_path) {
                error!("Failed to update registry: {e}");
            }
        }
        Err(e) => {
            error!("Failed to save checkpoint: {e}");
        }
    }
    
    // Print summary
    let final_stats = epoch_stats.last().unwrap();
    let summary = TrainingSummary {
        model_id: config.model_id.clone(),
        family: config.family.clone(),
        distilled_from: config.distilled_from.clone(),
        total_epochs: config.epochs,
        final_loss: final_stats.total_loss,
        best_loss: trainer.best_loss(),
        total_examples: dataset.len() * config.epochs as usize,
        total_duration_ms: duration.as_millis() as u64,
        checkpoint_path: Some(checkpoint_path),
    };
    
    println!();
    println!("{summary}");
    
    println!();
    println!("═══════════════════════════════════════════════════════════════");
    println!("✅ CODE DISTILLATION COMPLETE");
    println!("═══════════════════════════════════════════════════════════════");
    println!();
    println!("Next: cargo run --bin gaialm_eval_code");
    println!();
}

