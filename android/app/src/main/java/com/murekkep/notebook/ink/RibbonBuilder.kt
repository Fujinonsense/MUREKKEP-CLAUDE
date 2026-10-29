package com.murekkep.notebook.ink

import kotlin.math.abs
import kotlin.math.acos
import kotlin.math.atan2
import kotlin.math.ceil
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt

// Port of Murekkep.swiftpm/RibbonBuilder.swift: a stroke becomes one continuous triangle mesh, a
// smoothed centerline with a strip along it and round caps at both ends. Because the across and
// along coordinates are interpolated over a single surface, shading has no seams at turns and every
// pixel of the stroke is covered once. The output is GL-ready (android/PORTING.md, "Ribbon meshes").

/**
 * A growable ribbon mesh. `vertices` holds [RibbonBuilder.FLOATS_PER_VERTEX] floats a vertex, in the
 * order of the GL attribute table in android/PORTING.md: center x y, offset x y, tangent x y, r, u,
 * side, arc, ink, and the stroke slot's bits (`Float.fromBits(slot)`, read back with `toRawBits()`;
 * the shader reads them as a uint). `indices` holds triangle corners, absolute in this mesh. The
 * counts say how much of each array is in use; the arrays grow as strokes are appended.
 */
class RibbonOut(vertexCapacity: Int = 256, indexCapacity: Int = 512) {
    var vertices: FloatArray = FloatArray(max(vertexCapacity, 1) * RibbonBuilder.FLOATS_PER_VERTEX)
        private set
    var vertexCount: Int = 0
        internal set
    var indices: IntArray = IntArray(max(indexCapacity, 1))
        private set
    var indexCount: Int = 0
        internal set

    /** Bytes of vertex data in use (the GL buffer size). */
    val vertexBytes: Int get() = vertexCount * RibbonBuilder.VERTEX_BYTES

    fun clear() {
        vertexCount = 0
        indexCount = 0
    }

    /** Makes room for `extra` more vertices. */
    fun reserveVertices(extra: Int) {
        val needed = (vertexCount + extra) * RibbonBuilder.FLOATS_PER_VERTEX
        if (needed > vertices.size) vertices = vertices.copyOf(max(needed, vertices.size * 2))
    }

    /** Makes room for `extra` more indices. */
    fun reserveIndices(extra: Int) {
        val needed = indexCount + extra
        if (needed > indices.size) indices = indices.copyOf(max(needed, indices.size * 2))
    }
}

object RibbonBuilder {
    /** Floats a vertex in [RibbonOut.vertices]: the layout of the iPad's `RibbonVertexGPU`. */
    const val FLOATS_PER_VERTEX = 12

    /** Bytes a vertex (the GL stride). */
    const val VERTEX_BYTES = FLOATS_PER_VERTEX * 4

    /** Segments per half circle of a cap. */
    private const val CAP_SEGMENTS = 10

    /** Largest direction change between neighbouring vertex rows; quicker turns get a fan of rows. */
    private const val MAX_JOIN_TURN = 0.15f

    /** Float.pi of the iPad. */
    private const val PI_F = 3.1415927f

    /** Samples as parallel arrays, so the loops below allocate nothing per point. */
    private class Samples(capacity: Int) {
        var n = 0
        var x = FloatArray(capacity)
        var y = FloatArray(capacity)
        var r = FloatArray(capacity)
        var ink = FloatArray(capacity)

        fun add(px: Float, py: Float, pr: Float, pink: Float) {
            if (n == x.size) {
                val size = max(8, n * 2)
                x = x.copyOf(size)
                y = y.copyOf(size)
                r = r.copyOf(size)
                ink = ink.copyOf(size)
            }
            x[n] = px
            y[n] = py
            r[n] = pr
            ink[n] = pink
            n++
        }

        fun copy(): Samples {
            val out = Samples(max(n, 1))
            x.copyInto(out.x, 0, 0, n)
            y.copyInto(out.y, 0, 0, n)
            r.copyInto(out.r, 0, 0, n)
            ink.copyInto(out.ink, 0, 0, n)
            out.n = n
            return out
        }

        fun toList(): List<InkPoint> = List(n) { InkPoint(x[it], y[it], r[it], ink[it]) }

        companion object {
            fun of(pts: List<InkPoint>): Samples {
                val s = Samples(max(pts.size, 1))
                for (p in pts) s.add(p.x, p.y, p.r, p.ink)
                return s
            }
        }
    }

