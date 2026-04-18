//! Training configuration

use serde::{Deserialize, Serialize};
use std::path::PathBuf;

/// Training configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TrainConfig {
    /// Model ID being trained
    pub model_id: String,
    
    /// Domain/family (computer_use, medical, math, etc.)
    pub family: String,
    
    /// Teacher model(s) being distilled from
    pub distilled_from: Vec<String>,
    
    /// Path to harvest data
    pub harvest_path: PathBuf,
    
    /// Output path for checkpoints
    pub checkpoint_dir: PathBuf,
    
    /// Number of training epochs
    pub epochs: u32,
    
    /// Batch size
    pub batch_size: usize,
    
    /// Learning rate
    pub learning_rate: f32,
    
    /// Loss weights
    pub loss_weights: LossWeightsConfig,
    
    /// Whether to use QState8 regularizer
    pub use_qstate_regularizer: bool,
    
    /// Minimum virtue threshold for training examples
    pub min_virtue_threshold: Option<f32>,
    
    /// Random seed for reproducibility
    pub seed: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LossWeightsConfig {
    /// Weight for action prediction loss
    pub action: f32,
    
    /// Weight for reasoning/language loss
    pub reasoning: f32,
    
    /// Weight for QState8 regularizer
    pub qstate: f32,
}

impl Default for TrainConfig {
    fn default() -> Self {
        TrainConfig {
            model_id: "gaialm_computer_use_core".to_string(),
            family: "computer_use".to_string(),
            distilled_from: vec!["fara_7b_teacher".to_string()],
            harvest_path: PathBuf::from("services/teacher_harvest/harvest_data/fara_harvest.json"),
            checkpoint_dir: PathBuf::from("models/gaialm"),
            epochs: 10,
            batch_size: 8,
            learning_rate: 1e-4,
            loss_weights: LossWeightsConfig::default(),
            use_qstate_regularizer: true,
            min_virtue_threshold: None,
            seed: 42,
        }
    }
}

impl Default for LossWeightsConfig {
    fn default() -> Self {
        LossWeightsConfig {
            action: 1.0,
            reasoning: 0.5,
            qstate: 0.1,
        }
    }
}

impl TrainConfig {
    /// Create config for computer use domain
    pub fn computer_use() -> Self {
        Self::default()
    }
    
    /// Create config for medical domain
    pub fn medical() -> Self {
        TrainConfig {
            model_id: "gaialm_med_core".to_string(),
            family: "medical".to_string(),
            distilled_from: vec!["meditron_7b_teacher".to_string()],
            harvest_path: PathBuf::from("services/teacher_harvest/harvest_data/medical_harvest.json"),
            ..Self::default()
        }
    }
    
    /// Create config for math domain
    pub fn math() -> Self {
        TrainConfig {
            model_id: "gaialm_math_core".to_string(),
            family: "math".to_string(),
            distilled_from: vec!["deepseek_math_7b_teacher".to_string()],
            harvest_path: PathBuf::from("services/teacher_harvest/harvest_data/math_harvest.json"),
            ..Self::default()
        }
    }
    
    /// Create config for chemistry domain (HIGH-RISK: virtue >= 0.97)
    pub fn chemistry() -> Self {
        TrainConfig {
            model_id: "gaialm_chem_core".to_string(),
            family: "chemistry".to_string(),
            distilled_from: vec![
                "chemllm_2b_teacher".to_string(),
                "chemllm_7b_teacher".to_string(),
                "chemdfm_13b_teacher".to_string(),
                "llasmol_7b_teacher".to_string(),
            ],
            harvest_path: PathBuf::from("services/teacher_harvest/harvest_data/chemistry_harvest.json"),
            loss_weights: LossWeightsConfig {
                action: 1.0,
                reasoning: 0.5,
                qstate: 0.2, // Higher weight for high-risk domain
            },
            min_virtue_threshold: Some(0.5), // Filter low-virtue examples
            ..Self::default()
        }
    }
    
