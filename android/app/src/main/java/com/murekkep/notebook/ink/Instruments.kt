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
import kotlin.math.tan

// Port of the drafting instruments of Murekkep.swiftpm/Instruments.swift (`InstrumentKind`,
// `Instrument`, `EdgeSnap`, `CompassState`) and of what the iPad's canvas does with them in
// CanvasView.swift: fingers carrying and turning an instrument (`instrumentPanned`,
// `instrumentTurned`, the turn settling at 15° steps), the reading next to a pen sliding along it
// (`updateSnapLabel`) and the compass's arc (`compassBegan`, `compassMoved`, `compassEnded`).
// Document points, y down, in Double as the iPad's CGFloat; tools/instrumentcheck runs the real
// Swift instrument code and the JUnit tests hold this port to its answers.

/** The ruler, the two set squares and the protractor, in the iPad's order; [raw] is the iPad's value. */
enum class InstrumentKind(val raw: String) {
    RULER("ruler"),
    SET_SQUARE_45("setSquare45"),
    SET_SQUARE_3060("setSquare3060"),
    PROTRACTOR("protractor"),
    ;

    companion object {
        fun fromRaw(raw: String): InstrumentKind? = entries.firstOrNull { it.raw == raw }
    }
}

/** A ruler, set square or protractor lying on the document. The pen slides along its edges. */
data class Instrument(
    val kind: InstrumentKind,
    /** Document-space position: the ruler's middle, the set square's centroid, the protractor's center. */
    val center: Pt,
    /** Rotation in radians (0 = the long edge runs left to right). */
    val angle: Double,
) {
    companion object {
        const val RULER_LENGTH: Double = 170 * POINTS_PER_MILLIMETRE
        const val RULER_WIDTH: Double = 20 * POINTS_PER_MILLIMETRE
        const val SQUARE_LEG: Double = 95 * POINTS_PER_MILLIMETRE
        const val PROTRACTOR_RADIUS: Double = 55 * POINTS_PER_MILLIMETRE

        /** The turns a menu offers (Açıyı ayarla), in degrees counterclockwise as on paper. */
        val PRESET_DEGREES = listOf(0, 15, 30, 45, 60, 75, 90, 120, 135, 150)

        private val outlines: Map<InstrumentKind, List<Pt>> = InstrumentKind.entries.associateWith { localOutlineOf(it) }

        /** Corners in the instrument's own frame (before rotation, y down). */
        private fun localOutlineOf(kind: InstrumentKind): List<Pt> = when (kind) {
            InstrumentKind.RULER -> {
                val w = RULER_LENGTH / 2
                val h = RULER_WIDTH / 2
                listOf(Pt(-w, -h), Pt(w, -h), Pt(w, h), Pt(-w, h))
            }
            InstrumentKind.SET_SQUARE_45, InstrumentKind.SET_SQUARE_3060 -> {
                val a = SQUARE_LEG
                val b = if (kind == InstrumentKind.SET_SQUARE_45) a else a * tan(PI / 6)
                // Right angle at bottom-left; centroid at the origin.
                val pts = listOf(Pt(0.0, 0.0), Pt(a, 0.0), Pt(0.0, -b))
                val cx = a / 3
                val cy = -b / 3
                pts.map { Pt(it.x - cx, it.y - cy) }
            }
            InstrumentKind.PROTRACTOR -> {
                val r = PROTRACTOR_RADIUS
                val pts = ArrayList<Pt>(38)
                pts.add(Pt(-r, 0.0))
                for (i in 0..36) {
                    val a = PI * i / 36
                    pts.add(Pt(-r * cos(a), -r * sin(a)))
                }
                pts
            }
        }

        fun pointInTriangle(p: Pt, a: Pt, b: Pt, c: Pt): Boolean {
            fun side(p1: Pt, p2: Pt, p3: Pt): Double = (p1.x - p3.x) * (p2.y - p3.y) - (p2.x - p3.x) * (p1.y - p3.y)
            val d1 = side(p, a, b)
            val d2 = side(p, b, c)
            val d3 = side(p, c, a)
            val neg = d1 < 0 || d2 < 0 || d3 < 0
            val pos = d1 > 0 || d2 > 0 || d3 > 0
            return !(neg && pos)
        }

        /** A preset of the menu as the instrument's angle: counterclockwise on paper is negative here (y down). */
        fun angleFor(degrees: Double): Double = -degrees * PI / 180
    }

    /** Corners in the instrument's own frame (before rotation, y down). */
    val localOutline: List<Pt> get() = outlines.getValue(kind)

    fun toDocument(p: Pt): Pt {
        val c = cos(angle)
        val s = sin(angle)
        return Pt(center.x + p.x * c - p.y * s, center.y + p.x * s + p.y * c)
    }

    fun toLocal(p: Pt): Pt {
        val dx = p.x - center.x
        val dy = p.y - center.y
        val c = cos(angle)
        val s = sin(angle)
        return Pt(dx * c + dy * s, -dx * s + dy * c)
    }

    val outline: List<Pt> get() = localOutline.map { toDocument(it) }

    /** Straight edges the pen can slide along (document space). */
    val edges: List<Pair<Pt, Pt>>
        get() {
            val o = outline
            return when (kind) {
                InstrumentKind.RULER -> listOf(Pair(o[0], o[1]), Pair(o[3], o[2]))
                InstrumentKind.SET_SQUARE_45, InstrumentKind.SET_SQUARE_3060 -> listOf(Pair(o[0], o[1]), Pair(o[1], o[2]), Pair(o[2], o[0]))
                InstrumentKind.PROTRACTOR -> listOf(Pair(o[0], o[o.size - 1]))
            }
        }

    fun contains(p: Pt): Boolean {
        val q = toLocal(p)
        return when (kind) {
            InstrumentKind.RULER -> abs(q.x) <= RULER_LENGTH / 2 && abs(q.y) <= RULER_WIDTH / 2
            InstrumentKind.PROTRACTOR -> q.y <= 0 && hypot(q.x, q.y) <= PROTRACTOR_RADIUS
            InstrumentKind.SET_SQUARE_45, InstrumentKind.SET_SQUARE_3060 -> {
                val o = localOutline
                pointInTriangle(q, o[0], o[1], o[2])
            }
        }
    }

    /** Angle shown to the user, 0…180°, counterclockwise as on paper (the view's y axis points down). */
    val degrees: Int
        get() {
            var d = roundedAwayToInt(-angle * 180 / PI) % 180
            if (d < 0) d += 180
            return d
        }
}

