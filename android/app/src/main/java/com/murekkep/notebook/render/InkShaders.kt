package com.murekkep.notebook.render

// The ink shaders of the iPad app (Murekkep.swiftpm/InkShaders.swift) in GLSL ES 3.00, for the GL
// renderer (InkRenderer.kt, the twin of InkRenderer.swift). The same math, constants and branches for
// every pen, the paper styles and the shadows. The interface is the one android/PORTING.md sets out:
// the ribbon vertex attributes at locations 0-8, the stroke records in the RGBA32F texture
// `u_strokes` (3 texels a record, 512 records a row, read with texelFetch), the `u_` uniforms, GL's
// -1...1 clip depth (`gl_Position.z = zBase * 2.0 - 1.0`) with the 0...1 window depth written through
// `gl_FragDepth` where the Metal shaders returned a depth, premultiplied output.
//
// Beyond PORTING.md (the grass and the flowers had Metal buffers of their own):
// - `u_blades`: an RGBA32F texture, 4 texels a blade, 256 blades a row (width 1024), the fields of
//   `BladeGPU`: texel 0 = (base.x, base.y, height, width), texel 1 = (lean, phase, birth, depth),
//   texel 2 = color rgba, texel 3 = (stroke, kind, stiffness, 0). Blades draw as
//   glDrawArraysInstanced(GL_TRIANGLE_STRIP, 0, BLADE_VERTICES, bladeCount) with no attributes.
// - `u_flowers`: the same layout for `FlowerGPU`: texel 0 = (stem, radius, bloom, petals), texel 1 =
//   petal rgba, texel 2 = core rgba, texel 3 = (spin, style, 0, 0). A flower's `stem` indexes
//   `u_blades`. Flowers draw as glDrawArraysInstanced(GL_TRIANGLE_STRIP, 0, FLOWER_VERTICES, count).
// - `u_pointOffset` (uint): added to the blade index, as SegUniforms.pointOffset; 0 when the table
//   holds this draw's blades from its first record.
// - `u_texture`: the page picture of the texture program (a PDF page or a template).
// - Every float table needs GL_NEAREST filtering: an RGBA32F texture left at GL_LINEAR is incomplete
//   without OES_texture_float_linear and texelFetch reads zeros. The uint fields (brush, order,
//   stroke, kind, stem) are stored as whole-number floats.
// - The uint uniforms (u_orderOffset, u_depthOnly, u_pointOffset, u_style) are set with glUniform1ui.
//
// The Metal source is a Swift string; this is its Kotlin twin: `#version 300 es` is prepended in
// code so it is always the first line, then the shared prelude, then the program's own part.

/** The blend states of the iPad pipelines (InkRenderer.swift `Blend`), as GL calls. */
enum class Blend {
    /** No blending: glDisable(GL_BLEND). */
    OPAQUE,

    /**
     * Straight alpha, the iPad's `.alpha`: glEnable(GL_BLEND), glBlendEquation(GL_FUNC_ADD),
     * glBlendFuncSeparate(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA, GL_ONE, GL_ONE_MINUS_SRC_ALPHA)
     * (rgb: sourceAlpha / oneMinusSourceAlpha; alpha: one / oneMinusSourceAlpha).
     */
    ALPHA,

    /**
     * Premultiplied, the iPad's `.premultiplied`: glEnable(GL_BLEND), glBlendEquation(GL_FUNC_ADD),
     * glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA) (the same factors for rgb and alpha).
     */
    PREMULTIPLIED,

    /**
     * The highlighter's multiply, the iPad's `.multiply`: glEnable(GL_BLEND),
     * glBlendEquation(GL_FUNC_ADD), glBlendFuncSeparate(GL_DST_COLOR, GL_ZERO, GL_ZERO, GL_ONE)
     * (rgb: destinationColor / zero; alpha: zero / one, so the paper's alpha stays).
     */
    MULTIPLY,
}

/** One GL program: its vertex and fragment sources (complete, `#version` first) and its blend. */
data class ProgramSource(val name: String, val vertex: String, val fragment: String, val blend: Blend)

object InkShaders {
    /** Texels a stroke record takes in `u_strokes` (color; brush, birth, width, seed; order). */
    const val STROKE_RECORD_TEXELS = 3

    /** Stroke records a row of `u_strokes`; the texture is `STROKES_PER_ROW * STROKE_RECORD_TEXELS` wide. */
    const val STROKES_PER_ROW = 512

    /** Width in texels of `u_strokes`. */
    const val STROKE_TABLE_WIDTH = STROKES_PER_ROW * STROKE_RECORD_TEXELS

    /** Texels a blade or a flower record takes in `u_blades` / `u_flowers`. */
    const val DECOR_RECORD_TEXELS = 4

    /** Blade (or flower) records a row; the textures are `DECOR_PER_ROW * DECOR_RECORD_TEXELS` wide. */
    const val DECOR_PER_ROW = 256

    /** Width in texels of `u_blades` and `u_flowers`. */
    const val DECOR_TABLE_WIDTH = DECOR_PER_ROW * DECOR_RECORD_TEXELS

    /** Vertices of one blade's triangle strip: (BLADE_SEGS + 1) * 2, as `InkRenderer.bladeVertices`. */
    const val BLADE_VERTICES = 16

    /** Vertices of one flower's quad (a triangle strip from gl_VertexID). */
    const val FLOWER_VERTICES = 4

    /** Vertices of a page quad (a triangle strip from gl_VertexID). */
    const val QUAD_VERTICES = 4

    /** Every uniform any program may use, so a renderer can look their locations up in one loop. */
    val uniformNames: List<String> = listOf(
        "u_drawableSize", "u_viewOffset", "u_scale", "u_pixelSize", "u_time", "u_dryDuration",
        "u_waveTime", "u_coolDuration",
        "u_pageOrigin", "u_pointOffset", "u_orderOffset", "u_depthStep", "u_depthOnly",
        "u_rect", "u_uvRect", "u_pageSize", "u_style", "u_shadowRadius",
        "u_strokes", "u_blades", "u_flowers", "u_texture",
    )

    private const val VERSION = "#version 300 es\n"

    // MARK: shared prelude (every stage of every program)

    private val PRELUDE = """
        precision highp float;
        precision highp int;

        // Pens by their shading raw value (Brush.shading; the highlighter never reaches the ink shader).
        const uint BRUSH_PEN = 0u;
        const uint BRUSH_WET = 1u;
        const uint BRUSH_WAVE = 2u;
        const uint BRUSH_PENCIL = 4u;
        const uint BRUSH_CALLIGRAPHY = 5u;
        const uint BRUSH_WATERCOLOR = 6u;
        const uint BRUSH_NEON = 7u;
        const uint BRUSH_RAINBOW = 8u;
        const uint BRUSH_GLITTER = 9u;
        const uint BRUSH_GRASS = 10u;
        const uint BRUSH_SEA = 11u;
        const uint BRUSH_LAVA = 12u;
        const uint BRUSH_FOUNTAIN = 13u;
        const uint BRUSH_GOLD = 14u;
        const uint BRUSH_CHROME = 15u;
        const uint BRUSH_ICE = 16u;
        const uint BRUSH_JELLY = 17u;
        const uint BRUSH_GALAXY = 18u;
        const uint BRUSH_LIGHTNING = 19u;
        const uint BRUSH_PEARL = 20u;
        const uint BRUSH_IMPASTO = 21u;

        const vec3 kLight = vec3(-0.41941, -0.57919, 0.69902);
        const vec3 kHalf = vec3(-0.22752, -0.31420, 0.92169);

        // FrameUniforms
        uniform vec2 u_drawableSize;    // pixels
        uniform vec2 u_viewOffset;      // pixels: doc point P maps to P * scale + viewOffset
        uniform float u_scale;          // pixels per document point
        uniform float u_pixelSize;      // document points per pixel
        uniform float u_time;           // seconds since renderer start
        uniform float u_dryDuration;    // seconds until wet ink is dry
        uniform float u_waveTime;       // clock for animations (frozen when animation is off)
        uniform float u_coolDuration;   // seconds until lava has cooled into embers
        // SegUniforms
        uniform vec2 u_pageOrigin;      // document space (also QuadUniforms.pageOrigin)
        uniform uint u_pointOffset;     // first blade record of this draw
        uniform uint u_orderOffset;
        uniform float u_depthStep;
        uniform uint u_depthOnly;       // 1: write depth with a transparent color (the pass before a blend-once pass)
        // QuadUniforms
        uniform vec4 u_rect;            // document space x, y, w, h
        uniform vec4 u_uvRect;          // u0, v0, u1, v1
        uniform vec2 u_pageSize;
        uniform uint u_style;           // paper style
        uniform float u_shadowRadius;
        // Record tables (RGBA32F, GL_NEAREST)
        uniform highp sampler2D u_strokes;
        uniform highp sampler2D u_blades;
        uniform highp sampler2D u_flowers;

        // StrokeGPU: record k is at row k / 512, columns (k % 512) * 3 + j.
        struct StrokeRec {
            vec4 color;        // straight, not premultiplied
            uint brush;
            float birth;
            float width;
            float seed;
            uint order;        // place in the page's drawing order (its depth), apart from the record's slot
        };

        StrokeRec fetchStroke(uint k) {
            int col = int(k % 512u) * 3;
            int row = int(k / 512u);
            vec4 t1 = texelFetch(u_strokes, ivec2(col + 1, row), 0);
            vec4 t2 = texelFetch(u_strokes, ivec2(col + 2, row), 0);
            StrokeRec s;
            s.color = texelFetch(u_strokes, ivec2(col, row), 0);
            s.brush = uint(t1.x + 0.5);
            s.birth = t1.y;
            s.width = t1.z;
            s.seed = t1.w;
            s.order = uint(t2.x + 0.5);
            return s;
        }

        // BladeGPU: record k is at row k / 256, columns (k % 256) * 4 + j.
        struct BladeRec {
            vec2 base;         // page-local
            float height;
            float width;
            float lean;
            float phase;
            float birth;       // when it starts to grow (renderer clock)
            float depth;       // 0 front .. 1 back inside the stroke
            vec4 color;
            uint stroke;
            uint kind;         // 0 blade, 1 flower stem, 2 glass stem, 3 glass leaf (the flowering water)
            float stiffness;
        };

        BladeRec fetchBlade(uint k) {
            int col = int(k % 256u) * 4;
            int row = int(k / 256u);
            vec4 t0 = texelFetch(u_blades, ivec2(col, row), 0);
            vec4 t1 = texelFetch(u_blades, ivec2(col + 1, row), 0);
            vec4 t2 = texelFetch(u_blades, ivec2(col + 2, row), 0);
            vec4 t3 = texelFetch(u_blades, ivec2(col + 3, row), 0);
            BladeRec b;
            b.base = t0.xy;
            b.height = t0.z;
            b.width = t0.w;
            b.lean = t1.x;
            b.phase = t1.y;
            b.birth = t1.z;
            b.depth = t1.w;
            b.color = t2;
            b.stroke = uint(t3.x + 0.5);
            b.kind = uint(t3.y + 0.5);
            b.stiffness = t3.z;
            return b;
        }

        // FlowerGPU: the same layout as the blades.
        struct FlowerRec {
            uint stem;
            float radius;
            float bloom;       // when the bud starts to open (renderer clock)
            float petals;
            vec4 petal;
            vec4 core;
            float spin;
            float style;
        };

        FlowerRec fetchFlower(uint k) {
            int col = int(k % 256u) * 4;
            int row = int(k / 256u);
            vec4 t0 = texelFetch(u_flowers, ivec2(col, row), 0);
            vec4 t3 = texelFetch(u_flowers, ivec2(col + 3, row), 0);
            FlowerRec f;
            f.stem = uint(t0.x + 0.5);
            f.radius = t0.y;
            f.bloom = t0.z;
            f.petals = t0.w;
            f.petal = texelFetch(u_flowers, ivec2(col + 1, row), 0);
            f.core = texelFetch(u_flowers, ivec2(col + 2, row), 0);
            f.spin = t3.x;
            f.style = t3.y;
            return f;
        }

        vec2 docToNDC(vec2 doc) {
            vec2 px = doc * u_scale + u_viewOffset;
            return vec2(px.x / u_drawableSize.x * 2.0 - 1.0, 1.0 - px.y / u_drawableSize.y * 2.0);
        }

        float wetness(float birth) {
            float age = u_time - birth;
            return 1.0 - smoothstep(0.0, max(u_dryDuration, 0.01), age);
        }

        float hash21(vec2 p) {
            p = fract(p * vec2(123.34, 456.21));
            p += dot(p, p + 45.32);
            return fract(p.x * p.y);
        }

        vec2 hash22(vec2 p) {
            vec2 q = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
            return fract(sin(q) * 43758.5453);
        }

        float valueNoise(vec2 p) {
            vec2 i = floor(p);
            vec2 f = fract(p);
            vec2 u = f * f * (3.0 - 2.0 * f);
            float a = hash21(i);
            float b = hash21(i + vec2(1.0, 0.0));
            float c = hash21(i + vec2(0.0, 1.0));
            float d = hash21(i + vec2(1.0, 1.0));
            return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
        }

        float fbm(vec2 p) {
            float v = 0.0;
            float a = 0.5;
            for (int i = 0; i < 4; i++) {
                v += a * valueNoise(p);
                p = vec2(0.8 * p.x - 0.6 * p.y, 0.6 * p.x + 0.8 * p.y) * 2.03 + vec2(17.1, 9.2);
                a *= 0.5;
            }
            return v;
        }

        // Voronoi cell border distance and cell ID hash: x = edge distance (0 on cracks), y = center distance, z = cell hash
        vec3 voronoiDetail(vec2 p, float drift) {
            vec2 i = floor(p);
            vec2 f = fract(p);
            float d1 = 8.0;
            float d2 = 8.0;
            float id = 0.0;
            for (int y = -1; y <= 1; y++) {
                for (int x = -1; x <= 1; x++) {
                    vec2 g = vec2(float(x), float(y));
                    vec2 h = hash22(i + g);
                    vec2 o = drift > 0.0 ? (0.5 + 0.42 * sin(drift + 6.2831853 * h)) : (0.15 + 0.7 * h);
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
            return vec3(d2 - d1, d1, id);
        }

        float cellEdge(vec2 p) {
            return voronoiDetail(p, 0.0).x;
        }

        float waterCells(vec2 p, float t) {
            return voronoiDetail(p, t).x;
        }

        // Studio environment for metals & water reflection
        vec3 envColor(vec3 R, vec3 tint) {
            float y = -R.y;
            vec3 sky = mix(vec3(0.86, 0.93, 1.0), vec3(0.32, 0.56, 0.92), clamp(y * 1.4, 0.0, 1.0));
            vec3 ground = mix(vec3(0.42, 0.36, 0.30), vec3(0.08, 0.08, 0.10), clamp(-y * 1.8, 0.0, 1.0));
            vec3 c = y > 0.0 ? sky : ground;
            c = mix(c, vec3(1.0), exp(-abs(y) * 20.0) * 0.88);
            return c * tint;
        }

        vec3 reflectView(vec3 N) {
            return vec3(2.0 * N.z * N.x, 2.0 * N.z * N.y, 2.0 * N.z * N.z - 1.0);
        }

        vec3 rgb2hsv(vec3 c) {
            vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
            vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
            vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
            float d = q.x - min(q.w, q.y);
            float e = 1.0e-10;
            return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
        }

        vec3 hsv2rgb(vec3 c) {
            vec3 p = abs(fract(c.xxx + vec3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
            return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
        }

        float glowExtra(uint brush, float r) {
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

        float shadowHeight(StrokeRec s) {
            uint b = s.brush;
            if (b == BRUSH_WAVE || b == BRUSH_PEARL) {
                return 1.0;
            } else if (b == BRUSH_WET) {
                return wetness(s.birth);
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

        // Grass blades (shared by the blade and flower vertex shaders)
        float bladeGrowth(float time, float birth) {
            float g = clamp((time - birth) / 0.5, 0.0, 1.0);
            float k = 1.0 - g;
            return 1.0 - k * k * k;
        }

        float bladeSway(BladeRec b) {
            float t = u_waveTime;
            return sin(t * (1.1 + 0.9 * b.stiffness) + b.phase + b.base.x * 0.045) * 0.6
                 + sin(t * 2.7 + b.phase * 1.9 + b.base.y * 0.03) * 0.25;
        }

        vec2 bladeAt(BladeRec b, float s, float grow, float sway, out vec2 tangent) {
            float h = b.height * grow;
            float bend = b.lean * grow + sway * h * 0.16;
            tangent = vec2(2.0 * bend * s, -h);
            return b.base + vec2(bend * s * s, -h * s);
        }
    """.trimIndent()

