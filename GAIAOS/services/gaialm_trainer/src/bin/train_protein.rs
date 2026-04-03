//! Train gaialm_protein_core from Protein teacher harvests
//! HIGH-RISK: Biosecurity - virtue threshold 0.97

use gaialm_trainer::{TrainConfig, GaiaLMTrainer, TrainingDataset, load_fara_harvest};
use std::path::PathBuf;
use log::{info, error};

fn main() {
    env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("info")).init();
    
    println!("\n═══════════════════════════════════════════════════════════════");
    println!("🧬 GAIALM DISTILLATION: Protein → gaialm_protein_core");
    println!("⚠️  HIGH-RISK DOMAIN - Virtue threshold: 0.97 (biosecurity)");
    println!("═══════════════════════════════════════════════════════════════\n");
    
    let manifest_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let gaiaos_root = manifest_dir.parent().unwrap().parent().unwrap();
    
    let mut config = TrainConfig::protein();
    config.harvest_path = gaiaos_root.join("services/teacher_harvest/harvest_data/protein_harvest.json");
    config.checkpoint_dir = gaiaos_root.join("models/gaialm");
    config.epochs = 5;
    
    let examples = match load_fara_harvest(&config.harvest_path) {
        Ok(ex) => ex,
        Err(e) => { error!("Failed to load harvest: {e}"); return; }
    };
    
    let mut dataset = TrainingDataset::new(examples, config.batch_size, true, config.seed);
    println!("{}", dataset.stats());
    
    let mut trainer = GaiaLMTrainer::new(config.clone());
    let _ = trainer.train(&mut dataset);
    
    if let Ok(cp) = trainer.save_checkpoint(&config.checkpoint_dir) {
        info!("Checkpoint saved: {:?}", cp.weights_path);
    }
    
    println!("\n🧬 PROTEIN DISTILLATION COMPLETE\nNext: cargo run --bin gaialm_eval_protein\n");
}

