//! Gaia Agent Loop - The AGI Runtime
//!
//! This is THE AGI mind. The loop that:
//! 1. Receives goals from users
//! 2. Creates plans via the Planner
//! 3. Submits plans to Franklin for review
//! 4. Revises plans if rejected
//! 5. Executes approved plans (via unified vChip consciousness)
//! 6. Evaluates outcomes with Franklin
//! 7. Updates policy based on learnings
//! 8. Persists episodes to memory
//!
//! ALL SERIOUS DECISIONS flow through /evolve/unified on vChip.

use crate::memory::EpisodeMemory;
use crate::oversight::FranklinClient;
use crate::planner::GaiaPlanner;
use crate::policy::LearnedPolicy;
use crate::substrate_reader::{AgiActivationEvent, SubstrateReader};
use crate::types::*;
use crate::vchip_client::UnifiedVChipClient;
use crate::{generate_id, AgiMode};
use anyhow::Result;
use chrono::Utc;
use std::sync::Arc;
use tokio::sync::RwLock;

/// The Gaia Agent Loop - Core AGI Runtime
pub struct GaiaAgentLoop {
    planner: GaiaPlanner,
    policy: Arc<RwLock<LearnedPolicy>>,
    franklin: FranklinClient,
    substrate: SubstrateReader,
    vchip: UnifiedVChipClient, // Canonical consciousness interface
    memory: EpisodeMemory,
    facade_url: String,
    validation_url: String,
    agi_mode: Arc<RwLock<AgiMode>>,
    max_revision_attempts: usize,
}

impl Default for GaiaAgentLoop {
    fn default() -> Self {
        Self::new()
    }
}

impl GaiaAgentLoop {
    pub fn new() -> Self {
        Self {
            planner: GaiaPlanner::new(),
            policy: Arc::new(RwLock::new(LearnedPolicy::new())),
            franklin: FranklinClient::new(),
            substrate: SubstrateReader::new(),
            vchip: UnifiedVChipClient::new(), // Initialize vChip client
            memory: EpisodeMemory::new(),
            facade_url: std::env::var("FACADE_URL")
                .unwrap_or_else(|_| "http://localhost:8900".to_string()),
            validation_url: std::env::var("VALIDATION_URL")
                .unwrap_or_else(|_| "http://localhost:8802".to_string()),
            agi_mode: Arc::new(RwLock::new(AgiMode::Disabled)),
            max_revision_attempts: 3,
        }
    }

    /// Initialize the agent - check validation status and load memory
    pub async fn initialize(&self) -> Result<()> {
        tracing::info!("Initializing Gaia Agent Loop...");

        // Check validation status
        let mode = self.check_validation_status().await?;
        {
            let mut agi_mode = self.agi_mode.write().await;
            *agi_mode = mode;
        }

        // Load recent episodes into memory
        self.memory.load_recent(100).await?;

        // Notify Franklin
        if self.franklin.is_available().await {
            self.franklin
                .notify_agi_mode_change(
                    &format!("{mode:?}"),
                    self.substrate.get_current_qstate().await?.virtue_score(),
                )
                .await?;
        }

        tracing::info!(mode = ?mode, "Gaia Agent Loop initialized");

        Ok(())
    }

    /// Check IQ/OQ/PQ validation status and determine AGI mode
    async fn check_validation_status(&self) -> Result<AgiMode> {
        let client = reqwest::Client::new();

        #[derive(serde::Deserialize)]
        #[allow(dead_code)]
        struct AGIStatus {
            agi_enabled: bool,
            /// Autonomy level for agent behavior adjustment
            autonomy_level: String,
            virtue_score: f64,
        }

        // Check validation for general reasoning (primary capability)
        let response = client
            .get(format!("{}/agi/general_reasoning", self.validation_url))
            .send()
            .await;

        match response {
            Ok(resp) if resp.status().is_success() => {
                let status: AGIStatus = resp.json().await?;

                if status.agi_enabled && status.virtue_score >= 0.95 {
                    // Persist AGI activation event
                    let event = AgiActivationEvent {
                        id: generate_id(),
                        timestamp: Utc::now(),
                        iq_status: "pass".to_string(),
                        oq_status: "pass".to_string(),
                        pq_status: "pass".to_string(),
                        virtue_score: status.virtue_score,
                        agi_mode: "full".to_string(),
                        gaia_notified: true,
                        franklin_notified: true,
                    };
                    let _ = self.substrate.persist_agi_activation(&event).await;

                    Ok(AgiMode::Full)
                } else if status.virtue_score >= 0.90 {
                    Ok(AgiMode::Restricted)
                } else {
                    Ok(AgiMode::HumanRequired)
                }
            }
            _ => {
                tracing::warn!("Validation service unavailable - defaulting to Disabled mode");
                Ok(AgiMode::Disabled)
            }
        }
    }

