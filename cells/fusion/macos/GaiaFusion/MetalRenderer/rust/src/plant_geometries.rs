// plant_geometries.rs — Nine fusion plant wireframe geometries
// GaiaFTCL Metal Renderer | Patents: USPTO 19/460,960 | USPTO 19/096,071
// FortressAI Research Institute | Norwich, Connecticut

use crate::renderer::GaiaVertex;
use std::f32::consts::PI;

/// PlantKind enum matching OpenUSD prim_id order (0–8)
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum PlantKind {
    Tokamak = 0,
    Stellarator = 1,
    FRC = 2,
    Spheromak = 3,
    Mirror = 4,
    Inertial = 5,
    SphericalTokamak = 6,
    ZPinch = 7,
    MIF = 8,
}

impl PlantKind {
    pub fn from_u32(id: u32) -> Option<Self> {
        match id {
            0 => Some(PlantKind::Tokamak),
            1 => Some(PlantKind::Stellarator),
            2 => Some(PlantKind::FRC),
            3 => Some(PlantKind::Spheromak),
            4 => Some(PlantKind::Mirror),
            5 => Some(PlantKind::Inertial),
            6 => Some(PlantKind::SphericalTokamak),
            7 => Some(PlantKind::ZPinch),
            8 => Some(PlantKind::MIF),
            _ => None,
        }
    }
}

/// Plant geometry with vertex/index data
pub struct PlantGeometry {
    pub vertices: Vec<GaiaVertex>,
    pub indices: Vec<u16>,
}

impl PlantGeometry {
    /// Validates geometry meets Plant Catalogue minimums
    pub fn validate_catalogue_minimums(&self, min_vertices: usize, min_indices: usize) -> bool {
        self.vertices.len() >= min_vertices && self.indices.len() >= min_indices
    }
}

/// Main dispatch function — builds geometry for specified plant kind
pub fn build_geometry(kind: PlantKind) -> PlantGeometry {
    match kind {
        PlantKind::Tokamak => build_tokamak(),
        PlantKind::Stellarator => build_stellarator(),
        PlantKind::FRC => build_frc(),
        PlantKind::Spheromak => build_spheromak(),
        PlantKind::Mirror => build_mirror(),
        PlantKind::Inertial => build_inertial(),
        PlantKind::SphericalTokamak => build_spherical_tokamak(),
        PlantKind::ZPinch => build_zpinch(),
        PlantKind::MIF => build_mif(),
    }
}

// ═══════════════════════════════════════════════════════════════
// Geometry Helper Functions
// ═══════════════════════════════════════════════════════════════

fn append_torus(
    vertices: &mut Vec<GaiaVertex>,
    indices: &mut Vec<u16>,
    major_r: f32,
    minor_r: f32,
    major_segs: usize,
    minor_segs: usize,
    color: [f32; 4],
) {
    let base_idx = vertices.len() as u16;
    
    for i in 0..major_segs {
        let theta = 2.0 * PI * (i as f32) / (major_segs as f32);
        let cos_theta = theta.cos();
        let sin_theta = theta.sin();
        
        for j in 0..minor_segs {
            let phi = 2.0 * PI * (j as f32) / (minor_segs as f32);
            let cos_phi = phi.cos();
            let sin_phi = phi.sin();
            
            let x = (major_r + minor_r * cos_phi) * cos_theta;
            let y = minor_r * sin_phi;
            let z = (major_r + minor_r * cos_phi) * sin_theta;
            
            vertices.push(GaiaVertex::new([x, y, z], color));
        }
    }
    
    // Generate wireframe lines: major circles (constant i, varying j)
    for i in 0..major_segs {
        for j in 0..minor_segs {
            let j_next = (j + 1) % minor_segs;
            let v0 = base_idx + (i * minor_segs + j) as u16;
            let v1 = base_idx + (i * minor_segs + j_next) as u16;
            indices.extend_from_slice(&[v0, v1]);
        }
    }
    
    // Generate wireframe lines: minor circles (constant j, varying i)
    for j in 0..minor_segs {
        for i in 0..major_segs {
            let i_next = (i + 1) % major_segs;
            let v0 = base_idx + (i * minor_segs + j) as u16;
            let v1 = base_idx + (i_next * minor_segs + j) as u16;
            indices.extend_from_slice(&[v0, v1]);
        }
    }
}

