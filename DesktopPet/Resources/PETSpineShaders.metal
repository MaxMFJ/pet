#include <metal_stdlib>
using namespace metal;

struct PETSpineMetalVertex {
    float2 position;
    float2 uv;
    float4 color;
};

struct PETSpineUniforms {
    float4x4 transform;
};

struct PETSpineRasterizerData {
    float4 position [[position]];
    float2 uv;
    float4 color;
};

vertex PETSpineRasterizerData petSpineVertexMain(const device PETSpineMetalVertex *vertices [[buffer(0)]],
                                                 constant PETSpineUniforms &uniforms [[buffer(1)]],
                                                 uint vertexID [[vertex_id]]) {
    PETSpineRasterizerData out;
    float4 worldPosition = float4(vertices[vertexID].position, 0.0, 1.0);
    out.position = uniforms.transform * worldPosition;
    out.uv = vertices[vertexID].uv;
    out.color = vertices[vertexID].color;
    return out;
}

fragment float4 petSpineFragmentMain(PETSpineRasterizerData in [[stage_in]],
                                     constant PETSpineUniforms &uniforms [[buffer(1)]],
                                     texture2d<float> atlasTexture [[texture(0)]]) {
    (void)uniforms;
    constexpr sampler atlasSampler(address::clamp_to_edge, filter::linear);
    float4 texel = atlasTexture.sample(atlasSampler, in.uv);
    return texel * in.color;
}