/** Locks a stroke onto an instrument edge (or a protractor ray) once it starts close to it. */
data class EdgeSnap(
    val a: Pt,
    val b: Pt,
    /** Protractor rays: the stroke runs from the center outwards at a whole-degree angle. */
    val isRay: Boolean,
) {
    fun project(p: Pt): Pt {
        if (isRay) {
            val dx = p.x - a.x
            val dy = p.y - a.y
            val len = hypot(dx, dy)
            if (!(len > 0.01)) return a
            val raw = atan2(dy, dx)
            val base = atan2(b.y - a.y, b.x - a.x)
            val step = PI / 180
            val snapped = base + roundedAway((raw - base) / step) * step
            return Pt(a.x + cos(snapped) * len, a.y + sin(snapped) * len)
        }
        val abx = b.x - a.x
        val aby = b.y - a.y
        val l2 = abx * abx + aby * aby
        if (!(l2 > 0)) return a
        val t = min(max(((p.x - a.x) * abx + (p.y - a.y) * aby) / l2, -0.05), 1.05)
        return Pt(a.x + abx * t, a.y + aby * t)
    }

    /**
     * What the pen at [at] reads next to it (the iPad's `updateSnapLabel`), with the point it stands at
     * on the instrument: along an edge the length drawn from [start] (where the stroke came down,
     * projected), on a protractor's ray its angle on [instrument]'s scale.
     */
    fun reading(instrument: Instrument, start: Pt, at: Pt): Pair<Pt, InstrumentReading> {
        val p = project(at)
        if (isRay) {
            val local = instrument.toLocal(p)
            var deg = atan2(-local.y, local.x) * 180 / PI
            if (deg < 0) deg += 360
            return Pair(p, InstrumentReading.Angle(roundedAwayToInt(deg)))
        }
        val length = hypot(p.x - start.x, p.y - start.y)
        return Pair(p, InstrumentReading.Length(length / POINTS_PER_MILLIMETRE))
    }

    companion object {
        /** How far from an edge (view points) a stroke starts along it. */
        const val TOLERANCE = 18.0

        fun distance(p: Pt, a: Pt, b: Pt): Double {
            val abx = b.x - a.x
            val aby = b.y - a.y
            val l2 = abx * abx + aby * aby
            if (!(l2 > 0)) return hypot(p.x - a.x, p.y - a.y)
            val t = min(max(((p.x - a.x) * abx + (p.y - a.y) * aby) / l2, 0.0), 1.0)
            return hypot(p.x - (a.x + abx * t), p.y - (a.y + aby * t))
        }

        /** The edge (or protractor ray) a stroke starting at [p] should follow, if it starts close enough. */
        fun find(instrument: Instrument, p: Pt, tolerance: Double): EdgeSnap? {
            if (instrument.kind == InstrumentKind.PROTRACTOR) {
                val c = instrument.center
                if (hypot(p.x - c.x, p.y - c.y) <= tolerance * 1.4) {
                    val base = instrument.toDocument(Pt(Instrument.PROTRACTOR_RADIUS, 0.0))
                    return EdgeSnap(c, base, isRay = true)
                }
            }
            var best: EdgeSnap? = null
            var bestDistance = tolerance
            for ((a, b) in instrument.edges) {
                val d = distance(p, a, b)
                if (d <= bestDistance) {
                    bestDistance = d
                    best = EdgeSnap(a, b, isRay = false)
                }
            }
            return best
        }
    }
}

