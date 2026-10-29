package com.murekkep.notebook.ui

import android.graphics.Bitmap
import android.graphics.BlurMaskFilter
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.wrapContentHeight
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.CanvasDrawScope
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.graphics.drawscope.inset
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import com.murekkep.notebook.ink.Brush
import kotlin.math.PI
import kotlin.math.ceil
import kotlin.math.cos
import kotlin.math.pow
import kotlin.math.sin
import androidx.compose.ui.graphics.Brush as Shading
import androidx.compose.ui.graphics.Canvas as ImageCanvas

// The pens of the palette drawn like real objects (Murekkep.swiftpm/ToolPalette.swift: NibStyle, the
// Brush extension, ToolArt, ToolArtwork, ToolIcon, PenBodyView), the same shapes, numbers, colors and
// gradients as the iPad's so the two apps show the same pen bar. The iPad draws in a SwiftUI Canvas in
// a 30 x 68 point box, tip up, and cuts the bodies at the box's bottom edge; here the box is 30 x 68 dp
// and ToolArt.draw scales a DrawScope so one unit of the drawing is one dp. The only thing Compose
// cannot do the iPad's way is the view shadow (a blurred copy of the pen's silhouette): the hardware
// canvas has no blur below Android 12, so the shadow is rendered once per pen in software and drawn as
// a bitmap under the pen.

/** The shape of a pen's working end; it picks which body ToolArt draws. */
enum class NibStyle { CONE, CHISEL, FLAT, BRUSH, LEAF, ERASER }

val Brush.nibStyle: NibStyle
    get() = when (this) {
        Brush.HIGHLIGHTER -> NibStyle.CHISEL
        Brush.CALLIGRAPHY, Brush.FOUNTAIN -> NibStyle.FLAT
        Brush.WATERCOLOR, Brush.WAVE, Brush.SEA, Brush.IMPASTO, Brush.BLOOM -> NibStyle.BRUSH
        Brush.GRASS -> NibStyle.LEAF
        else -> NibStyle.CONE
    }

/** Colors of the pen barrel, left to right (gives a cylindrical look). */
fun Brush.barrel(ink: Color): List<Color> = when (this) {
    Brush.PEN -> listOf(grey(0.97f), grey(0.84f))
    Brush.PENCIL -> listOf(rgb(1.0f, 0.84f, 0.32f), rgb(0.90f, 0.66f, 0.16f))
    Brush.CALLIGRAPHY -> listOf(grey(0.24f), grey(0.06f))
    Brush.HIGHLIGHTER -> listOf(ink.opacity(0.75f), ink)
    Brush.WET -> listOf(rgb(0.20f, 0.27f, 0.52f), rgb(0.08f, 0.12f, 0.30f))
    Brush.WATERCOLOR -> listOf(rgb(0.78f, 0.58f, 0.38f), rgb(0.55f, 0.36f, 0.20f))
    Brush.NEON -> listOf(grey(0.26f), grey(0.10f))
    Brush.RAINBOW -> listOf(SystemRed, SystemOrange, SystemYellow, SystemGreen, SystemBlue, SystemPurple)
    Brush.GLITTER -> listOf(grey(0.92f), grey(0.62f), grey(0.88f))
    Brush.WAVE -> listOf(rgb(0.38f, 0.80f, 0.90f), rgb(0.06f, 0.48f, 0.70f))
    Brush.GRASS -> listOf(rgb(0.48f, 0.78f, 0.36f), rgb(0.20f, 0.52f, 0.20f))
    Brush.SEA -> listOf(rgb(0.25f, 0.62f, 0.90f), rgb(0.04f, 0.28f, 0.58f))
    Brush.LAVA -> listOf(rgb(0.30f, 0.13f, 0.08f), rgb(0.08f, 0.04f, 0.03f))
    Brush.FOUNTAIN -> listOf(rgb(0.14f, 0.16f, 0.26f), rgb(0.03f, 0.04f, 0.09f))
    Brush.GOLD -> listOf(rgb(1.0f, 0.90f, 0.55f), rgb(0.72f, 0.52f, 0.16f))
    Brush.CHROME -> listOf(grey(0.96f), grey(0.52f), grey(0.90f))
    Brush.ICE -> listOf(rgb(0.86f, 0.97f, 1.0f), rgb(0.55f, 0.80f, 0.92f))
    Brush.JELLY -> listOf(ink.opacity(0.55f), ink)
    Brush.GALAXY -> listOf(rgb(0.22f, 0.11f, 0.42f), rgb(0.03f, 0.02f, 0.10f))
    Brush.LIGHTNING -> listOf(grey(0.22f), grey(0.05f))
    Brush.PEARL -> listOf(grey(0.99f), rgb(0.90f, 0.86f, 0.82f))
    Brush.IMPASTO -> listOf(rgb(0.82f, 0.62f, 0.42f), rgb(0.55f, 0.36f, 0.20f))
    Brush.BLOOM -> listOf(rgb(0.62f, 0.90f, 0.96f), rgb(0.12f, 0.56f, 0.72f))
}

