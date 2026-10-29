package com.murekkep.notebook.ink

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.acos
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt
import kotlin.math.truncate

// Port of the geometry half of Murekkep.swiftpm/ShapeRecognizer.swift (`Geo` and `Fit`). CGFloat is
// 64-bit on the iPad, so the shape maths runs in Double here and only the ink points that come out of
// it are Float, as there. Every number is the iPad's; tools/shapecheck runs the real Swift code and
// the JUnit tests hold this port to its answers.

/** A page-local point in Double (the iPad's CGPoint); the ink's own points are the Float [Vec2]. */
data class Pt(val x: Double, val y: Double) {
    companion object {
        val ZERO = Pt(0.0, 0.0)
    }
}

/** The iPad's CGRect: an origin and a size, with the edges and the middle the shape code reads. */
data class Box(val x: Double, val y: Double, val width: Double, val height: Double) {
    val minX: Double get() = x
    val minY: Double get() = y
    val maxX: Double get() = x + width
    val maxY: Double get() = y + height
    val midX: Double get() = x + width / 2
    val midY: Double get() = y + height / 2

    companion object {
        val ZERO = Box(0.0, 0.0, 0.0, 0.0)
    }
}

/**
 * Swift's `rounded()`: schoolbook rounding, halves away from zero. Kotlin's `round` sends halves to
 * the even neighbour and Java's `Math.round` sends them up, so a turn of -22.5° would read -22 instead
 * of the iPad's -23.
 */
fun roundedAway(v: Double): Double {
    val t = truncate(v)
    // The fraction of a Double is exact, so a half is seen as a half.
    return if (abs(v - t) < 0.5) t else t + (if (v < 0) -1.0 else 1.0)
}

/** Swift's `Int(x.rounded())`. */
fun roundedAwayToInt(v: Double): Int = roundedAway(v).toInt()

object Geo {
    fun dist(a: Pt, b: Pt): Double = hypot(a.x - b.x, a.y - b.y)

    fun length(p: List<Pt>): Double {
        var l = 0.0
        for (i in 1 until p.size) {
            l += dist(p[i - 1], p[i])
        }
        return l
    }

    fun bounds(p: List<Pt>): Box {
        if (p.isEmpty()) return Box.ZERO
        val f = p[0]
        var x0 = f.x
        var y0 = f.y
        var x1 = f.x
        var y1 = f.y
        for (q in p) {
            x0 = min(x0, q.x)
            y0 = min(y0, q.y)
            x1 = max(x1, q.x)
            y1 = max(y1, q.y)
        }
        return Box(x0, y0, x1 - x0, y1 - y0)
    }

    fun wrap(a: Double): Double {
        var d = a
        while (d > PI) d -= 2 * PI
        while (d < -PI) d += 2 * PI
        return d
    }

    /** `count` points evenly spaced along the path. */
    fun resample(p: List<Pt>, count: Int): List<Pt> {
        val n = count
        val total = length(p)
        if (!(total > 0) || p.size < 2 || n < 2) return p
        val step = total / (n - 1).toDouble()
        val out = ArrayList<Pt>(n)
        out.add(p[0])
        var acc = 0.0
        for (i in 1 until p.size) {
            var a = p[i - 1]
            val b = p[i]
            var d = dist(a, b)
            while (acc + d >= step && d > 0 && out.size < n) {
                val t = (step - acc) / d
                val q = Pt(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t)
                out.add(q)
                a = q
                d = dist(a, b)
                acc = 0.0
            }
            acc += d
        }
        while (out.size < n) out.add(p[p.size - 1])
        return out
    }

    /**
     * Points no more than `spacing` apart along `p`, keeping every point of `p` (corners stay sharp,
     * unlike `resample`, which can step over a corner).
     */
    fun densify(p: List<Pt>, spacing: Double): List<Pt> {
        if (p.size < 2) return p
        val step = max(spacing, 0.5)
        val out = ArrayList<Pt>((length(p) / step).toInt() + p.size)
        for (i in 0 until p.size - 1) {
            val a = p[i]
            val b = p[i + 1]
            out.add(a)
            val n = min((dist(a, b) / step).toInt(), 4000)
            if (n > 1) {
                for (k in 1 until n) {
                    val t = k.toDouble() / n.toDouble()
                    out.add(Pt(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t))
                }
            }
        }
        out.add(p[p.size - 1])
        return out
    }

