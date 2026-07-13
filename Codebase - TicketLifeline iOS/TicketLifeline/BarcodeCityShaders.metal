#include <metal_stdlib>
using namespace metal;

struct BarcodeUniforms {
    float aspectRatio;
    float time;
    float flatness;
    float moduleCount;
    float4 padding;
};

struct BarcodeSegment {
    float start;
    float width;
    uint palette;
    uint kind;
};

struct CityRasterOut {
    float4 position [[position]];
    float3 normal;
    float3 world;
    float cityAmount;
    float kind;
    float palette;
};

struct RoadOut {
    float4 position [[position]];
    float cityAmount;
};

float cityRandom(float seed) {
    return fract(sin(seed) * 43758.5);
}

float3 cityPalette(uint palette, int face) {
    bool roof = face == 0;
    bool side = face == 4 || face == 5;
    if (palette == 0) {
        if (roof) return float3(0.294, 0.333, 0.388);
        if (side) return float3(0.216, 0.251, 0.302);
        return float3(0.122, 0.161, 0.216); // charcoal
    }
    if (palette == 1) {
        if (roof) return float3(0.184, 0.529, 0.600);
        if (side) return float3(0.078, 0.231, 0.286);
        return float3(0.086, 0.306, 0.388); // deep teal
    }
    if (palette == 2) {
        if (roof) return float3(0.357, 0.333, 0.839);
        if (side) return float3(0.118, 0.106, 0.294);
        return float3(0.192, 0.180, 0.506); // indigo
    }
    if (roof) return float3(0.760, 0.255, 0.050);
    if (side) return float3(0.263, 0.078, 0.027);
    return float3(0.486, 0.176, 0.071); // brick
}

void cityProject(
    float3 p,
    constant BarcodeUniforms &uniforms,
    thread float4 &position,
    thread float &depthValue
) {
    // In the city state the street is viewed at a shallow, 14° oblique angle
    // rather than the old near-front-on skyline. The top-down endpoint uses
    // the exact same x spans and bar depth as the scannable code.
    float cityYaw = 0.245;
    float cityPitch = -0.489;
    float flatYaw = 0.0;
    float flatPitch = -1.5707963;
    float yaw = mix(cityYaw, flatYaw, uniforms.flatness);
    float pitch = mix(cityPitch, flatPitch, uniforms.flatness);
    float cy = cos(yaw), sy = sin(yaw), cx = cos(pitch), sx = sin(pitch);
    float x = p.x * cy - p.z * sy;
    float z = p.x * sy + p.z * cy;
    float y = p.y * cx - z * sx;
    depthValue = p.y * sx + z * cx;

    float viewScale = mix(1.33, 1.18, uniforms.flatness);
    float scaleX = viewScale / max(uniforms.aspectRatio, 1.0);
    float scaleY = viewScale / max(1.0 / uniforms.aspectRatio, 1.0);
    float verticalOffset = mix(-0.075, 0.0, uniforms.flatness);
    position = float4(x * scaleX, (y + verticalOffset) * scaleY, depthValue * 0.10 + 0.5, 1);
}

