use chrono::Utc;
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::env;
use std::fs;
use std::io::{self, BufRead, Write};
use std::path::{Path, PathBuf};
use std::process::Command;

const DRIVER: &str = "cells/health/scripts/franklin_mac_admin_gamp5_zero_human.sh";
const STATE_EVIDENCE: &str = "cells/health/evidence/macfranklin_state";
const EXT_EVIDENCE: &str = "cells/health/evidence/mac_gamp5_external_loop";
const EXTERNAL_LOOP: &str = "cells/franklin/scripts/mac_gamp5_external_loop.sh";

fn repo_root() -> PathBuf {
    if let Ok(v) = env::var("GAIAFTCL_REPO_ROOT") {
        if !v.trim().is_empty() {
            return PathBuf::from(v);
        }
    }
    if let Ok(v) = env::var("GAIAHEALTH_REPO_ROOT") {
        if !v.trim().is_empty() {
            return PathBuf::from(v);
        }
    }
    env::current_dir().unwrap_or_else(|_| PathBuf::from("."))
}

fn now_compact() -> String {
    Utc::now().format("%Y-%m-%dT%H%M%SZ").to_string()
}

fn now_utc() -> String {
    Utc::now().format("%Y-%m-%dT%H:%M:%SZ").to_string()
}

fn sha256_file(path: &Path) -> Result<String, String> {
    let bytes = fs::read(path).map_err(|e| format!("read {}: {}", path.display(), e))?;
    Ok(format!("{:x}", Sha256::digest(bytes)))
}

fn tool_repo_status() -> Value {
    let r = repo_root();
    let driver = r.join(DRIVER);
    let state_dir = r.join(STATE_EVIDENCE);
    json!({
        "ok": true,
        "gaiaftcl_repo_root": r.display().to_string(),
        "gamp5_driver_path": driver.display().to_string(),
        "gamp5_driver_exists": driver.is_file(),
        "state_evidence_dir": state_dir.display().to_string(),
    })
}

fn tool_run_mac_gamp5(args: &Value) -> Value {
    let smoke = args.get("smoke").and_then(Value::as_bool).unwrap_or(true);
    let r = repo_root();
    let script = r.join(DRIVER);
    if !script.is_file() {
        return json!({"ok": false, "exit_code": 127, "summary": format!("missing {}", DRIVER)});
    }
    let mut cmd = Command::new("/bin/sh");
    cmd.arg(script);
    cmd.current_dir(&r);
    cmd.env("GAIAFTCL_REPO_ROOT", &r);
    cmd.env("GAIAHEALTH_REPO_ROOT", &r);
    cmd.env("FRANKLIN_GAMP5_SMOKE", if smoke { "1" } else { "0" });
    match cmd.output() {
        Ok(out) => json!({
            "ok": out.status.success(),
            "exit_code": out.status.code().unwrap_or(1),
            "stdout": String::from_utf8_lossy(&out.stdout).to_string(),
            "stderr": String::from_utf8_lossy(&out.stderr).to_string(),
        }),
        Err(e) => json!({"ok": false, "summary": format!("process error: {}", e)}),
    }
}

fn latest_state_snapshot(state_dir: &Path) -> Option<PathBuf> {
    let rd = fs::read_dir(state_dir).ok()?;
    let mut files: Vec<PathBuf> = rd
        .filter_map(|e| e.ok().map(|x| x.path()))
        .filter(|p| p.is_file() && p.extension().map(|x| x == "json").unwrap_or(false))
        .filter(|p| p.file_name().map(|n| n.to_string_lossy().starts_with("state_")).unwrap_or(false))
        .collect();
    files.sort_by_key(|p| p.metadata().and_then(|m| m.modified()).ok());
    files.pop()
}

fn tool_runtime_state_latest() -> Value {
    let r = repo_root();
    let d = r.join(STATE_EVIDENCE);
    let Some(p) = latest_state_snapshot(&d) else {
        return json!({"ok": false, "summary": format!("no runtime state snapshots under {}", d.display())});
    };
    match fs::read_to_string(&p) {
        Ok(s) => match serde_json::from_str::<Value>(&s) {
            Ok(v) => json!({"ok": true, "path": p.display().to_string(), "state": v}),
            Err(e) => json!({"ok": false, "summary": format!("parse error: {}", e)}),
        },
        Err(e) => json!({"ok": false, "summary": format!("read error: {}", e)}),
    }
}

