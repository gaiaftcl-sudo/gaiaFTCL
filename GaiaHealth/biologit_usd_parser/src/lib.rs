//! GaiaHealth Biologit USD Parser
//!
//! Parses protein and ligand scene files into `BioligitPrimitive` — the
//! biological cell's equivalent of `vQbitPrimitive` in GaiaFTCL.
//!
//! Supported input formats:
//!   .pdb  — Protein Data Bank (crystallography, cryo-EM)
//!   .sdf  — Structure-Data File (small molecule)
//!   .usda — OpenUSD ASCII (scene graph, shared with GaiaFusion)
//!
//! BioligitPrimitive ABI: #[repr(C)], 96 bytes.
//! Field offsets are GxP regression-locked by RG-002.
//!
//! Patents: USPTO 19/460,960 | USPTO 19/096,071 — © 2026 Richard Gillespie

pub mod parser;

// ── BioligitPrimitive ─────────────────────────────────────────────────────────

/// Biological primitive for the Metal molecular renderer.
///
/// Biological analog of `vQbitPrimitive` (76 bytes) in GaiaFTCL.
/// Expanded to 96 bytes to accommodate binding energy ΔG and epistemic tag.
///
/// Field layout (GxP-locked, RG-002):
///   Offset  0: transform      [[f32;4];4]   64 bytes — model matrix
///   Offset 64: binding_dg     f32            4 bytes — predicted ΔG (kcal/mol, negative = binding)
///   Offset 68: admet_score    f32            4 bytes — ADMET safety score (0.0=unsafe, 1.0=safe)
///   Offset 72: epistemic_tag  u32            4 bytes — 0=M, 1=I, 2=A
///   Offset 76: residue_id     u32            4 bytes — PDB residue sequence number
///   Offset 80: atom_count     u32            4 bytes — atoms in this primitive
///   Offset 84: mol_type       u32            4 bytes — 0=protein, 1=ligand, 2=water, 3=ion
///   Offset 88: _padding       [u8; 8]        8 bytes — alignment to 96 bytes
///   Total: 96 bytes
#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct BioligitPrimitive {
    pub transform:     [[f32; 4]; 4],
    pub binding_dg:    f32,
    pub admet_score:   f32,
    pub epistemic_tag: u32,
    pub residue_id:    u32,
    pub atom_count:    u32,
    pub mol_type:      u32,
    pub _padding:      [u8; 8],
}

impl BioligitPrimitive {
    pub const SIZE: usize = 96;

    pub fn identity() -> Self {
        Self {
            transform:     [
                [1.0, 0.0, 0.0, 0.0],
                [0.0, 1.0, 0.0, 0.0],
                [0.0, 0.0, 1.0, 0.0],
                [0.0, 0.0, 0.0, 1.0],
            ],
            binding_dg:    0.0,
            admet_score:   1.0,
            epistemic_tag: 2, // Assumed — most conservative default
            residue_id:    0,
            atom_count:    0,
            mol_type:      0,
            _padding:      [0u8; 8],
        }
    }

    /// Derived vertex color for the Metal shader.
    /// R = |binding_dg| normalized (binding strength — red)
    /// G = admet_score (safety — green)
    /// B = epistemic alpha (M=1.0, I=0.6, A=0.3)
    /// A = 1.0
    pub fn vertex_color(&self) -> [f32; 4] {
        let r = (self.binding_dg.abs() / 20.0).min(1.0); // normalize to ±20 kcal/mol range
        let g = self.admet_score.clamp(0.0, 1.0);
        let b = match self.epistemic_tag {
            0 => 1.0,  // M — Measured: full blue channel
            1 => 0.6,  // I — Inferred: translucent
            _ => 0.3,  // A — Assumed: stippled
        };
        [r, g, b, 1.0]
    }
}

// ── GxP Tests ─────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    // RG-002: ABI stride regression guard — any layout change breaks Swift FFI
    #[test]
    fn rg_002_bioligit_primitive_size_96() {
        assert_eq!(
            std::mem::size_of::<BioligitPrimitive>(),
            96,
            "BioligitPrimitive must be exactly 96 bytes — Swift FFI ABI lock"
        );
    }

    // RG-003: Field offset — transform at 0
    #[test]
    fn rg_003_transform_at_offset_0() {
        let p = BioligitPrimitive::identity();
        let base = &p as *const _ as usize;
        let field = &p.transform as *const _ as usize;
        assert_eq!(field - base, 0, "transform must be at offset 0");
    }

    // RG-004: Field offset — binding_dg at 64
    #[test]
    fn rg_004_binding_dg_at_offset_64() {
        let p = BioligitPrimitive::identity();
        let base = &p as *const _ as usize;
        let field = &p.binding_dg as *const _ as usize;
        assert_eq!(field - base, 64, "binding_dg must be at offset 64");
    }

    // RG-005: Field offset — epistemic_tag at 72
    #[test]
    fn rg_005_epistemic_tag_at_offset_72() {
        let p = BioligitPrimitive::identity();
        let base = &p as *const _ as usize;
        let field = &p.epistemic_tag as *const _ as usize;
        assert_eq!(field - base, 72, "epistemic_tag must be at offset 72");
    }

    // TC-010: Identity primitive has conservative Assumed epistemic tag
    #[test]
    fn tc_010_identity_is_assumed() {
        let p = BioligitPrimitive::identity();
        assert_eq!(p.epistemic_tag, 2, "default epistemic tag must be Assumed (2)");
    }

    // TP-010: Vertex color — strong binding shows high red channel
    #[test]
    fn tp_010_strong_binding_high_red() {
        let mut p = BioligitPrimitive::identity();
        p.binding_dg = -15.0; // strong binding
        p.epistemic_tag = 1;  // Inferred
        let color = p.vertex_color();
        assert!(color[0] > 0.5, "strong binding must produce high red channel");
    }
}
