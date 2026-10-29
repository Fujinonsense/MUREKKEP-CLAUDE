package com.murekkep.notebook.ink

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.ceil
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt

// Port of Murekkep.swiftpm/ShapeRecognizer.swift: hold-to-shape. Same constants, same tests in the
// same order, same tie-breaking; the geometry it leans on is in Geo.kt. The iPad names its shapes
// with `Loc.t("…")` strings; here every name is a [ShapeName] and the UI puts the words to it.

/**
 * A name the shape code shows the user: the title of a recognized or drawn shape and the shape tool's
 * entries. One entry per `Loc.t` title of the iPad's ShapeRecognizer, ShapeEditing and Instruments;
 * [titleTr] is the iPad's Turkish key and [titleEn] its English translation.
 */
enum class ShapeName(val titleTr: String, val titleEn: String) {
    /** Doğru: a straight line. */
    LINE("Doğru", "Line"),
    /** Kırık çizgi: straight pieces joined at corners. */
    POLYLINE("Kırık çizgi", "Polyline"),
    /** Eğri: a smooth bend (a quadratic Bézier). */
    CURVE("Eğri", "Curve"),
    /** Daire. */
    CIRCLE("Daire", "Circle"),
    /** Elips. */
    ELLIPSE("Elips", "Ellipse"),
    /** Kare. */
    SQUARE("Kare", "Square"),
    /** Dikdörtgen. */
    RECTANGLE("Dikdörtgen", "Rectangle"),
    /** Üçgen: a triangle that is none of the special ones. */
    TRIANGLE("Üçgen", "Triangle"),
    /** Dik üçgen. */
    RIGHT_TRIANGLE("Dik üçgen", "Right triangle"),
    /** Eşkenar üçgen. */
    EQUILATERAL_TRIANGLE("Eşkenar üçgen", "Equilateral triangle"),
    /** İkizkenar üçgen. */
    ISOSCELES_TRIANGLE("İkizkenar üçgen", "Isosceles triangle"),
    /** Dörtgen: four corners that are not a rectangle. */
    QUADRILATERAL("Dörtgen", "Quadrilateral"),
    /** Beşgen. */
    PENTAGON("Beşgen", "Pentagon"),
    /** Altıgen. */
    HEXAGON("Altıgen", "Hexagon"),
    /** Yedigen. */
    HEPTAGON("Yedigen", "Heptagon"),
    /** Sekizgen. */
    OCTAGON("Sekizgen", "Octagon"),
    /** Çokgen: more corners than the named polygons (never produced today; the recognizer stops at eight). */
    POLYGON("Çokgen", "Polygon"),
    /** Ok: the shape tool's arrow. */
    ARROW("Ok", "Arrow"),
    /** Çift ok: the shape tool's arrow with a head at both ends. */
    DOUBLE_ARROW("Çift ok", "Double arrow"),
    /** Çember (merkezden): the shape tool's circle, dragged from its center. */
    CIRCLE_FROM_CENTER("Çember (merkezden)", "Circle (from the center)"),
    /** Düzgün çokgen: the shape tool's regular polygon. */
    REGULAR_POLYGON("Düzgün çokgen", "Regular polygon"),
}

