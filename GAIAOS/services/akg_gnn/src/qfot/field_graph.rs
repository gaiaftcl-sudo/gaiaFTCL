use crate::substrate_query::{AtmosphereTileDoc, FieldRelationDoc};
use anyhow::Result;
use ndarray::Array2;
use serde::{Deserialize, Serialize};

pub const EDGE_DIM: usize = 8;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FieldGraphMeta {
    pub node_count: usize,
    pub edge_count: usize,
    pub feature_dim: usize,
}

/// Minimal in-memory field graph.
///
/// This is intentionally bounded and allocation-friendly:
/// - Node features are dense (N x D).
/// - Edges are stored as a flat adjacency list (src, dst, edge_feat).
#[derive(Debug, Clone)]
pub struct FieldGraph {
    pub node_ids: Vec<String>,
    pub node_features: Array2<f32>,
    pub edges: Vec<(usize, usize, [f32; EDGE_DIM])>,
}

impl FieldGraph {
    pub fn meta(&self) -> FieldGraphMeta {
        FieldGraphMeta {
            node_count: self.node_ids.len(),
            edge_count: self.edges.len(),
            feature_dim: self.node_features.ncols(),
        }
    }

    pub fn from_atmosphere_tiles(
        tiles: Vec<AtmosphereTileDoc>,
        relations: Vec<FieldRelationDoc>,
        feature_dim: usize,
        encode_tile: impl Fn(&AtmosphereTileDoc) -> Vec<f32>,
        encode_edge: impl Fn(&FieldRelationDoc) -> [f32; EDGE_DIM],
    ) -> Result<Self> {
        let n = tiles.len();
        let mut node_ids = Vec::with_capacity(n);
        let mut features = Array2::<f32>::zeros((n, feature_dim));

        // Map key->idx
        use std::collections::HashMap;
        let mut idx = HashMap::<String, usize>::with_capacity(n);

        for (i, tile) in tiles.iter().enumerate() {
            node_ids.push(tile.key.clone());
            idx.insert(tile.key.clone(), i);
            let f = encode_tile(tile);
            anyhow::ensure!(
                f.len() == feature_dim,
                "encode_tile returned {} dims, expected {}",
                f.len(),
                feature_dim
            );
            for j in 0..feature_dim {
                features[(i, j)] = f[j];
            }
        }

        let mut edges: Vec<(usize, usize, [f32; EDGE_DIM])> = Vec::new();
        edges.reserve(relations.len());

        for rel in relations {
            // Expect _from/_to like "atmosphere_tiles/<key>"
            let from_key = rel.from.split('/').nth(1).unwrap_or("").to_string();
            let to_key = rel.to.split('/').nth(1).unwrap_or("").to_string();
            let Some(&src) = idx.get(&from_key) else { continue };
            let Some(&dst) = idx.get(&to_key) else { continue };
            let ef = encode_edge(&rel);
            edges.push((src, dst, ef));
        }

        Ok(Self {
            node_ids,
            node_features: features,
            edges,
        })
    }
}


