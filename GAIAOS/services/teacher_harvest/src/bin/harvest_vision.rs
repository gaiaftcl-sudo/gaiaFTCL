//! Harvest Vision teachers (Qwen-VL, Pixtral, InternVL, etc.)
//! MEDIUM-RISK: Vision understanding for UI, charts, safety warnings

use teacher_harvest::{HarvestConfig, HarvestDb, TeacherHarvester};
use std::path::PathBuf;
use log::error;

fn main() {
    env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("info")).init();
    
    println!("\n═══════════════════════════════════════════════════════════════");
    println!("👁️  GAIAOS TEACHER HARVEST: Vision Understanding");
    println!("═══════════════════════════════════════════════════════════════\n");
    
    let manifest_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let registry_path = manifest_dir.parent().unwrap().parent().unwrap()
        .join("config/agi_model_registry.json");
    
    let config = match HarvestConfig::from_registry(&registry_path) {
        Ok(c) => c,
        Err(e) => { error!("Failed to load config: {}", e); return; }
    };
    
    let db_path = manifest_dir.join("harvest_data/vision_harvest.json");
    let db = HarvestDb::new(db_path.to_str().unwrap());
    let mut harvester = TeacherHarvester::new(config, db);
    
    match harvester.harvest_domain("vision") {
        Ok(ids) => println!("✅ Vision harvest complete! Episodes: {}", ids.len()),
        Err(e) => error!("Harvest failed: {}", e),
    }
    
    println!("{}", harvester.db().stats());
    let _ = harvester.save();
    println!("\n👁️  VISION HARVEST COMPLETE\nNext: cargo run --bin train_vision\n");
}

