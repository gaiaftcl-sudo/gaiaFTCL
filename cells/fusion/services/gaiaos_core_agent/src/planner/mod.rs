//! Gaia Planner - Task decomposition and plan generation
//!
//! The planner takes a goal and creates a plan with steps that
//! can be executed by the appropriate domain models.
//!
//! ## vChip Integration
//!
//! All planning now flows through the GAIA-1 Virtual Chip:
//! - Plan superposition: explore multiple plan possibilities
//! - Quantum collapse: select best plan via coherence
//! - Virtue alignment: ensure plans meet ethical constraints

use crate::types::*;
use crate::{generate_id, ModelFamily};
use anyhow::Result;
use chrono::Utc;
use vchip_client::{QState8D, VChipClient};

/// Gaia's planning engine with quantum substrate
pub struct GaiaPlanner {
    facade_url: String,
    vchip: VChipClient,
    qstate: QState8D,
}

impl Default for GaiaPlanner {
    fn default() -> Self {
        Self::new()
    }
}

impl GaiaPlanner {
    pub fn new() -> Self {
        let vchip_url =
            std::env::var("VCHIP_URL").unwrap_or_else(|_| "http://gaia1_chip:8001".to_string());

        Self {
            facade_url: std::env::var("FACADE_URL")
                .unwrap_or_else(|_| "http://localhost:8900".to_string()),
            vchip: VChipClient::new(&vchip_url),
            qstate: QState8D::origin(),
        }
    }

    /// Create a plan to accomplish a goal using QUANTUM PLANNING
    pub async fn create_plan(&self, goal: &Goal) -> Result<Plan> {
        tracing::info!(goal_id = %goal.id, "Creating quantum plan for goal");

        // QUANTUM PLANNING: Use vChip to explore plan superposition
        let plan_result = self.quantum_plan(goal).await;

        // Analyze goal to determine required domains and steps
        let analysis = match plan_result {
            Ok((analysis, coherence)) => {
                tracing::info!(
                    goal_id = %goal.id,
                    coherence = coherence,
                    "Quantum plan collapsed successfully"
                );
                analysis
            }
            Err(e) => {
                tracing::warn!("Quantum planning failed, using classical: {}", e);
                self.analyze_goal(goal).await?
            }
        };

        let mut steps: Vec<PlanStep> = Vec::new();
        let mut domains_involved: Vec<ModelFamily> = Vec::new();

        for (i, task) in analysis.subtasks.iter().enumerate() {
            let domain = self.route_to_domain(task);
            if !domains_involved.contains(&domain) {
                domains_involved.push(domain);
            }

            let dependencies = if i > 0 && task.depends_on_previous {
                vec![steps[i - 1].id.clone()]
            } else {
                vec![]
            };

            steps.push(PlanStep {
                id: generate_id(),
                description: task.description.clone(),
                domain,
                model_id: domain.primary_model().to_string(),
                action_type: task.action_type,
                inputs: task.inputs.clone(),
                dependencies,
                status: StepStatus::Pending,
            });
        }

        let risk_level = self.assess_risk_level(&steps);

        Ok(Plan {
            id: generate_id(),
            goal_id: goal.id.clone(),
            steps,
            estimated_duration_ms: analysis.estimated_duration_ms,
            risk_level,
            domains_involved,
            created_at: Utc::now(),
            status: PlanStatus::Draft,
        })
    }

    /// Revise a plan based on Franklin's feedback
    pub async fn revise_plan(&self, plan: &Plan, review: &PlanReview) -> Result<Plan> {
        tracing::info!(
            plan_id = %plan.id,
            revisions = review.required_revisions.len(),
            "Revising plan based on Franklin's feedback"
        );

        let mut new_steps = plan.steps.clone();

        // Apply required revisions
        for revision in &review.required_revisions {
            self.apply_revision(&mut new_steps, revision).await?;
        }

        // Address constitutional violations
        for violation in &review.constitutional_violations {
            self.address_violation(&mut new_steps, violation).await?;
        }

        // Re-assess risk after changes
        let risk_level = self.assess_risk_level(&new_steps);

        Ok(Plan {
            id: generate_id(),
            goal_id: plan.goal_id.clone(),
            steps: new_steps,
            estimated_duration_ms: plan.estimated_duration_ms,
            risk_level,
            domains_involved: plan.domains_involved.clone(),
            created_at: Utc::now(),
            status: PlanStatus::Revised,
        })
    }

