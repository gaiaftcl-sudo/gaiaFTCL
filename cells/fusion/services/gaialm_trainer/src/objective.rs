//! Distillation loss functions with FoT-aware virtue alignment

use crate::data::TrainingBatch;
use serde::{Deserialize, Serialize};

/// Loss weights for distillation
#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub struct LossWeights {
    /// Weight for action prediction loss
    pub action: f32,
    
    /// Weight for reasoning/language loss
    pub reasoning: f32,
    
    /// Weight for QState8 regularizer
    pub qstate: f32,
}

impl Default for LossWeights {
    fn default() -> Self {
        LossWeights {
            action: 1.0,
            reasoning: 0.5,
            qstate: 0.1,
        }
    }
}

/// Combined distillation loss
#[derive(Debug, Clone)]
pub struct DistillationLoss {
    pub weights: LossWeights,
    
    /// Accumulated action loss
    pub action_loss: f32,
    
    /// Accumulated reasoning loss
    pub reasoning_loss: f32,
    
    /// Accumulated QState regularizer
    pub qstate_loss: f32,
    
    /// Number of examples processed
    pub num_examples: usize,
}

impl DistillationLoss {
    pub fn new(weights: LossWeights) -> Self {
        DistillationLoss {
            weights,
            action_loss: 0.0,
            reasoning_loss: 0.0,
            qstate_loss: 0.0,
            num_examples: 0,
        }
    }
    
    /// Total weighted loss
    pub fn total(&self) -> f32 {
        self.weights.action * self.action_loss
            + self.weights.reasoning * self.reasoning_loss
            + self.weights.qstate * self.qstate_loss
    }
    
    /// Average loss per example
    pub fn average(&self) -> f32 {
        if self.num_examples == 0 {
            0.0
        } else {
            self.total() / self.num_examples as f32
        }
    }
    
    /// Reset accumulators
    pub fn reset(&mut self) {
        self.action_loss = 0.0;
        self.reasoning_loss = 0.0;
        self.qstate_loss = 0.0;
        self.num_examples = 0;
    }
    
    /// Accumulate losses from a batch
    pub fn accumulate(&mut self, batch_loss: &BatchLoss) {
        self.action_loss += batch_loss.action;
        self.reasoning_loss += batch_loss.reasoning;
        self.qstate_loss += batch_loss.qstate;
        self.num_examples += batch_loss.num_examples;
    }
}

/// Loss for a single batch
#[derive(Debug, Clone)]
pub struct BatchLoss {
    pub action: f32,
    pub reasoning: f32,
    pub qstate: f32,
    pub num_examples: usize,
}

/// Compute batch loss (simulated - in real impl this calls the model)
pub fn compute_batch_loss(
    batch: &TrainingBatch,
    model_predictions: &ModelPredictions,
) -> BatchLoss {
    let mut action_loss = 0.0;
    let mut reasoning_loss = 0.0;
    let mut qstate_loss = 0.0;
    
    for (i, example) in batch.examples.iter().enumerate() {
        // Action loss: cross-entropy between predicted and target action
        action_loss += compute_action_loss(
            &model_predictions.action_logits[i],
            &example.target_action,
        );
        
        // Reasoning loss: LM loss on thought tokens
        reasoning_loss += compute_reasoning_loss(
            &model_predictions.reasoning_logits[i],
            &example.target_reasoning,
        );
        
        // QState regularizer: ||q̂ - q_teacher||²
        qstate_loss += compute_qstate_loss(
            &model_predictions.qstate_predictions[i],
            &example.target_qstate,
        );
    }
    
    BatchLoss {
        action: action_loss,
        reasoning: reasoning_loss,
        qstate: qstate_loss,
        num_examples: batch.len(),
    }
}

/// Model predictions for a batch
pub struct ModelPredictions {
    /// Action logits per example
    pub action_logits: Vec<ActionLogits>,
    
    /// Reasoning token logits per example
    pub reasoning_logits: Vec<Vec<f32>>,
    
    /// QState8 predictions per example
    pub qstate_predictions: Vec<[f32; 8]>,
}

pub struct ActionLogits {
    pub click: f32,
    pub scroll: f32,
    pub type_text: f32,
    pub navigate: f32,
    pub wait: f32,
    pub terminate: f32,
}

impl ActionLogits {
    /// Simulated softmax prediction
    pub fn predicted_action(&self) -> &'static str {
        let max = self.click.max(self.scroll).max(self.type_text)
            .max(self.navigate).max(self.wait).max(self.terminate);
        
