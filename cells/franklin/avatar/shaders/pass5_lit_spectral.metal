// ─────────────────────────────────────────────────────────────────────────────
// pass5_lit_spectral.metal
//
// Z3 pass 5 — lit shading. PBR + spectral integration. For each fragment the
// shader integrates the active illuminant's Planckian SPD against the
// material reflectance LUT (claret silk, etc.) bin-by-bin, then collapses to
// a tristimulus radiance and applies microfacet BRDF + shadow occlusion from
// pass 2. This is what makes the candle-lit Passy salon read as 1778 instead
// of fluorescent.
// ─────────────────────────────────────────────────────────────────────────────

#include "Common.metal"
using namespace metal;

inline float3 sample_shadow_pcf(
    texture2d<float> shadow_map,
    sampler s,
    float4 light_clip
) {
    float3 ndc = light_clip.xyz / light_clip.w;
    float2 uv = ndc.xy * 0.5f + 0.5f;
    if (any(uv < 0.0f) || any(uv > 1.0f)) return float3(1.0f);
    float frag_z = ndc.z;
    float occ = 0.0f;
    int taps = 0;
    for (int dx = -1; dx <= 1; ++dx) {
        for (int dy = -1; dy <= 1; ++dy) {
            float2 ouv = uv + float2(dx, dy) / float2(2048.0f);
            float depth = shadow_map.sample(s, ouv).r;
            occ += (frag_z - 0.001f > depth) ? 0.0f : 1.0f;
            taps++;
        }
    }
    return float3(occ / float(taps));
}

// Visible-spectrum bin centers (nm). At 32 bins we cover 380–730 nm.
constant constexpr uint kMaxSpectralBins = 64u;

fragment float4 pass5_lit_fragment(
    AvatarV2F in [[stage_in]],
    constant AvatarFrameUniforms& uniforms [[buffer(0)]],
    texture2d<float> albedo_map [[texture(0)]],
    texture2d<float> normal_map [[texture(1)]],
    texture2d<float> roughness_map [[texture(2)]],
    texture2d<float> claret_lut [[texture(3)]],         // claret_silk_degradation.exr
    texture2d<float> shadow_map [[texture(4)]],
    sampler s [[sampler(0)]]
) {
    // ── Surface
    float3 albedo = srgb_to_linear(albedo_map.sample(s, in.uv).rgb);
    float roughness = roughness_map.sample(s, in.uv).r;
    float3 n_local = normal_map.sample(s, in.uv).rgb * 2.0f - 1.0f;
    float3 b = normalize(cross(in.world_normal, in.world_tangent));
    float3x3 tbn = float3x3(in.world_tangent, b, in.world_normal);
    float3 n = normalize(tbn * n_local);
    float3 v = normalize(uniforms.camera_pos - in.world_position);
    float3 l = normalize(uniforms.light_pos - in.world_position);
    float3 h = normalize(v + l);

    // ── BRDF (Cook–Torrance)
    float n_dot_l = max(dot(n, l), 0.0f);
    float f = fresnel_schlick(saturate(dot(h, v)), 0.04f);
    float d = distribution_ggx(n, h, roughness);
    float g = geometry_smith(n, v, l, roughness);
    float specular = (d * g * f) / max(4.0f * n_dot_l * max(dot(n, v), 0.0f), 1e-4f);
    float3 kd = (1.0f - f) * (1.0f - 0.0f);
    float3 brdf_color = kd * albedo / M_PI_F + specular;

    // ── Spectral integration against Planckian illuminant.
    // Bins evenly cover 380..730 nm. Reflectance comes from claret_lut along
    // (illuminant_temperature_k → u) and (uv.y → v) so the LUT carries period
    // degradation per material variant.
    uint bins = min(uniforms.spectral_bin_count, kMaxSpectralBins);
    float3 spectral_radiance = float3(0.0f);
    float total_weight = 0.0f;
    float u_temp = (uniforms.illuminant_temperature_k - 1500.0f) / (8000.0f - 1500.0f);
    for (uint i = 0; i < bins; ++i) {
        float lambda = mix(380.0f, 730.0f, (float(i) + 0.5f) / float(bins));
        float spd = planck_spd(lambda, uniforms.illuminant_temperature_k);
        float reflectance = claret_lut.sample(s, float2(saturate(u_temp), in.uv.y)).r;
        // Cheap CIE 1931 lobe approximation for the bin → tristimulus lift.
        float xw = exp(-pow((lambda - 600.0f) / 80.0f, 2.0f));
        float yw = exp(-pow((lambda - 555.0f) / 60.0f, 2.0f));
        float zw = exp(-pow((lambda - 450.0f) / 50.0f, 2.0f));
        spectral_radiance += spd * reflectance * float3(xw, yw, zw);
        total_weight += spd;
    }
    if (total_weight > 0.0f) spectral_radiance /= total_weight;

    // ── Shadowed direct + spectral ambient
    float3 shadow = sample_shadow_pcf(shadow_map, s, uniforms.light_view_proj * float4(in.world_position, 1.0f));
    float3 lit = brdf_color * n_dot_l * shadow + spectral_radiance * 0.25f;

    return float4(lit, 1.0f);
}
