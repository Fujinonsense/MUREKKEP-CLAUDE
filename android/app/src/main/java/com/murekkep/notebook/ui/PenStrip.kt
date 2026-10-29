@file:OptIn(
    androidx.compose.material3.ExperimentalMaterial3Api::class,
    androidx.compose.foundation.layout.ExperimentalLayoutApi::class,
    androidx.compose.foundation.ExperimentalFoundationApi::class,
)

package com.murekkep.notebook.ui

import android.graphics.Bitmap
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.Redo
import androidx.compose.material.icons.automirrored.outlined.Undo
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.Category
import androidx.compose.material.icons.outlined.GridView
import androidx.compose.material.icons.outlined.NoteAdd
import androidx.compose.material.icons.outlined.Remove
import androidx.compose.material3.Icon
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntRect
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Popup
import androidx.compose.ui.window.PopupPositionProvider
import androidx.compose.ui.window.PopupProperties
import com.murekkep.notebook.R
import com.murekkep.notebook.export.FlatInk
import com.murekkep.notebook.ink.Brush
import com.murekkep.notebook.ink.BrushGroup
import com.murekkep.notebook.ink.EraserMode
import com.murekkep.notebook.ink.InkColor
import com.murekkep.notebook.ink.InkPoint
import com.murekkep.notebook.ink.ShapeKind
import com.murekkep.notebook.ink.ShapeName
import com.murekkep.notebook.ink.Stroke
import com.murekkep.notebook.ink.referenceNow
import java.util.Locale
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.roundToInt
import kotlin.math.sin

// The editor's floating pen bar (the spec's "kalem rafı", Murekkep.swiftpm/ToolPalette.swift and
// PenStrip.swift): Geri al, Yinele | five pens (the favourites, then the pens used last) and the
// eraser standing in a low tray, the picked one raised | the ink's colour | Kement, Şekiller, Tüm
// kalemler | Sayfa ekle. In black and white the pens are flat silhouettes (PenSilhouettes.kt); a
// Pro theme draws the iPad's realistic bodies (ToolArt.kt). A second tap on the picked pen, or a tap
// on the colour, opens the pen's settings in a popover above the bar: its name, one sentence, the
// ink's real look, the colours, the width. The eraser's and the shapes' settings open the same way
// from their buttons; the grid button opens every pen by group. A long press on a pen stars it.

fun InkColor.toColor(): Color = Color(r, g, b, a)

private val isTurkish: Boolean
    get() = Locale.getDefault().language == "tr"

/** The pen's name in the user's language: Turkish, else English. */
fun Brush.localizedTitle(): String = if (isTurkish) titleTr else titleEn

fun BrushGroup.localizedTitle(): String = if (isTurkish) titleTr else titleEn

/** A shape's name in the user's language: Turkish, else English. */
fun ShapeName.localizedTitle(): String = if (isTurkish) titleTr else titleEn

/** The one sentence that tells what the pen does, for its settings. */
val Brush.descriptionRes: Int
    get() = when (this) {
        Brush.PEN -> R.string.pen_desc_pen
        Brush.WET -> R.string.pen_desc_wet
        Brush.WAVE -> R.string.pen_desc_wave
        Brush.HIGHLIGHTER -> R.string.pen_desc_highlighter
        Brush.PENCIL -> R.string.pen_desc_pencil
        Brush.CALLIGRAPHY -> R.string.pen_desc_calligraphy
        Brush.WATERCOLOR -> R.string.pen_desc_watercolor
        Brush.NEON -> R.string.pen_desc_neon
        Brush.RAINBOW -> R.string.pen_desc_rainbow
        Brush.GLITTER -> R.string.pen_desc_glitter
        Brush.GRASS -> R.string.pen_desc_grass
        Brush.SEA -> R.string.pen_desc_sea
        Brush.LAVA -> R.string.pen_desc_lava
        Brush.FOUNTAIN -> R.string.pen_desc_fountain
        Brush.GOLD -> R.string.pen_desc_gold
        Brush.CHROME -> R.string.pen_desc_chrome
        Brush.ICE -> R.string.pen_desc_ice
        Brush.JELLY -> R.string.pen_desc_jelly
        Brush.GALAXY -> R.string.pen_desc_galaxy
        Brush.LIGHTNING -> R.string.pen_desc_lightning
        Brush.PEARL -> R.string.pen_desc_pearl
        Brush.IMPASTO -> R.string.pen_desc_impasto
        Brush.BLOOM -> R.string.pen_desc_bloom
    }

