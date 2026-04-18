use anyhow::Result;
use serde::{Deserialize, Serialize};
use chrono::{DateTime, Utc};
use crate::akg::AKGClient;

/// World Scoreboard with current metrics and targets
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorldScoreboard {
    pub world: String,
    pub current_metrics: WorldMetrics,
    pub current_targets: WorldTargets,
    pub aspirational_targets: WorldTargets,
    pub last_escalation: Option<DateTime<Utc>>,
    pub improvements_since_escalation: u32,
    pub quality_bar_history: Vec<QualityBarEvent>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorldMetrics {
    pub fps_p95: Option<f64>,
    pub wasm_size_bytes: Option<u64>,
    pub particle_count: Option<u32>,
    pub draw_calls: Option<u32>,
    pub allocations_per_frame: Option<u32>,
    pub crash_rate: Option<f64>,
    // ATC-specific
    pub stream_determinism: Option<f64>,
    pub alert_accuracy: Option<f64>,
    pub ui_latency_p95: Option<f64>,
    // Astro-specific
    pub orbit_error_km_per_day: Option<f64>,
    pub camera_jitter_pixels: Option<f64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorldTargets {
    pub fps_p95: f64,
    pub wasm_size_bytes: u64,
    pub particles: u32,
    pub draw_calls: u32,
    pub allocations_per_frame: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QualityBarEvent {
    pub timestamp: DateTime<Utc>,
    pub metric: String,
    pub previous_target: f64,
    pub new_target: f64,
    pub trigger_reason: String,
}

/// Quality Bar Escalator
pub struct QualityBarEscalator {
    akg_client: AKGClient,
}

impl QualityBarEscalator {
    pub fn new(akg_client: AKGClient) -> Self {
        Self { akg_client }
    }

    /// Query current scoreboard for a world
    pub async fn query_scoreboard(&self, world: &str) -> Result<WorldScoreboard> {
        let query = format!(
            r#"
            FOR scoreboard IN WorldScoreboards
            FILTER scoreboard.world == "{}"
            RETURN scoreboard
            "#,
            world
        );
        
        let mut results: Vec<WorldScoreboard> = self.akg_client.query(&query).await?;
        
        if let Some(scoreboard) = results.pop() {
            Ok(scoreboard)
        } else {
            // Initialize default scoreboard
            Ok(self.initialize_scoreboard(world).await?)
        }
    }

    /// Check if quality bar should be raised and execute escalation
    pub async fn check_and_escalate(&self, world: &str) -> Result<EscalationResult> {
        // Get recent verification results
        let query = format!(
            r#"
            FOR v IN Verifications
            FILTER v.world == "{}"
            FILTER v.timestamp > DATE_SUBTRACT(NOW(), 7, "day")
            FILTER v.verdict == "PASS"
            COLLECT AGGREGATE 
                avg_fps = AVG(v.performance.fps),
                avg_improvement = AVG(v.improvement_pct),
                count = LENGTH(v)
            RETURN {{
                avg_fps: avg_fps,
                avg_improvement: avg_improvement,
                sample_size: count
            }}
            "#,
            world
        );
        
        let stats: Vec<PerformanceStats> = self.akg_client.query(&query).await?;
        let stats = stats.into_iter().next()
            .ok_or_else(|| anyhow::anyhow!("No performance data available"))?;
        
        // Get current scoreboard
        let mut scoreboard = self.query_scoreboard(world).await?;
        
        // Check escalation conditions
        if stats.sample_size >= 10 && stats.avg_improvement > 10.0 {
            // Raise the bar!
            let new_target_fps = stats.avg_fps * 1.1; // 10% higher
            let previous_target = scoreboard.current_targets.fps_p95;
            
            // Update targets
            scoreboard.current_targets.fps_p95 = new_target_fps;
            scoreboard.last_escalation = Some(Utc::now());
            scoreboard.improvements_since_escalation = 0;
            
            // Record event
            let event = QualityBarEvent {
                timestamp: Utc::now(),
                metric: "fps_p95".to_string(),
                previous_target,
                new_target: new_target_fps,
                trigger_reason: format!(
                    "{} improvements averaging {:.1}% gain",
                    stats.sample_size, stats.avg_improvement
                ),
            };
            scoreboard.quality_bar_history.push(event.clone());
            
            // Persist updated scoreboard
            self.update_scoreboard(&scoreboard).await?;
            
            // Create new stretch goals
            let stretch_goals = self.create_stretch_goals(world, &scoreboard).await?;
            
            println!("📈 Quality bar raised for {} world!", world);
            println!("   Previous FPS target: {:.1}", previous_target);
            println!("   New FPS target: {:.1}", new_target_fps);
            println!("   Created {} stretch goals", stretch_goals.len());
            
            Ok(EscalationResult {
                escalated: true,
                previous_targets: WorldTargets {
                    fps_p95: previous_target,
                    ..scoreboard.current_targets.clone()
                },
                new_targets: scoreboard.current_targets.clone(),
                stretch_goals_created: stretch_goals,
            })
        } else {
            Ok(EscalationResult {
                escalated: false,
                previous_targets: scoreboard.current_targets.clone(),
                new_targets: scoreboard.current_targets.clone(),
                stretch_goals_created: vec![],
            })
        }
    }

    async fn initialize_scoreboard(&self, world: &str) -> Result<WorldScoreboard> {
        let (current_targets, aspirational_targets) = match world {
            "small" => (
                WorldTargets {
                    fps_p95: 60.0,
                    wasm_size_bytes: 5 * 1024 * 1024, // 5 MB
                    particles: 100_000,
                    draw_calls: 10,
                    allocations_per_frame: 10,
                },
                WorldTargets {
                    fps_p95: 90.0,
                    wasm_size_bytes: 3 * 1024 * 1024, // 3 MB
                    particles: 200_000,
                    draw_calls: 5,
                    allocations_per_frame: 5,
                },
            ),
            "atc" => (
                WorldTargets {
                    fps_p95: 60.0,
                    wasm_size_bytes: 8 * 1024 * 1024,
                    particles: 0, // Not applicable
                    draw_calls: 50,
                    allocations_per_frame: 20,
                },
                WorldTargets {
                    fps_p95: 120.0,
                    wasm_size_bytes: 5 * 1024 * 1024,
                    particles: 0,
                    draw_calls: 30,
                    allocations_per_frame: 10,
                },
            ),
            "astro" => (
                WorldTargets {
                    fps_p95: 60.0,
                    wasm_size_bytes: 6 * 1024 * 1024,
                    particles: 1_000_000, // Stars
                    draw_calls: 20,
                    allocations_per_frame: 15,
                },
                WorldTargets {
                    fps_p95: 90.0,
                    wasm_size_bytes: 4 * 1024 * 1024,
                    particles: 10_000_000,
                    draw_calls: 10,
                    allocations_per_frame: 5,
                },
            ),
            _ => return Err(anyhow::anyhow!("Unknown world: {}", world)),
        };
        
        let scoreboard = WorldScoreboard {
            world: world.to_string(),
            current_metrics: WorldMetrics {
                fps_p95: None,
                wasm_size_bytes: None,
                particle_count: None,
                draw_calls: None,
                allocations_per_frame: None,
                crash_rate: None,
                stream_determinism: None,
                alert_accuracy: None,
                ui_latency_p95: None,
                orbit_error_km_per_day: None,
                camera_jitter_pixels: None,
            },
            current_targets,
            aspirational_targets,
            last_escalation: None,
            improvements_since_escalation: 0,
            quality_bar_history: vec![],
        };
        
        // Store initial scoreboard
        self.update_scoreboard(&scoreboard).await?;
        
        Ok(scoreboard)
    }

    async fn update_scoreboard(&self, scoreboard: &WorldScoreboard) -> Result<()> {
        let doc = serde_json::to_value(scoreboard)?;
        
        // Upsert scoreboard
        let query = format!(
            r#"
            UPSERT {{ world: "{}" }}
            INSERT @doc
            UPDATE @doc
            IN WorldScoreboards
            "#,
            scoreboard.world
        );
        
        self.akg_client.execute_with_params(&query, &serde_json::json!({ "doc": doc })).await?;
        
        Ok(())
    }

    async fn create_stretch_goals(&self, world: &str, scoreboard: &WorldScoreboard) -> Result<Vec<String>> {
        let mut goals = vec![];
        
        // Create aspirational FPS goal
        let fps_goal = format!(
            "Achieve {} FPS in {} world (current: {:.1})",
            scoreboard.aspirational_targets.fps_p95,
            world,
            scoreboard.current_targets.fps_p95
        );
        goals.push(fps_goal.clone());
        
        // Create WASM size goal
        let wasm_goal = format!(
            "Reduce WASM size to {} MB in {} world",
            scoreboard.aspirational_targets.wasm_size_bytes / (1024 * 1024),
            world
        );
        goals.push(wasm_goal.clone());
        
        // Store as improvement tasks in AKG
        for (idx, goal) in goals.iter().enumerate() {
            let task = serde_json::json!({
                "id": format!("{}_stretch_{}", world, idx),
                "world": world,
                "title": goal,
                "description": goal,
                "type": "stretch_goal",
                "priority": 6.0,
                "impact": 8.0,
                "effort": 10,
                "status": "ready",
                "created_at": Utc::now().to_rfc3339(),
            });
            
            self.akg_client.create_document("ImprovementQueue_V2", &task).await?;
        }
        
        Ok(goals)
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EscalationResult {
    pub escalated: bool,
    pub previous_targets: WorldTargets,
    pub new_targets: WorldTargets,
    pub stretch_goals_created: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct PerformanceStats {
    avg_fps: f64,
    avg_improvement: f64,
    sample_size: u32,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_world_targets_structure() {
        let targets = WorldTargets {
            fps_p95: 60.0,
            wasm_size_bytes: 5 * 1024 * 1024,
            particles: 100_000,
            draw_calls: 10,
            allocations_per_frame: 10,
        };
        
        assert_eq!(targets.fps_p95, 60.0);
        assert!(targets.wasm_size_bytes > 0);
    }
}
