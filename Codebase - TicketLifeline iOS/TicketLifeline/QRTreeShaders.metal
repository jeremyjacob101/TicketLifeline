#include <metal_stdlib>
using namespace metal;

struct Uniforms {
    float aspectRatio;
    float time;
    float blockCount;
    float progress;
    float gridSize;
    float3 padding;
};

struct BlockData {
    float4 position;
    float height;
    float baseY;
    uint type;
    uint padding;
};

struct RasterOut {
    float4 position [[position]];
    float2 uv;
    float3 normal;
    float blockType;
    float col;
    float row;
    float layer;
};

struct SimpleOut {
    float4 position [[position]];
    float2 uv;
};

constant float blockSize = 0.0245;
constant float isoAngleY = 0.78;
constant float isoAngleX = -0.55;
constant float flatAngleY = 0.0;
constant float flatAngleX = -1.5708;

vertex RasterOut qrBlockVertex(
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]],
    constant Uniforms &uniforms [[buffer(0)]],
    const device BlockData *blocks [[buffer(1)]]) {
    RasterOut out;
    BlockData block = blocks[instanceID];
    uint face = vertexID / 6;
    uint localIndex = vertexID % 6;
    const float2 quad[6] = {
        float2(0, 0), float2(1, 0), float2(0, 1),
        float2(0, 1), float2(1, 0), float2(1, 1)
    };
    float2 q = quad[localIndex];
    float halfGrid = uniforms.gridSize * blockSize * 0.5;
    // Block positions are module indices. Offset by half a module before
    // centering so an odd or even QR matrix is geometrically exact.
    float baseX = (block.position.x + 0.5) * blockSize - halfGrid;
    float baseY = block.baseY;
    float baseZ = (block.position.y + 0.5) * blockSize - halfGrid;
    float halfSize = blockSize * 0.5;
    float h = block.height;
    bool decorative = block.type >= 5;
    float widthScale = decorative ? (1.0 - uniforms.progress) : 1.0;
    halfSize *= widthScale;
    float3 p = 0;
    float3 n = 0;

    if (face == 0) {
        p = float3(baseX + (q.x - 0.5) * blockSize * widthScale, baseY + h * widthScale, baseZ + (q.y - 0.5) * blockSize * widthScale); n = float3(0, 1, 0);
    } else if (face == 1) {
        p = float3(baseX + (q.x - 0.5) * blockSize * widthScale, baseY, baseZ + (0.5 - q.y) * blockSize * widthScale); n = float3(0, -1, 0);
    } else if (face == 2) {
        p = float3(baseX + (q.x - 0.5) * blockSize * widthScale, baseY + q.y * h * widthScale, baseZ + halfSize); n = float3(0, 0, 1);
    } else if (face == 3) {
        p = float3(baseX + (0.5 - q.x) * blockSize * widthScale, baseY + q.y * h * widthScale, baseZ - halfSize); n = float3(0, 0, -1);
    } else if (face == 4) {
        p = float3(baseX + halfSize, baseY + q.y * h * widthScale, baseZ + (q.x - 0.5) * blockSize * widthScale); n = float3(1, 0, 0);
    } else {
        p = float3(baseX - halfSize, baseY + q.y * h * widthScale, baseZ + (0.5 - q.x) * blockSize * widthScale); n = float3(-1, 0, 0);
    }

    float angleY = mix(isoAngleY, flatAngleY, uniforms.progress);
    float angleX = mix(isoAngleX, flatAngleX, uniforms.progress);
    float cy = cos(angleY), sy = sin(angleY), cx = cos(angleX), sx = sin(angleX);
    float rotatedX = p.x * cy - p.z * sy;
    float rotatedZ = p.x * sy + p.z * cy;
    float rotatedY = p.y * cx - rotatedZ * sx;
    float depth = p.y * sx + rotatedZ * cx;
    float viewScale = mix(1.6, 2.1, uniforms.progress);
    float scaleX = viewScale / max(uniforms.aspectRatio, 1.0);
    float scaleY = viewScale / max(1.0 / uniforms.aspectRatio, 1.0);
    // The 3D crown is visually top-heavy. Bring that mode down slightly so
    // its actual bounds center in the card, while the flat scan view stays
    // mathematically centered at the origin.
    float yOffset = mix(-0.055, 0.0, uniforms.progress);
    out.position = float4(rotatedX * scaleX, (rotatedY + yOffset) * scaleY, depth * 0.01 + 0.5, 1);
    out.uv = q;
    out.normal = n;
    out.blockType = float(block.type == 5 ? 1 : block.type == 6 ? 2 : block.type);
    out.col = block.position.x;
    out.row = block.position.y;
    out.layer = block.baseY / blockSize;
    return out;
}

float randomValue(float seed) { return fract(sin(seed) * 43758.5); }
float3 pickPathTile(float value) {
    // Exact values from Codebase - TicketLifeline Web/src/QrTreeCode.tsx.
    if (value < 0.25) return float3(0.973, 0.965, 0.937); // #f8f6ef
    if (value < 0.50) return float3(0.933, 0.918, 0.867); // #eeeadd
    if (value < 0.75) return float3(0.902, 0.878, 0.824); // #e6e0d2
    return float3(0.957, 0.945, 0.906);                    // #f4f1e7
}

