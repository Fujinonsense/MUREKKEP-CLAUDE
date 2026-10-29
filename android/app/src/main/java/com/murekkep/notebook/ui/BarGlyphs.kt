package com.murekkep.notebook.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.AcUnit
import androidx.compose.material.icons.outlined.AutoAwesome
import androidx.compose.material.icons.outlined.Bolt
import androidx.compose.material.icons.outlined.BorderColor
import androidx.compose.material.icons.outlined.Brush as BrushIcon
import androidx.compose.material.icons.outlined.BubbleChart
import androidx.compose.material.icons.outlined.Contrast
import androidx.compose.material.icons.outlined.Create
import androidx.compose.material.icons.outlined.Draw
import androidx.compose.material.icons.outlined.EditNote
import androidx.compose.material.icons.outlined.FormatPaint
import androidx.compose.material.icons.outlined.Grass
import androidx.compose.material.icons.outlined.InvertColors
import androidx.compose.material.icons.outlined.Lightbulb
import androidx.compose.material.icons.outlined.LocalFireDepartment
import androidx.compose.material.icons.outlined.LocalFlorist
import androidx.compose.material.icons.outlined.Looks
import androidx.compose.material.icons.outlined.NightsStay
import androidx.compose.material.icons.outlined.Opacity
import androidx.compose.material.icons.outlined.Palette
import androidx.compose.material.icons.outlined.WaterDrop
import androidx.compose.material.icons.outlined.Waves
import androidx.compose.material.icons.outlined.WorkspacePremium
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.path
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.murekkep.notebook.ink.Brush
import com.murekkep.notebook.ink.ShapeKind
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin

// The pen bar's glyphs that the Material set has not: the iPad's SF Symbols for every pen
// (square.grid.3x3), the shapes (line.diagonal, arrow.up.right, rectangle, oval, hexagon...), the
// fold chevrons, the grip menu's edges and the eraser, drawn in a 24-unit box with the symbols'
// medium weight; and each pen's symbol (Brush.symbol on iPad) as its Material Symbols twin.

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

/** A pen's symbol (Brush.symbol on iPad, an SF Symbol) as its Material Symbols twin: the folded
 *  bar shows the tool in hand so in black and white (the iPad's compactSymbol). */
val Brush.symbol: ImageVector
    get() = when (this) {
        Brush.PEN -> Icons.Outlined.Draw // pencil.tip
        Brush.WET -> Icons.Outlined.WaterDrop // drop.fill
        Brush.WAVE -> Icons.Outlined.Opacity // drop.circle.fill
        Brush.HIGHLIGHTER -> Icons.Outlined.BorderColor // highlighter
        Brush.PENCIL -> Icons.Outlined.Create // pencil
        Brush.CALLIGRAPHY -> Icons.Outlined.BrushIcon // paintbrush.pointed.fill
        Brush.WATERCOLOR -> Icons.Outlined.FormatPaint // paintbrush.fill
        Brush.NEON -> Icons.Outlined.Lightbulb // lightbulb.fill
        Brush.RAINBOW -> Icons.Outlined.Looks // rainbow
        Brush.GLITTER -> Icons.Outlined.AutoAwesome // sparkles
        Brush.GRASS -> Icons.Outlined.Grass // camera.macro
        Brush.SEA -> Icons.Outlined.Waves // water.waves
        Brush.LAVA -> Icons.Outlined.LocalFireDepartment // flame.fill
        Brush.FOUNTAIN -> Icons.Outlined.EditNote // pencil.and.outline
        Brush.GOLD -> Icons.Outlined.WorkspacePremium // crown.fill
        Brush.CHROME -> Icons.Outlined.Contrast // circle.lefthalf.filled
        Brush.ICE -> Icons.Outlined.AcUnit // snowflake
        Brush.JELLY -> Icons.Outlined.InvertColors // drop.halffull
        Brush.GALAXY -> Icons.Outlined.NightsStay // moon.stars.fill
        Brush.LIGHTNING -> Icons.Outlined.Bolt // bolt.fill
        Brush.PEARL -> Icons.Outlined.BubbleChart // circle.grid.2x1.fill
        Brush.IMPASTO -> Icons.Outlined.Palette // paintpalette.fill
        Brush.BLOOM -> Icons.Outlined.LocalFlorist // camera.macro.circle.fill
    }

/** The iPad's eraser symbol, which the Material set has not: a block of rubber at a slant, its
 *  sleeve's edge across it, the line it rubs out under it. */
val EraserGlyph: ImageVector by lazy {
    ImageVector.Builder("Eraser", 24.dp, 24.dp, 24f, 24f).path(
        stroke = SolidColor(Color.Black),
        strokeLineWidth = 1.7f,
        strokeLineCap = StrokeCap.Round,
        strokeLineJoin = StrokeJoin.Round,
    ) {
        moveTo(14.5f, 3.5f)
        lineTo(20.5f, 9.5f)
        lineTo(10.5f, 19.5f)
        lineTo(4.5f, 13.5f)
        close()
        moveTo(8.5f, 9.5f)
        lineTo(14.5f, 15.5f)
        moveTo(13f, 20.5f)
        lineTo(20f, 20.5f)
    }.build()
}

/** The folded bar's tool in black and white: [symbol] 18 dp in ink-2 in a 30 dp square. */
@Composable
fun CompactSymbol(symbol: ImageVector, modifier: Modifier = Modifier) {
    Box(modifier.size(30.dp), contentAlignment = Alignment.Center) {
        Icon(symbol, contentDescription = null, tint = Zen.colors.ink2, modifier = Modifier.size(18.dp))
    }
}
