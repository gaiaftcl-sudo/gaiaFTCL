#include <metal_stdlib>
using namespace metal;

struct Uniforms {
    float4x4 modelViewProjection;
    float4 lineColor;
    uint diagnosticRefused;
    uint plantKindIndex;
    float normalizedT;
    float telemetryIp;
    float telemetryBt;
    float telemetryNe;
};

struct VSOut {
    float4 position [[position]];
};

vertex VSOut usd_proxy_vertex(
    const device packed_float3* positions [[buffer(0)]],
    constant Uniforms& u [[buffer(1)]],
    uint vid [[vertex_id]]
) {
    VSOut o;
    float3 p = positions[vid];
    o.position = u.modelViewProjection * float4(p, 1.0);
    return o;
}

/// SubGame Y: plant-kind and timeline/telemetry modulation on wireframe color (fragment-only; geometry stays line-list).
fragment float4 usd_proxy_fragment(constant Uniforms& u [[buffer(1)]]) {
    if (u.diagnosticRefused != 0u) {
        return float4(1.0, 0.12, 0.06, 1.0);
    }
    float t = saturate(u.normalizedT);
    float ipN = saturate(u.telemetryIp * 0.5);
    float btN = saturate(u.telemetryBt * 0.5);
    float3 c = u.lineColor.rgb;
    uint k = u.plantKindIndex;

    float pulse = 0.72 + 0.28 * sin(t * 6.2831853 * 2.0);
    if (k == 0u) {
        pulse *= 1.0 + 2.2 * pow(t, 3.0);
        c.g *= 0.85 + 0.15 * pulse;
    } else if (k == 1u) {
        float conf = saturate(1.2 - btN * 1.1);
        c *= float3(0.9 + 0.1 * conf, 0.95, 1.0);
    } else if (k == 3u) {
        float n = fract(sin(dot(float2(t, btN), float2(12.9898, 78.233))) * 43758.5453);
        c.r += 0.08 * n * pulse;
    } else if (k == 4u || k == 5u) {
        c.b += 0.06 * (1.0 - t);
    } else if (k == 6u) {
        c.g += 0.12 * pulse * mix(btN, 1.0, ipN);
    } else if (k == 8u) {
        float shift = t * t;
        c = mix(c, float3(0.45, 0.55, 1.0), shift * 0.35);
    }
    c *= (0.88 + 0.12 * pulse);
    return float4(saturate(c), 1.0);
}
