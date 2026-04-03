use anyhow::Result;
use std::env;

#[derive(Clone)]
/// Configuration for AKG-GNN service (loaded from environment)
#[allow(dead_code)]
pub struct Config {
    pub host: String,
    pub port: u16,

    pub arango_url: String,
    pub arango_db: String,
    pub arango_user: String,
    pub arango_password: String,

    pub embedding_model_path: String,

    pub gnn_hidden_dim: usize,
    pub gnn_num_layers: usize,

    pub pq_similarity_threshold: f32,
    pub pq_max_procedures: usize,

    pub risk_penalties: RiskPenalties,
}

#[derive(Clone)]
/// Risk-based scoring penalties
#[allow(dead_code)]
pub struct RiskPenalties {
    pub critical: f32,
    pub high: f32,
    pub medium: f32,
    pub low: f32,
}

impl Config {
    // Load configuration from environment variables (reserved for standalone deployment)
    #[allow(dead_code)]
    pub fn from_env() -> Result<Self> {
        Ok(Config {
            host: env::var("HOST").unwrap_or_else(|_| "0.0.0.0".to_string()),
            port: env::var("PORT")
                .unwrap_or_else(|_| "8080".to_string())
                .parse()?,

            arango_url: env::var("ARANGO_URL")
                .unwrap_or_else(|_| "http://arangodb:8529".to_string()),
            arango_db: env::var("ARANGO_DB").unwrap_or_else(|_| "gaiaos".to_string()),
            arango_user: env::var("ARANGO_USER").unwrap_or_else(|_| "root".to_string()),
            arango_password: env::var("ARANGO_PASSWORD").unwrap_or_else(|_| "gaiaos".to_string()),

            embedding_model_path: env::var("EMBEDDING_MODEL_PATH")
                .unwrap_or_else(|_| "/app/models/all-MiniLM-L6-v2".to_string()),

            gnn_hidden_dim: env::var("GNN_HIDDEN_DIM")
                .unwrap_or_else(|_| "256".to_string())
                .parse()?,
            gnn_num_layers: env::var("GNN_NUM_LAYERS")
                .unwrap_or_else(|_| "2".to_string())
                .parse()?,

            pq_similarity_threshold: env::var("PQ_SIMILARITY_THRESHOLD")
                .unwrap_or_else(|_| "0.65".to_string())
                .parse()?,
            pq_max_procedures: env::var("PQ_MAX_PROCEDURES")
                .unwrap_or_else(|_| "20".to_string())
                .parse()?,

            risk_penalties: RiskPenalties {
                critical: 0.20,
                high: 0.15,
                medium: 0.08,
                low: 0.02,
            },
        })
    }
}
