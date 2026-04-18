//! Data Models for Dimensional Viewer
//!
//! Request/response types for the projection API.

use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::quantum_projection::ProjectedPoint;

/// Layer filter for querying substrate
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LayerFilter {
    /// Filter by layer name (optional)
    #[serde(default)]
    pub layer_name: Option<String>,

    /// Filter by layer type (optional)
    #[serde(default)]
    pub layer_type: Option<String>,

    /// Bounding box filter [min_x, min_y, min_z, max_x, max_y, max_z] in 8D
    #[serde(default)]
    pub bounds_8d: Option<[f32; 16]>, // 8D min + 8D max
}

/// Request for generating a projected view
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ViewRequest {
    /// Cell identifier
    pub cell_id: String,

    /// Layer filter
    #[serde(default)]
    pub layer_filter: Option<LayerFilter>,

    /// Which 8D dimensions to project to 3D axes [x, y, z]
    #[serde(default = "default_dimension_map")]
    pub dimension_map: [usize; 3],

    /// Minimum virtue score to display (0.0-1.0)
    #[serde(default = "default_virtue_threshold")]
    pub virtue_threshold: f32,

    /// Maximum points to return (performance limit)
    #[serde(default = "default_max_points")]
    pub max_points: usize,
}

fn default_dimension_map() -> [usize; 3] {
    [0, 2, 5]
}
fn default_virtue_threshold() -> f32 {
    0.90
}
fn default_max_points() -> usize {
    10000
}

/// A projected layer with virtue scores
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProjectedLayer {
    /// Layer identifier
    pub id: Uuid,

    /// Layer name
    pub name: String,

    /// Projected points
    pub points: Vec<ProjectedPoint>,

    /// Per-point virtue scores (parallel to points)
    pub virtue_scores: Vec<f32>,

    /// Average coherence for this layer
    pub coherence_avg: f32,

    /// Layer color hint [r, g, b]
    #[serde(default)]
    pub color_hint: [f32; 3],
}

/// Metadata about the view generation
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ViewMetadata {
    /// Total points in substrate (before filtering)
    pub total_points_8d: usize,

    /// Points displayed (after virtue filtering)
    pub points_displayed: usize,

    /// Percentage passing virtue gate
    pub virtue_pass_rate: f32,

    /// Average coherence across all displayed points
    pub avg_coherence: f32,

    /// Minimum coherence
    pub min_coherence: f32,

    /// Maximum coherence
    pub max_coherence: f32,

    /// Time to generate projection (ms)
    pub projection_time_ms: f64,

    /// Dimension map used
    pub dimension_map: [usize; 3],

    /// Virtue threshold used
    pub virtue_threshold: f32,
}

/// Complete view response
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ViewResponse {
    /// Projected layers
    pub layers: Vec<ProjectedLayer>,

    /// View metadata
    pub metadata: ViewMetadata,
}

/// Health check response
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HealthResponse {
    pub status: String,
    pub service: String,
    pub version: String,
    pub substrate_connected: bool,
    pub guardian_connected: bool,
}

/// Dependency status response
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DependencyStatus {
    pub substrate: String,
    pub franklin_guardian: String,
    pub nats: String,
}

/// Error response
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ErrorResponse {
    pub error: String,
    pub code: String,
}

/// Substrate layer data (from quantum substrate)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SubstrateLayer {
    pub name: String,
    pub points: Vec<SubstratePoint>,
}

/// Substrate point (8D quantum state)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SubstratePoint {
    pub id: Uuid,
    pub coord: [f32; 8],
    #[serde(default)]
    pub metadata: serde_json::Value,
}

/// Substrate query response
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SubstrateData {
    pub layers: Vec<SubstrateLayer>,
    pub total_points: usize,
}

/// Virtue score response from Franklin Guardian
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VirtueScore {
    pub score: f32,
    pub dimensions: VirtueDimensions,
}

/// Individual virtue dimensions
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VirtueDimensions {
    pub truth: f32,
    pub justice: f32,
    pub courage: f32,
    pub temperance: f32,
    pub wisdom: f32,
}

impl Default for VirtueDimensions {
    fn default() -> Self {
        Self {
            truth: 1.0,
            justice: 1.0,
            courage: 1.0,
            temperance: 1.0,
            wisdom: 1.0,
        }
    }
}

/// Coherence metrics from recent projections
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CoherenceMetrics {
    /// Average coherence across recent projections
    pub avg_coherence: f32,
    /// Minimum coherence observed
    pub min_coherence: f32,
    /// Maximum coherence observed
    pub max_coherence: f32,
    /// Number of projections sampled
    pub sample_count: usize,
    /// Total points projected
    pub total_points: usize,
}