    /** vlength of the iPad: sqrt(x*x + y*y), in that order. */
    private fun length(x: Float, y: Float): Float = sqrt(x * x + y * y)

    /**
     * Appends one stroke's mesh to `out`, its vertices tagged with `stroke`, the stroke's record slot.
     * `relax` lets thick ink bend smoothly through sharp corners (see [relaxed]).
     */
    fun append(points: List<InkPoint>, stroke: Int, relax: Boolean = false, out: RibbonOut) {
        val slot = stroke
        if (points.isEmpty()) return
        val input = Samples.of(points)
        val samples = smoothed(if (relax) relaxed(input) else input)
        val n = samples.n
        val sx = samples.x
        val sy = samples.y
        val sr = samples.r
        val sink = samples.ink
        val arcs = FloatArray(n)
        for (i in 1 until n) {
            arcs[i] = arcs[i - 1] + length(sx[i] - sx[i - 1], sy[i] - sy[i - 1])
        }
        // A dot: a full disc made of two caps.
        if (n == 1 || arcs[n - 1] < 1e-3f) {
            appendCap(out, sx[0], sy[0], sr[0], sink[0], 0f, 1f, 0f, true, slot)
            appendCap(out, sx[0], sy[0], sr[0], sink[0], 0f, 1f, 0f, false, slot)
            return
        }

        // Central-difference tangents; a zero-length step keeps the previous direction.
        val tx = FloatArray(n)
        val ty = FloatArray(n)
        var lastX = 1f
        var lastY = 0f
        var foundFirst = false
        for (i in 0 until n) {
            val a = max(i - 1, 0)
            val b = min(i + 1, n - 1)
            val dx = sx[b] - sx[a]
            val dy = sy[b] - sy[a]
            val l = length(dx, dy)
            if (l > 1e-5f) {
                lastX = dx / l
                lastY = dy / l
                if (!foundFirst) {
                    foundFirst = true
                    for (j in 0 until i) {
                        tx[j] = lastX
                        ty[j] = lastY
                    }
                }
            }
            tx[i] = lastX
            ty[i] = lastY
        }

        // One row per sample: left edge, centerline, right edge. Each half of the ribbon is then a
        // clean strip, so even rows that share a center (round joins) never overlap each other.
        val base = out.vertexCount
        out.reserveVertices(n * 3 + (CAP_SEGMENTS + 2) * 2)
        var rows = 0
        for (i in 0 until n) {
            if (i > 0) {
                val ax = tx[i - 1]
                val ay = ty[i - 1]
                val bx = tx[i]
                val by = ty[i]
                val turn = atan2(ax * by - ay * bx, ax * bx + ay * by)
                val extra = min(ceil(abs(turn) / MAX_JOIN_TURN).toInt() - 1, 24)
                if (extra > 0) {
                    val start = atan2(ay, ax)
                    val px = sx[i - 1]
                    val py = sy[i - 1]
                    val pr = sr[i - 1]
                    val pink = sink[i - 1]
                    val qx = sx[i]
                    val qy = sy[i]
                    val qr = sr[i]
                    val qink = sink[i]
                    for (j in 1..extra) {
                        val f = j.toFloat() / (extra + 1).toFloat()
                        val angle = start + turn * f
                        appendRow(
                            out,
                            px + (qx - px) * f, py + (qy - py) * f, pr + (qr - pr) * f, pink + (qink - pink) * f,
                            cos(angle), sin(angle), arcs[i - 1] + (arcs[i] - arcs[i - 1]) * f, slot,
                        )
                        rows++
                    }
                }
            }
            appendRow(out, sx[i], sy[i], sr[i], sink[i], tx[i], ty[i], arcs[i], slot)
            rows++
        }
        out.reserveIndices((rows - 1) * 12 + CAP_SEGMENTS * 6)
        val idx = out.indices
        var k = out.indexCount
        for (i in 0 until rows - 1) {
            val l0 = base + i * 3
            val c0 = l0 + 1
            val r0 = l0 + 2
            val l1 = l0 + 3
            val c1 = l0 + 4
            val r1 = l0 + 5
            idx[k] = c0
            idx[k + 1] = l0
            idx[k + 2] = l1
            idx[k + 3] = c0
            idx[k + 4] = l1
            idx[k + 5] = c1
            idx[k + 6] = c0
            idx[k + 7] = r1
            idx[k + 8] = r0
            idx[k + 9] = c0
            idx[k + 10] = c1
            idx[k + 11] = r1
            k += 12
        }
        out.indexCount = k
        appendCap(out, sx[0], sy[0], sr[0], sink[0], arcs[0], tx[0], ty[0], false, slot)
        appendCap(out, sx[n - 1], sy[n - 1], sr[n - 1], sink[n - 1], arcs[n - 1], tx[n - 1], ty[n - 1], true, slot)
    }