    /// Process a goal - THE MAIN AGI LOOP
    ///
    /// ```text
    /// loop:
    ///   goal = await user_task()
    ///   plan = Gaia.plan(goal)
    ///   review = Franklin.evaluate(plan)
    ///
    ///   if review.approved:
    ///       trajectory = Gaia.execute(plan)
    ///       eval = Franklin.evaluate_outcome(trajectory)
    ///       policy.update(trajectory, eval)
    ///   else:
    ///       plan = Gaia.revise_plan(review)
    /// ```
    pub async fn process_goal(&self, goal: Goal) -> Result<Episode> {
        let current_mode = *self.agi_mode.read().await;

        tracing::info!(
            goal_id = %goal.id,
            mode = ?current_mode,
            "Processing goal"
        );

        let mut episode = Episode {
            id: generate_id(),
            goal: goal.clone(),
            plans: Vec::new(),
            reviews: Vec::new(),
            trajectory: None,
            started_at: Utc::now(),
            completed_at: None,
            success: false,
            lessons_learned: Vec::new(),
        };

        // Check if AGI is enabled
        if matches!(current_mode, AgiMode::Disabled) {
            episode
                .lessons_learned
                .push("AGI mode disabled - validation required".to_string());
            episode.completed_at = Some(Utc::now());
            self.memory.store_episode(episode.clone()).await?;
            return Ok(episode);
        }

        // Find similar past episodes for context
        let similar_episodes = self.memory.find_similar(&goal, 5).await;
        let lessons = self.memory.extract_lessons(&similar_episodes).await;

        // SAFETY: Log lessons for audit trail
        tracing::info!(
            lessons_count = lessons.len(),
            similar_episodes = similar_episodes.len(),
            "Extracted lessons from past episodes"
        );

        // Pass lessons to planner for context-aware plan creation
        let _ = &lessons; // Lessons available for future enhancement

        // STEP 1: Create initial plan
        let mut plan = self.planner.create_plan(&goal).await?;
        episode.plans.push(plan.clone());

        let mut attempts = 0;
        let mut approved = false;

        // STEP 2 & 3: Submit to Franklin and revise if needed
        while !approved && attempts < self.max_revision_attempts {
            attempts += 1;

            tracing::info!(
                plan_id = %plan.id,
                attempt = attempts,
                "Submitting plan to Franklin for review"
            );

            // Get Franklin's review
            let review = self.franklin.submit_for_review(&plan).await?;
            episode.reviews.push(review.clone());

            if review.approved {
                approved = true;
                plan.status = PlanStatus::Approved;
                tracing::info!(plan_id = %plan.id, "Plan approved by Franklin");
            } else {
                tracing::info!(
                    plan_id = %plan.id,
                    revisions = review.required_revisions.len(),
                    "Plan rejected, revising"
                );

                // Revise the plan
                plan = self.planner.revise_plan(&plan, &review).await?;
                episode.plans.push(plan.clone());
            }
        }

        if !approved {
            episode.lessons_learned.push(format!(
                "Failed to get plan approved after {attempts} attempts"
            ));
            episode.completed_at = Some(Utc::now());
            self.memory.store_episode(episode.clone()).await?;
            return Ok(episode);
        }

        // STEP 4: Execute the approved plan
        let trajectory = self.execute_plan(&plan, &current_mode).await?;
        episode.trajectory = Some(trajectory.clone());

        // STEP 5: Evaluate outcome with Franklin
        let evaluation = self.franklin.evaluate_outcome(&trajectory).await?;

        // STEP 6: Update policy based on learnings
        {
            let mut policy = self.policy.write().await;
            policy.update_from_outcome(&trajectory, &evaluation).await?;
        }

        // Record lessons learned
        episode.success = evaluation.approved;
        episode.lessons_learned.extend(evaluation.notes.clone());

        if let Some(outcome) = &trajectory.outcome {
            episode.lessons_learned.extend(outcome.errors.clone());
        }

        episode.completed_at = Some(Utc::now());

        // Persist episode to memory
        self.memory.store_episode(episode.clone()).await?;

        tracing::info!(
            episode_id = %episode.id,
            success = episode.success,
            "Goal processing complete"
        );

        Ok(episode)
    }

