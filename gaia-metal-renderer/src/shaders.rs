/// Metal Shading Language source compiled at runtime.
/// No .metallib build step — sovereign, self-contained.
pub const SHADER_SOURCE: &str = r#"
#include <metal_stdlib>
using namespace metal;

// ── Vertex layout matches GaiaVertex in Rust ──
struct VertexIn {
    float3 position [[attribute(0)]];
    float4 color    [[attribute(1)]];
};

struct VertexOut {
    float4 position [[position]];
    float4 color;
};

// ── Uniforms: MVP matrix pushed per-frame ──
struct Uniforms {
    float4x4 mvp;
};

vertex VertexOut vertex_main(
    VertexIn in [[stage_in]],
    constant Uniforms &uniforms [[buffer(1)]]
) {
    VertexOut out;
    out.position = uniforms.mvp * float4(in.position, 1.0);
    out.color = in.color;
    return out;
}

fragment float4 fragment_main(VertexOut in [[stage_in]]) {
    return in.color;
}
"#;