/** A clean shape found in a hand-drawn stroke. `path` is page-local and ready to become ink. */
data class ShapeMatch(
    val kind: Kind,
    val name: ShapeName,
    val path: List<Pt>,
    /** Corners the user can drag after the pen lifts (polygons, rectangles, broken lines, lines). */
    val corners: List<Pt> = emptyList(),
    /** Set for circles and ellipses: their axes get handles instead of corners. */
    val oval: Oval? = null,
    /** Set for curves: the ends and the bend get handles. */
    val curve: Curve? = null,
) {
    enum class Kind {
        LINE,
        POLYLINE,
        POLYGON,
        RECTANGLE,
        CIRCLE,
        ELLIPSE,
        /** A smooth bend between two ends (a quadratic Bézier, so a piece of a parabola); no arrowhead. */
        CURVE,
    }

    /** Center, radii and turn of a circle or an ellipse. */
    data class Oval(val center: Pt, val rx: Double, val ry: Double, val angle: Double)

    /** The two ends of a curve and the control point between them. */
    data class Curve(val start: Pt, val control: Pt, val end: Pt) {
        fun point(t: Double): Pt {
            val u = 1 - t
            val x = u * u * start.x + 2 * u * t * control.x + t * t * end.x
            val y = u * u * start.y + 2 * u * t * control.y + t * t * end.y
            return Pt(x, y)
        }

        /** The point the curve passes through halfway, where its bend handle sits. */
        val middle: Pt get() = point(0.5)

        fun path(): List<Pt> {
            val length = Geo.dist(start, control) + Geo.dist(control, end)
            val n = max(24, min(240, ceil(length / 2).toInt()))
            return (0..n).map { i -> point(i.toDouble() / n.toDouble()) }
        }

        companion object {
            /** The control point that makes the curve pass through `m` halfway. */
            fun control(start: Pt, through: Pt, end: Pt): Pt =
                Pt(2 * through.x - (start.x + end.x) / 2, 2 * through.y - (start.y + end.y) / 2)
        }
    }

    /** Closed shapes turn and scale around their middle, open ones around where they started. */
    val isClosed: Boolean
        get() = when (kind) {
            Kind.POLYGON, Kind.RECTANGLE, Kind.CIRCLE, Kind.ELLIPSE -> true
            else -> false
        }
}

/**
 * Hold-to-shape: lines, broken lines, triangles, rectangles and other polygons, circles, ellipses
 * and curves. Real handwriting shakes, so the stroke is smoothed first and every possible
 * shape is fitted; the one with the smallest error wins, and only when it really follows the
 * drawing. Every test is relative to the drawing's size.
 *
 * Holding the pen still is a request for a shape, so the tests are forgiving: a crooked square
 * still becomes a square, a lopsided triangle with a near right angle becomes a right triangle.
 * What is not perfect afterwards can be fixed by dragging the corners.
 */
object ShapeRecognizer {
    fun recognize(raw: List<Pt>): ShapeMatch? {
        if (raw.size < 3) return null
        val length = Geo.length(raw)
        val box = Geo.bounds(raw)
        val diag = hypot(box.width, box.height)
        val maxDim = max(box.width, box.height)
        if (!(length >= 14 && maxDim >= 8)) return null
        // Closed when the end comes back near the first stretch of the stroke: overshooting the
        // start is normal when a shape is closed by hand, and so is stopping a little short of it.
        val last = raw[raw.size - 1]
        var gap = Double.POSITIVE_INFINITY
        var run = 0.0
        for (i in raw.indices) {
            if (i > 0) run += Geo.dist(raw[i - 1], raw[i])
            if (run > 0.3 * length) break
            gap = min(gap, Geo.dist(raw[i], last))
        }
        val closed = gap < max(0.28 * maxDim, 10.0) && length > 2.1 * maxDim
        return if (closed) closedShape(raw, diag) else openShape(raw, length, diag)
    }

    private class Candidate(
        val match: ShapeMatch,
        /** RMS distance of the drawing from the shape, in points. */
        val rms: Double,
        /** Above 1 for shapes that should only win clearly (many corners). */
        val penalty: Double,
    )

    private fun pick(candidates: List<Candidate>, limit: Double): ShapeMatch? {
        // Swift's `min(by:)`: the first of equal candidates wins.
        var best: Candidate? = null
        for (c in candidates) {
            val b = best
            if (b == null || c.rms * c.penalty < b.rms * b.penalty) best = c
        }
        val b = best ?: return null
        if (!(b.rms <= limit)) return null
        return b.match
    }

    // MARK: Open strokes

