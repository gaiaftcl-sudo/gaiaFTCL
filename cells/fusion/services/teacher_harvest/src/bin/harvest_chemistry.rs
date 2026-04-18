//! Harvest Chemistry teachers (ChemLLM, ChemDFM, LlaSMol)
//!
//! High-risk domain: virtue threshold 0.97

use teacher_harvest::{HarvestConfig, HarvestDb, TeacherHarvester};
use std::path::PathBuf;
use log::{info, error};

fn main() {
    env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("info"))
        .init();
    
    println!();
    println!("═══════════════════════════════════════════════════════════════");
    println!("🧪 GAIAOS TEACHER HARVEST: Chemistry");
    println!("═══════════════════════════════════════════════════════════════");
    println!();
    println!("⚠️  HIGH-RISK DOMAIN - Virtue threshold: 0.97");
    println!("    Teachers: ChemLLM-2B, ChemLLM-7B, ChemDFM-13B, LlaSMol-7B");
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
    
    // Check chemistry teachers exist
    let chem_domain = config.teachers_for_domain("chemistry");
    if chem_domain.is_none() {
        error!("Chemistry domain not found in registry!");
        return;
    }
    
    let chem = chem_domain.unwrap();
    println!("📚 Chemistry Teachers Found:");
    for teacher in &chem.teachers {
        let status_icon = match teacher.status.as_str() {
            "downloaded" => "⬇️",
            "downloading" => "⏳",
            _ => "⚪",
        };
        println!("   {} {} ({})", status_icon, teacher.id, teacher.status);
    }
    println!();
    
    // Initialize harvest DB
    let db_path = manifest_dir.join("harvest_data/chemistry_harvest.json");
    info!("Harvest DB: {:?}", db_path);
    
    let db = HarvestDb::new(db_path.to_str().unwrap());
    let mut harvester = TeacherHarvester::new(config, db);
    
    // Run harvest
    println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    println!("Starting Chemistry domain harvest...");
    println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    println!();
    
    match harvester.harvest_domain("chemistry") {
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
    println!("  1. Validate harvest: cargo run --bin validate_harvest");
    println!("  2. Train: cargo run --bin train_chemistry");
    println!("  3. Commit: cargo run --bin gaialm_eval_chemistry");
    println!("═══════════════════════════════════════════════════════════════");
    println!();
}