/** The bar's height; the pens stand bottom-aligned in it and are cut at its edge. */
val PenBarHeight = 64.dp

/** How far the bar floats above the bottom of the page. */
val PenBarMargin = 18.dp

// MARK: The bar

/** What the bar has open; one thing at a time. */
private enum class Sheet { PEN_FROM_SLOT, PEN_FROM_DOT, ERASER, SHAPES, ALL_PENS }

@Composable
fun PenBar(state: EditorState, modifier: Modifier = Modifier) {
    val z = Zen.colors
    var sheet by remember { mutableStateOf<Sheet?>(null) }
    val close = { sheet = null }
    val tool = state.tool
    val (favorites, recent) = state.barPens
    val pens = favorites + recent
    Row(
        modifier.floating(Zen.bar).height(PenBarHeight).padding(horizontal = 10.dp),
        verticalAlignment = Alignment.Bottom,
    ) {
        Row(Modifier.height(62.dp), verticalAlignment = Alignment.CenterVertically) {
            BarButton(stringResource(R.string.undo), enabled = state.canUndo, onClick = state::undo) {
                Icon(Icons.AutoMirrored.Outlined.Undo, contentDescription = null, modifier = Modifier.size(22.dp))
            }
            BarButton(stringResource(R.string.redo), enabled = state.canRedo, onClick = state::redo) {
                Icon(Icons.AutoMirrored.Outlined.Redo, contentDescription = null, modifier = Modifier.size(22.dp))
            }
            BarDivider()
        }
        Row(Modifier.height(62.dp), horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.Bottom) {
            for (brush in pens) {
                val selected = tool is Tool.Brush && tool.brush == brush
                PenSlot(
                    brush = brush,
                    ink = state.color(brush).toColor(),
                    selected = selected,
                    starred = brush in favorites,
                    onTap = { if (selected) sheet = Sheet.PEN_FROM_SLOT else state.tool = Tool.Brush(brush) },
                    onLongPress = { state.toggleFavorite(brush) },
                ) {
                    if (sheet == Sheet.PEN_FROM_SLOT && selected) {
                        BarPopover(onDismiss = close) { PenSettings(state, brush) }
                    }
                }
            }
            PenSlot(
                brush = null,
                ink = Color.Transparent,
                selected = tool is Tool.Eraser,
                starred = false,
                onTap = { if (tool is Tool.Eraser) sheet = Sheet.ERASER else state.toggleEraser() },
                onLongPress = {},
            ) {
                if (sheet == Sheet.ERASER) {
                    BarPopover(onDismiss = close) { EraserSettings(state) }
                }
            }
        }
        Row(Modifier.height(62.dp), verticalAlignment = Alignment.CenterVertically) {
            BarDivider()
            val active = state.activeBrush
            ColorDot(state.color(active).toColor(), onClick = { sheet = Sheet.PEN_FROM_DOT }) {
                if (sheet == Sheet.PEN_FROM_DOT) {
                    BarPopover(onDismiss = close) { PenSettings(state, active) }
                }
            }
            BarDivider()
            BarButton(
                stringResource(R.string.lasso),
                selected = tool is Tool.Lasso,
                onClick = { state.tool = if (tool is Tool.Lasso) Tool.Brush(state.lastBrush) else Tool.Lasso },
            ) { LassoGlyph(Modifier.size(22.dp), if (tool is Tool.Lasso) z.ink else z.ink2) }
            BarButton(
                stringResource(R.string.shapes),
                selected = tool is Tool.Shape,
                onClick = { if (tool is Tool.Shape) sheet = Sheet.SHAPES else state.tool = Tool.Shape },
            ) {
                Icon(Icons.Outlined.Category, contentDescription = null, modifier = Modifier.size(22.dp))
                if (sheet == Sheet.SHAPES) {
                    BarPopover(onDismiss = close) { ShapeSettings(state) }
                }
            }
            BarButton(stringResource(R.string.all_pens), onClick = { sheet = Sheet.ALL_PENS }) {
                Icon(Icons.Outlined.GridView, contentDescription = null, modifier = Modifier.size(22.dp))
                if (sheet == Sheet.ALL_PENS) {
                    BarPopover(onDismiss = close, width = 482.dp) { AllPens(state, onPicked = close) }
                }
            }
            if (!state.isPdf) {
                BarDivider()
                BarButton(stringResource(R.string.add_page), enabled = !state.readOnly, onClick = state::addPage) {
                    Icon(Icons.Outlined.NoteAdd, contentDescription = null, modifier = Modifier.size(22.dp))
                }
            }
        }
    }
}

