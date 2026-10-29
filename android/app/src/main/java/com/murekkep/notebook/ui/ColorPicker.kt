package com.murekkep.notebook.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.drag
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush as Gradient
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.murekkep.notebook.R
import com.murekkep.notebook.ink.Brush
import com.murekkep.notebook.ink.InkColor
import kotlin.math.abs
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

// The pen's colours (ColorGrid on iPad, Murekkep.swiftpm/ToolPalette.swift): its six, a custom one,
// and the custom colours picked lately. The iPad's custom swatch is the system colour picker; Android
// has none, so the swatch opens a small picker under the colours: a saturation and brightness field
// over a hue bar, with an opacity bar for the watercolour and the highlighter as the iPad allows.

/** Only the watercolour and the highlighter take a custom colour's opacity (the iPad's supportsOpacity). */
private val Brush.takesOpacity: Boolean get() = this == Brush.WATERCOLOR || this == Brush.HIGHLIGHTER

/** The six colours and the custom one in a row, the recent custom colours (up to seven) under them. */
@Composable
internal fun ColorGrid(state: EditorState, brush: Brush) {
    val color = state.color(brush)
    val tick = rememberSelectionTick()
    var picking by remember(brush) { mutableStateOf(false) }
    val pick = { c: InkColor ->
        if (c != state.color(brush)) {
            state.setColor(brush, c)
            tick()
        }
    }
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        // Seven 40 dp swatches fit the popover's 288 dp only this close.
        Row(horizontalArrangement = Arrangement.spacedBy(1.dp)) {
            brush.palette.forEachIndexed { index, c ->
                Swatch(c, selected = c == color, label = stringResource(R.string.color_number, index + 1)) { pick(c) }
            }
            CustomSwatch(color) { picking = !picking }
        }
        val recents = state.recentColors.filter { it !in brush.palette }.take(7)
        if (recents.isNotEmpty()) {
            val label = stringResource(R.string.pen_custom_color)
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                for (c in recents) Swatch(c, selected = c == color, label = label, small = true) { pick(c) }
            }
        }
        if (picking) {
            HsvPicker(color, opacity = brush.takesOpacity) { state.setColor(brush, it) }
        }
    }
}

/** A dot of the colour, 32 dp (24 among the recent ones); the chosen one wears a ring of ink-2 a little way out. */
@Composable
private fun Swatch(color: InkColor, selected: Boolean, label: String, small: Boolean = false, onClick: () -> Unit) {
    val z = Zen.colors
    Box(
        Modifier
            .size(if (small) 30.dp else 40.dp)
            .then(if (selected) Modifier.border(2.dp, z.ink2, CircleShape) else Modifier)
            .padding(if (small) 3.dp else 4.dp)
            .clip(CircleShape)
            .background(color.toColor())
            .border(1.dp, z.ink.copy(alpha = 0.12f), CircleShape)
            .clickable(role = Role.Button, onClick = onClick)
            .semantics {
                contentDescription = label
                this.selected = selected
            },
    )
}

/** The custom colour's well: the colour in hand inside a ring of every hue, as the iPad's colour well. */
@Composable
private fun CustomSwatch(color: InkColor, onClick: () -> Unit) {
    val label = stringResource(R.string.pen_custom_color)
    Box(
        Modifier
            .size(40.dp)
            .padding(4.dp)
            .clip(CircleShape)
            .clickable(role = Role.Button, onClick = onClick)
            .semantics { contentDescription = label },
    ) {
        Canvas(Modifier.size(32.dp)) {
            drawCircle(Gradient.sweepGradient(HueStops), style = Stroke(width = 3.5.dp.toPx()), radius = size.minDimension / 2 - 1.75.dp.toPx())
            drawCircle(color.toColor(), radius = size.minDimension / 2 - 5.5.dp.toPx())
        }
    }
}

/** Every hue round the wheel, red to red. */
private val HueStops: List<Color> = (0..6).map { Hsv(it * 60f % 360f, 1f, 1f, 1f).toInk().toColor() }

/**
 * The custom colour's picker: a field of saturation (across) and brightness (down) in the colour's
 * hue, a hue bar and, for [opacity], an opacity bar. It follows a colour picked elsewhere, and gives
 * every change at once.
 */