/** Metal of the grip ring and trim. */
val Brush.trimIsGold: Boolean
    get() = this == Brush.FOUNTAIN || this == Brush.GOLD || this == Brush.GALAXY || this == Brush.LAVA || this == Brush.PEARL

// SwiftUI's `.red`, `.orange`... are the system colors (light appearance); the rainbow barrel is made of them.
private val SystemRed = Color(0xFFFF3B30)
private val SystemOrange = Color(0xFFFF9500)
private val SystemYellow = Color(0xFFFFCC00)
private val SystemGreen = Color(0xFF34C759)
private val SystemBlue = Color(0xFF007AFF)
private val SystemPurple = Color(0xFFAF52DE)

private fun grey(white: Float) = Color(white, white, white)

private fun rgb(red: Float, green: Float, blue: Float) = Color(red, green, blue)

/** SwiftUI's `Color.opacity`: scales the color's own alpha. */
private fun Color.opacity(fraction: Float) = copy(alpha = alpha * fraction)

/**
 * Draws the tools of the palette like real objects: a turned barrel lit from the left, a metal
 * grip ring, the tip that belongs to the ink and a band in the current ink color. The eraser is a
 * block eraser in its paper sleeve. Drawn in a 30 x 68 box, tip up; the bodies run on to y = 80 and
 * are cut at the box's bottom edge, as the iPad's Canvas cuts them.
 */
object ToolArt {
    /** The drawing's box: the iPad's points, dp here. */
    val box = Size(30f, 68f)

    /** Draws [brush] (null is the eraser) filling the scope, one unit of the drawing per `size / box`. */
    fun draw(scope: DrawScope, brush: Brush?, ink: Color) = with(scope) {
        clipRect(0f, 0f, size.width, size.height) {
            scale(size.width / box.width, size.height / box.height, pivot = Offset.Zero) {
                when {
                    brush == null -> eraser()
                    brush == Brush.PENCIL -> pencil(ink)
                    else -> when (brush.nibStyle) {
                        NibStyle.CHISEL -> highlighter(brush, ink)
                        NibStyle.FLAT -> nibPen(brush, ink)
                        NibStyle.BRUSH -> paintBrush(brush, ink)
                        NibStyle.LEAF -> grassBrush(brush, ink)
                        NibStyle.CONE, NibStyle.ERASER -> fineliner(brush, ink)
                    }
                }
            }
        }
    }

    // MARK: Light

    private fun across(minX: Float, maxX: Float) = Offset(minX, 0f) to Offset(maxX, 0f)

    /** The light on a round body: a dark left edge, the soft highlight at a third, the shadowed right edge. */
    internal fun glossStops(gloss: Float): List<Pair<Float, Color>> = listOf(
        0f to Color.Black.copy(alpha = 0.22f),
        0.12f to Color.White.copy(alpha = 0f),
        0.30f to Color.White.copy(alpha = gloss),
        0.50f to Color.White.copy(alpha = 0f),
        0.68f to Color.Black.copy(alpha = 0f),
        1f to Color.Black.copy(alpha = 0.32f),
    )

    /** Base colors plus the soft highlight and the shadowed edge of a round body. */
    private fun DrawScope.cylinder(path: Path, minX: Float, maxX: Float, colors: List<Color>, gloss: Float = 0.55f) {
        val (a, b) = across(minX, maxX)
        drawPath(path, Shading.linearGradient(colors, start = a, end = b))
        drawPath(path, Shading.linearGradient(*glossStops(gloss).toTypedArray(), start = a, end = b))
    }

