//! Quantum Dimensional Projection Operator
//!
//! Projects 8D UUM quantum coordinates to 3D viewer space while preserving
//! maximum coherence. Tracks information loss from dimensionality reduction.

use nalgebra::{SMatrix, SVector};
use serde::{Deserialize, Serialize};

// Type aliases for clearer code
type Matrix3x8 = SMatrix<f32, 3, 8>;
type Vector8 = SVector<f32, 8>;

/// 8D → 3D projection preserving maximum coherence
#[derive(Debug, Clone)]
pub struct ProjectionOperator {
    /// Which UUM-8D dimensions map to viewer axes (e.g., [0, 2, 5])
    pub dimension_map: [usize; 3],

    /// Projection matrix (3x8) learned to preserve local structure
    projection_matrix: Matrix3x8,

    /// Coherence preservation weight (0.0-1.0)
    pub coherence_weight: f32,
}

impl ProjectionOperator {
    /// Create a new projection operator with specified dimension mapping
    pub fn new(dimension_map: [usize; 3]) -> Self {
        // Validate dimensions
        for &dim in &dimension_map {
            assert!(dim < 8, "Dimension index must be < 8");
        }

        // Build projection matrix that selects the specified dimensions
        let mut projection_matrix = Matrix3x8::zeros();
        for (row, &col) in dimension_map.iter().enumerate() {
            projection_matrix[(row, col)] = 1.0;
        }

        Self {
            dimension_map,
            projection_matrix,
            coherence_weight: 1.0,
        }
    }

    /// Create with a custom learned projection matrix
    pub fn with_matrix(dimension_map: [usize; 3], matrix: Matrix3x8) -> Self {
        Self {
            dimension_map,
            projection_matrix: matrix,
            coherence_weight: 1.0,
        }
    }

    /// Project 8D quantum coordinate to 3D viewer space
    pub fn project(&self, coord_8d: &[f32; 8]) -> ProjectedPoint {
        let vec8 = Vector8::from_row_slice(coord_8d);
        let vec3 = self.projection_matrix * vec8;

        // Compute coherence loss from dimensionality reduction
        let coherence_loss = self.compute_coherence_loss(coord_8d);

        ProjectedPoint {
            position: [vec3[0], vec3[1], vec3[2]],
            original_coord: *coord_8d,
            coherence: (1.0 - coherence_loss) * self.coherence_weight,
        }
    }

    /// Compute information lost by not displaying hidden dimensions
    fn compute_coherence_loss(&self, coord: &[f32; 8]) -> f32 {
        // Energy in hidden dimensions (not in dimension_map)
        let hidden_energy: f32 = coord
            .iter()
            .enumerate()
            .filter(|(i, _)| !self.dimension_map.contains(i))
            .map(|(_, x)| x.powi(2))
            .sum();

        // Total energy across all dimensions
        let total_energy: f32 = coord.iter().map(|x| x.powi(2)).sum();

        if total_energy < 1e-6 {
            0.0
        } else {
            hidden_energy / total_energy
        }
    }

    /// Update dimension mapping dynamically
    pub fn set_dimension_map(&mut self, new_map: [usize; 3]) {
        for &dim in &new_map {
            assert!(dim < 8, "Dimension index must be < 8");
        }

        self.dimension_map = new_map;

        // Rebuild projection matrix
        self.projection_matrix = Matrix3x8::zeros();
        for (row, &col) in new_map.iter().enumerate() {
            self.projection_matrix[(row, col)] = 1.0;
        }
    }

    /// Get the current projection matrix
    pub fn matrix(&self) -> &Matrix3x8 {
        &self.projection_matrix
    }
}

/// A point projected from 8D to 3D with coherence tracking
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProjectedPoint {
    /// 3D viewer coordinates
    pub position: [f32; 3],

    /// Original 8D UUM coordinate (for tooltip/detail view)
    pub original_coord: [f32; 8],

    /// How much information preserved (0.0-1.0)
    /// 1.0 = all energy in displayed dimensions
    /// 0.0 = all energy in hidden dimensions
    pub coherence: f32,
}

/// Batch projection result with statistics
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProjectionBatch {
    pub points: Vec<ProjectedPoint>,
    pub avg_coherence: f32,
    pub min_coherence: f32,
    pub max_coherence: f32,
}

impl ProjectionOperator {
    /// Project a batch of points with statistics
    pub fn project_batch(&self, coords: &[[f32; 8]]) -> ProjectionBatch {
        let points: Vec<ProjectedPoint> = coords.iter().map(|c| self.project(c)).collect();

        if points.is_empty() {
            return ProjectionBatch {
                points,
                avg_coherence: 0.0,
                min_coherence: 0.0,
                max_coherence: 0.0,
            };
        }

        let coherences: Vec<f32> = points.iter().map(|p| p.coherence).collect();
        let avg_coherence = coherences.iter().sum::<f32>() / coherences.len() as f32;
        let min_coherence = coherences.iter().cloned().fold(f32::INFINITY, f32::min);
        let max_coherence = coherences.iter().cloned().fold(f32::NEG_INFINITY, f32::max);

        ProjectionBatch {
            points,
            avg_coherence,
            min_coherence,
            max_coherence,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_projection_basic() {
        let projector = ProjectionOperator::new([0, 1, 2]);

        let coord = [1.0, 2.0, 3.0, 0.0, 0.0, 0.0, 0.0, 0.0];
        let projected = projector.project(&coord);

        assert_eq!(projected.position, [1.0, 2.0, 3.0]);
        assert!((projected.coherence - 1.0).abs() < 0.01); // All energy in displayed dims
    }

    #[test]
    fn test_coherence_loss() {
        let projector = ProjectionOperator::new([0, 1, 2]);

        // Half energy in displayed dims, half in hidden
        let coord = [1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 0.0, 0.0];
        let projected = projector.project(&coord);

        // 3 dims shown, 3 dims hidden with equal energy = 50% coherence
        assert!((projected.coherence - 0.5).abs() < 0.01);
    }

    #[test]
    fn test_dimension_mapping() {
        let projector = ProjectionOperator::new([0, 2, 5]);

        let coord = [1.0, 0.0, 2.0, 0.0, 0.0, 3.0, 0.0, 0.0];
        let projected = projector.project(&coord);

        assert_eq!(projected.position, [1.0, 2.0, 3.0]);
    }
}
