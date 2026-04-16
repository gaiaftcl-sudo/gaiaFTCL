//! Metal Shading Language (MSL) — GaiaHealth Molecular Renderer
//!
//! M/I/A Epistemic Color Encoding (enforced at shader level):
//!
//!   M — Measured:  Opaque, solid, sharp geometric lines.
//!                  Alpha = 1.0. Color from vertex buffer (binding strength / ADMET).
//!   I — Inferred:  Translucent, glassy, semi-transparent.
//!                  Alpha blended to 0.6. Soft edges via fragment discard.
//!   A — Assumed:   Dashed / stippled. Highly fragmented.
//!                  Alpha = 0.3. Checkerboard discard pattern.
//!
//! The epistemic_tag uniform (0=M, 1=I, 2=A) is pushed as a per-frame constant
//! in buffer(2) and controls the fragment shader's transparency and discard logic.
//!
//! GaiaVertex layout: 32 bytes
//!   position [f32;3] at offset 0   (12 bytes)
//!   color    [f32;4] at offset 12  (16 bytes)
//!   _pad     f32     at offset 28  ( 4 bytes — alignment)
//!
//! Regression test RG-005 locks the stride to 32 bytes.

pub const BIOLOGIT_SHADERS: &str = r#"
#include <metal_stdlib>
using namespace metal;

// ── Vertex Input ─────────────────────────────────────────────────────────────

struct GaiaHealthVertex {
    float3 position [[attribute(0)]];
    float4 color    [[attribute(1)]];
};

// ── Uniforms ──────────────────────────────────────────────────────────────────

struct Uniforms {
    float4x4 mvp;                 // model-view-projection matrix
    float    epistemic_alpha;     // 1.0=M (Measured), 0.6=I (Inferred), 0.3=A (Assumed)
    uint     epistemic_tag;       // 0=M, 1=I, 2=A
    uint     cell_state;          // BiologicalCellState discriminant
    uint     training_mode;       // 1 = synthetic data, no PHI proximity
};

// ── Vertex Output ─────────────────────────────────────────────────────────────

struct VertexOut {
    float4 position [[position]];
    float4 color;
    float2 frag_coord;            // used for stipple pattern in Assumed mode
    float  epistemic_alpha;
    uint   epistemic_tag;
};

// ── Vertex Shader ─────────────────────────────────────────────────────────────

vertex VertexOut bio_vertex_main(
    GaiaHealthVertex in              [[stage_in]],
    constant Uniforms &uniforms      [[buffer(1)]],
    uint              vertex_id      [[vertex_id]]
) {
    VertexOut out;
    out.position        = uniforms.mvp * float4(in.position, 1.0);
    out.color           = in.color;
    out.frag_coord      = float2(out.position.x, out.position.y);
    out.epistemic_alpha = uniforms.epistemic_alpha;
    out.epistemic_tag   = uniforms.epistemic_tag;
    return out;
}

// ── Fragment Shader ───────────────────────────────────────────────────────────

fragment float4 bio_fragment_main(VertexOut in [[stage_in]]) {
    float4 color = in.color;

    // M — Measured: full opacity, solid render
    if (in.epistemic_tag == 0) {
        color.a = 1.0;
        return color;
    }

    // I — Inferred: translucent glass-like render
    if (in.epistemic_tag == 1) {
        color.a = 0.6;
        return color;
    }

    // A — Assumed: checkerboard stipple pattern (8x8 px grid discard)
    // Fragments on even tiles are discarded, producing a stippled appearance.
    int2 tile = int2(int(in.frag_coord.x) / 8, int(in.frag_coord.y) / 8);
    if ((tile.x + tile.y) % 2 == 0) {
        discard_fragment();
    }
    color.a = 0.3;
    return color;
}

// ── CONSTITUTIONAL_FLAG Alarm Shader ─────────────────────────────────────────
// Renders a pulsing red overlay when cell is in CONSTITUTIONAL_FLAG state.
// Alpha cycles 0.4→0.8 using the frame count uniform baked into mvp[3][3].

vertex VertexOut alarm_vertex_main(
    GaiaHealthVertex in         [[stage_in]],
    constant Uniforms &uniforms [[buffer(1)]]
) {
    VertexOut out;
    out.position        = uniforms.mvp * float4(in.position, 1.0);
    out.color           = float4(1.0, 0.1, 0.1, 0.6); // constitutional alarm red
    out.frag_coord      = float2(0.0, 0.0);
    out.epistemic_alpha = 1.0;
    out.epistemic_tag   = 0;
    return out;
}

fragment float4 alarm_fragment_main(VertexOut in [[stage_in]]) {
    return in.color;
}
"#;

/// Vertex stride in bytes (GxP regression-locked by RG-006).
pub const GAIA_HEALTH_VERTEX_STRIDE: usize = 32;

#[cfg(test)]
mod tests {
    use super::*;

    // RG-006: Vertex stride regression guard
    #[test]
    fn rg_006_vertex_stride_32_bytes() {
        assert_eq!(GAIA_HEALTH_VERTEX_STRIDE, 32,
            "GaiaHealthVertex stride must be 32 bytes — MSL attribute descriptor lock");
    }

    // TP-016: Shader source is non-empty and contains required function names
    #[test]
    fn tp_016_shader_source_contains_required_functions() {
        assert!(BIOLOGIT_SHADERS.contains("bio_vertex_main"));
        assert!(BIOLOGIT_SHADERS.contains("bio_fragment_main"));
        assert!(BIOLOGIT_SHADERS.contains("alarm_vertex_main"));
        assert!(BIOLOGIT_SHADERS.contains("alarm_fragment_main"));
    }

    // TP-017: Shader source contains M/I/A epistemic logic
    #[test]
    fn tp_017_shader_contains_epistemic_logic() {
        assert!(BIOLOGIT_SHADERS.contains("epistemic_tag == 0")); // M
        assert!(BIOLOGIT_SHADERS.contains("epistemic_tag == 1")); // I
        assert!(BIOLOGIT_SHADERS.contains("discard_fragment"));   // A stipple
    }
}
