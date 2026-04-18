//! Main teacher harvester - orchestrates the harvest pipeline

use crate::projector_bridge::ProjectorBridge;
use crate::{HarvestConfig, HarvestDb, Mission};
use anyhow::Result;
use log::{error, info};

/// Teacher harvester - runs missions against teacher models
pub struct TeacherHarvester {
    config: HarvestConfig,
    db: HarvestDb,
    projector: ProjectorBridge,
}

impl TeacherHarvester {
    /// Create a new harvester
    pub fn new(config: HarvestConfig, db: HarvestDb) -> Self {
        TeacherHarvester {
            config,
            db,
            projector: ProjectorBridge::new(),
        }
    }

    /// Run a single mission for a teacher
    pub fn run_mission(&mut self, teacher_id: &str, mission: &Mission) -> Result<String> {
        // Look up teacher in config
        let (domain, _projector_profile, teacher) = self
            .config
            .get_teacher(teacher_id)
            .ok_or_else(|| anyhow::anyhow!("Teacher not found: {teacher_id}"))?;

        info!(
            "Starting harvest: teacher={}, mission={}, domain={}",
            teacher_id, mission.id, domain
        );

        // Create episode
        let episode_id = self.db.create_episode(
            teacher_id,
            &teacher.name,
            domain,
            &mission.id,
            &mission.task_prompt,
        );

        info!("Created episode: {episode_id}");

        // Call teacher model (simulation mode until model endpoint available)
        let steps = self.simulate_teacher_run(mission);

        // Process each step
        for (index, step_data) in steps.iter().enumerate() {
            let step_id = self.db.add_step(
                &episode_id,
                &step_data.input,
                &step_data.output,
                step_data.action_type.as_deref(),
                step_data.tool_call.clone(),
                step_data.context.clone(),
            );

            if let Some(step_id) = step_id {
                let idx = index as u32;

                // Project to QState8 based on domain
                let qstate = match domain {
                    "computer_use" => {
                        self.projector.project_fara_step(
                            &step_data.output,
                            idx,
                            step_data.action_type.as_deref().unwrap_or("wait"),
                            0,
                            0, // x, y coordinates
                            Some(&step_data.output),
                            None,
                        )
                    }
                    "chemistry" => self.projector.project_chemistry_step(&step_data.input, idx),
                    "medical" => self.projector.project_medical_step(
                        &step_data.input,
                        &step_data.output,
                        0.5,
                        idx,
                    ),
                    "math" => {
                        self.projector
                            .project_math_step(&step_data.input, &step_data.output, idx)
                    }
                    "galaxy" => self.projector.project_galaxy_step(&step_data.input, idx),
                    "code" => self
                        .projector
                        .project_code_step(&step_data.output, 10, 1, idx),
                    "world_models" => {
                        self.projector
                            .project_world_model_step(&step_data.output, 5, idx)
                    }
                    "vision" => self.projector.project_vision_step(&step_data.input, 3, idx),
                    "protein" => self.projector.project_protein_step(&step_data.input, idx),
                    _ => self.projector.project_general_turn(
                        "assistant",
                        &step_data.output,
                        if step_data.tool_call.is_some() { 1 } else { 0 },
                        idx,
                    ),
                };

                // Store QState8
                self.db
                    .add_qstate(&step_id, teacher_id, domain, qstate.amps);

                info!(
                    "[HARVEST] step={} qstate=[{:.3}, {:.3}, {:.3}, {:.3}, {:.3}, {:.3}, {:.3}, {:.3}]",
                    step_id,
                    qstate.amps[0], qstate.amps[1], qstate.amps[2], qstate.amps[3],
                    qstate.amps[4], qstate.amps[5], qstate.amps[6], qstate.amps[7]
                );
            }
        }

        // Complete episode
        self.db.complete_episode(&episode_id, true);
        info!(
            "Completed episode: {} with {} steps",
            episode_id,
            steps.len()
        );

        Ok(episode_id)
    }

    /// Run all missions for a domain
    pub fn harvest_domain(&mut self, domain: &str) -> Result<Vec<String>> {
        let domain_config = self
            .config
            .teachers_for_domain(domain)
            .ok_or_else(|| anyhow::anyhow!("Domain not found: {domain}"))?
            .clone();

        let missions = crate::mission::builtin::for_domain(domain);
        let mut episode_ids = Vec::new();

        for teacher in &domain_config.teachers {
            info!("Harvesting from teacher: {}", teacher.id);

            for mission in &missions {
                match self.run_mission(&teacher.id, mission) {
                    Ok(episode_id) => {
                        episode_ids.push(episode_id);
                    }
                    Err(e) => {
                        error!("Failed mission {} for {}: {}", mission.id, teacher.id, e);
                    }
                }
            }
        }

        Ok(episode_ids)
    }

    /// Get database reference
    pub fn db(&self) -> &HarvestDb {
        &self.db
    }

    /// Get mutable database reference
    pub fn db_mut(&mut self) -> &mut HarvestDb {
        &mut self.db
    }

    /// Save database to disk
    pub fn save(&self) -> Result<()> {
        self.db.save()
    }

    /// Simulate a teacher run (placeholder for real inference)
    fn simulate_teacher_run(&self, mission: &Mission) -> Vec<SimulatedStep> {
        // Generate mock steps based on mission
        let step_count = mission.expected_steps.unwrap_or(5) as usize;

        (0..step_count)
            .map(|i| SimulatedStep {
                input: format!("Step {} input for: {}", i, mission.task_prompt),
                output: format!("Step {i} output: Analyzing task..."),
                action_type: Some(match i % 4 {
                    0 => "navigate".to_string(),
                    1 => "click".to_string(),
                    2 => "type".to_string(),
                    _ => "wait".to_string(),
                }),
                tool_call: None,
                context: serde_json::json!({
                    "step_index": i,
                    "mission_id": mission.id,
                }),
            })
            .collect()
    }
}

struct SimulatedStep {
    input: String,
    output: String,
    action_type: Option<String>,
    tool_call: Option<serde_json::Value>,
    context: serde_json::Value,
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    #[test]
    fn test_harvester_creation() {
        let registry_path = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .parent()
            .unwrap()
            .parent()
            .unwrap()
            .join("config/agi_model_registry.json");

        if registry_path.exists() {
            let config = HarvestConfig::from_registry(&registry_path).unwrap();
            let db = HarvestDb::new("/tmp/test_harvest.db");
            let harvester = TeacherHarvester::new(config, db);

            // Should have config loaded
            assert!(!harvester.config.teachers_by_domain.is_empty());
        }
    }
}