    /// Create config for world model / PAN domain
    pub fn world_models() -> Self {
        TrainConfig {
            model_id: "gaialm_worldmodel_core".to_string(),
            family: "world_models".to_string(),
            distilled_from: vec![
                "pan_world_teacher".to_string(),
            ],
            harvest_path: PathBuf::from("services/teacher_harvest/harvest_data/world_models_harvest.json"),
            ..Self::default()
        }
    }
    
    /// Create config for code domain
    pub fn code() -> Self {
        TrainConfig {
            model_id: "gaialm_code_core".to_string(),
            family: "code".to_string(),
            distilled_from: vec![
                "starcoder2_15b_teacher".to_string(),
                "deepseek_coder_v2_236b_teacher".to_string(),
                "qwen25_coder_32b_teacher".to_string(),
            ],
            harvest_path: PathBuf::from("services/teacher_harvest/harvest_data/code_harvest.json"),
            ..Self::default()
        }
    }
    
    /// Create config for protein domain (HIGH-RISK: virtue >= 0.97)
    pub fn protein() -> Self {
        TrainConfig {
            model_id: "gaialm_protein_core".to_string(),
            family: "protein".to_string(),
            distilled_from: vec![
                "esm2_650m_teacher".to_string(),
                "esm2_3b_teacher".to_string(),
            ],
            harvest_path: PathBuf::from("services/teacher_harvest/harvest_data/protein_harvest.json"),
            loss_weights: LossWeightsConfig {
                action: 1.0,
                reasoning: 0.5,
                qstate: 0.2, // Higher weight for high-risk domain
            },
            min_virtue_threshold: Some(0.5),
            ..Self::default()
        }
    }
    
    /// Create config for galaxy / astrophysics domain (LOW-RISK: virtue >= 0.85)
    pub fn galaxy() -> Self {
        TrainConfig {
            model_id: "gaialm_galaxy_core".to_string(),
            family: "galaxy".to_string(),
            distilled_from: vec![
                "astrosage_8b_teacher".to_string(),
            ],
            harvest_path: PathBuf::from("services/teacher_harvest/harvest_data/galaxy_harvest.json"),
            ..Self::default()
        }
    }
    
    /// Create config for vision domain
    pub fn vision() -> Self {
        TrainConfig {
            model_id: "gaialm_vision_core".to_string(),
            family: "vision".to_string(),
            distilled_from: vec![
                "qwen25_vl_72b_teacher".to_string(),
                "pixtral_12b_teacher".to_string(),
            ],
            harvest_path: PathBuf::from("services/teacher_harvest/harvest_data/vision_harvest.json"),
            ..Self::default()
        }
    }
    
    /// Create config for general reasoning domain
    pub fn general_reasoning() -> Self {
        TrainConfig {
            model_id: "gaialm_unified_v1".to_string(),
            family: "general_reasoning".to_string(),
            distilled_from: vec![
                "llama_core_70b_teacher".to_string(),
                "gemma2_27b_teacher".to_string(),
                "mistral_nemo_12b_teacher".to_string(),
                "deepseek_r1_7b_teacher".to_string(),
            ],
            harvest_path: PathBuf::from("services/teacher_harvest/harvest_data/general_harvest.json"),
            ..Self::default()
        }
    }
    
    /// Alias for general_reasoning() - the "glue brain"
    pub fn general() -> Self {
        Self::general_reasoning()
    }
    
    /// Get config by domain name
    pub fn for_domain(domain: &str) -> Option<Self> {
        match domain {
            "computer_use" => Some(Self::computer_use()),
            "medical" => Some(Self::medical()),
            "math" => Some(Self::math()),
            "chemistry" => Some(Self::chemistry()),
            "world_models" => Some(Self::world_models()),
            "code" => Some(Self::code()),
            "protein" => Some(Self::protein()),
            "galaxy" => Some(Self::galaxy()),
            "vision" => Some(Self::vision()),
            "general_reasoning" => Some(Self::general_reasoning()),
            _ => None,
        }
    }
}

