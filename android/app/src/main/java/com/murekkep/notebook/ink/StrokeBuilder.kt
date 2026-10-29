package com.murekkep.notebook.ink

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.sqrt

// Port of Murekkep.swiftpm/StrokeBuilder.swift: raw pen samples become a smoothed, decimated stroke
// whose radius follows pressure, tilt and (calligraphy) the nib angle, and whose ink value follows
// the pen's speed. Every number is the iPad's.
//
// Hold-to-shape is here too (`snapToLine`, `snapToShape`, `apply`, `drawnPath`, `isStraight`,
// `shapeAdjustment`, `editable`): once the pen rests, the stroke becomes a line that keeps following
// the pen, or a clean shape (ShapeRecognizer.kt) that the pen then resizes and turns. Left out for
// good: the Pencil's late force estimates (`refine`, `estimationIndex`), which Android pens do not
// send, so the iPad's `pendingEstimates` has nothing to forget when a stroke snaps.

/** Float.pi of the iPad: Swift rounds it toward zero, to 3.1415925 (bits 0x40490FDA), not to the nearest Float 3.1415927. */
private const val PI_F = 3.1415925f

/** Current resize (1 = as recognized) and turn in degrees of a snapped shape, for the label next to the pen. */
data class ShapeAdjustment(val scale: Double, val degrees: Int)

