package com.murekkep.notebook.ink

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

// The lasso's ink logic from the iPad: which strokes a loop takes and which one a tap picks
// (EditorModel.swift selectStrokes, selectItem), what a touch on the selection's frame does
// (CanvasView.swift selectionGrab), the selection moved, resized and turned (transformSelection,
// with the turn settling at right angles as in lassoMoved) and the ticks the pen plays along the
// loop (tests/ports/lasso.py dash_ticks). Points are page-local, as the iPad's selection; lengths
// "on screen" are in dp, the iPad's view points.

/** Strokes picked with the lasso on one page, and the box around them (page points, radius included). */
data class InkSelection(val page: Int, val ids: Set<Int>, val bounds: InkRect)

/** What a touch on the selection does while it moves. */
sealed class SelectionDrag {
    /** Inside the frame: moves the selection. */
    data class Move(val start: Vec2) : SelectionDrag()

    /** A corner: resizes it, the opposite corner of the box stays put. */
    data class Scale(val anchor: Vec2, val startDistance: Float) : SelectionDrag()

    /** The handle above the frame: turns it around the middle of its box. */
    data class Rotate(val center: Vec2, val startAngle: Float) : SelectionDrag()
}

object Lasso {
    /** dp between the selection's box and its dashed frame. */
    const val FRAME_PAD = 8f

    /** dp between the frame and its turn handle (CanvasOverlayView.turnHandleOffset). */
    const val TURN_HANDLE_OFFSET = 30f

    /** How far from a handle (dp) the pen still takes it. */
    const val REACH = 24f

    /** The loop's dash and gap in dp (CanvasOverlayView.lassoDash). */
    const val DASH = 6f
    const val GAP = 4f

    /** A loop shorter than this (dp) is a tap: it picks the stroke under the pen. */
    const val TAP_LENGTH = 10f

    /** Whether (x, y) is inside the closed polygon by the nonzero winding rule, as CGPath.contains
     *  fills a loop: a lasso that crosses itself still takes what its outer loop goes round. */
    fun contains(polygon: List<Vec2>, x: Float, y: Float): Boolean {
        if (polygon.size < 3) return false
        var winding = 0
        var a = polygon[polygon.size - 1]
        for (b in polygon) {
            if (a.y <= y) {
                if (b.y > y && cross(a, b, x, y) > 0) winding++
            } else if (b.y <= y && cross(a, b, x, y) < 0) {
                winding--
            }
            a = b
        }
        return winding != 0
    }

    /** > 0 when (x, y) is left of the line a→b (y down: clockwise on screen). */
    private fun cross(a: Vec2, b: Vec2, x: Float, y: Float): Float =
        (b.x - a.x) * (y - a.y) - (x - a.x) * (b.y - a.y)

    /** The strokes that lie mostly inside the loop: at least half of up to about 24 of their points. */
    fun select(strokes: List<Stroke>, polygon: List<Vec2>): Set<Int> {
        if (polygon.size < 3) return emptySet()
        val ids = HashSet<Int>()
        for (s in strokes) {
            val pts = s.points
            if (pts.isEmpty()) continue
            val step = max(1, pts.size / 24)
            var inside = 0
            var total = 0
            var i = 0
            while (i < pts.size) {
                total++
                if (contains(polygon, pts[i].x, pts[i].y)) inside++
                i += step
            }
            if (inside * 2 >= total) ids.add(s.id)
        }
        return ids
    }

    /** The topmost stroke under a tap, within `tolerance` page points of its ink. */
    fun strokeAt(strokes: List<Stroke>, p: Vec2, tolerance: Float): Stroke? {
        for (s in strokes.asReversed()) {
            val b = s.bounds
            val pad = s.maxRadius + tolerance
            if (p.x < b.minX - pad || p.x > b.maxX + pad || p.y < b.minY - pad || p.y > b.maxY + pad) continue
            if (InkEraser.hits(s, p, p, tolerance)) return s
        }
        return null
    }

    /** The box around the strokes `ids`, null when none of them is there. */
    fun bounds(strokes: List<Stroke>, ids: Set<Int>): InkRect? {
        var box = InkRect.EMPTY
        for (s in strokes) {
            if (s.id !in ids || s.bounds.isEmpty) continue
            val b = s.bounds
            box = InkRect(min(box.minX, b.minX), min(box.minY, b.minY), max(box.maxX, b.maxX), max(box.maxY, b.maxY))
        }
        return if (box.isEmpty) null else box
    }

