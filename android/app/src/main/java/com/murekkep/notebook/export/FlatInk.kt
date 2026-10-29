package com.murekkep.notebook.export

import android.graphics.BlendMode
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.os.Build
import com.murekkep.notebook.ink.BladeKind
import com.murekkep.notebook.ink.Brush
import com.murekkep.notebook.ink.GrassField
import com.murekkep.notebook.ink.GrassFlower
import com.murekkep.notebook.ink.GrassGenerator
import com.murekkep.notebook.ink.InkColor
import com.murekkep.notebook.ink.InkPoint
import com.murekkep.notebook.ink.Stroke
import com.murekkep.notebook.ink.Vec2
import com.murekkep.notebook.ink.Vec3
import com.murekkep.notebook.ink.vlength
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

// Port of Murekkep.swiftpm/FlatInk.swift: the 2D version of the ink (Core Graphics on iPad,
// android.graphics here), used for PDF export. Every pen's still, flat likeness with the iPad's
// numbers: the highlighter multiplies, the pencil fades with its ink, the watercolor washes thin,
// glitter and galaxy sparkle, the rainbow cycles its hue along the line, grass and the flowering
// water grow GrassGenerator's blades and flowers, neon, lava and lightning glow, pearls are beads,
// the raised inks (fountain, gold, chrome, oil, ice, jelly) get a light streak.
//
// Core Graphics to android.graphics: a stroked path is a Paint.Style.STROKE paint with round caps
// and joins where the iPad sets them; fillEllipse is Canvas.drawOval; setShadow (a soft glow in the
// ink's colour under what is drawn, blur = sigma) is Paint.setShadowLayer with the radius Skia turns
// into that sigma, which the PDF backend rasterizes; the multiply blend is BlendMode.MULTIPLY, a
// PDF blend mode, so an imported page's text stays readable under the highlighter. The iPad's
// transparency layers around the watercolor and pencil lines are left out: composited with full
// alpha, no shadow and normal blending they change nothing.

object FlatInk {
    /** Draws the strokes into a canvas whose units are page points (origin top-left, y down):
     *  highlighters first, under the ink, as on screen. */
    fun draw(strokes: List<Stroke>, canvas: Canvas) {
        canvas.save()
        for (s in strokes) {
            if (s.brush == Brush.HIGHLIGHTER) drawHighlighter(s, canvas)
        }
        for (s in strokes) {
            if (s.brush != Brush.HIGHLIGHTER) drawInk(s, canvas)
        }
        canvas.restore()
    }

    /** Every stroke as an even, dark line (for text recognition: no foam, beads, glow or blades). */
    fun drawPlain(strokes: List<Stroke>, canvas: Canvas) {
        val dark = FlatInkGeometry.argb(0.05f, 0.05f, 0.08f, 1f)
        val dot = fillPaint(dark)
        val line = strokePaint(dark, 1f)
        for (s in strokes) {
            if (s.brush == Brush.HIGHLIGHTER) continue
            val first = s.points.firstOrNull() ?: continue
            val width = FlatInkGeometry.plainWidth(s.width)
            if (s.points.size == 1) {
                val r = width * 0.6f
                canvas.drawOval(first.x - r, first.y - r, first.x + r, first.y + r, dot)
                continue
            }
            line.strokeWidth = width
            canvas.drawPath(path(s.points, 0, s.points.size - 1), line)
        }
    }

    /** The glow Core Graphics' setShadow gives: a blur in a colour, under what is drawn. */
    private class Glow(val blur: Float, val color: InkColor)