/** A 44 dp button of the bar: its glyph in ink-2, paper-3 behind it while its tool is in the hand. */
@Composable
fun BarButton(
    label: String,
    selected: Boolean = false,
    enabled: Boolean = true,
    onClick: () -> Unit,
    content: @Composable () -> Unit,
) {
    val z = Zen.colors
    val tint = when {
        !enabled -> z.rule
        selected -> z.ink
        else -> z.ink2
    }
    Box(
        Modifier
            .size(Zen.target)
            .clip(RoundedCornerShape(Zen.control))
            .background(if (selected) z.paper3 else Color.Transparent)
            .clickable(enabled = enabled, onClick = onClick)
            .semantics {
                contentDescription = label
                if (selected) this.selected = true
            },
        contentAlignment = Alignment.Center,
    ) {
        CompositionLocalProvider(LocalContentColor provides tint) {
            content()
        }
    }
}

@Composable
private fun BarDivider() {
    Box(Modifier.padding(horizontal = 8.dp).size(1.dp, 28.dp).background(Zen.colors.rule))
}

/** The numbers of the pens' lift: resting 16 dp into the clipped slot, raised 2 dp (the mockup's SVGs). */
private const val PEN_REST_Y = 16f
private const val PEN_RAISED_Y = 2f

/**
 * One pen standing in the tray (null: the eraser), 34 x 62 dp, cut at the tray's edge. The picked
 * one is raised on the iPad's spring. A starred pen wears a small star in its corner. [popover] is
 * the pen's settings when they are open, anchored to this slot.
 */
@Composable
private fun PenSlot(
    brush: Brush?,
    ink: Color,
    selected: Boolean,
    starred: Boolean,
    onTap: () -> Unit,
    onLongPress: () -> Unit,
    popover: @Composable () -> Unit,
) {
    val z = Zen.colors
    val name = brush?.localizedTitle() ?: stringResource(R.string.eraser)
    val hint = stringResource(R.string.tap_again_settings)
    val lift by animateFloatAsState(
        targetValue = if (selected) 1f else 0f,
        animationSpec = spring(dampingRatio = 0.7f, stiffness = springStiffness(0.32f)),
        label = "penLift",
    )
    Box(
        Modifier
            .size(34.dp, 62.dp)
            .clipToBounds()
            .combinedClickable(onClick = onTap, onLongClick = onLongPress)
            .semantics {
                contentDescription = if (selected) "$name. $hint" else name
                this.selected = selected
            },
    ) {
        if (z.proTheme) {
            PenBody(brush, ink, selected, Modifier.align(Alignment.TopCenter))
        } else {
            val y = PEN_REST_Y + (PEN_RAISED_Y - PEN_REST_Y) * lift
            PenSilhouetteArt(
                brush, ink,
                Modifier.align(Alignment.TopCenter).offset { IntOffset(0, y.dp.roundToPx()) },
            )
        }
        if (starred) {
            Icon(
                Icons.Filled.Star, contentDescription = null, tint = z.muted,
                modifier = Modifier.align(Alignment.TopStart).padding(start = 2.dp, top = 3.dp).size(8.dp),
            )
        }
        popover()
    }
}