    /** Writes one vertex's 12 floats at `k`. */
    private fun put(
        v: FloatArray, k: Int,
        cx: Float, cy: Float, ox: Float, oy: Float, tX: Float, tY: Float,
        r: Float, u: Float, side: Float, arc: Float, ink: Float, bits: Float,
    ) {
        v[k] = cx
        v[k + 1] = cy
        v[k + 2] = ox
        v[k + 3] = oy
        v[k + 4] = tX
        v[k + 5] = tY
        v[k + 6] = r
        v[k + 7] = u
        v[k + 8] = side
        v[k + 9] = arc
        v[k + 10] = ink
        v[k + 11] = bits
    }

    private fun appendRow(
        out: RibbonOut, px: Float, py: Float, pr: Float, pink: Float,
        tX: Float, tY: Float, arc: Float, slot: Int,
    ) {
        val nX = -tY
        val nY = tX
        out.reserveVertices(3)
        val v = out.vertices
        val k = out.vertexCount * FLOATS_PER_VERTEX
        val bits = Float.fromBits(slot)
        put(v, k, px, py, nX, nY, tX, tY, pr, 1f, 1f, arc, pink, bits)
        put(v, k + FLOATS_PER_VERTEX, px, py, 0f, 0f, tX, tY, pr, 0f, 0f, arc, pink, bits)
        put(v, k + 2 * FLOATS_PER_VERTEX, px, py, -nX, -nY, tX, tY, pr, -1f, -1f, arc, pink, bits)
        out.vertexCount += 3
    }

    /** Half disc around the point, from the left edge through the stroke's end direction to the right edge. */
    private fun appendCap(
        out: RibbonOut, px: Float, py: Float, pr: Float, pink: Float, arc: Float,
        tX: Float, tY: Float, forward: Boolean, slot: Int,
    ) {
        val nX = -tY
        val nY = tX
        val dX = if (forward) tX else -tX
        val dY = if (forward) tY else -tY
        out.reserveVertices(CAP_SEGMENTS + 2)
        val v = out.vertices
        val center = out.vertexCount
        val bits = Float.fromBits(slot)
        var k = center * FLOATS_PER_VERTEX
        put(v, k, px, py, 0f, 0f, tX, tY, pr, 0f, 0f, arc, pink, bits)
        k += FLOATS_PER_VERTEX
        for (j in 0..CAP_SEGMENTS) {
            val a = j.toFloat() / CAP_SEGMENTS.toFloat() * PI_F
            val c = cos(a)
            val s = sin(a)
            // The vertex shader extends `arc` into the cap by the rim's distance along the tangent.
            put(v, k, px, py, nX * c + dX * s, nY * c + dY * s, tX, tY, pr, 1f, c, arc, pink, bits)
            k += FLOATS_PER_VERTEX
        }
        out.vertexCount = center + CAP_SEGMENTS + 2
        out.reserveIndices(CAP_SEGMENTS * 3)
        val idx = out.indices
        var m = out.indexCount
        for (j in 0 until CAP_SEGMENTS) {
            val a = center + 1 + j
            idx[m] = center
            idx[m + 1] = a
            idx[m + 2] = a + 1
            m += 3
        }
        out.indexCount = m
    }

    /**
     * Gaussian smoothing along the stroke with a width that grows with the ink radius: a sharp corner
     * becomes a bend about as tight as the ink is thick, like real ink pulled smooth by surface
     * tension, so raised 3D ink shows no crease where the pen turned. Thin lines keep their shape, and
     * the window shrinks towards the ends so the first and last points stay where they were drawn.
     */
    fun relaxed(pts: List<InkPoint>): List<InkPoint> = relaxed(Samples.of(pts)).toList()