    // MARK: ribbon vertex shaders

    /** RibbonOut as varyings; `q` is "out" in the vertex stage, "in" in the fragment stage. */
    private fun ribbonVaryings(q: String) = """
        $q vec2 v_local;
        $q vec2 v_n2;
        $q vec2 v_tangent;
        $q float v_u;
        $q float v_side;
        $q float v_r;
        $q float v_arc;
        $q float v_ink;
        flat $q float v_h;
        $q float v_blur;
        flat $q uint v_stroke;
        flat $q float v_zBase;
    """.trimIndent()

    private val RIBBON_VERTEX_COMMON = """
        // RibbonVertexGPU (48 bytes, one interleaved VBO per page)
        layout(location = 0) in vec2 a_center;     // point on the stroke's centerline (page-local)
        layout(location = 1) in vec2 a_offset;     // unit direction to this vertex: normal (body) or radial (caps); 0 at cap centers
        layout(location = 2) in vec2 a_tangent;    // drawing direction
        layout(location = 3) in float a_r;         // radius
        layout(location = 4) in float a_u;         // signed across coordinate: +1 left edge, -1 right edge, +1 cap rim, 0 center
        layout(location = 5) in float a_side;      // across direction: +1 left edge, -1 right edge, cos(angle) on cap rims
        layout(location = 6) in float a_arc;       // distance along the stroke (cap rims: the end's value; the shader extends it)
        layout(location = 7) in float a_ink;       // pooling / graphite density
        layout(location = 8) in uint a_stroke;     // glVertexAttribIPointer
    """.trimIndent() + "\n\n" + ribbonVaryings("out") + "\n\n" + """
        void makeRibbon(uint rank, float extra, vec2 shift) {
            float r = max(a_r, 1e-4);
            float ext = r + extra + 2.0 * u_pixelSize;
            vec2 p = a_center + shift + a_offset * ext;
            float order = float(u_orderOffset + rank);
            float zBase = 1.0 - (order + 1.0) * u_depthStep;
            v_zBase = zBase;
            gl_Position = vec4(docToNDC(u_pageOrigin + p), zBase * 2.0 - 1.0, 1.0);
            v_local = p;
            v_n2 = a_u < 0.0 ? -a_offset : a_offset;
            v_tangent = a_tangent;
            v_u = a_u * ext / r;
            v_side = a_side * ext / r;
            v_r = r;
            v_arc = a_arc + dot(a_offset, a_tangent) * ext;
            v_ink = a_ink;
            v_stroke = a_stroke;
            v_h = 0.0;
            v_blur = 0.0;
        }
    """.trimIndent()

    /** ribbon_vertex: the ink and the highlighter. */
    private val RIBBON_VERTEX_MAIN = """
        void main() {
            StrokeRec s = fetchStroke(a_stroke);
            makeRibbon(s.order, glowExtra(s.brush, a_r), vec2(0.0));
        }
    """.trimIndent()

    /** ribbon_shadow_vertex. */
    private val SHADOW_VERTEX_MAIN = """
        void main() {
            StrokeRec s = fetchStroke(a_stroke);
            float h = shadowHeight(s);
            float blur = 0.55 * a_r + u_pixelSize;
            makeRibbon(s.order, blur, vec2(0.30, 0.42) * (a_r * h));
            float zBase = 1.0 - float(u_orderOffset + 1u) * u_depthStep;
            v_zBase = zBase;
            gl_Position.z = zBase * 2.0 - 1.0;
            v_h = h;
            v_blur = blur;
            if (h < 0.002) {
                gl_Position = vec4(-2.0, -2.0, 0.0, 1.0);
            }
        }
    """.trimIndent()

    // MARK: ribbon fragment shaders

    private val RIBBON_FRAGMENT_COMMON = ribbonVaryings("in") + "\n\n" + """
        layout(location = 0) out vec4 fragColor;

        struct StrokeFrag {
            float r;
            float d;
            float x;
            vec2 n2;
            float sq;
        };

        StrokeFrag strokeFrag() {
            StrokeFrag f;
            f.r = max(v_r, 1e-4);
            f.d = abs(v_u) * f.r;
            f.x = clamp(abs(v_u), 0.0, 1.0);
            float nl = length(v_n2);
            f.n2 = (nl > 1e-4 ? v_n2 / nl : vec2(0.0)) * (v_u < 0.0 ? -1.0 : 1.0);
            f.sq = sqrt(clamp(1.0 - f.x * f.x, 0.0, 1.0));
            return f;
        }
    """.trimIndent()

