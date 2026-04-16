//! GaiaFTCL Fusion Plant Geometry Library
//!
//! Procedural parametric wireframe geometries for the nine canonical fusion
//! plant topologies defined in the Plant Catalogue and patents
//! USPTO 19/460,960 | USPTO 19/096,071.
//!
//! # Plant kind IDs — must match USD prim_id order in rust_fusion_usd_parser
//!
//! | ID | Plant            | Physical topology                               |
//! |----|------------------|-------------------------------------------------|
//! |  0 | Tokamak          | Nested torus vessel + PF coil ring              |
//! |  1 | Stellarator      | Twisted helical torus (3-period, W7-X style)    |
//! |  2 | FRC              | Elongated cylinder + mirror end coils           |
//! |  3 | Spheromak        | Spherical conserver + coaxial gun injector      |
//! |  4 | Mirror           | Cylinder + three magnetic mirror choke coils    |
//! |  5 | Inertial         | Geodesic target chamber + hohlraum + beamlines  |
//! |  6 | SphericalTokamak | Compact sphere + central solenoid               |
//! |  7 | ZPinch           | Plasma column + electrode disks                 |
//! |  8 | MIF              | Icosphere + 12 Fibonacci plasma guns            |
//!
//! # Design constraints
//! - All generation code is platform-independent (no Metal, no GPU dependency).
//!   Geometry is uploaded to the GPU separately via `MetalRenderer::switch_plant()`,
//!   which IS macOS-only.
//! - Minimum vertex / index counts from the Plant Catalogue are constants below.
//!   Constitutional constraint C-005 requires vertex count ≥ catalogue minimum.
//! - MIF Fibonacci gun placement (12 guns) is constitutionally locked (C-009).
//!   Any change to that count requires full PQ-CSE re-execution.
//!
//! © 2026 Richard Gillespie — FortressAI Research Institute | Norwich, Connecticut

use std::collections::HashMap;
use std::f32::consts::PI;

use crate::renderer::GaiaVertex;

// ─────────────────────────────────────────────────────────────────────────────
// Plant Catalogue — minimum vertex / index counts
// Source: wiki/Composite-App-UI-Requirements.md § Plant Catalogue
// Constitutional constraint C-005: vertex_count ≥ plant_catalogue_minimum
// ─────────────────────────────────────────────────────────────────────────────

pub const TOKAMAK_MIN_VERTICES:            usize = 48;
pub const TOKAMAK_MIN_INDICES:             usize = 96;
pub const STELLARATOR_MIN_VERTICES:        usize = 48;
pub const STELLARATOR_MIN_INDICES:         usize = 96;
pub const FRC_MIN_VERTICES:                usize = 24;
pub const FRC_MIN_INDICES:                 usize = 48;
pub const SPHEROMAK_MIN_VERTICES:          usize = 32;
pub const SPHEROMAK_MIN_INDICES:           usize = 64;
pub const MIRROR_MIN_VERTICES:             usize = 24;
pub const MIRROR_MIN_INDICES:              usize = 48;
pub const INERTIAL_MIN_VERTICES:           usize = 40;
pub const INERTIAL_MIN_INDICES:            usize = 80;
pub const SPHERICAL_TOKAMAK_MIN_VERTICES:  usize = 32;
pub const SPHERICAL_TOKAMAK_MIN_INDICES:   usize = 64;
pub const ZPINCH_MIN_VERTICES:             usize = 16;
pub const ZPINCH_MIN_INDICES:              usize = 32;
pub const MIF_MIN_VERTICES:                usize = 40;
pub const MIF_MIN_INDICES:                 usize = 80;

// ─────────────────────────────────────────────────────────────────────────────
// PlantKind
// ─────────────────────────────────────────────────────────────────────────────

/// Canonical fusion plant topology identifiers.
///
/// Integer values match the USD prim_id order from `rust_fusion_usd_parser`
/// and the `plant_kind` parameter in the UUM-8D WASM FFI.
#[repr(u32)]
#[derive(Copy, Clone, Debug, PartialEq, Eq, Hash)]
pub enum PlantKind {
    Tokamak          = 0,
    Stellarator      = 1,
    FRC              = 2,
    Spheromak        = 3,
    Mirror           = 4,
    Inertial         = 5,
    SphericalTokamak = 6,
    ZPinch           = 7,
    MIF              = 8,
}

impl PlantKind {
    /// Parse from a `u32` plant_kind_id.
    /// Returns `None` for any value outside 0–8.
    pub fn from_u32(v: u32) -> Option<Self> {
        match v {
            0 => Some(Self::Tokamak),
            1 => Some(Self::Stellarator),
            2 => Some(Self::FRC),
            3 => Some(Self::Spheromak),
            4 => Some(Self::Mirror),
            5 => Some(Self::Inertial),
            6 => Some(Self::SphericalTokamak),
            7 => Some(Self::ZPinch),
            8 => Some(Self::MIF),
            _ => None,
        }
    }

    /// All nine plant kinds in USD prim_id order (0–8).
    pub fn all() -> [PlantKind; 9] {
        [
            PlantKind::Tokamak,
            PlantKind::Stellarator,
            PlantKind::FRC,
            PlantKind::Spheromak,
            PlantKind::Mirror,
            PlantKind::Inertial,
            PlantKind::SphericalTokamak,
            PlantKind::ZPinch,
            PlantKind::MIF,
        ]
    }

    /// Plant Catalogue minimum vertex count (constitutional constraint C-005).
    pub fn min_vertices(self) -> usize {
        match self {
            PlantKind::Tokamak          => TOKAMAK_MIN_VERTICES,
            PlantKind::Stellarator      => STELLARATOR_MIN_VERTICES,
            PlantKind::FRC              => FRC_MIN_VERTICES,
            PlantKind::Spheromak        => SPHEROMAK_MIN_VERTICES,
            PlantKind::Mirror           => MIRROR_MIN_VERTICES,
            PlantKind::Inertial         => INERTIAL_MIN_VERTICES,
            PlantKind::SphericalTokamak => SPHERICAL_TOKAMAK_MIN_VERTICES,
            PlantKind::ZPinch           => ZPINCH_MIN_VERTICES,
            PlantKind::MIF              => MIF_MIN_VERTICES,
        }
    }

