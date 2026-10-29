package com.murekkep.notebook.ui

import android.graphics.Bitmap
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.murekkep.notebook.R
import com.murekkep.notebook.export.FlatInk
import com.murekkep.notebook.ink.Brush
import com.murekkep.notebook.ink.GrassGenerator
import com.murekkep.notebook.ink.InkColor
import com.murekkep.notebook.ink.InkPoint
import com.murekkep.notebook.ink.Stroke
import com.murekkep.notebook.ink.referenceNow
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

// One pen's settings, a quiet card (BrushInspector on iPad, Murekkep.swiftpm/ToolPalette.swift): the
// pen's name and a sentence about it, the ink's real look, the colours (ColorPicker.kt), the
// thickness, what is the pen's own (the nib's angle, the flowers, the drying and cooling times, a
// note) and its animation. Closing it keeps a custom colour among the recent ones.

/** The iPad's subheadline: the sentence under the pen's name and the switches. */
private val Subheadline: TextStyle
    @Composable get() = MaterialTheme.typography.bodyMedium.copy(fontSize = 15.sp, lineHeight = 20.sp)

@Composable
internal fun PenSettings(state: EditorState, brush: Brush) {
    val z = Zen.colors
    val color = state.color(brush)
    val width = state.width(brush)
    DisposableEffect(state, brush) {
        onDispose {
            val picked = state.color(brush)
            if (picked !in brush.palette) state.rememberColor(picked)
        }
    }
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(brush.localizedTitle(), style = MaterialTheme.typography.titleMedium, color = z.ink)
        Text(stringResource(brush.descriptionRes), style = Subheadline, color = z.ink2)
    }
    val shape = RoundedCornerShape(12.dp)
    InkSample(
        brush, color, width, GrassGenerator.strokeSeed(brush, state.flowerLevel, 0.37f), 120.dp,
        Modifier.clip(shape).border(1.dp, z.rule, shape),
    )
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        LabelRow(stringResource(R.string.color))
        ColorGrid(state, brush)
    }
    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
        LabelRow(stringResource(R.string.pen_width), width.roundToInt().toString())
        ZenSlider(width, { state.setWidth(brush, it) }, brush.widthRange, stringResource(R.string.pen_width))
    }
    PenOptions(state, brush)
}

/** What is the pen's own, with the iPad's ranges (extraOptions): every animated pen's switch is the
 *  one setting of the animations. Steps of 1 as the iPad's sliders. */
@Composable
private fun PenOptions(state: EditorState, brush: Brush) {
    when (brush) {
        Brush.CALLIGRAPHY -> {
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                val title = stringResource(R.string.pen_nib_angle)
                LabelRow(title, "${state.nibAngle.roundToInt()}°")
                ZenSlider(state.nibAngle, { state.nibAngle = it.roundToInt().toFloat() }, 0f..180f, title)
            }
        }
        Brush.GRASS -> {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                LabelRow(stringResource(R.string.pen_flowers))
                ZenSegments(
                    options = listOf(
                        stringResource(R.string.pen_flowers_none),
                        stringResource(R.string.pen_flowers_some),
                        stringResource(R.string.pen_flowers_lots),
                    ),
                    selected = state.flowerLevel,
                    onSelect = { state.flowerLevel = it },
                    modifier = Modifier.fillMaxWidth(),
                )
                InspectorNote(stringResource(R.string.pen_note_grass))
            }
            InspectorSwitch(stringResource(R.string.pen_sway_in_wind), state.animations) { state.animations = it }
        }
        Brush.WET -> {
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                val title = stringResource(R.string.pen_drying_time)
                LabelRow(title, stringResource(R.string.pen_seconds, state.dryDuration.roundToInt()))
                ZenSlider(state.dryDuration.coerceIn(1f, 15f), { state.dryDuration = it.roundToInt().toFloat() }, 1f..15f, title)
            }
        }
        Brush.LAVA -> {
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                val title = stringResource(R.string.pen_cooling_time)
                LabelRow(title, stringResource(R.string.pen_seconds, state.coolDuration.roundToInt()))
                ZenSlider(state.coolDuration, { state.coolDuration = it.roundToInt().toFloat() }, 2f..20f, title)
                InspectorNote(stringResource(R.string.pen_note_lava))
            }
            InspectorSwitch(stringResource(R.string.pen_lava_animation), state.animations) { state.animations = it }
        }
        Brush.FOUNTAIN -> InspectorNote(stringResource(R.string.pen_note_fountain))
        Brush.WAVE, Brush.GLITTER, Brush.SEA, Brush.ICE, Brush.JELLY, Brush.BLOOM, Brush.GALAXY, Brush.LIGHTNING ->
            InspectorSwitch(stringResource(R.string.pen_animation), state.animations) { state.animations = it }
        Brush.PENCIL -> InspectorNote(stringResource(R.string.pen_note_pencil))
        else -> {}
    }
}