    fun resample(p: List<Pt>, spacing: Double): List<Pt> {
        val n = max(2, roundedAway(length(p) / max(spacing, 0.5)).toInt() + 1)
        return resample(p, count = min(n, 2000))
    }

    /** Moving average over `radius` neighbours on each side: takes the tremor out of a hand stroke. */
    fun smooth(p: List<Pt>, closed: Boolean, radius: Int): List<Pt> {
        val k = radius
        val n = p.size
        if (n <= 2 * k + 1) return p
        val out = ArrayList<Pt>(n)
        for (i in 0 until n) {
            var sx = 0.0
            var sy = 0.0
            for (j in -k..k) {
                val idx = if (closed) ((i + j) % n + n) % n else min(max(i + j, 0), n - 1)
                sx += p[idx].x
                sy += p[idx].y
            }
            val c = (2 * k + 1).toDouble()
            out.add(Pt(sx / c, sy / c))
        }
        if (!closed) {
            out[0] = p[0]
            out[n - 1] = p[n - 1]
        }
        return out
    }

    fun segmentDistance(p: Pt, a: Pt, b: Pt): Double {
        val dx = b.x - a.x
        val dy = b.y - a.y
        val l2 = dx * dx + dy * dy
        if (l2 <= 1e-9) return dist(p, a)
        val t = min(max(((p.x - a.x) * dx + (p.y - a.y) * dy) / l2, 0.0), 1.0)
        return hypot(p.x - a.x - t * dx, p.y - a.y - t * dy)
    }

    /** Douglas–Peucker: indices of the points that keep the path within `tolerance`. */
    fun simplify(p: List<Pt>, tolerance: Double): List<Int> {
        if (p.size < 3) return p.indices.toList()
        val keep = BooleanArray(p.size)
        keep[0] = true
        keep[p.size - 1] = true
        val stack = ArrayList<IntArray>()
        stack.add(intArrayOf(0, p.size - 1))
        while (stack.isNotEmpty()) {
            val span = stack.removeAt(stack.size - 1)
            val a = span[0]
            val b = span[1]
            var farthest = -1.0
            var index = -1
            if (b - a >= 2) {
                for (i in (a + 1) until b) {
                    val d = segmentDistance(p[i], p[a], p[b])
                    if (d > farthest) {
                        farthest = d
                        index = i
                    }
                }
            }
            if (farthest > tolerance && index > 0) {
                keep[index] = true
                stack.add(intArrayOf(a, index))
                stack.add(intArrayOf(index, b))
            }
        }
        return keep.indices.filter { keep[it] }
    }

    fun turn(a: Pt, b: Pt, c: Pt): Double =
        abs(wrap(atan2(c.y - b.y, c.x - b.x) - atan2(b.y - a.y, b.x - a.x)))

    /** Total signed turning of a closed path (±2π for one time around). */
    fun winding(p: List<Pt>): Double {
        val n = p.size
        if (n < 3) return 0.0
        var total = 0.0
        for (i in 0 until n) {
            val a = p[(i - 1 + n) % n]
            val b = p[i]
            val c = p[(i + 1) % n]
            total += wrap(atan2(c.y - b.y, c.x - b.x) - atan2(b.y - a.y, b.x - a.x))
        }
        return total
    }

    /** Shoelace area of a closed outline (sign follows the direction it runs). */
    fun signedArea(p: List<Pt>): Double {
        if (p.size < 3) return 0.0
        var a = 0.0
        for (i in p.indices) {
            val q = p[(i + 1) % p.size]
            a += p[i].x * q.y - q.x * p[i].y
        }
        return a / 2
    }

    fun interiorAngle(a: Pt, b: Pt, c: Pt): Double {
        val v1x = a.x - b.x
        val v1y = a.y - b.y
        val v2x = c.x - b.x
        val v2y = c.y - b.y
        val d = (v1x * v2x + v1y * v2y) / max(hypot(v1x, v1y) * hypot(v2x, v2y), 1e-9)
        return acos(min(max(d, -1.0), 1.0))
    }