    /** The ink fragment's shading helpers (only the ink program compiles them). */
    private val INK_SHADING = """
        // The ocean pen's swell seen from above: three trains of rounded crests crossing the page at fixed
        // angles, the wavelength following the line's width so thin and thick water read alike. Returns the
        // height (0 trough .. 1 crest) and its gradient in page space (height units per point).
        float swellField(vec2 P, float t, float L, float seed, out vec2 grad) {
            const vec2 d0 = vec2(0.86, 0.51);
            const vec2 d1 = vec2(-0.34, 0.94);
            float k0 = 6.2831853 / L;
            float k1 = 6.2831853 / (L * 0.55);
            float s0 = dot(P, d0) * k0 - 1.15 * t + seed;
            float s1 = dot(P, d1) * k1 - 1.75 * t + seed * 2.3 + 1.7;
            float u0 = max(0.5 + 0.5 * sin(s0), 1e-3);
            float u1 = max(0.5 + 0.5 * sin(s1), 1e-3);
            float W = 0.68 * pow(u0, 1.8) + 0.32 * pow(u1, 2.0);
            grad = d0 * (0.68 * 0.9 * k0 * pow(u0, 0.8) * cos(s0))
                 + d1 * (0.32 * 1.0 * k1 * u1 * cos(s1));
            return W;
        }

        vec3 shadeWet(vec3 base, float x, vec2 n2, float sq, float ink, float w) {
            float A = mix(0.10, 0.56, w) * mix(0.82, 1.45, ink);
            float slope = min(A * x / max(sq, 0.07), 5.5);
            float rimDx = (x - 0.82) / 0.12;
            float rimTension = exp(-rimDx * rimDx) * 0.22 * w;
            vec3 N = normalize(vec3(n2 * (slope + rimTension), 1.0));

            float lum = dot(base, vec3(0.3, 0.59, 0.11));
            vec3 richBase = clamp(vec3(lum) + (base - vec3(lum)) * mix(1.08, 1.38, w), 0.0, 1.0);
            vec3 col = richBase * mix(0.96, 0.64, w * (0.55 + 0.45 * sq));

            float ring = (1.0 - 0.45 * w) * 0.36 * smoothstep(0.55, 0.96, x);
            float poolDark = smoothstep(0.45, 1.0, ink) * 0.28 * sq;
            col *= (1.0 - ring - poolDark);

            vec3 hsv = rgb2hsv(base);
            vec3 sheenTint = hsv2rgb(vec3(fract(hsv.x + 0.42), 0.85, 1.0));
            float sheenFactor = smoothstep(0.45, 0.95, ink) * pow(clamp(dot(N, kHalf), 0.0, 1.0), 10.0) * smoothstep(0.25, 0.85, x);
            col = mix(col, sheenTint, sheenFactor * mix(0.22, 0.45, w));

            float ndl = dot(N, kLight);
            col *= 1.0 + 0.55 * (ndl - kLight.z);
            col *= mix(1.0, 0.50 + 0.50 * N.z, w);

            float fresnel = pow(clamp(1.0 - N.z, 0.0, 1.0), 3.0) * w;
            col = mix(col, envColor(reflectView(N), vec3(1.0)), fresnel * 0.32);

            float nh = clamp(dot(N, kHalf), 0.0, 1.0);
            float spec = pow(nh, mix(36.0, 140.0, w)) * mix(0.10, 1.45, w)
                       + pow(nh, 18.0) * 0.14 * w;

            float rx = 2.0 * N.z * N.x;
            float ry = 2.0 * N.z * N.y;
            float win = smoothstep(0.04, 0.18, -rx) * (1.0 - smoothstep(0.28, 0.46, -rx))
                      * smoothstep(0.06, 0.20, -ry) * (1.0 - smoothstep(0.34, 0.54, -ry));
            float bounce = smoothstep(0.22, 0.58, rx * 0.6 + ry * 0.8) * 0.22 * w;
            return clamp(col + vec3(spec + win * 0.85 * w + bounce), 0.0, 1.0);
        }

        // The ocean pen: a pool of sea seen from above. Turquoise shallows at the shore deepening to the
        // ink's blue in the middle, a swell whose lit and shadowed faces roll across the line, caustic nets
        // drifting over the bed, lace on the breaking crests and a thin white edge where the water meets
        // the shore. Every pattern is sized from the line's width and blurred by the pixel size, so a thin
        // line is smooth glossy water with soft bands of light rather than speckle.
        vec3 shadeWave(vec3 base, float x, vec2 n2, float sq, vec2 P, float t, float rN, float px, float seed) {
            float L = max(rN * 3.0, 9.0);
            vec2 g;
            float hN = swellField(P, t, L, seed, g);
            float slope = min(0.30 * x / max(sq, 0.12), 2.5);
            float amp = rN * 0.30 * (0.5 + 0.5 * sq);
            vec3 N = normalize(vec3(n2 * slope - g * amp, 1.0));
            float detail = smoothstep(2.0, 6.0, rN / px);

            float depth = clamp(pow(max(sq, 1e-4), 0.8) * (0.9 - 0.25 * hN), 0.0, 1.0);
            vec3 deep = base * vec3(0.20, 0.36, 0.64);
            vec3 mid = mix(base, vec3(0.06, 0.62, 0.80), 0.52);
            vec3 shallow = mix(base, vec3(0.40, 0.94, 0.88), 0.74);
            vec3 col = depth < 0.5 ? mix(shallow, mid, depth * 2.0) : mix(mid, deep, (depth - 0.5) * 2.0);
            // The swell: light through the rising crests, the troughs deeper, lit and shadowed faces.
            col = mix(col, mix(shallow, vec3(0.55, 0.95, 0.92), 0.4), smoothstep(0.55, 1.0, hN) * 0.40 * (1.0 - 0.3 * depth));
            col *= (0.82 + 0.18 * hN) * (0.92 + 0.45 * (dot(N, kLight) - kLight.z));

            float cs = max(rN * 0.9, 2.8);
            float aa = px / cs;
            vec2 cq = P / cs + g * 0.5 + seed * 11.0;
            float e1 = waterCells(cq, t * 1.1);
            float e2 = waterCells(cq * 1.9 + vec2(4.2, -3.1), -t * 1.5 + 1.5);
            float caust = pow(clamp(1.0 - e1 / (0.24 + aa * 2.0), 0.0, 1.0), 1.6) * 0.30
                        + pow(clamp(1.0 - e2 / (0.18 + aa * 2.4), 0.0, 1.0), 1.6) * 0.16;
            col += vec3(0.60, 0.97, 1.0) * caust * detail * smoothstep(0.15, 0.6, depth) * 0.55;

            float fresnel = pow(clamp(1.0 - N.z, 0.0, 1.0), 2.6);
            col = mix(col, envColor(reflectView(N), vec3(0.88, 0.96, 1.0)), fresnel * 0.35);

            float fn = valueNoise(P / max(rN * 0.9, 2.0) * 1.3 + t * 0.4 + seed * 5.0);
            float web = 1.0 - smoothstep(0.0, 0.18 + aa * 1.5, waterCells(P / max(rN * 0.6, 2.5) + seed * 3.0, t * 1.9));
            float crest = smoothstep(0.80, 0.97, hN + (fn - 0.5) * 0.20) * (0.35 + 0.65 * web) * detail;
            float shore = smoothstep(0.84, 0.97, x + 0.04 * sin(P.x * 0.5 + P.y * 0.4 - t * 2.0) + 0.04 * hN) * (0.5 + 0.5 * web);
            float foam = clamp(crest * 0.85 + shore * 0.65, 0.0, 1.0);
            col = mix(col, vec3(0.97, 0.995, 1.0), foam);

            float nh = clamp(dot(N, kHalf), 0.0, 1.0);
            float spec = pow(nh, 90.0) * 0.9 * (1.0 - foam * 0.6) + pow(nh, 400.0) * 1.2 + pow(nh, 20.0) * 0.12;
            return clamp(col + vec3(spec), 0.0, 1.0);
        }

        // The sea pen's waves: three trains rolling along the line with the current, their crests a little
        // oblique, the wavelength following the line's width. Returns the height (0 trough .. 1 crest) and
        // the slope along and across the line (height units per point).
        float seaSwell(float arc, float v, float t, float L, float seed, out vec2 slope) {
            float k0 = 6.2831853 / L;
            float k1 = 6.2831853 / (L * 0.62);
            float k2 = 6.2831853 / (L * 0.41);
            float p0 = k0 * (arc + v * 0.35) - 3.0 * t + seed * 3.1;
            float p1 = k1 * (arc - v * 0.28) - 3.8 * t + seed * 4.8 + 1.3;
            float p2 = k2 * (arc + v * 0.15) - 4.6 * t + seed * 6.5 + 2.9;
            float w0 = max(0.5 + 0.5 * sin(p0), 1e-3);
            float w1 = max(0.5 + 0.5 * sin(p1), 1e-3);
            float w2 = max(0.5 + 0.5 * sin(p2), 1e-3);
            float g0 = 0.55 * 0.8 * pow(w0, 0.6) * cos(p0) * k0;
            float g1 = 0.30 * 0.9 * pow(w1, 0.8) * cos(p1) * k1;
            float g2 = 0.15 * 1.0 * w2 * cos(p2) * k2;
            slope = vec2(g0 + g1 + g2, g0 * 0.35 - g1 * 0.28 + g2 * 0.15);
            return 0.55 * pow(w0, 1.6) + 0.30 * pow(w1, 1.8) + 0.15 * pow(w2, 2.0);
        }

        vec3 tubeLight(vec3 col, vec2 n2, float x, float sq, float gloss, float strength) {
            vec3 N = normalize(vec3(n2 * (x / max(sq, 0.15)) * strength, 1.0));
            float ndl = dot(N, kLight);
            col *= 1.0 + 0.48 * (ndl - kLight.z);
            float spec = pow(clamp(dot(N, kHalf), 0.0, 1.0), 48.0) * gloss;
            return clamp(col + vec3(spec), 0.0, 1.0);
        }

        // The lava's temperature ramp, built from the ink's own hue: a dark, redder skin, the ink colour at
        // full glow, a paler yellower blaze, then white heat.
        vec3 lavaRamp(vec3 skin, vec3 glow, vec3 blaze, float temp) {
            vec3 c = mix(skin, glow, smoothstep(0.0, 0.42, temp));
            c = mix(c, blaze, smoothstep(0.50, 0.82, temp));
            return mix(c, vec3(1.0, 0.98, 0.92), smoothstep(0.86, 1.0, temp));
        }
    """.trimIndent()

