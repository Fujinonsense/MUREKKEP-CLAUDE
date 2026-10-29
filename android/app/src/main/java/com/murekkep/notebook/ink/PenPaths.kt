package com.murekkep.notebook.ink

import kotlin.math.max
import kotlin.random.Random

// The iPad's StrokeText.strokes (Murekkep.swiftpm/StrokeFont.swift) for shapes: pen paths become
// strokes of a brush with an even line. Typed text (Lettering) comes with the text pen.

object PenPaths {
    /** One stroke per pen path. Straight pieces are filled in with points: the renderer draws a
     *  smooth curve through the points, and between far-apart corners that curve would bulge (an
     *  octagon became a circle). */
    fun strokes(paths: List<List<Vec2>>, brush: Brush, color: InkColor, width: Float, birth: Double): List<Stroke> {
        val r = max(width * 0.5f, 0.35f)
        val spacing = max(0.6f, r * 0.5f)
        return paths.mapNotNull { path ->
            if (path.isEmpty()) return@mapNotNull null
            val pts = ArrayList<InkPoint>(path.size * 4)
            for (i in path.indices) {
                val a = path[i]
                pts.add(InkPoint(a.x, a.y, r, 0.55f))
                if (i + 1 >= path.size) continue
                val b = path[i + 1]
                val n = ((b - a).length / spacing).toInt()
                for (k in 1 until n) {
                    val p = a + (b - a) * (k.toFloat() / n)
                    pts.add(InkPoint(p.x, p.y, r, 0.55f))
                }
            }
            // The canvas seeds every pen stroke this way (grass gets its flowers from it too).
            Stroke(brush, color, width, birth, Random.nextFloat(), pts)
        }
    }
}