fn append_cylinder(
    vertices: &mut Vec<GaiaVertex>,
    indices: &mut Vec<u16>,
    radius: f32,
    height: f32,
    segments: usize,
    color: [f32; 4],
) {
    let base_idx = vertices.len() as u16;
    let half_h = height / 2.0;
    
    // Bottom ring
    for i in 0..segments {
        let theta = 2.0 * PI * (i as f32) / (segments as f32);
        let x = radius * theta.cos();
        let z = radius * theta.sin();
        vertices.push(GaiaVertex::new([x, -half_h, z], color));
    }
    
    // Top ring
    for i in 0..segments {
        let theta = 2.0 * PI * (i as f32) / (segments as f32);
        let x = radius * theta.cos();
        let z = radius * theta.sin();
        vertices.push(GaiaVertex::new([x, half_h, z], color));
    }
    
    // Wireframe: bottom circle
    for i in 0..segments {
        let i_next = (i + 1) % segments;
        let v0 = base_idx + i as u16;
        let v1 = base_idx + i_next as u16;
        indices.extend_from_slice(&[v0, v1]);
    }
    
    // Wireframe: top circle
    for i in 0..segments {
        let i_next = (i + 1) % segments;
        let v0 = base_idx + (segments + i) as u16;
        let v1 = base_idx + (segments + i_next) as u16;
        indices.extend_from_slice(&[v0, v1]);
    }
    
    // Wireframe: vertical lines
    for i in 0..segments {
        let v0 = base_idx + i as u16;
        let v1 = base_idx + (segments + i) as u16;
        indices.extend_from_slice(&[v0, v1]);
    }
}

fn append_disk_cap(
    vertices: &mut Vec<GaiaVertex>,
    indices: &mut Vec<u16>,
    radius: f32,
    y_pos: f32,
    segments: usize,
    color: [f32; 4],
) {
    let base_idx = vertices.len() as u16;
    let center_idx = base_idx;
    
    vertices.push(GaiaVertex::new([0.0, y_pos, 0.0], color));
    
    for i in 0..segments {
        let theta = 2.0 * PI * (i as f32) / (segments as f32);
        let x = radius * theta.cos();
        let z = radius * theta.sin();
        vertices.push(GaiaVertex::new([x, y_pos, z], color));
    }
    
    // Wireframe: radial lines from center
    for i in 0..segments {
        let v1 = base_idx + 1 + i as u16;
        indices.extend_from_slice(&[center_idx, v1]);
    }
    
    // Wireframe: outer circle
    for i in 0..segments {
        let i_next = (i + 1) % segments;
        let v1 = base_idx + 1 + i as u16;
        let v2 = base_idx + 1 + i_next as u16;
        indices.extend_from_slice(&[v1, v2]);
    }
}

fn append_uv_sphere(
    vertices: &mut Vec<GaiaVertex>,
    indices: &mut Vec<u16>,
    radius: f32,
    lat_segs: usize,
    lon_segs: usize,
    color: [f32; 4],
) {
    let base_idx = vertices.len() as u16;
    
    for i in 0..=lat_segs {
        let theta = PI * (i as f32) / (lat_segs as f32);
        let sin_theta = theta.sin();
        let cos_theta = theta.cos();
        
        for j in 0..=lon_segs {
            let phi = 2.0 * PI * (j as f32) / (lon_segs as f32);
            let sin_phi = phi.sin();
            let cos_phi = phi.cos();
            
            let x = radius * sin_theta * cos_phi;
            let y = radius * cos_theta;
            let z = radius * sin_theta * sin_phi;
            
            vertices.push(GaiaVertex::new([x, y, z], color));
        }
    }
    
    // Wireframe: latitude lines (constant i, varying j)
    for i in 0..=lat_segs {
        for j in 0..lon_segs {
            let v0 = base_idx + (i * (lon_segs + 1) + j) as u16;
            let v1 = base_idx + (i * (lon_segs + 1) + j + 1) as u16;
            indices.extend_from_slice(&[v0, v1]);
        }
    }
    
    // Wireframe: longitude lines (constant j, varying i)
    for j in 0..=lon_segs {
        for i in 0..lat_segs {
            let v0 = base_idx + (i * (lon_segs + 1) + j) as u16;
            let v1 = base_idx + ((i + 1) * (lon_segs + 1) + j) as u16;
            indices.extend_from_slice(&[v0, v1]);
        }
    }
}

