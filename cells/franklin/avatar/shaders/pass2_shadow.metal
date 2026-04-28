// ─────────────────────────────────────────────────────────────────────────────
// pass2_shadow.metal
//
// Z3 pass 2 — light-space depth. Renders the avatar from the light's POV
// into a depth-only attachment so pass 5 can sample shadow occlusion. Same
// skinning + blendshape math as pass 1 but uses light_view_proj.
// ─────────────────────────────────────────────────────────────────────────────

#include "Common.metal"
using namespace metal;

struct ShadowVOut {
    float4 clip_position [[position]];
};

vertex ShadowVOut pass2_shadow_vertex(
    AvatarVertex in [[stage_in]],
    constant AvatarFrameUniforms& uniforms [[buffer(1)]],
    constant AvatarBlendshapes& blendshapes [[buffer(2)]],
    constant float4x4* bone_palette [[buffer(3)]],
    constant float3* blendshape_deltas [[buffer(4)]],
    uint vertex_id [[vertex_id]]
) {
    float3 deformed_pos = in.position;
    for (uint i = 0; i < 56; ++i) {
        float w = blendshapes.weights[i];
        if (w > 0.0f) {
            uint base = vertex_id * 56u + i;
            deformed_pos += w * blendshape_deltas[base];
        }
    }
    uint b0 = (in.bone_ids >>  0) & 0xff;
    uint b1 = (in.bone_ids >>  8) & 0xff;
    uint b2 = (in.bone_ids >> 16) & 0xff;
    uint b3 = (in.bone_ids >> 24) & 0xff;
    float4x4 skin = bone_palette[b0] * in.bone_weights.x
                  + bone_palette[b1] * in.bone_weights.y
                  + bone_palette[b2] * in.bone_weights.z
                  + bone_palette[b3] * in.bone_weights.w;
    float4 world = skin * float4(deformed_pos, 1.0f);

    ShadowVOut out;
    out.clip_position = uniforms.light_view_proj * world;
    return out;
}

// Depth-only fragment — no color attachment. Shader exists so the encoder
// can bind a complete pipeline state.
fragment void pass2_shadow_fragment(ShadowVOut in [[stage_in]]) {
    // intentionally empty; depth attachment handles occluder write.
}
