//! Harvest General Reasoning teachers (LLaMA, Gemma, Mistral, Phi, etc.)
//!
//! This is the "glue brain" - the default capability for:
//! - Task decomposition
//! - Cross-domain coordination
//! - General explanation and reasoning
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
    println!("🧠 GAIAOS TEACHER HARVEST: General Reasoning (GLUE BRAIN)");
    println!("═══════════════════════════════════════════════════════════════");
    println!();
    println!("✅ LOW-RISK DOMAIN - Virtue threshold: 0.90");
    println!("   Teachers: LLaMA, Gemma, Mistral, Phi, DeepSeek-R1, Kimi");
    println!();
    println!("Purpose: Task decomposition, cross-domain coordination,");
    println!("         general explanation and reasoning");
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
    
    // Check general reasoning teachers exist
    let general_domain = config.teachers_for_domain("general_reasoning");
    if general_domain.is_none() {
        error!("General reasoning domain not found in registry!");
        return;
    }
    
    let general = general_domain.unwrap();
    println!("📚 General Reasoning Teachers Found:");
    for teacher in &general.teachers {
        println!("   • {} ({})", teacher.id, teacher.status);
    }
    println!();
    
    // Initialize harvest DB
    let db_path = manifest_dir.join("harvest_data/general_harvest.json");
    info!("Harvest DB: {:?}", db_path);
    
    let db = HarvestDb::new(db_path.to_str().unwrap());
    let mut harvester = TeacherHarvester::new(config, db);
    
    // Run harvest
    println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    println!("Starting General Reasoning harvest...");
    println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    println!();
    
    match harvester.harvest_domain("general_reasoning") {
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
    println!("🧠 GLUE BRAIN HARVEST COMPLETE");
    println!("═══════════════════════════════════════════════════════════════");
    println!();
    println!("Next: cargo run --bin train_general");
    println!();
}

