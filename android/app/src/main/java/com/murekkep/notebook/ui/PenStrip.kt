@file:OptIn(
    androidx.compose.material3.ExperimentalMaterial3Api::class,
    androidx.compose.foundation.layout.ExperimentalLayoutApi::class,
    androidx.compose.foundation.ExperimentalFoundationApi::class,
)

package com.murekkep.notebook.ui

import android.graphics.Bitmap
import android.os.Build
import android.view.HapticFeedbackConstants
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.awaitTouchSlopOrCancellation
import androidx.compose.foundation.gestures.drag
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.wrapContentHeight
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.Redo
import androidx.compose.material.icons.automirrored.outlined.Undo
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.FavoriteBorder
import androidx.compose.material.icons.outlined.HeartBroken
import androidx.compose.material.icons.outlined.NoteAdd
import androidx.compose.material.icons.outlined.Remove
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
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
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.PointerEventTimeoutCancellationException
import androidx.compose.ui.input.pointer.PointerInputChange
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChange
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.ui.layout.layout
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Constraints
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

// The editor's floating pen bar (the spec's "kalem rafı"; FloatingToolPalette and PenStrip on iPad,
// Murekkep.swiftpm/ToolPalette.swift and PenStrip.swift), along the bottom by default, along the top
// or upright down the right side: its grip, Geri al and Yinele | the pens (the favourites, a hairline,
// the pens used last) and the eraser standing in a low tray, the picked one raised, Tüm kalemler | the
// ink's colour | Kement, Şekiller, Sayfa ekle, and the fold. Folded it keeps the grip, undo and redo
// and the ink and tool in hand. The grip carries the bar to another edge; a long press on it offers
// the three. In black and white the pens are flat silhouettes (PenSilhouettes.kt); a Pro theme draws
// the iPad's realistic bodies (ToolArt.kt). A second tap on the picked pen, or a tap on the colour,
// opens the pen's settings in a popover on the page's side of the bar; a long press on a pen adds it
// to the favourites or takes it away. The eraser's and the shapes' settings open from their buttons;
// the grid button opens every pen.

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

/** The bar's thickness: its height along the top or the bottom, its width down the right side. */
val PenBarHeight = 64.dp

/** How far the bar floats above the bottom of the page. */
val PenBarMargin = 18.dp

/** The light tick of a pick (the iPad's selection feedback): a tool or a colour taken. */
@Composable
internal fun rememberSelectionTick(): () -> Unit {
    val view = LocalView.current
    return remember(view) {
        { view.performHapticFeedback(if (Build.VERSION.SDK_INT >= 34) HapticFeedbackConstants.SEGMENT_FREQUENT_TICK else HapticFeedbackConstants.CLOCK_TICK) }
    }
}

// MARK: The bar

/** What the bar has open; one thing at a time. */
private enum class Sheet { PEN_FROM_SLOT, PEN_FROM_DOT, ERASER, SHAPES, ALL_PENS }

/**
 * The floating pen bar on `state.paletteEdge`: a row along the top or the bottom, a column down the
 * right side. Its grip reports the finger's drag in root coordinates ([onGripMove] with how far it
 * moved, then [onGripDrop] where it let go, or [onGripCancel]); its long press docks the bar from a
 * menu. [popoverRoom] is the height the window leaves a popover beside the bar.
 */
