package com.murekkep.notebook.ink

import java.util.concurrent.atomic.AtomicInteger
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

// The ink model of the iPad app (Murekkep.swiftpm/InkModel.swift): page-local points, strokes with
// a brush, a color and a width, pages with a version that GPU caches follow.

/** RGBA in 0...1. */
data class InkColor(val r: Float, val g: Float, val b: Float, val a: Float = 1f) {
    companion object {
        fun hex(hex: Int, alpha: Float = 1f) = InkColor(
            ((hex shr 16) and 0xFF) / 255f,
            ((hex shr 8) and 0xFF) / 255f,
            (hex and 0xFF) / 255f,
            alpha,
        )
    }
}

/** A 2D vector (SIMD2<Float> on iPad). */
data class Vec2(val x: Float, val y: Float) {
    operator fun plus(o: Vec2) = Vec2(x + o.x, y + o.y)
    operator fun minus(o: Vec2) = Vec2(x - o.x, y - o.y)
    operator fun times(k: Float) = Vec2(x * k, y * k)
    operator fun div(k: Float) = Vec2(x / k, y / k)
    operator fun unaryMinus() = Vec2(-x, -y)
    infix fun dot(o: Vec2) = x * o.x + y * o.y
    val length: Float get() = sqrt(x * x + y * y)

    companion object {
        val ZERO = Vec2(0f, 0f)
    }
}

fun vdot(a: Vec2, b: Vec2) = a.x * b.x + a.y * b.y
fun vlength(v: Vec2) = sqrt(v.x * v.x + v.y * v.y)
fun clampf(v: Float, lo: Float, hi: Float) = min(max(v, lo), hi)

/** A committed stroke's sample: position in page points (origin top-left, y down), radius in points,
 *  and how much ink pooled there (0...1; slow strokes pool more). */
data class InkPoint(val x: Float, val y: Float, val r: Float, val ink: Float) {
    val position: Vec2 get() = Vec2(x, y)
}

data class InkRect(val minX: Float, val minY: Float, val maxX: Float, val maxY: Float) {
    val isEmpty: Boolean get() = minX > maxX || minY > maxY

    fun expanded(d: Float) = InkRect(minX - d, minY - d, maxX + d, maxY + d)

    fun intersects(o: InkRect) =
        !(isEmpty || o.isEmpty) && minX <= o.maxX && o.minX <= maxX && minY <= o.maxY && o.minY <= maxY

    fun including(p: InkPoint) =
        InkRect(min(minX, p.x - p.r), min(minY, p.y - p.r), max(maxX, p.x + p.r), max(maxY, p.y + p.r))

    companion object {
        val EMPTY = InkRect(Float.POSITIVE_INFINITY, Float.POSITIVE_INFINITY, Float.NEGATIVE_INFINITY, Float.NEGATIVE_INFINITY)

        fun of(a: Vec2, b: Vec2) = InkRect(min(a.x, b.x), min(a.y, b.y), max(a.x, b.x), max(a.y, b.y))
    }
}

/** Stroke ids are never reused within a run (GPU caches key meshes by them); loaded strokes get new ones. */
object StrokeIds {
    private val counter = AtomicInteger(0)
    fun next(): Int = counter.incrementAndGet()
}

/** A committed stroke. Equal when it is the same stroke (same id). */
class Stroke(
    val brush: Brush,
    val color: InkColor,
    /** Stroke width in page points. */
    val width: Float,
    /** Seconds since 2001-01-01 (as on iPad) when the stroke was committed: drives drying, cooling, blooming. */
    val birth: Double,
    /** Random per-stroke value for shader variation. For grass the integer part is the flower level. */
    val seed: Float,
    val points: List<InkPoint>,
    /** How long the pen took to draw it (only known in the session it was drawn; not saved). */
    val duration: Double = 0.0,
) {
    val id: Int = StrokeIds.next()
    val bounds: InkRect
    val maxRadius: Float

    init {
        var box = InkRect.EMPTY
        var maxR = 0f
        for (p in points) {
            box = box.including(p)
            maxR = max(maxR, p.r)
        }
        bounds = box
        maxRadius = maxR
    }

    /** Same look, different geometry (the partial eraser). */
    fun withPoints(pts: List<InkPoint>) = Stroke(brush, color, width, birth, seed, pts, duration)

    override fun equals(other: Any?) = other is Stroke && other.id == id
    override fun hashCode() = id
}

/** A page's ink. `version` is bumped on every change so GPU caches know when to rebuild. */
data class PageInk(val strokes: List<Stroke> = emptyList(), val version: Int = 0)

/** Seconds since 2001-01-01 00:00 UTC, the iPad's reference date (stroke births are saved in it). */
fun referenceNow(): Double = System.currentTimeMillis() / 1000.0 - 978_307_200.0
