package com.murekkep.notebook.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.unit.dp
import com.murekkep.notebook.ink.Brush

// The pens of the black and white theme: flat silhouettes, as the approved mockup draws them (a
// thin outline barrel in paper, the tip that belongs to the pen's kind, a band in the ink's colour).
// Drawn in a 24 x 64 box, tip up, as the mockup's SVGs; the bodies run to the box's bottom edge and
// the bar cuts them there. The Pro themes draw the realistic bodies of ToolArt.kt instead.

object PenSilhouette {
    /** The drawing's box in dp. */
    val box = Size(24f, 64f)

    private const val LINE = 1.2f

    /** Draws [brush] (null is the eraser) filling the scope, one unit of the drawing per `size / box`. */
    fun draw(scope: DrawScope, brush: Brush?, ink: Color, z: ZenColors) = with(scope) {
        scale(size.width / box.width, size.height / box.height, pivot = Offset.Zero) {
            when {
                brush == null -> eraser(z)
                brush == Brush.PENCIL -> pencil(ink, z)
                else -> when (brush.nibStyle) {
                    NibStyle.CHISEL -> marker(ink, z)
                    NibStyle.FLAT -> nibPen(ink, z)
                    NibStyle.BRUSH -> paintBrush(ink, z)
                    NibStyle.LEAF -> grassBrush(ink, z)
                    NibStyle.CONE, NibStyle.ERASER -> pen(ink, z)
                }
            }
            if (brush != null && brush.isPremium) star(z)
        }
    }

    private val outline = Stroke(width = LINE, join = StrokeJoin.Round)

    private fun polygon(vararg pts: Float): Path = Path().apply {
        moveTo(pts[0], pts[1])
        var i = 2
        while (i < pts.size) {
            lineTo(pts[i], pts[i + 1])
            i += 2
        }
        close()
    }

    private fun rounded(x: Float, y: Float, w: Float, h: Float, r: Float): Path =
        Path().apply { addRoundRect(RoundRect(Rect(x, y, x + w, y + h), CornerRadius(r))) }

    private fun DrawScope.shape(path: Path, fill: Color, edge: Color?) {
        drawPath(path, fill)
        if (edge != null) drawPath(path, edge, style = outline)
    }

    /** The lower body: a stroked barrel in paper and the ink's band on it. */
    private fun DrawScope.barrel(ink: Color, z: ZenColors, top: Float, band: Float, radius: Float = 2f) {
        shape(rounded(6f, top, 12f, 64f - top, radius), z.paper, z.ink2)
        drawRect(ink, Offset(6.6f, band), Size(10.8f, 4f))
        // A dark ink on the dark barrel of the night look still reads as a band.
        drawRect(z.rule, Offset(6.6f, band), Size(10.8f, 4f), style = Stroke(width = 0.5f))
    }

    /** The plain pen, gel, neon and every other fine tip: a cone with the ink at its point. */
    private fun DrawScope.pen(ink: Color, z: ZenColors) {
        shape(polygon(6f, 20f, 12f, 5f, 18f, 20f), z.paper2, z.ink2)
        drawPath(polygon(10.7f, 8.4f, 12f, 4.8f, 13.3f, 8.4f), ink)
        barrel(ink, z, top = 20f, band = 27f)
    }

    /** A sharpened pencil: the wood cone, the lead in the ink, two facet lines down the body. */
    private fun DrawScope.pencil(ink: Color, z: ZenColors) {
        shape(polygon(6f, 20f, 12f, 4f, 18f, 20f), z.paper3, z.ink2)
        drawPath(polygon(10.2f, 8.8f, 12f, 4f, 13.8f, 8.8f), ink)
        shape(rounded(6f, 20f, 12f, 44f, 1f), z.paper, z.ink2)
        drawLine(z.rule, Offset(10f, 20f), Offset(10f, 64f), strokeWidth = 1f)
        drawLine(z.rule, Offset(14f, 20f), Offset(14f, 64f), strokeWidth = 1f)
        drawRect(ink, Offset(6.6f, 30f), Size(10.8f, 2.4f))
    }