    private fun openShape(raw: List<Pt>, length: Double, diag: Double): ShapeMatch? {
        val pts = Geo.smooth(Geo.resample(raw, count = 96), closed = false, radius = 2)
        val first = raw[0]
        val last = raw[raw.size - 1]
        var deviation = 0.0
        for (p in pts) {
            deviation = max(deviation, Geo.segmentDistance(p, first, last))
        }
        val chord = Geo.dist(first, last)
        if (deviation < max(0.07 * chord, 3.0) && chord > 0.8 * length) {
            return ShapeMatch(ShapeMatch.Kind.LINE, ShapeName.LINE, listOf(first, last), corners = listOf(first, last))
        }

        val candidates = ArrayList<Candidate>()
        // Straight pieces joined at real corners (an angle, a zigzag, axes).
        var v = Geo.simplify(pts, tolerance = 0.05 * diag).map { pts[it] }
        v = Geo.dropCollinear(v, closed = false, minTurn = 25 * PI / 180)
        v = Geo.mergeClose(v, closed = false, minLength = 0.1 * length)
        if (v.size >= 3 && v.size <= 8 && Geo.cornersAreSharp(pts, v, closed = false)) {
            candidates.add(
                Candidate(
                    ShapeMatch(ShapeMatch.Kind.POLYLINE, ShapeName.POLYLINE, v, corners = v),
                    rms = Geo.polylineRMS(pts, v, closed = false),
                    penalty = 1 + 0.08 * (v.size - 3).toDouble(),
                ),
            )
        }
        // Any smooth bend becomes a curve with a handle on its bend: no arcs, no arrowheads.
        if (pts.isNotEmpty()) {
            val fit = Fit.quadraticBezier(pts)
            if (fit != null) {
                val curve = ShapeMatch.Curve(pts[0], fit.control, pts[pts.size - 1])
                candidates.add(
                    Candidate(
                        ShapeMatch(ShapeMatch.Kind.CURVE, ShapeName.CURVE, curve.path(), curve = curve),
                        rms = fit.rms,
                        penalty = 1.05,
                    ),
                )
            }
        }
        return pick(candidates, limit = 0.06 * diag)
    }

    // MARK: Closed strokes

