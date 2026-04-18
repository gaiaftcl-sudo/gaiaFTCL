//! Data loading and batch creation for distillation training

use teacher_harvest::HarvestDb;
use serde::{Deserialize, Serialize};
use std::path::Path;
use anyhow::Result;
use rand::seq::SliceRandom;
use rand::SeedableRng;
use rand::rngs::StdRng;

/// A single training example
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TrainingExample {
    /// Unique ID for this example
    pub id: String,
    
    /// Episode this came from
    pub episode_id: String,
    
    /// Step index within episode
    pub step_index: u32,
    
    /// Input: task description + observation
    pub input_text: String,
    
    /// Input: previous actions (short history)
    pub history: Vec<String>,
    
    /// Target: action type (click, type, scroll, navigate, etc.)
    pub target_action: String,
    
    /// Target: action parameters (JSON)
    pub target_params: serde_json::Value,
    
    /// Target: reasoning/thought text
    pub target_reasoning: String,
    
    /// Target: QState8 amplitudes (from teacher)
    pub target_qstate: [f32; 8],
    
    /// Domain (computer_use, medical, etc.)
    pub domain: String,
    
    /// Teacher model that produced this
    pub teacher_model_id: String,
}

/// A batch of training examples
#[derive(Debug, Clone)]
pub struct TrainingBatch {
    pub examples: Vec<TrainingExample>,
}

impl TrainingBatch {
    pub fn new(examples: Vec<TrainingExample>) -> Self {
        TrainingBatch { examples }
    }
    
    pub fn len(&self) -> usize {
        self.examples.len()
    }
    
    pub fn is_empty(&self) -> bool {
        self.examples.is_empty()
    }
}

/// Load Fara harvest data and convert to training examples
pub fn load_fara_harvest(path: &Path) -> Result<Vec<TrainingExample>> {
    let db = HarvestDb::load(path.to_str().unwrap())?;
    
    let mut examples = Vec::new();
    
    for (episode_id, episode) in &db.episodes {
        let steps = db.steps_for_episode(episode_id);
        let mut history: Vec<String> = Vec::new();
        
        for step in steps {
            // Get QState8 for this step
            let qstate = db.qstate_for_step(&step.step_id);
            let qstate_amps = qstate.map(|q| q.amps()).unwrap_or([0.0; 8]);
            
            // Parse action from step data
            let action_type = step.action_type.clone().unwrap_or_else(|| "unknown".to_string());
            
            let example = TrainingExample {
                id: step.step_id.clone(),
                episode_id: episode_id.clone(),
                step_index: step.index,
                input_text: step.raw_input.clone(),
                history: history.clone(),
                target_action: action_type.clone(),
                target_params: step.tool_call.clone().unwrap_or(serde_json::Value::Null),
                target_reasoning: step.raw_output.clone(),
                target_qstate: qstate_amps,
                domain: episode.domain.clone(),
                teacher_model_id: episode.teacher_model_id.clone(),
            };
            
            examples.push(example);
            
            // Update history for next step
            history.push(format!("{}: {}", action_type, step.raw_output));
            if history.len() > 5 {
                history.remove(0); // Keep last 5 actions
            }
        }
    }
    
    Ok(examples)
}

/// Create training batches from examples
pub fn create_batches(
    examples: Vec<TrainingExample>,
    batch_size: usize,
    shuffle: bool,
    seed: u64,
) -> Vec<TrainingBatch> {
    let mut examples = examples;
    
    if shuffle {
        let mut rng = StdRng::seed_from_u64(seed);
        examples.shuffle(&mut rng);
    }
    
    examples
        .chunks(batch_size)
        .map(|chunk| TrainingBatch::new(chunk.to_vec()))
        .collect()
}

/// Filter examples by virtue threshold
pub fn filter_by_virtue(
    examples: Vec<TrainingExample>,
    min_threshold: f32,
) -> Vec<TrainingExample> {
    examples
        .into_iter()
        .filter(|ex| {
            // QState8 amp[2] is typically the virtue/ethics dimension
            // Filter out low-virtue examples
            ex.target_qstate[2] >= min_threshold
        })
        .collect()
}

/// Training dataset with iteration support
pub struct TrainingDataset {
    examples: Vec<TrainingExample>,
    batch_size: usize,
    shuffle: bool,
    seed: u64,
    current_epoch: u32,
}