    /** Five bands of a turned metal ring: dark, bright, mid, dark, bright. */
    internal fun metal(gold: Boolean): List<Color> = if (gold) {
        listOf(rgb(0.62f, 0.44f, 0.12f), rgb(1.0f, 0.94f, 0.68f), rgb(0.86f, 0.66f, 0.24f), rgb(0.52f, 0.35f, 0.08f), rgb(0.92f, 0.76f, 0.38f))
    } else {
        listOf(grey(0.48f), grey(0.97f), grey(0.72f), grey(0.40f), grey(0.80f))
    }

    private fun DrawScope.metalBand(path: Path, minX: Float, maxX: Float, gold: Boolean) {
        val (a, b) = across(minX, maxX)
        drawPath(path, Shading.linearGradient(metal(gold), start = a, end = b))
    }

    private fun DrawScope.line(x0: Float, y0: Float, x1: Float, y1: Float, color: Color, width: Float) {
        drawLine(color, Offset(x0, y0), Offset(x1, y1), strokeWidth = width)
    }

    /** The corners of a trapezoid standing on [bottom], narrowing to [top], centered on [cx]. */
    internal fun trapezoidCorners(top: Float, topHalf: Float, bottom: Float, bottomHalf: Float, cx: Float = 15f): List<Offset> =
        listOf(Offset(cx - bottomHalf, bottom), Offset(cx - topHalf, top), Offset(cx + topHalf, top), Offset(cx + bottomHalf, bottom))

    private fun trapezoid(top: Float, topHalf: Float, bottom: Float, bottomHalf: Float, cx: Float = 15f): Path =
        polygon(trapezoidCorners(top, topHalf, bottom, bottomHalf, cx))

    private fun polygon(points: List<Offset>): Path = Path().apply {
        points.forEachIndexed { i, p -> if (i == 0) moveTo(p.x, p.y) else lineTo(p.x, p.y) }
        close()
    }

    private fun rect(x: Float, y: Float, width: Float, height: Float): Path =
        Path().apply { addRect(Rect(x, y, x + width, y + height)) }

    private fun roundedRect(x: Float, y: Float, width: Float, height: Float, radius: Float): Path =
        Path().apply { addRoundRect(RoundRect(Rect(x, y, x + width, y + height), CornerRadius(radius))) }

    private fun ellipse(rect: Rect): Path = Path().apply { addOval(rect) }

    /** Lower body with an ink-colored band, shared by most tools. */
    private fun DrawScope.barrel(brush: Brush, ink: Color, top: Float, minX: Float = 4f, maxX: Float = 26f, band: Float? = null) {
        val body = roundedRect(minX, top, maxX - minX, 80f - top, 2.5f)
        cylinder(body, minX, maxX, brush.barrel(ink))
        val y = band ?: (top + 5f)
        val ring = rect(minX, y, maxX - minX, 3.6f)
        cylinder(ring, minX, maxX, listOf(ink, ink), gloss = 0.4f)
        if (brush.isPremium) star(Offset((minX + maxX) / 2f, y + 13f), 2.6f)
    }

    /** A five-pointed star's outline, the first point straight up, the inner points at 0.45 of the radius. */
    internal fun starPoints(center: Offset, radius: Float): List<Offset> = (0 until 10).map { i ->
        val a = -PI.toFloat() / 2f + i * PI.toFloat() / 5f
        val rr = if (i % 2 == 0) radius else radius * 0.45f
        Offset(center.x + cos(a) * rr, center.y + sin(a) * rr)
    }

    /** The gold star of the Pro pens. */
    private fun DrawScope.star(center: Offset, radius: Float) {
        val shine = Shading.linearGradient(metal(true), start = Offset(center.x - radius, center.y), end = Offset(center.x + radius, center.y))
        drawPath(polygon(starPoints(center, radius)), shine)
    }

    // MARK: Tools

    /** Pen, gel, neon, metallic and the other fine tips: barrel, grip ring, cone, metal sleeve, ink point. */
    private fun DrawScope.fineliner(brush: Brush, ink: Color) {
        barrel(brush, ink, top = 32f)
        val grip = trapezoid(top = 24f, topHalf = 8f, bottom = 32.5f, bottomHalf = 10.2f)
        metalBand(grip, 4.8f, 25.2f, gold = brush.trimIsGold)
        line(6f, 27.2f, 24f, 27.2f, Color.Black.copy(alpha = 0.22f), 0.5f)
        line(5.5f, 30f, 24.5f, 30f, Color.Black.copy(alpha = 0.22f), 0.5f)
        val cone = trapezoid(top = 9f, topHalf = 2.5f, bottom = 24.2f, bottomHalf = 8f)
        cylinder(cone, 7f, 23f, brush.barrel(ink))
        val sleeve = trapezoid(top = 4f, topHalf = 1.2f, bottom = 9.2f, bottomHalf = 2.5f)
        metalBand(sleeve, 12.5f, 17.5f, gold = false)
        drawPath(roundedRect(14.15f, 0.9f, 1.7f, 3.4f, 0.85f), ink)
    }

