//! View Generation Pipeline
//! 
//! Complete pipeline: Substrate → Projection → Virtue Gate → View

use anyhow::Result;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::RwLock;
use std::time::Instant;
use tracing::{debug, info};
use uuid::Uuid;

use crate::clients::{FranklinClient, SubstrateClient};
use crate::models::*;
use crate::quantum_projection::ProjectionOperator;

/// Complete pipeline: Substrate → Projection → Virtue Gate → View
pub struct ViewerPipeline {
    pub substrate_client: SubstrateClient,
    pub guardian_client: FranklinClient,
    pub projector: ProjectionOperator,
    pub default_virtue_threshold: f32,
    metrics: MetricsState,
}

/// Internal metrics tracking state
struct MetricsState {
    coherence_sum: RwLock<f64>,
    coherence_min: RwLock<f32>,
    coherence_max: RwLock<f32>,
    sample_count: AtomicUsize,
    total_points: AtomicUsize,
}

impl Default for MetricsState {
    fn default() -> Self {
        Self {
            coherence_sum: RwLock::new(0.0),
            coherence_min: RwLock::new(f32::INFINITY),
            coherence_max: RwLock::new(f32::NEG_INFINITY),
            sample_count: AtomicUsize::new(0),
            total_points: AtomicUsize::new(0),
        }
    }
}

impl ViewerPipeline {
    /// Create a new pipeline with default configuration
    pub fn new(
        substrate_client: SubstrateClient,
        guardian_client: FranklinClient,
        dimension_map: [usize; 3],
        default_virtue_threshold: f32,
    ) -> Self {
        Self {
            substrate_client,
            guardian_client,
            projector: ProjectionOperator::new(dimension_map),
            default_virtue_threshold,
            metrics: MetricsState::default(),
        }
    }
    
    /// Generate a projected view from the substrate
    pub async fn generate_view(&self, request: ViewRequest) -> Result<ViewResponse> {
        let start = Instant::now();
        
        // Use request dimension map or default
        let mut projector = self.projector.clone();
        projector.set_dimension_map(request.dimension_map);
        
        let virtue_threshold = request.virtue_threshold;
        let max_points = request.max_points;
        
        // 1. Query substrate for 8D quantum points
        debug!("Querying substrate for layers");
        let substrate_data = self.substrate_client
            .query_layer(request.layer_filter)
            .await?;
        
        let total_points_8d = substrate_data.total_points;
        
        // 2. Project each point and apply virtue gating
        let mut projected_layers = Vec::new();
        let mut total_displayed = 0;
        let mut all_coherences = Vec::new();
        
        for layer in substrate_data.layers {
            let mut projected_points = Vec::new();
            let mut virtue_scores = Vec::new();
            let mut layer_coherences = Vec::new();
            
            // Get virtue scores for all points in batch
            let scores = self.guardian_client.score_batch(&layer.points).await?;
            
            for (point_8d, virtue) in layer.points.iter().zip(scores.iter()) {
                // Virtue gate: only include if passes threshold
                if *virtue < virtue_threshold {
                    continue;
                }
                
                // Project to 3D
                let projected = projector.project(&point_8d.coord);
                
                projected_points.push(projected.clone());
                virtue_scores.push(*virtue);
                layer_coherences.push(projected.coherence);
                all_coherences.push(projected.coherence);
                
                // Performance limit
                if projected_points.len() >= max_points {
                    break;
                }
            }
            
            let coherence_avg = if !layer_coherences.is_empty() {
                layer_coherences.iter().sum::<f32>() / layer_coherences.len() as f32
            } else {
                0.0
            };
            
            total_displayed += projected_points.len();
            
            // Assign color based on layer name
            let color_hint = match layer.name.as_str() {
                "vQbit" => [0.4, 0.8, 1.0],      // Cyan
                "Agents" => [0.2, 1.0, 0.4],     // Green
                "Cells" => [1.0, 0.6, 0.2],      // Orange
                _ => [0.7, 0.7, 0.7],            // Gray
            };
            
            projected_layers.push(ProjectedLayer {
                id: Uuid::new_v4(),
                name: layer.name,
                points: projected_points,
                virtue_scores,
                coherence_avg,
                color_hint,
            });
        }
        
        // 3. Compute metadata
        let virtue_pass_rate = if total_points_8d > 0 {
            total_displayed as f32 / total_points_8d as f32
        } else {
            0.0
        };
        
        let (avg_coherence, min_coherence, max_coherence) = if !all_coherences.is_empty() {
            let avg = all_coherences.iter().sum::<f32>() / all_coherences.len() as f32;
            let min = all_coherences.iter().cloned().fold(f32::INFINITY, f32::min);
            let max = all_coherences.iter().cloned().fold(f32::NEG_INFINITY, f32::max);
            (avg, min, max)
        } else {
            (0.0, 0.0, 0.0)
        };
        
        let projection_time_ms = start.elapsed().as_secs_f64() * 1000.0;
        
        info!(
            "Generated view: {} points displayed from {} total, {:.1}% virtue pass rate, {:.2} avg coherence, {:.1}ms",
            total_displayed, total_points_8d, virtue_pass_rate * 100.0, avg_coherence, projection_time_ms
        );

        // Update metrics
        self.update_metrics(avg_coherence, min_coherence, max_coherence, total_displayed);

        Ok(ViewResponse {
            layers: projected_layers,
            metadata: ViewMetadata {
                total_points_8d,
                points_displayed: total_displayed,
                virtue_pass_rate,
                avg_coherence,
                min_coherence,
                max_coherence,
                projection_time_ms,
                dimension_map: request.dimension_map,
                virtue_threshold,
            },
        })
    }
    
