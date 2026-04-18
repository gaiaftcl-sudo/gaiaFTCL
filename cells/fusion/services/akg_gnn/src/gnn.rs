use nalgebra::DVector;
use petgraph::graph::{Graph, NodeIndex};
use petgraph::Directed;
use std::collections::HashMap;

/// Graph Neural Network processor for knowledge graph reasoning
#[allow(dead_code)]
pub struct GNNProcessor {
    hidden_dim: usize,
    num_layers: usize,
}

/// Node features for GNN processing
#[allow(dead_code)]
#[derive(Clone)]
pub struct NodeFeatures {
    pub embedding: Vec<f32>,
    pub success_rate: f32,
    pub execution_count: u32,
    pub recency_score: f32,
}

#[allow(dead_code)]
impl GNNProcessor {
    pub fn new(hidden_dim: usize, num_layers: usize) -> Self {
        Self {
            hidden_dim,
            num_layers,
        }
    }

    pub fn process_graph(
        &self,
        graph: &Graph<NodeFeatures, f32, Directed>,
        query_embedding: &[f32],
    ) -> HashMap<NodeIndex, f32> {
        let mut node_reps: HashMap<NodeIndex, DVector<f32>> = HashMap::new();

        // Initialize node representations with features
        for node_idx in graph.node_indices() {
            let features = &graph[node_idx];

            // Combine query embedding with node features
            let mut rep = Vec::with_capacity(query_embedding.len() + 3);
            rep.extend_from_slice(query_embedding);
            rep.push(features.success_rate);
            rep.push(((features.execution_count as f32 + 1.0).ln() / 10.0).min(1.0));
            rep.push(features.recency_score);

            node_reps.insert(node_idx, DVector::from_vec(rep));
        }

        // Message passing layers
        for _layer in 0..self.num_layers {
            let mut new_reps = HashMap::new();

            for node_idx in graph.node_indices() {
                let neighbors: Vec<_> = graph.neighbors(node_idx).collect();

                if neighbors.is_empty() {
                    new_reps.insert(node_idx, node_reps[&node_idx].clone());
                    continue;
                }

                let mut aggregated = DVector::zeros(node_reps[&node_idx].len());
                let mut total_weight = 0.0f32;

                for neighbor_idx in neighbors {
                    let edge_weight = graph
                        .find_edge(node_idx, neighbor_idx)
                        .map(|e| graph[e])
                        .unwrap_or(1.0);

                    let attention =
                        self.compute_attention(&node_reps[&node_idx], &node_reps[&neighbor_idx]);

                    let weight = attention * edge_weight;
                    aggregated += weight * &node_reps[&neighbor_idx];
                    total_weight += weight;
                }

                if total_weight > 0.0 {
                    aggregated /= total_weight;
                }

                // Combine with self-connection
                new_reps.insert(node_idx, 0.5 * &node_reps[&node_idx] + 0.5 * &aggregated);
            }

            node_reps = new_reps;
        }

        // Compute final scores based on similarity to query
        let query_vec = DVector::from_column_slice(query_embedding);
        let query_norm = query_vec.norm();

        let mut scores = HashMap::new();
        for (node_idx, rep) in &node_reps {
            // Extract embedding portion (first query_embedding.len() dims)
            let node_emb: Vec<f32> = rep.iter().take(query_embedding.len()).cloned().collect();
            let node_vec = DVector::from_column_slice(&node_emb);
            let node_norm = node_vec.norm();

            let similarity = if query_norm > 0.0 && node_norm > 0.0 {
                node_vec.dot(&query_vec) / (node_norm * query_norm)
            } else {
                0.0
            };

            scores.insert(*node_idx, similarity);
        }

        scores
    }

    fn compute_attention(&self, query: &DVector<f32>, key: &DVector<f32>) -> f32 {
        let dot = query.dot(key);
        let scale = (self.hidden_dim as f32).sqrt();

        // Softmax approximation for single pair
        (dot / scale).exp()
    }

    pub fn cosine_similarity(&self, a: &[f32], b: &[f32]) -> f32 {
        if a.len() != b.len() {
            return 0.0;
        }

        let dot: f32 = a.iter().zip(b).map(|(x, y)| x * y).sum();
        let norm_a: f32 = a.iter().map(|x| x * x).sum::<f32>().sqrt();
        let norm_b: f32 = b.iter().map(|x| x * x).sum::<f32>().sqrt();

        if norm_a == 0.0 || norm_b == 0.0 {
            0.0
        } else {
            dot / (norm_a * norm_b)
        }
    }
}