    /** Removes corners that barely turn (the straightest first). */
    fun dropCollinear(v: List<Pt>, closed: Boolean, minTurn: Double): List<Pt> {
        val out = ArrayList(v)
        // The iPad's `for _ in 0..<30 where out.count > …`: the corners only get fewer, so once the
        // count is down the remaining rounds do nothing.
        for (round in 0 until 30) {
            if (out.size <= (if (closed) 3 else 2)) break
            val lo = if (closed) 0 else 1
            val hi = if (closed) out.size else out.size - 1
            if (lo >= hi) break
            var worst = -1
            var smallest = Double.POSITIVE_INFINITY
            for (i in lo until hi) {
                val t = turn(out[(i - 1 + out.size) % out.size], out[i], out[(i + 1) % out.size])
                if (t < smallest) {
                    smallest = t
                    worst = i
                }
            }
            if (!(smallest < minTurn && worst >= 0)) break
            out.removeAt(worst)
        }
        return out
    }

    /** Joins corners closer than `minLength` (a wobble that looked like two corners). */
    fun mergeClose(v: List<Pt>, closed: Boolean, minLength: Double): List<Pt> {
        val out = ArrayList(v)
        var changed = true
        while (changed && out.size > (if (closed) 3 else 2)) {
            changed = false
            val m = if (closed) out.size else out.size - 1
            for (i in 0 until m) {
                val j = (i + 1) % out.size
                if (!(dist(out[i], out[j]) < minLength)) continue
                if (!closed && i == 0) {
                    out.removeAt(1)
                } else if (!closed && j == out.size - 1) {
                    out.removeAt(i)
                } else {
                    out[i] = Pt((out[i].x + out[j].x) / 2, (out[i].y + out[j].y) / 2)
                    out.removeAt(j)
                }
                changed = true
                break
            }
        }
        return out
    }

    /** RMS distance of the points from the polyline (or polygon). */
    fun polylineRMS(pts: List<Pt>, v: List<Pt>, closed: Boolean): Double {
        if (v.size < 2 || pts.isEmpty()) return Double.POSITIVE_INFINITY
        val m = if (closed) v.size else v.size - 1
        var e = 0.0
        for (q in pts) {
            var best = Double.POSITIVE_INFINITY
            for (i in 0 until m) {
                best = min(best, segmentDistance(q, v[i], v[(i + 1) % v.size]))
            }
            e += best * best
        }
        return sqrt(e / pts.size.toDouble())
    }

    fun nearestIndex(pts: List<Pt>, to: Pt): Int {
        var best = 0
        var bestDistance = Double.POSITIVE_INFINITY
        for ((i, p) in pts.withIndex()) {
            val d = dist(p, to)
            if (d < bestDistance) {
                bestDistance = d
                best = i
            }
        }
        return best
    }

    /** Every corner turns within a short stretch of the path (a real corner), not gradually (a curve). */
    fun cornersAreSharp(pts: List<Pt>, v: List<Pt>, closed: Boolean): Boolean {
        val n = pts.size
        if (n < 5 || v.size < 3) return false
        val w = max(2, roundedAwayToInt(n.toDouble() * 0.05))
        // Hand-drawn corners are often a little round, so a corner may take some room to turn.
        val ratio = if (v.size >= 6) 0.42 else 0.27
        val lo = if (closed) 0 else 1
        val hi = if (closed) v.size else v.size - 1
        for (k in lo until hi) {
            val i = nearestIndex(pts, v[k])
            val a = if (closed) pts[(i - w + n) % n] else pts[max(0, i - w)]
            val c = if (closed) pts[(i + w) % n] else pts[min(n - 1, i + w)]
            val shortTurn = turn(a, pts[i], c)
            val cornerTurn = turn(v[(k - 1 + v.size) % v.size], v[k], v[(k + 1) % v.size])
            if (shortTurn < ratio * cornerTurn) return false
        }
        return true
    }

