//! Live Encoding Test Binary
//!
//! Run with: cargo run -p inference_encoder --bin test_live_encoding

use inference_encoder::{LiveInferenceEncoder, InMemoryAkg};
use uum8d::{TurnMeta, ChemistryMeta, GalaxyMeta, WorldModelMeta};
use std::sync::Arc;

fn main() {
    // Initialize logging to see [QSTATE8] messages
    env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("info"))
        .format_timestamp_millis()
        .init();

    println!();
    println!("═══════════════════════════════════════════════════════════════════");
    println!("🔬 GAIAOS LIVE ENCODING TEST - HELLO WORLD");
    println!("═══════════════════════════════════════════════════════════════════");
    println!();

    // Create AKG (in-memory for testing)
    let akg = Arc::new(InMemoryAkg::new());
    let encoder = LiveInferenceEncoder::new(akg.clone());

    println!("📊 Initial AKG state: {} QState8 nodes", akg.qstate_nodes().len());
    println!();

    // =========================================================================
    // SIMULATE 4 MODEL INFERENCES + ENCODINGS
    // =========================================================================

    // 1. General Reasoning
    println!("━━━ ENCODING: General Reasoning (llama_core_70b) ━━━");
    encoder.encode_after_general_inference(
        "llama_core_70b",
        "step_001",
        "assistant",
        "I can help you with quantum computing concepts.",
        TurnMeta::default(),
    );
    println!();

    // 2. Chemistry
    println!("━━━ ENCODING: Chemistry (chemllm_7b_dpo) ━━━");
    encoder.encode_after_chemistry_inference(
        "chemllm_7b_dpo",
        "step_002",
        "CC(=O)OC1=CC=CC=C1C(=O)O", // Aspirin SMILES
        ChemistryMeta::default(),
    );
    println!();

    // 3. Galaxy
    println!("━━━ ENCODING: Galaxy (astrosage_8b) ━━━");
    encoder.encode_after_galaxy_inference(
        "astrosage_8b",
        "step_003",
        "What is dark energy?",
        GalaxyMeta::default(),
    );
    println!();

    // 4. World Model
    println!("━━━ ENCODING: World Model (cosmos_14b) ━━━");
    encoder.encode_after_world_model_inference(
        "cosmos_14b",
        "step_004",
        "Simulate robot navigation",
        WorldModelMeta::default(),
    );
    println!();

    // =========================================================================
    // VERIFY AKG HAS THE NODES
    // =========================================================================
    println!("═══════════════════════════════════════════════════════════════════");
    println!("📊 AKG VERIFICATION");
    println!("═══════════════════════════════════════════════════════════════════");
    println!();

    let nodes = akg.qstate_nodes();
    println!("QState8 nodes in AKG: {}", nodes.len());
    println!();

    for (id, props) in &nodes {
        let model = props.get("model_id").and_then(|v| v.as_str()).unwrap_or("?");
        let profile = props.get("profile").and_then(|v| v.as_str()).unwrap_or("?");
        
        let mut amps = [0.0f64; 8];
        for i in 0..8 {
            if let Some(serde_json::Value::Number(n)) = props.get(&format!("uum:amp{i}")) {
                amps[i] = n.as_f64().unwrap_or(0.0);
            }
        }
        
        let norm_sq: f64 = amps.iter().map(|x| x * x).sum();
        let norm_ok = (norm_sq - 1.0).abs() < 0.02;
        
        println!("  {id} ({model})");
        println!("    profile: {profile}");
        println!("    amps: [{:.3}, {:.3}, {:.3}, {:.3}, {:.3}, {:.3}, {:.3}, {:.3}]",
            amps[0], amps[1], amps[2], amps[3], amps[4], amps[5], amps[6], amps[7]);
        println!("    Σ(amp²) = {:.6} {}", norm_sq, if norm_ok { "✅" } else { "❌" });
        println!();
    }

    // =========================================================================
    // FINAL STATUS
    // =========================================================================
    if nodes.len() == 4 {
        println!("═══════════════════════════════════════════════════════════════════");
        println!("✅ LIVE ENCODING WORKS - 4/4 models encoded to AKG");
        println!("═══════════════════════════════════════════════════════════════════");
        println!();
        println!("This proves the encoding hot path is functional.");
        println!("Next: Wire LiveInferenceEncoder into the main orchestrator.");
    } else {
        println!("═══════════════════════════════════════════════════════════════════");
        println!("❌ INCOMPLETE: Expected 4 nodes, got {}", nodes.len());
        println!("═══════════════════════════════════════════════════════════════════");
    }
}

