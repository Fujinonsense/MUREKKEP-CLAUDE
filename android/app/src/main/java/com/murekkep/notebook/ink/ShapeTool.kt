package com.murekkep.notebook.ink

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

// Port of the shape tool of Murekkep.swiftpm/Instruments.swift (`ShapeKind`, `ShapeBuilder`: the
// pen paths of a shape dragged from one point to another, its live measurement, arrow heads and
// dashes) and of `snappedShapeEnd` in Murekkep.swiftpm/CanvasView.swift (where the drag's end
// settles). Same numbers as the iPad; the paths are Float like the ink, as there.
//
// Left out until Android has the stroke font (StrokeFont.swift): the `axes` ("Koordinat ekseni")
// and `dimension` ("Ölçü çizgisi") kinds, which write labels with it, and `plot`, which does too.
// The drafting instruments of the same file (ruler, set squares, protractor) are a separate port.

/**
 * Float.pi of the iPad: Swift rounds it toward zero, to 3.1415925 (bits 0x40490FDA), not to the
 * nearest Float 3.1415927; the ellipse's and the polygon's corners turn by multiples of it.
 */
private const val PI_F = 3.1415925f

/** The shape tool's shapes, in the iPad's order; `raw` is the iPad's stored value, `shapeName` its title. */
enum class ShapeKind(val raw: String, val shapeName: ShapeName) {
    LINE("line", ShapeName.LINE),
    ARROW("arrow", ShapeName.ARROW),
    DOUBLE_ARROW("doubleArrow", ShapeName.DOUBLE_ARROW),
    RECTANGLE("rectangle", ShapeName.RECTANGLE),
    ELLIPSE("ellipse", ShapeName.ELLIPSE),
    /** Dragged from the center to a point on the circle. */
    CIRCLE("circle", ShapeName.CIRCLE_FROM_CENTER),
    TRIANGLE("triangle", ShapeName.TRIANGLE),
    RIGHT_TRIANGLE("rightTriangle", ShapeName.RIGHT_TRIANGLE),
    /** A regular polygon around the start, its first corner at the end. */
    POLYGON("polygon", ShapeName.REGULAR_POLYGON);

    companion object {
        /** Unknown raw values (the iPad's axes and dimension, which Android has not yet) read as the line. */
        fun fromRaw(raw: String): ShapeKind = entries.firstOrNull { it.raw == raw } ?: LINE
    }
}

/**
 * The live label of a shape being dragged ("42,3 mm · 30°", "r = 18 mm", "20 mm × 15 mm"): the
 * iPad's `ShapeBuilder.measurement`, as data; [format] writes it with the UI's decimal separator.
 */
sealed class ShapeMeasurement {
    abstract fun format(decimalSeparator: Char = ','): String

    /** Boxes, ovals and triangles: the drag's width and height. */
    data class Size(val widthMm: Double, val heightMm: Double) : ShapeMeasurement() {
        override fun format(decimalSeparator: Char): String =
            "${ShapeBuilder.mm(widthMm, decimalSeparator)} × ${ShapeBuilder.mm(heightMm, decimalSeparator)}"
    }

    /** Circles and regular polygons: the radius. */
    data class Radius(val radiusMm: Double) : ShapeMeasurement() {
        override fun format(decimalSeparator: Char): String = "r = ${ShapeBuilder.mm(radiusMm, decimalSeparator)}"
    }

    /** Lines and arrows: the length and the angle (0…360°, counterclockwise as on paper). */
    data class Length(val lengthMm: Double, val degrees: Int) : ShapeMeasurement() {
        override fun format(decimalSeparator: Char): String = "${ShapeBuilder.mm(lengthMm, decimalSeparator)} · $degrees°"
    }
}

/** Geometry of the shape tool's shapes and measurement labels as pen paths (page-local, y down). */
object ShapeBuilder {
    /** The paths of a shape dragged from `from` to `to`; `sides` is for the regular polygon (3…24). */
    fun paths(kind: ShapeKind, from: Pt, to: Pt, sides: Int): List<List<Vec2>> {
        val p = Vec2(from.x.toFloat(), from.y.toFloat())
        val q = Vec2(to.x.toFloat(), to.y.toFloat())
        return when (kind) {
            ShapeKind.LINE -> listOf(listOf(p, q))
            ShapeKind.ARROW -> listOf(arrowPath(p, q))
            ShapeKind.DOUBLE_ARROW -> listOf(arrowPath(p, q), head(p, q))
            ShapeKind.RECTANGLE -> listOf(listOf(p, Vec2(q.x, p.y), q, Vec2(p.x, q.y), p))
            ShapeKind.ELLIPSE -> {
                val c = (p + q) / 2f
                val r = Vec2(abs(q.x - p.x), abs(q.y - p.y)) / 2f
                listOf(ellipse(c, r.x, r.y))
            }
            ShapeKind.CIRCLE -> {
                val r = vlength(q - p)
                listOf(ellipse(p, r, r))
            }
            ShapeKind.TRIANGLE -> listOf(listOf(Vec2(p.x, q.y), Vec2((p.x + q.x) / 2f, p.y), q, Vec2(p.x, q.y)))
            ShapeKind.RIGHT_TRIANGLE -> listOf(listOf(p, Vec2(p.x, q.y), q, p))
            ShapeKind.POLYGON -> {
                val r = vlength(q - p)
                val start = atan2(q.y - p.y, q.x - p.x)
                val n = max(3, min(sides, 24))
                val pts = (0..n).map { i ->
                    val ang = start + i.toFloat() * 2f * PI_F / n.toFloat()
                    p + Vec2(cos(ang), sin(ang)) * r
                }
                listOf(pts)
            }
        }
    }