    private fun relaxed(pts: Samples): Samples {
        val n = pts.n
        if (n <= 2) return pts
        val px = pts.x
        val py = pts.y
        val arc = FloatArray(n)
        for (i in 1 until n) {
            arc[i] = arc[i - 1] + length(px[i] - px[i - 1], py[i] - py[i - 1])
        }
        val out = pts.copy()
        var lo = 0
        var hi = 0
        for (i in 0 until n) {
            val r = pts.r[i]
            val t = clampf((r - 1.5f) / 2.5f, 0f, 1f)
            val sigma = max(r * (0.35f + 0.55f * t * t * (3f - 2f * t)), 0.3f)
            val reach = minOf(2.5f * sigma, arc[i], arc[n - 1] - arc[i])
            while (arc[i] - arc[lo] > reach) lo++
            while (lo > 0 && arc[i] - arc[lo - 1] <= reach) lo--
            hi = max(hi, i)
            while (hi + 1 < n && arc[hi + 1] - arc[i] <= reach) hi++
            while (hi > i && arc[hi] - arc[i] > reach) hi--
            var sumX = 0f
            var sumY = 0f
            var weight = 0f
            for (j in lo..hi) {
                val dd = arc[j] - arc[i]
                val ds = (arc[min(j + 1, n - 1)] - arc[max(j - 1, 0)]) * 0.5f + 1e-4f
                val w = exp(-0.5f * dd * dd / (sigma * sigma)) * ds
                sumX += px[j] * w
                sumY += py[j] * w
                weight += w
            }
            if (weight <= 0f) continue
            val x = sumX / weight
            val y = sumY / weight
            if (!x.isFinite() || !y.isFinite()) continue
            out.x[i] = x
            out.y[i] = y
        }
        return out
    }

    /**
     * Catmull-Rom through the input points: long gaps and sharp turns get extra samples so the ribbon
     * follows a smooth curve instead of a polyline.
     */
    fun smoothed(pts: List<InkPoint>): List<InkPoint> = smoothed(Samples.of(pts)).toList()

    private fun smoothed(pts: Samples): Samples {
        val n = pts.n
        if (n <= 2) return pts
        val px = pts.x
        val py = pts.y
        val pr = pts.r
        val pink = pts.ink
        val out = Samples(n * 2)
        out.add(px[0], py[0], pr[0], pink[0])
        for (i in 0 until n - 1) {
            val i0 = max(i - 1, 0)
            val i2 = i + 1
            val i3 = min(i + 2, n - 1)
            val segX = px[i2] - px[i]
            val segY = py[i2] - py[i]
            val len = length(segX, segY)
            if (len < 1e-4f) continue
            val step = max(0.5f, min(pr[i], pr[i2]) * 0.45f)
            var m = ceil(len / step).toInt()
            // Extra samples where the direction changes quickly.
            val turn = max(
                angle(px[i] - px[i0], py[i] - py[i0], segX, segY),
                angle(segX, segY, px[i3] - px[i2], py[i3] - py[i2]),
            )
            m = max(m, ceil(turn / 0.3f).toInt())
            m = min(max(m, 1), 32)
            val x0 = px[i0]
            val y0 = py[i0]
            val x1 = px[i]
            val y1 = py[i]
            val x2 = px[i2]
            val y2 = py[i2]
            val x3 = px[i3]
            val y3 = py[i3]
            for (k in 1..m) {
                val t = k.toFloat() / m.toFloat()
                val x = catmullRom(x0, x1, x2, x3, t)
                val y = catmullRom(y0, y1, y2, y3, t)
                if (!x.isFinite() || !y.isFinite()) continue
                out.add(x, y, pr[i] + (pr[i2] - pr[i]) * t, pink[i] + (pink[i2] - pink[i]) * t)
            }
        }
        return out
    }

    private fun angle(ax: Float, ay: Float, bx: Float, by: Float): Float {
        val la = length(ax, ay)
        val lb = length(bx, by)
        if (la <= 1e-5f || lb <= 1e-5f) return 0f
        return acos(clampf((ax * bx + ay * by) / (la * lb), -1f, 1f))
    }

    /** One coordinate of the iPad's catmullRom, in its order of operations. */
    private fun catmullRom(p0: Float, p1: Float, p2: Float, p3: Float, t: Float): Float {
        val t2 = t * t
        val t3 = t2 * t
        val a = p1 * 2f
        val b = (p2 - p0) * t
        val c = (p0 * 2f - p1 * 5f + p2 * 4f - p3) * t2
        val d = (p1 * 3f - p0 - p2 * 3f + p3) * t3
        return (a + b + c + d) * 0.5f
    }
}
