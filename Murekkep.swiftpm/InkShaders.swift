import Foundation

/// Metal source, compiled at runtime with `makeLibrary(source:)` so the project also builds in Swift Playgrounds.
enum InkShaders {
    static let source = #"""
#include <metal_stdlib>
using namespace metal;

// MARK: shared structs (must match InkRenderer.swift)

struct FrameUniforms {
    float2 drawableSize;   // pixels
    float2 viewOffset;     // pixels: doc point P maps to P * scale + viewOffset
    float  scale;          // pixels per document point
    float  pixelSize;      // document points per pixel
    float  time;           // seconds since renderer start
    float  dryDuration;    // seconds until wet ink is dry
    float  waveTime;       // clock for animations (frozen when animation is off)
    float  coolDuration;   // seconds until lava has cooled into embers
};

struct SegUniforms {
    float2 pageOrigin;     // document space
    uint   pointOffset;
    uint   orderOffset;
    float  depthStep;
    float  depthOnly;      // 1: write depth with a transparent color (the pass before a blend-once pass)
    float2 pad1;
};

struct QuadUniforms {
    float4 rect;           // document space x, y, w, h
    float4 uvRect;         // u0, v0, u1, v1
    float2 pageOrigin;
    float2 pageSize;
    uint   style;          // paper style
    float  shadowRadius;
    float2 pad;
};

struct StrokeGPU {
    float4 color;
    uint   brush;
    float  birth;
    float  width;
    float  seed;
};

struct BladeGPU {
    float2 base;           // page-local
    float  height;
    float  width;
    float  lean;
    float  phase;
    float  birth;          // when it starts to grow (renderer clock)
    float  depth;          // 0 front .. 1 back inside the stroke
    float4 color;
    uint   stroke;
    uint   kind;           // 0 blade, 1 flower stem
    float  stiffness;
    float  pad;
};

struct FlowerGPU {
    uint   stem;
    float  radius;
    float  bloom;          // when the bud starts to open (renderer clock)
    float  petals;
    float4 petal;
    float4 core;
    float  spin;
    float  style;
    float2 pad;
};

constant uint BRUSH_PEN = 0;
constant uint BRUSH_WET = 1;
constant uint BRUSH_WAVE = 2;
constant uint BRUSH_PENCIL = 4;
constant uint BRUSH_CALLIGRAPHY = 5;
constant uint BRUSH_WATERCOLOR = 6;
constant uint BRUSH_NEON = 7;
constant uint BRUSH_RAINBOW = 8;
constant uint BRUSH_GLITTER = 9;
constant uint BRUSH_GRASS = 10;
constant uint BRUSH_SEA = 11;
constant uint BRUSH_LAVA = 12;
constant uint BRUSH_FOUNTAIN = 13;
constant uint BRUSH_GOLD = 14;
constant uint BRUSH_CHROME = 15;
constant uint BRUSH_ICE = 16;
constant uint BRUSH_JELLY = 17;
constant uint BRUSH_GALAXY = 18;
constant uint BRUSH_LIGHTNING = 19;
constant uint BRUSH_PEARL = 20;
constant uint BRUSH_IMPASTO = 21;

constant float3 kLight = float3(-0.41941, -0.57919, 0.69902);
constant float3 kHalf  = float3(-0.22752, -0.31420, 0.92169);

struct RibbonVertexGPU {
    float2 center;         // point on the stroke's centerline (page-local)
    float2 offset;         // unit direction to this vertex: normal (body) or radial (caps); 0 at cap centers
    float2 tangent;        // drawing direction
    float  r;              // radius
    float  u;              // signed across coordinate: +1 left edge, -1 right edge, +1 cap rim, 0 center
    float  side;           // across direction: +1 left edge, -1 right edge, cos(angle) on cap rims
    float  arc;            // distance along the stroke (cap rims: the end's value; the shader extends it)
    float  ink;            // pooling / graphite density
    uint   stroke;
};

struct RibbonOut {
    float4 position [[position]];
    float2 local;
    float2 n2;
    float2 tangent;
    float  u;
    float  side;
    float  r;
    float  arc;
    float  ink;
    float  h      [[flat]];
    float  blur;
    uint   stroke [[flat]];
    float  zBase  [[flat]];
};

struct StrokeFrag {
    float  r;
    float  d;
    float  x;
    float2 n2;
    float  sq;
};

static StrokeFrag strokeFrag(RibbonOut in) {
    StrokeFrag f;
    f.r = max(in.r, 1e-4);
    f.d = abs(in.u) * f.r;
    f.x = clamp(abs(in.u), 0.0, 1.0);
    float nl = length(in.n2);
    f.n2 = (nl > 1e-4 ? in.n2 / nl : float2(0.0)) * (in.u < 0.0 ? -1.0 : 1.0);
    f.sq = sqrt(saturate(1.0 - f.x * f.x));
    return f;
}

struct InkOut {
    float4 color [[color(0)]];
    float  depth [[depth(greater)]];
};

struct DecorOut {
    float4 color [[color(0)]];
    float  depth [[depth(any)]];
};

struct QuadOut {
    float4 position [[position]];
    float2 uv;
    float2 local;
};

static float2 docToNDC(float2 doc, constant FrameUniforms& fu) {
    float2 px = doc * fu.scale + fu.viewOffset;
    return float2(px.x / fu.drawableSize.x * 2.0 - 1.0, 1.0 - px.y / fu.drawableSize.y * 2.0);
}

static float wetness(constant FrameUniforms& fu, float birth) {
    float age = fu.time - birth;
    return 1.0 - smoothstep(0.0, max(fu.dryDuration, 0.01), age);
}

static float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

static float2 hash22(float2 p) {
    float2 q = float2(dot(p, float2(127.1, 311.7)), dot(p, float2(269.5, 183.3)));
    return fract(sin(q) * 43758.5453);
}

static float valueNoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    float a = hash21(i);
    float b = hash21(i + float2(1.0, 0.0));
    float c = hash21(i + float2(0.0, 1.0));
    float d = hash21(i + float2(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

static float fbm(float2 p) {
    float v = 0.0;
    float a = 0.5;
    for (int i = 0; i < 4; i++) {
        v += a * valueNoise(p);
        p = float2(0.8 * p.x - 0.6 * p.y, 0.6 * p.x + 0.8 * p.y) * 2.03 + float2(17.1, 9.2);
        a *= 0.5;
    }
    return v;
}

// Voronoi cell border distance and cell ID hash: x = edge distance (0 on cracks), y = center distance, z = cell hash
static float3 voronoiDetail(float2 p, float drift) {
    float2 i = floor(p);
    float2 f = fract(p);
    float d1 = 8.0;
    float d2 = 8.0;
    float id = 0.0;
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            float2 g = float2(float(x), float(y));
            float2 h = hash22(i + g);
            float2 o = drift > 0.0 ? (0.5 + 0.42 * sin(drift + 6.2831853 * h)) : (0.15 + 0.7 * h);
            float d = length(g + o - f);
            if (d < d1) {
                d2 = d1;
                d1 = d;
                id = h.x;
            } else if (d < d2) {
                d2 = d;
            }
        }
    }
    return float3(d2 - d1, d1, id);
}

static float cellEdge(float2 p) {
    return voronoiDetail(p, 0.0).x;
}

static float waterCells(float2 p, float t) {
    return voronoiDetail(p, t).x;
}

// Studio environment for metals & water reflection
static float3 envColor(float3 R, float3 tint) {
    float y = -R.y;
    float3 sky = mix(float3(0.86, 0.93, 1.0), float3(0.32, 0.56, 0.92), saturate(y * 1.4));
    float3 ground = mix(float3(0.42, 0.36, 0.30), float3(0.08, 0.08, 0.10), saturate(-y * 1.8));
    float3 c = y > 0.0 ? sky : ground;
    c = mix(c, float3(1.0), exp(-abs(y) * 20.0) * 0.88);
    return c * tint;
}

static float3 reflectView(float3 N) {
    return float3(2.0 * N.z * N.x, 2.0 * N.z * N.y, 2.0 * N.z * N.z - 1.0);
}

static float3 rgb2hsv(float3 c) {
    float4 K = float4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    float4 p = mix(float4(c.bg, K.wz), float4(c.gb, K.xy), step(c.b, c.g));
    float4 q = mix(float4(p.xyw, c.r), float4(c.r, p.yzx), step(p.x, c.r));
    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return float3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

static float3 hsv2rgb(float3 c) {
    float3 p = abs(fract(c.xxx + float3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
    return c.z * mix(float3(1.0), saturate(p - 1.0), c.y);
}

// MARK: ribbon vertex shaders

static float glowExtra(uint brush, float r) {
    if (brush == BRUSH_NEON) {
        return 2.2 * r;
    } else if (brush == BRUSH_LIGHTNING) {
        return 2.0 * r;
    } else if (brush == BRUSH_LAVA) {
        return 1.4 * r;
    } else if (brush == BRUSH_SEA || brush == BRUSH_WAVE) {
        return 0.16 * r;
    } else if (brush == BRUSH_WATERCOLOR) {
        return 0.22 * r;
    } else if (brush == BRUSH_JELLY) {
        return 0.12 * r;
    }
    return 0.0;
}

static float shadowHeight(constant FrameUniforms& fu, StrokeGPU s) {
    uint b = s.brush;
    if (b == BRUSH_WAVE || b == BRUSH_PEARL) {
        return 1.0;
    } else if (b == BRUSH_WET) {
        return wetness(fu, s.birth);
    } else if (b == BRUSH_GRASS || b == BRUSH_IMPASTO) {
        return 0.95;
    } else if (b == BRUSH_CHROME) {
        return 0.90;
    } else if (b == BRUSH_SEA || b == BRUSH_JELLY) {
        return 0.85;
    } else if (b == BRUSH_GOLD) {
        return 0.80;
    } else if (b == BRUSH_LAVA || b == BRUSH_GALAXY) {
        return 0.75;
    } else if (b == BRUSH_FOUNTAIN) {
        return 0.65;
    } else if (b == BRUSH_ICE) {
        return 0.55;
    } else if (b == BRUSH_GLITTER) {
        return 0.45;
    }
    return 0.0;
}

static RibbonOut makeRibbon(RibbonVertexGPU v, float extra, float2 shift,
                            constant FrameUniforms& fu, constant SegUniforms& su) {
    RibbonOut o;
    float r = max(v.r, 1e-4);
    float ext = r + extra + 2.0 * fu.pixelSize;
    float2 p = v.center + shift + v.offset * ext;
    float order = float(su.orderOffset + v.stroke);
    o.zBase = 1.0 - (order + 1.0) * su.depthStep;
    o.position = float4(docToNDC(su.pageOrigin + p, fu), o.zBase, 1.0);
    o.local = p;
    o.n2 = v.u < 0.0 ? -v.offset : v.offset;
    o.tangent = v.tangent;
    o.u = v.u * ext / r;
    o.side = v.side * ext / r;
    o.r = r;
    o.arc = v.arc + dot(v.offset, v.tangent) * ext;
    o.ink = v.ink;
    o.stroke = v.stroke;
    o.h = 0.0;
    o.blur = 0.0;
    return o;
}

vertex RibbonOut ribbon_vertex(uint vid [[vertex_id]],
                               constant FrameUniforms& fu [[buffer(0)]],
                               constant SegUniforms& su [[buffer(1)]],
                               const device RibbonVertexGPU* verts [[buffer(2)]],
                               const device StrokeGPU* strokes [[buffer(3)]])
{
    RibbonVertexGPU v = verts[vid];
    return makeRibbon(v, glowExtra(strokes[v.stroke].brush, v.r), float2(0.0), fu, su);
}

vertex RibbonOut ribbon_shadow_vertex(uint vid [[vertex_id]],
                                      constant FrameUniforms& fu [[buffer(0)]],
                                      constant SegUniforms& su [[buffer(1)]],
                                      const device RibbonVertexGPU* verts [[buffer(2)]],
                                      const device StrokeGPU* strokes [[buffer(3)]])
{
    RibbonVertexGPU v = verts[vid];
    float h = shadowHeight(fu, strokes[v.stroke]);
    float blur = 0.55 * v.r + fu.pixelSize;
    RibbonOut o = makeRibbon(v, blur, float2(0.30, 0.42) * (v.r * h), fu, su);
    o.zBase = 1.0 - float(su.orderOffset + 1) * su.depthStep;
    o.position.z = o.zBase;
    o.h = h;
    o.blur = blur;
    if (h < 0.002) {
        o.position = float4(-2.0, -2.0, 0.5, 1.0);
    }
    return o;
}

// MARK: shading

static float waveField(float2 P, float t, thread float2& grad) {
    const float2 d0 = float2(0.97014, 0.24254);
    const float2 d1 = float2(-0.33035, 0.94386);
    const float2 d2 = float2(0.80000, -0.60000);
    const float2 d3 = float2(-0.97619, -0.21693);
    const float2 d4 = float2(0.44721, 0.89442);
    const float k0 = 0.18;
    const float k1 = 0.29;
    const float k2 = 0.48;
    const float k3 = 0.76;
    const float k4 = 1.15;

    float s0 = dot(P, d0) * k0 - 1.45 * t;
    float s1 = dot(P, d1) * k1 - 2.05 * t + 1.7;
    float s2 = dot(P, d2) * k2 - 2.85 * t + 4.1;
    float s3 = dot(P, d3) * k3 - 3.70 * t + 2.3;
    float s4 = dot(P, d4) * k4 - 4.60 * t + 5.0;

    float u0 = max(0.5 + 0.5 * sin(s0), 1e-3);
    float u1 = max(0.5 + 0.5 * sin(s1), 1e-3);
    float u2 = max(0.5 + 0.5 * sin(s2), 1e-3);
    float u3 = max(0.5 + 0.5 * sin(s3), 1e-3);
    float u4 = max(0.5 + 0.5 * sin(s4), 1e-3);

    float W = 0.52 * powr(u0, 1.7)
            + 0.36 * powr(u1, 1.7)
            + 0.24 * powr(u2, 1.8)
            + 0.15 * powr(u3, 1.9)
            + 0.09 * powr(u4, 2.0);

    grad = d0 * (0.52 * 0.85 * k0 * powr(u0, 0.7) * cos(s0))
         + d1 * (0.36 * 0.85 * k1 * powr(u1, 0.7) * cos(s1))
         + d2 * (0.24 * 0.90 * k2 * powr(u2, 0.8) * cos(s2))
         + d3 * (0.15 * 0.95 * k3 * powr(u3, 0.9) * cos(s3))
         + d4 * (0.09 * 1.00 * k4 * powr(u4, 1.0) * cos(s4));
    return (W - 0.55) * 1.35;
}

static float3 shadeWet(float3 base, float x, float2 n2, float sq, float ink, float w) {
    float A = mix(0.10, 0.56, w) * mix(0.82, 1.45, ink);
    float slope = min(A * x / max(sq, 0.07), 5.5);
    float rimDx = (x - 0.82) / 0.12;
    float rimTension = exp(-rimDx * rimDx) * 0.22 * w;
    float3 N = normalize(float3(n2 * (slope + rimTension), 1.0));

    float lum = dot(base, float3(0.3, 0.59, 0.11));
    float3 richBase = saturate(float3(lum) + (base - float3(lum)) * mix(1.08, 1.38, w));
    float3 col = richBase * mix(0.96, 0.64, w * (0.55 + 0.45 * sq));

    float ring = (1.0 - 0.45 * w) * 0.36 * smoothstep(0.55, 0.96, x);
    float poolDark = smoothstep(0.45, 1.0, ink) * 0.28 * sq;
    col *= (1.0 - ring - poolDark);

    float3 hsv = rgb2hsv(base);
    float3 sheenTint = hsv2rgb(float3(fract(hsv.x + 0.42), 0.85, 1.0));
    float sheenFactor = smoothstep(0.45, 0.95, ink) * powr(saturate(dot(N, kHalf)), 10.0) * smoothstep(0.25, 0.85, x);
    col = mix(col, sheenTint, sheenFactor * mix(0.22, 0.45, w));

    float ndl = dot(N, kLight);
    col *= 1.0 + 0.55 * (ndl - kLight.z);
    col *= mix(1.0, 0.50 + 0.50 * N.z, w);

    float fresnel = powr(saturate(1.0 - N.z), 3.0) * w;
    col = mix(col, envColor(reflectView(N), float3(1.0)), fresnel * 0.32);

    float nh = saturate(dot(N, kHalf));
    float spec = powr(nh, mix(36.0, 140.0, w)) * mix(0.10, 1.45, w)
               + powr(nh, 18.0) * 0.14 * w;

    float rx = 2.0 * N.z * N.x;
    float ry = 2.0 * N.z * N.y;
    float win = smoothstep(0.04, 0.18, -rx) * (1.0 - smoothstep(0.28, 0.46, -rx))
              * smoothstep(0.06, 0.20, -ry) * (1.0 - smoothstep(0.34, 0.54, -ry));
    float bounce = smoothstep(0.22, 0.58, rx * 0.6 + ry * 0.8) * 0.22 * w;
    return saturate(col + float3(spec + win * 0.85 * w + bounce));
}

static float3 shadeWave(float3 base, float x, float2 n2, float sq, float2 P, float t) {
    float2 g;
    float Wn = waveField(P, t, g);
    float slope = min(0.38 * x / max(sq, 0.12), 3.4);
    float ws = 0.85 * sq;
    float3 N = normalize(float3(n2 * slope - g * ws, 1.0));

    float3 deep = base * float3(0.18, 0.34, 0.62);
    float3 midWater = mix(base, float3(0.06, 0.68, 0.78), 0.55);
    float3 shallow = mix(base, float3(0.38, 0.95, 0.88), 0.78);
    float depth = saturate(powr(max(sq, 1e-4), 0.75) * (0.82 + 0.18 * Wn));
    float3 col = depth < 0.5 ? mix(shallow, midWater, depth * 2.0) : mix(midWater, deep, (depth - 0.5) * 2.0);

    float sss = saturate(Wn * 0.8 + 0.2) * (1.0 - 0.5 * depth);
    col += float3(0.08, 0.85, 0.78) * sss * 0.28;

    float2 cUV = P * 0.16 + g * 0.8;
    float e1 = waterCells(cUV, t * 1.4);
    float e2 = waterCells(cUV * 1.65 + float2(4.2, -3.1), -t * 1.8 + 1.5);
    float caust = powr(saturate(1.0 - e1 * 4.5), 2.2) * 0.75
                + powr(saturate(1.0 - e2 * 5.0), 2.2) * 0.45;
    col += float3(0.65, 0.98, 1.0) * caust * sq * (1.0 - 0.5 * depth) * 0.85;

    float fresnel = powr(saturate(1.0 - N.z), 2.8);
    col = mix(col, envColor(reflectView(N), float3(0.88, 0.96, 1.0)), fresnel * 0.42);

    float foamCell = waterCells(P * 0.38 - g * 1.2, t * 2.1);
    float bubbleWeb = 1.0 - smoothstep(0.0, 0.14, foamCell);
    float crestBreak = smoothstep(0.28, 0.68, Wn + 0.18 * valueNoise(P * 0.3 + t));
    float shoreWave = smoothstep(0.66, 0.86, x + 0.08 * sin(P.x * 0.25 + P.y * 0.22 - t * 2.2) + 0.06 * Wn);
    float foamMask = saturate(crestBreak * (0.45 + 0.55 * bubbleWeb) + shoreWave * (0.50 + 0.50 * bubbleWeb));
    col = mix(col, float3(0.97, 0.995, 1.0), foamMask * 0.92);

    float nh = saturate(dot(N, kHalf));
    float spec = powr(nh, 180.0) * 1.55 * (1.0 - foamMask * 0.5) + powr(nh, 28.0) * 0.16;
    return saturate(col + float3(spec));
}

static void curlingSeaWave(float2 q, float2 dir, float scale, float amp, float L, float t, float seed,
                           thread float& h, thread float2& g, thread float& breaker) {
    float k = 6.2831853 / (L * scale);
    float w = 2.6 / sqrt(scale);
    float rawPhase = dot(dir, q) * k - w * t + seed;
    float warpedPhase = rawPhase + 0.42 * sin(rawPhase);
    float sn = max(0.5 + 0.5 * sin(warpedPhase), 1e-3);
    float waveH = powr(sn, 2.1);
    h += amp * waveH;

    float dWarped = 1.0 + 0.42 * cos(rawPhase);
    float dWave = amp * 2.1 * powr(sn, 1.1) * 0.5 * cos(warpedPhase) * dWarped * k;
    g += dWave * dir;

    float frontFace = saturate(cos(rawPhase - 0.55));
    breaker += amp * powr(max(waveH, 1e-4), 2.2) * (0.65 + 0.35 * frontFace);
}

static float3 tubeLight(float3 col, float2 n2, float x, float sq, float gloss, float strength) {
    float3 N = normalize(float3(n2 * (x / max(sq, 0.15)) * strength, 1.0));
    float ndl = dot(N, kLight);
    col *= 1.0 + 0.48 * (ndl - kLight.z);
    float spec = powr(saturate(dot(N, kHalf)), 48.0) * gloss;
    return saturate(col + float3(spec));
}

// MARK: segment fragment shaders

fragment InkOut ink_fragment(RibbonOut in [[stage_in]],
                             constant FrameUniforms& fu [[buffer(0)]],
                             constant SegUniforms& su [[buffer(1)]],
                             const device StrokeGPU* strokes [[buffer(3)]])
{
    StrokeFrag sf = strokeFrag(in);
    float r = sf.r;
    float d = sf.d;
    float x = sf.x;
    float2 n2 = sf.n2;
    float sq = sf.sq;
    StrokeGPU s = strokes[in.stroke];
    float px = fu.pixelSize;
    float ink = in.ink;
    float arc = in.arc;
    float2 P = in.local;
    float tl = length(in.tangent);
    float2 tdir = tl > 1e-4 ? in.tangent / tl : float2(1.0, 0.0);
    float across = in.side;
    float sacross = clamp(across, -1.0, 1.0);

    float3 col = s.color.rgb;
    float alpha;
    float alphaScale = 1.0;

    if (s.brush == BRUSH_SEA) {
        float t = fu.waveTime;
        float L = max(r * 2.35, 6.5);
        float curveLag = sacross * sacross * r * 0.52;
        float2 wq = float2(arc - curveLag, sacross * r);

        float hsum = 0.0;
        float2 grad = float2(0.0);
        float breaker = 0.0;
        curlingSeaWave(wq, float2(1.0, 0.0),    1.00, 1.00, L, t * 1.15, s.seed * 3.1,       hsum, grad, breaker);
        curlingSeaWave(wq, float2(0.93, 0.36),  0.58, 0.52, L, t * 1.25, s.seed * 4.8 + 1.3, hsum, grad, breaker);
        curlingSeaWave(wq, float2(0.92, -0.39), 0.38, 0.36, L, t * 1.35, s.seed * 6.5 + 2.9, hsum, grad, breaker);
        curlingSeaWave(wq, float2(0.98, 0.18),  0.24, 0.22, L, t * 1.50, s.seed * 8.1 + 0.7, hsum, grad, breaker);

        float hN = hsum / 2.10;
        float breakN = breaker / 1.65;

        float shoreSurge = sin(arc / L * 6.2831853 - t * 2.6 + s.seed * 5.0 + step(0.0, sacross) * 1.5);
        float shoreNoise = valueNoise(float2(arc / max(r * 0.7, 1.2) - t * 0.9, sacross * 3.0) + s.seed * 9.0) - 0.5;
        float rDynamic = r * (0.95 + 0.09 * hN + 0.06 * shoreSurge + 0.04 * shoreNoise);
        float cov = clamp((rDynamic - d) / (px * 1.2) + 0.5, 0.0, 1.0);
        if (cov <= 0.0) {
            discard_fragment();
        }

        float xDyn = clamp(d / max(rDynamic, 1e-4), 0.0, 1.0);
        float sqDyn = sqrt(saturate(1.0 - xDyn * xDyn));

        float2 slope = grad * (L * 0.085);
        float2 nLeft = float2(-tdir.y, tdir.x);
        float3 N = normalize(float3(-(slope.x * tdir + slope.y * nLeft) + n2 * (xDyn / max(sqDyn, 0.18)) * 0.42, 1.0));

        float3 base = s.color.rgb;
        float3 deep = base * float3(0.20, 0.38, 0.68);
        float3 midSea = mix(base, float3(0.05, 0.66, 0.78), 0.58);
        float3 shallow = mix(base, float3(0.36, 0.96, 0.88), 0.78);
        float depth = smoothstep(0.15, 0.92, sqDyn * (0.85 + 0.15 * hN));
        float3 water = depth < 0.5 ? mix(shallow, midSea, depth * 2.0) : mix(midSea, deep, (depth - 0.5) * 2.0);

        float sss = smoothstep(0.35, 0.90, hN) * (1.0 - 0.35 * depth);
        water += float3(0.12, 0.92, 0.84) * sss * 0.34;
        water *= (0.80 + 0.38 * hN) * (1.0 + 0.65 * (dot(N, kLight) - kLight.z));

        float cs = max(max(r * 0.95, 2.2), px * 12.0);
        float2 cq = (wq + float2(-t * r * 1.05, 0.0)) / cs + slope * 0.75 + s.seed * 11.0;
        float e1 = waterCells(cq, t * 1.45);
        float e2 = waterCells(cq * 1.75 + float2(3.1 - t * 0.35, 7.7), t * 1.85 + 2.0);
        float pxc = px / cs;
        float caust = (1.0 - smoothstep(0.0, 0.08 + pxc * 1.4, e1)) * 0.80
                    + (1.0 - smoothstep(0.0, 0.06 + pxc * 2.2, e2)) * 0.45;
        water += float3(0.62, 0.96, 1.0) * caust * mix(0.85, 0.22, depth);

        float fresnel = powr(saturate(1.0 - N.z), 2.6);
        water = mix(water, envColor(reflectView(N), float3(0.88, 0.96, 1.0)), fresnel * 0.36);

        float2 foamUV = float2(arc / max(r * 0.45, 1.0) - t * 1.6, sacross * 3.4) + slope * 0.8;
        float3 vFoam = voronoiDetail(foamUV * 1.8, t * 2.2);
        float foamWeb = 1.0 - smoothstep(0.0, 0.16, vFoam.x);
        float fn = fbm(foamUV * 0.7 + s.seed * 7.0);

        float whitecap = smoothstep(0.42, 0.78, breakN + (fn - 0.5) * 0.28);
        float trailingLace = smoothstep(0.22, 0.58, breakN) * foamWeb * smoothstep(0.38, 0.68, fn);
        float shoreZone = smoothstep(0.70, 0.94, xDyn + 0.10 * shoreSurge + 0.12 * (fn - 0.5));
        float shoreFoam = shoreZone * (0.45 + 0.55 * foamWeb);

        float foam = saturate(whitecap * (0.65 + 0.35 * foamWeb) + trailingLace * 0.75 + shoreFoam * 0.90);
        float3 foamColor = float3(0.96, 0.99, 1.0) * (0.88 + 0.14 * dot(N, kLight));
        water = mix(water, foamColor, foam);

        float nh = saturate(dot(N, kHalf));
        float glint = powr(nh, 140.0) * 1.35 * (1.0 - foam * 0.65) + powr(nh, 28.0) * 0.18;
        col = saturate(water + float3(glint));
        alpha = cov * s.color.a;
    } else if (s.brush == BRUSH_LAVA) {
        // Cools from where the pen started: each point starts cooling a little after the one before,
        // at drawing speed (380 pt/s, as InkRenderer.lavaCoolSpeed), counted from when the pen lifted.
        float age = fu.time - (s.birth + max(arc, 0.0) / 380.0);
        float heat = 1.0 - smoothstep(0.0, max(fu.coolDuration, 0.5), age);

        float edgeJag = (valueNoise(P * 0.85 + s.seed * 19.0) - 0.5) * r * 0.10 * (1.0 - 0.5 * heat);
        float rLava = r + edgeJag;
        float body = clamp((rLava - d) / px + 0.5, 0.0, 1.0);
        float glowA = (1.0 - body) * (0.35 + 0.65 * heat) * 0.16 * exp(-1.7 * max(d - rLava, 0.0) / max(r, 0.5));
        if (body <= 0.0 && glowA <= 0.002) {
            discard_fragment();
        }

        float flowShift = mix(s.birth * 0.45 + fu.coolDuration * 0.25, fu.waveTime * 0.55, heat * heat);
        float2 flowUV = float2(arc / max(r, 0.5) * 0.60 - flowShift, sacross * 1.35) + s.seed * 13.0;

        float3 plate1 = voronoiDetail(flowUV * 1.45, 0.0);
        float3 plate2 = voronoiDetail(P / max(r * 0.85, 1.5) + s.seed * 7.0, 0.0);
        float n = fbm(flowUV * 1.2);

        float coolingProgress = (1.0 - heat) * 1.15 + (x * 0.22) + (n - 0.5) * 0.35;
        float crackWidth = mix(0.07, 0.26, heat);
        float primaryCrack = 1.0 - smoothstep(0.015, crackWidth, plate1.x);
        float microCrack   = (1.0 - smoothstep(0.01, crackWidth * 0.65, plate2.x)) * 0.65;
        float crackMask    = saturate(primaryCrack + microCrack);

        float crust = saturate(smoothstep(0.12, 0.72, coolingProgress) * (1.0 - crackMask * 0.92));

        float plateBevel = smoothstep(0.0, 0.18, plate1.x) * crust;
        float2 rockBump = float2(valueNoise(P * 1.6) - 0.5, valueNoise(P * 1.6 + 7.3) - 0.5) * 1.1 * crust;
        float3 N = normalize(float3(n2 * (x / max(sq, 0.15)) * (0.65 + 0.35 * plateBevel) + rockBump, 1.0));
        float ndl = saturate(dot(N, kLight));

        float3 charcoalRock = float3(0.07, 0.065, 0.075) + plate1.z * float3(0.04, 0.03, 0.03);
        float3 rock = charcoalRock * (0.45 + 0.85 * ndl)
                    + powr(saturate(dot(N, kHalf)), 28.0) * 0.18 * crust;

        float pulse = 0.62 + 0.38 * sin(fu.waveTime * 2.8 + plate1.z * 6.28 + n * 7.0);
        float coreTemp = saturate(mix(crackMask * (0.72 + 0.28 * pulse) + sq * 0.18,
                                      0.55 + 0.45 * n + 0.25 * sq,
                                      heat));

        float3 hotBase   = s.color.rgb;
        float3 darkEmber = hotBase * float3(0.45, 0.08, 0.02);
        float3 midMagma  = mix(hotBase, float3(1.0, 0.38, 0.02), 0.55);
        float3 whiteHot  = float3(1.0, 0.96, 0.74);

        float3 fireCol = darkEmber;
        fireCol = mix(fireCol, midMagma, smoothstep(0.15, 0.60, coreTemp));
        fireCol = mix(fireCol, whiteHot, smoothstep(0.62, 0.96, coreTemp));

        float rimGlow = (1.0 - abs(crust - 0.5) * 2.0) * (0.5 + 0.5 * pulse);
        float3 bodyCol = mix(fireCol, rock, crust);
        bodyCol += midMagma * rimGlow * 0.45;
        bodyCol += powr(saturate(dot(N, kHalf)), 45.0) * 0.25 * (1.0 - crust);

        alpha = body + glowA;
        col = saturate((bodyCol * body + midMagma * glowA) / max(alpha, 1e-4));
        alpha *= s.color.a;
    } else if (s.brush == BRUSH_JELLY) {
        float wob = sin(P.x * 0.25 + P.y * 0.18 + fu.waveTime * 3.2) * 0.5
                  + sin(P.x * 0.11 - P.y * 0.30 + fu.waveTime * 2.1) * 0.5;
        float rr = r * (1.0 + 0.06 * wob);
        float cov = clamp((rr - d) / px + 0.5, 0.0, 1.0);
        if (cov <= 0.0) {
            discard_fragment();
        }
        float xr = clamp(d / max(rr, 1e-4), 0.0, 1.0);
        float sqr = sqrt(saturate(1.0 - xr * xr));
        float3 N = normalize(float3(n2 * (xr / max(sqr, 0.14)) * 0.88, 1.0));
        float3 base = s.color.rgb;
        float3 gel = mix(base * 0.52, mix(base, float3(1.0), 0.30), sqr * 0.75 + 0.15);
        gel += base * 0.40 * smoothstep(0.50, 0.95, xr);
        float spec = powr(saturate(dot(N, kHalf)), 65.0) * 1.15;
        float blob = smoothstep(0.72, 0.95, dot(normalize(float3(n2 * xr, max(sqr, 0.05))), normalize(float3(-0.45, -0.6, 0.66))));
        col = saturate(gel + float3(spec + blob * 0.48));
        alpha = cov * (0.78 + 0.18 * xr) * s.color.a;
    } else if (s.brush == BRUSH_LIGHTNING) {
        float flick = fu.waveTime * 15.0;
        float along = arc / max(r, 0.5);
        float jitter1 = (valueNoise(float2(along * 1.35, floor(flick))) - 0.5) * 1.35
                      + (valueNoise(float2(along * 4.2 + 7.0, floor(flick * 1.7))) - 0.5) * 0.55;
        float jitter2 = (valueNoise(float2(along * 2.1 + 19.0, floor(flick * 1.3))) - 0.5) * 1.6;
        float fd1 = abs(across * r - jitter1 * r * 0.72);
        float fd2 = abs(across * r - jitter2 * r * 0.85);
        // In the round caps |u| > |side|: the distance past the end point. The bolt stops at the
        // pen tip instead of shooting ahead of it; only the soft glow goes round the tip.
        float beyond = sqrt(max(in.u * in.u - in.side * in.side, 0.0)) * r;
        float atTip = 1.0 - smoothstep(0.0, r * 0.3, beyond);
        float core = ((1.0 - smoothstep(r * 0.13, r * 0.13 + px * 1.5, fd1))
                   + (1.0 - smoothstep(r * 0.06, r * 0.06 + px * 1.2, fd2)) * 0.55) * atTip;
        float halo = (exp(-fd1 / max(r * 0.32, 0.4)) + exp(-fd2 / max(r * 0.20, 0.3)) * 0.35) * atTip;
        float outer = 0.18 * exp(-1.6 * max(d - r * 0.6, 0.0) / max(r, 0.5));
        float a = saturate(core + halo * 0.85 + outer);
        if (a <= 0.003) {
            discard_fragment();
        }
        float3 hsvL = rgb2hsv(s.color.rgb);
        float3 glowC = hsv2rgb(float3(hsvL.x, max(hsvL.y, 0.78), min(hsvL.z, 0.98)));
        col = mix(glowC, mix(s.color.rgb, float3(1.0), 0.82), saturate(core + halo * 0.28));
        alpha = a * s.color.a;
    } else if (s.brush == BRUSH_PEARL) {
        float spacing = max(r * 2.0, 1.5);
        float u = arc / spacing;
        float k = floor(u + 0.5);
        float2 lp = float2((u - k) * spacing, across * r);
        float br = r * 0.92;
        float dd = length(lp);
        float cov = clamp((br - dd) / px + 0.5, 0.0, 1.0);
        float silkThread = (1.0 - smoothstep(r * 0.06, r * 0.06 + px, d)) * 0.7;
        if (cov <= 0.0 && silkThread <= 0.0) {
            discard_fragment();
        }
        float xb = saturate(dd / max(br, 1e-4));
        float sb = sqrt(saturate(1.0 - xb * xb));
        float2 dir2 = dd > 1e-5 ? lp / dd : float2(0.0);
        float2 ndir = float2(-tdir.y, tdir.x);
        float2 pageDir = tdir * dir2.x + ndir * dir2.y;
        float3 N = normalize(float3(pageDir * xb, max(sb, 0.05)));
        float ndl = saturate(dot(N, kLight));
        float irid = sin(xb * 9.0 + k * 1.7 + s.seed * 6.0);
        float3 sheen = 0.5 + 0.5 * cos(6.2831 * (float3(0.0, 0.33, 0.67) + xb * 0.6 + k * 0.13));
        float3 pc = s.color.rgb * (0.64 + 0.46 * ndl) + sheen * 0.14 * (0.6 + 0.4 * irid);
        pc += powr(saturate(dot(N, kHalf)), 75.0) * 1.05 + powr(saturate(1.0 - sb), 3.0) * 0.16;
        alpha = max(cov, silkThread);
        col = cov >= silkThread ? saturate(pc) : float3(0.75, 0.72, 0.68);
        alpha *= s.color.a;
    } else if (s.brush == BRUSH_NEON) {
        float body = clamp((r - d) / px + 0.5, 0.0, 1.0);
        float core = smoothstep(r * 0.65, r * 0.15, d);
        float glow = 0.14 * exp(-1.45 * max(d - r, 0.0) / max(r, 0.5)) * (1.0 - body);
        float3 bodyCol = mix(s.color.rgb, float3(1.0), saturate(0.20 + 0.75 * core * sq));
        alpha = body + glow;
        if (alpha <= 0.002) {
            discard_fragment();
        }
        col = (bodyCol * body + s.color.rgb * glow) / max(alpha, 1e-4);
        alpha *= s.color.a;
    } else if (s.brush == BRUSH_WATERCOLOR) {
        float n1 = valueNoise(P * 0.16 + s.seed * 37.0);
        float n2v = valueNoise(P * 0.55 + s.seed * 11.0);
        float rr = r * (0.9 + 0.14 * n1 + 0.05 * n2v);
        float cov = clamp((rr - d) / (px * 1.5) + 0.5, 0.0, 1.0);
        if (cov <= 0.0) {
            discard_fragment();
        }
        float xr = clamp(d / max(rr, 1e-4), 0.0, 1.0);
        float edge = smoothstep(0.55, 0.95, xr);
        float pigment = 0.10 + 0.07 * n1 + 0.06 * n2v + 0.14 * edge;
        col = saturate(s.color.rgb * (0.92 + 0.1 * n2v) * (1.0 - 0.20 * edge));
        alpha = cov * pigment * s.color.a;
    } else if (s.brush == BRUSH_PENCIL) {
        float cov = clamp((r - d) / px + 0.5, 0.0, 1.0);
        if (cov <= 0.0) {
            discard_fragment();
        }
        float grain = valueNoise(P * 1.7) * 0.65 + valueNoise(P * 5.3 + 7.1) * 0.35;
        float density = smoothstep(0.15, 0.85, grain + (ink - 0.55) * 0.9);
        float soft = 1.0 - smoothstep(0.45, 1.0, x);
        col = s.color.rgb * 0.92;
        alpha = cov * ink * (0.18 + 0.62 * density) * (0.35 + 0.65 * soft) * s.color.a;
        if (alpha <= 0.002) {
            discard_fragment();
        }
    } else {
        float cov = clamp((r - d) / px + 0.5, 0.0, 1.0);
        if (cov <= 0.0) {
            discard_fragment();
        }
        if (s.brush == BRUSH_WET) {
            float w = wetness(fu, s.birth);
            col = shadeWet(s.color.rgb, x, n2, sq, ink, w);
        } else if (s.brush == BRUSH_WAVE) {
            col = shadeWave(s.color.rgb, x, n2, sq, P, fu.waveTime);
        } else if (s.brush == BRUSH_RAINBOW) {
            float3 hsv = rgb2hsv(s.color.rgb);
            float hue = fract(hsv.x + arc / 220.0);
            col = hsv2rgb(float3(hue, max(hsv.y, 0.28), max(hsv.z, 0.38)));
            col = tubeLight(col, n2, x, sq, 0.42, 0.40);
        } else if (s.brush == BRUSH_GLITTER) {
            float3 base = s.color.rgb;
            float flake = hash21(floor(P * 1.6) + s.seed * 13.0);
            float3 metal = base * (0.62 + 0.55 * flake);
            metal = tubeLight(metal, n2, x, sq, 0.65, 0.65);
            float2 cell = floor(P / 1.3);
            float h = hash21(cell + 3.7);
            float2 f = fract(P / 1.3) - 0.5;
            float tw = 0.5 + 0.5 * sin(fu.waveTime * (2.0 + 3.0 * h) + h * 40.0);
            float star = (1.0 - smoothstep(0.0, 0.32, length(f))) * step(0.8, h) * tw;
            float rays = (1.0 - smoothstep(0.0, 0.06, min(abs(f.x), abs(f.y)))) * (1.0 - smoothstep(0.0, 0.5, length(f)))
                         * step(0.93, h) * tw;
            col = saturate(metal + float3(1.0, 0.98, 0.9) * (star * 0.95 + rays * 0.85));
        } else if (s.brush == BRUSH_CALLIGRAPHY) {
            float pool = smoothstep(0.68, 1.0, x) * 0.22;
            col = s.color.rgb * (1.0 - pool) * (0.96 + 0.06 * valueNoise(P * 0.8));
            col = tubeLight(col, n2, x, sq, 0.18, 0.30);
        } else if (s.brush == BRUSH_GRASS) {
            float3 tuft = voronoiDetail(P * 0.75 + s.seed * 5.0, 0.0);
            float n = fbm(P * 0.55 + s.seed * 3.0);
            float tuftDome = 1.0 - smoothstep(0.0, 0.65, tuft.y);
            float3 base = s.color.rgb;
            float3 deepMoss = base * 0.36;
            float3 freshTurf = mix(base * 0.88, float3(0.48, 0.82, 0.24), 0.28);
            col = mix(deepMoss, freshTurf, saturate(tuftDome * 0.7 + n * 0.4));
            col = tubeLight(col, n2, x, sq, 0.08, 0.45);
            float edgeTuft = smoothstep(0.62, 0.98, x + (tuft.y - 0.4) * 0.22);
            cov *= 0.95 * (1.0 - edgeTuft);
        } else if (s.brush == BRUSH_FOUNTAIN) {
            col = shadeWet(s.color.rgb, x, n2, sq, ink, 0.78);
        } else if (s.brush == BRUSH_GOLD) {
            float2 hammer = (float2(valueNoise(P * 0.9 + 3.0), valueNoise(P * 0.9 + 11.0)) - 0.5) * 0.32;
            float3 N = normalize(float3(n2 * (x / max(sq, 0.12)) * 0.95 + hammer, 1.0));
            float lum = dot(envColor(reflectView(N), float3(1.0)), float3(0.3, 0.59, 0.11));
            col = s.color.rgb * (0.24 + 1.12 * lum) + powr(saturate(dot(N, kHalf)), 75.0) * float3(1.0, 0.96, 0.82) * 1.05;
            col = saturate(col);
        } else if (s.brush == BRUSH_CHROME) {
            float3 N = normalize(float3(n2 * (x / max(sq, 0.12)) * 1.15, 1.0));
            float3 env = envColor(reflectView(N), mix(float3(1.0), s.color.rgb * 1.2, 0.55));
            col = saturate(env * 1.08 + powr(saturate(dot(N, kHalf)), 140.0) * 1.3);
        } else if (s.brush == BRUSH_ICE) {
            float frost = fbm(P * 0.35 + s.seed * 4.0);
            float cracks = (1.0 - smoothstep(0.015, 0.075, cellEdge(P / max(r * 1.05, 0.8) + s.seed * 3.0))) * 0.68;
            float3 N = normalize(float3(n2 * (x / max(sq, 0.15)) * 0.78 + (frost - 0.5) * 0.42, 1.0));
            float fres = powr(saturate(1.0 - N.z), 2.2);
            float3 base = mix(s.color.rgb, float3(0.92, 0.98, 1.0), 0.38);
            float hs = hash21(floor(P / 1.5) + 2.3);
            float tw = step(0.93, hs) * (0.5 + 0.5 * sin(fu.waveTime * (3.0 + 4.0 * hs) + hs * 30.0));
            col = base * (0.76 + 0.24 * frost) + fres * 0.48 + cracks * 0.55;
            col = saturate(col + powr(saturate(dot(N, kHalf)), 85.0) * 1.05 + tw * 0.85);
            alphaScale = saturate(0.66 + 0.28 * fres + 0.22 * cracks);
        } else if (s.brush == BRUSH_GALAXY) {
            float drift = fu.waveTime * 0.15;
            float2 gp = P * 0.07 + float2(drift, -drift * 0.6) + s.seed * 9.0;
            float neb = fbm(gp + fbm(gp * 1.7 - drift) * 1.25);
            float3 hsv = rgb2hsv(s.color.rgb);
            float3 c1 = hsv2rgb(float3(hsv.x, 0.88, 0.95));
            float3 c2 = hsv2rgb(float3(fract(hsv.x + 0.18), 0.78, 0.90));
            float3 space = float3(0.015, 0.010, 0.045);
            col = mix(space, mix(c1, c2, smoothstep(0.28, 0.82, fbm(gp * 2.3 + 4.0))), smoothstep(0.32, 0.86, neb) * 0.90);
            float sh = hash21(floor(P / 1.1) + s.seed * 3.1);
            float2 sf = fract(P / 1.1) - 0.5;
            float star = step(0.88, sh) * (1.0 - smoothstep(0.0, 0.22 + (sh - 0.88) * 1.2, length(sf)));
            star *= 0.55 + 0.45 * sin(fu.waveTime * (1.5 + sh * 5.0) + sh * 40.0);
            col += star * float3(0.96, 0.97, 1.0);
            col = tubeLight(col, n2, x, sq, 0.60, 0.55);
        } else if (s.brush == BRUSH_IMPASTO) {
            float acrossN = sacross;
            float ridgePhase = acrossN * 14.0 + valueNoise(float2(arc * 0.15, acrossN * 3.0) + s.seed * 5.0) * 4.0;
            float lump = valueNoise(float2(arc * 0.25, acrossN * 2.0) + s.seed * 3.0) - 0.5;
            float2 nLeft = float2(-tdir.y, tdir.x);
            float3 N = normalize(float3(n2 * (x / max(sq, 0.15)) * 0.55 - nLeft * cos(ridgePhase) * 0.55 + tdir * lump * 0.75, 1.0));
            float3 base = s.color.rgb * (0.9 + 0.2 * valueNoise(P * 0.2 + 9.0));
            col = base * (0.52 + 0.80 * saturate(dot(N, kLight)));
            col = saturate(col + powr(saturate(dot(N, kHalf)), 26.0) * 0.34);
            alphaScale = 1.0 - 0.35 * smoothstep(0.85, 1.0, x) * valueNoise(P * 0.8);
        }
        alpha = cov * s.color.a * alphaScale;
    }

    InkOut o;
    o.color = su.depthOnly > 0.5 ? float4(0.0) : float4(col * alpha, alpha);
    o.depth = in.zBase + su.depthStep * (0.46 + 0.44 * saturate(abs(in.u) * 0.25));
    return o;
}

fragment InkOut highlighter_fragment(RibbonOut in [[stage_in]],
                                     constant FrameUniforms& fu [[buffer(0)]],
                                     constant SegUniforms& su [[buffer(1)]],
                                     const device StrokeGPU* strokes [[buffer(3)]])
{
    StrokeFrag sf = strokeFrag(in);
    float cov = clamp((sf.r - sf.d) / fu.pixelSize + 0.5, 0.0, 1.0);
    if (cov <= 0.0) {
        discard_fragment();
    }
    StrokeGPU s = strokes[in.stroke];
    InkOut o;
    o.color = float4(mix(float3(1.0), s.color.rgb, cov * s.color.a), 1.0);
    o.depth = in.zBase + (1.0 - cov) * su.depthStep * 0.9;
    return o;
}

fragment InkOut shadow_fragment(RibbonOut in [[stage_in]],
                                constant FrameUniforms& fu [[buffer(0)]],
                                constant SegUniforms& su [[buffer(1)]],
                                const device StrokeGPU* strokes [[buffer(3)]])
{
    StrokeFrag sf = strokeFrag(in);
    float r = sf.r;
    float d = sf.d;
    float blur = in.blur;
    float cov = 1.0 - smoothstep(r - blur, r + blur, d);
    if (cov <= 0.003) {
        discard_fragment();
    }
    StrokeGPU s = strokes[in.stroke];
    float strength = 0.28;
    if (s.brush == BRUSH_WAVE || s.brush == BRUSH_SEA) {
        strength = 0.22;
    } else if (s.brush == BRUSH_GRASS) {
        strength = 0.24;
    } else if (s.brush == BRUSH_ICE || s.brush == BRUSH_JELLY) {
        strength = 0.16;
    }
    strength *= in.h * s.color.a;
    float a = cov * strength;
    InkOut o;
    o.color = su.depthOnly > 0.5 ? float4(0.0) : float4(float3(0.09, 0.11, 0.18) * a, a);
    o.depth = in.zBase + su.depthStep * 0.9 * saturate(d / (r + blur));
    return o;
}

// MARK: grass blades

constant uint BLADE_SEGS = 7u;

struct BladeOut {
    float4 position [[position]];
    float2 n2;
    float  t;
    float  u;
    float  halfPx;
    float3 color [[flat]];
    float  alpha [[flat]];
    float  depth [[flat]];
    float  kind  [[flat]];
};

static float bladeGrowth(float time, float birth) {
    float g = saturate((time - birth) / 0.5);
    float k = 1.0 - g;
    return 1.0 - k * k * k;
}

static float bladeSway(constant FrameUniforms& fu, BladeGPU b) {
    float t = fu.waveTime;
    return sin(t * (1.1 + 0.9 * b.stiffness) + b.phase + b.base.x * 0.045) * 0.6
         + sin(t * 2.7 + b.phase * 1.9 + b.base.y * 0.03) * 0.25;
}

static float2 bladeAt(BladeGPU b, float s, float grow, float sway, thread float2& tangent) {
    float h = b.height * grow;
    float bend = b.lean * grow + sway * h * 0.16;
    tangent = float2(2.0 * bend * s, -h);
    return b.base + float2(bend * s * s, -h * s);
}

vertex BladeOut blade_vertex(uint vid [[vertex_id]],
                             uint iid [[instance_id]],
                             constant FrameUniforms& fu [[buffer(0)]],
                             constant SegUniforms& su [[buffer(1)]],
                             const device BladeGPU* blades [[buffer(5)]])
{
    BladeGPU b = blades[su.pointOffset + iid];
    float g = bladeGrowth(fu.time, b.birth);
    float sway = bladeSway(fu, b);
    uint i = min(vid >> 1, BLADE_SEGS);
    float s = float(i) / float(BLADE_SEGS);
    float side = (vid & 1u) != 0u ? 1.0 : -1.0;
    float2 tangent;
    float2 P = bladeAt(b, s, g, sway, tangent);
    float tl = length(tangent);
    float2 dir = tl > 1e-5 ? tangent / tl : float2(0.0, -1.0);
    float2 nrm = float2(-dir.y, dir.x);
    float w = b.kind == 1u ? b.width * (1.0 - 0.45 * s) : b.width * powr(max(1.0 - s, 1e-4), 0.85);
    w *= 0.35 + 0.65 * g;
    float hw = 0.5 * w;
    float ext = hw + fu.pixelSize;
    float order = float(su.orderOffset + b.stroke);
    float zBase = 1.0 - (order + 1.0) * su.depthStep;

    BladeOut o;
    float2 V = P + nrm * (side * ext);
    o.position = float4(docToNDC(su.pageOrigin + V, fu), zBase, 1.0);
    o.n2 = nrm;
    o.t = s;
    o.u = side * min(ext / max(hw, 1e-4), 6.0);
    o.halfPx = hw * fu.scale;
    o.color = b.color.rgb;
    o.alpha = b.color.a;
    o.depth = zBase + su.depthStep * 0.44 * b.depth;
    o.kind = float(b.kind);
    if (g <= 0.001) {
        o.position = float4(-2.0, -2.0, 0.5, 1.0);
    }
    return o;
}

fragment DecorOut blade_fragment(BladeOut in [[stage_in]])
{
    float cov = saturate((1.0 - abs(in.u)) * in.halfPx + 0.5);
    float a = cov * in.alpha;
    if (a <= 0.004) {
        discard_fragment();
    }
    float u = clamp(in.u, -1.0, 1.0);
    float3 base = in.color;
    float3 col;
    if (in.kind > 0.5) {
        col = base * mix(0.55, 1.05, in.t);
    } else {
        float3 darkRoot = base * 0.28;
        float3 sunlitTip = mix(base * 1.25, float3(0.88, 0.96, 0.38), 0.32);
        col = mix(darkRoot, base, smoothstep(0.0, 0.38, in.t));
        col = mix(col, sunlitTip, smoothstep(0.50, 1.0, in.t));
        float midrib = exp(-abs(u) * 8.0) * 0.12;
        float fibers = sin(u * 16.0) * 0.03;
        col += float3(midrib + fibers);
    }
    float3 N = normalize(float3(in.n2 * (u * 0.90), sqrt(max(1.0 - u * u * 0.75, 0.05))));
    float ndl = saturate(dot(N, kLight));
    col *= 0.58 + 0.68 * ndl;
    float spec = powr(saturate(dot(N, kHalf)), 32.0) * 0.28 * smoothstep(0.12, 0.88, in.t);
    col = saturate(col + float3(spec));
    DecorOut o;
    o.color = float4(col * a, a);
    o.depth = in.depth;
    return o;
}

// MARK: flowers

struct FlowerOut {
    float4 position [[position]];
    float2 q;
    float  pxR    [[flat]];
    float  open   [[flat]];
    float  grow   [[flat]];
    float  petals [[flat]];
    float  style  [[flat]];
    float  spin   [[flat]];
    float3 petal  [[flat]];
    float3 core   [[flat]];
    float  depth  [[flat]];
};

vertex FlowerOut flower_vertex(uint vid [[vertex_id]],
                               uint iid [[instance_id]],
                               constant FrameUniforms& fu [[buffer(0)]],
                               constant SegUniforms& su [[buffer(1)]],
                               const device BladeGPU* blades [[buffer(5)]],
                               const device FlowerGPU* flowers [[buffer(6)]])
{
    FlowerGPU f = flowers[iid];
    BladeGPU b = blades[su.pointOffset + f.stem];
    float g = bladeGrowth(fu.time, b.birth);
    float sway = bladeSway(fu, b);
    float2 tangent;
    float2 tip = bladeAt(b, 1.0, g, sway, tangent);
    float R = max(f.radius, 0.5);
    float extent = R * 1.35 + fu.pixelSize * 2.0;
    float2 corner = float2((vid & 1u) != 0u ? 1.0 : -1.0, (vid & 2u) != 0u ? 1.0 : -1.0);
    float order = float(su.orderOffset + b.stroke);
    float zBase = 1.0 - (order + 1.0) * su.depthStep;

    FlowerOut o;
    o.position = float4(docToNDC(su.pageOrigin + tip + corner * extent, fu), zBase, 1.0);
    o.q = corner * (extent / R);
    o.pxR = fu.pixelSize / R;
    o.open = saturate((fu.time - f.bloom) / 0.85);
    o.grow = smoothstep(0.55, 1.0, g);
    o.petals = max(f.petals, 3.0);
    o.style = f.style;
    o.spin = f.spin + sway * 0.14;
    o.petal = f.petal.rgb;
    o.core = f.core.rgb;
    o.depth = zBase + su.depthStep * (0.44 * b.depth - 0.002);
    if (o.grow <= 0.001) {
        o.position = float4(-2.0, -2.0, 0.5, 1.0);
    }
    return o;
}

static float4 over(float4 src, float4 dst) {
    return src + dst * (1.0 - src.a);
}

fragment DecorOut flower_fragment(FlowerOut in [[stage_in]])
{
    float e = in.open;
    float c1 = 1.85;
    float em = e - 1.0;
    float ob = 1.0 + (c1 + 1.0) * em * em * em + c1 * em * em;
    float S = mix(0.28, 1.0, ob) * in.grow;
    float px = in.pxR;

    float2 q = float2(in.q.x, in.q.y / 0.86);
    float cs = cos(in.spin);
    float sn = sin(in.spin);
    float2 r = float2(cs * q.x - sn * q.y, sn * q.x + cs * q.y);
    float rho = length(r);
    float th = atan2(r.y, r.x);
    float2 dirQ = length(q) > 1e-5 ? normalize(q) : float2(0.0);

    float n = in.petals;
    float sharp = in.style < 0.5 ? 1.45 : (in.style < 1.5 ? 0.52 : 0.38);
    float notch = in.style < 0.5 ? 0.20 : 0.44;
    float c0 = max(abs(cos(0.5 * n * th)), 1e-4);
    float c2 = max(abs(cos(0.5 * n * th + 1.5707963)), 1e-4);
    float lobe1 = powr(c0, sharp);
    float lobe2 = powr(c2, sharp);
    float tipDip = in.style > 0.5 ? (0.04 * powr(c0, 12.0)) : 0.0;
    float edge1 = S * (notch + (1.0 - notch) * lobe1 - tipDip);
    float edge2 = S * 0.90 * (notch + (1.0 - notch) * lobe2);
    float a1 = saturate((edge1 - rho) / px + 0.5);
    float a2 = in.style > 0.5 ? saturate((edge2 - rho) / px + 0.5) : 0.0;

    float budMix = 1.0 - smoothstep(0.05, 0.55, e);
    float3 petal = mix(in.petal, float3(0.32, 0.58, 0.22), budMix * 0.55);
    float rr = rho / max(S, 1e-4);

    float cup = in.style > 1.5 ? 0.95 : 0.62;
    float petalPleat = (1.0 - lobe1) * 0.35;
    float3 N = normalize(float3(-dirQ * (cup * rr - petalPleat), 1.0));
    float ndl = saturate(dot(N, kLight));
    float fineVeins = sin(th * n * 7.0) * 0.5 + 0.5;
    float vein = powr(max(lobe1, 1e-4), 14.0) * 0.08 + fineVeins * smoothstep(0.15, 0.85, rr) * 0.05;

    float3 throatCol = mix(petal * 0.62, in.core, 0.28);
    float3 rimGlow = mix(petal, float3(1.0), 0.32);
    float3 col1 = mix(throatCol, petal, smoothstep(0.10, 0.52, rr));
    col1 = mix(col1, rimGlow, smoothstep(0.68, 0.98, rr));
    col1 *= 0.76 + 0.46 * ndl;
    col1 += float3(vein);
    col1 = saturate(col1 + powr(saturate(dot(N, kHalf)), 32.0) * 0.22);

    float3 col2 = mix(throatCol * 0.75, petal * 0.80, smoothstep(0.12, 0.70, rr)) * (0.78 + 0.32 * ndl);

    float coreR = S * (in.style < 0.5 ? 0.32 : 0.24) * smoothstep(0.08, 0.55, e);
    float aC = coreR > 1e-4 ? saturate((coreR - rho) / px + 0.5) : 0.0;
    float xc = saturate(rho / max(coreR, 1e-4));
    float sqc = sqrt(saturate(1.0 - xc * xc));
    float3 Nc = normalize(float3(dirQ * xc, max(sqc, 0.05)));
    float3 colC = in.core * (0.68 + 0.52 * saturate(dot(Nc, kLight)));
    float pollenGrain = step(0.55, hash21(floor(r * 32.0)));
    colC = mix(colC, colC * 1.25 + float3(0.18, 0.12, 0.0), pollenGrain * 0.45);
    colC = saturate(colC + powr(saturate(dot(Nc, kHalf)), 26.0) * 0.38);

    float stamenRingR = coreR * 1.28;
    float stamenAngle = atan2(r.y, r.x) * 12.0;
    float2 stamenP = float2(rho - stamenRingR, sin(stamenAngle) * stamenRingR * 0.12);
    float aStamen = (coreR > 1e-4 ? saturate((coreR * 0.14 - length(stamenP)) / px + 0.5) : 0.0) * smoothstep(0.3, 0.8, e);
    float3 colStamen = float3(1.0, 0.88, 0.25);

    float2 sq = in.q - float2(0.12, 0.18) * S;
    float shadowA = 0.26 * (1.0 - smoothstep(0.30 * S, 1.08 * S, length(sq))) * smoothstep(0.0, 0.3, e) * in.grow;

    float4 acc = float4(0.0, 0.0, 0.0, shadowA);
    acc = over(float4(col2 * a2, a2), acc);
    acc = over(float4(col1 * a1, a1), acc);
    acc = over(float4(colStamen * aStamen, aStamen), acc);
    acc = over(float4(colC * aC, aC), acc);
    if (acc.a <= 0.003) {
        discard_fragment();
    }
    DecorOut o;
    o.color = acc;
    o.depth = in.depth;
    return o;
}

// MARK: page quads

vertex QuadOut quad_vertex(uint vid [[vertex_id]],
                           constant FrameUniforms& fu [[buffer(0)]],
                           constant QuadUniforms& qu [[buffer(1)]])
{
    float2 corner = float2((vid & 1u) != 0u ? 1.0 : 0.0, (vid & 2u) != 0u ? 1.0 : 0.0);
    float2 doc = qu.rect.xy + corner * qu.rect.zw;
    QuadOut o;
    o.position = float4(docToNDC(doc, fu), 0.0, 1.0);
    o.uv = mix(qu.uvRect.xy, qu.uvRect.zw, corner);
    o.local = doc - qu.pageOrigin;
    return o;
}

fragment float4 paper_fragment(QuadOut in [[stage_in]],
                               constant FrameUniforms& fu [[buffer(0)]],
                               constant QuadUniforms& qu [[buffer(1)]])
{
    float px = fu.pixelSize;
    float2 p = in.local;
    float3 col = float3(1.0);
    if (qu.style == 1u) {
        float spacing = 28.0;
        float top = 84.0;
        float fade = smoothstep(3.0, 7.0, spacing / px);
        if (p.y > top - spacing * 0.5) {
            float f = (p.y - top) / spacing;
            float dist = abs(f - round(f)) * spacing;
            float lw = max(0.45, px * 0.5);
            float line = 1.0 - smoothstep(lw, lw + px, dist);
            col = mix(col, float3(0.66, 0.80, 0.95), line * fade);
        }
        float mw = max(0.5, px * 0.5);
        float ml = 1.0 - smoothstep(mw, mw + px, abs(p.x - 72.0));
        col = mix(col, float3(0.96, 0.62, 0.62), ml * 0.85);
    } else if (qu.style == 2u) {
        float spacing = 20.0;
        float fade = smoothstep(3.0, 7.0, spacing / px);
        float2 f = p / spacing;
        float2 dist = abs(f - round(f)) * spacing;
        float lw = max(0.35, px * 0.5);
        float line = 1.0 - smoothstep(lw, lw + px, min(dist.x, dist.y));
        col = mix(col, float3(0.78, 0.85, 0.93), line * fade);
    } else if (qu.style == 3u) {
        float spacing = 20.0;
        float fade = smoothstep(3.0, 7.0, spacing / px);
        float2 f = p / spacing;
        float2 dd = (f - round(f)) * spacing;
        float rd = max(0.9, px * 0.7);
        float dotv = 1.0 - smoothstep(rd, rd + px, length(dd));
        col = mix(col, float3(0.60, 0.64, 0.70), dotv * fade);
    }
    return float4(col, 1.0);
}

fragment float4 texture_fragment(QuadOut in [[stage_in]],
                                 texture2d<float> tex [[texture(0)]],
                                 sampler smp [[sampler(0)]])
{
    return float4(tex.sample(smp, in.uv).rgb, 1.0);
}

fragment float4 page_shadow_fragment(QuadOut in [[stage_in]],
                                     constant QuadUniforms& qu [[buffer(1)]])
{
    float2 p = in.local - float2(0.0, 1.5);
    float2 h = qu.pageSize * 0.5;
    float2 q = abs(p - h) - h;
    float dist = length(max(q, float2(0.0))) + min(max(q.x, q.y), 0.0);
    float a = (1.0 - smoothstep(0.0, max(qu.shadowRadius, 0.5), dist)) * 0.14;
    return float4(0.0, 0.0, 0.0, a);
}
"""#
}
