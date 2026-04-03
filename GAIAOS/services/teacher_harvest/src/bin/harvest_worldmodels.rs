//! Harvest World Model teachers (PAN, Cosmos, etc.)
//! MEDIUM-RISK: Macro cognition, counterfactuals, civilization modeling

use teacher_harvest::{HarvestConfig, HarvestDb, TeacherHarvester};
use std::path::PathBuf;
use log::error;

fn main() {
    env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("info")).init();
    
    println!("\n═══════════════════════════════════════════════════════════════");
    println!("🌍 GAIAOS TEACHER HARVEST: World Models (PAN)");
    println!("═══════════════════════════════════════════════════════════════\n");
    
    let manifest_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let registry_path = manifest_dir.parent().unwrap().parent().unwrap()
        .join("config/agi_model_registry.json");
    
    let config = match HarvestConfig::from_registry(&registry_path) {
        Ok(c) => c,
        Err(e) => { error!("Failed to load config: {}", e); return; }
    };
    
    let db_path = manifest_dir.join("harvest_data/worldmodels_harvest.json");
    let db = HarvestDb::new(db_path.to_str().unwrap());
    let mut harvester = TeacherHarvester::new(config, db);
    
    match harvester.harvest_domain("world_models") {
        Ok(ids) => println!("✅ World Models harvest complete! Episodes: {}", ids.len()),
        Err(e) => error!("Harvest failed: {}", e),
    }
    
    println!("{}", harvester.db().stats());
    let _ = harvester.save();
    println!("\n🌍 WORLD MODELS HARVEST COMPLETE\nNext: cargo run --bin train_worldmodels\n");
}