    /** A sharpened hexagonal pencil: painted facets, scalloped paint edge, wood cone, lead in the ink color. */
    private fun DrawScope.pencil(ink: Color) {
        val wood = trapezoid(top = 10f, topHalf = 3.6f, bottom = 33f, bottomHalf = 11f)
        val (wa, wb) = across(4f, 26f)
        val grain = listOf(rgb(0.80f, 0.62f, 0.42f), rgb(0.98f, 0.86f, 0.68f), rgb(0.74f, 0.55f, 0.36f))
        drawPath(wood, Shading.linearGradient(grain, start = wa, end = wb))
        val lead = Path().apply {
            moveTo(11.4f, 10.2f)
            lineTo(14.6f, 1.6f)
            quadraticTo(15f, 0.9f, 15.4f, 1.6f)
            lineTo(18.6f, 10.2f)
            close()
        }
        cylinder(lead, 11.4f, 18.6f, listOf(ink, ink), gloss = 0.35f)
        val paint = Path().apply {
            moveTo(4f, 80f)
            lineTo(4f, 33f)
            quadraticTo(7.67f, 28.5f, 11.33f, 33f)
            quadraticTo(15f, 28.5f, 18.67f, 33f)
            quadraticTo(22.33f, 28.5f, 26f, 33f)
            lineTo(26f, 80f)
            close()
        }
        val yellowDark = rgb(0.90f, 0.66f, 0.12f)
        val yellow = rgb(1.0f, 0.84f, 0.30f)
        val yellowLight = rgb(1.0f, 0.93f, 0.56f)
        // Three facets: the hard steps at 0.33 and 0.66 are the pencil's edges.
        drawPath(
            paint,
            Shading.linearGradient(
                0f to yellow, 0.33f to yellowLight,
                0.335f to yellow, 0.66f to yellow,
                0.665f to yellowDark, 1f to rgb(0.78f, 0.54f, 0.08f),
                start = wa, end = wb,
            ),
        )
        line(11.33f, 32f, 11.33f, 80f, Color.Black.copy(alpha = 0.10f), 0.5f)
        line(18.67f, 32f, 18.67f, 80f, Color.Black.copy(alpha = 0.14f), 0.5f)
        val stripe = rect(4f, 42f, 22f, 2.4f)
        cylinder(stripe, 4f, 26f, listOf(ink, ink), gloss = 0.3f)
    }

    /** A chunky marker with a cap shoulder and a slanted felt tip. */
    private fun DrawScope.highlighter(brush: Brush, ink: Color) {
        barrel(brush, ink, top = 30f, minX = 3f, maxX = 27f, band = 40f)
        val shoulder = trapezoid(top = 20f, topHalf = 8f, bottom = 30.5f, bottomHalf = 12f)
        cylinder(shoulder, 3f, 27f, listOf(grey(0.30f), grey(0.12f)), gloss = 0.35f)
        val collar = rect(8.5f, 18.6f, 13f, 1.8f)
        metalBand(collar, 8.5f, 21.5f, gold = false)
        val felt = polygon(listOf(Offset(9.6f, 18.8f), Offset(9.6f, 5.6f), Offset(20.4f, 1.8f), Offset(20.4f, 18.8f)))
        cylinder(felt, 9.6f, 20.4f, listOf(ink, ink), gloss = 0.3f)
        line(9.6f, 5.6f, 20.4f, 1.8f, Color.White.copy(alpha = 0.55f), 0.6f)
    }

    /** The ink on the nib's point: a dot on the fountain pen, the whole broad edge on the calligraphy nib. */
    internal fun nibTip(broad: Boolean): Rect {
        val tipY = if (broad) 2.6f else 1.0f
        val tipW = if (broad) 7.2f else 1.8f
        return Rect(15f - tipW / 2f, tipY, 15f + tipW / 2f, tipY + 1.3f)
    }

