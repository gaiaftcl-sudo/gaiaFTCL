//! Bevy UI Test Executor
//! Executes cargo test commands for Bevy UI packages

use anyhow::{Context, Result};
use chrono::Utc;
use std::process::Command;
use uuid::Uuid;

use crate::{PerformanceMetrics, TestRunResult};

#[derive(Debug, Clone, Copy)]
pub enum WorldKind {
    ATC,
    QCell,
    Astro,
}

impl WorldKind {
    pub fn from_str(s: &str) -> Option<Self> {
        match s {
            "ATC" => Some(WorldKind::ATC),
            "QCell" => Some(WorldKind::QCell),
            "Astro" => Some(WorldKind::Astro),
            _ => None,
        }
    }

    pub fn package_name(&self) -> &'static str {
        match self {
            WorldKind::ATC => "gaiaos_atc_ui",
            WorldKind::QCell => "gaiaos_smallworld_ui",
            WorldKind::Astro => "gaiaos_astro_ui",
        }
    }

    pub fn test_file(&self) -> &'static str {
        match self {
            WorldKind::ATC => "substrate_physics_tests",
            WorldKind::QCell => "molecular_physics_tests",
            WorldKind::Astro => "orbital_physics_tests",
        }
    }
}

/// Execute Bevy UI scenario test
pub async fn execute_bevy_scenario(
    world: &str,
    scenario: &str,
    frames: usize,
) -> Result<TestRunResult> {
    let world_kind = WorldKind::from_str(world).context(format!("Invalid world: {}", world))?;

    let run_id = Uuid::new_v4().to_string();
    let workspace_root = std::env::current_dir()?;

    tracing::info!(
        "Executing Bevy scenario: world={}, scenario={}, frames={}",
        world,
        scenario,
        frames
    );

    // Build cargo test command
    let output = Command::new("cargo")
        .args(&[
            "test",
            "--package",
            world_kind.package_name(),
            "--test",
            world_kind.test_file(),
            "--",
            scenario,
            "--nocapture",
        ])
        .current_dir(&workspace_root)
        .output()
        .context("Failed to execute cargo test")?;

    let passed = output.status.success();
    let stdout = String::from_utf8_lossy(&output.stdout);
    let stderr = String::from_utf8_lossy(&output.stderr);

    // Parse test output for performance metrics
    let performance_metrics = parse_performance_metrics(&stdout);

    // Collect artifacts
    let artifacts = collect_test_artifacts(world_kind).await?;

    let result = TestRunResult {
        run_id: run_id.clone(),
        world: world.to_string(),
        scenario: scenario.to_string(),
        passed,
        timestamp: Utc::now().to_rfc3339(),
        artifacts,
        substrate_match: passed, // If test passed, assume substrate match
        performance_metrics,
    };

    tracing::info!("Scenario complete: run_id={}, passed={}", run_id, passed);

    if !passed {
        tracing::error!("Test output:\n{}\n{}", stdout, stderr);
    }

    Ok(result)
}

fn parse_performance_metrics(stdout: &str) -> Option<PerformanceMetrics> {
    // Parse performance data from test output
    // Look for patterns like "frame_time: 16.5ms"

    // Planned: implement structured parsing (frame_time_ms, fps, memory_mb) from stdout markers.
    let _ = stdout;
    None
}

async fn collect_test_artifacts(world: WorldKind) -> Result<Vec<String>> {
    // Collect screenshots, logs, reports from test run

    let artifacts_dir = format!("target/test-artifacts/{}", world.package_name());

    // Planned: scan directory for artifacts (screenshots, logs, reports) and return their relative paths.
    let _ = artifacts_dir;
    // For now, return empty list

    Ok(vec![])
}

/// Execute all scenarios for a world
pub async fn execute_all_scenarios(world: &str) -> Result<Vec<TestRunResult>> {
    let scenarios = match world {
        "ATC" => vec![
            "two_aircraft_converging",
            "high_risk_weather",
            "atc_8d_coordinate_mapping",
            "atc_quantum_superposition",
        ],
        "QCell" => vec![
            "toxic_candidate",
            "high_coherence",
            "candidate_ranking",
            "vqbit_8d_consumption",
        ],
        "Astro" => vec!["transfer_window", "orbital_integration"],
        _ => vec![],
    };

    let mut results = Vec::new();

    for scenario in scenarios {
        let result = execute_bevy_scenario(world, scenario, 100).await?;
        results.push(result);
    }

    Ok(results)
}