vertex CityRasterOut barcodeCityBlockVertex(
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]],
    constant BarcodeUniforms &uniforms [[buffer(0)]],
    const device BarcodeSegment *segments [[buffer(1)]]
) {
    CityRasterOut out;
    BarcodeSegment segment = segments[instanceID];
    uint face = vertexID / 6;
    uint localIndex = vertexID % 6;
    const float2 quad[6] = {
        float2(0, 0), float2(1, 0), float2(0, 1),
        float2(0, 1), float2(1, 0), float2(1, 1)
    };
    float2 q = quad[localIndex];
    float fractionStart = segment.start / max(uniforms.moduleCount, 1.0);
    float fractionWidth = segment.width / max(uniforms.moduleCount, 1.0);
    float x0 = (fractionStart - 0.5) * 1.55;
    float xWidth = fractionWidth * 1.55;
    bool building = segment.kind == 1;
    float cityAmount = 1.0 - uniforms.flatness;

    // At rest, every run occupies the original barcode height. As it folds
    // down, dark runs become building lots and pale runs become cross streets.
    float flatDepth = 0.56;
    // Light runs become short pale cross streets at the building frontage;
    // they no longer stripe across the entire avenue in the foreground.
    float cityDepth = building ? 0.34 : 0.38;
    float zCenter = 0.28;
    float footprintDepth = mix(cityDepth, flatDepth, uniforms.flatness);
    float footprintCenter = mix(zCenter, 0.0, uniforms.flatness);
    float heightNoise = cityRandom(segment.start * 23.7 + segment.width * 17.1);
    float cityHeight = building
        ? 0.31 + min(0.30, fractionWidth * 6.0) + heightNoise * 0.23
        : 0.012;
    float height = mix(cityHeight, 0.006, uniforms.flatness);
    float3 p = 0;
    float3 normal = 0;

    if (face == 0) {
        p = float3(x0 + q.x * xWidth, height, footprintCenter + (q.y - 0.5) * footprintDepth);
        normal = float3(0, 1, 0);
    } else if (face == 1) {
        p = float3(x0 + q.x * xWidth, 0, footprintCenter + (0.5 - q.y) * footprintDepth);
        normal = float3(0, -1, 0);
    } else if (face == 2) {
        p = float3(x0 + q.x * xWidth, q.y * height, footprintCenter + footprintDepth * 0.5);
        normal = float3(0, 0, 1);
    } else if (face == 3) {
        p = float3(x0 + (1.0 - q.x) * xWidth, q.y * height, footprintCenter - footprintDepth * 0.5);
        normal = float3(0, 0, -1);
    } else if (face == 4) {
        p = float3(x0 + xWidth, q.y * height, footprintCenter + (q.x - 0.5) * footprintDepth);
        normal = float3(1, 0, 0);
    } else {
        p = float3(x0, q.y * height, footprintCenter + (0.5 - q.x) * footprintDepth);
        normal = float3(-1, 0, 0);
    }

    float depthValue = 0;
    cityProject(p, uniforms, out.position, depthValue);
    out.normal = normal;
    out.world = p;
    out.cityAmount = cityAmount;
    out.kind = float(segment.kind);
    out.palette = float(segment.palette);
    return out;
}

fragment float4 barcodeCityBlockFragment(CityRasterOut in [[stage_in]]) {
    bool building = in.kind > 0.5;
    if (!building) {
        // Light runs stay visibly cool-gray in both modes: quiet space in 2D,
        // then the pale alleys and cross streets in the city.
        float3 pale = mix(float3(0.925, 0.937, 0.949), float3(0.785, 0.808, 0.800), in.cityAmount);
        return float4(pale, 1);
    }

    int face = in.normal.y > 0.5 ? 0 : (abs(in.normal.x) > 0.5 ? 4 : 2);
    uint palette = uint(in.palette + 0.5);
    // In the flat endpoint every bar uses the deliberately low-luminance
    // facade color, never a bright roof highlight. As it rises, each face
    // resolves into the richer city shading.
    float3 color = mix(cityPalette(palette, 2), cityPalette(palette, face), in.cityAmount);

    // The flat surface is intentionally the same dark-but-colored facade
    // palette; each color has low enough luminance to retain Code 128 contrast.
    if (in.cityAmount > 0.35 && abs(in.normal.z) > 0.5 && in.world.y > 0.08) {
        float columns = floor((in.world.x + 1.0) * 40.0);
        float rows = floor(in.world.y * 46.0);
        float lit = step(0.79, cityRandom(columns * 17.0 + rows * 31.0 + in.palette * 7.0));
        float windowGrid = step(0.43, fract((in.world.x + 1.0) * 55.0)) * step(0.34, fract(in.world.y * 32.0));
        color = mix(color, float3(0.92, 0.78, 0.38), lit * windowGrid * in.cityAmount * 0.74);
    }
    return float4(color, 1);
}

vertex RoadOut barcodeCityRoadVertex(
    uint vertexID [[vertex_id]],
    constant BarcodeUniforms &uniforms [[buffer(0)]]) {
    RoadOut out;
    const float2 quad[6] = {
        float2(-1, -1), float2(1, -1), float2(-1, 1),
        float2(-1, 1), float2(1, -1), float2(1, 1)
    };
    float2 q = quad[vertexID];
    // A continuous avenue in front of the barcode-derived building row.
    float3 p = float3(q.x * 0.94, -0.014, -0.32 + q.y * 0.48);
    float depthValue = 0;
    cityProject(p, uniforms, out.position, depthValue);
    out.cityAmount = 1.0 - uniforms.flatness;
    return out;
}

fragment float4 barcodeCityRoadFragment(RoadOut in [[stage_in]]) {
    float3 flat = float3(0.970, 0.976, 0.984);
    float3 asphalt = float3(0.224, 0.259, 0.310);
    return float4(mix(flat, asphalt, in.cityAmount), 1);
}
