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

// Port of Murekkep.swiftpm/ShapeEditing.swift: a recognized shape that keeps handles after the pen
// lifts, with `pointsPerMillimetre` of Instruments.swift and `EditorModel.restroke(_:along:)`, which
// redraws the shape's stroke along the moved outline. Same numbers as the iPad. Where the iPad
// mutates the shape (`move(handle:to:snap:)`), the port returns the moved shape with the feedback.
//
// The iPad builds the bubble text with `Loc.t` strings; here the feedback carries a [ShapeLabel],
// structured data the UI formats with the words of its own language.

/** Points per millimetre on the page (pages are laid out in PostScript points: A4 = 595 × 842). */
const val POINTS_PER_MILLIMETRE: Double = 72 / 25.4

/**
 * The text for the bubble next to the pen while a handle is dragged. [format] builds the iPad's
 * string from the shape names of the UI's language (`name`) and its decimal separator (the iPad
 * writes "42,3 mm" in Turkish and "42.3 mm" in English).
 */
sealed class ShapeLabel {
    abstract fun format(name: (ShapeName) -> String, decimalSeparator: Char = ','): String

    /** The angle at a dragged corner: "90°". */
    data class Degrees(val degrees: Int) : ShapeLabel() {
        override fun format(name: (ShapeName) -> String, decimalSeparator: Char): String = "$degrees°"
    }

    /** A dragged end's distance from its neighbour: "42,3 mm", "12,5 cm". */
    data class Length(val millimetres: Double) : ShapeLabel() {
        override fun format(name: (ShapeName) -> String, decimalSeparator: Char): String =
            ShapeBuilder.mm(millimetres, decimalSeparator)
    }

    /** The shape's name alone (a curve's bend handle). */
    data class Title(val name: ShapeName) : ShapeLabel() {
        override fun format(name: (ShapeName) -> String, decimalSeparator: Char): String = name(this.name)
    }

    /** An oval's name and size: "Daire · 24 mm", "Elips · 24 mm × 16,5 mm" (no height for a circle). */
    data class OvalSize(val name: ShapeName, val widthMm: Double, val heightMm: Double?) : ShapeLabel() {
        override fun format(name: (ShapeName) -> String, decimalSeparator: Char): String {
            val size = if (heightMm == null) ShapeBuilder.mm(widthMm, decimalSeparator)
            else ShapeBuilder.mm(widthMm, decimalSeparator) + " × " + ShapeBuilder.mm(heightMm, decimalSeparator)
            return "${name(this.name)} · $size"
        }
    }
}

/**
 * What a handle drag did: the text for the bubble next to the pen, and whether the handle
 * settled on something (a right angle, a level or upright side, a circle) for a click.
 */
data class ShapeHandleFeedback(val label: ShapeLabel?, val snapped: Boolean)

/** The shape after a handle moved, with the drag's feedback (the iPad mutates the shape instead). */
data class ShapeMove(val shape: EditableShape, val feedback: ShapeHandleFeedback)

/**
 * A recognized shape that stays adjustable after the pen lifts. Polygons and broken lines get a
 * handle on every corner, circles and ellipses on the ends of their axes, and every shape one in
 * its middle that moves it whole. The handles stay until the next touch somewhere else.
 */