    /** Fountain and calligraphy pens: a nib with its slit and breather hole. */
    private fun DrawScope.nibPen(ink: Color, z: ZenColors) {
        val nib = Path().apply {
            moveTo(7f, 21f)
            cubicTo(7f, 14f, 9.5f, 9f, 12f, 3f)
            cubicTo(14.5f, 9f, 17f, 14f, 17f, 21f)
            close()
        }
        shape(nib, z.paper3, z.ink2)
        drawLine(z.ink2, Offset(12f, 8f), Offset(12f, 15f), strokeWidth = 1f)
        drawCircle(z.ink2, radius = 1f, center = Offset(12f, 16f))
        barrel(ink, z, top = 21f, band = 27f)
    }

    /** Watercolor and the other wet brushes: a tuft loaded with the ink above a ferrule. */
    private fun DrawScope.paintBrush(ink: Color, z: ZenColors) {
        val tuft = Path().apply {
            moveTo(7.5f, 21f)
            cubicTo(7.5f, 14f, 9.5f, 9f, 12f, 3f)
            cubicTo(14.5f, 9f, 16.5f, 14f, 16.5f, 21f)
            close()
        }
        drawPath(tuft, ink)
        shape(rounded(6f, 21f, 12f, 6f, 0f), z.paper3, z.ink2)
        shape(rounded(6f, 27f, 12f, 37f, 2f), z.paper, z.ink2)
    }

    /** The grass brush: three blades standing out of the ferrule. */
    private fun DrawScope.grassBrush(ink: Color, z: ZenColors) {
        for ((base, tip) in listOf(9f to Offset(7f, 7f), 12f to Offset(12.5f, 3.5f), 15f to Offset(17f, 7f))) {
            val blade = Path().apply {
                moveTo(base - 1.5f, 21.5f)
                quadraticTo(base - 1f, 13f, tip.x, tip.y)
                quadraticTo(base + 1.4f, 13f, base + 1.5f, 21.5f)
                close()
            }
            drawPath(blade, ink)
        }
        shape(rounded(6f, 21f, 12f, 6f, 0f), z.paper3, z.ink2)
        shape(rounded(6f, 27f, 12f, 37f, 2f), z.paper, z.ink2)
    }

    /** A chunky marker: a slanted felt tip in the ink over a cap shoulder, a wider body. */
    private fun DrawScope.marker(ink: Color, z: ZenColors) {
        drawPath(polygon(8f, 14f, 8f, 8f, 16f, 4f, 16f, 14f), ink)
        shape(rounded(5f, 14f, 14f, 6f, 0f), z.paper3, z.ink2)
        shape(rounded(5f, 20f, 14f, 44f, 2f), z.paper, z.ink2)
        drawRect(ink, Offset(5.6f, 27f), Size(12.8f, 4f))
        drawRect(z.rule, Offset(5.6f, 27f), Size(12.8f, 4f), style = Stroke(width = 0.5f))
    }

    /** A block eraser standing in its sleeve. */
    private fun DrawScope.eraser(z: ZenColors) {
        shape(rounded(5f, 8f, 14f, 56f, 4f), z.paper, z.ink2)
        drawPath(rounded(5.6f, 8.6f, 12.8f, 12.8f, 3.5f), z.paper3)
        drawLine(z.ink2, Offset(5f, 22f), Offset(19f, 22f), strokeWidth = LINE)
    }

    /** The small star of the Pro pens, on the barrel under the band (as ToolArt sets it). */
    private fun DrawScope.star(z: ZenColors) {
        val pts = ToolArt.starPoints(Offset(12f, 40f), 2.6f)
        val path = Path().apply {
            pts.forEachIndexed { i, p -> if (i == 0) moveTo(p.x, p.y) else lineTo(p.x, p.y) }
            close()
        }
        drawPath(path, z.muted)
    }
}

/** One pen (null: the eraser) as its flat silhouette in its 24 x 64 dp box, or scaled by [scale]. */
@Composable
fun PenSilhouetteArt(brush: Brush?, ink: Color, modifier: Modifier = Modifier, scale: Float = 1f) {
    val z = Zen.colors
    Canvas(modifier.size((PenSilhouette.box.width * scale).dp, (PenSilhouette.box.height * scale).dp)) {
        PenSilhouette.draw(this, brush, ink, z)
    }
}
