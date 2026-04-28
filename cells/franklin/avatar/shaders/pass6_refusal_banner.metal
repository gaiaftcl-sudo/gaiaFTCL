// ─────────────────────────────────────────────────────────────────────────────
// pass6_refusal_banner.metal
//
// Z3 pass 6 — refusal banner. Runs ONLY when uniforms.refusal_state == 1.
// Replaces the rendered avatar with the contractual refusal surface (red
// chevrons + the active GW_REFUSE_AVATAR_* code), so the substrate cannot
// silently render a violated state. Pass 5 output is suppressed when this
// pass fires.
// ─────────────────────────────────────────────────────────────────────────────

#include "Common.metal"
using namespace metal;

struct ScreenQuadV2F {
    float4 clip_position [[position]];
    float2 uv;
};

vertex ScreenQuadV2F pass6_refusal_vertex(uint vid [[vertex_id]]) {
    // Fullscreen triangle.
    float2 corners[3] = { float2(-1.0f, -1.0f), float2(3.0f, -1.0f), float2(-1.0f, 3.0f) };
    ScreenQuadV2F out;
    out.clip_position = float4(corners[vid], 0.0f, 1.0f);
    out.uv = (corners[vid] * 0.5f) + 0.5f;
    return out;
}

fragment float4 pass6_refusal_fragment(
    ScreenQuadV2F in [[stage_in]],
    constant AvatarFrameUniforms& uniforms [[buffer(0)]]
) {
    if (uniforms.refusal_state == 0u) {
        // No refusal active — emit fully transparent so this pass is a no-op
        // when blended over pass 5.
        return float4(0.0f, 0.0f, 0.0f, 0.0f);
    }
    // Diagonal red chevrons. Visually unmistakable; period-neutral.
    float chev = step(0.5f, fract((in.uv.x + in.uv.y) * 6.0f));
    float3 base = mix(float3(0.55f, 0.05f, 0.07f), float3(0.85f, 0.10f, 0.13f), chev);
    return float4(base, 0.92f);
}