@Composable
private fun HsvPicker(color: InkColor, opacity: Boolean, onChange: (InkColor) -> Unit) {
    val z = Zen.colors
    var hsv by remember { mutableStateOf(Hsv.of(color)) }
    LaunchedEffect(color) {
        if (hsv.toInk(opacity) != color) hsv = Hsv.of(color, hueIfGrey = hsv.h)
    }
    val set = { next: Hsv ->
        hsv = next
        onChange(next.toInk(opacity))
    }
    val shape = RoundedCornerShape(Zen.control)
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        val pure = Hsv(hsv.h, 1f, 1f, 1f).toInk().toColor()
        val shadeLabel = stringResource(R.string.picker_shade)
        Canvas(
            Modifier
                .fillMaxWidth()
                .height(120.dp)
                .clip(shape)
                .border(1.dp, z.rule, shape)
                .semantics { contentDescription = shadeLabel }
                .track { x, y -> set(hsv.copy(s = x, v = 1f - y)) },
        ) {
            drawRect(Gradient.horizontalGradient(listOf(Color.White, pure)))
            drawRect(Gradient.verticalGradient(listOf(Color.Transparent, Color.Black)))
            thumb(Offset(hsv.s * size.width, (1f - hsv.v) * size.height), hsv.copy(a = 1f).toInk().toColor())
        }
        val hueLabel = stringResource(R.string.picker_hue)
        Canvas(
            Modifier
                .fillMaxWidth()
                .height(22.dp)
                .clip(shape)
                .semantics { contentDescription = hueLabel }
                .track { x, _ -> set(hsv.copy(h = x * 360f)) },
        ) {
            drawRect(Gradient.horizontalGradient(HueStops))
            thumb(Offset(hsv.h / 360f * size.width, size.height / 2), pure)
        }
        if (opacity) {
            val opacityLabel = stringResource(R.string.picker_opacity)
            Canvas(
                Modifier
                    .fillMaxWidth()
                    .height(22.dp)
                    .clip(shape)
                    .border(1.dp, z.rule, shape)
                    .semantics { contentDescription = opacityLabel }
                    .track { x, _ -> set(hsv.copy(a = x)) },
            ) {
                checkers()
                val solid = hsv.copy(a = 1f).toInk().toColor()
                drawRect(Gradient.horizontalGradient(listOf(solid.copy(alpha = 0f), solid)))
                thumb(Offset(hsv.a * size.width, size.height / 2), hsv.toInk().toColor())
            }
        }
    }
}

/** Follows a finger or pen on the control from its first touch, as fractions of its width and height;
 *  the touch is the control's alone (the popover does not scroll under it). */
private fun Modifier.track(onMove: (x: Float, y: Float) -> Unit): Modifier = pointerInput(Unit) {
    fun report(p: Offset) = onMove(
        (p.x / size.width).coerceIn(0f, 1f),
        (p.y / size.height).coerceIn(0f, 1f),
    )
    awaitEachGesture {
        val down = awaitFirstDown()
        down.consume()
        report(down.position)
        drag(down.id) { change ->
            change.consume()
            report(change.position)
        }
    }
}

/** The picker's thumb: a white ring with a hairline round the colour it stands on. */
private fun DrawScope.thumb(center: Offset, fill: Color) {
    val r = 9.dp.toPx()
    drawCircle(Color.Black.copy(alpha = 0.25f), radius = r + 1.dp.toPx(), center = center)
    drawCircle(Color.White, radius = r, center = center)
    drawCircle(fill, radius = r - 2.5.dp.toPx(), center = center)
}

/** The grey and white checks behind a see-through colour. */
private fun DrawScope.checkers() {
    val cell = 5.5.dp.toPx()
    drawRect(Color.White)
    val columns = (size.width / cell).toInt() + 1
    val rows = (size.height / cell).toInt() + 1
    for (row in 0 until rows) for (col in 0 until columns) {
        if ((row + col) % 2 == 0) drawRect(Color(0xFFD9D9D9), Offset(col * cell, row * cell), Size(cell, cell))
    }
}

/**
 * A colour as hue (degrees), saturation, brightness and opacity, all but the hue in 0...1. [toInk]
 * rounds to the 8 bits a channel is kept in, so a picked colour compares equal to itself once stored.
 */
internal data class Hsv(val h: Float, val s: Float, val v: Float, val a: Float) {
    fun toInk(opacity: Boolean = true): InkColor {
        val c = v * s
        val k = (h % 360f + 360f) % 360f / 60f
        val x = c * (1f - abs(k % 2f - 1f))
        val (r, g, b) = when (floor(k).toInt()) {
            0 -> Triple(c, x, 0f)
            1 -> Triple(x, c, 0f)
            2 -> Triple(0f, c, x)
            3 -> Triple(0f, x, c)
            4 -> Triple(x, 0f, c)
            else -> Triple(c, 0f, x)
        }
        val m = v - c
        return InkColor(byte(r + m), byte(g + m), byte(b + m), if (opacity) byte(a) else 1f)
    }

    companion object {
        /** [color] as hue, saturation and brightness; a grey has no hue of its own and keeps [hueIfGrey]. */
        fun of(color: InkColor, hueIfGrey: Float = 0f): Hsv {
            val hi = max(color.r, max(color.g, color.b))
            val lo = min(color.r, min(color.g, color.b))
            val d = hi - lo
            val h = when {
                d <= 0f -> hueIfGrey
                hi == color.r -> 60f * (((color.g - color.b) / d) % 6f)
                hi == color.g -> 60f * ((color.b - color.r) / d + 2f)
                else -> 60f * ((color.r - color.g) / d + 4f)
            }
            return Hsv((h + 360f) % 360f, if (hi <= 0f) 0f else d / hi, hi, color.a)
        }

        private fun byte(v: Float): Float = (v.coerceIn(0f, 1f) * 255f).roundToInt() / 255f
    }
}