    /** Fountain and calligraphy pens: resin body, trim ring, grip and a metal nib with slit and breather hole. */
    private fun DrawScope.nibPen(brush: Brush, ink: Color) {
        val gold = brush.trimIsGold
        barrel(brush, ink, top = 34f, minX = 4.5f, maxX = 25.5f, band = 46f)
        val trim = rect(4.5f, 34f, 21f, 2f)
        metalBand(trim, 4.5f, 25.5f, gold)
        val grip = trapezoid(top = 21.5f, topHalf = 5.6f, bottom = 34.2f, bottomHalf = 9f)
        cylinder(grip, 6f, 24f, brush.barrel(ink), gloss = 0.45f)
        val broad = brush == Brush.CALLIGRAPHY
        val nib = Path().apply {
            moveTo(9.6f, 22.5f)
            if (broad) {
                quadraticTo(9.4f, 10f, 11.4f, 3.2f)
                lineTo(18.6f, 3.2f)
                quadraticTo(20.6f, 10f, 20.4f, 22.5f)
            } else {
                quadraticTo(9.0f, 8.5f, 15f, 1.4f)
                quadraticTo(21.0f, 8.5f, 20.4f, 22.5f)
            }
            close()
        }
        metalBand(nib, 9.6f, 20.4f, gold)
        drawPath(nib, Color.Black.copy(alpha = 0.25f), style = Stroke(width = 0.4f))
        line(15f, 13.6f, 15f, if (broad) 3.2f else 2.2f, Color.Black.copy(alpha = 0.55f), 0.55f)
        drawPath(ellipse(Rect(13.8f, 12.6f, 16.2f, 15f)), Color.Black.copy(alpha = 0.6f))
        val engraving = Path().apply {
            moveTo(11.2f, 19.5f)
            quadraticTo(15f, 16.5f, 18.8f, 19.5f)
        }
        drawPath(engraving, Color.Black.copy(alpha = 0.18f), style = Stroke(width = 0.4f))
        val tip = nibTip(broad)
        drawPath(roundedRect(tip.left, tip.top, tip.width, tip.height, 0.6f), ink)
    }

    /** Watercolor and the other wet brushes: lacquered handle, crimped ferrule, a tuft loaded with ink. */
    private fun DrawScope.paintBrush(brush: Brush, ink: Color) {
        barrel(brush, ink, top = 34f, minX = 6f, maxX = 24f, band = 44f)
        val ferrule = trapezoid(top = 17.5f, topHalf = 6.6f, bottom = 34.2f, bottomHalf = 9f)
        metalBand(ferrule, 6f, 24f, gold = brush.trimIsGold)
        line(6.8f, 29.6f, 23.2f, 29.6f, Color.Black.copy(alpha = 0.25f), 0.5f)
        line(6.9f, 31.4f, 23.1f, 31.4f, Color.Black.copy(alpha = 0.25f), 0.5f)
        val tuft = Path().apply {
            moveTo(8.6f, 18.2f)
            quadraticTo(6.6f, 7f, 15f, 0.8f)
            quadraticTo(23.4f, 7f, 21.4f, 18.2f)
            close()
        }
        // Ink from the tip to past the middle, the bare hair at the ferrule.
        val loaded = Shading.linearGradient(0f to ink, 0.55f to ink, 1f to rgb(0.93f, 0.86f, 0.72f), start = Offset(0f, 1f), end = Offset(0f, 18f))
        drawPath(tuft, loaded)
        cylinder(tuft, 7.5f, 22.5f, listOf(Color.Transparent, Color.Transparent), gloss = 0.35f)
        for (x in listOf(11.5f, 14.0f, 16.5f, 18.6f)) {
            line(x, 17.6f, 15f + (x - 15f) * 0.25f, 4f, Color.White.copy(alpha = 0.22f), 0.35f)
        }
    }

    /** A blade of the grass tuft: where it stands on the ferrule and where its tip points. */
    internal class Blade(val base: Float, val tip: Offset)

    internal val blades = listOf(
        Blade(9f, Offset(6.5f, 11f)), Blade(11.5f, Offset(10.5f, 6f)), Blade(15f, Offset(15.5f, 4.5f)),
        Blade(18.5f, Offset(20f, 7f)), Blade(21f, Offset(24f, 12f)),
    )

    /** The flower's five petals around [flower], the first straight up, each a 3.4 circle 2.2 out from the middle. */
    internal fun petals(flower: Offset): List<Rect> = (0 until 5).map { k ->
        val a = k * 2f * PI.toFloat() / 5f - PI.toFloat() / 2f
        val x = flower.x + cos(a) * 2.2f - 1.7f
        val y = flower.y + sin(a) * 2.2f - 1.7f
        Rect(x, y, x + 3.4f, y + 3.4f)
    }

