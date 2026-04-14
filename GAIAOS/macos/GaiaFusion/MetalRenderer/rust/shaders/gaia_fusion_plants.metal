#include <metal_stdlib>
using namespace metal;

// ═══════════════════════════════════════════════════════════════
// GaiaFusion Plant Topology Shaders — Precompiled for Apple Silicon
// All 9 fusion plant types: tokamak, stellarator, frc, spheromak,
// mirror, inertial, spherical_tokamak, z_pinch, mif
// ═══════════════════════════════════════════════════════════════

// ── Vertex layout matches GaiaVertex in Rust (repr(C)) ──
struct VertexIn {
    float3 position [[attribute(0)]];
    float4 color    [[attribute(1)]];
};

struct VertexOut {
    float4 position [[position]];
    float4 color;
};

// ── Uniforms: MVP matrix + plant type ID ──
struct Uniforms {
    float4x4 mvp;
    uint plant_type;  // 0=tokamak, 1=stellarator, etc.
    float time;       // For animation if needed
};

// ═══════════════════════════════════════════════════════════════
// VERTEX SHADER — Universal for all plant types
// ═══════════════════════════════════════════════════════════════

vertex VertexOut vertex_main(
    VertexIn in [[stage_in]],
    constant Uniforms &uniforms [[buffer(1)]]
) {
    VertexOut out;
    
    // Transform vertex position with MVP matrix
    out.position = uniforms.mvp * float4(in.position, 1.0);
    
    // Pass through vertex color
    out.color = in.color;
    
    return out;
}

// ═══════════════════════════════════════════════════════════════
// FRAGMENT SHADER — Universal wireframe rendering
// ═══════════════════════════════════════════════════════════════

fragment float4 fragment_main(
    VertexOut in [[stage_in]],
    constant Uniforms &uniforms [[buffer(1)]]
) {
    // Direct passthrough of vertex color (computed in Rust based on entropy/truth)
    return in.color;
}

// ═══════════════════════════════════════════════════════════════
// PLANT-SPECIFIC COMPUTE KERNELS (if needed for physics sim)
// ═══════════════════════════════════════════════════════════════

// Tokamak magnetic field computation (example)
kernel void compute_tokamak_field(
    device float3* positions [[buffer(0)]],
    device float3* field_vectors [[buffer(1)]],
    constant float& major_radius [[buffer(2)]],
    constant float& minor_radius [[buffer(3)]],
    uint id [[thread_position_in_grid]]
) {
    float3 pos = positions[id];
    // Simplified toroidal field computation
    float R = length(pos.xy);
    float B_phi = major_radius / R;
    field_vectors[id] = float3(0.0, 0.0, B_phi);
}

// Stellarator twisted coil field (example)
kernel void compute_stellarator_field(
    device float3* positions [[buffer(0)]],
    device float3* field_vectors [[buffer(1)]],
    constant float& twist_period [[buffer(2)]],
    uint id [[thread_position_in_grid]]
) {
    float3 pos = positions[id];
    float theta = atan2(pos.y, pos.x);
    float twist = sin(twist_period * theta);
    field_vectors[id] = float3(twist, -twist, 1.0);
}

// Note: For wireframe rendering, most plant differentiation happens
// in Rust geometry generation, not shaders. These compute kernels
// are placeholders for future physics simulation on GPU.