    /** Scales into the unit square (each axis on its own, so wide and tall drawings compare alike). */
    fun normalized(p: List<Pt>): List<Pt> {
        val b = bounds(p)
        val sx = max(b.width, 1e-6)
        val sy = max(b.height, 1e-6)
        return p.map { Pt((it.x - b.minX) / sx, (it.y - b.minY) / sy) }
    }

    /** Symmetric average nearest-point distance; independent of where and which way a shape was drawn. */
    fun chamfer(a: List<Pt>, b: List<Pt>): Double {
        fun one(x: List<Pt>, y: List<Pt>): Double {
            var s = 0.0
            for (p in x) {
                var m = Double.POSITIVE_INFINITY
                for (q in y) {
                    m = min(m, (p.x - q.x) * (p.x - q.x) + (p.y - q.y) * (p.y - q.y))
                }
                s += sqrt(m)
            }
            return s / max(x.size, 1).toDouble()
        }
        return (one(a, b) + one(b, a)) / 2
    }
}

// MARK: - Fitting

object Fit {
    data class Circle(val center: Pt, val radius: Double, /** Root-mean-square distance from the circle, in points. */ val rms: Double) {
        val relative: Double get() = rms / radius
    }

    data class Ellipse(
        val center: Pt,
        val rx: Double,
        val ry: Double,
        val angle: Double,
        /** RMS of (normalized radius − 1). */
        val residual: Double,
        /** Approximate RMS distance from the ellipse, in points. */
        val rms: Double,
    )

    /** A quadratic Bézier's control point and the RMS distance of the points from the curve. */
    data class Quadratic(val control: Pt, val rms: Double)

    private fun solve3(m: Array<DoubleArray>, v: DoubleArray): DoubleArray? {
        fun det(a: Array<DoubleArray>): Double =
            a[0][0] * (a[1][1] * a[2][2] - a[1][2] * a[2][1]) -
                a[0][1] * (a[1][0] * a[2][2] - a[1][2] * a[2][0]) +
                a[0][2] * (a[1][0] * a[2][1] - a[1][1] * a[2][0])
        val d = det(m)
        if (!(abs(d) > 1e-12)) return null
        return DoubleArray(3) { k ->
            val a = Array(3) { m[it].copyOf() }
            for (i in 0 until 3) a[i][k] = v[i]
            det(a) / d
        }
    }

    /** Algebraic least-squares circle (Kåsa), centered on the mean for stability. */
    fun circle(p: List<Pt>): Circle? {
        if (p.size < 3) return null
        val n = p.size.toDouble()
        var mx = 0.0
        var my = 0.0
        for (q in p) {
            mx += q.x
            my += q.y
        }
        mx /= n
        my /= n
        var sxx = 0.0
        var sxy = 0.0
        var syy = 0.0
        var sx = 0.0
        var sy = 0.0
        var sxz = 0.0
        var syz = 0.0
        var sz = 0.0
        for (q in p) {
            val x = q.x - mx
            val y = q.y - my
            val z = x * x + y * y
            sxx += x * x
            sxy += x * y
            syy += y * y
            sx += x
            sy += y
            sxz += x * z
            syz += y * z
            sz += z
        }
        val s = solve3(
            arrayOf(doubleArrayOf(sxx, sxy, sx), doubleArrayOf(sxy, syy, sy), doubleArrayOf(sx, sy, n)),
            doubleArrayOf(-sxz, -syz, -sz),
        ) ?: return null
        val cx = -s[0] / 2
        val cy = -s[1] / 2
        val r2 = cx * cx + cy * cy - s[2]
        if (!(r2 > 0)) return null
        val r = sqrt(r2)
        var e = 0.0
        for (q in p) {
            val d = hypot(q.x - mx - cx, q.y - my - cy) - r
            e += d * d
        }
        return Circle(Pt(cx + mx, cy + my), r, sqrt(e / n))
    }