    /** The grass brush: a ferrule holding a little tuft of blades with a flower on top. */
    private fun DrawScope.grassBrush(brush: Brush, ink: Color) {
        barrel(brush, ink, top = 34f, minX = 5f, maxX = 25f, band = 44f)
        val ferrule = trapezoid(top = 24f, topHalf = 7.4f, bottom = 34.2f, bottomHalf = 10f)
        metalBand(ferrule, 5f, 25f, gold = false)
        blades.forEachIndexed { i, blade ->
            val p = Path().apply {
                moveTo(blade.base - 1.8f, 24.5f)
                quadraticTo(blade.base - 1.2f, 14f, blade.tip.x, blade.tip.y)
                quadraticTo(blade.base + 1.6f, 14f, blade.base + 1.8f, 24.5f)
                close()
            }
            val front = i % 2 == 0
            val green = listOf(ink.opacity(if (front) 0.85f else 1f), ink)
            drawPath(p, Shading.linearGradient(green, start = blade.tip, end = Offset(blade.base, 24.5f)))
            // Every other blade stands behind, in a little shade.
            if (!front) drawPath(p, Color.Black.copy(alpha = 0.12f))
        }
        val flower = Offset(15.5f, 4.6f)
        for (petal in petals(flower)) drawPath(ellipse(petal), rgb(1f, 0.72f, 0.84f))
        drawPath(ellipse(Rect(flower.x - 1.2f, flower.y - 1.2f, flower.x + 1.2f, flower.y + 1.2f)), rgb(1f, 0.78f, 0.2f))
    }

    /** A block eraser in a paper sleeve, seen slightly from the side so it has depth. */
    private fun DrawScope.eraser() {
        val pink = rgb(0.99f, 0.72f, 0.76f)
        val pinkLight = rgb(1.0f, 0.86f, 0.88f)
        val pinkDark = rgb(0.86f, 0.52f, 0.58f)
        // Rubber: top face, side face, front face.
        val top = Path().apply {
            moveTo(4f, 7.5f)
            quadraticTo(4.6f, 4.6f, 8f, 4f)
            lineTo(26f, 4f)
            lineTo(22f, 7.5f)
            close()
        }
        drawPath(top, pinkLight)
        val side = polygon(listOf(Offset(22f, 7.5f), Offset(26f, 4f), Offset(26f, 27f), Offset(22f, 30.5f)))
        drawPath(side, pinkDark)
        val front = roundedRect(4f, 7.5f, 18f, 24f, 1.2f)
        drawPath(front, Shading.linearGradient(listOf(pinkLight, pink, pink), start = Offset(0f, 7.5f), end = Offset(0f, 30f)))
        line(6.2f, 10.5f, 6.2f, 27f, Color.White.copy(alpha = 0.45f), 1.1f)
        // Paper sleeve: front and side, with a white band like a stationery brand stripe.
        val blue = rgb(0.16f, 0.40f, 0.82f)
        val blueDark = rgb(0.08f, 0.25f, 0.60f)
        val sleeveSide = polygon(listOf(Offset(23f, 29f), Offset(27f, 25.5f), Offset(27f, 80f), Offset(23f, 80f)))
        drawPath(sleeveSide, blueDark)
        val sleeve = rect(3f, 29f, 20f, 51f)
        drawPath(sleeve, Shading.linearGradient(listOf(blue.opacity(0.92f), blue), start = Offset(3f, 0f), end = Offset(23f, 0f)))
        drawPath(rect(3f, 38f, 20f, 5f), Color.White.copy(alpha = 0.92f))
        drawPath(rect(3f, 44.4f, 20f, 1.2f), rgb(0.90f, 0.22f, 0.26f))
        val fold = polygon(listOf(Offset(23f, 38f), Offset(27f, 34.5f), Offset(27f, 39.5f), Offset(23f, 43f)))
        drawPath(fold, Color.White.copy(alpha = 0.7f))
        line(3f, 29f, 23f, 29f, Color.Black.copy(alpha = 0.18f), 0.5f)
    }
}

// MARK: The views

/** One tool drawn by [ToolArt], in its 30 x 68 dp box. */
@Composable
fun ToolArtwork(brush: Brush?, ink: Color, modifier: Modifier = Modifier) {
    Canvas(modifier.size(ToolArt.box.width.dp, ToolArt.box.height.dp)) {
        ToolArt.draw(this, brush, ink)
    }
}