/** What a pen sliding along an instrument shows next to it; [format] writes it in the UI's decimals. */
sealed class InstrumentReading {
    abstract fun format(decimalSeparator: Char = ','): String

    /** Along an edge: how long the line is ("42,3 mm", "12,5 cm"). */
    data class Length(val mm: Double) : InstrumentReading() {
        override fun format(decimalSeparator: Char): String = ShapeBuilder.mm(mm, decimalSeparator)
    }

    /** On a protractor's ray: its angle, 0…360° counterclockwise from the protractor's base. */
    data class Angle(val degrees: Int) : InstrumentReading() {
        override fun format(decimalSeparator: Char): String = "$degrees°"
    }
}

/**
 * Fingers on an instrument (the iPad's `instrumentPanned` and `instrumentTurned`): their middle
 * carries it, two of them turn it, the turn settling on 15° steps within 1.6°. Finger positions are
 * document points, keyed by pointer id; a finger that joins or leaves moves nothing.
 */
class InstrumentDrag(start: Instrument) {
    companion object {
        /** How close (degrees) a turn comes to a 15° step before it settles on it. */
        const val SETTLE = 1.6

        /**
         * The angle a turn to [angle] (radians) settles at: the nearest 15° step when it is within
         * [SETTLE] of it, with that step in degrees; else the angle itself and null.
         */
        fun settleTurn(angle: Double): Pair<Double, Int?> {
            val degrees = angle * 180 / PI
            val nearest = roundedAway(degrees / 15) * 15
            if (abs(degrees - nearest) < SETTLE) return Pair(nearest * PI / 180, nearest.toInt())
            return Pair(angle, null)
        }
    }

    /** The instrument where the fingers have put it. */
    var instrument: Instrument = start
        private set

    private val fingers = LinkedHashMap<Int, Pt>()

    /** The angle when the turn began and how far the fingers have turned since (radians). */
    private var turnFrom = start.angle
    private var turned = 0.0

    /** The 15° step the turn rests on, while it rests on one. */
    var settled: Int? = null
        private set

    /** Two fingers or more: the instrument turns with them (its angle is shown). */
    val isTurning: Boolean get() = fingers.size >= 2

    val isEmpty: Boolean get() = fingers.isEmpty()

    operator fun contains(id: Int): Boolean = id in fingers