/** The ink's colour in a ring: opens the pen's settings. */
@Composable
private fun ColorDot(color: Color, onClick: () -> Unit, popover: @Composable () -> Unit) {
    val z = Zen.colors
    val label = stringResource(R.string.color_and_width)
    Box(
        Modifier
            .size(Zen.target)
            .clip(RoundedCornerShape(Zen.control))
            .clickable(onClick = onClick)
            .semantics { contentDescription = label },
        contentAlignment = Alignment.Center,
    ) {
        Box(
            Modifier
                .size(30.dp)
                .border(1.dp, if (z.dark) z.muted else z.rule, CircleShape)
                .padding(3.dp)
                .clip(CircleShape)
                .background(color),
        )
        popover()
    }
}

// MARK: Popovers

/** The transparent margin round a popover, where its shadow is drawn (the popup window is cut at its edge). */
private val PopoverShadowPad = 44.dp

/** Puts a popover 12 dp above its anchor, centred on it, kept inside the window by 8 dp. */
private class AboveAnchor(private val pad: Int, private val gap: Int, private val margin: Int) : PopupPositionProvider {
    override fun calculatePosition(anchorBounds: IntRect, windowSize: IntSize, layoutDirection: LayoutDirection, popupContentSize: IntSize): IntOffset {
        val innerW = popupContentSize.width - 2 * pad
        val innerH = popupContentSize.height - 2 * pad
        val left = (anchorBounds.center.x - innerW / 2).coerceIn(margin, max(margin, windowSize.width - innerW - margin))
        val top = (anchorBounds.top - gap - innerH).coerceAtLeast(margin)
        return IntOffset(left - pad, top - pad)
    }
}

/** A popover of the bar: 320 dp of paper with a hairline and the float shadow, closed by a tap outside or Back. */
@Composable
private fun BarPopover(onDismiss: () -> Unit, width: Dp = 320.dp, content: @Composable ColumnScope.() -> Unit) {
    val density = LocalDensity.current
    val provider = remember(density) {
        with(density) { AboveAnchor(PopoverShadowPad.roundToPx(), 12.dp.roundToPx(), 8.dp.roundToPx()) }
    }
    Popup(popupPositionProvider = provider, onDismissRequest = onDismiss, properties = PopupProperties(focusable = true)) {
        Box(Modifier.padding(PopoverShadowPad)) {
            Column(
                Modifier.width(width).floating(Zen.popover).padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp),
                content = content,
            )
        }
    }
}

/** A control's name on the left and its value on the right, in the muted text of the popovers. */
@Composable
private fun LabelRow(label: String, value: String? = null) {
    val z = Zen.colors
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        Text(label, style = MaterialTheme.typography.bodySmall, color = z.muted)
        if (value != null) Text(value, style = MaterialTheme.typography.bodySmall, color = z.ink2)
    }
}

/** A thin slider in ink-2 on a rule track. */
@Composable
fun ZenSlider(value: Float, onChange: (Float) -> Unit, range: ClosedFloatingPointRange<Float>, label: String, modifier: Modifier = Modifier) {
    val z = Zen.colors
    val colors = SliderDefaults.colors(
        thumbColor = z.ink2, activeTrackColor = z.ink2, inactiveTrackColor = z.rule,
        activeTickColor = Color.Transparent, inactiveTickColor = Color.Transparent,
    )
    val interaction = remember { MutableInteractionSource() }
    Slider(
        value = value,
        onValueChange = onChange,
        valueRange = range,
        colors = colors,
        interactionSource = interaction,
        thumb = { SliderDefaults.Thumb(interactionSource = interaction, colors = colors, thumbSize = DpSize(20.dp, 20.dp)) },
        track = { sliderState ->
            SliderDefaults.Track(
                sliderState = sliderState, colors = colors, thumbTrackGapSize = 0.dp, trackInsideCornerSize = 0.dp,
                drawStopIndicator = null, modifier = Modifier.height(4.dp),
            )
        },
        modifier = modifier.fillMaxWidth().semantics { contentDescription = label },
    )
}

