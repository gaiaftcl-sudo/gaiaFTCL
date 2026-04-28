// ─────────────────────────────────────────────────────────────────────────────
// pass1_geometry.metal
//
// Z3 pass 1 — geometry. Skins the Passy mesh to FACS-52 blendshapes, transforms
// to world / clip space, and writes per-vertex attributes downstream passes
// consume. No lighting here — this pass is structural.
// ─────────────────────────────────────────────────────────────────────────────

#include "Common.metal"
using namespace metal;

vertex AvatarV2F pass1_geometry_vertex(
    AvatarVertex in [[stage_in]],
    constant AvatarFrameUniforms& uniforms [[buffer(1)]],
    constant AvatarBlendshapes& blendshapes [[buffer(2)]],
    constant float4x4* bone_palette [[buffer(3)]],
    constant float3* blendshape_deltas [[buffer(4)]],   // 56 deltas per vertex
    uint vertex_id [[vertex_id]]
) {
    AvatarV2F out;

    // ── Blendshape sum (FACS-52). Per-vertex deltas pre-uploaded to buffer(4).
    float3 deformed_pos = in.position;
    for (uint i = 0; i < 56; ++i) {
        float w = blendshapes.weights[i];
        if (w > 0.0f) {
            uint base = vertex_id * 56u + i;
            deformed_pos += w * blendshape_deltas[base];
        }
    }

    // ── Linear blend skinning (4 bones, packed weights).
    uint b0 = (in.bone_ids >>  0) & 0xff;
    uint b1 = (in.bone_ids >>  8) & 0xff;
    uint b2 = (in.bone_ids >> 16) & 0xff;
    uint b3 = (in.bone_ids >> 24) & 0xff;
    float4x4 skin = bone_palette[b0] * in.bone_weights.x
                  + bone_palette[b1] * in.bone_weights.y
                  + bone_palette[b2] * in.bone_weights.z
                  + bone_palette[b3] * in.bone_weights.w;

    float4 world = skin * float4(deformed_pos, 1.0f);
    out.world_position = world.xyz;
    out.clip_position = uniforms.view_proj * world;

    float3x3 normal_matrix = float3x3(skin[0].xyz, skin[1].xyz, skin[2].xyz);
    out.world_normal  = normalize(normal_matrix * in.normal);
    out.world_tangent = normalize(normal_matrix * in.tangent);

    out.uv = in.uv;

    float3 v = normalize(uniforms.camera_pos - out.world_position);
    out.fresnel = fresnel_schlick(saturate(dot(v, out.world_normal)), 0.04f);

    // Shadow depth seeded; pass 2 overwrites for shadow-targeted draw.
    out.shadow_depth = 0.0f;
    return out;
}

fragment float4 pass1_geometry_fragment(
    AvatarV2F in [[stage_in]]
) {
    // pass1 is opaque G-buffer-style. No real shading; downstream passes mix.
    return float4(in.world_normal * 0.5f + 0.5f, 1.0f);
}