    private fun closedShape(raw: List<Pt>, diag: Double): ShapeMatch? {
        // Cut the overshoot past the starting point.
        var bestIndex = raw.size - 1
        var bestDistance = Double.POSITIVE_INFINITY
        for (i in (raw.size.toDouble() * 0.65).toInt() until raw.size) {
            val d = Geo.dist(raw[i], raw[0])
            if (d < bestDistance) {
                bestDistance = d
                bestIndex = i
            }
        }
        val loop = raw.subList(0, bestIndex + 1)
        val pts = Geo.smooth(Geo.resample(loop, count = 120), closed = true, radius = 2)
        // About once around: a spiral or a scribble is not a shape (a small overshoot is fine).
        if (!(abs(abs(Geo.winding(pts)) - 2 * PI) < 0.75 * PI)) return null

        val candidates = ArrayList<Candidate>()
        val e = Fit.ellipse(pts)
        if (e != null) {
            if (e.ry / e.rx > 0.82) {
                val r = (e.rx + e.ry) / 2
                candidates.add(
                    Candidate(
                        ShapeMatch(
                            ShapeMatch.Kind.CIRCLE, ShapeName.CIRCLE,
                            ellipsePath(e.center, r, r, 0.0, following = pts),
                            oval = ShapeMatch.Oval(e.center, r, r, 0.0),
                        ),
                        rms = Fit.circle(pts)?.rms ?: e.rms,
                        penalty = 1.0,
                    ),
                )
            } else {
                var angle = e.angle
                val quarter = PI / 2
                val k = roundedAway(angle / quarter)
                if (abs(angle - k * quarter) < 8 * PI / 180) angle = k * quarter
                candidates.add(
                    Candidate(
                        ShapeMatch(
                            ShapeMatch.Kind.ELLIPSE, ShapeName.ELLIPSE,
                            ellipsePath(e.center, e.rx, e.ry, angle, following = pts),
                            oval = ShapeMatch.Oval(e.center, e.rx, e.ry, angle),
                        ),
                        rms = e.rms,
                        penalty = 1.0,
                    ),
                )
            }
        }

        // A loop that fills almost all of the smallest rectangle around it is a rectangle, however
        // crooked its sides or round its corners (an ellipse fills 79 %, a hexagon 75 %).
        val box = boundingRectangle(pts)
        if (box != null && box.fill > 0.88) {
            val rect = snapRectangle(box.corners)
            candidates.add(
                Candidate(
                    ShapeMatch(
                        ShapeMatch.Kind.RECTANGLE, if (isSquare(rect)) ShapeName.SQUARE else ShapeName.RECTANGLE,
                        rect + rect[0], corners = rect,
                    ),
                    rms = Geo.polylineRMS(pts, rect, closed = true),
                    penalty = 0.7,
                ),
            )
        }

        // Polygon: simplify the loop starting from its sharpest point (a corner).
        val n = pts.size
        var sharpest = 0
        var sharpestTurn = -1.0
        for (i in 0 until n) {
            val t = Geo.turn(pts[(i - 6 + n) % n], pts[i], pts[(i + 6) % n])
            if (t > sharpestTurn) {
                sharpestTurn = t
                sharpest = i
            }
        }
        val rotated = ArrayList<Pt>(n + 1)
        rotated.addAll(pts.subList(sharpest, n))
        rotated.addAll(pts.subList(0, sharpest))
        rotated.add(rotated[0])
        var v = Geo.simplify(rotated, tolerance = 0.045 * diag).dropLast(1).map { rotated[it] }
        v = Geo.dropCollinear(v, closed = true, minTurn = 28 * PI / 180)
        v = Geo.mergeClose(v, closed = true, minLength = 0.12 * diag)
        if (v.size >= 3 && v.size <= 8 && Geo.cornersAreSharp(pts, v, closed = true)) {
            var path = v
            var kind = ShapeMatch.Kind.POLYGON
            var name = when (v.size) {
                3 -> ShapeName.TRIANGLE
                4 -> ShapeName.QUADRILATERAL
                5 -> ShapeName.PENTAGON
                6 -> ShapeName.HEXAGON
                7 -> ShapeName.HEPTAGON
                8 -> ShapeName.OCTAGON
                else -> ShapeName.POLYGON
            }
            val nearlyRight = v.size == 4 && (0 until 4).all { i ->
                abs(Geo.interiorAngle(v[(i + 3) % 4], v[i], v[(i + 1) % 4]) - PI / 2) < 30 * PI / 180
            }
            if (v.size == 4 && (nearlyRight || (box?.fill ?: 0.0) > 0.9)) {
                path = snapRectangle(v)
                kind = ShapeMatch.Kind.RECTANGLE
                name = if (isSquare(path)) ShapeName.SQUARE else ShapeName.RECTANGLE
            } else if (v.size == 3) {
                val tri = beautifyTriangle(v)
                path = tri.points
                name = tri.name
            }
            val penalties = doubleArrayOf(0.0, 0.0, 0.0, 0.8, 0.8, 0.85, 1.0, 1.15, 1.3)
            candidates.add(
                Candidate(
                    ShapeMatch(kind, name, path + path[0], corners = path),
                    rms = Geo.polylineRMS(pts, v, closed = true),
                    penalty = penalties[v.size],
                ),
            )
        }
        return pick(candidates, limit = 0.075 * diag)
    }

    private class BoundingRect(val corners: List<Pt>, val fill: Double)

    /** The smallest rectangle (at any turn) around the loop, and how much of it the loop fills. */
    private fun boundingRectangle(pts: List<Pt>): BoundingRect? {
        val area = abs(Geo.signedArea(pts))
        if (!(area > 1)) return null
        var bestArea = Double.POSITIVE_INFINITY
        var bestCorners: List<Pt> = emptyList()
        for (step in 0 until 90) {
            val a = step.toDouble() * PI / 180
            val c = cos(a)
            val s = sin(a)
            var u0 = Double.POSITIVE_INFINITY
            var u1 = Double.NEGATIVE_INFINITY
            var w0 = Double.POSITIVE_INFINITY
            var w1 = Double.NEGATIVE_INFINITY
            for (p in pts) {
                val u = p.x * c + p.y * s
                val w = -p.x * s + p.y * c
                u0 = min(u0, u)
                u1 = max(u1, u)
                w0 = min(w0, w)
                w1 = max(w1, w)
            }
            val boxArea = (u1 - u0) * (w1 - w0)
            if (boxArea < bestArea) {
                bestArea = boxArea
                bestCorners = listOf(
                    Pt(u0 * c - w0 * s, u0 * s + w0 * c), Pt(u1 * c - w0 * s, u1 * s + w0 * c),
                    Pt(u1 * c - w1 * s, u1 * s + w1 * c), Pt(u0 * c - w1 * s, u0 * s + w1 * c),
                )
            }
        }
        if (!(bestArea > 1 && bestCorners.size == 4)) return null
        return BoundingRect(bestCorners, area / bestArea)
    }