/** The tool laid at an angle in a small square, for compact buttons and the radial palette. */
@Composable
fun ToolIcon(brush: Brush?, ink: Color, side: Dp = 28.dp, modifier: Modifier = Modifier) {
    val density = LocalDensity.current
    // The pen's box scaled so its height just fills the square (the iPad's scaleEffect), then turned 40 degrees.
    val scale = side / ToolArt.box.height.dp * 1.02f
    val shadow = rememberToolShadow(brush, unit = scale * density.density, sigmaDp = 1.2f)
    Canvas(modifier.size(side)) {
        val c = center
        val boxPx = Size(ToolArt.box.width.dp.toPx() * scale, ToolArt.box.height.dp.toPx() * scale)
        val boxTopLeft = Offset(c.x - boxPx.width / 2f, c.y - boxPx.height / 2f)
        translate(top = 0.8.dp.toPx()) {
            rotate(ICON_TURN, c) { drawImage(shadow.image, topLeft = boxTopLeft + shadow.origin, alpha = 0.18f) }
        }
        rotate(ICON_TURN, c) {
            inset(
                left = boxTopLeft.x, top = boxTopLeft.y,
                right = size.width - boxTopLeft.x - boxPx.width, bottom = size.height - boxTopLeft.y - boxPx.height,
            ) {
                ToolArt.draw(this, brush, ink)
            }
        }
    }
}

/**
 * A little pen standing in the palette, like a tool in a pencil case. The selected one is raised
 * (y 2 instead of 18 in its box) with a deeper shadow, on the iPad's spring; the two shadows cross-fade
 * along the same spring, which reads like the iPad animating its shadow radius.
 */
@Composable
fun PenBody(brush: Brush?, ink: Color, selected: Boolean, modifier: Modifier = Modifier) {
    val density = LocalDensity.current.density
    val lift by animateFloatAsState(
        targetValue = if (selected) 1f else 0f,
        animationSpec = spring(dampingRatio = PEN_SPRING_DAMPING, stiffness = springStiffness(PEN_SPRING_RESPONSE)),
        label = "penLift",
    )
    val resting = rememberToolShadow(brush, unit = density, sigmaDp = PEN_REST_SHADOW_RADIUS)
    val raised = rememberToolShadow(brush, unit = density, sigmaDp = PEN_RAISED_SHADOW_RADIUS)
    Canvas(
        modifier
            .size(ToolArt.box.width.dp, ToolArt.box.height.dp)
            .graphicsLayer { translationY = (PEN_REST_Y + (PEN_RAISED_Y - PEN_REST_Y) * lift).dp.toPx() },
    ) {
        val cast = Offset(1.dp.toPx(), 2.dp.toPx())
        if (lift < 1f) drawImage(resting.image, topLeft = cast + resting.origin, alpha = PEN_REST_SHADOW * (1f - lift))
        if (lift > 0f) drawImage(raised.image, topLeft = cast + raised.origin, alpha = PEN_RAISED_SHADOW * lift)
        ToolArt.draw(this, brush, ink)
    }
}

/** ToolIcon lays the pen at this angle, clockwise. */
private const val ICON_TURN = 40f

/** PenBodyView's numbers: where the pen sits in its box and the shadow it casts, resting and raised. */
private const val PEN_REST_Y = 18f
private const val PEN_RAISED_Y = 2f
private const val PEN_REST_SHADOW = 0.14f
private const val PEN_RAISED_SHADOW = 0.28f
private const val PEN_REST_SHADOW_RADIUS = 2.5f
private const val PEN_RAISED_SHADOW_RADIUS = 5f
private const val PEN_SPRING_RESPONSE = 0.32f
private const val PEN_SPRING_DAMPING = 0.7f

/** Compose's stiffness for SwiftUI's `spring(response:)`: the response is the undamped period, 2 pi / sqrt(stiffness). */
internal fun springStiffness(response: Float): Float = (2.0 * PI / response).pow(2).toFloat()

// MARK: The shadow

/** A pen's shadow bitmap and where its box's origin sits in it (the blur grows the bitmap around the box). */
private class ToolShadow(val image: ImageBitmap, val origin: Offset)