float3 webPalette(int type, float3 normal, float variation) {
    // The web canvas paints each cuboid face with a fixed palette. Do the
    // same here instead of applying HDR lighting/ACES, which was bleaching it.
    if (type == 0) return pickPathTile(variation);

    bool top = normal.y > 0.5;
    bool left = normal.z > 0.5;
    bool right = normal.x > 0.5;
    if (type == 1) { // blossom
        if (top) return float3(1.000, 0.824, 0.863);        // #ffd2dc
        if (left) return float3(0.784, 0.471, 0.565);       // #c87890
        if (right) return float3(0.914, 0.608, 0.678);      // #e99bad
        return float3(0.839, 0.533, 0.616);                 // #d6889d
    }
    if (type == 2) { // trunk
        if (top) return float3(0.604, 0.416, 0.263);        // #9a6a43
        if (left) return float3(0.369, 0.239, 0.169);       // #5e3d2b
        if (right) return float3(0.443, 0.298, 0.200);      // #714c33
        return float3(0.490, 0.322, 0.208);                 // #7d5235
    }
    if (type == 3) { // grass
        if (top) return float3(0.443, 0.651, 0.322);        // #71a652
        if (left) return float3(0.247, 0.420, 0.220);       // #3f6b38
        if (right) return float3(0.337, 0.529, 0.259);      // #568742
        return float3(0.290, 0.471, 0.239);                 // #4a783d
    }

    // QR petal modules use the web's dark, scanner-friendly flat palette.
    if (variation < 0.25) return float3(0.561, 0.247, 0.353); // #8f3f5a
    if (variation < 0.50) return float3(0.647, 0.294, 0.400); // #a54b66
    if (variation < 0.75) return float3(0.722, 0.365, 0.467); // #b85d77
    return float3(0.769, 0.424, 0.518);                       // #c46c84
}

fragment float4 qrBlockFragment(RasterOut in [[stage_in]], constant Uniforms &uniforms [[buffer(0)]]) {
    int type = int(in.blockType + 0.5);
    float3 normal = normalize(in.normal);
    float seed = in.col * 17.3 + in.row * 31.1 + in.layer * 73.7;
    float variation = randomValue(seed);
    float3 sceneColor = webPalette(type, normal, variation);

    // At the top-down end, match the web canvas's scanner-safe flat QR
    // pixels. Blossom towers resolve to the dark-pink flat palette instead
    // of staying #ffd2dc on their top faces.
    if (type == 1) {
        float flatness = smoothstep(0.65, 0.98, uniforms.progress);
        sceneColor = mix(sceneColor, webPalette(4, normal, variation), flatness);
    }
    return float4(sceneColor, 1);
}

vertex SimpleOut qrSkyVertex(uint vertexID [[vertex_id]]) {
    const float2 points[3] = { float2(-1, -1), float2(3, -1), float2(-1, 3) };
    SimpleOut out;
    float2 p = points[vertexID];
    out.position = float4(p, 1, 1);
    out.uv = float2(p.x * 0.5 + 0.5, 0.5 - p.y * 0.5);
    return out;
}

fragment float4 qrSkyFragment(SimpleOut in [[stage_in]]) { return float4(0.969, 0.969, 0.969, 1); }

vertex SimpleOut qrShadowVertex(uint vertexID [[vertex_id]], constant Uniforms &uniforms [[buffer(0)]]) {
    SimpleOut out;
    const float2 quad[6] = { float2(-1,-1), float2(1,-1), float2(-1,1), float2(-1,1), float2(1,-1), float2(1,1) };
    float2 q = quad[vertexID];
    float halfGrid = uniforms.gridSize * blockSize * 0.5;
    float2 offset = float2(0.5, 0.5) * 0.48 * 0.35 * (1.0 - uniforms.progress);
    float3 p = float3(q.x * halfGrid * 0.85 + offset.x, -0.48, q.y * halfGrid * 0.85 + offset.y);
    float angleY = mix(isoAngleY, flatAngleY, uniforms.progress), angleX = mix(isoAngleX, flatAngleX, uniforms.progress);
    float cy = cos(angleY), sy = sin(angleY), cx = cos(angleX), sx = sin(angleX);
    float rotatedX = p.x * cy - p.z * sy, rotatedZ = p.x * sy + p.z * cy;
    float rotatedY = p.y * cx - rotatedZ * sx, depth = p.y * sx + rotatedZ * cx;
    float viewScale = mix(1.6, 2.1, uniforms.progress);
    float scaleX = viewScale / max(uniforms.aspectRatio, 1.0), scaleY = viewScale / max(1.0 / uniforms.aspectRatio, 1.0);
    out.position = float4(rotatedX * scaleX, (rotatedY + mix(-0.055, 0.0, uniforms.progress)) * scaleY, depth * 0.0 + 0.99, 1);
    out.uv = q * 0.5 + 0.5;
    return out;
}

fragment float4 qrShadowFragment(SimpleOut in [[stage_in]]) {
    float2 centered = in.uv * 2.0 - 1.0;
    float alpha = 0.08 * exp(-dot(centered, centered) * 2.5);
    return float4(float3(0.1, 0.12, 0.15) * alpha, alpha);
}
