use crate::qfot::compression::QuantumBasisCompressor;
use crate::qfot::field_graph::FieldGraph;
use crate::qfot::forecast::{baseline_forecast, ForecastStep};
use crate::qfot::message_passing::MessagePassing;
use anyhow::Result;
use ndarray::Array2;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CompressionReport {
    pub hidden_dim: usize,
    pub compressed_dim: usize,
    pub rmse: f32,
}

#[derive(Debug, Clone)]
pub struct QfotEngine {
    pub feature_dim: usize,
    pub hidden_dim: usize,
    pub compressed_dim: usize,
    message: MessagePassing,
    compressor: QuantumBasisCompressor,
}

impl QfotEngine {
    pub fn new(feature_dim: usize, hidden_dim: usize, compressed_dim: usize) -> Result<Self> {
        // MVP uses identity hidden representation: hidden_dim == feature_dim.
        anyhow::ensure!(
            hidden_dim == feature_dim,
            "MVP requires hidden_dim == feature_dim"
        );
        let mut compressor = QuantumBasisCompressor::new(hidden_dim, compressed_dim)?;
        compressor.orthonormalize();
        Ok(Self {
            feature_dim,
            hidden_dim,
            compressed_dim,
            message: MessagePassing::new(feature_dim),
            compressor,
        })
    }

    pub fn forward_hidden(&self, g: &FieldGraph) -> Result<Array2<f32>> {
        // One message passing step produces a bounded hidden state.
        self.message.forward(g)
    }

    pub fn compress_hidden(&self, hidden: &Array2<f32>) -> Result<(Array2<f32>, Array2<f32>, CompressionReport)> {
        let compressed = self.compressor.compress(hidden)?;
        let reconstructed = self.compressor.reconstruct(&compressed)?;
        let rmse = self.compressor.reconstruction_mse(hidden)?;
        Ok((
            compressed,
            reconstructed,
            CompressionReport {
                hidden_dim: self.hidden_dim,
                compressed_dim: self.compressed_dim,
                rmse,
            },
        ))
    }

    pub fn forecast_baseline(
        &self,
        current_features: &Array2<f32>,
        start_valid_time: i64,
        step_secs: i64,
        steps: usize,
    ) -> Result<Vec<ForecastStep>> {
        baseline_forecast(current_features, start_valid_time, step_secs, steps)
    }
}