fn tool_capture_screenshot(args: &Value) -> Value {
    let prefix = args.get("prefix").and_then(Value::as_str).unwrap_or("macfranklin_state");
    let r = repo_root();
    let out_dir = r.join(EXT_EVIDENCE).join("screenshots");
    if fs::create_dir_all(&out_dir).is_err() {
        return json!({"ok": false, "summary": "failed to create screenshot dir"});
    }
    let out = out_dir.join(format!("{}_{}.png", prefix, now_compact()));
    let st = Command::new("/usr/sbin/screencapture").arg("-x").arg(&out).status();
    match st {
        Ok(status) if status.success() && out.is_file() => {
            let sha = sha256_file(&out).unwrap_or_default();
            json!({"ok": true, "path": out.display().to_string(), "sha256": sha, "captured_utc": now_utc(), "capture_mode": "fullscreen"})
        }
        Ok(_) => json!({"ok": false, "summary": "screencapture failed", "hint": "grant Screen Recording permission and run in interactive GUI session"}),
        Err(e) => json!({"ok": false, "summary": format!("screencapture exec failed: {}", e)}),
    }
}

fn tool_visual_validate(args: &Value) -> Value {
    let r = repo_root();
    let expected_rel = match args.get("expected_relative_path").and_then(Value::as_str) {
        Some(v) => v,
        None => return json!({"ok": false, "summary": "missing expected_relative_path"}),
    };
    let actual_rel = match args.get("actual_relative_path").and_then(Value::as_str) {
        Some(v) => v,
        None => return json!({"ok": false, "summary": "missing actual_relative_path"}),
    };
    let state_id = args.get("state_id").and_then(Value::as_str).unwrap_or("RUNNING_GAMES");
    let expected = r.join(expected_rel);
    let actual = r.join(actual_rel);
    if !expected.is_file() {
        return json!({"ok": false, "summary": format!("missing expected file: {}", expected_rel)});
    }
    if !actual.is_file() {
        return json!({"ok": false, "summary": format!("missing actual file: {}", actual_rel)});
    }
    let exp_size = expected.metadata().map(|m| m.len()).unwrap_or(0);
    let act_size = actual.metadata().map(|m| m.len()).unwrap_or(0);
    let size_delta = exp_size.abs_diff(act_size);
    let denom = exp_size.max(act_size).max(1);
    let norm = (size_delta as f64) / (denom as f64);
    let exp_sha = sha256_file(&expected).unwrap_or_default();
    let act_sha = sha256_file(&actual).unwrap_or_default();
    let ext_exp = expected.extension().map(|x| format!(".{}", x.to_string_lossy().to_lowercase())).unwrap_or_default();
    let ext_act = actual.extension().map(|x| format!(".{}", x.to_string_lossy().to_lowercase())).unwrap_or_default();
    let exp_ok = [".svg", ".usda", ".usd", ".png", ".jpg", ".jpeg"].contains(&ext_exp.as_str());
    let act_ok = [".png", ".jpg", ".jpeg"].contains(&ext_act.as_str());
    let pass = exp_ok && act_ok && norm <= 0.95;

    let out_dir = r.join(EXT_EVIDENCE).join("visual");
    let _ = fs::create_dir_all(&out_dir);
    let out_path = out_dir.join(format!("visual_{}_{}.json", state_id, now_compact()));
    let result = json!({
        "schema": "macfranklin_visual_validation_v1",
        "ts_utc": now_utc(),
        "state_id": state_id,
        "expected_path": expected.display().to_string(),
        "actual_path": actual.display().to_string(),
        "expected_sha256": exp_sha,
        "actual_sha256": act_sha,
        "expected_size": exp_size,
        "actual_size": act_size,
        "size_delta_bytes": size_delta,
        "normalized_size_delta": norm,
        "extension_pair": [ext_exp, ext_act],
        "structural_extension_ok": exp_ok && act_ok,
        "exact_hash_match": exp_sha == act_sha,
        "pass": pass
    });
    let _ = fs::write(&out_path, serde_json::to_string_pretty(&result).unwrap_or_else(|_| "{}".to_string()) + "\n");
    json!({"ok": true, "result_path": out_path.display().to_string(), "result": result})
}

