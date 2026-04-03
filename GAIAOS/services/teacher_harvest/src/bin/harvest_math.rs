//! Harvest Math teachers (DeepSeek-Math)
//!
//! Low-risk domain: virtue threshold 0.90

use teacher_harvest::{HarvestConfig, HarvestDb, TeacherHarvester};
use std::path::PathBuf;
use log::{info, error};

fn main() {
    env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("info"))
        .init();
    
    println!();
    println!("═══════════════════════════════════════════════════════════════");
    println!("🧮 GAIAOS TEACHER HARVEST: Mathematics");
    println!("═══════════════════════════════════════════════════════════════");
    println!();
    println!("✅ LOW-RISK DOMAIN - Virtue threshold: 0.90");
    println!("   Teachers: DeepSeek-Math-7B");
    println!();
    
    let manifest_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let registry_path = manifest_dir
        .parent().unwrap()
        .parent().unwrap()
        .join("config/agi_model_registry.json");
    
    info!("Loading registry from: {:?}", registry_path);
    
    let config = match HarvestConfig::from_registry(&registry_path) {
        Ok(c) => c,
        Err(e) => {
            error!("Failed to load config: {}", e);
            return;
        }
    };
    
    // Check math teachers exist
    let math_domain = config.teachers_for_domain("math");
    if math_domain.is_none() {
        error!("Math domain not found in registry!");
        return;
    }
    
    let math = math_domain.unwrap();
    println!("📚 Math Teachers Found:");
    for teacher in &math.teachers {
        println!("   • {} ({})", teacher.id, teacher.status);
    }
    println!();
    
    // Initialize harvest DB
    let db_path = manifest_dir.join("harvest_data/math_harvest.json");
    info!("Harvest DB: {:?}", db_path);
    
    let db = HarvestDb::new(db_path.to_str().unwrap());
    let mut harvester = TeacherHarvester::new(config, db);
    
    // Run harvest
    println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    println!("Starting Math domain harvest...");
    println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    println!();
    
    match harvester.harvest_domain("math") {
        Ok(episode_ids) => {
            println!();
            println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
            println!("✅ Harvest complete!");
            println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
            println!();
            println!("Episodes created: {}", episode_ids.len());
        }
        Err(e) => {
            error!("Harvest failed: {}", e);
        }
    }
    
    // Print stats
    let stats = harvester.db().stats();
    println!();
    println!("{}", stats);
    
    // Save database
    match harvester.save() {
        Ok(_) => info!("Harvest DB saved"),
        Err(e) => error!("Failed to save harvest DB: {}", e),
    }
    
    println!();
    println!("═══════════════════════════════════════════════════════════════");
    println!("Next: cargo run --bin train_math");
    println!("═══════════════════════════════════════════════════════════════");
}

