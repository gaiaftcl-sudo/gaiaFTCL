//! Coherence Engine - DBSCAN Clustering + Weighted Merge
//!
//! Computes social coherence across multiple observations of the same entity.
//! Uses spatial clustering to group nearby observations, then merges them
//! with uncertainty-weighted averaging.

use crate::model::vqbit::Vqbit8D;
use std::collections::HashMap;
use uuid::Uuid;

/// Result of coherence computation
#[allow(dead_code)]
#[derive(Debug, Clone)]
pub struct CoherenceResult {
    /// Overall coherence score [0.0, 1.0]
    pub score: f32,
    /// Merged vQbit representing consensus
    pub merged: Vqbit8D,
    /// Detected conflicts
    pub conflicts: Vec<ConflictReport>,
}

/// Report of a conflicting observation
#[allow(dead_code)]
#[derive(Debug, Clone)]
pub struct ConflictReport {
    /// ID of the conflicting vQbit
    pub vqbit_id: Uuid,
    /// Source that produced the conflict
    pub source_id: String,
    /// Deviation from merged truth in meters
    pub deviation_m: f32,
    /// Domain of the conflicting source
    pub domain: String,
}

/// Coherence engine for multi-source validation
pub struct CoherenceEngine {
    /// Spatial clustering threshold in meters (used in health check)
    pub cluster_threshold_m: f32,
    /// Conflict detection threshold in meters (reserved for conflict detection)
    #[allow(dead_code)]
    pub conflict_threshold_m: f32,
}

impl Default for CoherenceEngine {
    fn default() -> Self {
        Self {
            cluster_threshold_m: 5.0,
            conflict_threshold_m: 10.0,
        }
    }
}

impl CoherenceEngine {
    /// Create new coherence engine with custom thresholds
    #[allow(dead_code)]
    pub fn new(cluster_threshold_m: f32, conflict_threshold_m: f32) -> Self {
        Self {
            cluster_threshold_m,
            conflict_threshold_m,
        }
    }

    /// Compute coherence across a set of observations
    ///
    /// # Algorithm
    /// 1. Cluster observations spatially (DBSCAN-like)
    /// 2. Select the largest cluster as consensus
    /// 3. Merge observations with uncertainty weighting
    /// 4. Detect conflicts (observations outside threshold)
    #[allow(dead_code)]
    pub async fn compute_coherence(
        &self,
        observations: &[Vqbit8D],
    ) -> Result<CoherenceResult, String> {
        if observations.is_empty() {
            return Err("No observations to process".to_string());
        }

        if observations.len() == 1 {
            let mut merged = observations[0].clone();
            merged.d6_social_coherence = 0.33; // Single source
            return Ok(CoherenceResult {
                score: 0.33,
                merged,
                conflicts: vec![],
            });
        }

        // Step 1: Spatial clustering
        let clusters = self.spatial_cluster(observations);

        if clusters.is_empty() {
            return Err("Clustering produced no results".to_string());
        }

        // Step 2: Select best (largest) cluster
        let best_cluster = clusters.into_iter().max_by_key(|c| c.len()).unwrap();

        // Step 3: Merge observations
        let merged = self.merge_observations(&best_cluster);

        // Step 4: Compute coherence score
        let score = (best_cluster.len() as f32 / 3.0).min(1.0);

        // Step 5: Detect conflicts
        let conflicts = self.detect_conflicts(observations, &merged);

        Ok(CoherenceResult {
            score,
            merged,
            conflicts,
        })
    }

    /// Cluster observations spatially using simple distance-based grouping
    /// (Simplified DBSCAN without noise handling)
    fn spatial_cluster(&self, vqbits: &[Vqbit8D]) -> Vec<Vec<Vqbit8D>> {
        let mut clusters: Vec<Vec<Vqbit8D>> = Vec::new();
        let mut assigned: HashMap<Uuid, bool> = HashMap::new();

        for vq in vqbits {
            if assigned.contains_key(&vq.id) {
                continue;
            }

            // Start new cluster with this point
            let mut cluster = vec![vq.clone()];
            assigned.insert(vq.id, true);

            // Find all points within threshold
            for other in vqbits {
                if assigned.contains_key(&other.id) {
                    continue;
                }

                let dist = self.spatial_distance(vq, other);
                if dist <= self.cluster_threshold_m as f64 {
                    cluster.push(other.clone());
                    assigned.insert(other.id, true);
                }
            }

            clusters.push(cluster);
        }

        clusters
    }

    /// Compute spatial distance between two vQbits (D0-D2)
    fn spatial_distance(&self, a: &Vqbit8D, b: &Vqbit8D) -> f64 {
        let dx = a.d0_x - b.d0_x;
        let dy = a.d1_y - b.d1_y;
        let dz = a.d2_z - b.d2_z;
        (dx * dx + dy * dy + dz * dz).sqrt()
    }