    /** ink_fragment. */
    private val INK_FRAGMENT_MAIN = """
        void main() {
            StrokeFrag sf = strokeFrag();
            float r = sf.r;
            float d = sf.d;
            float x = sf.x;
            vec2 n2 = sf.n2;
            float sq = sf.sq;
            StrokeRec s = fetchStroke(v_stroke);
            float px = u_pixelSize;
            float ink = v_ink;
            float arc = v_arc;
            vec2 P = v_local;
            float tl = length(v_tangent);
            vec2 tdir = tl > 1e-4 ? v_tangent / tl : vec2(1.0, 0.0);
            float across = v_side;
            float sacross = clamp(across, -1.0, 1.0);

            vec3 col = s.color.rgb;
            float alpha;
            float alphaScale = 1.0;

            if (s.brush == BRUSH_SEA) {
                // A sea flowing along the line: the water, its caustic nets and foam all slide with the
                // current, waves roll along it, turquoise shallows and breaking foam line both shores and the
                // shoreline itself surges with the waves. Patterns are sized from the line's set width and
                // blurred by the pixel size, so thin handwriting stays a smooth banded line with a foamy rim.
                float t = u_waveTime;
                float rN = max(s.width * 0.5, 0.5);
                float L = max(rN * 2.4, 7.0);
                float detail = smoothstep(2.0, 6.0, rN / px);
                float u = arc - t * rN * 1.5;
                float v = sacross * r;
                vec2 slope;
                float hN = seaSwell(arc, v, t, L, s.seed, slope);

                float side = sacross < 0.0 ? -1.0 : 1.0;
                float surge = sin(arc / L * 6.2831853 - 2.6 * t + s.seed * 5.0 + side * 1.6);
                float rDyn = r * (0.97 + 0.06 * surge + 0.05 * hN);
                float cov = clamp((rDyn - d) / (px * 1.2) + 0.5, 0.0, 1.0);
                if (cov <= 0.0) {
                    discard;
                }
                float xDyn = clamp(d / max(rDyn, 1e-4), 0.0, 1.0);
                float sqDyn = sqrt(clamp(1.0 - xDyn * xDyn, 0.0, 1.0));

                vec2 nLeft = vec2(-tdir.y, tdir.x);
                vec2 slopeP = slope.x * tdir + slope.y * nLeft;
                vec3 N = normalize(vec3(-slopeP * (rN * 0.45) + n2 * (xDyn / max(sqDyn, 0.18)) * 0.35, 1.0));

                vec3 base = s.color.rgb;
                vec3 deep = base * vec3(0.20, 0.38, 0.68);
                vec3 midSea = mix(base, vec3(0.05, 0.66, 0.78), 0.58);
                vec3 shallow = mix(base, vec3(0.36, 0.96, 0.88), 0.78);
                float depth = smoothstep(0.45, 1.0, sqDyn * (0.88 - 0.22 * hN)) * (0.65 + 0.35 * detail);
                vec3 water = depth < 0.5 ? mix(shallow, midSea, depth * 2.0) : mix(midSea, deep, (depth - 0.5) * 2.0);
                water = mix(water, mix(shallow, vec3(0.50, 0.96, 0.90), 0.4), smoothstep(0.55, 1.0, hN) * 0.50 * (1.0 - 0.3 * depth));
                water *= (0.78 + 0.22 * hN) * (0.92 + 0.50 * (dot(N, kLight) - kLight.z));

                float cs = max(rN * 0.9, 3.0);
                float aa = px / cs;
                vec2 cq = vec2(u, v) / cs + slope * 0.6 + s.seed * 11.0;
                float e1 = waterCells(cq, t * 1.3);
                float e2 = waterCells(cq * 1.8 + vec2(3.1, 7.7), -t * 1.6 + 2.0);
                float caust = pow(clamp(1.0 - e1 / (0.28 + aa * 2.2), 0.0, 1.0), 1.6) * 0.25
                            + pow(clamp(1.0 - e2 / (0.20 + aa * 2.6), 0.0, 1.0), 1.6) * 0.12;
                water += vec3(0.60, 0.97, 1.0) * caust * detail * smoothstep(0.25, 0.7, depth) * 0.7;

                float fresnel = pow(clamp(1.0 - N.z, 0.0, 1.0), 2.6);
                water = mix(water, envColor(reflectView(N), vec3(0.88, 0.96, 1.0)), fresnel * 0.32);

                float fw = max(rN * 0.5, 1.0);
                vec3 vF = voronoiDetail(vec2(u / fw, sacross * 3.0) * 1.2 + s.seed * 3.0, t * 2.0);
                float web = 1.0 - smoothstep(0.0, 0.18 + (px / fw) * 1.5, vF.x);
                float fn = valueNoise(vec2(u / max(rN * 0.8, 1.5), sacross * 2.0) + s.seed * 7.0);
                float shoreLine = 0.70 + 0.09 * surge + 0.10 * (fn - 0.5);
                float shoreFoam = smoothstep(shoreLine - 0.16, shoreLine + 0.04, xDyn) * (0.55 + 0.45 * web) * (0.55 + 0.45 * detail);
                float edgeLine = smoothstep(0.90, 0.985, xDyn) * 0.8;
                float streak = valueNoise(vec2(u / max(rN * 1.6, 2.0), sacross * 5.0) + s.seed * 4.0);
                float spill = smoothstep(0.40, 0.90, xDyn) * smoothstep(0.55, 0.85, streak) * 0.45 * detail;
                float cap = smoothstep(0.72, 0.95, hN + (fn - 0.5) * 0.25) * (0.35 + 0.65 * web) * detail;
                float foam = clamp(max(shoreFoam * 0.9, edgeLine) + spill + cap * 0.65, 0.0, 1.0);
                vec3 foamColor = vec3(0.96, 0.99, 1.0) * (0.90 + 0.12 * dot(N, kLight));
                water = mix(water, foamColor, foam);

                float nh = clamp(dot(N, kHalf), 0.0, 1.0);
                float glint = pow(nh, 120.0) * 1.2 * (1.0 - foam * 0.6) + pow(nh, 400.0) * 1.0 + pow(nh, 24.0) * 0.14;
                col = clamp(water + vec3(glint), 0.0, 1.0);
                alpha = cov * s.color.a;
            } else if (s.brush == BRUSH_LAVA) {
                // Cools from where the pen started: each point starts cooling a little after the one before,
                // at drawing speed (380 pt/s, as InkRenderer.lavaCoolSpeed), counted from when the pen lifted.
                float age = u_time - (s.birth + max(arc, 0.0) / 380.0);
                float heat = 1.0 - smoothstep(0.0, max(u_coolDuration, 0.5), age);

                float heat2 = heat * heat;
                // Textures are scaled by the stroke's set width, not the pressure-varied radius, so they
                // do not bunch up where the pen pressed lighter.
                float rN = max(s.width * 0.5, 0.5);

                // Molten lava spills a little past its line; the set crust keeps the shape. A warm glow
                // lights the paper around it while it is hot, and faintly from the embers after.
                float edgeJag = (valueNoise(vec2(arc / rN * 0.9, sacross * 1.5) + s.seed * 19.0) - 0.5)
                              * r * 0.09 * (0.6 + 0.4 * heat);
                float rLava = r + edgeJag;
                float body = clamp((rLava - d) / px + 0.5, 0.0, 1.0);
                float past = max(d - rLava, 0.0) / max(r, 0.5);
                float glowA = (1.0 - body) * (0.06 + 0.55 * heat) * exp(-2.4 * past) * clamp(1.0 - past / 1.4, 0.0, 1.0);
                if (body <= 0.0 && glowA <= 0.002) {
                    discard;
                }
                float xL = clamp(d / max(rLava, 1e-4), 0.0, 1.0);
                float sqL = sqrt(clamp(1.0 - xL * xL, 0.0, 1.0));

                // The flow slides along the line while hot and freezes as it sets.
                float flowShift = mix(s.birth * 0.45 + u_coolDuration * 0.25, u_waveTime * 0.5, heat2);
                vec2 fq = vec2(arc / rN * 0.5 - flowShift, sacross * 1.1) + s.seed * 13.0;
                float n1 = fbm(fq);
                float rope = 0.5 + 0.5 * sin(fq.y * 5.5 + n1 * 6.0 + fq.x * 2.0);

                // Temperature: hottest down the middle, pulled into ropy streaks by the flow.
                float temp = clamp(0.18 + 0.48 * sqL + (n1 - 0.5) * 0.8 + rope * 0.2 * sqL, 0.0, 1.0);

                vec3 hsvL = rgb2hsv(s.color.rgb);
                vec3 skin = hsv2rgb(vec3(fract(hsvL.x - 0.035), min(hsvL.y * 1.15 + 0.1, 1.0), hsvL.z * 0.38));
                vec3 glow = hsv2rgb(vec3(hsvL.x, hsvL.y, max(hsvL.z, 0.85)));
                vec3 blaze = hsv2rgb(vec3(fract(hsvL.x + 0.055), hsvL.y * 0.55, 1.0));
                vec3 molten = lavaRamp(skin, glow, blaze, temp);

                // A viscous, faintly glossy surface.
                vec2 bump = vec2(valueNoise(fq * 2.3 + 5.0) - 0.5, valueNoise(fq * 2.3 + 9.0) - 0.5) * 0.5;
                vec3 Nm = normalize(vec3(n2 * (xL / max(sqL, 0.2)) * 0.6 + bump * sqL, 1.0));
                float nhM = clamp(dot(Nm, kHalf), 0.0, 1.0);
                molten = molten * (0.9 + 0.2 * clamp(dot(Nm, kLight), 0.0, 1.0))
                       + (pow(nhM, 22.0) * 0.18 + pow(nhM, 90.0) * 0.35) * vec3(1.0, 0.98, 0.9) * (0.4 + 0.6 * heat);

                // The crust: basalt plates, sized from the line's width, with the cracks between them glowing.
                float cell = max(rN * 0.95, 2.6);
                vec2 pq = vec2(arc, sacross * r) / cell + s.seed * 7.0;
                vec3 plate = voronoiDetail(pq, 0.0);
                float aa = px / cell;
                float cw = mix(0.075, 0.16, heat) + aa * 0.5;
                float crack = 1.0 - smoothstep(cw - aa, cw + aa, plate.x);
                float crustProgress = (1.0 - heat) * 1.35 - 0.2 + (valueNoise(pq * 0.7 + 3.0) - 0.5) * 0.45 + xL * 0.18;
                float crustRaw = smoothstep(0.0, 0.5, crustProgress);
                float crust = crustRaw * (1.0 - crack);

                float grain = valueNoise(P * 1.4 + s.seed) - 0.5;
                float plateAO = smoothstep(0.0, 0.26, plate.x);
                vec3 rock = vec3(0.115, 0.10, 0.10) + plate.z * vec3(0.035, 0.025, 0.02) + grain * smoothstep(3.0, 7.0, rN / px) * 0.08;
                vec3 Nr = normalize(vec3(n2 * (xL / max(sqL, 0.2)) * 0.75, 1.0));
                rock *= (0.55 + 0.75 * clamp(dot(Nr, kLight), 0.0, 1.0)) * (0.55 + 0.45 * plateAO);
                rock += pow(clamp(dot(Nr, kHalf), 0.0, 1.0), 14.0) * 0.07;

                // Embers keep burning in the cracks after the rock has set.
                float pulse = 0.5 + 0.5 * sin(u_waveTime * 1.6 + plate.z * 6.28);
                vec3 ember = lavaRamp(skin, glow, blaze, mix(0.08 + 0.20 * pulse + 0.25 * plate.z, temp, heat));
                vec3 inside = mix(molten, ember, crustRaw);
                vec3 bodyCol = mix(inside, rock, crust);
                float rim = crustRaw * (1.0 - crustRaw) * 4.0 * heat;
                bodyCol = mix(bodyCol, glow, rim * 0.3);

                alpha = body + glowA;
                col = clamp((bodyCol * body + mix(glow, blaze, 0.35) * glowA) / max(alpha, 1e-4), 0.0, 1.0);
                alpha *= s.color.a;
            } else if (s.brush == BRUSH_JELLY) {
                float wob = sin(P.x * 0.25 + P.y * 0.18 + u_waveTime * 3.2) * 0.5
                          + sin(P.x * 0.11 - P.y * 0.30 + u_waveTime * 2.1) * 0.5;
                float rr = r * (1.0 + 0.06 * wob);
                float cov = clamp((rr - d) / px + 0.5, 0.0, 1.0);
                if (cov <= 0.0) {
                    discard;
                }
                float xr = clamp(d / max(rr, 1e-4), 0.0, 1.0);
                float sqr = sqrt(clamp(1.0 - xr * xr, 0.0, 1.0));
                vec3 N = normalize(vec3(n2 * (xr / max(sqr, 0.14)) * 0.88, 1.0));
                vec3 base = s.color.rgb;
                vec3 gel = mix(base * 0.52, mix(base, vec3(1.0), 0.30), sqr * 0.75 + 0.15);
                gel += base * 0.40 * smoothstep(0.50, 0.95, xr);
                float spec = pow(clamp(dot(N, kHalf), 0.0, 1.0), 65.0) * 1.15;
                float blob = smoothstep(0.72, 0.95, dot(normalize(vec3(n2 * xr, max(sqr, 0.05))), normalize(vec3(-0.45, -0.6, 0.66))));
                col = clamp(gel + vec3(spec + blob * 0.48), 0.0, 1.0);
                alpha = cov * (0.78 + 0.18 * xr) * s.color.a;
            } else if (s.brush == BRUSH_LIGHTNING) {
                float flick = u_waveTime * 15.0;
                float along = arc / max(r, 0.5);
                float jitter1 = (valueNoise(vec2(along * 1.35, floor(flick))) - 0.5) * 1.35
                              + (valueNoise(vec2(along * 4.2 + 7.0, floor(flick * 1.7))) - 0.5) * 0.55;
                float jitter2 = (valueNoise(vec2(along * 2.1 + 19.0, floor(flick * 1.3))) - 0.5) * 1.6;
                float fd1 = abs(across * r - jitter1 * r * 0.72);
                float fd2 = abs(across * r - jitter2 * r * 0.85);
                // In the round caps |u| > |side|: the distance past the end point. The bolt stops at the
                // pen tip instead of shooting ahead of it; only the soft glow goes round the tip.
                float beyond = sqrt(max(v_u * v_u - v_side * v_side, 0.0)) * r;
                float atTip = 1.0 - smoothstep(0.0, r * 0.3, beyond);
                float core = ((1.0 - smoothstep(r * 0.13, r * 0.13 + px * 1.5, fd1))
                           + (1.0 - smoothstep(r * 0.06, r * 0.06 + px * 1.2, fd2)) * 0.55) * atTip;
                float halo = (exp(-fd1 / max(r * 0.32, 0.4)) + exp(-fd2 / max(r * 0.20, 0.3)) * 0.35) * atTip;
                float outer = 0.18 * exp(-1.6 * max(d - r * 0.6, 0.0) / max(r, 0.5));
                float a = clamp(core + halo * 0.85 + outer, 0.0, 1.0);
                if (a <= 0.003) {
                    discard;
                }
                vec3 hsvL = rgb2hsv(s.color.rgb);
                vec3 glowC = hsv2rgb(vec3(hsvL.x, max(hsvL.y, 0.78), min(hsvL.z, 0.98)));
                col = mix(glowC, mix(s.color.rgb, vec3(1.0), 0.82), clamp(core + halo * 0.28, 0.0, 1.0));
                alpha = a * s.color.a;
            } else if (s.brush == BRUSH_PEARL) {
                float spacing = max(r * 2.0, 1.5);
                float u = arc / spacing;
                float k = floor(u + 0.5);
                vec2 lp = vec2((u - k) * spacing, across * r);
                float br = r * 0.92;
                float dd = length(lp);
                float cov = clamp((br - dd) / px + 0.5, 0.0, 1.0);
                float silkThread = (1.0 - smoothstep(r * 0.06, r * 0.06 + px, d)) * 0.7;
                if (cov <= 0.0 && silkThread <= 0.0) {
                    discard;
                }
                float xb = clamp(dd / max(br, 1e-4), 0.0, 1.0);
                float sb = sqrt(clamp(1.0 - xb * xb, 0.0, 1.0));
                vec2 dir2 = dd > 1e-5 ? lp / dd : vec2(0.0);
                vec2 ndir = vec2(-tdir.y, tdir.x);
                vec2 pageDir = tdir * dir2.x + ndir * dir2.y;
                vec3 N = normalize(vec3(pageDir * xb, max(sb, 0.05)));
                float ndl = clamp(dot(N, kLight), 0.0, 1.0);
                float irid = sin(xb * 9.0 + k * 1.7 + s.seed * 6.0);
                vec3 sheen = 0.5 + 0.5 * cos(6.2831 * (vec3(0.0, 0.33, 0.67) + xb * 0.6 + k * 0.13));
                vec3 pc = s.color.rgb * (0.64 + 0.46 * ndl) + sheen * 0.14 * (0.6 + 0.4 * irid);
                pc += pow(clamp(dot(N, kHalf), 0.0, 1.0), 75.0) * 1.05 + pow(clamp(1.0 - sb, 0.0, 1.0), 3.0) * 0.16;
                alpha = max(cov, silkThread);
                col = cov >= silkThread ? clamp(pc, 0.0, 1.0) : vec3(0.75, 0.72, 0.68);
                alpha *= s.color.a;
            } else if (s.brush == BRUSH_NEON) {
                float body = clamp((r - d) / px + 0.5, 0.0, 1.0);
                // Metal: smoothstep(r * 0.65, r * 0.15, d); GLSL leaves reversed edges undefined, and
                // smoothstep(b, a, x) == 1 - smoothstep(a, b, x) exactly.
                float core = 1.0 - smoothstep(r * 0.15, r * 0.65, d);
                float glow = 0.14 * exp(-1.45 * max(d - r, 0.0) / max(r, 0.5)) * (1.0 - body);
                vec3 bodyCol = mix(s.color.rgb, vec3(1.0), clamp(0.20 + 0.75 * core * sq, 0.0, 1.0));
                alpha = body + glow;
                if (alpha <= 0.002) {
                    discard;
                }
                col = (bodyCol * body + s.color.rgb * glow) / max(alpha, 1e-4);
                alpha *= s.color.a;
            } else if (s.brush == BRUSH_WATERCOLOR) {
                float n1 = valueNoise(P * 0.16 + s.seed * 37.0);
                float n2v = valueNoise(P * 0.55 + s.seed * 11.0);
                float rr = r * (0.9 + 0.14 * n1 + 0.05 * n2v);
                float cov = clamp((rr - d) / (px * 1.5) + 0.5, 0.0, 1.0);
                if (cov <= 0.0) {
                    discard;
                }
                float xr = clamp(d / max(rr, 1e-4), 0.0, 1.0);
                float edge = smoothstep(0.55, 0.95, xr);
                float pigment = 0.10 + 0.07 * n1 + 0.06 * n2v + 0.14 * edge;
                col = clamp(s.color.rgb * (0.92 + 0.1 * n2v) * (1.0 - 0.20 * edge), 0.0, 1.0);
                alpha = cov * pigment * s.color.a;
            } else if (s.brush == BRUSH_PENCIL) {
                float cov = clamp((r - d) / px + 0.5, 0.0, 1.0);
                if (cov <= 0.0) {
                    discard;
                }
                float grain = valueNoise(P * 1.7) * 0.65 + valueNoise(P * 5.3 + 7.1) * 0.35;
                float density = smoothstep(0.15, 0.85, grain + (ink - 0.55) * 0.9);
                float soft = 1.0 - smoothstep(0.45, 1.0, x);
                col = s.color.rgb * 0.92;
                alpha = cov * ink * (0.18 + 0.62 * density) * (0.35 + 0.65 * soft) * s.color.a;
                if (alpha <= 0.002) {
                    discard;
                }
            } else {
                float cov = clamp((r - d) / px + 0.5, 0.0, 1.0);
                if (cov <= 0.0) {
                    discard;
                }
                if (s.brush == BRUSH_WET) {
                    float w = wetness(s.birth);
                    col = shadeWet(s.color.rgb, x, n2, sq, ink, w);
                } else if (s.brush == BRUSH_WAVE) {
                    col = shadeWave(s.color.rgb, x, n2, sq, P, u_waveTime, max(s.width * 0.5, 0.5), px, s.seed);
                } else if (s.brush == BRUSH_RAINBOW) {
                    vec3 hsv = rgb2hsv(s.color.rgb);
                    float hue = fract(hsv.x + arc / 220.0);
                    col = hsv2rgb(vec3(hue, max(hsv.y, 0.28), max(hsv.z, 0.38)));
                    col = tubeLight(col, n2, x, sq, 0.42, 0.40);
                } else if (s.brush == BRUSH_GLITTER) {
                    vec3 base = s.color.rgb;
                    float flake = hash21(floor(P * 1.6) + s.seed * 13.0);
                    vec3 metal = base * (0.62 + 0.55 * flake);
                    metal = tubeLight(metal, n2, x, sq, 0.65, 0.65);
                    vec2 cell = floor(P / 1.3);
                    float h = hash21(cell + 3.7);
                    vec2 f = fract(P / 1.3) - 0.5;
                    float tw = 0.5 + 0.5 * sin(u_waveTime * (2.0 + 3.0 * h) + h * 40.0);
                    float star = (1.0 - smoothstep(0.0, 0.32, length(f))) * step(0.8, h) * tw;
                    float rays = (1.0 - smoothstep(0.0, 0.06, min(abs(f.x), abs(f.y)))) * (1.0 - smoothstep(0.0, 0.5, length(f)))
                                 * step(0.93, h) * tw;
                    col = clamp(metal + vec3(1.0, 0.98, 0.9) * (star * 0.95 + rays * 0.85), 0.0, 1.0);
                } else if (s.brush == BRUSH_CALLIGRAPHY) {
                    float pool = smoothstep(0.68, 1.0, x) * 0.22;
                    col = s.color.rgb * (1.0 - pool) * (0.96 + 0.06 * valueNoise(P * 0.8));
                    col = tubeLight(col, n2, x, sq, 0.18, 0.30);
                } else if (s.brush == BRUSH_GRASS) {
                    // The turf the blades grow from: a mossy mound with a soft, ragged edge, shaded where it
                    // lies under the grass on its lower side. Its clumps are sized from the line's width.
                    float tuftScale = 1.0 / max(s.width * 0.4, 1.3);
                    vec3 tuft = voronoiDetail(P * tuftScale + s.seed * 5.0, 0.0);
                    float n = fbm(P * tuftScale * 0.7 + s.seed * 3.0);
                    float tuftDome = 1.0 - smoothstep(0.0, 0.65, tuft.y);
                    vec3 base = s.color.rgb;
                    vec3 deepMoss = base * 0.30;
                    vec3 freshTurf = mix(base * 0.88, vec3(0.48, 0.82, 0.24), 0.28);
                    col = mix(deepMoss, freshTurf, clamp(tuftDome * 0.7 + n * 0.4, 0.0, 1.0));
                    col = tubeLight(col, n2, x, sq, 0.08, 0.45);
                    float under = smoothstep(0.1, 0.9, n2.y * x);
                    col = mix(col, vec3(0.30, 0.21, 0.12) * (0.7 + 0.5 * n), under * 0.6);
                    col *= 1.0 - 0.3 * under;
                    float edgeTuft = smoothstep(0.62, 0.98, x + (tuft.y - 0.4) * 0.22 + (n - 0.5) * 0.1);
                    cov *= 0.95 * (1.0 - edgeTuft);
                } else if (s.brush == BRUSH_FOUNTAIN) {
                    col = shadeWet(s.color.rgb, x, n2, sq, ink, 0.78);
                } else if (s.brush == BRUSH_GOLD) {
                    vec2 hammer = (vec2(valueNoise(P * 0.9 + 3.0), valueNoise(P * 0.9 + 11.0)) - 0.5) * 0.32;
                    vec3 N = normalize(vec3(n2 * (x / max(sq, 0.12)) * 0.95 + hammer, 1.0));
                    float lum = dot(envColor(reflectView(N), vec3(1.0)), vec3(0.3, 0.59, 0.11));
                    col = s.color.rgb * (0.24 + 1.12 * lum) + pow(clamp(dot(N, kHalf), 0.0, 1.0), 75.0) * vec3(1.0, 0.96, 0.82) * 1.05;
                    col = clamp(col, 0.0, 1.0);
                } else if (s.brush == BRUSH_CHROME) {
                    vec3 N = normalize(vec3(n2 * (x / max(sq, 0.12)) * 1.15, 1.0));
                    vec3 env = envColor(reflectView(N), mix(vec3(1.0), s.color.rgb * 1.2, 0.55));
                    col = clamp(env * 1.08 + pow(clamp(dot(N, kHalf), 0.0, 1.0), 140.0) * 1.3, 0.0, 1.0);
                } else if (s.brush == BRUSH_ICE) {
                    float frost = fbm(P * 0.35 + s.seed * 4.0);
                    float cracks = (1.0 - smoothstep(0.015, 0.075, cellEdge(P / max(r * 1.05, 0.8) + s.seed * 3.0))) * 0.68;
                    vec3 N = normalize(vec3(n2 * (x / max(sq, 0.15)) * 0.78 + (frost - 0.5) * 0.42, 1.0));
                    float fres = pow(clamp(1.0 - N.z, 0.0, 1.0), 2.2);
                    vec3 base = mix(s.color.rgb, vec3(0.92, 0.98, 1.0), 0.38);
                    float hs = hash21(floor(P / 1.5) + 2.3);
                    float tw = step(0.93, hs) * (0.5 + 0.5 * sin(u_waveTime * (3.0 + 4.0 * hs) + hs * 30.0));
                    col = base * (0.76 + 0.24 * frost) + fres * 0.48 + cracks * 0.55;
                    col = clamp(col + pow(clamp(dot(N, kHalf), 0.0, 1.0), 85.0) * 1.05 + tw * 0.85, 0.0, 1.0);
                    alphaScale = clamp(0.66 + 0.28 * fres + 0.22 * cracks, 0.0, 1.0);
                } else if (s.brush == BRUSH_GALAXY) {
                    float drift = u_waveTime * 0.15;
                    vec2 gp = P * 0.07 + vec2(drift, -drift * 0.6) + s.seed * 9.0;
                    float neb = fbm(gp + fbm(gp * 1.7 - drift) * 1.25);
                    vec3 hsv = rgb2hsv(s.color.rgb);
                    vec3 c1 = hsv2rgb(vec3(hsv.x, 0.88, 0.95));
                    vec3 c2 = hsv2rgb(vec3(fract(hsv.x + 0.18), 0.78, 0.90));
                    vec3 space = vec3(0.015, 0.010, 0.045);
                    col = mix(space, mix(c1, c2, smoothstep(0.28, 0.82, fbm(gp * 2.3 + 4.0))), smoothstep(0.32, 0.86, neb) * 0.90);
                    float sh = hash21(floor(P / 1.1) + s.seed * 3.1);
                    vec2 sf2 = fract(P / 1.1) - 0.5;
                    // Metal: step(0.88, sh) * (1 - smoothstep(0, 0.22 + (sh - 0.88) * 1.2, ...)); the
                    // smoothstep's upper edge is only above 0 where the step is 1, so it is evaluated there.
                    float star = sh >= 0.88 ? (1.0 - smoothstep(0.0, 0.22 + (sh - 0.88) * 1.2, length(sf2))) : 0.0;
                    star *= 0.55 + 0.45 * sin(u_waveTime * (1.5 + sh * 5.0) + sh * 40.0);
                    col += star * vec3(0.96, 0.97, 1.0);
                    col = tubeLight(col, n2, x, sq, 0.60, 0.55);
                } else if (s.brush == BRUSH_IMPASTO) {
                    float acrossN = sacross;
                    float ridgePhase = acrossN * 14.0 + valueNoise(vec2(arc * 0.15, acrossN * 3.0) + s.seed * 5.0) * 4.0;
                    float lump = valueNoise(vec2(arc * 0.25, acrossN * 2.0) + s.seed * 3.0) - 0.5;
                    vec2 nLeft = vec2(-tdir.y, tdir.x);
                    vec3 N = normalize(vec3(n2 * (x / max(sq, 0.15)) * 0.55 - nLeft * cos(ridgePhase) * 0.55 + tdir * lump * 0.75, 1.0));
                    vec3 base = s.color.rgb * (0.9 + 0.2 * valueNoise(P * 0.2 + 9.0));
                    col = base * (0.52 + 0.80 * clamp(dot(N, kLight), 0.0, 1.0));
                    col = clamp(col + pow(clamp(dot(N, kHalf), 0.0, 1.0), 26.0) * 0.34, 0.0, 1.0);
                    alphaScale = 1.0 - 0.35 * smoothstep(0.85, 1.0, x) * valueNoise(P * 0.8);
                }
                alpha = cov * s.color.a * alphaScale;
            }

            fragColor = u_depthOnly != 0u ? vec4(0.0) : vec4(col * alpha, alpha);
            gl_FragDepth = v_zBase + u_depthStep * (0.46 + 0.44 * clamp(abs(v_u) * 0.25, 0.0, 1.0));
        }
    """.trimIndent()

