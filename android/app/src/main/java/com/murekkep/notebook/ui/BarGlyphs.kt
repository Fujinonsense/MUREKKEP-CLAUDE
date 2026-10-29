package com.murekkep.notebook.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.murekkep.notebook.ink.Brush
import com.murekkep.notebook.ink.ShapeKind
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin

// The pen bar's glyphs that the Material set has not: the iPad's SF Symbols for every pen
// (square.grid.3x3), the shapes (line.diagonal, arrow.up.right, rectangle, oval, hexagon...), the
// fold chevrons and the grip menu's edges, drawn in a 24-unit box with the symbols' medium weight.

/** A glyph drawn in a 24 x 24 box scaled to [size], its lines [weight] units wide. */
@Composable
private fun Glyph(size: Dp, modifier: Modifier, draw: DrawScope.(line: Stroke) -> Unit) {
    Canvas(modifier.size(size)) {
        scale(this.size.width / 24f, this.size.height / 24f, pivot = Offset.Zero) {
            draw(Stroke(width = 1.7f, cap = StrokeCap.Round, join = StrokeJoin.Round))
        }
    }
}

private fun path(vararg pts: Float, close: Boolean = false): Path = Path().apply {
    moveTo(pts[0], pts[1])
    var i = 2
    while (i < pts.size) {
        lineTo(pts[i], pts[i + 1])
        i += 2
    }
    if (close) close()
}

/** Every pen: nine small squares (square.grid.3x3). */
@Composable
fun AllPensGlyph(color: Color, size: Dp = 22.dp, modifier: Modifier = Modifier) = Glyph(size, modifier) {
    val cell = Stroke(width = 1.4f)
    for (row in 0 until 3) for (col in 0 until 3) {
        drawRoundRect(color, Offset(3f + col * 6.6f, 3f + row * 6.6f), Size(4.6f, 4.6f), CornerRadius(1.1f), style = cell)
    }
}

/** The shape in use, as the iPad's ShapeKind.symbol draws it. */
@Composable
fun ShapeGlyph(kind: ShapeKind, color: Color, size: Dp = 22.dp, modifier: Modifier = Modifier) = Glyph(size, modifier) { line ->
    when (kind) {
        ShapeKind.LINE -> drawLine(color, Offset(5f, 19f), Offset(19f, 5f), strokeWidth = line.width, cap = StrokeCap.Round)
        ShapeKind.ARROW -> {
            drawLine(color, Offset(6f, 18f), Offset(17.5f, 6.5f), strokeWidth = line.width, cap = StrokeCap.Round)
            drawPath(path(9.5f, 6f, 18f, 6f, 18f, 14.5f), color, style = line)
        }
        ShapeKind.DOUBLE_ARROW -> {
            drawLine(color, Offset(4f, 12f), Offset(20f, 12f), strokeWidth = line.width, cap = StrokeCap.Round)
            drawPath(path(8f, 8f, 4f, 12f, 8f, 16f), color, style = line)
            drawPath(path(16f, 8f, 20f, 12f, 16f, 16f), color, style = line)
        }
        ShapeKind.RECTANGLE -> drawRoundRect(color, Offset(3f, 6f), Size(18f, 12f), CornerRadius(1.5f), style = line)
        ShapeKind.ELLIPSE -> drawOval(color, Offset(3f, 6.5f), Size(18f, 11f), style = line)
        ShapeKind.CIRCLE -> drawCircle(color, radius = 8.5f, center = Offset(12f, 12f), style = line)
        ShapeKind.TRIANGLE -> drawPath(path(12f, 4f, 21f, 19.5f, 3f, 19.5f, close = true), color, style = line)
        ShapeKind.RIGHT_TRIANGLE -> drawPath(path(4f, 4f, 4f, 20f, 20f, 20f, close = true), color, style = line)
        ShapeKind.POLYGON -> {
            val corners = (0 until 6).flatMap { i ->
                val a = -PI / 2 + i * PI / 3
                listOf(12f + 9f * cos(a).toFloat(), 12f + 9f * sin(a).toFloat())
            }
            drawPath(path(*corners.toFloatArray(), close = true), color, style = line)
        }
    }
}

/** The shape tool in the folded bar: a square over a circle (square.on.circle). */
@Composable
fun ShapeToolGlyph(color: Color, size: Dp = 18.dp, modifier: Modifier = Modifier) = Glyph(size, modifier) { line ->
    drawCircle(color, radius = 6.5f, center = Offset(14.5f, 14.5f), style = line)
    drawRoundRect(color, Offset(3f, 3f), Size(11f, 11f), CornerRadius(1.5f), style = line)
}

/** Where a chevron points. */
enum class Chevron { UP, DOWN, LEFT, RIGHT }

/** A small bold chevron, the fold and unfold of the bar. */
@Composable
fun ChevronGlyph(direction: Chevron, color: Color, size: Dp = 12.dp, modifier: Modifier = Modifier) = Glyph(size, modifier) {
    val bold = Stroke(width = 3f, cap = StrokeCap.Round, join = StrokeJoin.Round)
    val turn = when (direction) {
        Chevron.DOWN -> 0f
        Chevron.LEFT -> 90f
        Chevron.UP -> 180f
        Chevron.RIGHT -> 270f
    }
    rotate(turn, pivot = Offset(12f, 12f)) { drawPath(path(5f, 8.5f, 12f, 15.5f, 19f, 8.5f), color, style = bold) }
}

/** The grip menu's place: a frame with its top, bottom or right third filled. */
@Composable
fun EdgeGlyph(edge: PaletteEdge, color: Color, size: Dp = 20.dp, modifier: Modifier = Modifier) = Glyph(size, modifier) {
    drawRoundRect(color, Offset(2.5f, 4.5f), Size(19f, 15f), CornerRadius(3f), style = Stroke(width = 1.5f))
    when (edge) {
        PaletteEdge.TOP -> drawRoundRect(color, Offset(5f, 7f), Size(14f, 3.5f), CornerRadius(1f))
        PaletteEdge.BOTTOM -> drawRoundRect(color, Offset(5f, 13.5f), Size(14f, 3.5f), CornerRadius(1f))
        PaletteEdge.TRAILING -> drawRoundRect(color, Offset(14.5f, 7f), Size(4.5f, 10f), CornerRadius(1f))
    }
}

/** A pen (null: the eraser) laid at an angle in a small square: the folded bar's tool in black and
 *  white, as ToolIcon lays the realistic body in a Pro theme. */
@Composable
fun PenIcon(brush: Brush?, ink: Color, side: Dp = 30.dp, modifier: Modifier = Modifier) {
    val z = Zen.colors
    Canvas(modifier.size(side)) {
        val k = size.height / PenSilhouette.box.height * 1.02f
        val w = PenSilhouette.box.width * k
        val h = PenSilhouette.box.height * k
        rotate(40f) {
            translate((size.width - w) / 2f, (size.height - h) / 2f) {
                scale(k, k, pivot = Offset.Zero) { PenSilhouette.drawUnits(this, brush, ink, selected = true, z = z) }
            }
        }
    }
}