    /// Merge observations using inverse-uncertainty weighting
    fn merge_observations(&self, cluster: &[Vqbit8D]) -> Vqbit8D {
        if cluster.is_empty() {
            return Vqbit8D::default();
        }

        if cluster.len() == 1 {
            let mut m = cluster[0].clone();
            m.d6_social_coherence = 0.33;
            return m;
        }

        // Compute weights as inverse uncertainty (add small epsilon to avoid div by zero)
        let weights: Vec<f32> = cluster
            .iter()
            .map(|v| 1.0 / (v.d7_uncertainty + 0.01))
            .collect();

        let total_weight: f32 = weights.iter().sum();

        // Weighted average of positions
        let mut d0_x = 0.0;
        let mut d1_y = 0.0;
        let mut d2_z = 0.0;
        let mut d3_t = 0.0;
        let mut d4_env = 0.0f32;
        let mut d5_use = 0.0f32;

        for (vq, w) in cluster.iter().zip(weights.iter()) {
            let nw = *w / total_weight;
            d0_x += vq.d0_x * nw as f64;
            d1_y += vq.d1_y * nw as f64;
            d2_z += vq.d2_z * nw as f64;
            d3_t += vq.d3_t * nw as f64;
            d4_env += vq.d4_env_type * nw;
            d5_use += vq.d5_use_intensity * nw;
        }

        // For orientation, use the lowest-uncertainty source
        let best = cluster
            .iter()
            .min_by(|a, b| a.d7_uncertainty.partial_cmp(&b.d7_uncertainty).unwrap())
            .unwrap();

        // Merged uncertainty is reduced by fusion
        let merged_uncertainty: f32 = cluster
            .iter()
            .map(|v| v.d7_uncertainty)
            .fold(f32::INFINITY, f32::min)
            * 0.8;

        // Social coherence from number of agreeing sources
        let social_coherence = (cluster.len() as f32 / 3.0).min(1.0);

        // Collect parent IDs
        let parent_ids: Vec<Uuid> = cluster.iter().map(|v| v.id).collect();

        // Use most common domain
        let domain = cluster
            .iter()
            .next()
            .map(|v| v.domain.clone())
            .unwrap_or_else(|| "MERGED".to_string());

        Vqbit8D {
            id: Uuid::new_v4(),
            cell_id: best.cell_id,
            source_id: format!("merged:{}", cluster.len()),
            d0_x,
            d1_y,
            d2_z,
            d3_t,
            orientation: best.orientation.clone(),
            d4_env_type: d4_env,
            d5_use_intensity: d5_use,
            d6_social_coherence: social_coherence,
            d7_uncertainty: merged_uncertainty,
            domain,
            sensor_type: "FUSED".to_string(),
            timestamp_unix: Vqbit8D::now_unix(),
            raw_uncertainty_m: merged_uncertainty * 100.0,
            signature: None,
            parent_observations: parent_ids,
            fot_validated: false,
        }
    }

    /// Detect observations that conflict with merged truth
    fn detect_conflicts(&self, all: &[Vqbit8D], merged: &Vqbit8D) -> Vec<ConflictReport> {
        all.iter()
            .filter_map(|v| {
                let dist = self.spatial_distance(v, merged);
                if dist > self.conflict_threshold_m as f64 {
                    Some(ConflictReport {
                        vqbit_id: v.id,
                        source_id: v.source_id.clone(),
                        deviation_m: dist as f32,
                        domain: v.domain.clone(),
                    })
                } else {
                    None
                }
            })
            .collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn make_vqbit(x: f64, y: f64, z: f64, uncertainty: f32) -> Vqbit8D {
        let mut vq = Vqbit8D::new(
            Uuid::new_v4(),
            "test".to_string(),
            x,
            y,
            z,
            "TEST".to_string(),
        );
        vq.d7_uncertainty = uncertainty;
        vq
    }

    #[tokio::test]
    async fn test_coherence_single_source() {
        let engine = CoherenceEngine::default();
        let obs = vec![make_vqbit(0.0, 0.0, 0.0, 0.1)];

        let result = engine.compute_coherence(&obs).await.unwrap();
        assert!((result.score - 0.33).abs() < 0.01);
    }

    #[tokio::test]
    async fn test_coherence_multiple_agreeing() {
        let engine = CoherenceEngine::default();
        let obs = vec![
            make_vqbit(0.0, 0.0, 0.0, 0.1),
            make_vqbit(1.0, 1.0, 0.0, 0.2),
            make_vqbit(2.0, 0.5, 0.0, 0.15),
        ];

        let result = engine.compute_coherence(&obs).await.unwrap();
        assert!(result.score > 0.9);
        assert!(result.conflicts.is_empty());
    }

    #[tokio::test]
    async fn test_coherence_with_conflict() {
        let engine = CoherenceEngine::default();
        let obs = vec![
            make_vqbit(0.0, 0.0, 0.0, 0.1),
            make_vqbit(1.0, 1.0, 0.0, 0.2),
            make_vqbit(100.0, 100.0, 0.0, 0.3), // Conflict
        ];

        let result = engine.compute_coherence(&obs).await.unwrap();
        assert!(!result.conflicts.is_empty());
    }
}