/** A switch in the accent. */
@Composable
fun ZenSwitch(checked: Boolean, onChange: (Boolean) -> Unit) {
    val z = Zen.colors
    Switch(
        checked = checked,
        onCheckedChange = onChange,
        colors = SwitchDefaults.colors(
            checkedTrackColor = z.accent, checkedThumbColor = Color.White, checkedBorderColor = z.accent,
            uncheckedTrackColor = z.paper3, uncheckedThumbColor = z.muted, uncheckedBorderColor = z.rule,
        ),
    )
}

/** A row of choices in a paper-3 track; the picked one stands on paper with a hairline. */
@Composable
fun ZenSegments(options: List<String>, selected: Int, onSelect: (Int) -> Unit, modifier: Modifier = Modifier) {
    val z = Zen.colors
    Row(modifier.background(z.paper3, RoundedCornerShape(Zen.control)).padding(2.dp)) {
        options.forEachIndexed { i, label ->
            val on = i == selected
            Box(
                Modifier
                    .height(32.dp)
                    .clip(RoundedCornerShape(8.dp))
                    .background(if (on) z.paper else Color.Transparent)
                    .then(if (on) Modifier.border(1.dp, z.rule, RoundedCornerShape(8.dp)) else Modifier)
                    .clickable { onSelect(i) }
                    .semantics { this.selected = on }
                    .padding(horizontal = 16.dp),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    label,
                    style = MaterialTheme.typography.labelMedium,
                    fontWeight = if (on) FontWeight.SemiBold else FontWeight.Normal,
                    color = if (on) z.ink else z.ink2,
                )
            }
        }
    }
}

/** A choice in a hairline; filled with paper-3 while it is the one picked. */
@Composable
private fun ZenChip(label: String, selected: Boolean, onClick: () -> Unit) {
    val z = Zen.colors
    Box(
        Modifier
            .height(32.dp)
            .clip(RoundedCornerShape(8.dp))
            .background(if (selected) z.paper3 else Color.Transparent)
            .border(1.dp, if (selected) z.ink2 else z.rule, RoundedCornerShape(8.dp))
            .clickable(onClick = onClick)
            .semantics { this.selected = selected }
            .padding(horizontal = 12.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            label,
            style = MaterialTheme.typography.labelMedium,
            fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal,
            color = if (selected) z.ink else z.ink2,
        )
    }
}

/** "7", "2.2": a width in points, whole when it is whole. */
internal fun widthText(width: Float): String =
    if (abs(width - width.roundToInt()) < 0.05f) width.roundToInt().toString() else String.format(Locale.ROOT, "%.1f", width)

// MARK: The pen's settings

@Composable
private fun PenSettings(state: EditorState, brush: Brush) {
    val z = Zen.colors
    val color = state.color(brush)
    val width = state.width(brush)
    val starred = state.isFavorite(brush)
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(brush.localizedTitle(), style = MaterialTheme.typography.titleMedium, color = z.ink, modifier = Modifier.weight(1f))
            if (brush.isPremium) Text(stringResource(R.string.pro), style = MaterialTheme.typography.labelSmall, color = z.muted)
        }
        Text(stringResource(brush.descriptionRes), style = MaterialTheme.typography.bodyMedium, color = z.ink2)
    }
    InkSample(brush, color, width)
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        LabelRow(stringResource(R.string.color))
        Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            brush.palette.forEachIndexed { index, c ->
                Swatch(c, selected = c == color, label = stringResource(R.string.color_number, index + 1)) { state.setColor(brush, c) }
            }
        }
    }
    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
        LabelRow(stringResource(R.string.pen_width), widthText(width))
        ZenSlider(width, { state.setWidth(brush, it) }, brush.widthRange, stringResource(R.string.pen_width))
    }
    Row(
        Modifier.fillMaxWidth().padding(top = 4.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(stringResource(R.string.favorite), style = MaterialTheme.typography.bodyLarge, color = z.ink2)
        ZenSwitch(starred) { state.toggleFavorite(brush) }
    }
}