/** A switch of the pen, under a hairline. */
@Composable
private fun InspectorSwitch(title: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    val z = Zen.colors
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Box(Modifier.fillMaxWidth().height(1.dp).background(z.rule))
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text(title, style = Subheadline, color = z.ink2, modifier = Modifier.weight(1f))
            ZenSwitch(checked, onChange)
        }
    }
}

/** A sentence about the pen, in the muted small text. */
@Composable
private fun InspectorNote(text: String) {
    Text(text, style = MaterialTheme.typography.bodySmall, color = Zen.colors.muted)
}

/**
 * The ink as it lands (StrokePreview on iPad): one S-curve across the sample in the pen, its colour
 * and width (no wider than a third of the height), drawn by FlatInk on [paper] [height] tall: the
 * card's own white, or a row's colour, or clear for the row to show through. [seed] is the
 * stroke's (grass carries its flowers in it).
 */
@Composable
internal fun InkSample(brush: Brush, color: InkColor, width: Float, seed: Float, height: Dp, modifier: Modifier = Modifier, paper: Color = Color.White) {
    BoxWithConstraints(modifier.fillMaxWidth().height(height)) {
        val density = LocalDensity.current.density
        val w = maxWidth.value
        val under = paper.toArgb()
        val image = remember(brush, color, width, seed, w, height, density, under) { renderInkSample(brush, color, width, seed, w, height.value, density, under) }
        Image(image, contentDescription = null, modifier = Modifier.fillMaxSize())
    }
}

/** The iPad's sample stroke in a box [w] x [h] (dp, a page point each) on [paper] (argb): from 16 in
 *  from the left to 16 in from the right at 62 % of the height, up through the first third and a
 *  little down after. */
private fun renderInkSample(brush: Brush, color: InkColor, width: Float, seed: Float, w: Float, h: Float, density: Float, paper: Int): ImageBitmap {
    val bitmap = Bitmap.createBitmap(max(1, (w * density).roundToInt()), max(1, (h * density).roundToInt()), Bitmap.Config.ARGB_8888)
    bitmap.eraseColor(paper)
    val canvas = android.graphics.Canvas(bitmap)
    canvas.scale(density, density)
    val mid = h * 0.62f
    val line = max(1.5f, min(width, h * 0.35f))
    val x0 = 16f
    val x3 = w - 16f
    val x1 = w * 0.35f
    val x2 = w * 0.62f
    val y1 = mid - h * 0.55f
    val y2 = mid + h * 0.35f
    val count = 120
    val points = (0..count).map { i ->
        val t = i.toFloat() / count
        val u = 1f - t
        val a = u * u * u
        val b = 3f * u * u * t
        val c = 3f * u * t * t
        val d = t * t * t
        InkPoint(a * x0 + b * x1 + c * x2 + d * x3, a * mid + b * y1 + c * y2 + d * mid, line / 2f, 0.55f)
    }
    // Born a minute ago: wet ink dry, lava cooled, as the iPad's settings show them.
    FlatInk.draw(listOf(Stroke(brush, color, line, referenceNow() - 60.0, seed, points)), canvas)
    return bitmap.asImageBitmap()
}