    /// Check health of all dependencies
    pub async fn check_dependencies(&self) -> DependencyStatus {
        let substrate_ok = self.substrate_client.health_check().await;
        let guardian_ok = self.guardian_client.health_check().await;

        DependencyStatus {
            substrate: if substrate_ok { "ok".to_string() } else { "unavailable".to_string() },
            franklin_guardian: if guardian_ok { "ok".to_string() } else { "unavailable".to_string() },
            nats: "not_implemented".to_string(),
        }
    }

    /// Update internal metrics after a projection
    fn update_metrics(&self, avg: f32, min: f32, max: f32, points: usize) {
        if let Ok(mut sum) = self.metrics.coherence_sum.write() {
            *sum += avg as f64;
        }
        if let Ok(mut current_min) = self.metrics.coherence_min.write() {
            if min < *current_min {
                *current_min = min;
            }
        }
        if let Ok(mut current_max) = self.metrics.coherence_max.write() {
            if max > *current_max {
                *current_max = max;
            }
        }
        self.metrics.sample_count.fetch_add(1, Ordering::Relaxed);
        self.metrics.total_points.fetch_add(points, Ordering::Relaxed);
    }

    /// Get coherence metrics from recent projections
    pub async fn get_coherence_metrics(&self) -> CoherenceMetrics {
        let sample_count = self.metrics.sample_count.load(Ordering::Relaxed);
        let total_points = self.metrics.total_points.load(Ordering::Relaxed);

        let avg_coherence = if sample_count > 0 {
            if let Ok(sum) = self.metrics.coherence_sum.read() {
                (*sum / sample_count as f64) as f32
            } else {
                0.0
            }
        } else {
            0.0
        };

        let min_coherence = self.metrics.coherence_min.read()
            .map(|v| if *v == f32::INFINITY { 0.0 } else { *v })
            .unwrap_or(0.0);

        let max_coherence = self.metrics.coherence_max.read()
            .map(|v| if *v == f32::NEG_INFINITY { 0.0 } else { *v })
            .unwrap_or(0.0);

        CoherenceMetrics {
            avg_coherence,
            min_coherence,
            max_coherence,
            sample_count,
            total_points,
        }
    }
}