    private class Triangle(val points: List<Pt>, val name: ShapeName)

    /**
     * A hand-drawn triangle made exact when it is close to a special one: equilateral, right
     * angled or isosceles; a side that is almost level (or upright) is straightened.
     */
    private fun beautifyTriangle(v: List<Pt>): Triangle {
        val p = ArrayList(v)
        var name = ShapeName.TRIANGLE
        // Side i runs from v[i] to v[i+1].
        val s = DoubleArray(3) { Geo.dist(v[it], v[(it + 1) % 3]) }
        val longest = s.max()
        val shortest = s.min()
        val center = Pt((p[0].x + p[1].x + p[2].x) / 3, (p[0].y + p[1].y + p[2].y) / 3)
        var rightAt: Int? = null
        for (i in 0 until 3) {
            val angle = Geo.interiorAngle(p[(i + 2) % 3], p[i], p[(i + 1) % 3])
            if (abs(angle - PI / 2) < 10 * PI / 180) rightAt = i
        }
        if (longest - shortest < 0.12 * longest) {
            // Equilateral around the same middle, keeping the most level side's direction.
            var levelSide = 0
            var levelness = Double.POSITIVE_INFINITY
            for (i in 0 until 3) {
                val d = abs(sin(atan2(p[(i + 1) % 3].y - p[i].y, p[(i + 1) % 3].x - p[i].x)))
                if (d < levelness) {
                    levelness = d
                    levelSide = i
                }
            }
            val a = p[levelSide]
            val b = p[(levelSide + 1) % 3]
            val apex = p[(levelSide + 2) % 3]
            val length = max(Geo.dist(a, b), 1.0)
            val ux = (b.x - a.x) / length
            val uy = (b.y - a.y) / length
            var nx = -uy
            var ny = ux
            val mid = Pt((a.x + b.x) / 2, (a.y + b.y) / 2)
            if ((apex.x - mid.x) * nx + (apex.y - mid.y) * ny < 0) {
                nx = -nx
                ny = -ny
            }
            val radius = (Geo.dist(p[0], center) + Geo.dist(p[1], center) + Geo.dist(p[2], center)) / 3
            val side = radius * sqrt(3.0)
            val baseMid = Pt(center.x - nx * radius / 2, center.y - ny * radius / 2)
            p[levelSide] = Pt(baseMid.x - ux * side / 2, baseMid.y - uy * side / 2)
            p[(levelSide + 1) % 3] = Pt(baseMid.x + ux * side / 2, baseMid.y + uy * side / 2)
            p[(levelSide + 2) % 3] = Pt(center.x + nx * radius, center.y + ny * radius)
            name = ShapeName.EQUILATERAL_TRIANGLE
        } else if (rightAt != null) {
            // The right-angle corner moves onto the circle over the other two (Thales).
            val i = rightAt
            val a = p[(i + 2) % 3]
            val c = p[(i + 1) % 3]
            val mid = Pt((a.x + c.x) / 2, (a.y + c.y) / 2)
            val r = Geo.dist(a, c) / 2
            val d = Geo.dist(p[i], mid)
            if (d > 1e-3) {
                p[i] = Pt(mid.x + (p[i].x - mid.x) * r / d, mid.y + (p[i].y - mid.y) * r / d)
            }
            name = ShapeName.RIGHT_TRIANGLE
        } else {
            // Two equal sides meeting at p[i]: the apex moves onto the middle of the base.
            for (i in 0 until 3) {
                val one = s[i]
                val other = s[(i + 2) % 3]
                if (!(abs(one - other) < 0.08 * max(one, other))) continue
                val b = p[(i + 1) % 3]
                val c = p[(i + 2) % 3]
                val length = max(Geo.dist(b, c), 1.0)
                val ux = (c.x - b.x) / length
                val uy = (c.y - b.y) / length
                val mid = Pt((b.x + c.x) / 2, (b.y + c.y) / 2)
                val along = (p[i].x - mid.x) * ux + (p[i].y - mid.y) * uy
                p[i] = Pt(p[i].x - ux * along, p[i].y - uy * along)
                name = ShapeName.ISOSCELES_TRIANGLE
                break
            }
        }
        // Straighten a side that is almost level or upright by turning the whole triangle.
        var smallest = Double.POSITIVE_INFINITY
        var correction = 0.0
        for (i in 0 until 3) {
            val a = atan2(p[(i + 1) % 3].y - p[i].y, p[(i + 1) % 3].x - p[i].x)
            val quarter = PI / 2
            val off = a - roundedAway(a / quarter) * quarter
            if (abs(off) < smallest) {
                smallest = abs(off)
                correction = -off
            }
        }
        if (smallest > 0.001 && smallest < 7 * PI / 180) {
            val c = Pt((p[0].x + p[1].x + p[2].x) / 3, (p[0].y + p[1].y + p[2].y) / 3)
            val cs = cos(correction)
            val sn = sin(correction)
            for (i in 0 until 3) {
                val q = p[i]
                val x = q.x - c.x
                val y = q.y - c.y
                p[i] = Pt(c.x + x * cs - y * sn, c.y + x * sn + y * cs)
            }
        }
        return Triangle(p, name)
    }

