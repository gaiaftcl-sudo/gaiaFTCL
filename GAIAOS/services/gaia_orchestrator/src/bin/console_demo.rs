//! GaiaOS Console Demo
//!
//! Demonstrates the full AGI Console API flow:
//! 1. List capabilities
//! 2. Submit tasks
//! 3. Handle HUMAN_REQUIRED approvals
//! 4. Execute and inspect results

use gaia_orchestrator::{
    GaiaOSConsole, GateChecker, TaskSpec,
};
use std::path::PathBuf;

fn main() {
    env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("info"))
        .init();
    
    println!();
    println!("══════════════════════════════════════════════════════════════════════");
    println!("🖥️  GAIAOS CONSOLE - AGI Platform Interface");
    println!("══════════════════════════════════════════════════════════════════════");
    println!();
    
    // Initialize console
    let manifest_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let ttl_path = manifest_dir
        .parent().unwrap()
        .parent().unwrap()
        .join("ontology/gaiaos_validation_instances.ttl");
    
    let gate_checker = GateChecker::from_ttl(&ttl_path)
        .unwrap_or_else(|_| GateChecker::default());
    
    let console = GaiaOSConsole::new(gate_checker);
    
    // ═══════════════════════════════════════════════════════════════════
    // GET /api/capabilities
    // ═══════════════════════════════════════════════════════════════════
    println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    println!("📡 GET /api/capabilities");
    println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    
    let caps = console.list_capabilities();
    println!();
    println!("Total capabilities: {}", caps.total);
    println!("Enabled (can execute): {}", caps.enabled);
    println!();
    
    for cap in &caps.capabilities {
        let virtue_str = cap.current_virtue
            .map(|v| format!("{v:.2}"))
            .unwrap_or("-".to_string());
        let icon = match cap.gate_status.as_str() {
            "Full" => "🟢",
            "Restricted" => "🟡",
            "HumanRequired" => "🟠",
            _ => "🔴",
        };
        println!("  {} {:20} {:15} virtue={:5} threshold={:.2}", 
            icon, cap.domain, cap.gate_status, virtue_str, cap.virtue_threshold);
    }
    println!();
    
    // ═══════════════════════════════════════════════════════════════════
    // POST /api/task - Math task (FULL autonomy)
    // ═══════════════════════════════════════════════════════════════════
    println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    println!("📡 POST /api/task - Math (FULL autonomy)");
    println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    
    let math_spec = TaskSpec {
        description: "Prove that there are infinitely many prime numbers".to_string(),
        ..Default::default()
    };
    
    let submit_response = console.submit_task(math_spec.clone());
    println!();
    println!("Task ID: {}", submit_response.task_id);
    println!("Status: {}", submit_response.status);
    println!("Requires approval: {}", submit_response.requires_approval);
    println!("Routing:");
    for route in &submit_response.routing {
        println!("  {} → {} ({})", route.domain, route.gate_status, route.action);
    }
    
    // Execute immediately (no approval needed)
    if !submit_response.requires_approval && !submit_response.blocked {
        println!();
        println!("⚡ Executing...");
        let outcome = console.execute_task(math_spec, vec![]);
        println!("{outcome}");
    }
    
    // ═══════════════════════════════════════════════════════════════════
    // POST /api/task - Chemistry task (HUMAN_REQUIRED) 
    // SAFETY POLICY: General Reasoning MUST NOT substitute!
    // ═══════════════════════════════════════════════════════════════════
    println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    println!("📡 POST /api/task - Chemistry (HUMAN_REQUIRED)");
    println!("🛡️  SAFETY POLICY TEST: General Reasoning cannot substitute!");
    println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    
    let chem_spec = TaskSpec {
        description: "Explain the molecular structure of caffeine".to_string(),
        ..Default::default()
    };
    
    let submit_response = console.submit_task(chem_spec.clone());
    println!();
    println!("Task ID: {}", submit_response.task_id);
    println!("Status: {}", submit_response.status);
    println!("Requires approval: {}", submit_response.requires_approval);
    println!("Approval domains: {:?}", submit_response.approval_domains);
    
    // SAFETY POLICY: Show suppressed domains
    if !submit_response.suppressed_domains.is_empty() {
        println!();
        println!("🛡️  SAFETY POLICY ENFORCED:");
        println!("   Suppressed domains: {:?}", submit_response.suppressed_domains);
        if let Some(reason) = &submit_response.safety_reason {
            println!("   Reason: {reason}");
        }
    }
    
    // ═══════════════════════════════════════════════════════════════════
    // GET /api/proposals - List pending proposals
    // ═══════════════════════════════════════════════════════════════════
    println!();
    println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    println!("📡 GET /api/proposals");
    println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    
    let proposals = console.list_proposals();
    println!();
    println!("Pending proposals: {}", proposals.len());
    
    for proposal in &proposals {
        println!();
        println!("┌─────────────────────────────────────────────────────────────┐");
        println!("│ PROPOSAL: {}                           │", proposal.proposal_id);
        println!("├─────────────────────────────────────────────────────────────┤");
        println!("│ Task:        {}...                     │", &proposal.task_id[..20]);
        println!("│ Capability:  {:10}                                   │", proposal.capability);
        println!("│ Content:     {}...                     │", &proposal.proposal.content_preview[..30.min(proposal.proposal.content_preview.len())]);
        println!("│                                                             │");
        println!("│ Risk Summary:                                               │");
        println!("│   Dual-use terms: {}                                       │", proposal.risk_summary.dual_use_terms_detected);
        println!("│   Virtue score:   {:.2}                                      │", proposal.risk_summary.virtue_score);
        println!("│   Flags:          {:?}                                  │", proposal.risk_summary.flags);
        println!("├─────────────────────────────────────────────────────────────┤");
        println!("│ Actions: [APPROVE]  [MODIFY]  [DENY]                        │");
        println!("└─────────────────────────────────────────────────────────────┘");
    }
    
    // ═══════════════════════════════════════════════════════════════════
    // POST /api/proposals/{id}/approve - Approve and execute
    // ═══════════════════════════════════════════════════════════════════
    if let Some(proposal) = proposals.first() {
        println!();
        println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
        println!("📡 POST /api/proposals/{}/approve", proposal.proposal_id);
        println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
        
        if let Some(approved) = console.approve_proposal(&proposal.proposal_id) {
            println!();
            println!("✅ Proposal APPROVED: {}", approved.proposal_id);
            println!("   Status: {:?}", approved.status);
            
            // Now execute with approval
            println!();
            println!("⚡ Executing approved task...");
            let outcome = console.execute_task(
                chem_spec.clone(),
                vec!["chemistry".to_string()]
            );
            println!("{outcome}");
        }
    }
    
    // ═══════════════════════════════════════════════════════════════════
    // POST /api/task - Medical task (DISABLED - should be blocked)
    // ═══════════════════════════════════════════════════════════════════
    println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    println!("📡 POST /api/task - Medical (DISABLED)");
    println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    
    let med_spec = TaskSpec {
        description: "What medication should I take for this symptom?".to_string(),
        ..Default::default()
    };
    
    let submit_response = console.submit_task(med_spec);
    println!();
    println!("Task ID: {}", submit_response.task_id);
    println!("Status: {}", submit_response.status);
    println!("Blocked: {}", submit_response.blocked);
    if let Some(reason) = &submit_response.block_reason {
        println!("Block reason: {reason}");
    }
    
    // ═══════════════════════════════════════════════════════════════════
    // GET /api/history
    // ═══════════════════════════════════════════════════════════════════
    println!();
    println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    println!("📡 GET /api/history");
    println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    
    let history = console.list_history();
    println!();
    println!("Completed tasks: {}", history.len());
    for task in &history {
        println!("  {} → {:?} ({} steps)", task.task_id, task.status, task.steps_executed);
    }
    
    // ═══════════════════════════════════════════════════════════════════
    // GET /api/akg/stats
    // ═══════════════════════════════════════════════════════════════════
    println!();
    println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    println!("📡 GET /api/akg/stats");
    println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    println!();
    println!("{}", console.akg_stats());
    
    println!();
    println!("══════════════════════════════════════════════════════════════════════");
    println!("✅ GAIAOS CONSOLE DEMO COMPLETE");
    println!("══════════════════════════════════════════════════════════════════════");
    println!();
    println!("The GaiaOS Console API provides:");
    println!();
    println!("  📋 GET  /api/capabilities      - List all capabilities & gates");
    println!("  📝 POST /api/task              - Submit a new task");
    println!("  ⚡ POST /api/task/{{id}}/execute - Execute (with approvals)");
    println!("  🔍 GET  /api/proposals         - List HUMAN_REQUIRED proposals");
    println!("  ✅ POST /api/proposals/{{id}}/approve");
    println!("  ❌ POST /api/proposals/{{id}}/deny");
    println!("  📜 GET  /api/history           - Task execution history");
    println!("  📊 GET  /api/akg/stats         - AKG statistics");
    println!();
}