    /// Plant Catalogue minimum index count.
    pub fn min_indices(self) -> usize {
        match self {
            PlantKind::Tokamak          => TOKAMAK_MIN_INDICES,
            PlantKind::Stellarator      => STELLARATOR_MIN_INDICES,
            PlantKind::FRC              => FRC_MIN_INDICES,
            PlantKind::Spheromak        => SPHEROMAK_MIN_INDICES,
            PlantKind::Mirror           => MIRROR_MIN_INDICES,
            PlantKind::Inertial         => INERTIAL_MIN_INDICES,
            PlantKind::SphericalTokamak => SPHERICAL_TOKAMAK_MIN_INDICES,
            PlantKind::ZPinch           => ZPINCH_MIN_INDICES,
            PlantKind::MIF              => MIF_MIN_INDICES,
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// PlantGeometry
// ─────────────────────────────────────────────────────────────────────────────

/// A fully-generated plant wireframe geometry ready for GPU upload.
pub struct PlantGeometry {
    pub vertices: Vec<GaiaVertex>,
    pub indices:  Vec<u16>,
    pub kind:     PlantKind,
}

impl PlantGeometry {
    /// Validate that vertex / index counts meet Plant Catalogue minimums and
    /// that all indices are within bounds.
    ///
    /// Returns `Err` with a description if any constraint is violated.
    pub fn validate_catalogue_minimums(&self) -> Result<(), String> {
        let min_v = self.kind.min_vertices();
        let min_i = self.kind.min_indices();

        if self.vertices.len() < min_v {
            return Err(format!(
                "{:?}: vertex count {} < Plant Catalogue minimum {}",
                self.kind, self.vertices.len(), min_v
            ));
        }
        if self.indices.len() < min_i {
            return Err(format!(
                "{:?}: index count {} < Plant Catalogue minimum {}",
                self.kind, self.indices.len(), min_i
            ));
        }
        let n = self.vertices.len() as u16;
        for &ix in &self.indices {
            if ix >= n {
                return Err(format!(
                    "{:?}: index {} out of range (vertex count = {})",
                    self.kind, ix, n
                ));
            }
        }
        Ok(())
    }
}

/// Build a plant geometry for the given [`PlantKind`].
///
/// Returns a [`PlantGeometry`] that satisfies all Plant Catalogue minimums.
/// Panics only if memory allocation fails (OOM).
pub fn build_geometry(kind: PlantKind) -> PlantGeometry {
    let (vertices, indices) = match kind {
        PlantKind::Tokamak          => gen_tokamak(),
        PlantKind::Stellarator      => gen_stellarator(),
        PlantKind::FRC              => gen_frc(),
        PlantKind::Spheromak        => gen_spheromak(),
        PlantKind::Mirror           => gen_mirror(),
        PlantKind::Inertial         => gen_inertial(),
        PlantKind::SphericalTokamak => gen_spherical_tokamak(),
        PlantKind::ZPinch           => gen_zpinch(),
        PlantKind::MIF              => gen_mif(),
    };
    PlantGeometry { vertices, indices, kind }
}

// ─────────────────────────────────────────────────────────────────────────────
// Low-level geometry helpers
//
// Every helper appends to existing Vec<GaiaVertex> / Vec<u16> buffers.
// Indices are offset by the current vertex count at call time (the `base`
// idiom: `let base = v.len() as u16` before any push).
// ─────────────────────────────────────────────────────────────────────────────

/// Append a torus (optionally twisted for stellarator geometry).
///
/// # Parameters
/// - `major_r`: centroidal (major) radius
/// - `minor_r`: tube (minor) radius
/// - `n_major`: segments around the major axis
/// - `n_minor`: segments around the tube cross-section
/// - `twist`:   total helical twist in radians accumulated over one full circuit
///              (0.0 = plain tokamak torus, 6π = three full twists for a stellarator)
fn append_torus(
    v:       &mut Vec<GaiaVertex>,
    idx:     &mut Vec<u16>,
    major_r: f32,
    minor_r: f32,
    n_major: usize,
    n_minor: usize,
    twist:   f32,
    color:   [f32; 4],
) {
    let base = v.len() as u16;
    for i in 0..n_major {
        let theta       = 2.0 * PI * i as f32 / n_major as f32;
        let phi_offset  = twist * (i as f32 / n_major as f32);
        for j in 0..n_minor {
            let phi = 2.0 * PI * j as f32 / n_minor as f32 + phi_offset;
            let x = (major_r + minor_r * phi.cos()) * theta.cos();
            let y = minor_r * phi.sin();
            let z = (major_r + minor_r * phi.cos()) * theta.sin();
            v.push(GaiaVertex::new([x, y, z], color));
        }
    }
    for i in 0..n_major {
        for j in 0..n_minor {
            let a = base + (i * n_minor + j) as u16;
            let b = base + (i * n_minor + (j + 1) % n_minor) as u16;
            let c = base + (((i + 1) % n_major) * n_minor + j) as u16;
            let d = base + (((i + 1) % n_major) * n_minor + (j + 1) % n_minor) as u16;
            idx.extend_from_slice(&[a, b, d, a, d, c]);
        }
    }
}

/// Append an open-ended cylinder.
///
/// Rings are evenly distributed between `z_bottom` and `z_top`.
/// `n_rings` must be ≥ 2.
fn append_cylinder(
    v:        &mut Vec<GaiaVertex>,
    idx:      &mut Vec<u16>,
    z_bottom: f32,
    z_top:    f32,
    radius:   f32,
    n_rings:  usize,
    n_segs:   usize,
    color:    [f32; 4],
) {
    debug_assert!(n_rings >= 2, "append_cylinder requires n_rings >= 2");
    let base = v.len() as u16;
    for r in 0..n_rings {
        let z = z_bottom + (z_top - z_bottom) * r as f32 / (n_rings - 1) as f32;
        for j in 0..n_segs {
            let a = 2.0 * PI * j as f32 / n_segs as f32;
            v.push(GaiaVertex::new([radius * a.cos(), radius * a.sin(), z], color));
        }
    }
    for r in 0..(n_rings - 1) {
        for j in 0..n_segs {
            let a = base + (r * n_segs + j) as u16;
            let b = base + (r * n_segs + (j + 1) % n_segs) as u16;
            let c = base + ((r + 1) * n_segs + j) as u16;
            let d = base + ((r + 1) * n_segs + (j + 1) % n_segs) as u16;
            idx.extend_from_slice(&[a, b, d, a, d, c]);
        }
    }
}

/// Append a filled disk cap (triangle fan from center to perimeter).
///
/// `center` is the apex vertex. Ring vertices are at `[center[0] + r·cos, center[1] + r·sin, ring_z]`.
/// `flip` reverses winding (for caps that should face the opposite direction).
fn append_disk_cap(
    v:      &mut Vec<GaiaVertex>,
    idx:    &mut Vec<u16>,
    center: [f32; 3],
    ring_z: f32,
    radius: f32,
    n_segs: usize,
    color:  [f32; 4],
    flip:   bool,
) {
    let base = v.len() as u16;
    v.push(GaiaVertex::new(center, color)); // index base+0 = center
    for j in 0..n_segs {
        let a = 2.0 * PI * j as f32 / n_segs as f32;
        v.push(GaiaVertex::new(
            [center[0] + radius * a.cos(), center[1] + radius * a.sin(), ring_z],
            color,
        ));
    }
    for j in 0..n_segs {
        let c  = base;
        let r0 = base + 1 + j as u16;
        let r1 = base + 1 + ((j + 1) % n_segs) as u16;
        if flip {
            idx.extend_from_slice(&[c, r1, r0]);
        } else {
            idx.extend_from_slice(&[c, r0, r1]);
        }
    }
}

/// Append a UV sphere.
///
/// - North pole at `[cx, cy+r, cz]`, south pole at `[cx, cy-r, cz]`.
/// - `n_lat` latitude ring count (excluding poles) — must be ≥ 1.
/// - `n_lon` longitude segment count.
fn append_uv_sphere(
    v:     &mut Vec<GaiaVertex>,
    idx:   &mut Vec<u16>,
    cx:    f32,
    cy:    f32,
    cz:    f32,
    r:     f32,
    n_lat: usize,
    n_lon: usize,
    color: [f32; 4],
) {
    debug_assert!(n_lat >= 1, "append_uv_sphere requires n_lat >= 1");
    let base = v.len() as u16;

    // North pole
    v.push(GaiaVertex::new([cx, cy + r, cz], color));

    // Latitude rings
    for lat in 0..n_lat {
        let theta = PI * (lat + 1) as f32 / (n_lat + 1) as f32; // (0, π), poles excluded
        let y     = cy + r * theta.cos();
        let rr    = r * theta.sin();
        for lon in 0..n_lon {
            let phi = 2.0 * PI * lon as f32 / n_lon as f32;
            v.push(GaiaVertex::new([cx + rr * phi.cos(), y, cz + rr * phi.sin()], color));
        }
    }

    // South pole
    let south = v.len() as u16;
    v.push(GaiaVertex::new([cx, cy - r, cz], color));

    let north = base;

    // North cap fan
    for lon in 0..n_lon {
        let r0 = base + 1 + lon as u16;
        let r1 = base + 1 + ((lon + 1) % n_lon) as u16;
        idx.extend_from_slice(&[north, r0, r1]);
    }

    // Middle bands
    for lat in 0..(n_lat - 1) {
        for lon in 0..n_lon {
            let a = base + 1 + (lat * n_lon + lon) as u16;
            let b = base + 1 + (lat * n_lon + (lon + 1) % n_lon) as u16;
            let c = base + 1 + ((lat + 1) * n_lon + lon) as u16;
            let d = base + 1 + ((lat + 1) * n_lon + (lon + 1) % n_lon) as u16;
            idx.extend_from_slice(&[a, b, d, a, d, c]);
        }
    }

    // South cap fan
    for lon in 0..n_lon {
        let r0 = base + 1 + ((n_lat - 1) * n_lon + lon) as u16;
        let r1 = base + 1 + ((n_lat - 1) * n_lon + (lon + 1) % n_lon) as u16;
        idx.extend_from_slice(&[south, r1, r0]);
    }
}

/// Midpoint of two unit-sphere vertices, projected back onto the unit sphere.
fn sphere_midpoint(a: [f32; 3], b: [f32; 3]) -> [f32; 3] {
    let mid = [(a[0] + b[0]) / 2.0, (a[1] + b[1]) / 2.0, (a[2] + b[2]) / 2.0];
    let len  = (mid[0] * mid[0] + mid[1] * mid[1] + mid[2] * mid[2]).sqrt();
    if len < 1e-9 {
        return [0.0, 1.0, 0.0]; // degenerate — fallback to north pole
    }
    [mid[0] / len, mid[1] / len, mid[2] / len]
}

/// Look up (or compute and cache) the midpoint vertex between icosphere vertices `a` and `b`.
fn icosphere_midpoint(
    positions: &mut Vec<[f32; 3]>,
    cache:     &mut HashMap<(usize, usize), usize>,
    a:         usize,
    b:         usize,
) -> usize {
    let key = if a < b { (a, b) } else { (b, a) };
    if let Some(&existing) = cache.get(&key) {
        return existing;
    }
    let mid = sphere_midpoint(positions[key.0], positions[key.1]);
    let new_idx = positions.len();
    positions.push(mid);
    cache.insert(key, new_idx);
    new_idx
}

/// Append a level-1 subdivided icosphere: 42 vertices, 80 triangles (240 indices).
/// Positions lie on the sphere of given `radius` centred at (`cx`, `cy`, `cz`).
fn append_icosphere_l1(
    v:     &mut Vec<GaiaVertex>,
    idx:   &mut Vec<u16>,
    cx:    f32,
    cy:    f32,
    cz:    f32,
    radius: f32,
    color: [f32; 4],
) {
    // Golden ratio φ for icosahedron construction
    let phi = (1.0_f32 + 5.0_f32.sqrt()) / 2.0;

    // 12 icosahedron vertices (unnormalized); normalised below
    let raw: [[f32; 3]; 12] = [
        [-1.0,  phi,  0.0],
        [ 1.0,  phi,  0.0],
        [-1.0, -phi,  0.0],
        [ 1.0, -phi,  0.0],
        [ 0.0, -1.0,  phi],
        [ 0.0,  1.0,  phi],
        [ 0.0, -1.0, -phi],
        [ 0.0,  1.0, -phi],
        [ phi,  0.0, -1.0],
        [ phi,  0.0,  1.0],
        [-phi,  0.0, -1.0],
        [-phi,  0.0,  1.0],
    ];

    let mut positions: Vec<[f32; 3]> = raw
        .iter()
        .map(|p| {
            let len = (p[0] * p[0] + p[1] * p[1] + p[2] * p[2]).sqrt();
            [p[0] / len, p[1] / len, p[2] / len]
        })
        .collect();

    // 20 faces of the base icosahedron
    let base_faces: [[usize; 3]; 20] = [
        [0, 11, 5], [0, 5,  1], [0, 1,  7], [0,  7, 10], [0, 10, 11],
        [1, 5,  9], [5, 11, 4], [11, 10, 2], [10, 7,  6], [7, 1,   8],
        [3, 9,  4], [3, 4,  2], [3, 2,  6], [3,  6,  8], [3, 8,   9],
        [4, 9,  5], [2, 4, 11], [6,  2, 10], [8, 6,   7], [9, 8,   1],
    ];

    let mut cache: HashMap<(usize, usize), usize> = HashMap::with_capacity(30);
    let mut subdivided: Vec<[usize; 3]> = Vec::with_capacity(80);

    for face in &base_faces {
        let [a, b, c] = *face;
        let ab = icosphere_midpoint(&mut positions, &mut cache, a, b);
        let bc = icosphere_midpoint(&mut positions, &mut cache, b, c);
        let ca = icosphere_midpoint(&mut positions, &mut cache, c, a);
        subdivided.push([a,  ab, ca]);
        subdivided.push([ab, b,  bc]);
        subdivided.push([bc, c,  ca]);
        subdivided.push([ab, bc, ca]);
    }
    // positions now has exactly 42 entries (12 original + 30 edge midpoints)

    let base = v.len() as u16;
    for p in &positions {
        v.push(GaiaVertex::new(
            [cx + p[0] * radius, cy + p[1] * radius, cz + p[2] * radius],
            color,
        ));
    }
    for face in &subdivided {
        idx.extend_from_slice(&[
            base + face[0] as u16,
            base + face[1] as u16,
            base + face[2] as u16,
        ]);
    }
}

/// Generate `n` approximately uniform points on the unit sphere using the
/// Fibonacci sphere (golden-angle) algorithm.
///
/// Returns `n` positions `[x, y, z]` with `x²+y²+z² ≈ 1`.
///
/// # Constitutional note (C-009)
/// The MIF plant calls this with `n = 12`. That value is constitutionally
/// locked. Any change to the gun count requires full PQ-CSE re-execution.
fn fibonacci_sphere(n: usize) -> Vec<[f32; 3]> {
    if n == 0 {
        return Vec::new();
    }
    if n == 1 {
        return vec![[0.0, 1.0, 0.0]];
    }
    let golden_angle = PI * (3.0 - 5.0_f32.sqrt()); // ≈ 2.39996 rad
    (0..n)
        .map(|i| {
            let y   = 1.0 - (i as f32 / (n - 1) as f32) * 2.0;
            let rr  = (1.0 - y * y).max(0.0).sqrt();
            let phi = golden_angle * i as f32;
            [rr * phi.cos(), y, rr * phi.sin()]
        })
        .collect()
}

// ─────────────────────────────────────────────────────────────────────────────
// Plant geometry generators
//
// Naming convention: gen_<plant_name>()
// Each returns (Vec<GaiaVertex>, Vec<u16>) meeting Plant Catalogue minimums.
//
// Vertex colour defaults encode the plant's constitutional identity:
//   R ≈ plant vqbit_entropy (from USD file) — overridden by live telemetry
//   G ≈ plant vqbit_truth                   — overridden by live telemetry
//   B = 0.5 (hardcoded per renderer.rs upload_geometry_from_primitives)
//   A = 1.0
//
// The default colours below use distinctive per-plant hues for CERN demo
// legibility. Live telemetry replaces them via upload_geometry_from_primitives.
// ─────────────────────────────────────────────────────────────────────────────

/// 0 — Tokamak: nested torus vessel + thin PF coil ring.
/// A physicist sees a donut with a surrounding coil belt — immediately distinct
/// from every other plant topology.
/// Signature: amber [1.0, 0.70, 0.0]
fn gen_tokamak() -> (Vec<GaiaVertex>, Vec<u16>) {
    let mut v:   Vec<GaiaVertex> = Vec::new();
    let mut idx: Vec<u16>        = Vec::new();

    let vessel_color = [1.0_f32, 0.70, 0.00, 1.0]; // amber — toroidal vessel
    let coil_color   = [1.0_f32, 0.90, 0.50, 1.0]; // pale gold — PF coil belt

    // Main toroidal vessel: R=1.0, r=0.25, 16 major × 8 minor = 128 vertices
    append_torus(&mut v, &mut idx, 1.0, 0.25, 16, 8, 0.0, vessel_color);

    // Poloidal field (PF) coil ring — thin torus concentric with the vessel
    // R=1.0, r=0.06, 16 major × 4 minor = 64 vertices
    append_torus(&mut v, &mut idx, 1.0, 0.06, 16, 4, 0.0, coil_color);

    // Total: 192 vertices, ~1152 indices  (min 48 / 96)
    (v, idx)
}

/// 1 — Stellarator: three-period twisted helical torus (W7-X style).
/// The helical twist makes this immediately visually distinct from the plain
/// Tokamak torus — a physicist can identify it in under one second.
/// Signature: violet [0.60, 0.15, 0.70]
fn gen_stellarator() -> (Vec<GaiaVertex>, Vec<u16>) {
    let mut v:   Vec<GaiaVertex> = Vec::new();
    let mut idx: Vec<u16>        = Vec::new();

    let vessel_color = [0.60_f32, 0.15, 0.70, 1.0]; // violet — twisted vessel
    let coil_color   = [0.80_f32, 0.40, 0.90, 1.0]; // lavender — helical coils

    // Twisted torus: 3 full twist periods (6π total twist).
    // 18 major × 10 minor = 180 vertices.
    let twist = 3.0_f32 * 2.0 * PI;
    append_torus(&mut v, &mut idx, 1.0, 0.30, 18, 10, twist, vessel_color);

    // Helical coil winding — same twist profile at a slightly larger radius
    // 18 major × 4 minor = 72 vertices
    append_torus(&mut v, &mut idx, 1.0, 0.08, 18, 4, twist, coil_color);

    // Total: 252 vertices  (min 48)
    (v, idx)
}

/// 2 — Field-Reversed Configuration: elongated cylinder + two end mirror coils.
/// The FRC is a long thin tube — aspect ratio ~3:1 — easily distinguishable from
/// the compact spherical geometries and the donut topologies.
/// Signature: emerald green [0.30, 0.80, 0.30]
fn gen_frc() -> (Vec<GaiaVertex>, Vec<u16>) {
    let mut v:   Vec<GaiaVertex> = Vec::new();
    let mut idx: Vec<u16>        = Vec::new();

    let vessel_color = [0.30_f32, 0.80, 0.30, 1.0]; // emerald — elongated vessel
    let coil_color   = [0.70_f32, 1.00, 0.50, 1.0]; // bright lime — end coils

    // Main cylindrical vessel: z ∈ [-1.2, 1.2], radius 0.4, 4 rings × 12 segs = 48 vertices
    append_cylinder(&mut v, &mut idx, -1.2, 1.2, 0.4, 4, 12, vessel_color);

    // End mirror coil rings: thin tori at ±1.25, slightly wider than the vessel
    for &z_center in &[-1.25_f32, 1.25] {
        let base    = v.len() as u16;
        let n_coil  = 12usize;
        let n_tube  = 4usize;
        let r_major = 0.52_f32;
        let r_minor = 0.05_f32;
        for i in 0..n_coil {
            let theta = 2.0 * PI * i as f32 / n_coil as f32;
            for j in 0..n_tube {
                let phi = 2.0 * PI * j as f32 / n_tube as f32;
                let x = (r_major + r_minor * phi.cos()) * theta.cos();
                let y = (r_major + r_minor * phi.cos()) * theta.sin();
                let z = z_center + r_minor * phi.sin();
                v.push(GaiaVertex::new([x, y, z], coil_color));
            }
        }
        for i in 0..n_coil {
            for j in 0..n_tube {
                let a = base + (i * n_tube + j) as u16;
                let b = base + (i * n_tube + (j + 1) % n_tube) as u16;
                let c = base + (((i + 1) % n_coil) * n_tube + j) as u16;
                let d = base + (((i + 1) % n_coil) * n_tube + (j + 1) % n_tube) as u16;
                idx.extend_from_slice(&[a, b, d, a, d, c]);
            }
        }
    }

    // Total: 48 + 2×48 = 144 vertices  (min 24)
    (v, idx)
}

/// 3 — Spheromak: spherical flux conserver + coaxial gun injector below.
/// The sphere-below-injector stack is unique among all nine topologies.
/// Signature: burnt orange [1.0, 0.35, 0.13]
fn gen_spheromak() -> (Vec<GaiaVertex>, Vec<u16>) {
    let mut v:   Vec<GaiaVertex> = Vec::new();
    let mut idx: Vec<u16>        = Vec::new();

    let sphere_color   = [1.00_f32, 0.35, 0.13, 1.0]; // burnt orange — conserver
    let injector_color = [1.00_f32, 0.65, 0.40, 1.0]; // light orange — coaxial gun

    // Spherical conserver: radius 0.8, n_lat=5, n_lon=12 → 2 + 5×12 = 62 vertices
    append_uv_sphere(&mut v, &mut idx, 0.0, 0.0, 0.0, 0.8, 5, 12, sphere_color);

    // Coaxial gun injector: narrow cylinder below the sphere
    // 3 rings × 8 segs = 24 vertices
    append_cylinder(&mut v, &mut idx, -1.5, -0.8, 0.15, 3, 8, injector_color);

    // Total: 86 vertices  (min 32)
    (v, idx)
}

/// 4 — Mirror Machine: cylinder with three magnetic mirror choke coils.
/// Three pronounced ring coils at specific axial positions are the visual
/// signature — unambiguous to anyone who has seen a tandem mirror device.
/// Signature: electric cyan [0.0, 0.75, 0.83]
fn gen_mirror() -> (Vec<GaiaVertex>, Vec<u16>) {
    let mut v:   Vec<GaiaVertex> = Vec::new();
    let mut idx: Vec<u16>        = Vec::new();

    let vessel_color = [0.00_f32, 0.75, 0.83, 1.0]; // electric cyan — vacuum vessel
    let coil_color   = [0.50_f32, 1.00, 1.00, 1.0]; // bright cyan — mirror coils

    // Central vacuum vessel: z ∈ [-1.5, 1.5], radius 0.3, 4 rings × 10 segs = 40 vertices
    append_cylinder(&mut v, &mut idx, -1.5, 1.5, 0.3, 4, 10, vessel_color);

    // Three mirror coil rings at z = -1.2, 0.0, +1.2
    // Each is a thin torus encircling the vessel (r_major > vessel radius)
    for &z_pos in &[-1.2_f32, 0.0, 1.2] {
        let base    = v.len() as u16;
        let n_coil  = 10usize;
        let n_tube  = 4usize;
        let r_major = 0.42_f32;
        let r_minor = 0.06_f32;
        for i in 0..n_coil {
            let theta = 2.0 * PI * i as f32 / n_coil as f32;
            for j in 0..n_tube {
                let phi = 2.0 * PI * j as f32 / n_tube as f32;
                let x = (r_major + r_minor * phi.cos()) * theta.cos();
                let y = (r_major + r_minor * phi.cos()) * theta.sin();
                let z = z_pos + r_minor * phi.sin();
                v.push(GaiaVertex::new([x, y, z], coil_color));
            }
        }
        for i in 0..n_coil {
            for j in 0..n_tube {
                let a = base + (i * n_tube + j) as u16;
                let b = base + (i * n_tube + (j + 1) % n_tube) as u16;
                let c = base + (((i + 1) % n_coil) * n_tube + j) as u16;
                let d = base + (((i + 1) % n_coil) * n_tube + (j + 1) % n_tube) as u16;
                idx.extend_from_slice(&[a, b, d, a, d, c]);
            }
        }
    }

    // Total: 40 + 3×40 = 160 vertices  (min 24)
    (v, idx)
}

/// 5 — Inertial Confinement Fusion: geodesic target chamber + hohlraum + laser ports.
/// The geodesic sphere with visible beam entry ports is the canonical ICF image —
/// any NIF physicist will recognize it.
/// Signature: crimson [0.96, 0.26, 0.21]
fn gen_inertial() -> (Vec<GaiaVertex>, Vec<u16>) {
    let mut v:   Vec<GaiaVertex> = Vec::new();
    let mut idx: Vec<u16>        = Vec::new();

    let sphere_color   = [0.96_f32, 0.26, 0.21, 1.0]; // crimson — target chamber
    let hohlraum_color = [1.00_f32, 0.60, 0.55, 1.0]; // pale red — hohlraum
    let port_color     = [1.00_f32, 0.85, 0.85, 1.0]; // light rose — beam ports

    // Level-1 icosphere target chamber: 42 vertices, 240 indices
    append_icosphere_l1(&mut v, &mut idx, 0.0, 0.0, 0.0, 1.0, sphere_color);

    // Hohlraum: small cylinder at the centre of the target (the gold can the laser heats)
    // 2 rings × 6 segs = 12 vertices
    append_cylinder(&mut v, &mut idx, -0.12, 0.12, 0.06, 2, 6, hohlraum_color);

    // 6 laser beam ports arranged with NIF-style geometry:
    // alternating above/below equator, 60° apart in azimuth
    for i in 0..6usize {
        let azimuth   = 2.0 * PI * i as f32 / 6.0;
        let elevation = if i % 2 == 0 { 0.35_f32 } else { -0.35_f32 };
        let rr        = (1.0 - elevation * elevation).max(0.0).sqrt();
        let px = rr * azimuth.cos();
        let py = elevation;
        let pz = rr * azimuth.sin();

        // Port: small triangle on the sphere surface — three vertices per port
        let tangent_x = -azimuth.sin();
        let tangent_z =  azimuth.cos();
        let scale = 0.09_f32;

        let b = v.len() as u16;
        v.push(GaiaVertex::new([px,                      py,              pz             ], port_color));
        v.push(GaiaVertex::new([px + scale * tangent_x,  py + scale,      pz + scale * tangent_z], port_color));
        v.push(GaiaVertex::new([px - scale * tangent_x,  py + scale,      pz - scale * tangent_z], port_color));
        idx.extend_from_slice(&[b, b + 1, b + 2]);
    }

    // Total: 42 + 12 + 18 = 72 vertices  (min 40)
    (v, idx)
}

/// 6 — Spherical Tokamak: compact sphere + central solenoid column.
/// The tall thin solenoid threading a near-spherical vessel is unique —
/// no other plant has a central column penetrating a sphere.
/// Signature: electric blue [0.13, 0.59, 0.95]
fn gen_spherical_tokamak() -> (Vec<GaiaVertex>, Vec<u16>) {
    let mut v:   Vec<GaiaVertex> = Vec::new();
    let mut idx: Vec<u16>        = Vec::new();

    let sphere_color   = [0.13_f32, 0.59, 0.95, 1.0]; // electric blue — vessel
    let solenoid_color = [0.50_f32, 0.80, 1.00, 1.0]; // pale blue — central solenoid

    // Near-spherical vessel: radius 0.9, n_lat=6, n_lon=12 → 2 + 6×12 = 74 vertices
    append_uv_sphere(&mut v, &mut idx, 0.0, 0.0, 0.0, 0.9, 6, 12, sphere_color);

    // Central solenoid: tall narrow cylinder threading through the sphere
    // 3 rings × 8 segs = 24 vertices
    append_cylinder(&mut v, &mut idx, -1.1, 1.1, 0.08, 3, 8, solenoid_color);

    // Total: 74 + 24 = 98 vertices  (min 32)
    (v, idx)
}

/// 7 — Z-Pinch: plasma column + two electrode disks.
/// The two large flat disks at the ends of a thin column is instantly recognizable
/// and unlike any other fusion confinement geometry.
/// Signature: golden yellow [1.0, 0.92, 0.23]
fn gen_zpinch() -> (Vec<GaiaVertex>, Vec<u16>) {
    let mut v:   Vec<GaiaVertex> = Vec::new();
    let mut idx: Vec<u16>        = Vec::new();

    let column_color   = [1.00_f32, 0.92, 0.23, 1.0]; // golden yellow — plasma column
    let electrode_color = [1.00_f32, 1.00, 0.65, 1.0]; // pale yellow — electrodes

    // Z-pinch plasma column: thin, tall cylinder
    // 3 rings × 8 segs = 24 vertices
    append_cylinder(&mut v, &mut idx, -1.0, 1.0, 0.12, 3, 8, column_color);

    // Anode electrode disk at z = -1.0 (bottom)
    // center + 8 ring vertices = 9 vertices
    append_disk_cap(
        &mut v, &mut idx,
        [0.0, 0.0, -1.0], -1.0, 0.5, 8,
        electrode_color,
        false,
    );

    // Cathode electrode disk at z = +1.0 (top, winding flipped)
    // center + 8 ring vertices = 9 vertices
    append_disk_cap(
        &mut v, &mut idx,
        [0.0, 0.0, 1.0], 1.0, 0.5, 8,
        electrode_color,
        true,
    );

    // Total: 24 + 9 + 9 = 42 vertices  (min 16)
    (v, idx)
}

/// 8 — Magnetized Inertial Fusion: icosphere driver + 12 Fibonacci plasma guns.
///
/// Constitutional constraint C-009: the Fibonacci gun count (12) and positions
/// are a locked configuration item. Any change to this count requires full
/// PQ-CSE re-execution as documented in wiki/Composite-App-UI-Requirements.md.
///
/// Signature: hot magenta [0.91, 0.12, 0.39]
fn gen_mif() -> (Vec<GaiaVertex>, Vec<u16>) {
    let mut v:   Vec<GaiaVertex> = Vec::new();
    let mut idx: Vec<u16>        = Vec::new();

    let sphere_color = [0.91_f32, 0.12, 0.39, 1.0]; // hot magenta — driver coil
    let gun_color    = [1.00_f32, 0.55, 0.75, 1.0]; // light pink — plasma guns

    // Spherical driver coil: level-1 icosphere, 42 vertices, 240 indices
    append_icosphere_l1(&mut v, &mut idx, 0.0, 0.0, 0.0, 0.9, sphere_color);

    // 12 Fibonacci-distributed plasma gun positions (C-009 locked count)
    let gun_positions = fibonacci_sphere(12);
    let gun_surface_r = 0.90_f32;

    for gp in &gun_positions {
        let gx = gp[0] * gun_surface_r;
        let gy = gp[1] * gun_surface_r;
        let gz = gp[2] * gun_surface_r;

        // Tangent vector for the gun marker triangle: perpendicular to the
        // outward normal (gp), lying in the surface
        let ref_vec: [f32; 3] = if gp[0].abs() < 0.9 {
            [1.0, 0.0, 0.0]
        } else {
            [0.0, 1.0, 0.0]
        };
        // Cross product: gp × ref_vec
        let tx = gp[1] * ref_vec[2] - gp[2] * ref_vec[1];
        let ty = gp[2] * ref_vec[0] - gp[0] * ref_vec[2];
        let tz = gp[0] * ref_vec[1] - gp[1] * ref_vec[0];
        let t_len = (tx * tx + ty * ty + tz * tz).sqrt().max(1e-9);
        let scale = 0.10_f32;
        let (tx, ty, tz) = (tx / t_len * scale, ty / t_len * scale, tz / t_len * scale);

        // Three-vertex triangular gun marker
        let b = v.len() as u16;
        v.push(GaiaVertex::new([gx,      gy,      gz     ], gun_color));
        v.push(GaiaVertex::new([gx + tx, gy + ty, gz + tz], gun_color));
        v.push(GaiaVertex::new([gx - tx, gy - ty, gz - tz], gun_color));
        idx.extend_from_slice(&[b, b + 1, b + 2]);
    }

    // Total: 42 + 12×3 = 78 vertices  (min 40)
    (v, idx)
}

// ─────────────────────────────────────────────────────────────────────────────
// GxP Tests — pg_* series (Plant Geometry)
//
// These tests verify the constitutional constraint C-005 (vertex_count ≥
// Plant Catalogue minimum) and the index contract, for all nine plant kinds.
//
// Test environment: macOS only (bin target links renderer.rs → Metal).
// ─────────────────────────────────────────────────────────────────────────────
#[cfg(test)]
mod tests {
    use super::*;

    /// pg_001 — All nine plants generate without panic.
    #[test]
    fn pg_001_all_plants_generate_without_panic() {
        for kind in PlantKind::all() {
            let _ = build_geometry(kind);
        }
    }

    /// pg_002 — Every plant meets Plant Catalogue vertex / index minimums
    /// and has all indices within bounds (constitutional constraint C-005).
    #[test]
    fn pg_002_all_plants_meet_catalogue_minimums() {
        for kind in PlantKind::all() {
            let geom = build_geometry(kind);
            geom.validate_catalogue_minimums().unwrap_or_else(|e| {
                panic!("pg_002 FAILED: {}", e);
            });
        }
    }

    /// pg_003 — PlantKind::from_u32 correctly round-trips all nine IDs.
    #[test]
    fn pg_003_plant_kind_from_u32_roundtrip() {
        for (expected_id, kind) in PlantKind::all().iter().enumerate() {
            let parsed = PlantKind::from_u32(expected_id as u32)
                .unwrap_or_else(|| panic!("pg_003: from_u32({}) returned None", expected_id));
            assert_eq!(
                *kind, parsed,
                "pg_003: from_u32({}) returned wrong kind: {:?}",
                expected_id, parsed
            );
        }
        // Values outside [0,8] must return None
        assert!(
            PlantKind::from_u32(9).is_none(),
            "pg_003: from_u32(9) must return None"
        );
        assert!(
            PlantKind::from_u32(u32::MAX).is_none(),
            "pg_003: from_u32(u32::MAX) must return None"
        );
    }

    /// pg_004 — Tokamak vertex count is substantially above catalogue minimum.
    /// The torus geometry must produce a recognisable donut, not a degenerate mesh.
    #[test]
    fn pg_004_tokamak_vertex_count_sufficient() {
        let geom = build_geometry(PlantKind::Tokamak);
        assert!(
            geom.vertices.len() >= 128,
            "pg_004: Tokamak must have ≥ 128 vertices for a 16×8 torus; got {}",
            geom.vertices.len()
        );
    }

    /// pg_005 — Stellarator vertex count is substantially above catalogue minimum.
    #[test]
    fn pg_005_stellarator_vertex_count_sufficient() {
        let geom = build_geometry(PlantKind::Stellarator);
        assert!(
            geom.vertices.len() >= 180,
            "pg_005: Stellarator must have ≥ 180 vertices for an 18×10 twisted torus; got {}",
            geom.vertices.len()
        );
    }

    /// pg_006 — Icosphere level-1 produces exactly 42 vertices and 240 indices.
    /// Regression guard: any change to the subdivision algorithm breaks this.
    #[test]
    fn pg_006_icosphere_l1_vertex_and_index_count() {
        let mut v:   Vec<GaiaVertex> = Vec::new();
        let mut idx: Vec<u16>        = Vec::new();
        append_icosphere_l1(&mut v, &mut idx, 0.0, 0.0, 0.0, 1.0, [1.0, 0.0, 0.0, 1.0]);
        assert_eq!(v.len(),   42,  "pg_006: icosphere_l1 must produce exactly 42 vertices");
        assert_eq!(idx.len(), 240, "pg_006: icosphere_l1 must produce exactly 240 indices (80 triangles)");
    }

    /// pg_007 — MIF Fibonacci gun count is constitutionally locked at 12 (C-009).
    /// This test encodes the constitutional constraint — it must not be changed
    /// without full PQ-CSE re-execution.
    #[test]
    fn pg_007_mif_fibonacci_gun_count_locked_at_12() {
        let geom = build_geometry(PlantKind::MIF);
        // Icosphere: 42 vertices. Each gun: 3 vertices. 12 guns: 36 vertices.
        // Total: 78. Assert at least 78 to catch gun removal regression.
        assert!(
            geom.vertices.len() >= 78,
            "pg_007: MIF must have ≥ 78 vertices (42 icosphere + 12×3 guns); got {}. \
             Constitutional constraint C-009: Fibonacci gun count is locked at 12.",
            geom.vertices.len()
        );
    }

    /// pg_008 — Fibonacci sphere produces unit-length positions.
    #[test]
    fn pg_008_fibonacci_sphere_positions_on_unit_sphere() {
        let pts = fibonacci_sphere(12);
        assert_eq!(pts.len(), 12);
        for (i, p) in pts.iter().enumerate() {
            let len_sq = p[0] * p[0] + p[1] * p[1] + p[2] * p[2];
            assert!(
                (len_sq - 1.0).abs() < 1e-5,
                "pg_008: fibonacci_sphere point {} has length² = {:.6}, expected ~1.0",
                i, len_sq
            );
        }
    }

    /// pg_009 — PlantKind::min_vertices and min_indices agree with catalogue constants.
    #[test]
    fn pg_009_plant_kind_min_counts_agree_with_constants() {
        assert_eq!(PlantKind::Tokamak.min_vertices(),          TOKAMAK_MIN_VERTICES);
        assert_eq!(PlantKind::Tokamak.min_indices(),           TOKAMAK_MIN_INDICES);
        assert_eq!(PlantKind::Stellarator.min_vertices(),      STELLARATOR_MIN_VERTICES);
        assert_eq!(PlantKind::Stellarator.min_indices(),       STELLARATOR_MIN_INDICES);
        assert_eq!(PlantKind::FRC.min_vertices(),              FRC_MIN_VERTICES);
        assert_eq!(PlantKind::FRC.min_indices(),               FRC_MIN_INDICES);
        assert_eq!(PlantKind::Spheromak.min_vertices(),        SPHEROMAK_MIN_VERTICES);
        assert_eq!(PlantKind::Spheromak.min_indices(),         SPHEROMAK_MIN_INDICES);
        assert_eq!(PlantKind::Mirror.min_vertices(),           MIRROR_MIN_VERTICES);
        assert_eq!(PlantKind::Mirror.min_indices(),            MIRROR_MIN_INDICES);
        assert_eq!(PlantKind::Inertial.min_vertices(),         INERTIAL_MIN_VERTICES);
        assert_eq!(PlantKind::Inertial.min_indices(),          INERTIAL_MIN_INDICES);
        assert_eq!(PlantKind::SphericalTokamak.min_vertices(), SPHERICAL_TOKAMAK_MIN_VERTICES);
        assert_eq!(PlantKind::SphericalTokamak.min_indices(),  SPHERICAL_TOKAMAK_MIN_INDICES);
        assert_eq!(PlantKind::ZPinch.min_vertices(),           ZPINCH_MIN_VERTICES);
        assert_eq!(PlantKind::ZPinch.min_indices(),            ZPINCH_MIN_INDICES);
        assert_eq!(PlantKind::MIF.min_vertices(),              MIF_MIN_VERTICES);
        assert_eq!(PlantKind::MIF.min_indices(),               MIF_MIN_INDICES);
    }
}