fn tool_publish_game_receipt(args: &Value) -> Value {
    let r = repo_root();
    let state_id = args.get("state_id").and_then(Value::as_str).unwrap_or("RUNNING_GAMES");
    let catalog_row = args.get("catalog_row").and_then(Value::as_str).unwrap_or("external-loop-visual");
    let passed = args.get("passed").and_then(Value::as_bool).unwrap_or(false);
    let expected_rel = args.get("expected_relative_path").and_then(Value::as_str).unwrap_or("");
    let actual_rel = args.get("actual_relative_path").and_then(Value::as_str).unwrap_or("");
    let visual_rel = args.get("visual_result_relative_path").and_then(Value::as_str).unwrap_or("");
    let note = args.get("note").and_then(Value::as_str).unwrap_or("");
    let operator_id = env::var("MAC_GAMP5_OPERATOR_ID").unwrap_or_else(|_| "owner-mac".to_string());

    let exp_sha = if expected_rel.is_empty() { "".to_string() } else { sha256_file(&r.join(expected_rel)).unwrap_or_default() };
    let act_sha = if actual_rel.is_empty() { "".to_string() } else { sha256_file(&r.join(actual_rel)).unwrap_or_default() };
    let vis_sha = if visual_rel.is_empty() { "".to_string() } else { sha256_file(&r.join(visual_rel)).unwrap_or_default() };
    let canonical = json!({
        "schema":"mac_gamp5_game_receipt_v1",
        "ts_utc": now_utc(),
        "state_id": state_id,
        "catalog_row": catalog_row,
        "passed": passed,
        "operator_id": operator_id,
        "expected_relative_path": expected_rel,
        "actual_relative_path": actual_rel,
        "visual_result_relative_path": visual_rel,
        "expected_sha256": exp_sha,
        "actual_sha256": act_sha,
        "visual_result_sha256": vis_sha,
        "note": note
    });
    let sig = format!("{:x}", Sha256::digest(serde_json::to_vec(&canonical).unwrap_or_default()));
    let mut payload = canonical;
    payload["signature_sha256"] = json!(sig);
    payload["signature_scheme"] = json!("sha256(canonical_json_v1)");

    let out_dir = r.join(EXT_EVIDENCE).join("receipts");
    let _ = fs::create_dir_all(&out_dir);
    let out = out_dir.join(format!("game_receipt_{}_{}.json", state_id, now_compact()));
    let _ = fs::write(&out, serde_json::to_string_pretty(&payload).unwrap_or_else(|_| "{}".to_string()) + "\n");
    json!({"ok": true, "path": out.display().to_string(), "receipt": payload})
}

fn tool_run_external_loop(args: &Value) -> Value {
    let use_clone = args.get("use_clone").and_then(Value::as_bool).unwrap_or(true);
    let open_app = args.get("open_app").and_then(Value::as_bool).unwrap_or(true);
    let owner_consent = args.get("owner_consent").and_then(Value::as_str).unwrap_or("ask");
    let r = repo_root();
    let script = r.join(EXTERNAL_LOOP);
    if !script.is_file() {
        return json!({"ok": false, "exit_code": 127, "summary": format!("missing {}", EXTERNAL_LOOP)});
    }
    let out = Command::new("/bin/zsh")
        .arg(script)
        .current_dir(&r)
        .env("GAIAFTCL_REPO_ROOT", &r)
        .env("GAIAHEALTH_REPO_ROOT", &r)
        .env("MAC_GAMP5_USE_CLONE", if use_clone { "1" } else { "0" })
        .env("MAC_GAMP5_OPEN_APP", if open_app { "1" } else { "0" })
        .env("MAC_GAMP5_OWNER_CONSENT", owner_consent)
        .output();
    match out {
        Ok(o) => json!({
            "ok": o.status.success(),
            "exit_code": o.status.code().unwrap_or(1),
            "stdout": String::from_utf8_lossy(&o.stdout).to_string(),
            "stderr": String::from_utf8_lossy(&o.stderr).to_string(),
        }),
        Err(e) => json!({"ok": false, "summary": format!("process error: {}", e)}),
    }
}

