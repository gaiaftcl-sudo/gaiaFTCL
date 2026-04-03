//! Main training loop for GaiaLM distillation

use crate::config::TrainConfig;
use crate::data::TrainingDataset;
use crate::objective::{DistillationLoss, LossWeights, compute_batch_loss, simulate_predictions};
use crate::checkpoint::Checkpoint;
use log::info;
use chrono::Utc;

/// Training statistics for an epoch
#[derive(Debug, Clone)]
pub struct TrainStats {
    pub epoch: u32,
    pub total_loss: f32,
    pub action_loss: f32,
    pub reasoning_loss: f32,
    pub qstate_loss: f32,
    pub num_batches: usize,
    pub num_examples: usize,
    pub duration_ms: u64,
}

impl std::fmt::Display for TrainStats {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(
            f,
            "Epoch {}: loss={:.4} (action={:.4}, reasoning={:.4}, qstate={:.4}) | {} examples in {}ms",
            self.epoch,
            self.total_loss,
            self.action_loss,
            self.reasoning_loss,
            self.qstate_loss,
            self.num_examples,
            self.duration_ms
        )
    }
}

/// GaiaLM Trainer
pub struct GaiaLMTrainer {
    config: TrainConfig,
    loss_weights: LossWeights,
    current_epoch: u32,
    best_loss: f32,
}

impl GaiaLMTrainer {
    pub fn new(config: TrainConfig) -> Self {
        let loss_weights = LossWeights {
            action: config.loss_weights.action,
            reasoning: config.loss_weights.reasoning,
            qstate: config.loss_weights.qstate,
        };
        
        GaiaLMTrainer {
            config,
            loss_weights,
            current_epoch: 0,
            best_loss: f32::MAX,
        }
    }
    
    /// Train for one epoch
    pub fn train_epoch(&mut self, dataset: &mut TrainingDataset) -> TrainStats {
        let start_time = std::time::Instant::now();
        self.current_epoch += 1;
        
        let mut epoch_loss = DistillationLoss::new(self.loss_weights);
        let batches = dataset.epoch_batches();
        let num_batches = batches.len();
        
        for (batch_idx, batch) in batches.iter().enumerate() {
            // Forward pass (simulated)
            let predictions = simulate_predictions(batch);
            
            // Compute loss
            let batch_loss = compute_batch_loss(batch, &predictions);
            epoch_loss.accumulate(&batch_loss);
            
            // Log progress every 10 batches
            if (batch_idx + 1) % 10 == 0 || batch_idx == num_batches - 1 {
                info!(
                    "[Epoch {}] Batch {}/{}: loss={:.4}",
                    self.current_epoch,
                    batch_idx + 1,
                    num_batches,
                    epoch_loss.average()
                );
            }
            
            // In real impl: backward pass + optimizer step here
        }
        
        let duration_ms = start_time.elapsed().as_millis() as u64;
        let avg_loss = epoch_loss.average();
        
        // Track best loss
        if avg_loss < self.best_loss {
            self.best_loss = avg_loss;
            info!("New best loss: {:.4}", self.best_loss);
        }
        
        TrainStats {
            epoch: self.current_epoch,
            total_loss: avg_loss,
            action_loss: epoch_loss.action_loss / epoch_loss.num_examples as f32,
            reasoning_loss: epoch_loss.reasoning_loss / epoch_loss.num_examples as f32,
            qstate_loss: epoch_loss.qstate_loss / epoch_loss.num_examples as f32,
            num_batches,
            num_examples: epoch_loss.num_examples,
            duration_ms,
        }
    }
    
    /// Train for multiple epochs
    pub fn train(&mut self, dataset: &mut TrainingDataset) -> Vec<TrainStats> {
        info!("Starting training: {} epochs, {} examples", 
            self.config.epochs, dataset.len());
        
        let mut all_stats = Vec::new();
        
        for _epoch in 1..=self.config.epochs {
            let stats = self.train_epoch(dataset);
            info!("{stats}");
            all_stats.push(stats);
        }
        
        info!("Training complete! Best loss: {:.4}", self.best_loss);
        all_stats
    }
    
    /// Save checkpoint
    pub fn save_checkpoint(&self, path: &std::path::Path) -> anyhow::Result<Checkpoint> {
        let checkpoint = Checkpoint {
            model_id: self.config.model_id.clone(),
            family: self.config.family.clone(),
            distilled_from: self.config.distilled_from.clone(),
            epoch: self.current_epoch,
            best_loss: self.best_loss,
            created_at: Utc::now(),
            weights_path: path.join(format!(
                "{}-v{}.weights",
                self.config.model_id,
                self.current_epoch
            )),
            config: self.config.clone(),
        };
        
        checkpoint.save(path)?;
        Ok(checkpoint)
    }
    
    /// Get current config
    pub fn config(&self) -> &TrainConfig {
        &self.config
    }
    
    /// Get current epoch
    pub fn current_epoch(&self) -> u32 {
        self.current_epoch
    }
    
    /// Get best loss
    pub fn best_loss(&self) -> f32 {
        self.best_loss
    }
}

/// Training run summary
#[derive(Debug, Clone)]
pub struct TrainingSummary {
    pub model_id: String,
    pub family: String,
    pub distilled_from: Vec<String>,
    pub total_epochs: u32,
    pub final_loss: f32,
    pub best_loss: f32,
    pub total_examples: usize,
    pub total_duration_ms: u64,
    pub checkpoint_path: Option<std::path::PathBuf>,
}

impl std::fmt::Display for TrainingSummary {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        writeln!(f, "═══════════════════════════════════════════")?;
        writeln!(f, "🎓 TRAINING SUMMARY")?;
        writeln!(f, "═══════════════════════════════════════════")?;
        writeln!(f, "  Model:        {}", self.model_id)?;
        writeln!(f, "  Family:       {}", self.family)?;
        writeln!(f, "  Teachers:     {:?}", self.distilled_from)?;
        writeln!(f, "  Epochs:       {}", self.total_epochs)?;
        writeln!(f, "  Final Loss:   {:.4}", self.final_loss)?;
        writeln!(f, "  Best Loss:    {:.4}", self.best_loss)?;
        writeln!(f, "  Examples:     {}", self.total_examples)?;
        writeln!(f, "  Duration:     {}ms", self.total_duration_ms)?;
        if let Some(path) = &self.checkpoint_path {
            writeln!(f, "  Checkpoint:   {path:?}")?;
        }
        writeln!(f, "═══════════════════════════════════════════")?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::data::TrainingExample;
    
    #[test]
    fn test_trainer_epoch() {
        let config = TrainConfig::default();
        let mut trainer = GaiaLMTrainer::new(config);
        
        // Create fake dataset
        let examples: Vec<TrainingExample> = (0..20)
            .map(|i| TrainingExample {
                id: format!("ex_{}", i),
                episode_id: "ep_test".to_string(),
                step_index: i,
                input_text: "test".to_string(),
                history: vec![],
                target_action: "click".to_string(),
                target_params: serde_json::Value::Null,
                target_reasoning: "test reasoning".to_string(),
                target_qstate: [0.35; 8],
                domain: "computer_use".to_string(),
                teacher_model_id: "fara_7b_teacher".to_string(),
            })
            .collect();
        
        let mut dataset = TrainingDataset::new(examples, 8, true, 42);
        
        let stats = trainer.train_epoch(&mut dataset);
        assert_eq!(stats.epoch, 1);
        assert!(stats.total_loss > 0.0);
    }
}

