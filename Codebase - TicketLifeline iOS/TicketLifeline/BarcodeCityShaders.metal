#include <metal_stdlib>
using namespace metal;

struct BarcodeUniforms {
    float aspectRatio;
    float time;
    float flatness;
    float moduleCount;
    float cityStreetWidth;
    float cityHalfWidth;
    float2 padding;
};

struct BarcodeSegment {
    float flatCenter;
    float flatWidth;
    float cityCenter;
    float cityWidth;
    uint palette;
    uint kind;
};

struct CityProp {
    float x;
    float z;
    float streetWidth;
    uint kind;
    uint palette;
    uint direction;
};

struct CityRasterOut {
    float4 position [[position]];
    float3 normal;
    float3 world;
    float cityAmount;
    float kind;
    float palette;
    float streetCenter;
};

struct RoadOut {
    float4 position [[position]];
    float3 world;
    float cityAmount;
};

struct PropOut {
    float4 position [[position]];
    float3 normal;
    float visibility;
    float kind;
    float palette;
    float part;
};

float cityRandom(float seed) {
    return fract(sin(seed) * 43758.5);
}

float3 cityAsphalt() {
    return float3(0.525, 0.555, 0.590);
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
    // Keep the long 14° avenue view, with just enough downward pitch for the
    // connected cross streets, lane dashes, and junction props to remain
    // legible between the tall facades.
    float cityPitch = -0.575;
    float flatYaw = 0.0;
    float flatPitch = -1.5707963;
    float yaw = mix(cityYaw, flatYaw, uniforms.flatness);
    float pitch = mix(cityPitch, flatPitch, uniforms.flatness);
    float cy = cos(yaw), sy = sin(yaw), cx = cos(pitch), sx = sin(pitch);
    float x = p.x * cy - p.z * sy;
    float z = p.x * sy + p.z * cy;
    float y = p.y * cx - z * sx;
    depthValue = p.y * sx + z * cx;

    // City bounds are normalized before they reach this shader. The small
    // safety margin keeps the avenue and the first/last buildings in frame.
    float viewScaleX = mix(1.03, 1.18, uniforms.flatness);
    float viewScaleY = mix(1.45, 1.18, uniforms.flatness);
    float scaleX = viewScaleX / max(uniforms.aspectRatio, 1.0);
    float scaleY = viewScaleY / max(1.0 / uniforms.aspectRatio, 1.0);
    float verticalOffset = mix(-0.360, 0.0, uniforms.flatness);
    float horizontalOffset = mix(0.068, 0.0, uniforms.flatness);
    position = float4((x + horizontalOffset) * scaleX, (y + verticalOffset) * scaleY, depthValue * 0.10 + 0.5, 1);
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
    float xCenter = mix(segment.cityCenter, segment.flatCenter, uniforms.flatness);
    float xWidth = mix(segment.cityWidth, segment.flatWidth, uniforms.flatness);
    float x0 = xCenter - xWidth * 0.5;
    bool building = segment.kind == 1;
    bool street = segment.kind == 2;
    float cityAmount = 1.0 - uniforms.flatness;

    // Flat mode is the literal barcode. City mode folds those exact runs into
    // building lots and normalized, car-width cross streets.
    float flatDepth = 0.56;
    // Cross streets terminate at the rear edge of the avenue. Both surfaces
    // use the same height and material, preserving a clean T-junction without
    // projecting the cross street through or beyond the parallel road.
    float avenueRearEdge = 0.09 + uniforms.cityStreetWidth * 0.5;
    float crossStreetNearEdge = avenueRearEdge;
    float crossStreetFarEdge = 0.49;
    float crossStreetDepth = max(0.001, crossStreetFarEdge - crossStreetNearEdge);
    float cityDepth = building ? 0.34 : (street ? crossStreetDepth : 0.001);
    float zCenter = street ? (crossStreetNearEdge + crossStreetFarEdge) * 0.5 : 0.28;
    float footprintDepth = mix(cityDepth, flatDepth, uniforms.flatness);
    float footprintCenter = mix(zCenter, 0.0, uniforms.flatness);
    float heightNoise = cityRandom(segment.flatCenter * 237.0 + segment.flatWidth * 171.0);
    float cityHeight = building
        ? 0.31 + min(0.30, segment.flatWidth * 6.0) + heightNoise * 0.23
        : (street ? 0.012 : 0.001);
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
    out.streetCenter = segment.cityCenter;
    return out;
}

