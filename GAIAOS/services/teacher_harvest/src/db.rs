//! Harvest Database - Stores teacher outputs for distillation
//!
//! This is a STAGING AREA, not the production AKG.
//! Data here feeds into GaiaLM training, then gets archived or deleted.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::Path;
use std::fs;
use anyhow::Result;
use uuid::Uuid;

/// Episode record - one task/mission run
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HarvestEpisode {
    pub episode_id: String,
    pub teacher_model_id: String,
    pub family: String,
    pub domain: String,
    pub mission_id: String,
    pub task_spec: String,
    pub status: EpisodeStatus,
    pub step_count: u32,
    pub created_at: DateTime<Utc>,
    pub completed_at: Option<DateTime<Utc>>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum EpisodeStatus {
    Running,
    Completed,
    Failed,
    Cancelled,
}

/// Step record - one inference step within an episode
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HarvestStep {
    pub step_id: String,
    pub episode_id: String,
    pub index: u32,
    pub raw_input: String,
    pub raw_output: String,
    pub action_type: Option<String>,
    pub tool_call: Option<serde_json::Value>,
    pub projection_context: serde_json::Value,
    pub created_at: DateTime<Utc>,
}

/// QState8 record for a step
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HarvestQState {
    pub qstate_id: String,
    pub step_id: String,
    pub teacher_model_id: String,
    pub family: String,
    pub amp0: f32,
    pub amp1: f32,
    pub amp2: f32,
    pub amp3: f32,
    pub amp4: f32,
    pub amp5: f32,
    pub amp6: f32,
    pub amp7: f32,
    pub norm_error: f32,
    pub virtue_annotations: Option<serde_json::Value>,
    pub created_at: DateTime<Utc>,
}

impl HarvestQState {
    pub fn amps(&self) -> [f32; 8] {
        [self.amp0, self.amp1, self.amp2, self.amp3, 
         self.amp4, self.amp5, self.amp6, self.amp7]
    }
    
    pub fn is_normalized(&self, tolerance: f32) -> bool {
        self.norm_error.abs() < tolerance
    }
}

/// In-memory harvest database (JSON file backend)
/// For production, replace with ArangoDB or similar
pub struct HarvestDb {
    pub episodes: HashMap<String, HarvestEpisode>,
    pub steps: HashMap<String, HarvestStep>,
    pub qstates: HashMap<String, HarvestQState>,
    db_path: String,
}

impl HarvestDb {
    /// Create new empty database
    pub fn new(db_path: &str) -> Self {
        HarvestDb {
            episodes: HashMap::new(),
            steps: HashMap::new(),
            qstates: HashMap::new(),
            db_path: db_path.to_string(),
        }
    }
    
    /// Load from disk
    pub fn load(db_path: &str) -> Result<Self> {
        let path = Path::new(db_path);
        
        if !path.exists() {
            return Ok(Self::new(db_path));
        }
        
        let content = fs::read_to_string(path)?;
        let data: HarvestDbData = serde_json::from_str(&content)?;
        
        Ok(HarvestDb {
            episodes: data.episodes.into_iter().map(|e| (e.episode_id.clone(), e)).collect(),
            steps: data.steps.into_iter().map(|s| (s.step_id.clone(), s)).collect(),
            qstates: data.qstates.into_iter().map(|q| (q.qstate_id.clone(), q)).collect(),
            db_path: db_path.to_string(),
        })
    }
    
    /// Save to disk
    pub fn save(&self) -> Result<()> {
        let path = Path::new(&self.db_path);
        
        // Ensure parent directory exists
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent)?;
        }
        
        let data = HarvestDbData {
            episodes: self.episodes.values().cloned().collect(),
            steps: self.steps.values().cloned().collect(),
            qstates: self.qstates.values().cloned().collect(),
        };
        
        let content = serde_json::to_string_pretty(&data)?;
        fs::write(path, content)?;
        
        Ok(())
    }
    
    /// Create a new episode
    pub fn create_episode(
        &mut self,
        teacher_model_id: &str,
        family: &str,
        domain: &str,
        mission_id: &str,
        task_spec: &str,
    ) -> String {
        let episode_id = format!("ep_{}", &Uuid::new_v4().to_string().replace("-", "")[..12]);
        
        let episode = HarvestEpisode {
            episode_id: episode_id.clone(),
            teacher_model_id: teacher_model_id.to_string(),
            family: family.to_string(),
            domain: domain.to_string(),
            mission_id: mission_id.to_string(),
            task_spec: task_spec.to_string(),
            status: EpisodeStatus::Running,
            step_count: 0,
            created_at: Utc::now(),
            completed_at: None,
        };
        
        self.episodes.insert(episode_id.clone(), episode);
        episode_id
    }
    
    /// Add a step to an episode
    pub fn add_step(
        &mut self,
        episode_id: &str,
        raw_input: &str,
        raw_output: &str,
        action_type: Option<&str>,
        tool_call: Option<serde_json::Value>,
        projection_context: serde_json::Value,
    ) -> Option<String> {
        let episode = self.episodes.get_mut(episode_id)?;
        
        let step_id = format!("step_{}", &Uuid::new_v4().to_string().replace("-", "")[..12]);
        let index = episode.step_count;
        episode.step_count += 1;
        
        let step = HarvestStep {
            step_id: step_id.clone(),
            episode_id: episode_id.to_string(),
            index,
            raw_input: raw_input.to_string(),
            raw_output: raw_output.to_string(),
            action_type: action_type.map(|s| s.to_string()),
            tool_call,
            projection_context,
            created_at: Utc::now(),
        };
        
        self.steps.insert(step_id.clone(), step);
        Some(step_id)
    }
    
    /// Add QState8 for a step
    pub fn add_qstate(
        &mut self,
        step_id: &str,
        teacher_model_id: &str,
        family: &str,
        amps: [f32; 8],
    ) -> String {
        let norm_sq: f32 = amps.iter().map(|a| a * a).sum();
        let norm_error = (norm_sq - 1.0).abs();
        
        let qstate_id = format!("qs_{}", &Uuid::new_v4().to_string().replace("-", "")[..12]);
        
        let qstate = HarvestQState {
            qstate_id: qstate_id.clone(),
            step_id: step_id.to_string(),
            teacher_model_id: teacher_model_id.to_string(),
            family: family.to_string(),
            amp0: amps[0],
            amp1: amps[1],
            amp2: amps[2],
            amp3: amps[3],
            amp4: amps[4],
            amp5: amps[5],
            amp6: amps[6],
            amp7: amps[7],
            norm_error,
            virtue_annotations: None,
            created_at: Utc::now(),
        };
        
        self.qstates.insert(qstate_id.clone(), qstate);
        qstate_id
    }
    
    /// Complete an episode
    pub fn complete_episode(&mut self, episode_id: &str, success: bool) {
        if let Some(episode) = self.episodes.get_mut(episode_id) {
            episode.status = if success { EpisodeStatus::Completed } else { EpisodeStatus::Failed };
            episode.completed_at = Some(Utc::now());
        }
    }
    
    /// Get statistics
    pub fn stats(&self) -> HarvestStats {
        let mut by_teacher: HashMap<String, (u64, u64)> = HashMap::new();
        
        for episode in self.episodes.values() {
            let entry = by_teacher.entry(episode.teacher_model_id.clone()).or_insert((0, 0));
            entry.0 += 1;
            entry.1 += episode.step_count as u64;
        }
        
        let completed = self.episodes.values()
            .filter(|e| e.status == EpisodeStatus::Completed)
            .count() as u64;
        
        let normalized_qstates = self.qstates.values()
            .filter(|q| q.is_normalized(0.001))
            .count() as u64;
        
        HarvestStats {
            total_episodes: self.episodes.len() as u64,
            completed_episodes: completed,
            total_steps: self.steps.len() as u64,
            total_qstates: self.qstates.len() as u64,
            normalized_qstates,
            by_teacher,
        }
    }
    
    /// Get all steps for an episode
    pub fn steps_for_episode(&self, episode_id: &str) -> Vec<&HarvestStep> {
        let mut steps: Vec<_> = self.steps.values()
            .filter(|s| s.episode_id == episode_id)
            .collect();
        steps.sort_by_key(|s| s.index);
        steps
    }
    
    /// Get QState for a step
    pub fn qstate_for_step(&self, step_id: &str) -> Option<&HarvestQState> {
        self.qstates.values().find(|q| q.step_id == step_id)
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct HarvestDbData {
    episodes: Vec<HarvestEpisode>,
    steps: Vec<HarvestStep>,
    qstates: Vec<HarvestQState>,
}

#[derive(Debug, Clone)]
pub struct HarvestStats {
    pub total_episodes: u64,
    pub completed_episodes: u64,
    pub total_steps: u64,
    pub total_qstates: u64,
    pub normalized_qstates: u64,
    pub by_teacher: HashMap<String, (u64, u64)>, // (episodes, steps)
}

impl std::fmt::Display for HarvestStats {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        writeln!(f, "═══════════════════════════════════════════")?;
        writeln!(f, "📊 HARVEST DATABASE STATISTICS")?;
        writeln!(f, "═══════════════════════════════════════════")?;
        writeln!(f, "  Episodes:     {} ({} completed)", self.total_episodes, self.completed_episodes)?;
        writeln!(f, "  Steps:        {}", self.total_steps)?;
        writeln!(f, "  QState8s:     {} ({} normalized)", self.total_qstates, self.normalized_qstates)?;
        writeln!(f)?;
        writeln!(f, "By Teacher:")?;
        for (teacher, (eps, steps)) in &self.by_teacher {
            writeln!(f, "  • {teacher}: {eps} episodes, {steps} steps")?;
        }
        writeln!(f, "═══════════════════════════════════════════")?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_harvest_db_operations() {
        let mut db = HarvestDb::new("/tmp/test_harvest.db");
        
        // Create episode
        let episode_id = db.create_episode(
            "fara_7b_teacher",
            "computer_use",
            "computer_use",
            "test_mission",
            "Open browser and search for cats",
        );
        
        // Add steps
        let step1_id = db.add_step(
            &episode_id,
            "Open browser",
            "Browser opened",
            Some("navigate"),
            None,
            serde_json::json!({"action": "navigate"}),
        ).unwrap();
        
        let step2_id = db.add_step(
            &episode_id,
            "Search for cats",
            "Search results displayed",
            Some("type"),
            None,
            serde_json::json!({"action": "type", "text": "cats"}),
        ).unwrap();
        
        // Add QState8s
        let amps = [0.35, 0.35, 0.35, 0.35, 0.35, 0.35, 0.35, 0.35];
        db.add_qstate(&step1_id, "fara_7b_teacher", "computer_use", amps);
        db.add_qstate(&step2_id, "fara_7b_teacher", "computer_use", amps);
        
        // Complete episode
        db.complete_episode(&episode_id, true);
        
        // Check stats
        let stats = db.stats();
        assert_eq!(stats.total_episodes, 1);
        assert_eq!(stats.completed_episodes, 1);
        assert_eq!(stats.total_steps, 2);
        assert_eq!(stats.total_qstates, 2);
    }
    
    #[test]
    fn test_qstate_normalization_check() {
        // Normalized: sum of squares = 1
        let normalized = HarvestQState {
            qstate_id: "test".to_string(),
            step_id: "step".to_string(),
            teacher_model_id: "teacher".to_string(),
            family: "test".to_string(),
            amp0: 0.5,
            amp1: 0.5,
            amp2: 0.5,
            amp3: 0.5,
            amp4: 0.0,
            amp5: 0.0,
            amp6: 0.0,
            amp7: 0.0,
            norm_error: 0.0,
            virtue_annotations: None,
            created_at: Utc::now(),
        };
        
        // Sum of squares = 0.25 * 4 = 1.0
        assert!(normalized.is_normalized(0.001));
    }
}

