// ─────────────────────────────────────────────────────────────────────────────
// Common.metal
//
// Shared structs, samplers, and helpers for the Franklin Z3 7-pass pipeline.
// Compiled into Franklin_Z3_Materials.metallib by scripts/build_metallib.zsh.
//
// Pipeline (left → right): pass1 geometry → pass2 shadow → pass3 PBD cloth →
// pass4 strand fur → pass5 lit (spectral) → pass6 refusal banner → pass7 tonemap.
//
// ABI contract: structs marked `[[buffer(N)]]` must match the Rust-side
// avatar-render encoder layout exactly. A change to any of these requires
// regenerating the Swift FFI header and bumping AVATAR_RENDER_ABI_VERSION.
// ─────────────────────────────────────────────────────────────────────────────

#include <metal_stdlib>
using namespace metal;

// ABI version — bump on any layout change.
constant constexpr uint AVATAR_RENDER_ABI_VERSION = 3;

// ─── shared structs ──────────────────────────────────────────────────────────

struct AvatarVertex {
    float3 position    [[attribute(0)]];
    float3 normal      [[attribute(1)]];
    float3 tangent     [[attribute(2)]];
    float2 uv          [[attribute(3)]];
    uint   bone_ids    [[attribute(4)]];   // packed 4×u8
    float4 bone_weights[[attribute(5)]];
};

struct AvatarV2F {
    float4 clip_position [[position]];
    float3 world_position;
    float3 world_normal;
    float3 world_tangent;
    float2 uv;
    float  shadow_depth;
    float  fresnel;
};

struct AvatarFrameUniforms {
    float4x4 view;
    float4x4 projection;
    float4x4 view_proj;
    float4x4 light_view_proj;
    float3   camera_pos;
    float    time_seconds;
    float3   light_pos;
    uint     spectral_bin_count;       // 11 / 32 / 64 per DeviceTier
    float    illuminant_temperature_k; // 1850 candle, 6504 daylight, etc.
    uint     refusal_state;            // 0 = projecting, 1 = refused (drives pass6)
    uint     pad0;
    uint     pad1;
};

// 56 FACS-52 blendshapes + 4 padding lanes for 16-byte alignment.
struct AvatarBlendshapes {
    float weights[56];
};

struct AvatarStrandConstants {
    uint   strand_count;        // ~120k for Passy hair + cap
    uint   segments_per_strand;
    float  root_radius_m;
    float  tip_radius_m;
    float3 anisotropy_axis;
    float  alpha_coverage;
};

// PBD cloth particle (frock coat + cravat). 32 bytes.
struct ClothParticle {
    float3 position;
    float  inv_mass;
    float3 velocity;
    float  pad0;
};

// PBD distance constraint between two particles.
struct ClothConstraint {
    uint  a;
    uint  b;
    float rest_length_m;
    float compliance;            // XPBD inverse-stiffness
};

// ─── helpers ─────────────────────────────────────────────────────────────────

inline float3 srgb_to_linear(float3 c) {
    return pow((c + 0.055f) / 1.055f, 2.4f);
}

inline float3 linear_to_srgb(float3 c) {
    return 1.055f * pow(max(c, 0.0f), 1.0f / 2.4f) - 0.055f;
}

inline float fresnel_schlick(float cos_theta, float f0) {
    return f0 + (1.0f - f0) * pow(1.0f - cos_theta, 5.0f);
}

inline float distribution_ggx(float3 n, float3 h, float roughness) {
    float a = roughness * roughness;
    float a2 = a * a;
    float n_dot_h = max(dot(n, h), 0.0f);
    float denom = (n_dot_h * n_dot_h * (a2 - 1.0f) + 1.0f);
    return a2 / (M_PI_F * denom * denom);
}

inline float geometry_smith(float3 n, float3 v, float3 l, float roughness) {
    float k = (roughness + 1.0f);
    k = (k * k) / 8.0f;
    float n_dot_v = max(dot(n, v), 0.0f);
    float n_dot_l = max(dot(n, l), 0.0f);
    float gv = n_dot_v / (n_dot_v * (1.0f - k) + k);
    float gl = n_dot_l / (n_dot_l * (1.0f - k) + k);
    return gv * gl;
}

// Planckian SPD at wavelength λ (nm), temperature T (K). c1 c2 are CIE.
inline float planck_spd(float lambda_nm, float temperature_k) {
    const float h = 6.62607015e-34f;
    const float c = 2.99792458e+8f;
    const float k = 1.380649e-23f;
    float lambda_m = lambda_nm * 1e-9f;
    float c1 = 2.0f * h * c * c;
    float c2 = (h * c) / (k * temperature_k);
    return (c1 / pow(lambda_m, 5.0f)) / (exp(c2 / lambda_m) - 1.0f);
}
