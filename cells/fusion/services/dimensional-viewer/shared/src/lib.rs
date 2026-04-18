//! Shared types for GaiaOS Dimensional Viewer
//!
//! This crate contains data structures shared between client (WASM) and server (native).
//! NO platform-specific code allowed.

#![cfg_attr(not(feature = "server"), no_std)]
#[cfg(not(feature = "server"))]
extern crate alloc;

use serde::{Deserialize, Serialize};

#[cfg(not(feature = "server"))]
use alloc::vec::Vec;
#[cfg(not(feature = "server"))]
use alloc::string::String;

/// 8D coordinate in UUM substrate
#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub struct Coord8D {
    pub coords: [f32; 8],
}

impl Coord8D {
    pub fn new(coords: [f32; 8]) -> Self {
        Self { coords }
    }

    pub fn zero() -> Self {
        Self { coords: [0.0; 8] }
    }

    pub fn norm(&self) -> f32 {
        self.coords.iter().map(|x| x * x).sum::<f32>().sqrt()
    }

    pub fn normalize(&self) -> Self {
        let n = self.norm();
        if n > 0.0 {
            let mut result = *self;
            for coord in &mut result.coords {
                *coord /= n;
            }
            result
        } else {
            *self
        }
    }

    pub fn dot(&self, other: &Coord8D) -> f32 {
        self.coords
            .iter()
            .zip(&other.coords)
            .map(|(a, b)| a * b)
            .sum()
    }
}

/// 3D projection of an 8D coordinate
#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub struct Projection3D {
    pub x: f32,
    pub y: f32,
    pub z: f32,
    pub coherence_loss: f32, // 0.0 = no information lost, 1.0 = maximum loss
}

/// Projection matrix: 8D → 3D
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProjectionMatrix {
    /// 3x8 matrix (3 output dimensions × 8 input dimensions)
    pub matrix: [[f32; 8]; 3],
}

impl ProjectionMatrix {
    pub fn default_projection() -> Self {
        // Default: project first 3 dimensions directly, ignore others
        Self {
            matrix: [
                [1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0], // X = D0
                [0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0], // Y = D1
                [0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0], // Z = D2
            ],
        }
    }

    pub fn project(&self, coord: &Coord8D) -> Projection3D {
        let x = self.matrix[0]
            .iter()
            .zip(&coord.coords)
            .map(|(m, c)| m * c)
            .sum();
        let y = self.matrix[1]
            .iter()
            .zip(&coord.coords)
            .map(|(m, c)| m * c)
            .sum();
        let z = self.matrix[2]
            .iter()
            .zip(&coord.coords)
            .map(|(m, c)| m * c)
            .sum();

        // Compute coherence loss (information lost in projection)
        // For default projection: dimensions 3-7 are lost
        let lost_energy: f32 = coord.coords[3..8].iter().map(|x| x * x).sum();
        let total_energy: f32 = coord.coords.iter().map(|x| x * x).sum();
        let coherence_loss = if total_energy > 0.0 {
            (lost_energy / total_energy).clamp(0.0, 1.0)
        } else {
            0.0
        };

        Projection3D {
            x,
            y,
            z,
            coherence_loss,
        }
    }
}

/// Virtue score (0.0 - 1.0)
#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub struct VirtueScore(pub f32);

impl VirtueScore {
    pub fn new(score: f32) -> Self {
        Self(score.clamp(0.0, 1.0))
    }

    pub fn value(&self) -> f32 {
        self.0
    }

    /// Convert to HSV color (Hue based on virtue)
    /// High virtue (1.0) = Blue (240°)
    /// Low virtue (0.0) = Red (0°)
    pub fn to_hsv(&self) -> (f32, f32, f32) {
        let hue = self.0 * 240.0; // 0° (red) to 240° (blue)
        let saturation = 0.8;
        let value = 0.6 + (self.0 * 0.4); // Brighter for higher virtue
        (hue, saturation, value)
    }
}

/// World tensor: collection of 8D points with virtue scores
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorldTensor {
    pub points: Vec<VisualizationPoint>,
    pub timestamp: f64,
    pub cell_id: Option<String>,
}

/// Single visualization point
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VisualizationPoint {
    pub coord_8d: Coord8D,
    pub virtue: VirtueScore,
    pub label: Option<String>,
    pub layer: String,
}

/// Delta update (memory-efficient)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorldTensorDelta {
    pub added: Vec<VisualizationPoint>,
    pub removed: Vec<usize>, // Indices
    pub updated: Vec<(usize, VisualizationPoint)>,
    pub version: u64,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_coord8d_norm() {
        let coord = Coord8D::new([1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]);
        assert!((coord.norm() - 1.0).abs() < 0.001);
    }

    #[test]
    fn test_coord8d_normalize() {
        let coord = Coord8D::new([3.0, 4.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]);
        let normalized = coord.normalize();
        assert!((normalized.norm() - 1.0).abs() < 0.001);
    }

    #[test]
    fn test_projection_default() {
        let coord = Coord8D::new([1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0]);
        let proj_matrix = ProjectionMatrix::default_projection();
        let proj = proj_matrix.project(&coord);

        assert_eq!(proj.x, 1.0);
        assert_eq!(proj.y, 2.0);
        assert_eq!(proj.z, 3.0);
        assert!(proj.coherence_loss > 0.0); // Lost dims 3-7
    }

    #[test]
    fn test_virtue_to_hsv() {
        let high_virtue = VirtueScore::new(1.0);
        let (h, s, v) = high_virtue.to_hsv();
        assert_eq!(h, 240.0); // Blue

        let low_virtue = VirtueScore::new(0.0);
        let (h, _, _) = low_virtue.to_hsv();
        assert_eq!(h, 0.0); // Red
    }
}
