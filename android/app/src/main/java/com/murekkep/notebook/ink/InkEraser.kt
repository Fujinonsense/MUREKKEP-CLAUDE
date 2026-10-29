package com.murekkep.notebook.ink

import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

// Port of Murekkep.swiftpm/InkEraser.swift: which strokes an eraser step touches, and the pieces a
// stroke leaves when the partial eraser cuts it. Same numbers as the iPad.

enum class EraserMode(val titleTr: String, val titleEn: String) {
    STROKE("Tüm çizgi", "Whole stroke"),
    PARTIAL("Kısmi", "Partial"),
}

object InkEraser {
    /** vlength of the iPad: sqrt(x*x + y*y). */
    private fun length(x: Float, y: Float): Float = sqrt(x * x + y * y)

    /** Distance from point `p` to segment `a`-`b`. */
    fun distance(p: Vec2, a: Vec2, b: Vec2): Float = distance(p.x, p.y, a.x, a.y, b.x, b.y)

    private fun distance(px: Float, py: Float, ax: Float, ay: Float, bx: Float, by: Float): Float {
        val abx = bx - ax
        val aby = by - ay
        val l2 = abx * abx + aby * aby
        if (l2 <= 1e-10f) return length(px - ax, py - ay)
        val t = clampf(((px - ax) * abx + (py - ay) * aby) / l2, 0f, 1f)
        return length(px - (ax + abx * t), py - (ay + aby * t))
    }

    /** Minimum distance between segments p1-q1 and p2-q2. */
    fun distance(p1: Vec2, q1: Vec2, p2: Vec2, q2: Vec2): Float =
        distance(p1.x, p1.y, q1.x, q1.y, p2.x, p2.y, q2.x, q2.y)

    private fun distance(
        p1x: Float, p1y: Float, q1x: Float, q1y: Float,
        p2x: Float, p2y: Float, q2x: Float, q2y: Float,
    ): Float {
        val d1x = q1x - p1x
        val d1y = q1y - p1y
        val d2x = q2x - p2x
        val d2y = q2y - p2y
        val rx = p1x - p2x
        val ry = p1y - p2y
        val a = d1x * d1x + d1y * d1y
        val e = d2x * d2x + d2y * d2y
        val f = d2x * rx + d2y * ry
        val eps = 1e-10f
        var s = 0f
        var t = 0f
        if (a <= eps && e <= eps) {
            return length(p1x - p2x, p1y - p2y)
        }
        if (a <= eps) {
            t = clampf(f / e, 0f, 1f)
        } else {
            val c = d1x * rx + d1y * ry
            if (e <= eps) {
                s = clampf(-c / a, 0f, 1f)
            } else {
                val b = d1x * d2x + d1y * d2y
                val denom = a * e - b * b
                s = if (denom > eps) clampf((b * f - c * e) / denom, 0f, 1f) else 0f
                t = (b * s + f) / e
                if (t < 0f) {
                    t = 0f
                    s = clampf(-c / a, 0f, 1f)
                } else if (t > 1f) {
                    t = 1f
                    s = clampf((b - c) / a, 0f, 1f)
                }
            }
        }
        val c1x = p1x + d1x * s
        val c1y = p1y + d1y * s
        val c2x = p2x + d2x * t
        val c2y = p2y + d2y * t
        return length(c1x - c2x, c1y - c2y)
    }

    /** True when the eraser path `from`-`to` (with `radius`) touches the stroke. */
    fun hits(s: Stroke, from: Vec2, to: Vec2, radius: Float): Boolean {
        val box = InkRect.of(from, to).expanded(radius + s.maxRadius)
        if (!s.bounds.intersects(box)) return false
        val pts = s.points
        if (pts.isEmpty()) return false
        if (pts.size == 1) {
            val first = pts[0]
            return distance(first.x, first.y, from.x, from.y, to.x, to.y) <= radius + first.r
        }
        for (i in 0 until pts.size - 1) {
            val p = pts[i]
            val q = pts[i + 1]
            val d = distance(p.x, p.y, q.x, q.y, from.x, from.y, to.x, to.y)
            if (d <= radius + max(p.r, q.r) * 0.8f) return true
        }
        return false
    }

    /**
     * Removes the parts of the stroke under the eraser path. Returns null when the stroke is
     * untouched, otherwise the remaining pieces (possibly none).
     */
    fun erase(s: Stroke, from: Vec2, to: Vec2, radius: Float): List<Stroke>? {
        val box = InkRect.of(from, to).expanded(radius + s.maxRadius)
        if (!s.bounds.intersects(box)) return null
        val dense = densify(s.points, max(0.5f, radius * 0.35f))
        val pieces = ArrayList<List<InkPoint>>()
        var current = ArrayList<InkPoint>()
        var touched = false
        for (p in dense) {
            if (distance(p.x, p.y, from.x, from.y, to.x, to.y) <= radius + p.r * 0.5f) {
                touched = true
                if (current.size >= 2) pieces.add(current)
                current = ArrayList()
            } else {
                current.add(p)
            }
        }
        if (!touched) return null
        if (current.size >= 2) pieces.add(current)
        return pieces.map { s.withPoints(it) }
    }

    /** Fills in points so that no two neighbours are further apart than `maxSpacing`. */
    fun densify(pts: List<InkPoint>, maxSpacing: Float): List<InkPoint> {
        if (pts.size < 2 || maxSpacing <= 0f) return pts
        val out = ArrayList<InkPoint>(pts.size)
        for (i in 0 until pts.size - 1) {
            val p = pts[i]
            val q = pts[i + 1]
            out.add(p)
            val len = length(q.x - p.x, q.y - p.y)
            val n = min((len / maxSpacing).toInt(), 2000)
            if (n >= 1) {
                for (k in 1..n) {
                    val t = k.toFloat() / (n + 1).toFloat()
                    out.add(
                        InkPoint(
                            p.x + (q.x - p.x) * t,
                            p.y + (q.y - p.y) * t,
                            p.r + (q.r - p.r) * t,
                            p.ink + (q.ink - p.ink) * t,
                        ),
                    )
                }
            }
        }
        out.add(pts[pts.size - 1])
        return out
    }
}
