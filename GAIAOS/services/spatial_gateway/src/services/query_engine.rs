//! Query Engine - Virtue-Weighted Truth Queries
//!
//! Provides domain-aware queries over the world state.
//! Results are filtered and ranked by virtue weights.

use crate::model::vqbit::Vqbit8D;
use crate::services::virtue_weights::VirtueWeights;
use crate::storage::arango::{ArangoClient, BoundingBox};

/// Query engine for virtue-weighted truth queries
#[allow(dead_code)]
pub struct QueryEngine {
    arango: ArangoClient,
}

/// Query parameters
#[allow(dead_code)]
#[derive(Debug, Clone)]
pub struct QueryParams {
    /// Bounding box for spatial query
    pub bbox: BoundingBox,
    /// Domain for virtue weight selection
    pub domain: String,
    /// Override default virtue weights
    pub weights: Option<VirtueWeights>,
    /// Maximum results to return
    pub limit: Option<usize>,
    /// Minimum coherence score
    pub min_coherence: Option<f32>,
    /// Maximum staleness in seconds
    pub max_staleness_secs: Option<f64>,
}

/// Query result with virtue scoring
#[allow(dead_code)]
#[derive(Debug, Clone)]
pub struct ScoredResult {
    pub vqbit: Vqbit8D,
    pub virtue_score: f32,
    pub freshness_score: f32,
    pub precision_score: f32,
    pub coherence_score: f32,
}

#[allow(dead_code)]
impl QueryEngine {
    /// Create a new query engine
    pub fn new(arango: ArangoClient) -> Self {
        Self { arango }
    }

    /// Query with virtue-weighted scoring
    pub async fn query_with_virtues(
        &self,
        params: &QueryParams,
    ) -> Result<Vec<ScoredResult>, String> {
        // Get virtue weights for domain
        let weights = params
            .weights
            .clone()
            .unwrap_or_else(|| VirtueWeights::for_domain(&params.domain));

        // Query raw results from ArangoDB
        let raw_results = self.arango.query_bbox(&params.bbox).await?;

        // Filter and score results
        let now = Vqbit8D::now_unix();

        let mut scored: Vec<ScoredResult> = raw_results
            .into_iter()
            .filter(|vq| {
                // Filter by uncertainty threshold
                if vq.d7_uncertainty > weights.max_uncertainty {
                    return false;
                }

                // Filter by minimum coherence
                if let Some(min_coh) = params.min_coherence {
                    if vq.d6_social_coherence < min_coh {
                        return false;
                    }
                }

                // Filter by staleness
                if let Some(max_stale) = params.max_staleness_secs {
                    let age = now - vq.timestamp_unix;
                    if age > max_stale {
                        return false;
                    }
                }

                true
            })
            .map(|vq| self.score_result(&vq, &weights, now))
            .collect();

        // Sort by virtue score (descending)
        scored.sort_by(|a, b| b.virtue_score.partial_cmp(&a.virtue_score).unwrap());

        // Apply limit
        if let Some(limit) = params.limit {
            scored.truncate(limit);
        }

        Ok(scored)
    }

    /// Query by point with radius
    pub async fn query_near(
        &self,
        center_x: f64,
        center_y: f64,
        radius_m: f64,
        domain: &str,
        limit: Option<usize>,
    ) -> Result<Vec<ScoredResult>, String> {
        let params = QueryParams {
            bbox: BoundingBox {
                x_min: center_x - radius_m,
                x_max: center_x + radius_m,
                y_min: center_y - radius_m,
                y_max: center_y + radius_m,
                z_min: None,
                z_max: None,
            },
            domain: domain.to_string(),
            weights: None,
            limit,
            min_coherence: None,
            max_staleness_secs: None,
        };

        let mut results = self.query_with_virtues(&params).await?;

        // Additional filtering by actual distance
        results.retain(|r| {
            let dx = r.vqbit.d0_x - center_x;
            let dy = r.vqbit.d1_y - center_y;
            (dx * dx + dy * dy).sqrt() <= radius_m
        });

        // Re-sort by distance
        results.sort_by(|a, b| {
            let da = ((a.vqbit.d0_x - center_x).powi(2) + (a.vqbit.d1_y - center_y).powi(2)).sqrt();
            let db = ((b.vqbit.d0_x - center_x).powi(2) + (b.vqbit.d1_y - center_y).powi(2)).sqrt();
            da.partial_cmp(&db).unwrap()
        });

        Ok(results)
    }

    /// Query latest observations for each cell
    pub async fn query_latest_by_cell(
        &self,
        domain: Option<&str>,
        limit: Option<usize>,
    ) -> Result<Vec<Vqbit8D>, String> {
        if let Some(d) = domain {
            self.arango.query_by_domain(d, limit).await
        } else {
            // Query all domains
            let bbox = BoundingBox {
                x_min: f64::MIN,
                x_max: f64::MAX,
                y_min: f64::MIN,
                y_max: f64::MAX,
                z_min: None,
                z_max: None,
            };
            self.arango.query_bbox(&bbox).await
        }
    }

    /// Score a single result
    #[allow(dead_code)]
    fn score_result(&self, vq: &Vqbit8D, weights: &VirtueWeights, now: f64) -> ScoredResult {
        // Freshness score (exponential decay)
        let age = (now - vq.timestamp_unix).abs();
        let freshness_score = (-0.1 * weights.temporal_freshness * age as f32 / 60.0).exp();

        // Precision score (inverse of uncertainty)
        let precision_score = 1.0 - vq.d7_uncertainty;

        // Coherence score (social agreement)
        let coherence_score = vq.d6_social_coherence;

        // Combined virtue score
        let virtue_score = weights.temporal_freshness * freshness_score
            + weights.spatial_precision * precision_score
            + weights.social_agreement * coherence_score;

        ScoredResult {
            vqbit: vq.clone(),
            virtue_score,
            freshness_score,
            precision_score,
            coherence_score,
        }
    }
}

/// Multi-domain conflict resolution
#[allow(dead_code)]
pub struct ConflictResolver;

#[allow(dead_code)]
impl ConflictResolver {
    /// Resolve conflicts between observations from different domains
    pub fn resolve(observations: &[Vqbit8D]) -> Option<Vqbit8D> {
        if observations.is_empty() {
            return None;
        }

        if observations.len() == 1 {
            return Some(observations[0].clone());
        }

        // Sort by domain priority
        let mut sorted: Vec<&Vqbit8D> = observations.iter().collect();
        sorted.sort_by(|a, b| {
            let pa = crate::services::virtue_weights::domain_priority(&a.domain);
            let pb = crate::services::virtue_weights::domain_priority(&b.domain);
            pb.cmp(&pa)
        });

        // Use highest priority as base
        let mut result = sorted[0].clone();

        // Adjust uncertainty based on agreement
        let agreement_count = sorted
            .iter()
            .filter(|v| {
                let dx = v.d0_x - result.d0_x;
                let dy = v.d1_y - result.d1_y;
                (dx * dx + dy * dy).sqrt() < 10.0
            })
            .count();

        result.d6_social_coherence = (agreement_count as f32 / 3.0).min(1.0);

        Some(result)
    }
}
