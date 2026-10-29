package com.murekkep.notebook

import com.murekkep.notebook.ink.Brush
import com.murekkep.notebook.ink.InkPoint
import com.murekkep.notebook.ink.Stroke
import com.murekkep.notebook.ink.referenceNow
import com.murekkep.notebook.ui.EditorState
import kotlin.math.PI
import kotlin.math.sin

/**
 * The check of the Android edition on a build machine's emulator (Codemagic `android-check`): a
 * debuggable build started with `--es murekkep.demo pens` opens a notebook with a line of every
 * pen, so a screenshot shows the renderer, the shaders and the shadows. Never in a release build.
 */
object DemoInk {
    const val EXTRA = "murekkep.demo"

    /** Rows of waves, each in one pen at its default width and first color (page points, A4). */
    fun fill(state: EditorState) {
        val rows = listOf(
            listOf(Brush.PEN, Brush.PENCIL, Brush.FOUNTAIN),
            listOf(Brush.HIGHLIGHTER, Brush.CALLIGRAPHY, Brush.WATERCOLOR),
            listOf(Brush.GOLD, Brush.CHROME, Brush.PEARL),
            listOf(Brush.GALAXY, Brush.ICE, Brush.JELLY),
            listOf(Brush.LAVA, Brush.SEA, Brush.WAVE),
            listOf(Brush.NEON, Brush.RAINBOW, Brush.GLITTER),
            listOf(Brush.IMPASTO, Brush.WET, Brush.LIGHTNING),
        )
        // Dry and cool already, except the wet ink, which is drawn wet.
        val old = referenceNow() - 60.0
        for ((r, row) in rows.withIndex()) {
            for ((c, brush) in row.withIndex()) {
                val x0 = 50f + c * 170f
                val y0 = 110f + r * 100f
                val width = brush.defaultWidth.coerceAtMost(14f)
                val points = ArrayList<InkPoint>()
                var t = 0f
                while (t <= 150f) {
                    val y = y0 + 18f * sin(t / 150f * 2f * PI.toFloat() + r).toFloat()
                    val radius = width / 2f * (0.85f + 0.3f * sin(t / 37f).toFloat())
                    points.add(InkPoint(x0 + t, y, radius, 0.5f + 0.4f * sin(t / 23f).toFloat()))
                    t += 1.5f
                }
                val birth = if (brush == Brush.WET) referenceNow() else old
                state.addStroke(0, Stroke(brush, brush.palette.first(), width, birth, 0.37f + 0.1f * c, points, 1.2))
            }
        }
    }
}