@Composable
fun PenBar(
    state: EditorState,
    popoverRoom: Dp,
    onGripMove: (finger: Offset, moved: Offset) -> Unit,
    onGripDrop: (finger: Offset) -> Unit,
    onGripCancel: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val edge = state.paletteEdge
    val vertical = edge.isVertical
    var sheet by remember { mutableStateOf<Sheet?>(null) }
    val grip = @Composable {
        Grip(edge, onGripMove, onGripDrop, onGripCancel) { place ->
            sheet = null
            state.paletteEdge = place
        }
    }
    BoxWithConstraints(modifier) {
        val surface = Modifier
            .floating(Zen.bar)
            // Every touch on the bar stays on it: none falls through to the page beneath.
            .pointerInput(Unit) {}
            .then(if (vertical) Modifier.width(PenBarHeight).padding(vertical = 10.dp) else Modifier.height(PenBarHeight).padding(horizontal = 10.dp))
        if (state.paletteCollapsed) {
            BarLine(vertical, surface, spacing = 8.dp) {
                grip()
                UndoRedo(state, vertical)
                BarDivider(vertical)
                FoldedTool(state, edge) { state.paletteCollapsed = false }
            }
            return@BoxWithConstraints
        }
        // The pens scroll inside what the rest leaves them; a window too small for the rest scrolls the whole bar.
        val fits = (if (vertical) maxHeight else maxWidth) >= fixedLength(addPage = !state.isPdf) + MinPensRoom
        val scroll = rememberScrollState()
        val line = when {
            fits -> surface
            vertical -> surface.verticalScroll(scroll)
            else -> surface.horizontalScroll(scroll)
        }
        val tool = state.tool
        val close = { sheet = null }
        val tick = rememberSelectionTick()
        BarLine(vertical, line, spacing = 2.dp) { weighted ->
            grip()
            UndoRedo(state, vertical)
            BarDivider(vertical)
            PenTray(state, edge, sheet, { sheet = it }, popoverRoom, if (fits) weighted else Modifier)
            BarButton(stringResource(R.string.all_pens), selected = sheet == Sheet.ALL_PENS, onClick = { sheet = Sheet.ALL_PENS }) {
                AllPensGlyph(LocalContentColor.current)
                if (sheet == Sheet.ALL_PENS) {
                    BarPopover(edge, popoverRoom, onDismiss = close, width = 482.dp) { AllPens(state, onPicked = close) }
                }
            }
            BarDivider(vertical)
            val active = state.activeBrush
            ColorDot(state.color(active).toColor(), onClick = { sheet = Sheet.PEN_FROM_DOT }) {
                if (sheet == Sheet.PEN_FROM_DOT) {
                    BarPopover(edge, popoverRoom, onDismiss = close) { PenSettings(state, active) }
                }
            }
            BarDivider(vertical)
            BarButton(
                stringResource(R.string.lasso),
                selected = tool is Tool.Lasso,
                onClick = {
                    state.tool = if (tool is Tool.Lasso) Tool.Brush(state.lastBrush) else Tool.Lasso
                    tick()
                },
            ) { LassoGlyph(Modifier.size(22.dp), LocalContentColor.current) }
            BarButton(
                stringResource(R.string.bar_shape_in_use, state.shapeKind.shapeName.localizedTitle()),
                selected = tool is Tool.Shape,
                onClick = {
                    if (tool !is Tool.Shape) {
                        state.tool = Tool.Shape
                        tick()
                    }
                    sheet = Sheet.SHAPES
                },
            ) {
                ShapeGlyph(state.shapeKind, LocalContentColor.current)
                if (sheet == Sheet.SHAPES) {
                    BarPopover(edge, popoverRoom, onDismiss = close) { ShapeSettings(state) }
                }
            }
            if (!state.isPdf) {
                BarButton(stringResource(R.string.add_page), enabled = !state.readOnly, onClick = state::addPage) {
                    Icon(Icons.Outlined.NoteAdd, contentDescription = null, modifier = Modifier.size(22.dp))
                }
            }
            FoldButton(edge) {
                sheet = null
                state.paletteCollapsed = true
            }
        }
    }
}

// The iPad's sizes along the bar (FloatingToolPalette): its padding, the grip, a divider with its
// margins, the fold and the gap between them.
private val BarPadding = 10.dp
private val GripLength = 16.dp
private val DividerLength = 13.dp
private val FoldLength = 26.dp
private val BarGap = 2.dp

/** Room for two pens in the tray at least: its padding, two pens and the gap between them. */
private val MinPensRoom = 72.dp

