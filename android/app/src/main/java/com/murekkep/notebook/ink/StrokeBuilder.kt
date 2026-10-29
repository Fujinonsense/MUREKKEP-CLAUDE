package com.murekkep.notebook.ink

import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.sqrt

// Port of Murekkep.swiftpm/StrokeBuilder.swift: raw pen samples become a smoothed, decimated stroke
// whose radius follows pressure, tilt and (calligraphy) the nib angle, and whose ink value follows
// the pen's speed. Every number is the iPad's.
//
// Left out for now, to come with the shape recognizer: hold-to-shape (`snapToLine`, `snapToShape`,
// `apply(path:)`, `editable`, `shapeAdjustment`, `drawnPath`, `isStraight`). Left out for good: the
// Pencil's late force estimates (`refine`, `estimationIndex`), which Android pens do not send.

/** Float.pi of the iPad (3.14159274). */
private const val PI_F = 3.1415927f

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
    private var smoothed: Vec2? = null
    private var lastRaw: Vec2? = null
    private var lastCommitted: Vec2? = null
    private var lastTime: Double = 0.0
    private var lastRadius: Float = width * 0.5f
    private var inkLevel: Float = 1f
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

    /** Committed points plus the live tip and the predicted samples, for drawing while the pen moves. */
    fun preview(predicted: List<InputSample>): List<InkPoint> {
        val out = ArrayList<InkPoint>(committed.size + predicted.size + 1)
        out.addAll(committed)
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
        if (raw != null && last != null && vlength(raw - last) > 0.1f) {
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