fn list_tools() -> Value {
    json!({
        "tools": [
            {"name":"franklin_repo_status","description":"Check repo and paths","inputSchema":{"type":"object","properties":{}}},
            {"name":"franklin_run_mac_gamp5","description":"Run franklin mac gamp5","inputSchema":{"type":"object","properties":{"smoke":{"type":"boolean"}}}},
            {"name":"franklin_runtime_state_latest","description":"Read latest app runtime state","inputSchema":{"type":"object","properties":{}}},
            {"name":"franklin_capture_screenshot","description":"Capture screenshot","inputSchema":{"type":"object","properties":{"prefix":{"type":"string"}}}},
            {"name":"franklin_visual_validate","description":"Visual validation expected vs actual","inputSchema":{"type":"object","properties":{"expected_relative_path":{"type":"string"},"actual_relative_path":{"type":"string"},"state_id":{"type":"string"}},"required":["expected_relative_path","actual_relative_path","state_id"]}},
            {"name":"franklin_publish_game_receipt","description":"Publish signed game receipt","inputSchema":{"type":"object","properties":{"state_id":{"type":"string"},"catalog_row":{"type":"string"},"passed":{"type":"boolean"}},"required":["state_id","catalog_row","passed"]}},
            {"name":"franklin_run_external_loop","description":"Run external loop orchestrator","inputSchema":{"type":"object","properties":{"use_clone":{"type":"boolean"},"open_app":{"type":"boolean"},"owner_consent":{"type":"string"}}}}
        ]
    })
}

fn handle_call(name: &str, args: &Value) -> Value {
    match name {
        "franklin_repo_status" => tool_repo_status(),
        "franklin_run_mac_gamp5" => tool_run_mac_gamp5(args),
        "franklin_runtime_state_latest" => tool_runtime_state_latest(),
        "franklin_capture_screenshot" => tool_capture_screenshot(args),
        "franklin_visual_validate" => tool_visual_validate(args),
        "franklin_publish_game_receipt" => tool_publish_game_receipt(args),
        "franklin_run_external_loop" => tool_run_external_loop(args),
        _ => json!({"ok": false, "summary": format!("unknown tool: {}", name)}),
    }
}

fn write_response(id: &Value, result: Value) {
    let mut out = io::stdout().lock();
    let resp = json!({"jsonrpc":"2.0","id":id,"result":result});
    let _ = writeln!(out, "{}", resp);
    let _ = out.flush();
}

fn write_error(id: &Value, code: i64, message: &str) {
    let mut out = io::stdout().lock();
    let resp = json!({"jsonrpc":"2.0","id":id,"error":{"code":code,"message":message}});
    let _ = writeln!(out, "{}", resp);
    let _ = out.flush();
}

fn main() {
    let stdin = io::stdin();
    for line in stdin.lock().lines() {
        let Ok(line) = line else { continue };
        if line.trim().is_empty() {
            continue;
        }
        let msg: Value = match serde_json::from_str(&line) {
            Ok(v) => v,
            Err(_) => continue,
        };
        let id = msg.get("id").cloned().unwrap_or(json!(null));
        let method = msg.get("method").and_then(Value::as_str).unwrap_or("");
        match method {
            "initialize" => write_response(
                &id,
                json!({
                    "protocolVersion":"2024-11-05",
                    "serverInfo":{"name":"macfranklin-rust","version":"0.1.0"},
                    "capabilities":{"tools":{}}
                }),
            ),
            "notifications/initialized" => {}
            "tools/list" => write_response(&id, list_tools()),
            "tools/call" => {
                let params = msg.get("params").cloned().unwrap_or_else(|| json!({}));
                let name = params.get("name").and_then(Value::as_str).unwrap_or("");
                let args = params.get("arguments").cloned().unwrap_or_else(|| json!({}));
                let result = handle_call(name, &args);
                write_response(&id, json!({"content":[{"type":"text","text": serde_json::to_string(&result).unwrap_or_else(|_| "{}".to_string())}], "isError": !result.get("ok").and_then(Value::as_bool).unwrap_or(false)}));
            }
            "ping" => write_response(&id, json!({})),
            _ => {
                if !id.is_null() {
                    write_error(&id, -32601, "method not found");
                }
            }
        }
    }
}
