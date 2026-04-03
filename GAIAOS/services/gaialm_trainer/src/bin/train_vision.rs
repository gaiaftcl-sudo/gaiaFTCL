//! Train gaialm_vision_core from Vision teacher harvests

use gaialm_trainer::{TrainConfig, GaiaLMTrainer, TrainingDataset, load_fara_harvest};
use std::path::PathBuf;
use log::{info, error};

fn main() {
    env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("info")).init();
    
    println!("\n═══════════════════════════════════════════════════════════════");
    println!("👁️  GAIALM DISTILLATION: Vision → gaialm_vision_core");
    println!("═══════════════════════════════════════════════════════════════\n");
    
    let manifest_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let gaiaos_root = manifest_dir.parent().unwrap().parent().unwrap();
    
    let mut config = TrainConfig::vision();
    config.harvest_path = gaiaos_root.join("services/teacher_harvest/harvest_data/vision_harvest.json");
    config.checkpoint_dir = gaiaos_root.join("models/gaialm");
    config.epochs = 5;
    
    let examples = match load_fara_harvest(&config.harvest_path) {
        Ok(ex) => ex,
        Err(e) => { error!("Failed to load harvest: {e}"); return; }
    };
    
    let mut dataset = TrainingDataset::new(examples, config.batch_size, true, config.seed);
    println!("{}", dataset.stats());
    
    let mut trainer = GaiaLMTrainer::new(config.clone());
    let _start = std::time::Instant::now();
    let _ = trainer.train(&mut dataset);
    
    let checkpoint_path = config.checkpoint_dir.clone();
    if let Ok(cp) = trainer.save_checkpoint(&checkpoint_path) {
        info!("Checkpoint saved: {:?}", cp.weights_path);
    }
    
    println!("\n👁️  VISION DISTILLATION COMPLETE\nNext: cargo run --bin gaialm_eval_vision\n");
}

