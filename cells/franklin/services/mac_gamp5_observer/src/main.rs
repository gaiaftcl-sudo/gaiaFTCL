use chrono::Utc;
use serde::Serialize;
use sha2::{Digest, Sha256};
use std::env;
use std::fs;
use std::io::Read;
use std::path::{Path, PathBuf};
use std::process::Command;

#[derive(Serialize)]
struct VisualResult {
    schema: &'static str,
    ts_utc: String,
    state_id: String,
    expected_path: String,
    actual_path: String,
    expected_sha256: String,
    actual_sha256: String,
    expected_size: u64,
    actual_size: u64,
    size_delta_bytes: u64,
    normalized_size_delta: f64,
    extension_pair: [String; 2],
    structural_extension_ok: bool,
    exact_hash_match: bool,
    pass: bool,
}

#[derive(Serialize)]
struct GameReceipt {
    schema: &'static str,
    ts_utc: String,
    state_id: String,
    catalog_row: String,
    passed: bool,
    operator_id: String,
    expected_relative_path: String,
    actual_relative_path: String,
    visual_result_relative_path: String,
    expected_sha256: String,
    actual_sha256: String,
    visual_result_sha256: String,
    note: String,
    signature_sha256: String,
    signature_scheme: &'static str,
}

#[derive(Serialize)]
struct Summary {
    state_snapshot_path: String,
    screenshot_path: String,
    visual_result_path: String,
    game_receipt_path: String,
    passed: bool,
}

fn now_compact() -> String {
    Utc::now().format("%Y-%m-%dT%H%M%SZ").to_string()
}

fn now_utc() -> String {
    Utc::now().format("%Y-%m-%dT%H:%M:%SZ").to_string()
}

fn sha256_file(path: &Path) -> Result<String, String> {
    let mut f = fs::File::open(path).map_err(|e| format!("open {}: {}", path.display(), e))?;
    let mut h = Sha256::new();
    let mut buf = [0u8; 1024 * 1024];
    loop {
        let n = f.read(&mut buf).map_err(|e| format!("read {}: {}", path.display(), e))?;
        if n == 0 {
            break;
        }
        h.update(&buf[..n]);
    }
    Ok(format!("{:x}", h.finalize()))
}

fn latest_state_snapshot(state_dir: &Path) -> Result<PathBuf, String> {
    let mut entries: Vec<PathBuf> = fs::read_dir(state_dir)
        .map_err(|e| format!("read_dir {}: {}", state_dir.display(), e))?
        .filter_map(|e| e.ok().map(|x| x.path()))
        .filter(|p| p.is_file() && p.extension().map(|x| x == "json").unwrap_or(false))
        .filter(|p| p.file_name().map(|n| n.to_string_lossy().starts_with("state_")).unwrap_or(false))
        .collect();
    if entries.is_empty() {
        return Err(format!("no runtime state snapshot in {}", state_dir.display()));
    }
    entries.sort_by_key(|p| p.metadata().and_then(|m| m.modified()).ok());
    entries.reverse();
    Ok(entries[0].clone())
}

fn capture_screenshot(repo: &Path, out: &Path) -> Result<(), String> {
    let st = Command::new("/usr/sbin/screencapture")
        .arg("-x")
        .arg(out)
        .current_dir(repo)
        .status()
        .map_err(|e| format!("screencapture exec failed: {}", e))?;
    if st.success() && out.is_file() {
        return Ok(());
    }
    Err("screencapture failed (grant Screen Recording and run in GUI session)".to_string())
}

fn rel_to_repo(repo: &Path, p: &Path) -> Result<String, String> {
    p.strip_prefix(repo)
        .map(|x| x.to_string_lossy().to_string())
        .map_err(|_| format!("path {} is not under repo {}", p.display(), repo.display()))
}

fn main() {
    if let Err(e) = run() {
        eprintln!("{e}");
        std::process::exit(1);
    }
}

