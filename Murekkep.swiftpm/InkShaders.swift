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
    uint   kind;           // 0 blade, 1 flower stem, 2 glass stem, 3 glass leaf (the flowering water)
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

// The ocean pen's swell seen from above: three trains of rounded crests crossing the page at fixed
// angles, the wavelength following the line's width so thin and thick water read alike. Returns the
// height (0 trough .. 1 crest) and its gradient in page space (height units per point).
static float swellField(float2 P, float t, float L, float seed, thread float2& grad) {
    const float2 d0 = float2(0.86, 0.51);
    const float2 d1 = float2(-0.34, 0.94);
    float k0 = 6.2831853 / L;
    float k1 = 6.2831853 / (L * 0.55);
    float s0 = dot(P, d0) * k0 - 1.15 * t + seed;
    float s1 = dot(P, d1) * k1 - 1.75 * t + seed * 2.3 + 1.7;
    float u0 = max(0.5 + 0.5 * sin(s0), 1e-3);
    float u1 = max(0.5 + 0.5 * sin(s1), 1e-3);
    float W = 0.68 * powr(u0, 1.8) + 0.32 * powr(u1, 2.0);
    grad = d0 * (0.68 * 0.9 * k0 * powr(u0, 0.8) * cos(s0))
         + d1 * (0.32 * 1.0 * k1 * u1 * cos(s1));
    return W;
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

// The ocean pen: a pool of sea seen from above. Turquoise shallows at the shore deepening to the
// ink's blue in the middle, a swell whose lit and shadowed faces roll across the line, caustic nets
// drifting over the bed, lace on the breaking crests and a thin white edge where the water meets
// the shore. Every pattern is sized from the line's width and blurred by the pixel size, so a thin
// line is smooth glossy water with soft bands of light rather than speckle.
static float3 shadeWave(float3 base, float x, float2 n2, float sq, float2 P, float t, float rN, float px, float seed) {
    float L = max(rN * 3.0, 9.0);
    float2 g;
    float hN = swellField(P, t, L, seed, g);
    float slope = min(0.30 * x / max(sq, 0.12), 2.5);
    float amp = rN * 0.30 * (0.5 + 0.5 * sq);
    float3 N = normalize(float3(n2 * slope - g * amp, 1.0));
    float detail = smoothstep(2.0, 6.0, rN / px);

    float depth = saturate(powr(max(sq, 1e-4), 0.8) * (0.9 - 0.25 * hN));
    float3 deep = base * float3(0.20, 0.36, 0.64);
    float3 mid = mix(base, float3(0.06, 0.62, 0.80), 0.52);
    float3 shallow = mix(base, float3(0.40, 0.94, 0.88), 0.74);
    float3 col = depth < 0.5 ? mix(shallow, mid, depth * 2.0) : mix(mid, deep, (depth - 0.5) * 2.0);
    // The swell: light through the rising crests, the troughs deeper, lit and shadowed faces.
    col = mix(col, mix(shallow, float3(0.55, 0.95, 0.92), 0.4), smoothstep(0.55, 1.0, hN) * 0.40 * (1.0 - 0.3 * depth));
    col *= (0.82 + 0.18 * hN) * (0.92 + 0.45 * (dot(N, kLight) - kLight.z));

    float cs = max(rN * 0.9, 2.8);
    float aa = px / cs;
    float2 cq = P / cs + g * 0.5 + seed * 11.0;
    float e1 = waterCells(cq, t * 1.1);
    float e2 = waterCells(cq * 1.9 + float2(4.2, -3.1), -t * 1.5 + 1.5);
    float caust = powr(saturate(1.0 - e1 / (0.24 + aa * 2.0)), 1.6) * 0.30
                + powr(saturate(1.0 - e2 / (0.18 + aa * 2.4)), 1.6) * 0.16;
    col += float3(0.60, 0.97, 1.0) * caust * detail * smoothstep(0.15, 0.6, depth) * 0.55;

    float fresnel = powr(saturate(1.0 - N.z), 2.6);
    col = mix(col, envColor(reflectView(N), float3(0.88, 0.96, 1.0)), fresnel * 0.35);

    float fn = valueNoise(P / max(rN * 0.9, 2.0) * 1.3 + t * 0.4 + seed * 5.0);
    float web = 1.0 - smoothstep(0.0, 0.18 + aa * 1.5, waterCells(P / max(rN * 0.6, 2.5) + seed * 3.0, t * 1.9));
    float crest = smoothstep(0.80, 0.97, hN + (fn - 0.5) * 0.20) * (0.35 + 0.65 * web) * detail;
    float shore = smoothstep(0.84, 0.97, x + 0.04 * sin(P.x * 0.5 + P.y * 0.4 - t * 2.0) + 0.04 * hN) * (0.5 + 0.5 * web);
    float foam = saturate(crest * 0.85 + shore * 0.65);
    col = mix(col, float3(0.97, 0.995, 1.0), foam);

    float nh = saturate(dot(N, kHalf));
    float spec = powr(nh, 90.0) * 0.9 * (1.0 - foam * 0.6) + powr(nh, 400.0) * 1.2 + powr(nh, 20.0) * 0.12;
    return saturate(col + float3(spec));
}

// The sea pen's waves: three trains rolling along the line with the current, their crests a little
// oblique, the wavelength following the line's width. Returns the height (0 trough .. 1 crest) and
// the slope along and across the line (height units per point).
static float seaSwell(float arc, float v, float t, float L, float seed, thread float2& slope) {
    float k0 = 6.2831853 / L;
    float k1 = 6.2831853 / (L * 0.62);
    float k2 = 6.2831853 / (L * 0.41);
    float p0 = k0 * (arc + v * 0.35) - 3.0 * t + seed * 3.1;
    float p1 = k1 * (arc - v * 0.28) - 3.8 * t + seed * 4.8 + 1.3;
    float p2 = k2 * (arc + v * 0.15) - 4.6 * t + seed * 6.5 + 2.9;
    float w0 = max(0.5 + 0.5 * sin(p0), 1e-3);
    float w1 = max(0.5 + 0.5 * sin(p1), 1e-3);
    float w2 = max(0.5 + 0.5 * sin(p2), 1e-3);
    float g0 = 0.55 * 0.8 * powr(w0, 0.6) * cos(p0) * k0;
    float g1 = 0.30 * 0.9 * powr(w1, 0.8) * cos(p1) * k1;
    float g2 = 0.15 * 1.0 * w2 * cos(p2) * k2;
    slope = float2(g0 + g1 + g2, g0 * 0.35 - g1 * 0.28 + g2 * 0.15);
    return 0.55 * powr(w0, 1.6) + 0.30 * powr(w1, 1.8) + 0.15 * powr(w2, 2.0);
}

static float3 tubeLight(float3 col, float2 n2, float x, float sq, float gloss, float strength) {
    float3 N = normalize(float3(n2 * (x / max(sq, 0.15)) * strength, 1.0));
    float ndl = dot(N, kLight);
    col *= 1.0 + 0.48 * (ndl - kLight.z);
    float spec = powr(saturate(dot(N, kHalf)), 48.0) * gloss;
    return saturate(col + float3(spec));
}

// The lava's temperature ramp, built from the ink's own hue: a dark, redder skin, the ink colour at
// full glow, a paler yellower blaze, then white heat.
static float3 lavaRamp(float3 skin, float3 glow, float3 blaze, float temp) {
    float3 c = mix(skin, glow, smoothstep(0.0, 0.42, temp));
    c = mix(c, blaze, smoothstep(0.50, 0.82, temp));
    return mix(c, float3(1.0, 0.98, 0.92), smoothstep(0.86, 1.0, temp));
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
        // A sea flowing along the line: the water, its caustic nets and foam all slide with the
        // current, waves roll along it, turquoise shallows and breaking foam line both shores and the
        // shoreline itself surges with the waves. Patterns are sized from the line's set width and
        // blurred by the pixel size, so thin handwriting stays a smooth banded line with a foamy rim.
        float t = fu.waveTime;
        float rN = max(s.width * 0.5, 0.5);
        float L = max(rN * 2.4, 7.0);
        float detail = smoothstep(2.0, 6.0, rN / px);
        float u = arc - t * rN * 1.5;
        float v = sacross * r;
        float2 slope;
        float hN = seaSwell(arc, v, t, L, s.seed, slope);

        float side = sacross < 0.0 ? -1.0 : 1.0;
        float surge = sin(arc / L * 6.2831853 - 2.6 * t + s.seed * 5.0 + side * 1.6);
        float rDyn = r * (0.97 + 0.06 * surge + 0.05 * hN);
        float cov = clamp((rDyn - d) / (px * 1.2) + 0.5, 0.0, 1.0);
        if (cov <= 0.0) {
            discard_fragment();
        }
        float xDyn = clamp(d / max(rDyn, 1e-4), 0.0, 1.0);
        float sqDyn = sqrt(saturate(1.0 - xDyn * xDyn));

        float2 nLeft = float2(-tdir.y, tdir.x);
        float2 slopeP = slope.x * tdir + slope.y * nLeft;
        float3 N = normalize(float3(-slopeP * (rN * 0.45) + n2 * (xDyn / max(sqDyn, 0.18)) * 0.35, 1.0));

        float3 base = s.color.rgb;
        float3 deep = base * float3(0.20, 0.38, 0.68);
        float3 midSea = mix(base, float3(0.05, 0.66, 0.78), 0.58);
        float3 shallow = mix(base, float3(0.36, 0.96, 0.88), 0.78);
        float depth = smoothstep(0.45, 1.0, sqDyn * (0.88 - 0.22 * hN)) * (0.65 + 0.35 * detail);
        float3 water = depth < 0.5 ? mix(shallow, midSea, depth * 2.0) : mix(midSea, deep, (depth - 0.5) * 2.0);
        water = mix(water, mix(shallow, float3(0.50, 0.96, 0.90), 0.4), smoothstep(0.55, 1.0, hN) * 0.50 * (1.0 - 0.3 * depth));
        water *= (0.78 + 0.22 * hN) * (0.92 + 0.50 * (dot(N, kLight) - kLight.z));

        float cs = max(rN * 0.9, 3.0);
        float aa = px / cs;
        float2 cq = float2(u, v) / cs + slope * 0.6 + s.seed * 11.0;
        float e1 = waterCells(cq, t * 1.3);
        float e2 = waterCells(cq * 1.8 + float2(3.1, 7.7), -t * 1.6 + 2.0);
        float caust = powr(saturate(1.0 - e1 / (0.28 + aa * 2.2)), 1.6) * 0.25
                    + powr(saturate(1.0 - e2 / (0.20 + aa * 2.6)), 1.6) * 0.12;
        water += float3(0.60, 0.97, 1.0) * caust * detail * smoothstep(0.25, 0.7, depth) * 0.7;

        float fresnel = powr(saturate(1.0 - N.z), 2.6);
        water = mix(water, envColor(reflectView(N), float3(0.88, 0.96, 1.0)), fresnel * 0.32);

        float fw = max(rN * 0.5, 1.0);
        float3 vF = voronoiDetail(float2(u / fw, sacross * 3.0) * 1.2 + s.seed * 3.0, t * 2.0);
        float web = 1.0 - smoothstep(0.0, 0.18 + (px / fw) * 1.5, vF.x);
        float fn = valueNoise(float2(u / max(rN * 0.8, 1.5), sacross * 2.0) + s.seed * 7.0);
        float shoreLine = 0.70 + 0.09 * surge + 0.10 * (fn - 0.5);
        float shoreFoam = smoothstep(shoreLine - 0.16, shoreLine + 0.04, xDyn) * (0.55 + 0.45 * web) * (0.55 + 0.45 * detail);
        float edgeLine = smoothstep(0.90, 0.985, xDyn) * 0.8;
        float streak = valueNoise(float2(u / max(rN * 1.6, 2.0), sacross * 5.0) + s.seed * 4.0);
        float spill = smoothstep(0.40, 0.90, xDyn) * smoothstep(0.55, 0.85, streak) * 0.45 * detail;
        float cap = smoothstep(0.72, 0.95, hN + (fn - 0.5) * 0.25) * (0.35 + 0.65 * web) * detail;
        float foam = saturate(max(shoreFoam * 0.9, edgeLine) + spill + cap * 0.65);
        float3 foamColor = float3(0.96, 0.99, 1.0) * (0.90 + 0.12 * dot(N, kLight));
        water = mix(water, foamColor, foam);

        float nh = saturate(dot(N, kHalf));
        float glint = powr(nh, 120.0) * 1.2 * (1.0 - foam * 0.6) + powr(nh, 400.0) * 1.0 + powr(nh, 24.0) * 0.14;
        col = saturate(water + float3(glint));
        alpha = cov * s.color.a;
    } else if (s.brush == BRUSH_LAVA) {
        // Cools from where the pen started: each point starts cooling a little after the one before,
        // at drawing speed (380 pt/s, as InkRenderer.lavaCoolSpeed), counted from when the pen lifted.
        float age = fu.time - (s.birth + max(arc, 0.0) / 380.0);
        float heat = 1.0 - smoothstep(0.0, max(fu.coolDuration, 0.5), age);

        float heat2 = heat * heat;
        // Textures are scaled by the stroke's set width, not the pressure-varied radius, so they
        // do not bunch up where the pen pressed lighter.
        float rN = max(s.width * 0.5, 0.5);

        // Molten lava spills a little past its line; the set crust keeps the shape. A warm glow
        // lights the paper around it while it is hot, and faintly from the embers after.
        float edgeJag = (valueNoise(float2(arc / rN * 0.9, sacross * 1.5) + s.seed * 19.0) - 0.5)
                      * r * 0.09 * (0.6 + 0.4 * heat);
        float rLava = r + edgeJag;
        float body = clamp((rLava - d) / px + 0.5, 0.0, 1.0);
        float past = max(d - rLava, 0.0) / max(r, 0.5);
        float glowA = (1.0 - body) * (0.06 + 0.55 * heat) * exp(-2.4 * past) * saturate(1.0 - past / 1.4);
        if (body <= 0.0 && glowA <= 0.002) {
            discard_fragment();
        }
        float xL = clamp(d / max(rLava, 1e-4), 0.0, 1.0);
        float sqL = sqrt(saturate(1.0 - xL * xL));

        // The flow slides along the line while hot and freezes as it sets.
        float flowShift = mix(s.birth * 0.45 + fu.coolDuration * 0.25, fu.waveTime * 0.5, heat2);
        float2 fq = float2(arc / rN * 0.5 - flowShift, sacross * 1.1) + s.seed * 13.0;
        float n1 = fbm(fq);
        float rope = 0.5 + 0.5 * sin(fq.y * 5.5 + n1 * 6.0 + fq.x * 2.0);

        // Temperature: hottest down the middle, pulled into ropy streaks by the flow.
        float temp = saturate(0.18 + 0.48 * sqL + (n1 - 0.5) * 0.8 + rope * 0.2 * sqL);

        float3 hsvL = rgb2hsv(s.color.rgb);
        float3 skin = hsv2rgb(float3(fract(hsvL.x - 0.035), min(hsvL.y * 1.15 + 0.1, 1.0), hsvL.z * 0.38));
        float3 glow = hsv2rgb(float3(hsvL.x, hsvL.y, max(hsvL.z, 0.85)));
        float3 blaze = hsv2rgb(float3(fract(hsvL.x + 0.055), hsvL.y * 0.55, 1.0));
        float3 molten = lavaRamp(skin, glow, blaze, temp);

        // A viscous, faintly glossy surface.
        float2 bump = float2(valueNoise(fq * 2.3 + 5.0) - 0.5, valueNoise(fq * 2.3 + 9.0) - 0.5) * 0.5;
        float3 Nm = normalize(float3(n2 * (xL / max(sqL, 0.2)) * 0.6 + bump * sqL, 1.0));
        float nhM = saturate(dot(Nm, kHalf));
        molten = molten * (0.9 + 0.2 * saturate(dot(Nm, kLight)))
               + (powr(nhM, 22.0) * 0.18 + powr(nhM, 90.0) * 0.35) * float3(1.0, 0.98, 0.9) * (0.4 + 0.6 * heat);

        // The crust: basalt plates, sized from the line's width, with the cracks between them glowing.
        float cell = max(rN * 0.95, 2.6);
        float2 pq = float2(arc, sacross * r) / cell + s.seed * 7.0;
        float3 plate = voronoiDetail(pq, 0.0);
        float aa = px / cell;
        float cw = mix(0.075, 0.16, heat) + aa * 0.5;
        float crack = 1.0 - smoothstep(cw - aa, cw + aa, plate.x);
        float crustProgress = (1.0 - heat) * 1.35 - 0.2 + (valueNoise(pq * 0.7 + 3.0) - 0.5) * 0.45 + xL * 0.18;
        float crustRaw = smoothstep(0.0, 0.5, crustProgress);
        float crust = crustRaw * (1.0 - crack);

        float grain = valueNoise(P * 1.4 + s.seed) - 0.5;
        float plateAO = smoothstep(0.0, 0.26, plate.x);
        float3 rock = float3(0.115, 0.10, 0.10) + plate.z * float3(0.035, 0.025, 0.02) + grain * smoothstep(3.0, 7.0, rN / px) * 0.08;
        float3 Nr = normalize(float3(n2 * (xL / max(sqL, 0.2)) * 0.75, 1.0));
        rock *= (0.55 + 0.75 * saturate(dot(Nr, kLight))) * (0.55 + 0.45 * plateAO);
        rock += powr(saturate(dot(Nr, kHalf)), 14.0) * 0.07;

        // Embers keep burning in the cracks after the rock has set.
        float pulse = 0.5 + 0.5 * sin(fu.waveTime * 1.6 + plate.z * 6.28);
        float3 ember = lavaRamp(skin, glow, blaze, mix(0.08 + 0.20 * pulse + 0.25 * plate.z, temp, heat));
        float3 inside = mix(molten, ember, crustRaw);
        float3 bodyCol = mix(inside, rock, crust);
        float rim = crustRaw * (1.0 - crustRaw) * 4.0 * heat;
        bodyCol = mix(bodyCol, glow, rim * 0.3);

        alpha = body + glowA;
        col = saturate((bodyCol * body + mix(glow, blaze, 0.35) * glowA) / max(alpha, 1e-4));
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
            col = shadeWave(s.color.rgb, x, n2, sq, P, fu.waveTime, max(s.width * 0.5, 0.5), px, s.seed);
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
            // The turf the blades grow from: a mossy mound with a soft, ragged edge, shaded where it
            // lies under the grass on its lower side. Its clumps are sized from the line's width.
            float tuftScale = 1.0 / max(s.width * 0.4, 1.3);
            float3 tuft = voronoiDetail(P * tuftScale + s.seed * 5.0, 0.0);
            float n = fbm(P * tuftScale * 0.7 + s.seed * 3.0);
            float tuftDome = 1.0 - smoothstep(0.0, 0.65, tuft.y);
            float3 base = s.color.rgb;
            float3 deepMoss = base * 0.30;
            float3 freshTurf = mix(base * 0.88, float3(0.48, 0.82, 0.24), 0.28);
            col = mix(deepMoss, freshTurf, saturate(tuftDome * 0.7 + n * 0.4));
            col = tubeLight(col, n2, x, sq, 0.08, 0.45);
            float under = smoothstep(0.1, 0.9, n2.y * x);
            col = mix(col, float3(0.30, 0.21, 0.12) * (0.7 + 0.5 * n), under * 0.6);
            col *= 1.0 - 0.3 * under;
            float edgeTuft = smoothstep(0.62, 0.98, x + (tuft.y - 0.4) * 0.22 + (n - 0.5) * 0.1);
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
    float w;
    if (b.kind == 3u) {
        // A leaf: pointed at both ends, widest a little past the middle.
        w = b.width * powr(max(sin(3.14159265 * powr(max(s, 1e-4), 1.15)), 1e-4), 0.8);
    } else if (b.kind >= 1u) {
        w = b.width * (1.0 - 0.45 * s);
    } else {
        w = b.width * powr(max(1.0 - s, 1e-4), 0.85);
    }
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

// The flowering water's stems (kind 2) and leaves (kind 3): translucent turquoise glass, denser and
// deeper at the edges, with a soft streak and a sharp glint where the rounded surface faces the light.
static DecorOut glassBlade(BladeOut in, float u, float a)
{
    float uu = u * u;
    float3 N = normalize(float3(in.n2 * (u * 0.92), sqrt(max(1.0 - uu * 0.85, 0.05))));
    float ndl = saturate(dot(N, kLight));
    float3 base = in.color;
    float3 deep = base * float3(0.55, 0.78, 0.92);
    float3 col;
    float alpha;
    if (in.kind > 2.5) {
        // A leaf: a light midrib, the tip a touch bluer.
        float midrib = exp(-abs(u) * 7.0) * 0.16;
        col = mix(base, mix(base, float3(0.55, 0.72, 1.0), 0.35), smoothstep(0.4, 1.0, in.t));
        col = mix(col, deep, uu * 0.6);
        col += float3(midrib);
        alpha = 0.52 + 0.30 * uu;
    } else {
        // A stem: a glass rod, lighter toward the flower.
        col = mix(deep, base, 0.2 + 0.8 * smoothstep(0.0, 0.7, in.t));
        col = mix(col, deep * 0.9, uu * uu * 0.7);
        alpha = 0.66 + 0.30 * uu;
    }
    col *= 0.82 + 0.26 * ndl;
    float nh = saturate(dot(N, kHalf));
    float streak = powr(nh, 18.0);
    float glint = powr(nh, 90.0);
    col = saturate(col + float3(0.92, 0.98, 1.0) * (streak * 0.35 + glint * 0.55));
    a *= saturate(alpha + glint * 0.3);
    DecorOut o;
    o.color = float4(col * a, a);
    o.depth = in.depth;
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
    if (in.kind > 1.5) {
        return glassBlade(in, u, a);
    }
    float3 base = in.color;
    float3 col;
    if (in.kind > 0.5) {
        col = base * mix(0.55, 1.05, in.t);
    } else {
        // A blade of grass: dark at the root, the ink's green up the blade, sunlit at the tip, with
        // the light shining through the thin tip on the side that faces it and a darker rim so each
        // blade stands out of the tuft.
        float3 darkRoot = base * 0.26;
        float3 sunlitTip = mix(base * 1.25, float3(0.90, 0.96, 0.40), 0.36);
        col = mix(darkRoot, base, smoothstep(0.0, 0.38, in.t));
        col = mix(col, sunlitTip, smoothstep(0.50, 1.0, in.t));
        float midrib = exp(-abs(u) * 8.0) * 0.12;
        float fibers = sin(u * 16.0) * 0.03;
        col += float3(midrib + fibers);
        float facing = dot(in.n2 * (u < 0.0 ? -1.0 : 1.0), float2(-0.5865, -0.8100));
        float through = smoothstep(0.55, 1.0, in.t) * (0.5 + 0.5 * facing) * 0.20;
        col += float3(0.55, 0.62, 0.18) * through;
        col *= 1.0 - 0.26 * smoothstep(0.55, 1.0, abs(u)) * (1.0 - 0.5 * smoothstep(0.7, 1.0, in.t));
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
    float  seed   [[flat]];   // 0..1, fixed per flower (the glass flowers vary their tilt and stamens by it)
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
    o.seed = fract(f.spin * 0.15915494 + f.radius * 0.731);
    if (o.grow <= 0.001) {
        o.position = float4(-2.0, -2.0, 0.5, 1.0);
    }
    return o;
}

static float4 over(float4 src, float4 dst) {
    return src + dst * (1.0 - src.a);
}

// MARK: glass flowers (the flowering water, style 3)

struct GlassPetal {
    float  a;      // coverage of this petal, 0 outside it
    float  t;      // 0 at the flower's centre .. 1 at the tip
    float  u;      // -1 .. 1 across the petal
    float2 dirA;   // along the petal, in page space
};

// One petal of a whorl of n (centre angle (i + offset) * sector in the spun frame): narrow at the
// centre, widest a little past the middle, drawn to a slightly rounded point.
static GlassPetal glassPetal(float rho, float th, float i, float offset, float sector,
                             float L, float halfWidth, float px, float spin)
{
    float ang = (i + offset) * sector;
    float dth = th - ang;
    float along = rho * cos(dth);
    float across = rho * sin(dth);
    float t = saturate(along / L);
    float shape = powr(max(sin(3.14159265 * powr(max(t, 1e-4), 1.15)), 0.0), 0.72);
    float w = halfWidth * L * shape;
    GlassPetal p;
    p.a = saturate((w - abs(across)) / px + 0.5) * saturate((L - along) / px + 0.5) * saturate(along / px + 0.5);
    p.t = t;
    p.u = clamp(across / max(w, 1e-4), -1.0, 1.0);
    p.dirA = float2(cos(ang - spin), sin(ang - spin));
    return p;
}

// Colour (straight, not premultiplied) and alpha of a glass petal: pale at the centre shading to the
// tip colour, deeper and denser at the edges where the glass is seen edge-on, faint veins, a soft
// lit streak and a sharper glint on the cupped surface. Buds keep the water's pale blue.
static float4 glassPetalColor(GlassPetal p, float3 tip, float3 pale, float budMix, float cupping, float alphaScale)
{
    float uu = p.u * p.u;
    float2 dirC = float2(-p.dirA.y, p.dirA.x);
    float3 N = normalize(float3(dirC * (p.u * cupping) + p.dirA * ((p.t - 0.5) * 0.9), 1.0));
    float ndl = saturate(dot(N, kLight));
    float nh = saturate(dot(N, kHalf));
    float3 deep = tip * float3(0.80, 0.74, 1.0);
    float3 col = mix(pale, tip, smoothstep(0.12, 0.92, p.t));
    float edge = (uu * uu * 0.55 + smoothstep(0.80, 1.0, abs(p.u)) * 0.35) * smoothstep(0.08, 0.4, p.t);
    col = mix(col, deep, edge);
    float veins = powr(max(0.5 + 0.5 * cos(p.u * 9.42478), 0.0), 5.0) * 0.09 * smoothstep(0.05, 0.45, p.t) * (1.0 - 0.6 * p.t);
    col += float3(veins);
    col = mix(col, float3(0.66, 0.88, 0.98), budMix * 0.6);
    col *= 0.84 + 0.24 * ndl;
    float streak = powr(nh, 14.0);
    float glint = powr(nh, 70.0);
    float rimLit = powr(abs(p.u), 4.0) * powr(nh, 6.0) * 0.6;
    col = saturate(col + float3(0.94, 0.97, 1.0) * (streak * 0.30 + glint * 0.55 + rimLit));
    float alpha = mix(0.40, 0.80, smoothstep(0.05, 0.9, p.t)) + 0.16 * uu + budMix * 0.18;
    alpha = min(saturate(alpha + glint * 0.25), 0.95) * alphaScale;
    return float4(col, alpha);
}

// The two petals of a whorl nearest the fragment, the lower index on top (and petal n-1 over petal
// 0), so where petals overlap there is one seam, as in a real flower.
static float4 glassWhorl(float rho, float th, float n, float sector, float offset, float L, float halfWidth,
                         float px, float spin, float3 tip, float3 pale, float budMix, float cupping, float alphaScale)
{
    float i0 = round(th / sector - offset);
    float dth = th - (i0 + offset) * sector;
    float i1 = i0 + (dth >= 0.0 ? 1.0 : -1.0);
    GlassPetal pA = glassPetal(rho, th, i0, offset, sector, L, halfWidth, px, spin);
    GlassPetal pB = glassPetal(rho, th, i1, offset, sector, L, halfWidth, px, spin);
    float4 cA = glassPetalColor(pA, tip, pale, budMix, cupping, alphaScale);
    float4 cB = glassPetalColor(pB, tip, pale, budMix, cupping, alphaScale);
    float aA = cA.a * pA.a;
    float aB = cB.a * pB.a;
    float4 layerA = float4(cA.rgb * aA, aA);
    float4 layerB = float4(cB.rgb * aB, aB);
    float i0w = i0 - n * floor(i0 / n);
    float i1w = i1 - n * floor(i1 / n);
    bool aOnTop = (i1w == i0w + 1.0) || (i0w == n - 1.0 && i1w == 0.0);
    return aOnTop ? over(layerA, layerB) : over(layerB, layerA);
}

// A glass flower (premultiplied): an outer whorl of long petals, a shorter inner whorl turned half
// a petal, a pale glowing heart with fine glassy stamens instead of pollen, and a faint blue shadow.
static float4 glassFlower(FlowerOut in, float S, float px, float e)
{
    float v1 = fract(in.seed * 7.13 + 0.37);
    float v2 = fract(in.seed * 3.71 + 0.61);
    // Each flower faces the viewer a little differently: a touch wider than tall.
    float aspect = 0.78 + 0.17 * v1;
    float2 q = float2(in.q.x, in.q.y / aspect);
    float cs = cos(in.spin);
    float sn = sin(in.spin);
    float2 r = float2(cs * q.x - sn * q.y, sn * q.x + cs * q.y);
    float rho = length(r);
    float th = atan2(r.y, r.x);
    float n = in.petals;
    float sector = 6.2831853 / n;
    float budMix = 1.0 - smoothstep(0.05, 0.55, e);
    float3 tip = in.petal;
    float3 pale = mix(in.core, float3(1.0), 0.25);
    float3 paleInner = mix(pale, tip, 0.18);

    float halfWidth = 0.38 - 0.03 * (n - 5.0);
    float4 outer = glassWhorl(rho, th, n, sector, 0.0, S, halfWidth, px, in.spin, tip, pale, budMix, 0.55, 1.0);
    float4 inner = glassWhorl(rho, th, n, sector, 0.5, S * 0.58, 0.40, px, in.spin, mix(tip, pale, 0.25), paleInner,
                              budMix, 0.75, 0.75);

    float opened = smoothstep(0.10, 0.60, e);
    float rr = rho / max(S, 1e-4);
    float glowA = (1.0 - smoothstep(0.04, 0.40, rr)) * 0.62 * opened;
    float3 glowC = mix(in.core, float3(1.0), 0.5);

    float stamens = 10.0;
    float sec2 = 6.2831853 / stamens;
    float k = round(th / sec2 - v2);
    float dk = th - (k + v2) * sec2;
    float along = rho * cos(dk);
    float across = rho * sin(dk);
    float stLen = S * 0.30 * opened;
    float stW = S * 0.022;
    float aLine = saturate((stW - abs(across)) / px + 0.5) * saturate((stLen - along) / px + 0.5)
                * saturate((along - S * 0.05) / px + 0.5);
    float aDot = saturate((S * 0.045 - length(float2(along - stLen, across))) / px + 0.5);
    float aSt = max(aLine, aDot) * 0.85 * opened;
    float3 stC = mix(float3(0.98, 0.98, 1.0), tip, 0.22);
    float aCore = saturate((S * 0.07 - rho) / px + 0.5) * 0.9 * opened;
    float3 coreC = mix(in.core, float3(1.0), 0.6);

    float2 sq = in.q - float2(0.10, 0.14) * S;
    float shadowA = 0.14 * (1.0 - smoothstep(0.25 * S, 1.0 * S, length(sq))) * smoothstep(0.0, 0.3, e) * in.grow;

    float4 acc = float4(float3(0.30, 0.36, 0.70) * shadowA, shadowA);
    acc = over(outer, acc);
    acc = over(inner, acc);
    acc = over(float4(glowC * glowA, glowA), acc);
    acc = over(float4(stC * aSt, aSt), acc);
    acc = over(float4(coreC * aCore, aCore), acc);
    return acc;
}

fragment DecorOut flower_fragment(FlowerOut in [[stage_in]])
{
    float e = in.open;
    float c1 = 1.85;
    float em = e - 1.0;
    float ob = 1.0 + (c1 + 1.0) * em * em * em + c1 * em * em;
    float S = mix(0.28, 1.0, ob) * in.grow;
    float px = in.pxR;

    if (in.style > 2.5) {
        float4 glass = glassFlower(in, S, px, e);
        if (glass.a <= 0.003) {
            discard_fragment();
        }
        DecorOut og;
        og.color = glass;
        og.depth = in.depth;
        return og;
    }

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