data class EditableShape(
    val kind: Kind,
    /** Corners in page space (empty for an oval and a curve). */
    val points: List<Pt>,
    val name: ShapeName,
) {
    sealed class Kind {
        /** Closed outline through `points` (triangles, rectangles, squares, other polygons). */
        data object Polygon : Kind()

        /** Open line through `points` (a straight line has two). */
        data object Polyline : Kind()

        data class Oval(val center: Pt, val rx: Double, val ry: Double, val angle: Double) : Kind()

        /** A bend between two ends; its handle sits on the curve halfway. */
        data class Curve(val curve: ShapeMatch.Curve) : Kind()
    }

    companion object {
        /** The shape of a match, or null for a match without handles (never today). */
        fun from(match: ShapeMatch): EditableShape? = when (match.kind) {
            ShapeMatch.Kind.LINE, ShapeMatch.Kind.POLYLINE -> {
                val corners = if (match.corners.size >= 2) match.corners
                else listOfNotNull(match.path.firstOrNull(), match.path.lastOrNull())
                if (corners.size >= 2) EditableShape(Kind.Polyline, corners, match.name) else null
            }
            ShapeMatch.Kind.POLYGON, ShapeMatch.Kind.RECTANGLE ->
                if (match.corners.size >= 3) EditableShape(Kind.Polygon, match.corners, match.name) else null
            ShapeMatch.Kind.CIRCLE, ShapeMatch.Kind.ELLIPSE -> {
                val o = match.oval
                if (o != null) EditableShape(Kind.Oval(o.center, o.rx, o.ry, o.angle), emptyList(), match.name) else null
            }
            ShapeMatch.Kind.CURVE -> {
                val c = match.curve
                if (c != null) EditableShape(Kind.Curve(c), emptyList(), match.name) else null
            }
        }
    }

    /** Average of the corners (the middle of an oval; for a curve, between its ends and its bend). */
    val middle: Pt
        get() {
            val k = kind
            if (k is Kind.Oval) return k.center
            if (k is Kind.Curve) {
                val c = k.curve
                val m = c.middle
                return Pt((c.start.x + m.x + c.end.x) / 3, (c.start.y + m.y + c.end.y) / 3)
            }
            if (points.isEmpty()) return Pt.ZERO
            val n = points.size.toDouble()
            var sx = 0.0
            var sy = 0.0
            for (p in points) {
                sx += p.x
                sy += p.y
            }
            return Pt(sx / n, sy / n)
        }

    /** Handle positions in page space. The last one is always the middle, which moves everything. */
    val handles: List<Pt>
        get() = when (val k = kind) {
            Kind.Polygon, Kind.Polyline -> points + middle
            is Kind.Oval -> {
                val ux = cos(k.angle)
                val uy = sin(k.angle)
                val vx = -sin(k.angle)
                val vy = cos(k.angle)
                listOf(
                    Pt(k.center.x + ux * k.rx, k.center.y + uy * k.rx),
                    Pt(k.center.x + vx * k.ry, k.center.y + vy * k.ry),
                    Pt(k.center.x - ux * k.rx, k.center.y - uy * k.rx),
                    Pt(k.center.x - vx * k.ry, k.center.y - vy * k.ry),
                    k.center,
                )
            }
            is Kind.Curve -> listOf(k.curve.start, k.curve.middle, k.curve.end, middle)
        }

    /** The outline to ink. */
    fun path(): List<Pt> = when (val k = kind) {
        Kind.Polygon -> if (points.isEmpty()) emptyList() else points + points[0]
        Kind.Polyline -> points
        is Kind.Oval -> {
            val n = max(48, min(720, ceil(PI * (k.rx + k.ry) / 3).toInt()))
            val c = cos(k.angle)
            val s = sin(k.angle)
            (0..n).map { i ->
                val t = 2 * PI * i.toDouble() / n.toDouble() - PI / 2
                val x = cos(t) * k.rx
                val y = sin(t) * k.ry
                Pt(k.center.x + x * c - y * s, k.center.y + x * s + y * c)
            }
        }
        is Kind.Curve -> k.curve.path()
    }

    /**
     * The same shape grown by `scale` and turned by `angle` around `anchor` (while the pen that
     * drew it still holds it).
     */
    fun transformed(anchor: Pt, scale: Double, angle: Double): EditableShape {
        val c = cos(angle)
        val s = sin(angle)
        fun place(p: Pt): Pt {
            val x = (p.x - anchor.x) * scale
            val y = (p.y - anchor.y) * scale
            return Pt(anchor.x + x * c - y * s, anchor.y + x * s + y * c)
        }
        val k = kind
        val newKind = when (k) {
            is Kind.Oval -> Kind.Oval(place(k.center), k.rx * scale, k.ry * scale, k.angle + angle)
            is Kind.Curve -> Kind.Curve(ShapeMatch.Curve(place(k.curve.start), place(k.curve.control), place(k.curve.end)))
            else -> k
        }
        return copy(kind = newKind, points = points.map { place(it) })
    }

    /**
     * Moves handle `index` to `target` (page space). `snap` is how close, in points, a corner has
     * to come to a level or upright line through its neighbour before it settles there.
     */
    fun move(handle: Int, to: Pt, snap: Double): ShapeMove {
        val index = handle
        val target = to
        val all = handles
        if (index !in all.indices) return ShapeMove(this, ShapeHandleFeedback(null, false))
        if (index == all.size - 1) {
            return ShapeMove(translated(Pt(target.x - all[index].x, target.y - all[index].y)), ShapeHandleFeedback(null, false))
        }
        return when (val k = kind) {
            Kind.Polygon, Kind.Polyline -> moveCorner(index, target, snap)
            is Kind.Oval -> moveAxis(index, target, k.center, k.rx, k.ry, k.angle)
            is Kind.Curve -> moveCurveHandle(index, target, k.curve, snap)
        }
    }

    private fun translated(d: Pt): EditableShape {
        fun shift(p: Pt) = Pt(p.x + d.x, p.y + d.y)
        val k = kind
        val newKind = when (k) {
            is Kind.Oval -> Kind.Oval(shift(k.center), k.rx, k.ry, k.angle)
            is Kind.Curve -> Kind.Curve(ShapeMatch.Curve(shift(k.curve.start), shift(k.curve.control), shift(k.curve.end)))
            else -> k
        }
        return copy(kind = newKind, points = points.map { shift(it) })
    }

    /**
     * Curve handles: 0 and 2 are the ends, 1 the bend. Moving an end keeps the bend where it is;
     * the ends settle level or upright with each other.
     */
    private fun moveCurveHandle(i: Int, target: Pt, c: ShapeMatch.Curve, snap: Double): ShapeMove {
        if (i == 1) {
            val next = c.copy(control = ShapeMatch.Curve.control(c.start, through = target, end = c.end))
            return ShapeMove(copy(kind = Kind.Curve(next)), ShapeHandleFeedback(ShapeLabel.Title(name), false))
        }
        var px = target.x
        var py = target.y
        var snapped = false
        val other = if (i == 0) c.end else c.start
        if (abs(px - other.x) < snap) {
            px = other.x
            snapped = true
        }
        if (abs(py - other.y) < snap) {
            py = other.y
            snapped = true
        }
        val bend = c.middle
        val p = Pt(px, py)
        val start = if (i == 0) p else c.start
        val end = if (i == 0) c.end else p
        val next = ShapeMatch.Curve(start, ShapeMatch.Curve.control(start, through = bend, end = end), end)
        return ShapeMove(
            copy(kind = Kind.Curve(next)),
            ShapeHandleFeedback(ShapeLabel.Length(Geo.dist(next.start, next.end) / POINTS_PER_MILLIMETRE), snapped),
        )
    }

    private fun moveCorner(i: Int, target: Pt, snap: Double): ShapeMove {
        val n = points.size
        if (i !in points.indices || n < 2) return ShapeMove(this, ShapeHandleFeedback(null, false))
        val closed = kind == Kind.Polygon
        val prev: Pt? = if (closed || i > 0) points[(i - 1 + n) % n] else null
        val next: Pt? = if (closed || i < n - 1) points[(i + 1) % n] else null
        var px = target.x
        var py = target.y
        var snapped = false
        // Level or upright with a neighbour.
        for (q in listOfNotNull(prev, next)) {
            if (abs(px - q.x) < snap) {
                px = q.x
                snapped = true
            }
            if (abs(py - q.y) < snap) {
                py = q.y
                snapped = true
            }
        }
        var p = Pt(px, py)
        // A right angle at this corner: it sits on the circle over its two neighbours (Thales).
        if (!snapped && prev != null && next != null) {
            val angle = Geo.interiorAngle(prev, p, next)
            if (abs(angle - PI / 2) < 5 * PI / 180) {
                val mid = Pt((prev.x + next.x) / 2, (prev.y + next.y) / 2)
                val r = Geo.dist(prev, next) / 2
                val d = Geo.dist(p, mid)
                if (d > 1e-3) {
                    p = Pt(mid.x + (p.x - mid.x) * r / d, mid.y + (p.y - mid.y) * r / d)
                    snapped = true
                }
            }
        }
        val moved = ArrayList(points)
        moved[i] = p
        val shape = copy(points = moved)
        if (prev != null && next != null) {
            val degrees = roundedAwayToInt(Geo.interiorAngle(prev, p, next) * 180 / PI)
            return ShapeMove(shape, ShapeHandleFeedback(ShapeLabel.Degrees(degrees), snapped))
        }
        val q = prev ?: next
        if (q != null) {
            return ShapeMove(shape, ShapeHandleFeedback(ShapeLabel.Length(Geo.dist(p, q) / POINTS_PER_MILLIMETRE), snapped))
        }
        return ShapeMove(shape, ShapeHandleFeedback(null, snapped))
    }

    /**
     * Axis handles: 0 and 2 on the first axis, 1 and 3 on the second. Dragging one sets that radius
     * and turns the oval; radii that come close become a circle.
     */
    private fun moveAxis(i: Int, target: Pt, center: Pt, rx: Double, ry: Double, angle: Double): ShapeMove {
        val dx = target.x - center.x
        val dy = target.y - center.y
        val r = max(hypot(dx, dy), 4.0)
        val along = atan2(dy, dx)
        var newRx = rx
        var newRy = ry
        var newAngle = angle
        when (i) {
            0 -> {
                newRx = r
                newAngle = along
            }
            2 -> {
                newRx = r
                newAngle = along + PI
            }
            1 -> {
                newRy = r
                newAngle = along - PI / 2
            }
            else -> {
                newRy = r
                newAngle = along + PI / 2
            }
        }
        var snapped = false
        // The turn settles on level and upright.
        val quarter = PI / 2
        val nearest = roundedAway(newAngle / quarter) * quarter
        if (abs(newAngle - nearest) < 4 * PI / 180) {
            newAngle = nearest
        }
        val circle = abs(newRx - newRy) < 0.05 * max(newRx, newRy)
        if (circle) {
            if (i % 2 == 0) newRy = newRx else newRx = newRy
            snapped = true
        }
        val title = if (circle) ShapeName.CIRCLE else ShapeName.ELLIPSE
        val label = ShapeLabel.OvalSize(
            title,
            widthMm = 2 * newRx / POINTS_PER_MILLIMETRE,
            heightMm = if (circle) null else 2 * newRy / POINTS_PER_MILLIMETRE,
        )
        return ShapeMove(
            copy(kind = Kind.Oval(center, newRx, newRy, newAngle), name = title),
            ShapeHandleFeedback(label, snapped),
        )
    }
}

/** The shape on a page whose handles are showing. */
data class ShapeEditState(
    val page: Int,
    /** The stroke that draws the shape (it gets a new id every time the shape is redrawn). */
    val strokeId: Int,
    val shape: EditableShape,
)

/**
 * The same stroke (brush, color, width, average pressure and ink) drawn along `path`: the iPad's
 * `EditorModel.restroke(_:along:)`, which redraws a shape's stroke after every handle move. The
 * new stroke gets a fresh id, as there.
 */
fun restroke(s: Stroke, along: List<Pt>): Stroke {
    val n = max(s.points.size, 1).toFloat()
    var r = 0f
    var ink = 0f
    for (p in s.points) {
        r += p.r
        ink += p.ink
    }
    r /= n
    ink /= n
    val dense = if (along.size >= 2) Geo.densify(along, max(1.5f, r * 0.7f).toDouble()) else along
    return Stroke(
        s.brush, s.color, s.width, s.birth, s.seed,
        dense.map { InkPoint(it.x.toFloat(), it.y.toFloat(), r, ink) }, s.duration,
    )
}