    /** highlighter_fragment. */
    private val HIGHLIGHTER_FRAGMENT_MAIN = """
        void main() {
            StrokeFrag sf = strokeFrag();
            float cov = clamp((sf.r - sf.d) / u_pixelSize + 0.5, 0.0, 1.0);
            if (cov <= 0.0) {
                discard;
            }
            StrokeRec s = fetchStroke(v_stroke);
            fragColor = vec4(mix(vec3(1.0), s.color.rgb, cov * s.color.a), 1.0);
            gl_FragDepth = v_zBase + (1.0 - cov) * u_depthStep * 0.9;
        }
    """.trimIndent()

    /** shadow_fragment. */
    private val SHADOW_FRAGMENT_MAIN = """
        void main() {
            StrokeFrag sf = strokeFrag();
            float r = sf.r;
            float d = sf.d;
            float blur = v_blur;
            float cov = 1.0 - smoothstep(r - blur, r + blur, d);
            if (cov <= 0.003) {
                discard;
            }
            StrokeRec s = fetchStroke(v_stroke);
            float strength = 0.28;
            if (s.brush == BRUSH_WAVE || s.brush == BRUSH_SEA) {
                strength = 0.22;
            } else if (s.brush == BRUSH_GRASS) {
                strength = 0.24;
            } else if (s.brush == BRUSH_ICE || s.brush == BRUSH_JELLY) {
                strength = 0.16;
            }
            strength *= v_h * s.color.a;
            float a = cov * strength;
            fragColor = u_depthOnly != 0u ? vec4(0.0) : vec4(vec3(0.09, 0.11, 0.18) * a, a);
            gl_FragDepth = v_zBase + u_depthStep * 0.9 * clamp(d / (r + blur), 0.0, 1.0);
        }
    """.trimIndent()