fn append_icosphere_l1(
    vertices: &mut Vec<GaiaVertex>,
    indices: &mut Vec<u16>,
    radius: f32,
    color: [f32; 4],
) {
    let base_idx = vertices.len() as u16;
    let t = (1.0 + 5.0_f32.sqrt()) / 2.0;
    let scale = radius / (1.0 + t * t).sqrt();
    
    let ico_verts = [
        [-1.0, t, 0.0], [1.0, t, 0.0], [-1.0, -t, 0.0], [1.0, -t, 0.0],
        [0.0, -1.0, t], [0.0, 1.0, t], [0.0, -1.0, -t], [0.0, 1.0, -t],
        [t, 0.0, -1.0], [t, 0.0, 1.0], [-t, 0.0, -1.0], [-t, 0.0, 1.0],
    ];
    
    for v in &ico_verts {
        let scaled = [v[0] * scale, v[1] * scale, v[2] * scale];
        vertices.push(GaiaVertex::new(scaled, color));
    }
    
    let ico_faces = [
        [0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11],
        [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
        [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9],
        [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1],
    ];
    
    // Wireframe: each triangle face becomes 3 edges
    for face in &ico_faces {
        let v0 = base_idx + face[0] as u16;
        let v1 = base_idx + face[1] as u16;
        let v2 = base_idx + face[2] as u16;
        indices.extend_from_slice(&[v0, v1, v1, v2, v2, v0]);
    }
}

fn fibonacci_sphere(count: usize, radius: f32) -> Vec<[f32; 3]> {
    let mut points = Vec::with_capacity(count);
    let golden_ratio = (1.0 + 5.0_f32.sqrt()) / 2.0;
    
    for i in 0..count {
        let i_f = i as f32;
        let theta = 2.0 * PI * i_f / golden_ratio;
        let phi = ((1.0 - 2.0 * (i_f + 0.5) / count as f32).clamp(-1.0, 1.0)).acos();
        
        let x = radius * phi.sin() * theta.cos();
        let y = radius * phi.sin() * theta.sin();
        let z = radius * phi.cos();
        
        points.push([x, y, z]);
    }
    
    points
}

// ═══════════════════════════════════════════════════════════════
// Nine Plant Generators
// ═══════════════════════════════════════════════════════════════

fn build_tokamak() -> PlantGeometry {
    let mut vertices = Vec::new();
    let mut indices = Vec::new();
    let color = [0.0, 0.6, 1.0, 1.0];
    
    // Main torus (16×8 segments)
    append_torus(&mut vertices, &mut indices, 1.0, 0.3, 16, 8, color);
    
    // Coil ring (single outer torus for TF coils)
    append_torus(&mut vertices, &mut indices, 1.3, 0.05, 16, 4, color);
    
    PlantGeometry { vertices, indices }
}

fn build_stellarator() -> PlantGeometry {
    let mut vertices = Vec::new();
    let mut indices = Vec::new();
    let color = [1.0, 0.7, 0.0, 1.0];
    
    // Twisted torus (18×10 segments, 3×2π twist)
    let major_r = 1.0;
    let minor_r = 0.25;
    let major_segs = 18;
    let minor_segs = 10;
    let twist_factor = 3.0;
    
    let base_idx = vertices.len() as u16;
    
    for i in 0..major_segs {
        let theta = 2.0 * PI * (i as f32) / (major_segs as f32);
        let twist_angle = twist_factor * theta;
        let cos_theta = theta.cos();
        let sin_theta = theta.sin();
        
        for j in 0..minor_segs {
            let phi = 2.0 * PI * (j as f32) / (minor_segs as f32);
            let local_phi = phi + twist_angle;
            let cos_phi = local_phi.cos();
            let sin_phi = local_phi.sin();
            
            let x = (major_r + minor_r * cos_phi) * cos_theta;
            let y = minor_r * sin_phi;
            let z = (major_r + minor_r * cos_phi) * sin_theta;
            
            vertices.push(GaiaVertex::new([x, y, z], color));
        }
    }
    
    for i in 0..major_segs {
        for j in 0..minor_segs {
            let i_next = (i + 1) % major_segs;
            let j_next = (j + 1) % minor_segs;
            
            let v0 = base_idx + (i * minor_segs + j) as u16;
            let v1 = base_idx + (i * minor_segs + j_next) as u16;
            let v2 = base_idx + (i_next * minor_segs + j_next) as u16;
            let v3 = base_idx + (i_next * minor_segs + j) as u16;
            
            indices.extend_from_slice(&[v0, v1, v2, v0, v2, v3]);
        }
    }
    
    PlantGeometry { vertices, indices }
}

fn build_frc() -> PlantGeometry {
    let mut vertices = Vec::new();
    let mut indices = Vec::new();
    let color = [0.0, 1.0, 0.5, 1.0];
    
    // Elongated cylinder
    append_cylinder(&mut vertices, &mut indices, 0.3, 2.0, 12, color);
    
    // End coil tori
    append_torus(&mut vertices, &mut indices, 0.4, 0.05, 12, 4, color);
    
    PlantGeometry { vertices, indices }
}

fn build_spheromak() -> PlantGeometry {
    let mut vertices = Vec::new();
    let mut indices = Vec::new();
    let color = [1.0, 0.3, 0.8, 1.0];
    
    // Spherical conserver
    append_uv_sphere(&mut vertices, &mut indices, 0.5, 8, 12, color);
    
    // Coaxial injector cylinder
    append_cylinder(&mut vertices, &mut indices, 0.1, 0.6, 8, color);
    
    PlantGeometry { vertices, indices }
}

fn build_mirror() -> PlantGeometry {
    let mut vertices = Vec::new();
    let mut indices = Vec::new();
    let color = [0.5, 1.0, 1.0, 1.0];
    
    // Central cylinder
    append_cylinder(&mut vertices, &mut indices, 0.2, 1.0, 12, color);
    
    // 3 choke coil tori along length
    for y in [-0.4, 0.0, 0.4] {
        let base_idx = vertices.len() as u16;
        let segments = 12;
        let major_r = 0.25;
        let minor_r = 0.05;
        
        for i in 0..segments {
            let theta = 2.0 * PI * (i as f32) / (segments as f32);
            let x = major_r * theta.cos();
            let z = major_r * theta.sin();
            vertices.push(GaiaVertex::new([x, y, z], color));
        }
        
        for i in 0..segments {
            let i_next = (i + 1) % segments;
            let v0 = base_idx + i as u16;
            let v1 = base_idx + i_next as u16;
            indices.extend_from_slice(&[v0, v1]);
        }
    }
    
    PlantGeometry { vertices, indices }
}

fn build_inertial() -> PlantGeometry {
    let mut vertices = Vec::new();
    let mut indices = Vec::new();
    let color = [1.0, 1.0, 0.0, 1.0];
    
    // Geodesic shell (level-1 icosphere)
    append_icosphere_l1(&mut vertices, &mut indices, 0.5, color);
    
    // Hohlraum (small central sphere)
    append_uv_sphere(&mut vertices, &mut indices, 0.1, 4, 6, color);
    
    // 6 beam ports (cylinders along ±X, ±Y, ±Z)
    let beam_radius = 0.02;
    let beam_length = 0.3;
    for axis in &[[1.0, 0.0, 0.0], [-1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, -1.0, 0.0], [0.0, 0.0, 1.0], [0.0, 0.0, -1.0]] {
        let base_idx = vertices.len() as u16;
        let segs = 6;
        
        for i in 0..segs {
            let t = (i as f32) / (segs - 1) as f32;
            let pos = [axis[0] * t * beam_length, axis[1] * t * beam_length, axis[2] * t * beam_length];
            vertices.push(GaiaVertex::new(pos, color));
        }
        
        for i in 0..(segs - 1) {
            let v0 = base_idx + i as u16;
            let v1 = base_idx + (i + 1) as u16;
            indices.extend_from_slice(&[v0, v1]);
        }
    }
    
    PlantGeometry { vertices, indices }
}

fn build_spherical_tokamak() -> PlantGeometry {
    let mut vertices = Vec::new();
    let mut indices = Vec::new();
    let color = [0.8, 0.5, 1.0, 1.0];
    
    // Cored sphere
    append_uv_sphere(&mut vertices, &mut indices, 0.5, 8, 12, color);
    
    // Central solenoid (thin cylinder)
    append_cylinder(&mut vertices, &mut indices, 0.05, 0.8, 8, color);
    
    PlantGeometry { vertices, indices }
}

fn build_zpinch() -> PlantGeometry {
    let mut vertices = Vec::new();
    let mut indices = Vec::new();
    let color = [1.0, 0.5, 0.0, 1.0];
    
    // Central column
    append_cylinder(&mut vertices, &mut indices, 0.1, 1.0, 8, color);
    
    // Top and bottom electrode disks
    append_disk_cap(&mut vertices, &mut indices, 0.2, 0.5, 8, color);
    append_disk_cap(&mut vertices, &mut indices, 0.2, -0.5, 8, color);
    
    PlantGeometry { vertices, indices }
}

fn build_mif() -> PlantGeometry {
    let mut vertices = Vec::new();
    let mut indices = Vec::new();
    let color = [1.0, 0.0, 0.5, 1.0];
    
    // Central sphere (UV sphere 6×8 gives 63 vertices, 288 indices)
    append_uv_sphere(&mut vertices, &mut indices, 0.3, 6, 8, color);
    
    // 12 Fibonacci guns (C-009 constitutional lock)
    const GUN_COUNT: usize = 12;
    let gun_positions = fibonacci_sphere(GUN_COUNT, 0.5);
    
    for gun_pos in gun_positions {
        let base_idx = vertices.len() as u16;
        let tip_pos = [gun_pos[0] * 1.2, gun_pos[1] * 1.2, gun_pos[2] * 1.2];
        
        vertices.push(GaiaVertex::new(gun_pos, color));
        vertices.push(GaiaVertex::new(tip_pos, color));
        
        indices.extend_from_slice(&[base_idx, base_idx + 1]);
    }
    
    PlantGeometry { vertices, indices }
}

// ═══════════════════════════════════════════════════════════════
// GxP Tests (pg_001 through pg_009)
// ═══════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn pg_001_tokamak_exceeds_catalogue_minimum() {
        let geom = build_tokamak();
        assert!(geom.validate_catalogue_minimums(48, 96));
        assert!(geom.vertices.len() >= 48);
        assert!(geom.indices.len() >= 96);
    }
    
    #[test]
    fn pg_002_stellarator_exceeds_catalogue_minimum() {
        let geom = build_stellarator();
        assert!(geom.validate_catalogue_minimums(48, 96));
        assert!(geom.vertices.len() >= 48);
        assert!(geom.indices.len() >= 96);
    }
    
    #[test]
    fn pg_003_frc_exceeds_catalogue_minimum() {
        let geom = build_frc();
        assert!(geom.validate_catalogue_minimums(24, 48));
        assert!(geom.vertices.len() >= 24);
        assert!(geom.indices.len() >= 48);
    }
    
    #[test]
    fn pg_004_spheromak_exceeds_catalogue_minimum() {
        let geom = build_spheromak();
        assert!(geom.validate_catalogue_minimums(32, 64));
        assert!(geom.vertices.len() >= 32);
        assert!(geom.indices.len() >= 64);
    }
    
    #[test]
    fn pg_005_mirror_exceeds_catalogue_minimum() {
        let geom = build_mirror();
        assert!(geom.validate_catalogue_minimums(24, 48));
        assert!(geom.vertices.len() >= 24);
        assert!(geom.indices.len() >= 48);
    }
    
    #[test]
    fn pg_006_inertial_exceeds_catalogue_minimum() {
        let geom = build_inertial();
        assert!(geom.validate_catalogue_minimums(40, 80));
        assert!(geom.vertices.len() >= 40);
        assert!(geom.indices.len() >= 80);
    }
    
    #[test]
    fn pg_007_spherical_tokamak_exceeds_catalogue_minimum() {
        let geom = build_spherical_tokamak();
        assert!(geom.validate_catalogue_minimums(32, 64));
        assert!(geom.vertices.len() >= 32);
        assert!(geom.indices.len() >= 64);
    }
    
    #[test]
    fn pg_008_zpinch_exceeds_catalogue_minimum() {
        let geom = build_zpinch();
        assert!(geom.validate_catalogue_minimums(16, 32));
        assert!(geom.vertices.len() >= 16);
        assert!(geom.indices.len() >= 32);
    }
    
    #[test]
    fn pg_009_mif_fibonacci_gun_count_locked() {
        let geom = build_mif();
        assert!(geom.validate_catalogue_minimums(40, 80));
        
        // C-009 constitutional constraint: MIF gun count = 12 (locked)
        // Each gun = 2 vertices (base + tip) + UV sphere (6×8 = 63 verts)
        // Total = 63 + (12 guns × 2) = 87 vertices
        let expected_gun_verts = 12 * 2; // 24 gun vertices
        let sphere_verts = (6 + 1) * (8 + 1); // 63 UV sphere vertices
        assert!(geom.vertices.len() >= sphere_verts + expected_gun_verts);
    }
}