/**
 * The shadow the iPad's `.shadow(radius:)` gives a pen: a Gaussian blur of the pen's silhouette, drawn
 * at full black; the draw call sets the shadow's opacity. Rendered in software once per pen, so it works
 * on every Android version. [unit] is pixels per unit of the drawing, [sigmaDp] the iPad's radius (its
 * blur's standard deviation).
 */
@Composable
private fun rememberToolShadow(brush: Brush?, unit: Float, sigmaDp: Float): ToolShadow {
    val density = LocalDensity.current
    val sigmaPx = sigmaDp * density.density
    return remember(brush, unit, sigmaPx) { renderToolShadow(brush, unit, sigmaPx, density) }
}

private fun renderToolShadow(brush: Brush?, unit: Float, sigmaPx: Float, density: Density): ToolShadow {
    val width = ceil(ToolArt.box.width * unit).toInt().coerceAtLeast(1)
    val height = ceil(ToolArt.box.height * unit).toInt().coerceAtLeast(1)
    val silhouette = ImageBitmap(width, height)
    CanvasDrawScope().draw(density, LayoutDirection.Ltr, ImageCanvas(silhouette), Size(ToolArt.box.width * unit, ToolArt.box.height * unit)) {
        ToolArt.draw(this, brush, Color.Black)
    }
    // extractAlpha runs the mask filter in software; the alpha bitmap comes back larger by the blur, with its offset.
    val blur = android.graphics.Paint().apply {
        val radius = blurRadiusForSigma(sigmaPx)
        if (radius > 0f) maskFilter = BlurMaskFilter(radius, BlurMaskFilter.Blur.NORMAL)
    }
    val offset = IntArray(2)
    val alpha = silhouette.asAndroidBitmap().extractAlpha(blur, offset)
    // An ordinary ARGB bitmap of the black shadow: the hardware canvas then draws it like any image.
    val shadow = Bitmap.createBitmap(alpha.width, alpha.height, Bitmap.Config.ARGB_8888)
    android.graphics.Canvas(shadow).drawBitmap(alpha, 0f, 0f, android.graphics.Paint().apply { color = android.graphics.Color.BLACK })
    alpha.recycle()
    return ToolShadow(shadow.asImageBitmap(), Offset(offset[0].toFloat(), offset[1].toFloat()))
}

/** Android's BlurMaskFilter takes a radius it turns into sigma = 0.57735 * radius + 0.5; this is the way back. */
internal fun blurRadiusForSigma(sigma: Float): Float = if (sigma > 0.5f) (sigma - 0.5f) / 0.57735f else 0f

// MARK: The gallery

/** The iPad dock's grey, for the gallery. */
private val DockGrey = Color(0xFF4A4A4C)

/**
 * Every pen and the eraser standing in a dock like the iPad's with one raised, and under it every tool as
 * the 30 dp icon of the folded bar: to compare with the iPad on the emulator. Not wired into the app.
 */
@Composable
fun ToolArtGallery(selected: Brush? = Brush.PEN, modifier: Modifier = Modifier) {
    val tools: List<Brush?> = Brush.paletteOrder + null
    fun inkOf(brush: Brush?): Color = brush?.palette?.first()?.let { Color(it.r, it.g, it.b, it.a) } ?: Color.Transparent
    Column(
        modifier.background(Color(0xFF1C1C1E)).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(20.dp),
    ) {
        // The dock: 66 dp tall, the pens bottom-aligned in it and cut at its edge like the iPad's clipped row,
        // kept clear of the capsule's round ends as the iPad's grip and buttons keep them.
        Row(
            Modifier
                .fillMaxWidth()
                .height(66.dp)
                .clip(CircleShape)
                .background(DockGrey)
                .horizontalScroll(rememberScrollState())
                .padding(horizontal = 36.dp),
            horizontalArrangement = Arrangement.spacedBy(6.dp),
            verticalAlignment = Alignment.Bottom,
        ) {
            for (tool in tools) {
                PenBody(tool, inkOf(tool), selected = tool == selected, Modifier.wrapContentHeight(Alignment.Bottom, unbounded = true))
            }
        }
        Row(
            Modifier
                .fillMaxWidth()
                .height(50.dp)
                .clip(CircleShape)
                .background(DockGrey)
                .horizontalScroll(rememberScrollState())
                .padding(horizontal = 36.dp),
            horizontalArrangement = Arrangement.spacedBy(6.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            for (tool in tools) ToolIcon(tool, inkOf(tool), side = 30.dp)
        }
    }
}