    // MARK: grass blades

    /** BladeOut as varyings. */
    private fun bladeVaryings(q: String) = """
        $q vec2 v_n2;
        $q float v_t;
        $q float v_u;
        $q float v_halfPx;
        flat $q vec3 v_color;
        flat $q float v_alpha;
        flat $q float v_depth;
        flat $q float v_kind;
    """.trimIndent()

    /** blade_vertex: 16 vertices a blade (a triangle strip from gl_VertexID), one instance a blade. */
    private val BLADE_VERTEX_MAIN = """
        const uint BLADE_SEGS = 7u;

        void main() {
            BladeRec b = fetchBlade(u_pointOffset + uint(gl_InstanceID));
            float g = bladeGrowth(u_time, b.birth);
            float sway = bladeSway(b);
            uint vid = uint(gl_VertexID);
            uint i = min(vid >> 1u, BLADE_SEGS);
            float s = float(i) / float(BLADE_SEGS);
            float side = (vid & 1u) != 0u ? 1.0 : -1.0;
            vec2 tangent;
            vec2 P = bladeAt(b, s, g, sway, tangent);
            float tl = length(tangent);
            vec2 dir = tl > 1e-5 ? tangent / tl : vec2(0.0, -1.0);
            vec2 nrm = vec2(-dir.y, dir.x);
            float w;
            if (b.kind == 3u) {
                // A leaf: pointed at both ends, widest a little past the middle.
                w = b.width * pow(max(sin(3.14159265 * pow(max(s, 1e-4), 1.15)), 1e-4), 0.8);
            } else if (b.kind >= 1u) {
                w = b.width * (1.0 - 0.45 * s);
            } else {
                w = b.width * pow(max(1.0 - s, 1e-4), 0.85);
            }
            w *= 0.35 + 0.65 * g;
            float hw = 0.5 * w;
            float ext = hw + u_pixelSize;
            float order = float(u_orderOffset + b.stroke);
            float zBase = 1.0 - (order + 1.0) * u_depthStep;

            vec2 V = P + nrm * (side * ext);
            gl_Position = vec4(docToNDC(u_pageOrigin + V), zBase * 2.0 - 1.0, 1.0);
            v_n2 = nrm;
            v_t = s;
            v_u = side * min(ext / max(hw, 1e-4), 6.0);
            v_halfPx = hw * u_scale;
            v_color = b.color.rgb;
            v_alpha = b.color.a;
            v_depth = zBase + u_depthStep * 0.44 * b.depth;
            v_kind = float(b.kind);
            if (g <= 0.001) {
                gl_Position = vec4(-2.0, -2.0, 0.0, 1.0);
            }
        }
    """.trimIndent()

    /** blade_fragment. */
    private val BLADE_FRAGMENT_MAIN = """
        layout(location = 0) out vec4 fragColor;

        // The flowering water's stems (kind 2) and leaves (kind 3): translucent turquoise glass, denser and
        // deeper at the edges, with a soft streak and a sharp glint where the rounded surface faces the light.
        vec4 glassBlade(float u, float a) {
            float uu = u * u;
            vec3 N = normalize(vec3(v_n2 * (u * 0.92), sqrt(max(1.0 - uu * 0.85, 0.05))));
            float ndl = clamp(dot(N, kLight), 0.0, 1.0);
            vec3 base = v_color;
            vec3 deep = base * vec3(0.55, 0.78, 0.92);
            vec3 col;
            float alpha;
            if (v_kind > 2.5) {
                // A leaf: a light midrib, the tip a touch bluer.
                float midrib = exp(-abs(u) * 7.0) * 0.16;
                col = mix(base, mix(base, vec3(0.55, 0.72, 1.0), 0.35), smoothstep(0.4, 1.0, v_t));
                col = mix(col, deep, uu * 0.6);
                col += vec3(midrib);
                alpha = 0.52 + 0.30 * uu;
            } else {
                // A stem: a glass rod, lighter toward the flower.
                col = mix(deep, base, 0.2 + 0.8 * smoothstep(0.0, 0.7, v_t));
                col = mix(col, deep * 0.9, uu * uu * 0.7);
                alpha = 0.66 + 0.30 * uu;
            }
            col *= 0.82 + 0.26 * ndl;
            float nh = clamp(dot(N, kHalf), 0.0, 1.0);
            float streak = pow(nh, 18.0);
            float glint = pow(nh, 90.0);
            col = clamp(col + vec3(0.92, 0.98, 1.0) * (streak * 0.35 + glint * 0.55), 0.0, 1.0);
            a *= clamp(alpha + glint * 0.3, 0.0, 1.0);
            return vec4(col * a, a);
        }

        void main() {
            float cov = clamp((1.0 - abs(v_u)) * v_halfPx + 0.5, 0.0, 1.0);
            float a = cov * v_alpha;
            if (a <= 0.004) {
                discard;
            }
            float u = clamp(v_u, -1.0, 1.0);
            gl_FragDepth = v_depth;
            if (v_kind > 1.5) {
                fragColor = glassBlade(u, a);
                return;
            }
            vec3 base = v_color;
            vec3 col;
            if (v_kind > 0.5) {
                col = base * mix(0.55, 1.05, v_t);
            } else {
                // A blade of grass: dark at the root, the ink's green up the blade, sunlit at the tip, with
                // the light shining through the thin tip on the side that faces it and a darker rim so each
                // blade stands out of the tuft.
                vec3 darkRoot = base * 0.26;
                vec3 sunlitTip = mix(base * 1.25, vec3(0.90, 0.96, 0.40), 0.36);
                col = mix(darkRoot, base, smoothstep(0.0, 0.38, v_t));
                col = mix(col, sunlitTip, smoothstep(0.50, 1.0, v_t));
                float midrib = exp(-abs(u) * 8.0) * 0.12;
                float fibers = sin(u * 16.0) * 0.03;
                col += vec3(midrib + fibers);
                float facing = dot(v_n2 * (u < 0.0 ? -1.0 : 1.0), vec2(-0.5865, -0.8100));
                float through = smoothstep(0.55, 1.0, v_t) * (0.5 + 0.5 * facing) * 0.20;
                col += vec3(0.55, 0.62, 0.18) * through;
                col *= 1.0 - 0.26 * smoothstep(0.55, 1.0, abs(u)) * (1.0 - 0.5 * smoothstep(0.7, 1.0, v_t));
            }
            vec3 N = normalize(vec3(v_n2 * (u * 0.90), sqrt(max(1.0 - u * u * 0.75, 0.05))));
            float ndl = clamp(dot(N, kLight), 0.0, 1.0);
            col *= 0.58 + 0.68 * ndl;
            float spec = pow(clamp(dot(N, kHalf), 0.0, 1.0), 32.0) * 0.28 * smoothstep(0.12, 0.88, v_t);
            col = clamp(col + vec3(spec), 0.0, 1.0);
            fragColor = vec4(col * a, a);
        }
    """.trimIndent()

    // MARK: flowers

    /** FlowerOut as varyings. */
    private fun flowerVaryings(q: String) = """
        $q vec2 v_q;
        flat $q float v_pxR;
        flat $q float v_open;
        flat $q float v_grow;
        flat $q float v_petals;
        flat $q float v_style;
        flat $q float v_spin;
        flat $q vec3 v_petal;
        flat $q vec3 v_core;
        flat $q float v_depth;
        flat $q float v_seed;     // 0..1, fixed per flower (the glass flowers vary their tilt and stamens by it)
    """.trimIndent()

