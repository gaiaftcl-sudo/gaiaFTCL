use crate::qfot::field_graph::{FieldGraph, EDGE_DIM};
use anyhow::Result;
use ndarray::Array2;

/// A bounded, deterministic message passing layer.
///
/// This MVP implementation is intentionally conservative:
/// - It performs neighbor aggregation with edge-conditioned weighting.
/// - It uses a fixed LeakyReLU-like nonlinearity.
/// - It does not mutate any persistent state and does not claim learned weights.
#[derive(Debug, Clone)]
pub struct MessagePassing {
    pub feature_dim: usize,
}

impl MessagePassing {
    pub fn new(feature_dim: usize) -> Self {
        Self { feature_dim }
    }

    pub fn forward(&self, g: &FieldGraph) -> Result<Array2<f32>> {
        anyhow::ensure!(
            g.node_features.ncols() == self.feature_dim,
            "feature_dim mismatch"
        );

        let n = g.node_features.nrows();
        let mut out = Array2::<f32>::zeros((n, self.feature_dim));
        let mut deg = vec![0u32; n];

        // Aggregate neighbor contributions.
        for (src, dst, ef) in &g.edges {
            let w = edge_weight(ef);
            deg[*dst] += 1;
            for d in 0..self.feature_dim {
                out[(*dst, d)] += g.node_features[(*src, d)] * w;
            }
        }

        // Normalize by degree and apply nonlinearity + residual.
        for i in 0..n {
            let denom = (deg[i] as f32).max(1.0);
            for d in 0..self.feature_dim {
                let agg = out[(i, d)] / denom;
                let v = g.node_features[(i, d)] + leaky_relu(agg);
                out[(i, d)] = v;
            }
        }

        Ok(out)
    }
}

fn leaky_relu(x: f32) -> f32 {
    if x >= 0.0 { x } else { 0.2 * x }
}

fn edge_weight(edge_feat: &[f32; EDGE_DIM]) -> f32 {
    // edge_feat[0] encodes relation type, edge_feat[1] optional strength proxy.
    // We keep weighting bounded to prevent blow-ups.
    let strength = edge_feat[1].clamp(0.0, 1.0);
    (0.5 + 0.5 * strength).clamp(0.1, 1.0)
}