    /** Length of a shape for the live label ("42,3 mm", "r = 18 mm"). */
    fun measurement(kind: ShapeKind, from: Pt, to: Pt): ShapeMeasurement {
        val dx = (to.x - from.x) / POINTS_PER_MILLIMETRE
        val dy = (to.y - from.y) / POINTS_PER_MILLIMETRE
        val len = hypot(dx, dy)
        var angle = atan2(-dy, dx) * 180 / PI
        if (angle < 0) angle += 360
        return when (kind) {
            ShapeKind.RECTANGLE, ShapeKind.ELLIPSE, ShapeKind.TRIANGLE, ShapeKind.RIGHT_TRIANGLE ->
                ShapeMeasurement.Size(abs(dx), abs(dy))
            ShapeKind.CIRCLE, ShapeKind.POLYGON -> ShapeMeasurement.Radius(len)
            else -> ShapeMeasurement.Length(len, roundedAwayToInt(angle))
        }
    }

    /**
     * A length in millimetres written as the iPad does: to a tenth, in centimetres from 10 cm
     * ("42,3 mm", "12,5 cm", "8 mm"); `decimalSeparator` is the UI language's (the iPad's
     * `MathFormat.decimal` writes a comma in Turkish and a point in English).
     */
    fun mm(v: Double, decimalSeparator: Char = ','): String {
        if (v >= 100) {
            return decimal(roundedAway(v / 10 * 10) / 10, decimalSeparator) + " cm"
        }
        return decimal(roundedAway(v * 10) / 10, decimalSeparator) + " mm"
    }

    /** `MathFormat.decimal` for the tenths [mm] hands it: no grouping, no fraction when there is none. */
    private fun decimal(v: Double, decimalSeparator: Char): String {
        val tenths = roundedAway(v * 10).toLong()
        val sign = if (tenths < 0) "-" else ""
        val a = abs(tenths)
        val whole = a / 10
        val fraction = a % 10
        return if (fraction == 0L) "$sign$whole" else "$sign$whole$decimalSeparator$fraction"
    }

    fun arrowPath(p: Vec2, q: Vec2): List<Vec2> {
        val d = q - p
        val len = vlength(d)
        if (!(len > 0.5f)) return listOf(p, q)
        val u = d / len
        val n = Vec2(-u.y, u.x)
        val size = min(max(len * 0.18f, 6f), 16f)
        val left = q - u * size + n * size * 0.45f
        val right = q - u * size - n * size * 0.45f
        return listOf(p, q, left, q, right)
    }

    /** An arrow head at `p` for a line coming from `q`. */
    fun head(p: Vec2, q: Vec2): List<Vec2> {
        val d = p - q
        val len = vlength(d)
        if (!(len > 0.5f)) return listOf(p)
        val u = d / len
        val n = Vec2(-u.y, u.x)
        val size = min(max(len * 0.18f, 6f), 16f)
        return listOf(p - u * size + n * size * 0.45f, p, p - u * size - n * size * 0.45f)
    }

    fun ellipse(center: Vec2, rx: Float, ry: Float): List<Vec2> {
        val n = max(24, min(160, ((rx + ry) * 0.6f).toInt()))
        return (0..n).map { i ->
            val a = i.toFloat() / n.toFloat() * 2f * PI_F
            center + Vec2(cos(a) * rx, sin(a) * ry)
        }
    }

    /** Breaks paths into dashes (lengths in points). */
    fun dashed(paths: List<List<Vec2>>, dash: Float = 6f, gap: Float = 4f): List<List<Vec2>> {
        val out = ArrayList<List<Vec2>>()
        for (path in paths) {
            if (path.size < 2) continue
            var current = ArrayList<Vec2>()
            current.add(path[0])
            var drawing = true
            var left = dash
            for (i in 1 until path.size) {
                var a = path[i - 1]
                val b = path[i]
                var segment = vlength(b - a)
                while (segment > 0) {
                    val step = min(left, segment)
                    val point = a + (b - a) * (step / max(vlength(b - a), 1e-6f))
                    if (drawing) current.add(point)
                    segment -= step
                    left -= step
                    a = point
                    if (left <= 1e-4f) {
                        if (drawing) {
                            if (current.size >= 2) out.add(current)
                            current = ArrayList()
                        } else {
                            current = ArrayList()
                            current.add(a)
                        }
                        drawing = !drawing
                        left = if (drawing) dash else gap
                    }
                }
            }
            if (drawing && current.size >= 2) out.add(current)
        }
        return out
    }

    /**
     * Where the drag from `from` ends for `p` under the pen: lines and arrows click to 15° steps;
     * boxes and ovals to squares when nearly square (the iPad's `CanvasView.snappedShapeEnd`).
     */
    fun snappedEnd(kind: ShapeKind, p: Pt, from: Pt): Pt {
        val a = from
        val dx = p.x - a.x
        val dy = p.y - a.y
        return when (kind) {
            ShapeKind.LINE, ShapeKind.ARROW, ShapeKind.DOUBLE_ARROW -> {
                val len = hypot(dx, dy)
                val angle = atan2(dy, dx)
                val step = PI / 12
                val nearest = roundedAway(angle / step) * step
                if (abs(angle - nearest) < 0.05) Pt(a.x + cos(nearest) * len, a.y + sin(nearest) * len) else p
            }
            ShapeKind.RECTANGLE, ShapeKind.ELLIPSE -> {
                if (abs(abs(dx) - abs(dy)) < max(abs(dx), abs(dy)) * 0.06) {
                    val s = max(abs(dx), abs(dy))
                    Pt(a.x + (if (dx < 0) -s else s), a.y + (if (dy < 0) -s else s))
                } else {
                    p
                }
            }
            else -> p
        }
    }
}