/** Turns raw touch samples into a smoothed, decimated stroke. One builder per stroke. */
class StrokeBuilder(
    val brush: Brush,
    val color: InkColor,
    /** Stroke width in page points. */
    val width: Float,
    /** Random per-stroke value for shader variation (grass: the integer part is the flower level). */
    val seed: Float,
) {
    /** Calligraphy nib angle in radians (page space). */
    var nibAngle: Float = 0.66f

    /** Add the pen's barrel roll to the nib angle. */
    var useRoll: Boolean = true

    private val committed = ArrayList<InkPoint>()

    /** Hold-to-shape turned the stroke into a line or another clean shape. */
    var isStraight: Boolean = false
        private set

    /** A recognized shape other than a line: the pen now resizes and turns it. */
    private var isFrozen = false
    private var shapeBase: List<Pt> = emptyList()
    private var shapeAnchor = Pt.ZERO
    private var shapeGrab = Pt.ZERO
    private var shapeRadius = 1f
    private var shapeInk = 1f
    private var adjusting = false

    /** Current resize (1 = as recognized) and turn in degrees, for the label next to the pen. */
    var shapeAdjustment: ShapeAdjustment? = null
        private set

    /**
     * The recognized shape with its corners, kept in step with the pen so its handles can be
     * shown once the pen lifts. null for freehand strokes.
     */
    var editable: EditableShape? = null
        private set

    private var editableBase: EditableShape? = null
    private var straightStart: InkPoint? = null
    private var smoothed: Vec2? = null
    private var lastRaw: Vec2? = null
    private var lastCommitted: Vec2? = null
    private var lastTime: Double = 0.0
    private var lastRadius: Float = width * 0.5f
    private var inkLevel: Float = 1f
    private var lastSample: InputSample? = null
    private var direction: Vec2 = Vec2(1f, 0f)

    /** The committed points so far (a live view; copy it to keep it). */
    val points: List<InkPoint> get() = committed

    /** Latest raw pen position (page space). */
    val tip: Vec2? get() = lastRaw

    /** Pressure part of the radius. */
    fun radius(force: Float): Float {
        val base = width * 0.5f
        val s = brush.pressureSensitivity
        if (s <= 0f) return base
        val f = if (force > 0f) force else 1f
        val pn = clampf(f, 0.05f, 3f)
        return base * ((1f - s) + s * sqrt(pn))
    }

    /** Nib angle for this sample (calligraphy). */
    fun nib(roll: Float): Float = nibAngle + (if (useRoll) roll else 0f)

    /** 0 when the pen is upright, 1 when it lies flat on the glass. */
    private fun tilt(s: InputSample): Float {
        if (!s.isPencil) return 0f
        return clampf(1f - s.altitude / (PI_F / 2f), 0f, 1f)
    }

    private fun calligraphyRadius(base: Float, dir: Vec2, roll: Float): Float {
        val a = nib(roll)
        val edgeX = cos(a)
        val edgeY = sin(a)
        // Moving along the nib edge leaves a hairline, moving across it the full width.
        val cross = abs(dir.x * edgeY - dir.y * edgeX)
        return base * (0.16f + 0.84f * cross)
    }

    private fun targetRadius(s: InputSample): Float {
        var r = radius(s.force)
        when (brush) {
            Brush.PENCIL -> {
                // Tilting the pencil shades with the side of the lead.
                val t = tilt(s)
                r *= 1f + 3.2f * t * t
            }
            Brush.WATERCOLOR -> r *= 1f + 0.8f * tilt(s)
            Brush.CALLIGRAPHY -> r = calligraphyRadius(r, direction, s.roll)
            Brush.FOUNTAIN -> {
                // Pressing harder spreads the nib's tines: the width follows pressure closely
                // and downstrokes come out fuller, like a flexible fountain-pen nib.
                val f = if (s.force > 0f) s.force else 1f
                val pn = clampf(f, 0.05f, 3.5f)
                val spread = 0.22f + 0.78f * pn.pow(0.85f)
                val downstroke = 0.82f + 0.25f * max(0f, direction.y)
                r = width * 0.5f * spread * downstroke
            }
            else -> {}
        }
        return r
    }

    /** Per-point "ink": pooling for wet ink, graphite density for the pencil. */
    private fun inkValue(s: InputSample): Float {
        if (brush != Brush.PENCIL) return inkLevel
        val f = if (s.force > 0f) s.force else 1f
        val pressure = clampf(0.35f + 0.4f * f, 0.25f, 1f)
        return clampf(pressure * (1f - 0.55f * tilt(s)), 0.12f, 1f)
    }

    private val tipInk: Float
        get() = if (brush == Brush.PENCIL) (committed.lastOrNull()?.ink ?: 0.7f) else inkLevel

    fun add(sample: InputSample) {
        // Predicted samples are for `preview` only; the iPad never adds one, so neither does Android.
        if (sample.predicted) return
        val raw = Vec2(sample.x, sample.y)
        if (!raw.x.isFinite() || !raw.y.isFinite()) return
        lastRaw = raw
        lastSample = sample
        if (isStraight) {
            if (isFrozen) {
                adjustShape(raw)
            } else {
                updateLine(raw)
            }
            return
        }
        val prev = smoothed
        val last = lastCommitted
        if (prev == null || last == null) {
            smoothed = raw
            lastCommitted = raw
            lastTime = sample.timestamp
            val r = targetRadius(sample)
            lastRadius = r
            committed.add(InkPoint(raw.x, raw.y, r, if (brush == Brush.PENCIL) inkValue(sample) else 1f))
            return
        }
        val s = prev + (raw - prev) * 0.62f
        smoothed = s
        val delta = s - last
        val dist = vlength(delta)
        if (dist > 0.05f) {
            var d = delta / dist
            if (vdot(d, direction) < 0f && brush == Brush.CALLIGRAPHY) d = -d
            val blended = direction * 0.55f + d * 0.45f
            val l = vlength(blended)
            direction = if (l > 1e-4f) blended / l else d
        }
        val r = targetRadius(sample)
        val rr = lastRadius + (r - lastRadius) * 0.5f
        val spacing = max(0.6f, rr * 0.4f)
        if (dist < spacing) return
        val dt = max(sample.timestamp - lastTime, 1.0 / 480.0)
        val speed = dist / dt.toFloat()
        val target = clampf(1f - speed / 700f, 0.05f, 1f)
        inkLevel = inkLevel * 0.8f + target * 0.2f
        committed.add(InkPoint(s.x, s.y, rr, inkValue(sample)))
        lastCommitted = s
        lastTime = sample.timestamp
        lastRadius = rr
    }

    /** Hold-to-straighten: the stroke becomes a line from its start to the pen, which can still move. */
    fun snapToLine(): Boolean {
        if (isStraight) return false
        val first = committed.firstOrNull() ?: return false
        val end = lastRaw ?: return false
        if (!(vlength(end - first.position) > 6f)) return false
        val n = committed.size.toFloat()
        var avgR = 0f
        var avgInk = 0f
        for (p in committed) {
            avgR += p.r
            avgInk += p.ink
        }
        avgR /= n
        avgInk /= n
        straightStart = InkPoint(first.x, first.y, avgR, avgInk)
        isStraight = true
        updateLine(end)
        return true
    }

    /** What the pen has drawn so far, tip included (page space). */
    val drawnPath: List<Pt>
        get() {
            val out = ArrayList<Pt>(committed.size + 1)
            for (p in committed) out.add(Pt(p.x.toDouble(), p.y.toDouble()))
            val raw = lastRaw
            val last = lastCommitted
            if (raw != null && last != null && vlength(raw - last) > 0.05f) {
                out.add(Pt(raw.x.toDouble(), raw.y.toDouble()))
            }
            return out
        }

    /**
     * Hold-to-shape: a line keeps following the pen; a circle, ellipse, curve, rectangle or polygon
     * replaces the stroke in the same ink. Returns the shape's name.
     */
    fun snapToShape(): ShapeName? {
        if (isStraight) return null
        val shape = ShapeRecognizer.recognize(drawnPath) ?: return null
        if (shape.kind == ShapeMatch.Kind.LINE) {
            return if (snapToLine()) shape.name else null
        }
        apply(shape.path)
        if (!isFrozen) return null
        shapeBase = shape.path
        editableBase = EditableShape.from(shape)
        editable = editableBase
        val box = Geo.bounds(shape.path)
        shapeAnchor = if (shape.isClosed) Pt(box.midX, box.midY) else shape.path[0]
        val tip = lastRaw
        if (tip != null) {
            shapeGrab = Pt(tip.x.toDouble(), tip.y.toDouble())
        }
        adjusting = false
        shapeAdjustment = ShapeAdjustment(scale = 1.0, degrees = 0)
        return shape.name
    }

    /** Replaces the stroke with `path`, keeping its average width and ink. */
    fun apply(path: List<Pt>) {
        if (path.size < 2 || committed.isEmpty()) return
        val n = committed.size.toFloat()
        var r = 0f
        var ink = 0f
        for (p in committed) {
            r += p.r
            ink += p.ink
        }
        shapeRadius = r / n
        shapeInk = ink / n
        place(path)
        isStraight = true
        isFrozen = true
    }

    /** Ink points along `path` with the stroke's width and ink (calligraphy follows the direction). */
    private fun place(path: List<Pt>) {
        // Corners stay points of the stroke, so a square keeps square corners in every ink.
        val dense = Geo.densify(path, max(1.5f, shapeRadius * 0.7f).toDouble())
        val out = ArrayList<InkPoint>(dense.size)
        for ((i, p) in dense.withIndex()) {
            var r = shapeRadius
            if (brush == Brush.CALLIGRAPHY) {
                val a = dense[max(i - 1, 0)]
                val b = dense[min(i + 1, dense.size - 1)]
                val d = Vec2((b.x - a.x).toFloat(), (b.y - a.y).toFloat())
                val len = vlength(d)
                if (len > 0.01f) {
                    r = calligraphyRadius(width * 0.5f, d / len, lastSample?.roll ?: 0f)
                }
            }
            out.add(InkPoint(p.x.toFloat(), p.y.toFloat(), r, shapeInk))
        }
        committed.clear()
        committed.addAll(out)
        val last = out.lastOrNull()
        if (last != null) {
            smoothed = last.position
            lastCommitted = last.position
            lastRadius = last.r
        }
    }

    /**
     * After the snap the pen keeps control: moving away from the center grows the shape,
     * moving round it turns it (in 15° clicks near round angles).
     */
    private fun adjustShape(raw: Vec2) {
        if (shapeBase.isEmpty()) return
        val tip = Pt(raw.x.toDouble(), raw.y.toDouble())
        if (!adjusting) {
            // A tiny wobble while lifting the pen changes nothing.
            if (!(Geo.dist(tip, shapeGrab) > 6)) return
            adjusting = true
        }
        val v0x = shapeGrab.x - shapeAnchor.x
        val v0y = shapeGrab.y - shapeAnchor.y
        val v1x = tip.x - shapeAnchor.x
        val v1y = tip.y - shapeAnchor.y
        val l0 = max(hypot(v0x, v0y), 8.0)
        val scale = min(max(hypot(v1x, v1y) / l0, 0.15), 8.0)
        var angle = Geo.wrap(atan2(v1y, v1x) - atan2(v0y, v0x))
        val step = PI / 12
        val nearest = roundedAway(angle / step) * step
        if (abs(angle - nearest) < 4 * PI / 180) angle = nearest
        val c = cos(angle)
        val s = sin(angle)
        val moved = shapeBase.map { p ->
            val x = (p.x - shapeAnchor.x) * scale
            val y = (p.y - shapeAnchor.y) * scale
            Pt(shapeAnchor.x + x * c - y * s, shapeAnchor.y + x * s + y * c)
        }
        place(moved)
        val degrees = roundedAwayToInt(angle * 180 / PI)
        shapeAdjustment = ShapeAdjustment(scale, degrees)
        editable = editableBase?.transformed(anchor = shapeAnchor, scale = scale, angle = angle)
    }

    private fun updateLine(end: Vec2) {
        val start = straightStart ?: return
        var r = start.r
        if (brush == Brush.CALLIGRAPHY) {
            val d = end - start.position
            val len = vlength(d)
            if (len > 0.5f) {
                r = calligraphyRadius(width * 0.5f, d / len, lastSample?.roll ?: 0f)
            }
        }
        committed.clear()
        committed.add(InkPoint(start.x, start.y, r, start.ink))
        committed.add(InkPoint(end.x, end.y, r, start.ink))
        smoothed = end
        lastCommitted = end
        lastRadius = r
        editable = EditableShape(
            EditableShape.Kind.Polyline,
            listOf(Pt(start.x.toDouble(), start.y.toDouble()), Pt(end.x.toDouble(), end.y.toDouble())),
            ShapeName.LINE,
        )
    }

    /** Committed points plus the live tip and the predicted samples, for drawing while the pen moves. */
    fun preview(predicted: List<InputSample>): List<InkPoint> {
        val out = ArrayList<InkPoint>(committed.size + predicted.size + 1)
        out.addAll(committed)
        if (isStraight) return out
        val ink = tipInk
        val raw = lastRaw
        val last = lastCommitted
        if (raw != null && last != null && vlength(raw - last) > 0.05f) {
            out.add(InkPoint(raw.x, raw.y, lastRadius, ink))
        }
        for (p in predicted) {
            val x = p.x
            val y = p.y
            if (!x.isFinite() || !y.isFinite()) continue
            out.add(InkPoint(x, y, lastRadius, ink))
        }
        return out
    }

    /** Final point list. Empty when nothing was drawn. */
    fun finish(): List<InkPoint> {
        val raw = lastRaw
        val last = lastCommitted
        if (!isStraight && raw != null && last != null && vlength(raw - last) > 0.1f) {
            committed.add(InkPoint(raw.x, raw.y, lastRadius, if (brush == Brush.PENCIL) tipInk else min(1f, inkLevel + 0.25f)))
        }
        if ((brush == Brush.WET || brush == Brush.FOUNTAIN) && committed.isNotEmpty()) {
            val i = committed.size - 1
            val p = committed[i]
            committed[i] = p.copy(ink = min(1f, p.ink + 0.35f))
        }
        return committed.toList()
    }
}