impl TrainingDataset {
    pub fn new(examples: Vec<TrainingExample>, batch_size: usize, shuffle: bool, seed: u64) -> Self {
        TrainingDataset {
            examples,
            batch_size,
            shuffle,
            seed,
            current_epoch: 0,
        }
    }
    
    pub fn len(&self) -> usize {
        self.examples.len()
    }
    
    pub fn num_batches(&self) -> usize {
        self.examples.len().div_ceil(self.batch_size)
    }
    
    pub fn epoch_batches(&mut self) -> Vec<TrainingBatch> {
        self.current_epoch += 1;
        create_batches(
            self.examples.clone(),
            self.batch_size,
            self.shuffle,
            self.seed + self.current_epoch as u64,
        )
    }
    
    /// Get statistics about the dataset
    pub fn stats(&self) -> DatasetStats {
        let mut action_counts: std::collections::HashMap<String, usize> = std::collections::HashMap::new();
        let mut domain_counts: std::collections::HashMap<String, usize> = std::collections::HashMap::new();
        
        for ex in &self.examples {
            *action_counts.entry(ex.target_action.clone()).or_insert(0) += 1;
            *domain_counts.entry(ex.domain.clone()).or_insert(0) += 1;
        }
        
        // Calculate average QState8 norms
        let avg_qstate_norm: f32 = self.examples.iter()
            .map(|ex| {
                let norm_sq: f32 = ex.target_qstate.iter().map(|a| a * a).sum();
                norm_sq.sqrt()
            })
            .sum::<f32>() / self.examples.len() as f32;
        
        DatasetStats {
            total_examples: self.examples.len(),
            action_counts,
            domain_counts,
            avg_qstate_norm,
        }
    }
}

#[derive(Debug, Clone)]
pub struct DatasetStats {
    pub total_examples: usize,
    pub action_counts: std::collections::HashMap<String, usize>,
    pub domain_counts: std::collections::HashMap<String, usize>,
    pub avg_qstate_norm: f32,
}

impl std::fmt::Display for DatasetStats {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        writeln!(f, "═══════════════════════════════════════════")?;
        writeln!(f, "📊 TRAINING DATASET STATISTICS")?;
        writeln!(f, "═══════════════════════════════════════════")?;
        writeln!(f, "  Total examples: {}", self.total_examples)?;
        writeln!(f, "  Avg QState norm: {:.4}", self.avg_qstate_norm)?;
        writeln!(f)?;
        writeln!(f, "  Actions:")?;
        for (action, count) in &self.action_counts {
            writeln!(f, "    • {action}: {count}")?;
        }
        writeln!(f)?;
        writeln!(f, "  Domains:")?;
        for (domain, count) in &self.domain_counts {
            writeln!(f, "    • {domain}: {count}")?;
        }
        writeln!(f, "═══════════════════════════════════════════")?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;
    
    #[test]
    fn test_load_fara_harvest() {
        let manifest_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let harvest_path = manifest_dir
            .parent().unwrap()
            .join("teacher_harvest/harvest_data/fara_harvest.json");
        
        if harvest_path.exists() {
            let examples = load_fara_harvest(&harvest_path).unwrap();
            assert!(!examples.is_empty());
            
            // Check all examples have valid QState8
            for ex in &examples {
                let norm_sq: f32 = ex.target_qstate.iter().map(|a| a * a).sum();
                assert!((norm_sq - 1.0).abs() < 0.1, "QState not normalized");
            }
        }
    }
    
    #[test]
    fn test_create_batches() {
        let examples: Vec<TrainingExample> = (0..25)
            .map(|i| TrainingExample {
                id: format!("ex_{}", i),
                episode_id: "ep_test".to_string(),
                step_index: i,
                input_text: "test input".to_string(),
                history: vec![],
                target_action: "click".to_string(),
                target_params: serde_json::Value::Null,
                target_reasoning: "test".to_string(),
                target_qstate: [0.35; 8],
                domain: "test".to_string(),
                teacher_model_id: "test_teacher".to_string(),
            })
            .collect();
        
        let batches = create_batches(examples, 8, true, 42);
        assert_eq!(batches.len(), 4); // 25 / 8 = 3.125 → 4 batches
        assert_eq!(batches[0].len(), 8);
        assert_eq!(batches[3].len(), 1); // Last batch has remainder
    }
}