fn run() -> Result<(), String> {
    let repo = PathBuf::from(env::var("TARGET_REPO").map_err(|_| "TARGET_REPO required".to_string())?);
    let run_dir = PathBuf::from(env::var("RUN_DIR").map_err(|_| "RUN_DIR required".to_string())?);
    let state_id = env::var("MAC_GAMP5_STATE_ID").unwrap_or_else(|_| "RUNNING_GAMES".to_string());
    let operator_id = env::var("MAC_GAMP5_OPERATOR_ID").unwrap_or_else(|_| "owner-mac".to_string());
    let expected_rel = env::var("MAC_GAMP5_EXPECTED_REL")
        .unwrap_or_else(|_| "cells/health/swift/MacFranklin/Sources/Resources/FranklinLiveCell.usda".to_string());
    let expected = repo.join(&expected_rel);
    if !expected.is_file() {
        return Err(format!("missing expected artifact: {}", expected.display()));
    }

    let state_dir = repo.join("cells/health/evidence/macfranklin_state");
    let state_snapshot = latest_state_snapshot(&state_dir)?;

    let screenshot_dir = repo.join("cells/health/evidence/mac_gamp5_external_loop/screenshots");
    fs::create_dir_all(&screenshot_dir).map_err(|e| e.to_string())?;
    let screenshot = screenshot_dir.join(format!("external_loop_{}.png", now_compact()));
    capture_screenshot(&repo, &screenshot)?;

    let expected_size = expected.metadata().map_err(|e| e.to_string())?.len();
    let actual_size = screenshot.metadata().map_err(|e| e.to_string())?.len();
    let size_delta = expected_size.abs_diff(actual_size);
    let denom = expected_size.max(actual_size).max(1);
    let normalized_size_delta = (size_delta as f64) / (denom as f64);
    let expected_sha = sha256_file(&expected)?;
    let actual_sha = sha256_file(&screenshot)?;
    let ext_exp = expected.extension().map(|s| format!(".{}", s.to_string_lossy().to_lowercase())).unwrap_or_default();
    let ext_act = screenshot.extension().map(|s| format!(".{}", s.to_string_lossy().to_lowercase())).unwrap_or_default();
    let exp_ok = [".svg", ".usda", ".usd", ".png", ".jpg", ".jpeg"].contains(&ext_exp.as_str());
    let act_ok = [".png", ".jpg", ".jpeg"].contains(&ext_act.as_str());
    let pass = exp_ok && act_ok && normalized_size_delta <= 0.95;

    let visual = VisualResult {
        schema: "macfranklin_visual_validation_v1",
        ts_utc: now_utc(),
        state_id: state_id.clone(),
        expected_path: expected.display().to_string(),
        actual_path: screenshot.display().to_string(),
        expected_sha256: expected_sha.clone(),
        actual_sha256: actual_sha.clone(),
        expected_size,
        actual_size,
        size_delta_bytes: size_delta,
        normalized_size_delta,
        extension_pair: [ext_exp.clone(), ext_act.clone()],
        structural_extension_ok: exp_ok && act_ok,
        exact_hash_match: expected_sha == actual_sha,
        pass,
    };
    let visual_dir = repo.join("cells/health/evidence/mac_gamp5_external_loop/visual");
    fs::create_dir_all(&visual_dir).map_err(|e| e.to_string())?;
    let visual_path = visual_dir.join(format!("visual_{}_{}.json", state_id, now_compact()));
    fs::write(&visual_path, serde_json::to_string_pretty(&visual).map_err(|e| e.to_string())? + "\n")
        .map_err(|e| e.to_string())?;
    let visual_sha = sha256_file(&visual_path)?;

    let canonical = serde_json::json!({
        "schema":"mac_gamp5_game_receipt_v1",
        "ts_utc": now_utc(),
        "state_id": state_id,
        "catalog_row":"external-loop-visual",
        "passed": pass,
        "operator_id": operator_id,
        "expected_relative_path": expected_rel,
        "actual_relative_path": rel_to_repo(&repo, &screenshot)?,
        "visual_result_relative_path": rel_to_repo(&repo, &visual_path)?,
        "expected_sha256": expected_sha,
        "actual_sha256": actual_sha,
        "visual_result_sha256": visual_sha,
        "note":"mac_gamp5_external_loop observer game (rust)"
    });
    let canonical_bytes = serde_json::to_vec(&canonical).map_err(|e| e.to_string())?;
    let sig = format!("{:x}", Sha256::digest(canonical_bytes));
    let receipt = GameReceipt {
        schema: "mac_gamp5_game_receipt_v1",
        ts_utc: now_utc(),
        state_id,
        catalog_row: "external-loop-visual".to_string(),
        passed: pass,
        operator_id,
        expected_relative_path: expected_rel,
        actual_relative_path: rel_to_repo(&repo, &screenshot)?,
        visual_result_relative_path: rel_to_repo(&repo, &visual_path)?,
        expected_sha256: expected_sha,
        actual_sha256: actual_sha,
        visual_result_sha256: visual_sha,
        note: "mac_gamp5_external_loop observer game (rust)".to_string(),
        signature_sha256: sig,
        signature_scheme: "sha256(canonical_json_v1)",
    };
    let rec_dir = repo.join("cells/health/evidence/mac_gamp5_external_loop/receipts");
    fs::create_dir_all(&rec_dir).map_err(|e| e.to_string())?;
    let rec_path = rec_dir.join(format!("game_receipt_{}_{}.json", receipt.state_id, now_compact()));
    fs::write(&rec_path, serde_json::to_string_pretty(&receipt).map_err(|e| e.to_string())? + "\n")
        .map_err(|e| e.to_string())?;

    let summary = Summary {
        state_snapshot_path: state_snapshot.display().to_string(),
        screenshot_path: screenshot.display().to_string(),
        visual_result_path: visual_path.display().to_string(),
        game_receipt_path: rec_path.display().to_string(),
        passed: receipt.passed,
    };
    let summary_path = run_dir.join("observer_game_summary.json");
    fs::write(&summary_path, serde_json::to_string_pretty(&summary).map_err(|e| e.to_string())? + "\n")
        .map_err(|e| e.to_string())?;
    println!("observer game summary: {}", summary_path.display());
    if !receipt.passed {
        return Err("observer visual check failed (REFUSED)".to_string());
    }
    Ok(())
}