    private fun fillPaint(color: Int) = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
        this.color = color
    }

    /** A line as drawPolyline strokes it: round caps and joins. */
    private fun strokePaint(color: Int, width: Float) = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        this.color = color
        strokeWidth = width
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
    }

    /** A line as Core Graphics strokes it by default: butt caps, mitered joins up to 10x. */
    private fun plainStrokePaint(color: Int, width: Float) = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        this.color = color
        strokeWidth = width
        strokeMiter = 10f
    }

    private fun Paint.glowing(glow: Glow?): Paint {
        if (glow != null) {
            setShadowLayer(FlatInkGeometry.shadowRadius(glow.blur), 0f, 0f, FlatInkGeometry.argb(glow.color))
        }
        return this
    }

    /** Multiply blending; the Porter-Duff multiply of older systems is the same on an opaque page. */
    private fun Paint.multiplied(): Paint {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            blendMode = BlendMode.MULTIPLY
        } else {
            xfermode = PorterDuffXfermode(PorterDuff.Mode.MULTIPLY)
        }
        return this
    }

    private fun path(pts: List<InkPoint>, first: Int, last: Int): Path {
        val path = Path()
        path.moveTo(pts[first].x, pts[first].y)
        for (k in first + 1..last) {
            path.lineTo(pts[k].x, pts[k].y)
        }
        return path
    }

    private fun mean(pts: List<InkPoint>, of: (InkPoint) -> Float): Float {
        var sum = 0f
        for (p in pts) sum += of(p)
        return sum / pts.size
    }

    private fun degrees(radians: Float): Float = radians * (180f / PI.toFloat())

    private fun drawHighlighter(s: Stroke, canvas: Canvas) {
        val first = s.points.firstOrNull() ?: return
        val c = FlatInkGeometry.argb(s.color)
        if (s.points.size == 1) {
            val r = first.r
            canvas.drawOval(first.x - r, first.y - r, first.x + r, first.y + r, fillPaint(c).multiplied())
        } else {
            val avg = mean(s.points) { it.r }
            canvas.drawPath(path(s.points, 0, s.points.size - 1), strokePaint(c, avg * 2f).multiplied())
        }
    }

    private fun drawInk(s: Stroke, canvas: Canvas) {
        val pts = s.points
        when (s.brush) {
            Brush.RAINBOW -> drawRainbow(s, canvas)
            Brush.GRASS -> drawGrass(s, canvas)
            Brush.BLOOM -> drawBloom(s, canvas)
            Brush.NEON -> {
                drawPolyline(pts, FlatInkGeometry.lighten(s.color, 0.15f), 1f, canvas, Glow(s.width * 2.2f, s.color))
                drawPolyline(pts, FlatInkGeometry.lighten(s.color, 0.7f), 0.45f, canvas)
            }
            Brush.WATERCOLOR -> drawPolyline(pts, s.color.copy(a = s.color.a * 0.42f), 1f, canvas)
            Brush.PENCIL -> {
                val avg = if (pts.isEmpty()) 1f else mean(pts) { it.ink }
                drawPolyline(pts, s.color.copy(a = s.color.a * min(1f, 0.25f + avg * 0.75f)), 1f, canvas)
            }
            Brush.GLITTER -> {
                drawPolyline(pts, FlatInkGeometry.lighten(s.color, 0.1f), 1f, canvas)
                drawSparkles(pts, canvas)
            }
            Brush.WAVE -> drawPolyline(pts, FlatInkGeometry.lighten(s.color, 0.12f), 1f, canvas)
            Brush.SEA -> {
                // As the shader draws it: foam along both shores, the water over it, turquoise shallows.
                drawPolyline(pts, InkColor(0.97f, 0.99f, 1f, 0.85f * s.color.a), 1.02f, canvas)
                drawPolyline(pts, FlatInkGeometry.lighten(s.color, 0.1f), 0.78f, canvas)
                val shallows = InkColor(
                    s.color.r + (0.36f - s.color.r) * 0.7f,
                    s.color.g + (0.96f - s.color.g) * 0.7f,
                    s.color.b + (0.88f - s.color.b) * 0.7f,
                    s.color.a * 0.75f,
                )
                drawPolyline(pts, shallows, 0.32f, canvas)
            }
            Brush.LAVA -> {
                // Exports show the cooled crust with glowing cracks.
                drawPolyline(pts, InkColor(0.13f, 0.08f, 0.07f, 1f), 1f, canvas)
                drawPolyline(pts, FlatInkGeometry.lighten(s.color, 0.25f), 0.3f, canvas, Glow(s.width * 0.8f, s.color))
            }
            Brush.LIGHTNING -> {
                drawPolyline(pts, FlatInkGeometry.lighten(s.color, 0.3f), 0.8f, canvas, Glow(s.width * 2.4f, s.color))
                drawPolyline(pts, InkColor(1f, 1f, 1f, 0.95f), 0.35f, canvas)
            }
            Brush.GALAXY -> {
                drawPolyline(pts, InkColor(s.color.r * 0.35f, s.color.g * 0.3f, s.color.b * 0.45f, s.color.a), 1f, canvas)
                drawSparkles(pts, canvas)
            }
            Brush.PEARL -> {
                val pearl = fillPaint(FlatInkGeometry.argb(s.color))
                val shine = fillPaint(FlatInkGeometry.argb(1f, 1f, 1f, 0.75f))
                for (b in FlatInkGeometry.along(pts) { it * 2f }) {
                    val r = b.r
                    canvas.drawOval(b.x - r * 0.92f, b.y - r * 0.92f, b.x + r * 0.92f, b.y + r * 0.92f, pearl)
                    canvas.drawOval(b.x - r * 0.5f, b.y - r * 0.6f, b.x - r * 0.5f + r * 0.45f, b.y - r * 0.6f + r * 0.4f, shine)
                }
            }
            Brush.ICE, Brush.JELLY -> {
                val a = s.color.a * (if (s.brush == Brush.ICE) 0.7f else 0.85f)
                drawPolyline(pts, s.color.copy(a = a), 1f, canvas)
                drawHighlight(s, 0.6f, canvas)
            }
            Brush.FOUNTAIN, Brush.GOLD, Brush.CHROME, Brush.IMPASTO -> {
                drawPolyline(pts, s.color, 1f, canvas)
                drawHighlight(s, if (s.brush == Brush.FOUNTAIN) 0.35f else 0.65f, canvas)
            }
            else -> drawPolyline(pts, s.color, 1f, canvas)
        }
    }

    /** A thin light streak towards the top-left, suggesting a raised, glossy surface. */
    private fun drawHighlight(s: Stroke, alpha: Float, canvas: Canvas) {
        canvas.save()
        canvas.translate(-s.width * 0.12f, -s.width * 0.15f)
        drawPolyline(s.points, InkColor(1f, 1f, 1f, alpha), 0.28f, canvas)
        canvas.restore()
    }

    private fun drawPolyline(pts: List<InkPoint>, color: InkColor, widthScale: Float, canvas: Canvas, glow: Glow? = null) {
        val first = pts.firstOrNull() ?: return
        val c = FlatInkGeometry.argb(color)
        if (pts.size == 1) {
            val r = first.r * widthScale
            canvas.drawOval(first.x - r, first.y - r, first.x + r, first.y + r, fillPaint(c).glowing(glow))
            return
        }
        // Group runs of similar width into one path to keep the output small.
        val paint = strokePaint(c, 1f).glowing(glow)
        for (run in FlatInkGeometry.polylineRuns(pts)) {
            paint.strokeWidth = run.diameter * widthScale
            canvas.drawPath(path(pts, run.first, run.last), paint)
        }
    }

    /** Same hue cycle as the shader: the hue moves with the distance along the stroke. */
    private fun drawRainbow(s: Stroke, canvas: Canvas) {
        val pts = s.points
        if (pts.size < 2) {
            drawPolyline(pts, s.color, 1f, canvas)
            return
        }
        val base = ColorComponents.hsv(s.color.r, s.color.g, s.color.b)
        val paint = strokePaint(0, 1f)
        var arc = 0f
        for (i in 0 until pts.size - 1) {
            val a = pts[i]
            val b = pts[i + 1]
            val rgb = ColorComponents.rgb(FlatInkGeometry.rainbowHue(base.h, arc), max(base.s, 0.25f), max(base.v, 0.35f))
            paint.color = FlatInkGeometry.argb(rgb.r, rgb.g, rgb.b, s.color.a)
            paint.strokeWidth = a.r + b.r
            canvas.drawLine(a.x, a.y, b.x, b.y, paint)
            arc += vlength(b.position - a.position)
        }
    }

    private fun drawSparkles(pts: List<InkPoint>, canvas: Canvas) {
        val white = fillPaint(FlatInkGeometry.argb(1f, 1f, 1f, 0.9f))
        for (sp in FlatInkGeometry.sparkles(pts)) {
            canvas.drawOval(sp.x - sp.r, sp.y - sp.r, sp.x + sp.r, sp.y + sp.r, white)
        }
    }

    /** Fully grown grass with open flowers. */
    private fun drawGrass(s: Stroke, canvas: Canvas) {
        // Soil line under the blades.
        drawPolyline(s.points, InkColor(s.color.r * 0.45f, s.color.g * 0.45f, s.color.b * 0.45f, 0.85f), 0.7f, canvas)
        drawField(GrassGenerator.field(s.points, s.width, s.color, s.seed), s.color.a, canvas)
    }

    /** The flowering water: the glossy line, then its flowers on their stems. */
    private fun drawBloom(s: Stroke, canvas: Canvas) {
        drawPolyline(s.points, s.color.copy(a = s.color.a * 0.85f), 1f, canvas)
        drawHighlight(s, 0.6f, canvas)
        drawField(GrassGenerator.blooms(s.points, s.width, s.color, s.seed), s.color.a, canvas)
    }

    /** Blades and stems, then the flowers at their tips. */
    private fun drawField(field: GrassField, alpha: Float, canvas: Canvas) {
        val fill = fillPaint(0)
        val edge = plainStrokePaint(0, 1f)
        for (b in field.blades) {
            val tip = GrassGenerator.pointOn(b, 1f)
            val mid = GrassGenerator.pointOn(b, 0.5f)
            val half = b.width * 0.5f
            val path = Path()
            if (b.kind == BladeKind.GLASS_LEAF) {
                // A leaf: pointed at both ends, bulging either side of its midline.
                val d = tip - b.base
                val dl = max(vlength(d), 1e-4f)
                val n = Vec2(-d.y, d.x) / dl * b.width
                path.moveTo(b.base.x, b.base.y)
                path.quadTo(mid.x - n.x, mid.y - n.y, tip.x, tip.y)
                path.quadTo(mid.x + n.x, mid.y + n.y, b.base.x, b.base.y)
            } else {
                path.moveTo(b.base.x - half, b.base.y)
                path.quadTo(mid.x - half * 0.6f, mid.y, tip.x, tip.y)
                path.quadTo(mid.x + half * 0.6f, mid.y, b.base.x + half, b.base.y)
            }
            path.close()
            val shade = if (b.kind == BladeKind.STEM) 0.9f else 1f
            // Glass stems and leaves are see-through, with a lighter edge.
            val glassAlpha = when (b.kind) {
                BladeKind.GLASS_STEM -> 0.74f
                BladeKind.GLASS_LEAF -> 0.6f
                else -> 1f
            }
            fill.color = FlatInkGeometry.argb(
                min(1f, b.color.x * shade), min(1f, b.color.y * shade), min(1f, b.color.z * shade), alpha * glassAlpha,
            )
            canvas.drawPath(path, fill)
            if (b.kind == BladeKind.GLASS_STEM || b.kind == BladeKind.GLASS_LEAF) {
                edge.color = FlatInkGeometry.argb(min(1f, b.color.x * 0.7f), min(1f, b.color.y * 0.9f), 1f, alpha * 0.35f)
                edge.strokeWidth = max(0.25f, b.width * 0.12f)
                canvas.drawPath(path, edge)
            }
        }
        for (f in field.flowers) {
            if (f.stem !in field.blades.indices) continue
            val center = GrassGenerator.pointOn(field.blades[f.stem], 1f)
            val r = f.radius
            if (f.style > 2.5f) {
                drawGlassFlower(f, center.x, center.y, r, alpha, canvas)
                continue
            }
            val count = max(4, f.petals.toInt())
            fill.color = FlatInkGeometry.argb(f.petal, 1f)
            val petalLength = r * 0.62f
            val petalWidth = if (f.style < 0.5f) r * 0.22f else r * 0.5f
            for (i in 0 until count) {
                val a = f.spin + i * 2f * PI.toFloat() / count
                canvas.save()
                canvas.translate(center.x, center.y)
                canvas.rotate(degrees(a))
                canvas.drawOval(r * 0.15f, -petalWidth / 2f, r * 0.15f + petalLength + r * 0.2f, petalWidth / 2f, fill)
                canvas.restore()
            }
            val coreR = r * (if (f.style < 0.5f) 0.3f else 0.2f)
            fill.color = FlatInkGeometry.argb(f.core, 1f)
            canvas.drawOval(center.x - coreR, center.y - coreR, center.x + coreR, center.y + coreR, fill)
        }
    }

    /**
     * The flowering water's glass flower, as the shader draws it: an outer whorl of long translucent
     * petals (pale centre, blue or violet tips), a shorter inner whorl turned half a petal, a pale
     * glowing heart and fine pale stamens; a touch wider than tall.
     */
    private fun drawGlassFlower(f: GrassFlower, cx: Float, cy: Float, r: Float, alpha: Float, canvas: Canvas) {
        val count = max(5, f.petals.toInt())
        val shape = FlatInkGeometry.glassFlowerShape(f.spin, f.radius)
        val seed = shape.seed
        val aspect = shape.aspect
        val tip = f.petal
        val pale = Vec3(
            f.core.x + (1f - f.core.x) * 0.25f, f.core.y + (1f - f.core.y) * 0.25f, f.core.z + (1f - f.core.z) * 0.25f,
        )
        val deep = Vec3(tip.x * 0.8f, tip.y * 0.74f, tip.z)
        val fill = fillPaint(0)
        val outline = plainStrokePaint(0, max(0.25f, r * 0.035f))

        // A leaf shape from t0 (0 = centre) to the tip; the cubic bows out to about the half-width.
        fun petalPath(length: Float, halfWidth: Float, t0: Float): Path {
            val hw = halfWidth * length
            val x0 = length * t0
            val span = length - x0
            val path = Path()
            path.moveTo(x0, 0f)
            path.cubicTo(x0 + span * 0.3f, hw * 1.4f, x0 + span * 0.8f, hw * 0.9f, length, 0f)
            path.cubicTo(x0 + span * 0.8f, -hw * 0.9f, x0 + span * 0.3f, -hw * 1.4f, x0, 0f)
            path.close()
            return path
        }

        fun whorl(length: Float, halfWidth: Float, offset: Float, paleAlpha: Float, tipAlpha: Float) {
            val petal = petalPath(length, halfWidth, 0f)
            val tipPart = petalPath(length, halfWidth * 0.92f, 0.42f)
            for (i in 0 until count) {
                val a = f.spin + (i + offset) * 2f * PI.toFloat() / count
                canvas.save()
                canvas.translate(cx, cy)
                canvas.scale(1f, aspect)
                canvas.rotate(degrees(a))
                fill.color = FlatInkGeometry.argb(pale, alpha * paleAlpha)
                canvas.drawPath(petal, fill)
                fill.color = FlatInkGeometry.argb(tip, alpha * tipAlpha)
                canvas.drawPath(tipPart, fill)
                outline.color = FlatInkGeometry.argb(deep, alpha * 0.4f)
                canvas.drawPath(petal, outline)
                canvas.restore()
            }
        }

        // A faint blue shadow, the whorls, then the heart.
        fill.color = FlatInkGeometry.argb(0.30f, 0.36f, 0.70f, alpha * 0.08f)
        canvas.drawOval(
            cx + r * 0.1f - r * 0.9f, cy + r * 0.14f - r * 0.9f * aspect,
            cx + r * 0.1f + r * 0.9f, cy + r * 0.14f + r * 0.9f * aspect, fill,
        )
        whorl(r, 0.38f - 0.03f * (count - 5), 0f, 0.42f, 0.55f)
        whorl(r * 0.58f, 0.40f, 0.5f, 0.32f, 0.36f)
        fill.color = FlatInkGeometry.argb(pale, alpha * 0.55f)
        canvas.drawOval(cx - r * 0.36f, cy - r * 0.36f * aspect, cx + r * 0.36f, cy + r * 0.36f * aspect, fill)
        val stamen = FlatInkGeometry.argb(
            0.98f + (tip.x - 0.98f) * 0.22f, 0.98f + (tip.y - 0.98f) * 0.22f, 1f + (tip.z - 1f) * 0.22f, alpha * 0.85f,
        )
        val thread = strokePaint(stamen, max(0.2f, r * 0.045f))
        fill.color = stamen
        for (k in 0 until 10) {
            val a = (k + seed) * 2f * PI.toFloat() / 10f
            val dx = cos(a)
            val dy = sin(a) * aspect
            canvas.drawLine(cx + dx * r * 0.05f, cy + dy * r * 0.05f, cx + dx * r * 0.30f, cy + dy * r * 0.30f, thread)
            val d = r * 0.045f
            canvas.drawOval(cx + dx * r * 0.30f - d, cy + dy * r * 0.30f - d, cx + dx * r * 0.30f + d, cy + dy * r * 0.30f + d, fill)
        }
        fill.color = FlatInkGeometry.argb(1f, 1f, 1f, alpha * 0.9f)
        canvas.drawOval(cx - r * 0.07f, cy - r * 0.07f, cx + r * 0.07f, cy + r * 0.07f, fill)
    }
}
