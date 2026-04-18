//! Harvest Fara-7B teacher model
//!
//! This is the first teacher harvest - proof of concept for the pipeline.

use teacher_harvest::{HarvestConfig, HarvestDb, TeacherHarvester};
use std::path::PathBuf;
use log::{info, error};

fn main() {
    // Initialize logging
    env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("info"))
        .init();
    
    println!();
    println!("═══════════════════════════════════════════════════════════════");
    println!("🎓 GAIAOS TEACHER HARVEST: Fara-7B (Computer Use)");
    println!("═══════════════════════════════════════════════════════════════");
    println!();
    println!("⚠️  This is OFFLINE HARVEST - NOT production runtime");
    println!("    Output goes to HARVEST DB, not AKG");
    println!();
    
    // Load config
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
    
    // Check Fara teacher exists
    if let Some((domain, profile, teacher)) = config.get_teacher("fara_7b_teacher") {
        info!("Found teacher: {} in domain '{}' with profile '{}'", 
            teacher.name, domain, profile);
        info!("Model path: {}", teacher.model_path);
        info!("Status: {}", teacher.status);
        
        if teacher.runtime_allowed {
            error!("❌ VIOLATION: Teacher has runtime_allowed=true!");
            return;
        }
    } else {
        error!("Fara teacher not found in registry!");
        return;
    }
    
    // Initialize harvest DB
    let db_path = manifest_dir.join("harvest_data/fara_harvest.json");
    info!("Harvest DB: {:?}", db_path);
    
    let db = HarvestDb::new(db_path.to_str().unwrap());
    let mut harvester = TeacherHarvester::new(config, db);
    
    // Run harvest
    println!();
    println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    println!("Starting Computer Use domain harvest...");
    println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    println!();
    
    match harvester.harvest_domain("computer_use") {
        Ok(episode_ids) => {
            println!();
            println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
            println!("✅ Harvest complete!");
            println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
            println!();
            println!("Episodes created: {}", episode_ids.len());
            for ep_id in &episode_ids {
                println!("  • {}", ep_id);
            }
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
        Ok(_) => {
            info!("Harvest DB saved to: {:?}", db_path);
        }
        Err(e) => {
            error!("Failed to save harvest DB: {}", e);
        }
    }
    
    println!();
    println!("═══════════════════════════════════════════════════════════════");
    println!("Next steps:");
    println!("  1. Run more missions to increase episode count");
    println!("  2. Validate harvest with: cargo run --bin validate_harvest");
    println!("  3. Distill into gaialm_computer_use_core");
    println!("═══════════════════════════════════════════════════════════════");
    println!();
}