    /**
     * Right angles become a true rectangle (a square when the sides are nearly equal); a rectangle
     * that is almost level is leveled.
     */
    private fun snapRectangle(v: List<Pt>): List<Pt> {
        var longest = 0.0
        var angle = 0.0
        for (i in 0 until 4) {
            val a = v[i]
            val b = v[(i + 1) % 4]
            val l = Geo.dist(a, b)
            if (l > longest) {
                longest = l
                angle = atan2(b.y - a.y, b.x - a.x)
            }
        }
        val quarter = PI / 2
        angle = (angle % quarter + quarter) % quarter
        if (angle > quarter / 2) angle -= quarter
        if (abs(angle) < 8 * PI / 180) angle = 0.0
        val c = cos(angle)
        val s = sin(angle)
        val us = v.map { it.x * c + it.y * s }.sorted()
        val ws = v.map { -it.x * s + it.y * c }.sorted()
        var u0 = (us[0] + us[1]) / 2
        var u1 = (us[2] + us[3]) / 2
        var w0 = (ws[0] + ws[1]) / 2
        var w1 = (ws[2] + ws[3]) / 2
        val width = u1 - u0
        val height = w1 - w0
        if (abs(width - height) < 0.15 * max(width, height)) {
            val m = (width + height) / 2
            val cu = (u0 + u1) / 2
            val cw = (w0 + w1) / 2
            u0 = cu - m / 2
            u1 = cu + m / 2
            w0 = cw - m / 2
            w1 = cw + m / 2
        }
        fun back(u: Double, w: Double) = Pt(u * c - w * s, u * s + w * c)
        return listOf(back(u0, w0), back(u1, w0), back(u1, w1), back(u0, w1))
    }

    private fun isSquare(r: List<Pt>): Boolean =
        abs(Geo.dist(r[0], r[1]) - Geo.dist(r[1], r[2])) < 0.01 * Geo.dist(r[0], r[2])

    /** Starts where the user started and runs the same way round. */
    private fun ellipsePath(center: Pt, rx: Double, ry: Double, angle: Double, following: List<Pt>): List<Pt> {
        val pts = following
        var area = 0.0
        for (i in 1 until pts.size) {
            area += pts[i - 1].x * pts[i].y - pts[i].x * pts[i - 1].y
        }
        val direction = if (area >= 0) 1.0 else -1.0
        val c = cos(angle)
        val s = sin(angle)
        val x = pts[0].x - center.x
        val y = pts[0].y - center.y
        val t0 = atan2((-x * s + y * c) / ry, (x * c + y * s) / rx)
        val n = max(48, ceil(PI * (rx + ry) / 3).toInt())
        return (0..n).map { i ->
            val t = t0 + direction * 2 * PI * i.toDouble() / n.toDouble()
            val u = cos(t) * rx
            val w = sin(t) * ry
            Pt(center.x + u * c - w * s, center.y + u * s + w * c)
        }
    }
}