/** One of the pen's six colours, 32 dp; the picked one in a ring of ink-2 a little way out. */
@Composable
private fun Swatch(color: InkColor, selected: Boolean, label: String, onClick: () -> Unit) {
    val z = Zen.colors
    Box(
        Modifier
            .size(40.dp)
            .then(if (selected) Modifier.border(2.dp, z.ink2, CircleShape) else Modifier)
            .padding(4.dp)
            .clip(CircleShape)
            .background(color.toColor())
            .border(1.dp, z.ink.copy(alpha = 0.12f), CircleShape)
            .clickable(onClick = onClick)
            .semantics {
                contentDescription = label
                this.selected = selected
            },
    )
}

/** The ink as it lands: a wave in the pen, its colour and width, drawn by FlatInk on paper. */
@Composable
private fun InkSample(brush: Brush, color: InkColor, width: Float) {
    val z = Zen.colors
    val density = LocalDensity.current.density
    val image = remember(brush, color, width, density) { renderInkSample(brush, color, width, density) }
    Image(
        image, contentDescription = null, contentScale = ContentScale.FillWidth,
        modifier = Modifier
            .fillMaxWidth()
            .height(InkSampleHeight.dp)
            .clip(RoundedCornerShape(12.dp))
            .border(1.dp, z.rule, RoundedCornerShape(12.dp)),
    )
}

private const val InkSampleWidth = 288f
private const val InkSampleHeight = 120f

/** The page's points are about 1.4 dp on a tablet at the fitting zoom; the sample keeps that scale. */
private const val InkSampleScale = 1.4f

private fun renderInkSample(brush: Brush, color: InkColor, width: Float, density: Float): ImageBitmap {
    val bitmap = Bitmap.createBitmap((InkSampleWidth * density).toInt(), (InkSampleHeight * density).toInt(), Bitmap.Config.ARGB_8888)
    bitmap.eraseColor(android.graphics.Color.WHITE)
    val canvas = android.graphics.Canvas(bitmap)
    canvas.scale(density * InkSampleScale, density * InkSampleScale)
    val w = InkSampleWidth / InkSampleScale
    val h = InkSampleHeight / InkSampleScale
    val r = max(width * 0.5f, 0.35f)
    val count = 120
    val points = (0..count).map { i ->
        val t = i.toFloat() / count
        InkPoint(w * (0.08f + 0.84f * t), h * (0.5f + 0.2f * sin(t * 2.0 * PI * 1.5).toFloat()), r, 0.55f)
    }
    // Born a minute ago: wet ink dry, lava cooled, as the iPad's settings show them.
    FlatInk.draw(listOf(Stroke(brush, color, width, referenceNow() - 60.0, 0.37f, points)), canvas)
    return bitmap.asImageBitmap()
}

// MARK: The eraser's settings

@Composable
private fun EraserSettings(state: EditorState) {
    val z = Zen.colors
    Text(stringResource(R.string.eraser), style = MaterialTheme.typography.titleMedium, color = z.ink)
    ZenSegments(
        options = listOf(stringResource(R.string.eraser_whole_stroke), stringResource(R.string.eraser_partial)),
        selected = if (state.eraserMode == EraserMode.STROKE) 0 else 1,
        onSelect = { state.eraserMode = if (it == 0) EraserMode.STROKE else EraserMode.PARTIAL },
    )
    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
        LabelRow(stringResource(R.string.eraser_size), widthText(state.eraserSize))
        ZenSlider(state.eraserSize, { state.eraserSize = it }, 4f..64f, stringResource(R.string.eraser_size))
    }
    Text(stringResource(R.string.eraser_help), style = MaterialTheme.typography.bodySmall, color = z.muted)
}

// MARK: The shape tool's settings

