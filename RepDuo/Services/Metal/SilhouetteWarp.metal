#include <metal_stdlib>
using namespace metal;

struct SilhouetteVertexOut {
    float4 position [[position]];
    float2 uv;
    float part [[flat]];
};

// Positions are Vision-normalized (origin bottom-left). Core Image reads a
// texture's first row as its bottom edge, so y = 0 maps to the first row here.
vertex SilhouetteVertexOut silhouette_vertex(
    uint vid [[vertex_id]],
    const device float2 *positions [[buffer(0)]],
    const device float2 *uvs [[buffer(1)]],
    const device float *parts [[buffer(2)]]
) {
    SilhouetteVertexOut out;
    float2 p = positions[vid];
    out.position = float4(p.x * 2.0 - 1.0, 1.0 - p.y * 2.0, 0.0, 1.0);
    out.uv = uvs[vid];
    out.part = parts[vid];
    return out;
}

// Samples the calibrated outline through the deformed mesh, keeping only the
// pixels that belong to this mesh's body part. A narrow smoothstep keeps the
// averaged mask's edge crisp but anti-aliased.
fragment float4 silhouette_fragment(
    SilhouetteVertexOut in [[stage_in]],
    texture2d<float> mask [[texture(0)]],
    texture2d<uint> labels [[texture(1)]]
) {
    uint2 size = uint2(labels.get_width(), labels.get_height());
    uint2 texel = min(uint2(in.uv * float2(size)), size - 1);
    if (labels.read(texel).r != uint(in.part + 0.5)) {
        discard_fragment();
    }
    constexpr sampler linearSampler(filter::linear, address::clamp_to_zero);
    float value = smoothstep(0.35, 0.65, mask.sample(linearSampler, in.uv).r);
    return float4(value);
}