    /** flower_vertex: a quad (a triangle strip from gl_VertexID), one instance a flower. */
    private val FLOWER_VERTEX_MAIN = """
        void main() {
            FlowerRec f = fetchFlower(uint(gl_InstanceID));
            BladeRec b = fetchBlade(u_pointOffset + f.stem);
            float g = bladeGrowth(u_time, b.birth);
            float sway = bladeSway(b);
            vec2 tangent;
            vec2 tip = bladeAt(b, 1.0, g, sway, tangent);
            float R = max(f.radius, 0.5);
            float extent = R * 1.35 + u_pixelSize * 2.0;
            uint vid = uint(gl_VertexID);
            vec2 corner = vec2((vid & 1u) != 0u ? 1.0 : -1.0, (vid & 2u) != 0u ? 1.0 : -1.0);
            float order = float(u_orderOffset + b.stroke);
            float zBase = 1.0 - (order + 1.0) * u_depthStep;

            gl_Position = vec4(docToNDC(u_pageOrigin + tip + corner * extent), zBase * 2.0 - 1.0, 1.0);
            v_q = corner * (extent / R);
            v_pxR = u_pixelSize / R;
            v_open = clamp((u_time - f.bloom) / 0.85, 0.0, 1.0);
            float grow = smoothstep(0.55, 1.0, g);
            v_grow = grow;
            v_petals = max(f.petals, 3.0);
            v_style = f.style;
            v_spin = f.spin + sway * 0.14;
            v_petal = f.petal.rgb;
            v_core = f.core.rgb;
            v_depth = zBase + u_depthStep * (0.44 * b.depth - 0.002);
            v_seed = fract(f.spin * 0.15915494 + f.radius * 0.731);
            if (grow <= 0.001) {
                gl_Position = vec4(-2.0, -2.0, 0.0, 1.0);
            }
        }
    """.trimIndent()

    /** flower_fragment, with the glass flowers (the flowering water, style 3). */
    private val FLOWER_FRAGMENT_MAIN = """
        layout(location = 0) out vec4 fragColor;

        vec4 over(vec4 src, vec4 dst) {
            return src + dst * (1.0 - src.a);
        }

        struct GlassPetal {
            float a;       // coverage of this petal, 0 outside it
            float t;       // 0 at the flower's centre .. 1 at the tip
            float u;       // -1 .. 1 across the petal
            vec2 dirA;     // along the petal, in page space
        };

        // One petal of a whorl of n (centre angle (i + offset) * sector in the spun frame): narrow at the
        // centre, widest a little past the middle, drawn to a slightly rounded point.
        GlassPetal glassPetal(float rho, float th, float i, float offset, float sector,
                              float L, float halfWidth, float px, float spin)
        {
            float ang = (i + offset) * sector;
            float dth = th - ang;
            float along = rho * cos(dth);
            float across = rho * sin(dth);
            float t = clamp(along / L, 0.0, 1.0);
            float shape = pow(max(sin(3.14159265 * pow(max(t, 1e-4), 1.15)), 0.0), 0.72);
            float w = halfWidth * L * shape;
            GlassPetal p;
            p.a = clamp((w - abs(across)) / px + 0.5, 0.0, 1.0) * clamp((L - along) / px + 0.5, 0.0, 1.0) * clamp(along / px + 0.5, 0.0, 1.0);
            p.t = t;
            p.u = clamp(across / max(w, 1e-4), -1.0, 1.0);
            p.dirA = vec2(cos(ang - spin), sin(ang - spin));
            return p;
        }

        // Colour (straight, not premultiplied) and alpha of a glass petal: pale at the centre shading to the
        // tip colour, deeper and denser at the edges where the glass is seen edge-on, faint veins, a soft
        // lit streak and a sharper glint on the cupped surface. Buds keep the water's pale blue.
        vec4 glassPetalColor(GlassPetal p, vec3 tip, vec3 pale, float budMix, float cupping, float alphaScale)
        {
            float uu = p.u * p.u;
            vec2 dirC = vec2(-p.dirA.y, p.dirA.x);
            vec3 N = normalize(vec3(dirC * (p.u * cupping) + p.dirA * ((p.t - 0.5) * 0.9), 1.0));
            float ndl = clamp(dot(N, kLight), 0.0, 1.0);
            float nh = clamp(dot(N, kHalf), 0.0, 1.0);
            vec3 deep = tip * vec3(0.80, 0.74, 1.0);
            vec3 col = mix(pale, tip, smoothstep(0.12, 0.92, p.t));
            float edge = (uu * uu * 0.55 + smoothstep(0.80, 1.0, abs(p.u)) * 0.35) * smoothstep(0.08, 0.4, p.t);
            col = mix(col, deep, edge);
            float veins = pow(max(0.5 + 0.5 * cos(p.u * 9.42478), 0.0), 5.0) * 0.09 * smoothstep(0.05, 0.45, p.t) * (1.0 - 0.6 * p.t);
            col += vec3(veins);
            col = mix(col, vec3(0.66, 0.88, 0.98), budMix * 0.6);
            col *= 0.84 + 0.24 * ndl;
            float streak = pow(nh, 14.0);
            float glint = pow(nh, 70.0);
            float rimLit = pow(abs(p.u), 4.0) * pow(nh, 6.0) * 0.6;
            col = clamp(col + vec3(0.94, 0.97, 1.0) * (streak * 0.30 + glint * 0.55 + rimLit), 0.0, 1.0);
            float alpha = mix(0.40, 0.80, smoothstep(0.05, 0.9, p.t)) + 0.16 * uu + budMix * 0.18;
            alpha = min(clamp(alpha + glint * 0.25, 0.0, 1.0), 0.95) * alphaScale;
            return vec4(col, alpha);
        }

        // The two petals of a whorl nearest the fragment, the lower index on top (and petal n-1 over petal
        // 0), so where petals overlap there is one seam, as in a real flower.
        vec4 glassWhorl(float rho, float th, float n, float sector, float offset, float L, float halfWidth,
                        float px, float spin, vec3 tip, vec3 pale, float budMix, float cupping, float alphaScale)
        {
            float i0 = round(th / sector - offset);
            float dth = th - (i0 + offset) * sector;
            float i1 = i0 + (dth >= 0.0 ? 1.0 : -1.0);
            GlassPetal pA = glassPetal(rho, th, i0, offset, sector, L, halfWidth, px, spin);
            GlassPetal pB = glassPetal(rho, th, i1, offset, sector, L, halfWidth, px, spin);
            vec4 cA = glassPetalColor(pA, tip, pale, budMix, cupping, alphaScale);
            vec4 cB = glassPetalColor(pB, tip, pale, budMix, cupping, alphaScale);
            float aA = cA.a * pA.a;
            float aB = cB.a * pB.a;
            vec4 layerA = vec4(cA.rgb * aA, aA);
            vec4 layerB = vec4(cB.rgb * aB, aB);
            float i0w = i0 - n * floor(i0 / n);
            float i1w = i1 - n * floor(i1 / n);
            bool aOnTop = (i1w == i0w + 1.0) || (i0w == n - 1.0 && i1w == 0.0);
            return aOnTop ? over(layerA, layerB) : over(layerB, layerA);
        }

        // A glass flower (premultiplied): an outer whorl of long petals, a shorter inner whorl turned half
        // a petal, a pale glowing heart with fine glassy stamens instead of pollen, and a faint blue shadow.
        vec4 glassFlower(float S, float px, float e)
        {
            float v1 = fract(v_seed * 7.13 + 0.37);
            float v2 = fract(v_seed * 3.71 + 0.61);
            // Each flower faces the viewer a little differently: a touch wider than tall.
            float aspect = 0.78 + 0.17 * v1;
            vec2 q = vec2(v_q.x, v_q.y / aspect);
            float cs = cos(v_spin);
            float sn = sin(v_spin);
            vec2 r = vec2(cs * q.x - sn * q.y, sn * q.x + cs * q.y);
            float rho = length(r);
            // atan2(0, 0) is 0 in Metal; GLSL leaves atan undefined at the origin.
            float th = rho > 0.0 ? atan(r.y, r.x) : 0.0;
            float n = v_petals;
            float sector = 6.2831853 / n;
            float budMix = 1.0 - smoothstep(0.05, 0.55, e);
            vec3 tip = v_petal;
            vec3 pale = mix(v_core, vec3(1.0), 0.25);
            vec3 paleInner = mix(pale, tip, 0.18);

            float halfWidth = 0.38 - 0.03 * (n - 5.0);
            vec4 outer = glassWhorl(rho, th, n, sector, 0.0, S, halfWidth, px, v_spin, tip, pale, budMix, 0.55, 1.0);
            vec4 inner = glassWhorl(rho, th, n, sector, 0.5, S * 0.58, 0.40, px, v_spin, mix(tip, pale, 0.25), paleInner,
                                    budMix, 0.75, 0.75);

            float opened = smoothstep(0.10, 0.60, e);
            float rr = rho / max(S, 1e-4);
            float glowA = (1.0 - smoothstep(0.04, 0.40, rr)) * 0.62 * opened;
            vec3 glowC = mix(v_core, vec3(1.0), 0.5);

            float stamens = 10.0;
            float sec2 = 6.2831853 / stamens;
            float k = round(th / sec2 - v2);
            float dk = th - (k + v2) * sec2;
            float along = rho * cos(dk);
            float across = rho * sin(dk);
            float stLen = S * 0.30 * opened;
            float stW = S * 0.022;
            float aLine = clamp((stW - abs(across)) / px + 0.5, 0.0, 1.0) * clamp((stLen - along) / px + 0.5, 0.0, 1.0)
                        * clamp((along - S * 0.05) / px + 0.5, 0.0, 1.0);
            float aDot = clamp((S * 0.045 - length(vec2(along - stLen, across))) / px + 0.5, 0.0, 1.0);
            float aSt = max(aLine, aDot) * 0.85 * opened;
            vec3 stC = mix(vec3(0.98, 0.98, 1.0), tip, 0.22);
            float aCore = clamp((S * 0.07 - rho) / px + 0.5, 0.0, 1.0) * 0.9 * opened;
            vec3 coreC = mix(v_core, vec3(1.0), 0.6);

            vec2 sq = v_q - vec2(0.10, 0.14) * S;
            float shadowA = 0.14 * (1.0 - smoothstep(0.25 * S, 1.0 * S, length(sq))) * smoothstep(0.0, 0.3, e) * v_grow;

            vec4 acc = vec4(vec3(0.30, 0.36, 0.70) * shadowA, shadowA);
            acc = over(outer, acc);
            acc = over(inner, acc);
            acc = over(vec4(glowC * glowA, glowA), acc);
            acc = over(vec4(stC * aSt, aSt), acc);
            acc = over(vec4(coreC * aCore, aCore), acc);
            return acc;
        }

        void main() {
            float e = v_open;
            float c1 = 1.85;
            float em = e - 1.0;
            float ob = 1.0 + (c1 + 1.0) * em * em * em + c1 * em * em;
            float S = mix(0.28, 1.0, ob) * v_grow;
            float px = v_pxR;
            gl_FragDepth = v_depth;

            if (v_style > 2.5) {
                vec4 glass = glassFlower(S, px, e);
                if (glass.a <= 0.003) {
                    discard;
                }
                fragColor = glass;
                return;
            }

            vec2 q = vec2(v_q.x, v_q.y / 0.86);
            float cs = cos(v_spin);
            float sn = sin(v_spin);
            vec2 r = vec2(cs * q.x - sn * q.y, sn * q.x + cs * q.y);
            float rho = length(r);
            // atan2(0, 0) is 0 in Metal; GLSL leaves atan undefined at the origin.
            float th = rho > 0.0 ? atan(r.y, r.x) : 0.0;
            vec2 dirQ = length(q) > 1e-5 ? normalize(q) : vec2(0.0);

            float n = v_petals;
            float sharp = v_style < 0.5 ? 1.45 : (v_style < 1.5 ? 0.52 : 0.38);
            float notch = v_style < 0.5 ? 0.20 : 0.44;
            float c0 = max(abs(cos(0.5 * n * th)), 1e-4);
            float c2 = max(abs(cos(0.5 * n * th + 1.5707963)), 1e-4);
            float lobe1 = pow(c0, sharp);
            float lobe2 = pow(c2, sharp);
            float tipDip = v_style > 0.5 ? (0.04 * pow(c0, 12.0)) : 0.0;
            float edge1 = S * (notch + (1.0 - notch) * lobe1 - tipDip);
            float edge2 = S * 0.90 * (notch + (1.0 - notch) * lobe2);
            float a1 = clamp((edge1 - rho) / px + 0.5, 0.0, 1.0);
            float a2 = v_style > 0.5 ? clamp((edge2 - rho) / px + 0.5, 0.0, 1.0) : 0.0;

            float budMix = 1.0 - smoothstep(0.05, 0.55, e);
            vec3 petal = mix(v_petal, vec3(0.32, 0.58, 0.22), budMix * 0.55);
            float rr = rho / max(S, 1e-4);

            float cup = v_style > 1.5 ? 0.95 : 0.62;
            float petalPleat = (1.0 - lobe1) * 0.35;
            vec3 N = normalize(vec3(-dirQ * (cup * rr - petalPleat), 1.0));
            float ndl = clamp(dot(N, kLight), 0.0, 1.0);
            float fineVeins = sin(th * n * 7.0) * 0.5 + 0.5;
            float vein = pow(max(lobe1, 1e-4), 14.0) * 0.08 + fineVeins * smoothstep(0.15, 0.85, rr) * 0.05;

            vec3 throatCol = mix(petal * 0.62, v_core, 0.28);
            vec3 rimGlow = mix(petal, vec3(1.0), 0.32);
            vec3 col1 = mix(throatCol, petal, smoothstep(0.10, 0.52, rr));
            col1 = mix(col1, rimGlow, smoothstep(0.68, 0.98, rr));
            col1 *= 0.76 + 0.46 * ndl;
            col1 += vec3(vein);
            col1 = clamp(col1 + pow(clamp(dot(N, kHalf), 0.0, 1.0), 32.0) * 0.22, 0.0, 1.0);

            vec3 col2 = mix(throatCol * 0.75, petal * 0.80, smoothstep(0.12, 0.70, rr)) * (0.78 + 0.32 * ndl);

            float coreR = S * (v_style < 0.5 ? 0.32 : 0.24) * smoothstep(0.08, 0.55, e);
            float aC = coreR > 1e-4 ? clamp((coreR - rho) / px + 0.5, 0.0, 1.0) : 0.0;
            float xc = clamp(rho / max(coreR, 1e-4), 0.0, 1.0);
            float sqc = sqrt(clamp(1.0 - xc * xc, 0.0, 1.0));
            vec3 Nc = normalize(vec3(dirQ * xc, max(sqc, 0.05)));
            vec3 colC = v_core * (0.68 + 0.52 * clamp(dot(Nc, kLight), 0.0, 1.0));
            float pollenGrain = step(0.55, hash21(floor(r * 32.0)));
            colC = mix(colC, colC * 1.25 + vec3(0.18, 0.12, 0.0), pollenGrain * 0.45);
            colC = clamp(colC + pow(clamp(dot(Nc, kHalf), 0.0, 1.0), 26.0) * 0.38, 0.0, 1.0);

            float stamenRingR = coreR * 1.28;
            float stamenAngle = th * 12.0;    // Metal: atan2(r.y, r.x) * 12.0, the same angle
            vec2 stamenP = vec2(rho - stamenRingR, sin(stamenAngle) * stamenRingR * 0.12);
            float aStamen = (coreR > 1e-4 ? clamp((coreR * 0.14 - length(stamenP)) / px + 0.5, 0.0, 1.0) : 0.0) * smoothstep(0.3, 0.8, e);
            vec3 colStamen = vec3(1.0, 0.88, 0.25);

            vec2 sq = v_q - vec2(0.12, 0.18) * S;
            float shadowA = 0.26 * (1.0 - smoothstep(0.30 * S, 1.08 * S, length(sq))) * smoothstep(0.0, 0.3, e) * v_grow;

            vec4 acc = vec4(0.0, 0.0, 0.0, shadowA);
            acc = over(vec4(col2 * a2, a2), acc);
            acc = over(vec4(col1 * a1, a1), acc);
            acc = over(vec4(colStamen * aStamen, aStamen), acc);
            acc = over(vec4(colC * aC, aC), acc);
            if (acc.a <= 0.003) {
                discard;
            }
            fragColor = acc;
        }
    """.trimIndent()