    /** A finger comes down; with the second one a turn begins. */
    fun down(id: Int, at: Pt) {
        fingers[id] = at
        if (fingers.size == 2) {
            turnFrom = instrument.angle
            turned = 0.0
            // A turn starts settled on the step the instrument rests on: no click until it leaves
            // that step and comes back, or reaches another.
            settled = settleTurn(turnFrom).second
        }
    }

    /** A finger lifts: the others carry on from where they are. */
    fun up(id: Int) {
        fingers.remove(id)
        if (fingers.size < 2) settled = null
    }

    /**
     * The fingers moved to [positions] (those not in it stay where they were): the instrument goes
     * with their middle and, with two, turns as the line between the first two turns. True when the
     * turn has just settled on a new 15° step (the pen bar's tick).
     */
    fun move(positions: Map<Int, Pt>): Boolean {
        if (fingers.isEmpty()) return false
        val before = fingers.values.toList()
        val after = fingers.keys.map { positions[it] ?: fingers.getValue(it) }
        val mx = after.sumOf { it.x } / after.size - before.sumOf { it.x } / before.size
        val my = after.sumOf { it.y } / after.size - before.sumOf { it.y } / before.size
        var angle = instrument.angle
        var ticked = false
        if (after.size >= 2) {
            var delta = atan2(after[1].y - after[0].y, after[1].x - after[0].x) - atan2(before[1].y - before[0].y, before[1].x - before[0].x)
            while (delta > PI) delta -= 2 * PI
            while (delta < -PI) delta += 2 * PI
            turned += delta
            val (a, step) = settleTurn(turnFrom + turned)
            angle = a
            if (step != null && step != settled) ticked = true
            settled = step
        }
        for ((i, id) in fingers.keys.toList().withIndex()) fingers[id] = after[i]
        instrument = Instrument(instrument.kind, Pt(instrument.center.x + mx, instrument.center.y + my), angle)
        return ticked
    }
}

/** The compass's setting: its center (page-local) and radius on a page. */
data class CompassState(val page: Int, val center: Pt, val radius: Double)

/**
 * An arc the pen draws round a set compass (page-local): its points, at most 2° apart, and the
 * angle the pen reached last. It starts on the circle where the pen points from the center.
 */
class CompassArc(val compass: CompassState, at: Pt) {
    /** The angle (radians, y down) of the pen's last place round the center. */
    var last: Double = atan2(at.y - compass.center.y, at.x - compass.center.x)
        private set

    val points: MutableList<Pt> = arrayListOf(Compass.onCircle(compass, last))

    /** The pen moved to [at]: the arc follows it round the short way, a point every 2° at most. */
    fun swing(at: Pt) {
        val c = compass
        val angle = atan2(at.y - c.center.y, at.x - c.center.x)
        var delta = angle - last
        while (delta > PI) delta -= 2 * PI
        while (delta < -PI) delta += 2 * PI
        val steps = max(1, ceil(abs(delta) / (2 * PI / 180)).toInt())
        for (i in 1..steps) {
            points.add(Compass.onCircle(c, last + delta * i / steps))
        }
        last = angle
    }
}

/** The compass tool's rules (CanvasView.swift's compassBegan and compassEnded). */
object Compass {
    /** How far from the center (view points) a pen must come down to draw an arc rather than set a new center. */
    const val CENTER_REACH = 14.0

    /** The smallest radius (points) that sets the compass; a shorter drag sets nothing. */
    const val MIN_RADIUS = 3.0

    /** The point of [c]'s circle at [angle]. */
    fun onCircle(c: CompassState, angle: Double): Pt = Pt(c.center.x + cos(angle) * c.radius, c.center.y + sin(angle) * c.radius)

    /** True when a pen down at [p] on [page] swings an arc of [c]: the same page, farther than [reach] from its center. */
    fun startsArc(c: CompassState?, page: Int, p: Pt, reach: Double): Boolean =
        c != null && c.page == page && hypot(p.x - c.center.x, p.y - c.center.y) > reach

    /** The setting a drag from [center] to [end] leaves, or null when it is too short. */
    fun set(page: Int, center: Pt, end: Pt): CompassState? {
        val r = hypot(end.x - center.x, end.y - center.y)
        return if (r > MIN_RADIUS) CompassState(page, center, r) else null
    }
}