@Composable
private fun ShapeSettings(state: EditorState) {
    val z = Zen.colors
    Text(stringResource(R.string.shapes), style = MaterialTheme.typography.titleMedium, color = z.ink)
    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        for (kind in ShapeKind.entries) {
            ZenChip(kind.shapeName.localizedTitle(), selected = state.shapeKind == kind) { state.shapeKind = kind }
        }
    }
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
        Text(stringResource(R.string.dashed_line), style = MaterialTheme.typography.bodyLarge, color = z.ink2)
        ZenSwitch(state.shapeDashed) { state.shapeDashed = it }
    }
    if (state.shapeKind == ShapeKind.POLYGON) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
            Text(stringResource(R.string.polygon_sides, state.polygonSides), style = MaterialTheme.typography.bodyLarge, color = z.ink2)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Stepper(Icons.Outlined.Remove, enabled = state.polygonSides > 3) { state.polygonSides = (state.polygonSides - 1).coerceAtLeast(3) }
                Stepper(Icons.Outlined.Add, enabled = state.polygonSides < 12) { state.polygonSides = (state.polygonSides + 1).coerceAtMost(12) }
            }
        }
    }
    Text(stringResource(R.string.shapes_help), style = MaterialTheme.typography.bodySmall, color = z.muted)
}

@Composable
private fun Stepper(icon: ImageVector, enabled: Boolean, onClick: () -> Unit) {
    val z = Zen.colors
    Box(
        Modifier
            .size(36.dp)
            .clip(RoundedCornerShape(8.dp))
            .border(1.dp, z.rule, RoundedCornerShape(8.dp))
            .clickable(enabled = enabled, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, contentDescription = null, tint = if (enabled) z.ink2 else z.rule, modifier = Modifier.size(18.dp))
    }
}

// MARK: Every pen

/** Every pen by group, six to a row: a tap picks one, a long press stars it. */
@Composable
private fun AllPens(state: EditorState, onPicked: () -> Unit) {
    val z = Zen.colors
    val tool = state.tool
    Text(stringResource(R.string.all_pens), style = MaterialTheme.typography.titleMedium, color = z.ink)
    Column(
        Modifier.heightIn(max = 560.dp).verticalScroll(rememberScrollState()),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        for (group in BrushGroup.entries) {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(group.localizedTitle(), style = MaterialTheme.typography.labelMedium, color = z.muted)
                for (row in group.brushes.chunked(6)) {
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        for (brush in row) {
                            PenTile(
                                brush = brush,
                                ink = state.color(brush).toColor(),
                                selected = tool is Tool.Brush && tool.brush == brush,
                                starred = state.isFavorite(brush),
                                onTap = {
                                    state.tool = Tool.Brush(brush)
                                    onPicked()
                                },
                                onLongPress = { state.toggleFavorite(brush) },
                            )
                        }
                    }
                }
            }
        }
    }
}

/** A pen's silhouette over its name, 70 dp wide; the picked one in a ring of the accent. */
@Composable
private fun PenTile(brush: Brush, ink: Color, selected: Boolean, starred: Boolean, onTap: () -> Unit, onLongPress: () -> Unit) {
    val z = Zen.colors
    // The configuration is a key so that a language change, which does not make the activity again
    // (the manifest's configChanges), names the pens of an open sheet anew: localizedTitle() reads
    // the locale, which Compose does not watch, and nothing else here reads a string resource.
    val name = remember(brush, LocalConfiguration.current) { brush.localizedTitle() }
    Column(
        Modifier
            .width(70.dp)
            .clip(RoundedCornerShape(Zen.control))
            .background(if (selected) z.paper3 else Color.Transparent)
            .border(1.dp, if (selected) z.accent else Color.Transparent, RoundedCornerShape(Zen.control))
            .combinedClickable(onClick = onTap, onLongClick = onLongPress)
            .semantics {
                contentDescription = name
                this.selected = selected
            }
            .padding(vertical = 6.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(Modifier.size(24.dp, 40.dp).clipToBounds()) {
            if (z.proTheme) {
                Box(Modifier.offset(x = (-3).dp)) { ToolArtwork(brush, ink) }
            } else {
                PenSilhouetteArt(brush, ink)
            }
            if (starred) {
                Icon(Icons.Filled.Star, contentDescription = null, tint = z.muted, modifier = Modifier.align(Alignment.TopEnd).size(8.dp))
            }
        }
        Spacer(Modifier.height(4.dp))
        Text(
            name,
            style = MaterialTheme.typography.labelSmall,
            color = if (selected) z.ink else z.ink2,
            textAlign = TextAlign.Center,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.height(32.dp).padding(horizontal = 2.dp),
        )
    }
}