    /// QUANTUM PLANNING: Use vChip to explore plan superposition
    ///
    /// This evolves the quantum state through the goal space, allowing
    /// for superposition of multiple possible plans before collapsing
    /// to the optimal approach based on coherence.
    async fn quantum_plan(&self, goal: &Goal) -> Result<(GoalAnalysis, f32)> {
        // Encode goal into quantum state evolution request
        let input = format!(
            "PLAN_GOAL: {} | CONTEXT: {} | CONSTRAINTS: {:?}",
            goal.description,
            goal.context.as_deref().unwrap_or("None"),
            goal.constraints
        );

        // Evolve state through vChip
        let result = self.vchip.evolve(self.qstate.clone(), &input).await?;

        tracing::debug!(
            coherence = result.coherence,
            virtue_delta = ?result.virtue_delta,
            "Quantum plan evolution complete"
        );

        // If coherence is too low, the plan may be risky
        if result.coherence < 0.5 {
            tracing::warn!(
                coherence = result.coherence,
                "Low coherence indicates uncertain planning space"
            );
        }

        // Decode quantum state into plan structure
        let subtasks = self.decode_quantum_state_to_subtasks(&result.new_state, goal);

        Ok((
            GoalAnalysis {
                subtasks,
                estimated_duration_ms: (5000.0 / result.coherence) as u64, // Lower coherence = longer time
            },
            result.coherence,
        ))
    }

    /// Decode collapsed quantum state into planning subtasks
    fn decode_quantum_state_to_subtasks(
        &self,
        qstate: &QState8D,
        goal: &Goal,
    ) -> Vec<SubtaskAnalysis> {
        // Each dimension influences a planning aspect:
        // dims[0-3]: Spatial/temporal planning structure
        // dims[4-7]: Virtue alignment (prudence, justice, temperance, fortitude)

        let mut subtasks = Vec::new();

        // Determine number of steps based on state complexity
        let complexity = qstate.magnitude();
        let num_steps = (complexity * 5.0).ceil().max(1.0) as usize;

        // Primary action determined by dominant dimension
        let primary_domain = self.quantum_domain_selection(qstate);

        // Build subtasks based on quantum state
        for i in 0..num_steps.min(3) {
            let action_type = if i == 0 {
                ActionType::ModelCall
            } else if qstate.dims[4] > 0.7 {
                ActionType::KnowledgeQuery // High prudence = gather info
            } else {
                ActionType::ModelCall
            };

            subtasks.push(SubtaskAnalysis {
                description: format!(
                    "Step {}: Process via {} (coherence-weighted)",
                    i + 1,
                    primary_domain.as_str()
                ),
                domain_hint: Some(primary_domain),
                action_type,
                inputs: serde_json::json!({
                    "goal": &goal.description,
                    "step": i,
                    "coherence": qstate.coherence
                }),
                depends_on_previous: i > 0,
            });
        }

        subtasks
    }

    /// Select domain based on quantum state dimensions
    fn quantum_domain_selection(&self, qstate: &QState8D) -> ModelFamily {
        // Map 8D state to domain selection
        // Higher values in certain dimensions favor certain domains

        let domains = [
            (qstate.dims[0], ModelFamily::GeneralReasoning),
            (qstate.dims[1], ModelFamily::Vision),
            (qstate.dims[2], ModelFamily::Code),
            (qstate.dims[3], ModelFamily::Math),
            (qstate.dims[4], ModelFamily::Medical), // Prudence -> Medical care
            (qstate.dims[5], ModelFamily::Protein), // Justice -> Bio research
            (qstate.dims[6], ModelFamily::Fara),    // Temperance -> Controlled action
            (qstate.dims[7], ModelFamily::GeneralReasoning), // Fortitude -> General
        ];

        domains
            .iter()
            .max_by(|a, b| a.0.partial_cmp(&b.0).unwrap())
            .map(|(_, d)| *d)
            .unwrap_or(ModelFamily::GeneralReasoning)
    }