    /** What a touch at `p` (page points) does to the selection boxed by `bounds`: turn it (the handle
     *  above the frame), resize it (any corner; the opposite one stays put), move it (inside the
     *  frame), or nothing. `unit` is page points per dp at the current zoom. */
    fun grab(p: Vec2, bounds: InkRect, unit: Float, reach: Float = REACH): SelectionDrag? {
        val pad = FRAME_PAD * unit
        val left = bounds.minX - pad
        val top = bounds.minY - pad
        val right = bounds.maxX + pad
        val bottom = bounds.maxY + pad
        val r = reach * unit
        val midX = (left + right) / 2f
        val turnY = top - TURN_HANDLE_OFFSET * unit
        if (hypot(p.x - midX, p.y - turnY) < r) {
            val center = Vec2((bounds.minX + bounds.maxX) / 2f, (bounds.minY + bounds.maxY) / 2f)
            return SelectionDrag.Rotate(center, atan2(p.y - center.y, p.x - center.x))
        }
        val corners = listOf(Vec2(left, top), Vec2(right, top), Vec2(right, bottom), Vec2(left, bottom))
        val fixed = listOf(
            Vec2(bounds.maxX, bounds.maxY), Vec2(bounds.minX, bounds.maxY),
            Vec2(bounds.minX, bounds.minY), Vec2(bounds.maxX, bounds.minY),
        )
        for (i in corners.indices) {
            val c = corners[i]
            if (hypot(p.x - c.x, p.y - c.y) < r) {
                val anchor = fixed[i]
                return SelectionDrag.Scale(anchor, max(hypot(p.x - anchor.x, p.y - anchor.y), 1f))
            }
        }
        if (p.x in left..right && p.y in top..bottom) return SelectionDrag.Move(p)
        return null
    }

    /** `strokes` with the ones in `ids` scaled by `scale` and turned by `rotation` radians around
     *  `anchor`, then moved by `offset`. Moved strokes are new strokes (new ids) with the same look
     *  and birth; radii and widths follow the scale. */
    fun transform(strokes: List<Stroke>, ids: Set<Int>, offset: Vec2, scale: Float, anchor: Vec2, rotation: Float): List<Stroke> {
        val k = scale.toDouble().coerceIn(0.05, 20.0)
        val kf = k.toFloat()
        val c = cos(rotation.toDouble())
        val s = sin(rotation.toDouble())
        val ax = anchor.x.toDouble()
        val ay = anchor.y.toDouble()
        return strokes.map { stroke ->
            if (stroke.id !in ids) {
                stroke
            } else {
                val pts = stroke.points.map { p ->
                    val u = (p.x - ax) * k
                    val v = (p.y - ay) * k
                    InkPoint((ax + u * c - v * s + offset.x).toFloat(), (ay + u * s + v * c + offset.y).toFloat(), p.r * kf, p.ink)
                }
                Stroke(stroke.brush, stroke.color, stroke.width * kf, stroke.birth, stroke.seed, pts, stroke.duration)
            }
        }
    }

    /** The same strokes `dy` page points lower (a selection carried to another page, or duplicated). */
    fun shifted(strokes: List<Stroke>, dx: Float, dy: Float): List<Stroke> = strokes.map { s ->
        Stroke(s.brush, s.color, s.width, s.birth, s.seed, s.points.map { InkPoint(it.x + dx, it.y + dy, it.r, it.ink) }, s.duration)
    }

    /** The turn of a selection settles at right angles (0°, 90°, 180°, 270°) within 7°, free in
     *  between. Returns the angle to use and, when it settled, the right angle in degrees. */
    fun settleTurn(angle: Float): Pair<Float, Int?> {
        val step = PI / 2
        val a = wrap(angle.toDouble())
        val nearest = roundHalfAway(a / step) * step
        if (abs(a - nearest) < 7 * PI / 180) {
            return Pair(nearest.toFloat(), roundHalfAway(nearest * 180 / PI).toInt())
        }
        return Pair(a.toFloat(), null)
    }

    /** An angle in -π...π (Geo.wrap). */
    fun wrap(a: Double): Double {
        var x = a
        while (x > PI) x -= 2 * PI
        while (x < -PI) x += 2 * PI
        return x
    }

    /** How many dash periods (dash and gap) a loop of `length` dp has passed: the pen ticks each time
     *  this grows. */
    fun dashCount(length: Float): Int = floor(length / (DASH + GAP)).toInt()

    /** Swift's rounded(): halves away from zero (Kotlin's round() takes them to even). */
    private fun roundHalfAway(x: Double): Double = if (x >= 0) floor(x + 0.5) else -floor(-x + 0.5)
}
