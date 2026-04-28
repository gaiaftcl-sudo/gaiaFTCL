// ─────────────────────────────────────────────────────────────────────────────
// pass4_strand_fur.metal
//
// Z3 pass 4 — anisotropic strand rendering for the tied-back grey-white hair
// and the beaver-fur Passy cap. ~120 k strands × N segments expanded into
// view-aligned camera-facing ribbons via vertex amplification, then shaded
// with Marschner-style anisotropic highlights using the pre-baked flow map
// (anisotropic_flow_map.exr) and the spectral reflectance LUT for cap fur
// (beaver_cap_spectral_lut.exr).
// ─────────────────────────────────────────────────────────────────────────────

#include "Common.metal"
using namespace metal;

struct StrandRoot {
    float3 root_world;
    float3 root_normal;
    float  curl_phase;
    uint   region_id;       // 0=hair, 1=beaver_cap
};

struct StrandV2F {
    float4 clip_position [[position]];
    float3 world_position;
    float3 tangent;
    float  along;           // 0 root → 1 tip
    uint   region_id;
};

vertex StrandV2F pass4_strand_vertex(
    constant StrandRoot* roots [[buffer(0)]],
    constant AvatarStrandConstants& sc [[buffer(1)]],
    constant AvatarFrameUniforms& uniforms [[buffer(2)]],
    uint vid [[vertex_id]]
) {
    uint strand_id  = vid / (sc.segments_per_strand * 2u);
    uint along_idx  = (vid / 2u) % sc.segments_per_strand;
    uint side       = vid & 1u;             // 0 = -tangent edge, 1 = +tangent edge
    StrandRoot r = roots[strand_id];
    float along = float(along_idx) / float(sc.segments_per_strand - 1u);
    float radius = mix(sc.root_radius_m, sc.tip_radius_m, along);

    // Curve along the anisotropy axis with a per-strand phase offset.
    float3 tip_dir = normalize(sc.anisotropy_axis + 0.18f * sin(uniforms.time_seconds + r.curl_phase));
    float3 along_pos = r.root_world + tip_dir * along * 0.06f;   // 6 cm strand length
    float3 view_normal = normalize(uniforms.camera_pos - along_pos);
    float3 ribbon_x = normalize(cross(tip_dir, view_normal));
    float3 world = along_pos + (side == 1u ? +radius : -radius) * ribbon_x;

    StrandV2F out;
    out.world_position = world;
    out.clip_position = uniforms.view_proj * float4(world, 1.0f);
    out.tangent = tip_dir;
    out.along = along;
    out.region_id = r.region_id;
    return out;
}

fragment float4 pass4_strand_fragment(
    StrandV2F in [[stage_in]],
    texture2d<float> flow_map [[texture(0)]],          // anisotropic_flow_map.exr
    texture2d<float> beaver_lut [[texture(1)]],        // beaver_cap_spectral_lut.exr
    constant AvatarFrameUniforms& uniforms [[buffer(0)]],
    sampler s [[sampler(0)]]
) {
    float3 t = normalize(in.tangent);
    float3 v = normalize(uniforms.camera_pos - in.world_position);
    float3 l = normalize(uniforms.light_pos - in.world_position);
    float3 h = normalize(v + l);

    // Marschner-ish: longitudinal highlight along tangent, lobe shifted by flow map.
    float t_dot_l = dot(t, l);
    float t_dot_v = dot(t, v);
    float sin_tl = sqrt(saturate(1.0f - t_dot_l * t_dot_l));
    float sin_tv = sqrt(saturate(1.0f - t_dot_v * t_dot_v));
    float spec = pow(saturate(t_dot_l * t_dot_v + sin_tl * sin_tv), 32.0f);

    float3 base;
    if (in.region_id == 1u) {
        // Beaver cap: integrate spectral LUT against current illuminant T_K.
        float u = (uniforms.illuminant_temperature_k - 1500.0f) / (8000.0f - 1500.0f);
        base = beaver_lut.sample(s, float2(saturate(u), in.along)).rgb;
    } else {
        // Tied-back hair: cool grey-white that warms slightly toward the tips.
        base = mix(float3(0.78f, 0.76f, 0.74f), float3(0.92f, 0.90f, 0.86f), in.along);
    }
    float3 c = base * 0.9f + spec * float3(1.0f, 0.95f, 0.88f);
    return float4(c, 1.0f);
}
