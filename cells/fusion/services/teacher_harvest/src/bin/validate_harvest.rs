//! Validate harvest database integrity

use teacher_harvest::HarvestDb;
use std::path::PathBuf;
use log::{info, error};

fn main() {
    // Initialize logging
    env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("info"))
        .init();
    
    println!();
    println!("═══════════════════════════════════════════════════════════════");
    println!("🔍 HARVEST DATABASE VALIDATOR");
    println!("═══════════════════════════════════════════════════════════════");
    println!();
    
    let manifest_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let db_path = manifest_dir.join("harvest_data/fara_harvest.json");
    
    info!("Loading harvest DB from: {:?}", db_path);
    
    let db = match HarvestDb::load(db_path.to_str().unwrap()) {
        Ok(db) => db,
        Err(e) => {
            error!("Failed to load harvest DB: {}", e);
            return;
        }
    };
    
    // Print stats
    let stats = db.stats();
    println!("{}", stats);
    
    // Validation checks
    let mut errors = Vec::new();
    let mut warnings = Vec::new();
    
    // Check 1: All episodes have steps
    println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    println!("Check 1: Episodes have steps");
    println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    
    for (ep_id, _episode) in &db.episodes {
        let steps = db.steps_for_episode(ep_id);
        if steps.is_empty() {
            errors.push(format!("Episode {} has no steps", ep_id));
            println!("  ❌ {} - NO STEPS", ep_id);
        } else {
            println!("  ✅ {} - {} steps", ep_id, steps.len());
        }
    }
    println!();
    
    // Check 2: All steps have QState8
    println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    println!("Check 2: Steps have QState8");
    println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    
    let mut steps_with_qstate = 0;
    let mut steps_without_qstate = 0;
    
    for (step_id, _step) in &db.steps {
        if db.qstate_for_step(step_id).is_some() {
            steps_with_qstate += 1;
        } else {
            steps_without_qstate += 1;
            warnings.push(format!("Step {} has no QState8", step_id));
        }
    }
    
    if steps_without_qstate > 0 {
        println!("  ⚠️  {} steps without QState8", steps_without_qstate);
    }
    println!("  ✅ {} steps with QState8", steps_with_qstate);
    println!();
    
    // Check 3: QState8 normalization
    println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    println!("Check 3: QState8 normalization (Σα² = 1 ± 0.01)");
    println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    
    let mut normalized = 0;
    let mut not_normalized = 0;
    
    for (qs_id, qstate) in &db.qstates {
        if qstate.is_normalized(0.01) {
            normalized += 1;
        } else {
            not_normalized += 1;
            let amps = qstate.amps();
            let norm_sq: f32 = amps.iter().map(|a| a * a).sum();
            errors.push(format!(
                "QState8 {} not normalized: Σα² = {:.4} (error: {:.4})",
                qs_id, norm_sq, qstate.norm_error
            ));
        }
    }
    
    if not_normalized > 0 {
        println!("  ❌ {} QState8s NOT normalized", not_normalized);
    }
    println!("  ✅ {} QState8s properly normalized", normalized);
    println!();
    
    // Check 4: Teacher runtime_allowed = false (sanity)
    println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    println!("Check 4: All harvested from teachers (not runtime models)");
    println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    
    let teacher_ids: std::collections::HashSet<_> = db.qstates.values()
        .map(|q| q.teacher_model_id.as_str())
        .collect();
    
    for teacher_id in &teacher_ids {
        if teacher_id.ends_with("_teacher") {
            println!("  ✅ {} (teacher)", teacher_id);
        } else if teacher_id.starts_with("gaialm_") {
            errors.push(format!("VIOLATION: Harvested from runtime model: {}", teacher_id));
            println!("  ❌ {} - NOT A TEACHER!", teacher_id);
        } else {
            warnings.push(format!("Unknown model type: {}", teacher_id));
            println!("  ⚠️  {} (unknown type)", teacher_id);
        }
    }
    println!();
    
    // Summary
    println!("═══════════════════════════════════════════════════════════════");
    println!("📊 VALIDATION SUMMARY");
    println!("═══════════════════════════════════════════════════════════════");
    println!();
    
    if !errors.is_empty() {
        println!("🚨 ERRORS ({}):", errors.len());
        for e in &errors {
            println!("   ❌ {}", e);
        }
        println!();
    }
    
    if !warnings.is_empty() {
        println!("⚠️  WARNINGS ({}):", warnings.len());
        for w in &warnings {
            println!("   ⚠️  {}", w);
        }
        println!();
    }
    
    if errors.is_empty() && warnings.is_empty() {
        println!("✅ HARVEST DATABASE VALID");
        println!();
        println!("Ready for distillation into GaiaLM");
    } else if errors.is_empty() {
        println!("✅ HARVEST DATABASE VALID (with warnings)");
    } else {
        println!("❌ HARVEST DATABASE INVALID");
        println!();
        println!("Fix errors before proceeding with distillation");
    }
    
    println!("═══════════════════════════════════════════════════════════════");
    println!();
}