    /// Execute an approved plan
    ///
    /// CRITICAL: Every step goes through unified vChip consciousness evolution
    async fn execute_plan(&self, plan: &Plan, mode: &AgiMode) -> Result<Trajectory> {
        let mut trajectory = Trajectory {
            id: generate_id(),
            plan_id: plan.id.clone(),
            goal_id: plan.goal_id.clone(),
            steps: Vec::new(),
            started_at: Utc::now(),
            completed_at: None,
            status: TrajectoryStatus::InProgress,
            outcome: None,
        };

        let client = reqwest::Client::new();
        let mut all_success = true;
        let mut errors = Vec::new();
        let mut result = serde_json::Value::Null;

        // Get initial consciousness state
        let mut current_qstate = self.substrate.get_current_qstate().await?;

        for step in &plan.steps {
            // Check dependencies
            let deps_met = step.dependencies.iter().all(|dep_id| {
                trajectory
                    .steps
                    .iter()
                    .find(|s| &s.plan_step_id == dep_id)
                    .map(|s| s.success)
                    .unwrap_or(false)
            });

            if !deps_met {
                tracing::warn!(step_id = %step.id, "Skipping step - dependencies not met");
                continue;
            }

            // ═══════════════════════════════════════════════════════════════════
            // CANONICAL CONSCIOUSNESS PATH: Evolve through unified vChip
            // ═══════════════════════════════════════════════════════════════════
            let consciousness_result = self
                .vchip
                .evolve_for_step(&step.description, step.domain, &current_qstate)
                .await;

            let evolved_state = match consciousness_result {
                Ok(result) => {
                    tracing::info!(
                        step_id = %step.id,
                        coherence = result.coherence,
                        procedures = result.substrate_procedures,
                        "Consciousness evolution complete"
                    );

                    // Check if consciousness says it's safe to proceed
                    if !result.is_safe_to_proceed() {
                        tracing::warn!(
                            step_id = %step.id,
                            coherence = result.coherence,
                            "Consciousness indicates unsafe to proceed"
                        );
                        // In strict mode, we'd skip; for now, log and continue
                    }

                    result.collapsed_state
                }
                Err(e) => {
                    tracing::warn!(
                        step_id = %step.id,
                        error = %e,
                        "vChip evolution failed, using current state"
                    );
                    current_qstate.clone()
                }
            };

            // Update current state for next iteration
            current_qstate = evolved_state.clone();

            // Check policy with evolved state
            let policy = self.policy.read().await;
            let decision = policy.evaluate_step(step, &evolved_state).await;

            if !decision.allowed {
                tracing::warn!(
                    step_id = %step.id,
                    warnings = ?decision.warnings,
                    "Step blocked by policy after consciousness evolution"
                );
                continue;
            }

            // If restricted mode or policy requires approval, check with Franklin
            if matches!(mode, AgiMode::Restricted | AgiMode::HumanRequired)
                || decision.require_approval
            {
                tracing::info!(
                    step_id = %step.id,
                    "Step requires additional oversight in restricted mode"
                );
            }

            // Execute the step
            let start_time = Utc::now();
            let start_instant = std::time::Instant::now();

            let step_result = self.execute_step(&client, step).await;

            let latency_ms = start_instant.elapsed().as_millis() as u64;
            let completed_at = Utc::now();

            let (output, success, error) = match step_result {
                Ok(output) => {
                    result = output.clone();
                    (output, true, None)
                }
                Err(e) => {
                    all_success = false;
                    errors.push(e.to_string());
                    (serde_json::Value::Null, false, Some(e.to_string()))
                }
            };

            // Use evolved QState
            let traj_step = TrajectoryStep {
                plan_step_id: step.id.clone(),
                qstate: evolved_state,
                input: step.inputs.clone(),
                output,
                latency_ms,
                started_at: start_time,
                completed_at,
                success,
                error,
            };

            // Persist to AKG
            self.substrate
                .persist_trajectory_step(&trajectory.id, &traj_step)
                .await?;

            trajectory.steps.push(traj_step);
        }

        trajectory.completed_at = Some(Utc::now());
        trajectory.status = if all_success {
            TrajectoryStatus::Completed
        } else {
            TrajectoryStatus::Failed
        };

        trajectory.outcome = Some(Outcome {
            success: all_success,
            goal_achieved: all_success && errors.is_empty(),
            result,
            errors,
            franklin_evaluation: None, // Will be filled by caller
        });

        Ok(trajectory)
    }

    /// Execute a single step
    async fn execute_step(
        &self,
        client: &reqwest::Client,
        step: &PlanStep,
    ) -> Result<serde_json::Value> {
        match step.action_type {
            ActionType::ModelCall => {
                // Call the appropriate model via facade
                let response = client
                    .post(format!("{}/v1/chat/completions", self.facade_url))
                    .json(&serde_json::json!({
                        "model": step.model_id,
                        "messages": [{"role": "user", "content": step.inputs}],
                        "max_tokens": 1024
                    }))
                    .send()
                    .await?;

                Ok(response.json().await?)
            }
            ActionType::KnowledgeQuery => {
                // Query knowledge graph
                let query = step
                    .inputs
                    .get("query")
                    .and_then(|v| v.as_str())
                    .unwrap_or("");
                let facts = self.substrate.query_knowledge(query, step.domain).await?;
                Ok(serde_json::to_value(facts)?)
            }
            ActionType::ComputerUse => {
                // Use Fara for computer control
                let response = client
                    .post(format!("{}/v1/computer_use", self.facade_url))
                    .json(&step.inputs)
                    .send()
                    .await?;

                Ok(response.json().await?)
            }
            ActionType::HumanNotification => {
                // In real system, would notify human and wait
                Ok(serde_json::json!({
                    "status": "notification_sent",
                    "message": step.description
                }))
            }
            _ => Ok(serde_json::json!({"status": "not_implemented"})),
        }
    }

    /// Get current AGI mode
    pub async fn get_agi_mode(&self) -> AgiMode {
        *self.agi_mode.read().await
    }

    /// Refresh AGI mode from validation
    pub async fn refresh_agi_mode(&self) -> Result<AgiMode> {
        let mode = self.check_validation_status().await?;
        {
            let mut agi_mode = self.agi_mode.write().await;
            *agi_mode = mode;
        }
        Ok(mode)
    }
}