    // MARK: page quads

    /** QuadOut as varyings. */
    private fun quadVaryings(q: String) = """
        $q vec2 v_uv;
        $q vec2 v_local;
    """.trimIndent()

    /** quad_vertex: 4 vertices as a triangle strip from gl_VertexID, no attributes. */
    private val QUAD_VERTEX_MAIN = """
        void main() {
            uint vid = uint(gl_VertexID);
            vec2 corner = vec2((vid & 1u) != 0u ? 1.0 : 0.0, (vid & 2u) != 0u ? 1.0 : 0.0);
            vec2 doc = u_rect.xy + corner * u_rect.zw;
            // Metal depth 0.0 (the quads draw with the depth test off).
            gl_Position = vec4(docToNDC(doc), -1.0, 1.0);
            v_uv = mix(u_uvRect.xy, u_uvRect.zw, corner);
            v_local = doc - u_pageOrigin;
        }
    """.trimIndent()

    /** paper_fragment. */
    private val PAPER_FRAGMENT_MAIN = """
        layout(location = 0) out vec4 fragColor;

        void main() {
            float px = u_pixelSize;
            vec2 p = v_local;
            vec3 col = vec3(1.0);
            if (u_style == 1u) {
                float spacing = 28.0;
                float top = 84.0;
                float fade = smoothstep(3.0, 7.0, spacing / px);
                if (p.y > top - spacing * 0.5) {
                    float f = (p.y - top) / spacing;
                    float dist = abs(f - round(f)) * spacing;
                    float lw = max(0.45, px * 0.5);
                    float line = 1.0 - smoothstep(lw, lw + px, dist);
                    col = mix(col, vec3(0.66, 0.80, 0.95), line * fade);
                }
                float mw = max(0.5, px * 0.5);
                float ml = 1.0 - smoothstep(mw, mw + px, abs(p.x - 72.0));
                col = mix(col, vec3(0.96, 0.62, 0.62), ml * 0.85);
            } else if (u_style == 2u) {
                float spacing = 20.0;
                float fade = smoothstep(3.0, 7.0, spacing / px);
                vec2 f = p / spacing;
                vec2 dist = abs(f - round(f)) * spacing;
                float lw = max(0.35, px * 0.5);
                float line = 1.0 - smoothstep(lw, lw + px, min(dist.x, dist.y));
                col = mix(col, vec3(0.78, 0.85, 0.93), line * fade);
            } else if (u_style == 3u) {
                float spacing = 20.0;
                float fade = smoothstep(3.0, 7.0, spacing / px);
                vec2 f = p / spacing;
                vec2 dd = (f - round(f)) * spacing;
                float rd = max(0.9, px * 0.7);
                float dotv = 1.0 - smoothstep(rd, rd + px, length(dd));
                col = mix(col, vec3(0.60, 0.64, 0.70), dotv * fade);
            }
            fragColor = vec4(col, 1.0);
        }
    """.trimIndent()

    /** texture_fragment: the page picture, sampled with linear (mipmapped) filtering, clamped to the edge. */
    private val TEXTURE_FRAGMENT_MAIN = """
        uniform mediump sampler2D u_texture;

        layout(location = 0) out vec4 fragColor;

        void main() {
            fragColor = vec4(texture(u_texture, v_uv).rgb, 1.0);
        }
    """.trimIndent()

    /** page_shadow_fragment: straight alpha. */
    private val PAGE_SHADOW_FRAGMENT_MAIN = """
        layout(location = 0) out vec4 fragColor;

        void main() {
            vec2 p = v_local - vec2(0.0, 1.5);
            vec2 h = u_pageSize * 0.5;
            vec2 q = abs(p - h) - h;
            float dist = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0);
            float a = (1.0 - smoothstep(0.0, max(u_shadowRadius, 0.5), dist)) * 0.14;
            fragColor = vec4(0.0, 0.0, 0.0, a);
        }
    """.trimIndent()

    // MARK: programs (the pipelines of InkRenderer.swift, with their blends)

    private fun join(vararg parts: String) = parts.joinToString("\n\n") + "\n"

    private val ribbonVertex = join(PRELUDE, RIBBON_VERTEX_COMMON, RIBBON_VERTEX_MAIN)
    private val shadowVertex = join(PRELUDE, RIBBON_VERTEX_COMMON, SHADOW_VERTEX_MAIN)
    private val inkFragment = join(PRELUDE, RIBBON_FRAGMENT_COMMON, INK_SHADING, INK_FRAGMENT_MAIN)
    private val highlighterFragment = join(PRELUDE, RIBBON_FRAGMENT_COMMON, HIGHLIGHTER_FRAGMENT_MAIN)
    private val shadowFragment = join(PRELUDE, RIBBON_FRAGMENT_COMMON, SHADOW_FRAGMENT_MAIN)
    private val bladeVertex = join(PRELUDE, bladeVaryings("out"), BLADE_VERTEX_MAIN)
    private val bladeFragment = join(PRELUDE, bladeVaryings("in"), BLADE_FRAGMENT_MAIN)
    private val flowerVertex = join(PRELUDE, flowerVaryings("out"), FLOWER_VERTEX_MAIN)
    private val flowerFragment = join(PRELUDE, flowerVaryings("in"), FLOWER_FRAGMENT_MAIN)
    private val quadVertex = join(PRELUDE, quadVaryings("out"), QUAD_VERTEX_MAIN)
    private val paperFragment = join(PRELUDE, quadVaryings("in"), PAPER_FRAGMENT_MAIN)
    private val textureFragment = join(PRELUDE, quadVaryings("in"), TEXTURE_FRAGMENT_MAIN)
    private val pageShadowFragment = join(PRELUDE, quadVaryings("in"), PAGE_SHADOW_FRAGMENT_MAIN)

    private fun program(name: String, vertex: String, fragment: String, blend: Blend) =
        ProgramSource(name, VERSION + vertex, VERSION + fragment, blend)

    /** ribbon_vertex + ink_fragment: every pen but the highlighter (depth write; blend-once pens run it twice). */
    val ink = program("ink", ribbonVertex, inkFragment, Blend.PREMULTIPLIED)

    /** ribbon_vertex + highlighter_fragment: multiply under the ink. */
    val highlighter = program("highlighter", ribbonVertex, highlighterFragment, Blend.MULTIPLY)

    /** ribbon_shadow_vertex + shadow_fragment: the raised inks' soft shadow (always drawn once). */
    val shadow = program("shadow", shadowVertex, shadowFragment, Blend.PREMULTIPLIED)

    /** quad_vertex + paper_fragment: blank, ruled, squared and dotted paper. */
    val paper = program("paper", quadVertex, paperFragment, Blend.OPAQUE)

    /** quad_vertex + page_shadow_fragment: the soft shadow round a page. */
    val pageShadow = program("pageShadow", quadVertex, pageShadowFragment, Blend.ALPHA)

    /** quad_vertex + texture_fragment: a PDF page or a template picture. */
    val texture = program("texture", quadVertex, textureFragment, Blend.OPAQUE)

    /** blade_vertex + blade_fragment: grass blades, flower stems, the glass stems and leaves. */
    val blade = program("blade", bladeVertex, bladeFragment, Blend.PREMULTIPLIED)

    /** flower_vertex + flower_fragment: the flowers on their stems. */
    val flower = program("flower", flowerVertex, flowerFragment, Blend.PREMULTIPLIED)

    val programs: List<ProgramSource> = listOf(ink, highlighter, shadow, paper, pageShadow, texture, blade, flower)
}