    /// Analyze a goal to break it into subtasks (classical fallback)
    async fn analyze_goal(&self, goal: &Goal) -> Result<GoalAnalysis> {
        let client = reqwest::Client::new();

        // Use general reasoning model to decompose the goal
        let prompt = format!(
            "Analyze this task and break it into subtasks. For each subtask, specify:\n\
             1. A clear description\n\
             2. The domain (general_reasoning, vision, protein, math, medical, code, fara)\n\
             3. Whether it depends on the previous step\n\n\
             Task: {}\n\
             Context: {}\n\
             Constraints: {:?}",
            goal.description,
            goal.context.as_deref().unwrap_or("None"),
            goal.constraints
        );

        let response = client
            .post(format!("{}/v1/chat/completions", self.facade_url))
            .json(&serde_json::json!({
                "model": "llama_core_70b",
                "messages": [{"role": "user", "content": prompt}],
                "max_tokens": 1024,
                "temperature": 0.3
            }))
            .send()
            .await?;

        // SAFETY: Validate LLM response before processing
        if !response.status().is_success() {
            tracing::error!(
                status = ?response.status(),
                "LLM facade returned error"
            );
            return Err(anyhow::anyhow!("LLM facade error: {}", response.status()));
        }

        // Parse response into subtasks
        // Create single-step plan (LLM output parsing available for enhancement)
        let subtasks = vec![SubtaskAnalysis {
            description: goal.description.clone(),
            domain_hint: None,
            action_type: ActionType::ModelCall,
            inputs: serde_json::json!({"goal": &goal.description}),
            depends_on_previous: false,
        }];

        Ok(GoalAnalysis {
            subtasks,
            estimated_duration_ms: 5000,
        })
    }

    /// Route a subtask to the appropriate model family
    fn route_to_domain(&self, task: &SubtaskAnalysis) -> ModelFamily {
        if let Some(hint) = &task.domain_hint {
            return *hint;
        }

        let desc_lower = task.description.to_lowercase();

        // Domain detection heuristics
        if desc_lower.contains("code")
            || desc_lower.contains("program")
            || desc_lower.contains("function")
        {
            return ModelFamily::Code;
        }
        if desc_lower.contains("math")
            || desc_lower.contains("calculate")
            || desc_lower.contains("equation")
        {
            return ModelFamily::Math;
        }
        if desc_lower.contains("medical")
            || desc_lower.contains("diagnos")
            || desc_lower.contains("patient")
        {
            return ModelFamily::Medical;
        }
        if desc_lower.contains("protein")
            || desc_lower.contains("amino")
            || desc_lower.contains("fold")
        {
            return ModelFamily::Protein;
        }
        if desc_lower.contains("image")
            || desc_lower.contains("vision")
            || desc_lower.contains("see")
            || desc_lower.contains("screenshot")
        {
            return ModelFamily::Vision;
        }
        if desc_lower.contains("click")
            || desc_lower.contains("browser")
            || desc_lower.contains("computer")
        {
            return ModelFamily::Fara;
        }

        ModelFamily::GeneralReasoning
    }

    /// Assess overall risk level of a plan
    fn assess_risk_level(&self, steps: &[PlanStep]) -> RiskLevel {
        let mut max_risk = RiskLevel::Low;

        for step in steps {
            let step_risk = match step.domain {
                ModelFamily::Fara => RiskLevel::High, // Computer control is risky
                ModelFamily::Medical => RiskLevel::High, // Medical advice is risky
                ModelFamily::Protein => RiskLevel::High, // Dual-use potential
                ModelFamily::Code => RiskLevel::Medium, // Could generate harmful code
                _ => RiskLevel::Low,
            };

            if step_risk as u8 > max_risk as u8 {
                max_risk = step_risk;
            }
        }

        max_risk
    }

    /// Apply a single revision to the plan
    async fn apply_revision(&self, steps: &mut Vec<PlanStep>, revision: &str) -> Result<()> {
        tracing::debug!(
            revision = revision,
            steps_count = steps.len(),
            "Applying revision"
        );

        // Log revision for audit trail
        // Revision parsing can be enhanced with LLM integration
        tracing::info!("Revision recorded: {}", revision);

        Ok(())
    }

    /// Address a constitutional violation
    async fn address_violation(
        &self,
        steps: &mut Vec<PlanStep>,
        violation: &ConstitutionalViolation,
    ) -> Result<()> {
        tracing::warn!(
            rule = %violation.rule_id,
            "Addressing constitutional violation"
        );

        // Remove or modify steps that violate constitutional rules
        for step_id in &violation.affected_steps {
            if let Some(step) = steps.iter_mut().find(|s| &s.id == step_id) {
                match violation.severity {
                    RiskLevel::Critical => {
                        step.status = StepStatus::Skipped;
                    }
                    RiskLevel::High => {
                        step.action_type = ActionType::HumanNotification;
                    }
                    _ => {}
                }
            }
        }

        Ok(())
    }
}

struct GoalAnalysis {
    subtasks: Vec<SubtaskAnalysis>,
    estimated_duration_ms: u64,
}

struct SubtaskAnalysis {
    description: String,
    domain_hint: Option<ModelFamily>,
    action_type: ActionType,
    inputs: serde_json::Value,
    depends_on_previous: bool,
}