        if max == self.click { "click" }
        else if max == self.scroll { "scroll" }
        else if max == self.type_text { "type" }
        else if max == self.navigate { "navigate" }
        else if max == self.wait { "wait" }
        else { "terminate" }
    }
}

/// Compute action cross-entropy loss
fn compute_action_loss(logits: &ActionLogits, target: &str) -> f32 {
    // Simplified cross-entropy (real impl uses proper softmax)
    let target_logit = match target {
        "click" | "left_click" => logits.click,
        "scroll" => logits.scroll,
        "type" => logits.type_text,
        "navigate" | "visit_url" => logits.navigate,
        "wait" => logits.wait,
        "terminate" | "done" => logits.terminate,
        _ => logits.wait,
    };
    
    // Negative log likelihood (simplified)
    let sum_exp = logits.click.exp() + logits.scroll.exp() + logits.type_text.exp()
        + logits.navigate.exp() + logits.wait.exp() + logits.terminate.exp();
    
    -(target_logit - sum_exp.ln())
}

/// Compute reasoning LM loss
fn compute_reasoning_loss(logits: &[f32], target: &str) -> f32 {
    // Simplified: just check if output length matches
    // Real impl does token-level cross-entropy
    let predicted_len = logits.len();
    let target_len = target.len();
    
    // Penalize length mismatch
    ((predicted_len as f32 - target_len as f32) / 100.0).powi(2)
}

/// Compute QState8 regularizer loss
fn compute_qstate_loss(predicted: &[f32; 8], target: &[f32; 8]) -> f32 {
    // L2 loss between predicted and teacher QState8
    predicted.iter()
        .zip(target.iter())
        .map(|(p, t)| (p - t).powi(2))
        .sum::<f32>()
}

/// Create simulated model predictions for a batch
/// (In real impl, this calls the actual GaiaLM model)
pub fn simulate_predictions(batch: &TrainingBatch) -> ModelPredictions {
    use rand::Rng;
    let mut rng = rand::thread_rng();
    
    let action_logits: Vec<ActionLogits> = batch.examples.iter()
        .map(|ex| {
            // Simulate learning: bias toward correct action
            let correct = &ex.target_action;
            ActionLogits {
                click: if correct.contains("click") { 2.0 } else { rng.gen_range(-1.0..1.0) },
                scroll: if correct == "scroll" { 2.0 } else { rng.gen_range(-1.0..1.0) },
                type_text: if correct == "type" { 2.0 } else { rng.gen_range(-1.0..1.0) },
                navigate: if correct.contains("navigate") || correct.contains("url") { 2.0 } else { rng.gen_range(-1.0..1.0) },
                wait: if correct == "wait" { 2.0 } else { rng.gen_range(-1.0..1.0) },
                terminate: if correct.contains("terminate") || correct == "done" { 2.0 } else { rng.gen_range(-1.0..1.0) },
            }
        })
        .collect();
    
    let reasoning_logits: Vec<Vec<f32>> = batch.examples.iter()
        .map(|ex| vec![0.0; ex.target_reasoning.len()])
        .collect();
    
    let qstate_predictions: Vec<[f32; 8]> = batch.examples.iter()
        .map(|ex| {
            // Simulate learning: predicted QState approaches teacher QState
            let mut pred = [0.0f32; 8];
            for i in 0..8 {
                pred[i] = ex.target_qstate[i] + rng.gen_range(-0.1..0.1);
            }
            pred
        })
        .collect();
    
    ModelPredictions {
        action_logits,
        reasoning_logits,
        qstate_predictions,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_loss_accumulation() {
        let mut loss = DistillationLoss::new(LossWeights::default());
        
        loss.accumulate(&BatchLoss {
            action: 1.0,
            reasoning: 0.5,
            qstate: 0.1,
            num_examples: 8,
        });
        
        loss.accumulate(&BatchLoss {
            action: 0.8,
            reasoning: 0.4,
            qstate: 0.08,
            num_examples: 8,
        });
        
        assert_eq!(loss.num_examples, 16);
        assert!((loss.action_loss - 1.8).abs() < 0.001);
    }
    
    #[test]
    fn test_qstate_loss() {
        let pred = [0.35, 0.35, 0.35, 0.35, 0.35, 0.35, 0.35, 0.35];
        let target = [0.35, 0.35, 0.35, 0.35, 0.35, 0.35, 0.35, 0.35];
        
        let loss = compute_qstate_loss(&pred, &target);
        assert!(loss < 0.001); // Should be ~0 for identical vectors
    }
}

