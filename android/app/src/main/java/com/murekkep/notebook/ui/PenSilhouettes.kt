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

// The pens of the black and white theme: flat silhouettes, as the iPad draws them
// (Murekkep.swiftpm/ToolPalette.swift, PenSilhouette): a thin outline barrel in paper with the ink's
// colour as a band and at the point; the pen in hand carries its whole tip in the ink. Drawn in a
// 24 x 64 box, tip up, as the mockup's SVGs; the bodies run to the box's bottom edge and the bar cuts
// them there. The Pro themes draw the realistic bodies of ToolArt.kt instead.

object PenSilhouette {
    /** The drawing's box in dp. */
    val box = Size(24f, 64f)

    private const val LINE = 1.2f

    /** Draws [brush] (null is the eraser) filling the scope, one unit of the drawing per `size / box`;
     *  [selected] is the pen in hand. */
    fun draw(scope: DrawScope, brush: Brush?, ink: Color, selected: Boolean, z: ZenColors) = with(scope) {
        scale(size.width / box.width, size.height / box.height, pivot = Offset.Zero) {
            drawUnits(this, brush, ink, selected, z)
        }
    }

    /** Draws in the box's own units (one per dp of the 24 x 64 box), whatever the scope's size. */
    fun drawUnits(scope: DrawScope, brush: Brush?, ink: Color, selected: Boolean, z: ZenColors) = with(scope) {
        when {
            brush == null -> eraser(z)
            brush == Brush.PENCIL -> pencil(ink, z)
            else -> when (brush.nibStyle) {
                NibStyle.CHISEL -> highlighter(ink, z)
                NibStyle.FLAT -> nibPen(ink, selected, z)
                NibStyle.BRUSH, NibStyle.LEAF -> paintBrush(ink, z)
                NibStyle.CONE, NibStyle.ERASER -> pen(ink, selected, z)
            }
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

    /** The outlined barrel from [top] to the bottom of the box, with the ink's band 7 below its top. */
    private fun DrawScope.barrel(ink: Color, z: ZenColors, top: Float, band: Boolean = true, radius: Float = 2f) {
        shape(rounded(6f, top, 12f, 64f - top, radius), z.paper, z.ink2)
        if (band) drawRect(ink, Offset(6.6f, top + 7f), Size(10.8f, 4f))
    }

    /** The plain pen, gel, neon and every other fine tip: a cone with the ink at its point. */
    private fun DrawScope.pen(ink: Color, selected: Boolean, z: ZenColors) {
        shape(polygon(6f, 20f, 12f, 5f, 18f, 20f), if (selected) ink else z.paper2, z.ink2)
        if (!selected) drawPath(polygon(10.7f, 8.4f, 12f, 4.8f, 13.3f, 8.4f), ink)
        barrel(ink, z, top = 20f)
    }

    /** A sharpened pencil: the wood, the lead in the ink, two facet lines down the barrel. */
    private fun DrawScope.pencil(ink: Color, z: ZenColors) {
        shape(polygon(6f, 20f, 12f, 4f, 18f, 20f), z.paper3, z.ink2)
        drawPath(polygon(10.2f, 8.8f, 12f, 4f, 13.8f, 8.8f), ink)
        barrel(ink, z, top = 20f, band = false, radius = 1f)
        drawLine(z.rule, Offset(10f, 20f), Offset(10f, 64f), strokeWidth = 1f)
        drawLine(z.rule, Offset(14f, 20f), Offset(14f, 64f), strokeWidth = 1f)
    }

    /** Fountain and calligraphy pens: a nib with its slit and breather hole. */
    private fun DrawScope.nibPen(ink: Color, selected: Boolean, z: ZenColors) {
        val nib = Path().apply {
            moveTo(7f, 21f)
            cubicTo(7f, 14f, 9.5f, 9f, 12f, 3f)
            cubicTo(14.5f, 9f, 17f, 14f, 17f, 21f)
            close()
        }
        shape(nib, if (selected) ink else z.paper3, z.ink2)
        if (!selected) {
            drawLine(z.ink2, Offset(12f, 8f), Offset(12f, 15f), strokeWidth = 1f)
            drawCircle(z.ink2, radius = 1f, center = Offset(12f, 16f))
        }
        barrel(ink, z, top = 21f)
    }

    /** A marker: a wider body and a slanted felt tip in the ink. */
    private fun DrawScope.highlighter(ink: Color, z: ZenColors) {
        shape(rounded(5f, 18f, 14f, 46f, 2f), z.paper, z.ink2)
        drawRect(ink, Offset(5.6f, 26f), Size(12.8f, 4f))
        shape(polygon(8f, 18f, 8f, 8f, 16f, 4f, 16f, 18f), ink, z.ink2)
    }

    /** Watercolour, the wet brushes and the grass: a tuft loaded with the ink above a ferrule. */
    private fun DrawScope.paintBrush(ink: Color, z: ZenColors) {
        val tuft = Path().apply {
            moveTo(8f, 20f)
            cubicTo(7f, 12f, 10f, 7f, 12f, 2f)
            cubicTo(14f, 7f, 17f, 12f, 16f, 20f)
            close()
        }
        shape(tuft, ink, z.ink2)
        shape(rounded(7f, 17f, 10f, 5f, 0f), z.paper3, z.ink2)
        barrel(ink, z, top = 22f)
    }

    /** A block eraser standing in its sleeve. */
    private fun DrawScope.eraser(z: ZenColors) {
        shape(rounded(5f, 8f, 14f, 56f, 4f), z.paper, z.ink2)
        drawPath(rounded(5.6f, 8.6f, 12.8f, 12.8f, 3.5f), z.paper3)
        drawLine(z.ink2, Offset(5f, 22f), Offset(19f, 22f), strokeWidth = LINE)
    }
}

/** One pen (null: the eraser) as its flat silhouette in its 24 x 64 dp box, or scaled by [scale];
 *  [selected] fills the tip of the pen in hand with its ink. */
@Composable
fun PenSilhouetteArt(brush: Brush?, ink: Color, selected: Boolean, modifier: Modifier = Modifier, scale: Float = 1f) {
    val z = Zen.colors
    Canvas(modifier.size((PenSilhouette.box.width * scale).dp, (PenSilhouette.box.height * scale).dp)) {
        PenSilhouette.draw(this, brush, ink, selected, z)
    }
}