/** The full bar's length without its pens: grip, undo and redo, three dividers, every pen, the
 *  colour, the lasso, the shapes, Sayfa ekle, the fold and the gaps between them. */
private fun fixedLength(addPage: Boolean): Dp {
    val buttons = if (addPage) 7 else 6
    val items = buttons + 5
    return BarPadding * 2 + GripLength + Zen.target * buttons + DividerLength * 3 + FoldLength + BarGap * (items - 1)
}

/** A row along the top or the bottom, a column down the right side; [content] gets the modifier that
 *  lets a child take what the others leave. */
@Composable
private fun BarLine(vertical: Boolean, modifier: Modifier, spacing: Dp, content: @Composable (weighted: Modifier) -> Unit) {
    if (vertical) {
        Column(modifier, Arrangement.spacedBy(spacing), Alignment.CenterHorizontally) { content(Modifier.weight(1f, fill = false)) }
    } else {
        Row(modifier, Arrangement.spacedBy(spacing), Alignment.CenterVertically) { content(Modifier.weight(1f, fill = false)) }
    }
}

@Composable
private fun UndoRedo(state: EditorState, vertical: Boolean) {
    BarLine(vertical, Modifier, spacing = 0.dp) {
        BarButton(stringResource(R.string.undo), enabled = state.canUndo, onClick = state::undo) {
            Icon(Icons.AutoMirrored.Outlined.Undo, contentDescription = null, modifier = Modifier.size(22.dp))
        }
        BarButton(stringResource(R.string.redo), enabled = state.canRedo, onClick = state::redo) {
            Icon(Icons.AutoMirrored.Outlined.Redo, contentDescription = null, modifier = Modifier.size(22.dp))
        }
    }
}

/**
 * The pens of the bar, then the eraser, in a tray that scrolls when they run long (560 dp along the top
 * or the bottom, 440 down the side): the favourites, a hairline, the pens used last. A picked pen
 * stands out toward the page.
 */
@Composable
private fun PenTray(state: EditorState, edge: PaletteEdge, sheet: Sheet?, setSheet: (Sheet?) -> Unit, popoverRoom: Dp, modifier: Modifier) {
    val vertical = edge.isVertical
    val tool = state.tool
    val (favorites, recent) = state.barPens
    val tick = rememberSelectionTick()
    val close = { setSheet(null) }

    @Composable
    fun pen(brush: Brush) {
        val selected = tool is Tool.Brush && tool.brush == brush
        PenSlot(
            brush = brush,
            ink = state.color(brush).toColor(),
            selected = selected,
            vertical = vertical,
            onTap = {
                if (selected) {
                    setSheet(Sheet.PEN_FROM_SLOT)
                } else {
                    state.tool = Tool.Brush(brush)
                    tick()
                }
            },
            favorite = state.isFavorite(brush),
            onToggleFavorite = { state.toggleFavorite(brush) },
        ) {
            if (sheet == Sheet.PEN_FROM_SLOT && selected) {
                BarPopover(edge, popoverRoom, onDismiss = close) { PenSettings(state, brush) }
            }
        }
    }

    val pens = @Composable {
        for (brush in favorites) pen(brush)
        if (favorites.isNotEmpty() && recent.isNotEmpty()) TrayHairline(vertical)
        for (brush in recent) pen(brush)
        PenSlot(
            brush = null,
            ink = Color.Transparent,
            selected = tool is Tool.Eraser,
            vertical = vertical,
            onTap = {
                if (tool is Tool.Eraser) {
                    setSheet(Sheet.ERASER)
                } else {
                    state.toggleEraser()
                    tick()
                }
            },
            favorite = null,
        ) {
            if (sheet == Sheet.ERASER) {
                BarPopover(edge, popoverRoom, onDismiss = close) { EraserSettings(state) }
            }
        }
    }
    val scroll = rememberScrollState()
    if (vertical) {
        Column(
            modifier.heightIn(max = 440.dp).verticalScroll(scroll).width(PenBarHeight).padding(vertical = 4.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp),
            horizontalAlignment = Alignment.End,
        ) { pens() }
    } else {
        Row(
            modifier.widthIn(max = 560.dp).horizontalScroll(scroll).height(PenBarHeight).padding(horizontal = 4.dp),
            horizontalArrangement = Arrangement.spacedBy(4.dp),
            verticalAlignment = Alignment.Bottom,
        ) { pens() }
    }
}

