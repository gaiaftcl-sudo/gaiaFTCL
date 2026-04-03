//! Checkpoint saving and loading for GaiaLM

use crate::config::TrainConfig;
use serde::{Deserialize, Serialize};
use chrono::{DateTime, Utc};
use std::path::{Path, PathBuf};
use anyhow::Result;

/// Model checkpoint
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Checkpoint {
    pub model_id: String,
    pub family: String,
    pub distilled_from: Vec<String>,
    pub epoch: u32,
    pub best_loss: f32,
    pub created_at: DateTime<Utc>,
    pub weights_path: PathBuf,
    pub config: TrainConfig,
}

impl Checkpoint {
    /// Save checkpoint to disk
    pub fn save(&self, dir: &Path) -> Result<()> {
        std::fs::create_dir_all(dir)?;
        
        let meta_path = dir.join(format!("{}-checkpoint.json", self.model_id));
        let content = serde_json::to_string_pretty(self)?;
        std::fs::write(&meta_path, content)?;
        
        // In real impl, also save actual weights here
        // For now, create a placeholder weights file
        let weights_content = serde_json::json!({
            "model_id": self.model_id,
            "epoch": self.epoch,
            "weights": "placeholder - real impl saves actual tensor weights",
            "created_at": self.created_at.to_rfc3339(),
        });
        std::fs::write(&self.weights_path, serde_json::to_string_pretty(&weights_content)?)?;
        
        Ok(())
    }
    
    /// Load checkpoint from disk
    pub fn load(dir: &Path, model_id: &str) -> Result<Self> {
        let meta_path = dir.join(format!("{model_id}-checkpoint.json"));
        let content = std::fs::read_to_string(meta_path)?;
        let checkpoint: Checkpoint = serde_json::from_str(&content)?;
        Ok(checkpoint)
    }
    
    /// List all checkpoints in a directory
    pub fn list(dir: &Path) -> Result<Vec<String>> {
        let mut checkpoints = Vec::new();
        
        if dir.is_dir() {
            for entry in std::fs::read_dir(dir)? {
                let entry = entry?;
                let path = entry.path();
                
                if let Some(name) = path.file_name().and_then(|n| n.to_str()) {
                    if name.ends_with("-checkpoint.json") {
                        let model_id = name.trim_end_matches("-checkpoint.json");
                        checkpoints.push(model_id.to_string());
                    }
                }
            }
        }
        
        Ok(checkpoints)
    }
}

/// Registry update for a trained model
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RegistryUpdate {
    pub model_id: String,
    pub status: String,
    pub distilled_from: Vec<String>,
    pub checkpoint_path: String,
    pub iq_status: String,
    pub oq_status: String,
    pub pq_status: String,
}

impl RegistryUpdate {
    /// Create update for a newly trained model
    pub fn from_checkpoint(checkpoint: &Checkpoint) -> Self {
        RegistryUpdate {
            model_id: checkpoint.model_id.clone(),
            status: format!("trained_v{}", checkpoint.epoch),
            distilled_from: checkpoint.distilled_from.clone(),
            checkpoint_path: checkpoint.weights_path.to_string_lossy().to_string(),
            iq_status: "pending".to_string(),
            oq_status: "pending".to_string(),
            pq_status: "pending".to_string(),
        }
    }
    
    /// Apply update to registry JSON
    pub fn apply_to_registry(&self, registry_path: &Path) -> Result<()> {
        let content = std::fs::read_to_string(registry_path)?;
        let mut registry: serde_json::Value = serde_json::from_str(&content)?;
        
        // Find and update the runtime model
        if let Some(runtime_models) = registry.get_mut("runtime_models")
            .and_then(|r| r.get_mut("models"))
            .and_then(|m| m.as_array_mut())
        {
            for model in runtime_models.iter_mut() {
                if model.get("id").and_then(|id| id.as_str()) == Some(&self.model_id) {
                    model["status"] = serde_json::json!(self.status);
                    model["distilled_from"] = serde_json::json!(self.distilled_from);
                    model["checkpoint_path"] = serde_json::json!(self.checkpoint_path);
                    model["iq_status"] = serde_json::json!(self.iq_status);
                    model["oq_status"] = serde_json::json!(self.oq_status);
                    model["pq_status"] = serde_json::json!(self.pq_status);
                    break;
                }
            }
        }
        
        // Write back
        let updated = serde_json::to_string_pretty(&registry)?;
        std::fs::write(registry_path, updated)?;
        
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;
    
    #[test]
    fn test_checkpoint_save_load() {
        let dir = tempdir().unwrap();
        
        let checkpoint = Checkpoint {
            model_id: "test_model".to_string(),
            family: "test".to_string(),
            distilled_from: vec!["teacher".to_string()],
            epoch: 5,
            best_loss: 0.123,
            created_at: Utc::now(),
            weights_path: dir.path().join("test_model-v5.weights"),
            config: TrainConfig::default(),
        };
        
        checkpoint.save(dir.path()).unwrap();
        
        let loaded = Checkpoint::load(dir.path(), "test_model").unwrap();
        assert_eq!(loaded.model_id, "test_model");
        assert_eq!(loaded.epoch, 5);
    }
}

