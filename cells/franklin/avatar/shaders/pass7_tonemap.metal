// ─────────────────────────────────────────────────────────────────────────────
// pass7_tonemap.metal
//
// Z3 pass 7 — tonemap + output transform. Maps linear-light HDR to the active
// display gamut. M-series Macs default to Display P3; HDR scenes go to
// BT.2100 PQ via a dedicated ACES Filmic curve. SDR uses ACES Reinhard.
//
// Output color space tagging is applied by the host AVAssetWriter / drawable;
// this shader only produces linear-encoded color in the active primary set.
// ─────────────────────────────────────────────────────────────────────────────

#include "Common.metal"
using namespace metal;

struct ScreenQuadV2F {
    float4 clip_position [[position]];
    float2 uv;
};

inline float3 aces_filmic(float3 x) {
    // Narkowicz 2015 fit of ACES Filmic.
    const float a = 2.51f;
    const float b = 0.03f;
    const float c = 2.43f;
    const float d = 0.59f;
    const float e = 0.14f;
    return saturate((x * (a * x + b)) / (x * (c * x + d) + e));
}

inline float3 reinhard(float3 x) {
    return x / (1.0f + x);
}

vertex ScreenQuadV2F pass7_tonemap_vertex(uint vid [[vertex_id]]) {
    float2 corners[3] = { float2(-1.0f, -1.0f), float2(3.0f, -1.0f), float2(-1.0f, 3.0f) };
    ScreenQuadV2F out;
    out.clip_position = float4(corners[vid], 0.0f, 1.0f);
    out.uv = (corners[vid] * 0.5f) + 0.5f;
    return out;
}

fragment float4 pass7_tonemap_fragment(
    ScreenQuadV2F in [[stage_in]],
    texture2d<float> hdr_input [[texture(0)]],
    texture2d<float> refusal_overlay [[texture(1)]],
    constant AvatarFrameUniforms& uniforms [[buffer(0)]],
    sampler s [[sampler(0)]]
) {
    float3 hdr = hdr_input.sample(s, in.uv).rgb;
    float3 mapped = (uniforms.refusal_state == 0u) ? aces_filmic(hdr) : reinhard(hdr);
    float4 overlay = refusal_overlay.sample(s, in.uv);
    float3 final_color = mix(mapped, overlay.rgb, overlay.a);
    return float4(final_color, 1.0f);
}