/** The hairline between the favourites and the pens used last. */
@Composable
private fun TrayHairline(vertical: Boolean) {
    val line = if (vertical) {
        Modifier.padding(vertical = 3.dp).padding(end = 10.dp).size(28.dp, 1.dp)
    } else {
        Modifier.padding(horizontal = 3.dp).padding(bottom = 10.dp).size(1.dp, 28.dp)
    }
    Box(line.background(Zen.colors.rule))
}

/** A 44 dp button of the bar: its glyph in ink-2; in the accent on a faint accent square while its tool is in hand. */
@Composable
fun BarButton(
    label: String,
    selected: Boolean = false,
    enabled: Boolean = true,
    onClick: () -> Unit,
    content: @Composable BoxScope.() -> Unit,
) {
    val z = Zen.colors
    val tint = when {
        !enabled -> z.rule
        selected -> z.accent
        else -> z.ink2
    }
    Box(
        Modifier
            .size(Zen.target)
            .clip(RoundedCornerShape(Zen.control))
            .background(if (selected) z.accent.copy(alpha = 0.10f) else Color.Transparent)
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
private fun BarDivider(vertical: Boolean) {
    val line = if (vertical) Modifier.padding(vertical = 6.dp).size(28.dp, 1.dp) else Modifier.padding(horizontal = 6.dp).size(1.dp, 28.dp)
    Box(line.background(Zen.colors.rule))
}

/** The grip's place in the menu. */
private val PaletteEdge.moveTitle: Int
    get() = when (this) {
        PaletteEdge.TOP -> R.string.bar_to_top
        PaletteEdge.BOTTOM -> R.string.bar_to_bottom
        PaletteEdge.TRAILING -> R.string.bar_to_right
    }

/**
 * The grip at the bar's start: a short capsule in a 16 x 44 target (44 x 16 upright). Dragged, it
 * reports the finger and how far it moved; held, it opens a menu with the three edges, the one the bar
 * stands on greyed out.
 */
@Composable
private fun Grip(
    edge: PaletteEdge,
    onMove: (finger: Offset, moved: Offset) -> Unit,
    onDrop: (finger: Offset) -> Unit,
    onCancel: () -> Unit,
    onDock: (PaletteEdge) -> Unit,
) {
    val z = Zen.colors
    val vertical = edge.isVertical
    var menu by remember { mutableStateOf(false) }
    val anchor = remember { GripAnchor() }
    val label = stringResource(R.string.bar_move)
    val hint = stringResource(R.string.bar_move_hint)
    val moves = PaletteEdge.entries.filter { it != edge }.map { place ->
        CustomAccessibilityAction(stringResource(place.moveTitle)) {
            onDock(place)
            true
        }
    }
    Box(
        Modifier
            .size(if (vertical) 44.dp else GripLength, if (vertical) GripLength else 44.dp)
            .onGloballyPositioned { anchor.coordinates = it }
            .pointerInput(edge) {
                awaitEachGesture {
                    val down = awaitFirstDown(requireUnconsumed = false)
                    down.consume()
                    var start: PointerInputChange? = null
                    val held = try {
                        withTimeout(viewConfiguration.longPressTimeoutMillis) {
                            start = awaitTouchSlopOrCancellation(down.id) { change, _ -> change.consume() }
                        }
                        false
                    } catch (_: PointerEventTimeoutCancellationException) {
                        true
                    }
                    if (held) {
                        menu = true
                        // The rest of the touch belongs to the menu's opening.
                        do {
                            val event = awaitPointerEvent()
                            event.changes.forEach { it.consume() }
                        } while (event.changes.any { it.pressed })
                        return@awaitEachGesture
                    }
                    val first = start ?: return@awaitEachGesture
                    var moved = first.position - down.position
                    var finger = anchor.coordinates?.localToRoot(first.position) ?: return@awaitEachGesture
                    onMove(finger, moved)
                    val lifted = drag(first.id) { change ->
                        moved += change.positionChange()
                        change.consume()
                        anchor.coordinates?.let { finger = it.localToRoot(change.position) }
                        onMove(finger, moved)
                    }
                    if (lifted) onDrop(finger) else onCancel()
                }
            }
            .semantics {
                contentDescription = "$label. $hint"
                customActions = moves
            },
        contentAlignment = Alignment.Center,
    ) {
        Box(Modifier.size(if (vertical) 22.dp else 4.dp, if (vertical) 4.dp else 22.dp).background(z.muted.copy(alpha = 0.5f), CircleShape))
        DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
            for (place in PaletteEdge.entries) {
                DropdownMenuItem(
                    text = { Text(stringResource(place.moveTitle)) },
                    trailingIcon = { EdgeGlyph(place, LocalContentColor.current) },
                    enabled = place != edge,
                    onClick = {
                        menu = false
                        onDock(place)
                    },
                )
            }
        }
    }
}

/** Where the grip is on screen, for the finger's place while it drags (kept out of Compose's state). */
private class GripAnchor {
    var coordinates: LayoutCoordinates? = null
}

/** Folding points at the bar's edge, unfolding at the page. */
private val PaletteEdge.fold: Chevron
    get() = when (this) {
        PaletteEdge.TOP -> Chevron.UP
        PaletteEdge.BOTTOM -> Chevron.DOWN
        PaletteEdge.TRAILING -> Chevron.RIGHT
    }

private val PaletteEdge.unfold: Chevron
    get() = when (this) {
        PaletteEdge.TOP -> Chevron.DOWN
        PaletteEdge.BOTTOM -> Chevron.UP
        PaletteEdge.TRAILING -> Chevron.LEFT
    }

/** The bar's last button: folds it. */
@Composable
private fun FoldButton(edge: PaletteEdge, onFold: () -> Unit) {
    val label = stringResource(R.string.bar_hide_tools)
    Box(
        Modifier
            .size(if (edge.isVertical) 44.dp else FoldLength, if (edge.isVertical) FoldLength else 44.dp)
            .clip(RoundedCornerShape(Zen.control))
            .clickable(onClick = onFold)
            .semantics { contentDescription = label },
        contentAlignment = Alignment.Center,
    ) {
        ChevronGlyph(edge.fold, Zen.colors.muted)
    }
}

/** The folded bar's button: the ink's dot, the tool in hand and a chevron; a tap unfolds the bar. */
@Composable
private fun FoldedTool(state: EditorState, edge: PaletteEdge, onUnfold: () -> Unit) {
    val z = Zen.colors
    val label = stringResource(R.string.bar_show_tools)
    Box(
        Modifier
            .defaultMinSize(minWidth = Zen.target, minHeight = Zen.target)
            .clip(RoundedCornerShape(Zen.control))
            .clickable(onClick = onUnfold)
            .semantics { contentDescription = label },
        contentAlignment = Alignment.Center,
    ) {
        BarLine(edge.isVertical, Modifier, spacing = 8.dp) {
            Box(Modifier.size(20.dp).background(state.color(state.activeBrush).toColor(), CircleShape).border(2.dp, z.paper, CircleShape))
            Box(Modifier.size(30.dp), contentAlignment = Alignment.Center) { ToolInHand(state) }
            ChevronGlyph(edge.unfold, z.muted)
        }
    }
}

/** The tool in hand in 30 dp: the pen or the eraser laid at an angle, else the tool's glyph. */
@Composable
private fun ToolInHand(state: EditorState) {
    val z = Zen.colors
    when (val tool = state.tool) {
        is Tool.Brush -> {
            val ink = state.color(tool.brush).toColor()
            if (z.proTheme) ToolIcon(tool.brush, ink, side = 30.dp) else PenIcon(tool.brush, ink)
        }
        Tool.Eraser -> if (z.proTheme) ToolIcon(null, Color.Transparent, side = 30.dp) else PenIcon(null, Color.Transparent)
        Tool.Lasso -> LassoGlyph(Modifier.size(18.dp), z.ink2)
        Tool.Shape -> ShapeToolGlyph(z.ink2)
    }
}

/** The numbers of the iPad's PenBodyView for a flat pen: resting 16 dp down its frame, raised to 2. */
private const val PEN_REST_Y = 16f
private const val PEN_RAISED_Y = 2f

/**
 * A pen standing in its frame (null: the eraser), the iPad's PenBodyView: 30 x 68 dp, the pen at its
 * top, resting low and raised on the iPad's spring while it is the one in hand. Black and white draws
 * its flat silhouette, a Pro theme its realistic body.
 */
@Composable
fun PenStand(brush: Brush?, ink: Color, selected: Boolean, modifier: Modifier = Modifier) {
    Box(modifier.size(30.dp, 68.dp), contentAlignment = Alignment.TopCenter) {
        if (Zen.colors.proTheme) {
            PenBody(brush, ink, selected)
        } else {
            val lift by animateFloatAsState(
                targetValue = if (selected) 1f else 0f,
                animationSpec = spring(dampingRatio = 0.7f, stiffness = springStiffness(0.32f)),
                label = "penLift",
            )
            val y = PEN_REST_Y + (PEN_RAISED_Y - PEN_REST_Y) * lift
            PenSilhouetteArt(brush, ink, selected, Modifier.offset { IntOffset(0, y.dp.roundToPx()) })
        }
    }
}

/** Down the right side a pen lies with its tip toward the page: its frame turned a quarter left and
 *  standing out of the column's right edge, as the iPad's 68 long pen in its 64 wide column. */
private fun Modifier.lyingInSlot(): Modifier = layout { measurable, _ ->
    val w = 30.dp.roundToPx()
    val h = 68.dp.roundToPx()
    val slotW = PenBarHeight.roundToPx()
    val slotH = 30.dp.roundToPx()
    val pen = measurable.measure(Constraints.fixed(w, h))
    layout(slotW, slotH) { pen.place(slotW - (w + h) / 2, (slotH - h) / 2) }
}.graphicsLayer { rotationZ = -90f }

/**
 * One pen in the tray (null: the eraser): 30 dp across, the bar's thickness long, the pen cut at the
 * tray's edge. A long press on a pen ([favorite] not null) opens its menu: add it to the favourites or
 * take it away. [popover] is the pen's settings when they are open, anchored to this slot.
 */
@Composable
private fun PenSlot(
    brush: Brush?,
    ink: Color,
    selected: Boolean,
    vertical: Boolean,
    onTap: () -> Unit,
    favorite: Boolean?,
    onToggleFavorite: () -> Unit = {},
    popover: @Composable BoxScope.() -> Unit,
) {
    val name = brush?.localizedTitle() ?: stringResource(R.string.eraser)
    val hint = stringResource(R.string.tap_again_settings)
    var menu by remember { mutableStateOf(false) }
    val favoriteLabel = favorite?.let { stringResource(if (it) R.string.remove_favorite else R.string.add_favorite) }
    Box(
        Modifier
            .then(if (vertical) Modifier.size(PenBarHeight, 30.dp) else Modifier.size(30.dp, PenBarHeight))
            .clipToBounds()
            .combinedClickable(
                onClick = onTap,
                onLongClick = if (favorite != null) ({ menu = true }) else null,
                onLongClickLabel = favoriteLabel,
            )
            .semantics {
                contentDescription = if (selected) "$name. $hint" else name
                this.selected = selected
            },
    ) {
        PenStand(
            brush, ink, selected,
            if (vertical) Modifier.lyingInSlot() else Modifier.align(Alignment.BottomCenter).wrapContentHeight(Alignment.Bottom, unbounded = true),
        )
        if (favorite != null && favoriteLabel != null) {
            DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                DropdownMenuItem(
                    text = { Text(favoriteLabel) },
                    trailingIcon = {
                        Icon(if (favorite) Icons.Outlined.HeartBroken else Icons.Outlined.FavoriteBorder, contentDescription = null)
                    },
                    onClick = {
                        menu = false
                        onToggleFavorite()
                    },
                )
            }
        }
        popover()
    }
}

