//! Harvest Medical teachers (Meditron, etc.)
//! HIGH-RISK: Medical reasoning - virtue threshold 0.98

use teacher_harvest::{HarvestConfig, HarvestDb, TeacherHarvester};
use std::path::PathBuf;
use log::error;

fn main() {
    env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("info")).init();
    
    println!("\n═══════════════════════════════════════════════════════════════");
    println!("🏥 GAIAOS TEACHER HARVEST: Medical Reasoning");
    println!("⚠️  HIGH-RISK DOMAIN - Virtue threshold: 0.98");
    println!("═══════════════════════════════════════════════════════════════\n");
    
    let manifest_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let registry_path = manifest_dir.parent().unwrap().parent().unwrap()
        .join("config/agi_model_registry.json");
    
    let config = match HarvestConfig::from_registry(&registry_path) {
        Ok(c) => c,
        Err(e) => { error!("Failed to load config: {}", e); return; }
    };
    
    let db_path = manifest_dir.join("harvest_data/medical_harvest.json");
    let db = HarvestDb::new(db_path.to_str().unwrap());
    let mut harvester = TeacherHarvester::new(config, db);
    
    match harvester.harvest_domain("medical") {
        Ok(ids) => println!("✅ Medical harvest complete! Episodes: {}", ids.len()),
        Err(e) => error!("Harvest failed: {}", e),
    }
    
    println!("{}", harvester.db().stats());
    let _ = harvester.save();
    println!("\n🏥 MEDICAL HARVEST COMPLETE\nNext: cargo run --bin train_medical\n");
}