    /** Axes from the point covariance; radii from the spread along each axis. */
    fun ellipse(p: List<Pt>): Ellipse? {
        if (p.size < 5) return null
        val n = p.size.toDouble()
        var mx = 0.0
        var my = 0.0
        for (q in p) {
            mx += q.x
            my += q.y
        }
        mx /= n
        my /= n
        var cxx = 0.0
        var cxy = 0.0
        var cyy = 0.0
        for (q in p) {
            val x = q.x - mx
            val y = q.y - my
            cxx += x * x
            cxy += x * y
            cyy += y * y
        }
        val angle = 0.5 * atan2(2 * cxy, cxx - cyy)
        val c = cos(angle)
        val s = sin(angle)
        var v1 = 0.0
        var v2 = 0.0
        for (q in p) {
            val x = q.x - mx
            val y = q.y - my
            val u = x * c + y * s
            val w = -x * s + y * c
            v1 += u * u
            v2 += w * w
        }
        val rx = sqrt(2 * v1 / n)
        val ry = sqrt(2 * v2 / n)
        if (!(rx > 1e-3 && ry > 1e-3)) return null
        var e = 0.0
        var ed = 0.0
        for (q in p) {
            val x = q.x - mx
            val y = q.y - my
            val u = x * c + y * s
            val w = -x * s + y * c
            val rho = hypot(u / rx, w / ry)
            val d = rho - 1
            e += d * d
            val distance = d * hypot(u, w) / max(rho, 1e-6)
            ed += distance * distance
        }
        return Ellipse(Pt(mx, my), rx, ry, angle, residual = sqrt(e / n), rms = sqrt(ed / n))
    }

    /**
     * Quadratic Bézier through the first and last point that follows `p` best (least squares). The
     * control point is solved for the points' curve parameters, which then move to the nearest
     * point of the curve (two Newton steps), 24 rounds. Returns the control point and the RMS
     * distance in points.
     */
    fun quadraticBezier(p: List<Pt>): Quadratic? {
        val n = p.size
        if (n < 3) return null
        val p0 = p[0]
        val p2 = p[n - 1]
        val ts = DoubleArray(n)
        var run = 0.0
        for (i in 1 until n) {
            run += Geo.dist(p[i - 1], p[i])
            ts[i] = run
        }
        if (!(run > 1e-6)) return null
        for (i in 0 until n) ts[i] /= run
        var cx = 0.0
        var cy = 0.0
        for (round in 0 until 24) {
            var nx = 0.0
            var ny = 0.0
            var den = 0.0
            for (i in 0 until n) {
                val t = ts[i]
                val u = 1 - t
                val w = 2 * t * u
                val rx = p[i].x - u * u * p0.x - t * t * p2.x
                val ry = p[i].y - u * u * p0.y - t * t * p2.y
                nx += w * rx
                ny += w * ry
                den += w * w
            }
            if (!(den > 1e-9)) return null
            cx = nx / den
            cy = ny / den
            val d2x = 2 * (p2.x - 2 * cx + p0.x)
            val d2y = 2 * (p2.y - 2 * cy + p0.y)
            for (i in 1 until n - 1) {
                var t = ts[i]
                for (step in 0 until 2) {
                    val u = 1 - t
                    val bx = u * u * p0.x + 2 * u * t * cx + t * t * p2.x
                    val by = u * u * p0.y + 2 * u * t * cy + t * t * p2.y
                    val d1x = 2 * u * (cx - p0.x) + 2 * t * (p2.x - cx)
                    val d1y = 2 * u * (cy - p0.y) + 2 * t * (p2.y - cy)
                    val ex = bx - p[i].x
                    val ey = by - p[i].y
                    val f1 = ex * d1x + ey * d1y
                    val f2 = d1x * d1x + d1y * d1y + ex * d2x + ey * d2y
                    if (f2 > 1e-9) t = min(max(t - f1 / f2, 0.0), 1.0)
                }
                ts[i] = t
            }
        }
        var e = 0.0
        for (i in 0 until n) {
            val t = ts[i]
            val u = 1 - t
            val dx = u * u * p0.x + 2 * u * t * cx + t * t * p2.x - p[i].x
            val dy = u * u * p0.y + 2 * u * t * cy + t * t * p2.y - p[i].y
            e += dx * dx + dy * dy
        }
        return Quadratic(Pt(cx, cy), sqrt(e / n.toDouble()))
    }
}