/** The ink's colour in a hairline ring: opens the pen's settings. */
@Composable
private fun ColorDot(color: Color, onClick: () -> Unit, popover: @Composable BoxScope.() -> Unit) {
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
                .border(1.dp, z.rule, CircleShape)
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

/** How far a popover stands from its anchor, and at least from the window's edges. */
val PopoverGap = 12.dp
val PopoverMargin = 8.dp

/**
 * Puts a popover on the page's side of its anchor, [gap] away: above it along the bottom, below it
 * along the top, to its left down the right side; centred on it and kept inside the window by [margin].
 */
private class BesideAnchor(private val edge: PaletteEdge, private val pad: Int, private val gap: Int, private val margin: Int) : PopupPositionProvider {
    override fun calculatePosition(anchorBounds: IntRect, windowSize: IntSize, layoutDirection: LayoutDirection, popupContentSize: IntSize): IntOffset {
        val w = popupContentSize.width - 2 * pad
        val h = popupContentSize.height - 2 * pad
        val x = if (edge == PaletteEdge.TRAILING) anchorBounds.left - gap - w else anchorBounds.center.x - w / 2
        val y = when (edge) {
            PaletteEdge.BOTTOM -> anchorBounds.top - gap - h
            PaletteEdge.TOP -> anchorBounds.bottom + gap
            PaletteEdge.TRAILING -> anchorBounds.center.y - h / 2
        }
        val left = x.coerceIn(margin, max(margin, windowSize.width - w - margin))
        val top = y.coerceIn(margin, max(margin, windowSize.height - h - margin))
        return IntOffset(left - pad, top - pad)
    }
}

/**
 * A popover of the bar on [edge]: paper with a hairline and the float shadow, [width] wide, closed by
 * a tap outside or Back; taller than [maxHeight], it scrolls.
 */
@Composable
private fun BarPopover(
    edge: PaletteEdge,
    maxHeight: Dp,
    onDismiss: () -> Unit,
    width: Dp = 320.dp,
    padding: Dp = 16.dp,
    spacing: Dp = 16.dp,
    content: @Composable ColumnScope.() -> Unit,
) {
    val density = LocalDensity.current
    val provider = remember(density, edge) {
        with(density) { BesideAnchor(edge, PopoverShadowPad.roundToPx(), PopoverGap.roundToPx(), PopoverMargin.roundToPx()) }
    }
    Popup(popupPositionProvider = provider, onDismissRequest = onDismiss, properties = PopupProperties(focusable = true)) {
        Box(Modifier.padding(PopoverShadowPad)) {
            Column(
                Modifier
                    .width(width)
                    .heightIn(max = maxHeight)
                    .floating(Zen.popover)
                    .clip(RoundedCornerShape(Zen.popover))
                    .verticalScroll(rememberScrollState())
                    .padding(padding),
                verticalArrangement = Arrangement.spacedBy(spacing),
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

/** A thin slider in the accent on a rule track (the iPad's Slider takes the app's tint). */
@Composable
fun ZenSlider(value: Float, onChange: (Float) -> Unit, range: ClosedFloatingPointRange<Float>, label: String, modifier: Modifier = Modifier) {
    val z = Zen.colors
    val colors = SliderDefaults.colors(
        thumbColor = z.accent, activeTrackColor = z.accent, inactiveTrackColor = z.rule,
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
    val name = brush.localizedTitle()
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
                PenSilhouetteArt(brush, ink, selected)
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
