//! Data Models (Client-side mirror of server models)

use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// A point projected from 8D to 3D
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProjectedPoint {
    pub position: [f32; 3],
    pub original_coord: [f32; 8],
    pub coherence: f32,
}

/// A projected layer with virtue scores
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProjectedLayer {
    pub id: Uuid,
    pub name: String,
    pub points: Vec<ProjectedPoint>,
    pub virtue_scores: Vec<f32>,
    pub coherence_avg: f32,
    #[serde(default)]
    pub color_hint: [f32; 3],
}

/// View metadata
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ViewMetadata {
    pub total_points_8d: usize,
    pub points_displayed: usize,
    pub virtue_pass_rate: f32,
    pub avg_coherence: f32,
    pub min_coherence: f32,
    pub max_coherence: f32,
    pub projection_time_ms: f64,
    pub dimension_map: [usize; 3],
    pub virtue_threshold: f32,
}

/// Complete view response from server
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ViewResponse {
    pub layers: Vec<ProjectedLayer>,
    pub metadata: ViewMetadata,
}

impl Default for ViewMetadata {
    fn default() -> Self {
        Self {
            total_points_8d: 0,
            points_displayed: 0,
            virtue_pass_rate: 0.0,
            avg_coherence: 0.0,
            min_coherence: 0.0,
            max_coherence: 0.0,
            projection_time_ms: 0.0,
            dimension_map: [0, 2, 5],
            virtue_threshold: 0.90,
        }
    }
}

impl Default for ViewResponse {
    fn default() -> Self {
        Self {
            layers: Vec::new(),
            metadata: ViewMetadata::default(),
        }
    }
}