fragment float4 barcodeCityBlockFragment(
    CityRasterOut in [[stage_in]],
    constant BarcodeUniforms &uniforms [[buffer(0)]]) {
    if (in.kind < 0.5) {
        // Barcode quiet zones remain white margins once the city has formed.
        return float4(mix(float3(0.938, 0.945, 0.952), float3(1.0), in.cityAmount), 1);
    }
    if (in.kind > 1.5) {
        // Every light run uses the exact same city material as the parallel
        // avenue, so intersections read as one connected road network.
        float roadAmount = smoothstep(0.25, 0.90, in.cityAmount);
        float3 streetColor = mix(float3(0.938, 0.945, 0.952), cityAsphalt(), roadAmount);
        if (in.normal.y > 0.5) {
            float markingProgress = smoothstep(0.52, 0.92, in.cityAmount);
            float avenueRearEdge = 0.09 + uniforms.cityStreetWidth * 0.5;
            float lineHalfWidth = max(uniforms.cityStreetWidth * 0.13, 0.0022);
            float centerLine = 1.0 - smoothstep(
                lineHalfWidth,
                lineHalfWidth * 1.7,
                abs(in.world.x - in.streetCenter)
            );
            float dash = step(0.56, fract((in.world.z - avenueRearEdge) * 10.0));
            float clearJunction = step(avenueRearEdge + uniforms.cityStreetWidth * 0.72, in.world.z);
            // Keep the mouth pure asphalt so it visibly flows into the
            // avenue; the dotted centerline begins only after the junction.
            float marking = centerLine * dash * clearJunction * markingProgress;
            streetColor = mix(streetColor, float3(0.94, 0.95, 0.96), marking);
        }
        return float4(streetColor, 1);
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
    // The avenue shares both the cross-street material and surface elevation.
    // Their exact common edge forms one continuous T-junction surface.
    float cityAmount = 1.0 - uniforms.flatness;
    float streetWidth = uniforms.cityStreetWidth;
    float roadCenter = 0.09;
    // Keep the city-only road behind the still-flat barcode, then raise it to
    // the shared street surface only after the fold is well underway. This
    // prevents a nearly-white road from depth-masking a flashing horizontal
    // stripe across the barcode on either animation direction.
    float roadHeight = mix(0.0, 0.012, smoothstep(0.28, 0.82, cityAmount));
    float3 p = float3(q.x * uniforms.cityHalfWidth, roadHeight, roadCenter + q.y * streetWidth * 0.5);
    float depthValue = 0;
    cityProject(p, uniforms, out.position, depthValue);
    out.world = p;
    out.cityAmount = cityAmount;
    return out;
}

fragment float4 barcodeCityRoadFragment(
    RoadOut in [[stage_in]],
    constant BarcodeUniforms &uniforms [[buffer(0)]]) {
    // The avenue is city-only geometry. Discarding it at the flat endpoint is
    // essential: an opaque white road would otherwise depth-mask a horizontal
    // band through the exact Code 128 bars.
    if (in.cityAmount < 0.002) discard_fragment();
    float3 flat = float3(1.0);
    float3 road = cityAsphalt();
    // Small white dashes make the long parallel surface immediately read as
    // a street while keeping the barcode endpoint completely clean.
    float dashProgress = smoothstep(0.52, 0.92, in.cityAmount);
    float roadCenter = 0.09;
    float lineHalfWidth = max(uniforms.cityStreetWidth * 0.13, 0.0022);
    float centerLine = 1.0 - smoothstep(lineHalfWidth, lineHalfWidth * 1.7, abs(in.world.z - roadCenter));
    float dash = step(0.56, fract((in.world.x + uniforms.cityHalfWidth) * 10.0));
    // A single uninterrupted dash rhythm keeps the long avenue readable even
    // where the barcode-derived side streets are very densely packed.
    float roadMarking = centerLine * dash * dashProgress;
    float3 markedRoad = mix(road, float3(0.96, 0.97, 0.98), roadMarking);
    return float4(mix(flat, markedRoad, in.cityAmount), 1);
}

void cityCuboid(
    uint face,
    float2 q,
    float3 center,
    float3 size,
    thread float3 &position,
    thread float3 &normal
) {
    float3 halfSize = size * 0.5;
    if (face == 0) {
        position = center + float3((q.x - 0.5) * size.x, halfSize.y, (q.y - 0.5) * size.z);
        normal = float3(0, 1, 0);
    } else if (face == 1) {
        position = center + float3((q.x - 0.5) * size.x, -halfSize.y, (0.5 - q.y) * size.z);
        normal = float3(0, -1, 0);
    } else if (face == 2) {
        position = center + float3((q.x - 0.5) * size.x, (q.y - 0.5) * size.y, halfSize.z);
        normal = float3(0, 0, 1);
    } else if (face == 3) {
        position = center + float3((0.5 - q.x) * size.x, (q.y - 0.5) * size.y, -halfSize.z);
        normal = float3(0, 0, -1);
    } else if (face == 4) {
        position = center + float3(halfSize.x, (q.y - 0.5) * size.y, (q.x - 0.5) * size.z);
        normal = float3(1, 0, 0);
    } else {
        position = center + float3(-halfSize.x, (q.y - 0.5) * size.y, (0.5 - q.x) * size.z);
        normal = float3(-1, 0, 0);
    }
}

float3 cityCarColor(uint palette) {
    if (palette == 0) return float3(0.92, 0.29, 0.19); // coral red
    if (palette == 1) return float3(0.16, 0.67, 0.62); // mint teal
    if (palette == 2) return float3(0.28, 0.43, 0.93); // cobalt blue
    return float3(0.95, 0.53, 0.14); // warm orange
}

vertex PropOut barcodeCityPropsVertex(
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]],
    constant BarcodeUniforms &uniforms [[buffer(0)]],
    const device CityProp *props [[buffer(1)]]) {
    PropOut out;
    CityProp prop = props[instanceID];
    uint part = vertexID / 36;
    uint face = (vertexID % 36) / 6;
    uint localIndex = vertexID % 6;
    const float2 quad[6] = {
        float2(0, 0), float2(1, 0), float2(0, 1),
        float2(0, 1), float2(1, 0), float2(1, 1)
    };
    float cityAmount = 1.0 - uniforms.flatness;
    float visibility = smoothstep(0.38, 0.90, cityAmount);
    float lane = max(prop.streetWidth, 0.018);
    bool avenueDirection = prop.direction == 1;
    float3 center;
    float3 size;

    if (prop.kind == 0) {
        // Two low, simple cuboids give each car a readable body and roof.
        if (part == 0) {
            center = float3(prop.x, 0.029, prop.z);
            size = float3(lane * 0.64, 0.034, lane * 1.46);
        } else if (part == 1) {
            center = float3(
                prop.x + (avenueDirection ? lane * 0.03 : 0.0),
                0.062,
                prop.z + (avenueDirection ? 0.0 : lane * 0.03)
            );
            size = float3(lane * 0.46, 0.024, lane * 0.72);
        } else {
            center = float3(prop.x, 0, prop.z);
            size = float3(0);
        }
        if (avenueDirection) size = float3(size.z, size.y, size.x);
    } else {
        // A real street-light silhouette: pole, mast arm, short hanging rod,
        // and a yellow signal box suspended from the arm.
        if (part == 0) {
            center = avenueDirection
                ? float3(prop.x, 0.080, prop.z + lane * 0.32)
                : float3(prop.x + lane * 0.32, 0.080, prop.z);
            size = float3(lane * 0.13, 0.136, lane * 0.13);
        } else if (part == 1) {
            center = avenueDirection
                ? float3(prop.x, 0.143, prop.z + lane * 0.14)
                : float3(prop.x + lane * 0.14, 0.143, prop.z);
            size = avenueDirection
                ? float3(lane * 0.12, 0.016, lane * 0.46)
                : float3(lane * 0.46, 0.016, lane * 0.12);
        } else if (part == 2) {
            center = float3(prop.x, 0.117, prop.z);
            size = float3(lane * 0.08, 0.052, lane * 0.08);
        } else {
            center = float3(prop.x, 0.085, prop.z);
            size = avenueDirection
                ? float3(lane * 0.18, 0.032, lane * 0.34)
                : float3(lane * 0.34, 0.032, lane * 0.18);
        }
    }

    float3 p = 0;
    float3 normal = 0;
    cityCuboid(face, quad[localIndex], center, size * visibility, p, normal);
    float depthValue = 0;
    cityProject(p, uniforms, out.position, depthValue);
    out.normal = normal;
    out.visibility = visibility;
    out.kind = float(prop.kind);
    out.palette = float(prop.palette);
    out.part = float(part);
    return out;
}

fragment float4 barcodeCityPropsFragment(PropOut in [[stage_in]]) {
    if (in.visibility < 0.01) discard_fragment();
    if (in.kind > 0.5) {
        float3 color = in.part > 2.5 ? float3(1.0, 0.77, 0.16) : float3(0.16, 0.19, 0.23);
        if (in.part > 2.5 && in.normal.y > 0.5) color = float3(1.0, 0.87, 0.30);
        return float4(color, 1);
    }

    if (in.part > 1.5) discard_fragment();

    float3 color = cityCarColor(uint(in.palette + 0.5));
    if (in.normal.y > 0.5 || in.part > 0.5) color = mix(color, float3(1.0), 0.18);
    if (in.normal.x < -0.5 || in.normal.z < -0.5) color *= 0.72;
    return float4(color, 1);
}
