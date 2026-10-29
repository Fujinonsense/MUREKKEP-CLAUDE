package com.murekkep.notebook.export

import com.murekkep.notebook.ink.InkColor
import com.murekkep.notebook.ink.InkPoint
import com.murekkep.notebook.ink.Vec3
import com.murekkep.notebook.ink.vlength
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sin

// The numbers behind Murekkep.swiftpm/FlatInk.swift, kept away from android.graphics so the JVM
// tests can check them: the plain line's width, the runs a polyline is stroked in, the beads and
// sparkles along a stroke, the glass flower's proportions, the glow's blur and the colour helpers
// (UIColorComponents at the end of FlatInk.swift). FlatInk.kt draws with them.

/** A small round thing on the page: a pearl, a sparkle. */
data class Spot(val x: Float, val y: Float, val r: Float)

/** Points `first`...`last` of a polyline, stroked as one path `diameter` wide (before the brush's
 *  width scale). */
data class PolylineRun(val first: Int, val last: Int, val diameter: Float)

/** The glass flower's proportions: `seed` turns its stamens, `aspect` squeezes it (a touch wider
 *  than tall). */
data class GlassFlowerShape(val seed: Float, val aspect: Float)

object FlatInkGeometry {
    /** The even dark line of `drawPlain`: a little over half the pen's width, never hairline-thin
     *  nor fat, so every pen reads the same to text recognition. */
    fun plainWidth(strokeWidth: Float): Float = min(max(strokeWidth * 0.55f, 1.4f), 3.0f)

    /** The colour moved `amount` of the way to white (`color(_:lighten:)` on iPad); the alpha stays. */
    fun lighten(c: InkColor, amount: Float): InkColor = InkColor(
        c.r + (1f - c.r) * amount,
        c.g + (1f - c.g) * amount,
        c.b + (1f - c.b) * amount,
        c.a,
    )

    /** The 8-bit ARGB int android.graphics.Paint takes: components clamped to 0...1 and rounded
     *  (the iPad's CGColor keeps floats; the difference is below what a PDF viewer shows). */
    fun argb(r: Float, g: Float, b: Float, a: Float): Int =
        (channel(a) shl 24) or (channel(r) shl 16) or (channel(g) shl 8) or channel(b)

    fun argb(c: InkColor): Int = argb(c.r, c.g, c.b, c.a)

    fun argb(c: Vec3, a: Float): Int = argb(c.x, c.y, c.z, a)

    private fun channel(v: Float): Int = if (v.isNaN()) 0 else (min(max(v, 0f), 1f) * 255f).roundToInt()

    /**
     * How `drawPolyline` strokes a stroke: runs of similar radius (within 8% of the run's first
     * point, at most 49 points) become one path at their mean diameter, to keep the output small.
     * Runs share their end points, so the line has no gaps.
     */
    fun polylineRuns(pts: List<InkPoint>): List<PolylineRun> {
        val runs = ArrayList<PolylineRun>()
        var i = 0
        while (i < pts.size - 1) {
            val r0 = pts[i].r
            var j = i + 1
            var sum = pts[i].r + pts[j].r
            var n = 2f
            while (j + 1 < pts.size && abs(pts[j + 1].r - r0) <= r0 * 0.08f && j - i < 48) {
                j++
                sum += pts[j].r
                n++
            }
            runs.add(PolylineRun(i, j, sum / n * 2f))
            i = j
        }
        return runs
    }

    /**
     * Where `drawAlong` calls its body: at regular distances along the stroke, the spacing taken
     * from the local radius (never under a point). A single point gets one spot.
     */
    fun along(pts: List<InkPoint>, spacing: (Float) -> Float): List<Spot> {
        val first = pts.firstOrNull() ?: return emptyList()
        if (pts.size == 1) return listOf(Spot(first.x, first.y, first.r))
        val spots = ArrayList<Spot>()
        var next = 0f
        var travelled = 0f
        for (i in 0 until pts.size - 1) {
            val a = pts[i]
            val b = pts[i + 1]
            val len = vlength(b.position - a.position)
            while (next <= travelled + len) {
                val t = if (len > 0f) (next - travelled) / len else 0f
                val r = a.r + (b.r - a.r) * t
                spots.add(Spot(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, r))
                next += max(spacing(r), 1f)
            }
            travelled += len
        }
        return spots
    }

    /**
     * The glitter's and the galaxy's sparkles: every other point rolls a stable hash (the low 16
     * bits of the index times the golden-ratio constant); the high rolls place a white dot a
     * little off the line, bigger for wider ink. A single point never sparkles.
     */
    fun sparkles(pts: List<InkPoint>): List<Spot> {
        if (pts.size < 2) return emptyList()
        val spots = ArrayList<Spot>()
        for (i in pts.indices step 2) {
            val p = pts[i]
            val h = ((i.toLong() * 2_654_435_761L) and 0xFFFFL).toFloat() / 65_535f
            if (h <= 0.55f) continue
            val angle = h * 40f
            val off = p.r * 0.6f * h
            spots.add(Spot(p.x + cos(angle) * off, p.y + sin(angle) * off, max(0.35f, p.r * 0.14f)))
        }
        return spots
    }

    /**
     * The radius for `Paint.setShadowLayer` that gives the iPad's `setShadow(blur:)`: Core Graphics
     * blurs with a Gaussian whose standard deviation is `blur`, Skia turns a radius into
     * `0.57735 * radius + 0.5`. Never zero, which would switch the shadow off.
     */
    fun shadowRadius(blur: Float): Float = max(0.25f, (blur - 0.5f) / 0.57735f)

    /** The rainbow's hue after `arc` points of line: one full cycle every 220 points, as the shader. */
    fun rainbowHue(baseHue: Float, arc: Float): Float = (baseHue + arc / 220f) % 1f

    fun glassFlowerShape(spin: Float, radius: Float): GlassFlowerShape {
        val seed = (spin * 0.15915494f + radius * 0.731f) % 1f
        val aspect = 0.78f + 0.17f * ((seed * 7.13f + 0.37f) % 1f)
        return GlassFlowerShape(seed, aspect)
    }
}

data class Hsv(val h: Float, val s: Float, val v: Float)

/** HSV helpers shared by the rainbow brush (UIColorComponents on iPad). Hue, saturation and value
 *  in 0...1. */
object ColorComponents {
    fun hsv(r: Float, g: Float, b: Float): Hsv {
        val mx = max(r, max(g, b))
        val mn = min(r, min(g, b))
        val d = mx - mn
        var h = 0f
        if (d > 1e-5f) {
            h = when {
                mx == r -> ((g - b) / d) % 6f
                mx == g -> (b - r) / d + 2f
                else -> (r - g) / d + 4f
            }
            h /= 6f
            if (h < 0f) h += 1f
        }
        return Hsv(h, if (mx > 0f) d / mx else 0f, mx)
    }

    /** The colour of a hue, saturation and value, opaque. */
    fun rgb(h: Float, s: Float, v: Float): InkColor {
        fun k(n: Float): Float {
            val x = (n + h * 6f) % 6f
            return v - v * s * max(0f, min(x, min(4f - x, 1f)))
        }
        return InkColor(k(5f), k(3f), k(1f), 1f)
    }
}
