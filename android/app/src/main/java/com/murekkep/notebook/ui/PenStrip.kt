@file:OptIn(
    androidx.compose.material3.ExperimentalMaterial3Api::class,
    androidx.compose.foundation.layout.ExperimentalLayoutApi::class,
    androidx.compose.foundation.ExperimentalFoundationApi::class,
)

package com.murekkep.notebook.ui

import android.os.Build
import android.view.HapticFeedbackConstants
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
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
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
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
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.Redo
import androidx.compose.material.icons.automirrored.outlined.Undo
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.DensityMedium
import androidx.compose.material.icons.outlined.FavoriteBorder
import androidx.compose.material.icons.outlined.HeartBroken
import androidx.compose.material.icons.outlined.NoteAdd
import androidx.compose.material.icons.outlined.Remove
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
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.PointerEventTimeoutCancellationException
import androidx.compose.ui.input.pointer.PointerInputChange
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChange
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.ui.layout.layout
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.paneTitle
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
import androidx.compose.ui.unit.min
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Popup
import androidx.compose.ui.window.PopupPositionProvider
import androidx.compose.ui.window.PopupProperties
import com.murekkep.notebook.R
import com.murekkep.notebook.ink.Brush
import com.murekkep.notebook.ink.EraserMode
import com.murekkep.notebook.ink.InkColor
import com.murekkep.notebook.ink.ShapeKind
import com.murekkep.notebook.ink.ShapeName
import java.util.Locale
import kotlin.math.max
import kotlin.math.roundToInt

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
// the grid button opens every pen (PenPanel.kt).

fun InkColor.toColor(): Color = Color(r, g, b, a)

private val isTurkish: Boolean
    get() = Locale.getDefault().language == "tr"

/** The pen's name in the user's language: Turkish, else English. */
fun Brush.localizedTitle(): String = if (isTurkish) titleTr else titleEn

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
            val allPens = stringResource(R.string.all_pens)
            BarButton(allPens, selected = sheet == Sheet.ALL_PENS, onClick = { sheet = Sheet.ALL_PENS }) {
                AllPensGlyph(LocalContentColor.current)
                if (sheet == Sheet.ALL_PENS) {
                    BarPopover(edge, popoverRoom, allPens, onDismiss = close, width = 548.dp, padding = 0.dp, spacing = 0.dp) { PenPanel(state, onPicked = close) }
                }
            }
            BarDivider(vertical)
            val active = state.activeBrush
            ColorDot(state.color(active).toColor(), onClick = { sheet = Sheet.PEN_FROM_DOT }) {
                if (sheet == Sheet.PEN_FROM_DOT) {
                    BarPopover(edge, min(popoverRoom, PenCardHeight), stringResource(R.string.pen_settings, active.localizedTitle()), onDismiss = close) {
                        PenSettings(state, active)
                    }
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
                    BarPopover(edge, popoverRoom, stringResource(R.string.shape_settings), onDismiss = close, width = 360.dp, padding = 18.dp, spacing = 14.dp) {
                        ShapeSettings(state, close)
                    }
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
                BarPopover(edge, min(popoverRoom, PenCardHeight), stringResource(R.string.pen_settings, brush.localizedTitle()), onDismiss = close) {
                    PenSettings(state, brush)
                }
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
                BarPopover(edge, popoverRoom, stringResource(R.string.eraser_settings), onDismiss = close) { EraserSettings(state) }
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
    // The gesture runs on across recompositions, so it calls the latest callbacks: a turned tablet
    // or a resized window hands new ones, which know the canvas's new size.
    val move by rememberUpdatedState(onMove)
    val drop by rememberUpdatedState(onDrop)
    val cancel by rememberUpdatedState(onCancel)
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
                    move(finger, moved)
                    val lifted = drag(first.id) { change ->
                        moved += change.positionChange()
                        change.consume()
                        anchor.coordinates?.let { finger = it.localToRoot(change.position) }
                        move(finger, moved)
                    }
                    if (lifted) drop(finger) else cancel()
                }
            }
            .semantics {
                contentDescription = "$label. $hint"
                customActions = moves
            },
        contentAlignment = Alignment.Center,
    ) {
        Box(Modifier.size(if (vertical) 22.dp else 4.dp, if (vertical) 4.dp else 22.dp).background(z.muted.copy(alpha = 0.5f), CircleShape))
        ZenMenu(expanded = menu, onDismissRequest = { menu = false }) {
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
            ZenMenu(expanded = menu, onDismissRequest = { menu = false }) {
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

/** The pen's card is no taller than the iPad's (it scrolls past it). */
private val PenCardHeight = 600.dp

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
 * a tap outside (its shadow's margin included, which lies over the bar beside the anchor) or Back;
 * taller than [maxHeight], it scrolls. TalkBack names it [title] as it opens.
 */
@Composable
private fun BarPopover(
    edge: PaletteEdge,
    maxHeight: Dp,
    title: String,
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
    // Not clipped to the screen: the shadow's margin may run past its edge while BesideAnchor keeps
    // the card inside, so the system does not push the whole window (and the card) back in.
    Popup(popupPositionProvider = provider, onDismissRequest = onDismiss, properties = PopupProperties(focusable = true, clippingEnabled = false)) {
        Box(Modifier.dismissInMargin(PopoverShadowPad, onDismiss).padding(PopoverShadowPad)) {
            Column(
                Modifier
                    .semantics { paneTitle = title }
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
internal fun LabelRow(label: String, value: String? = null) {
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

/** The system's light grey fill (a switch's off track, a stepper), lighter than the card at night too. */
internal fun systemFill(dark: Boolean): Color = if (dark) Color(0xFF39393D) else Color(0xFFE9E9EA)

/**
 * A switch in the accent; off, a white knob of the same size on the system's light grey track, as
 * iOS draws one. [onChange] null leaves the touch to the row it stands in ([SwitchRow]), which
 * TalkBack then reads as one switch with its name.
 */
@Composable
fun ZenSwitch(checked: Boolean, onChange: ((Boolean) -> Unit)?) {
    val z = Zen.colors
    Switch(
        checked = checked,
        onCheckedChange = onChange,
        // Any thumb content keeps the knob at its full 24 dp when off.
        thumbContent = {},
        colors = SwitchDefaults.colors(
            checkedTrackColor = z.accent, checkedThumbColor = Color.White, checkedBorderColor = z.accent,
            uncheckedTrackColor = systemFill(z.dark), uncheckedThumbColor = Color.White, uncheckedBorderColor = Color.Transparent,
        ),
    )
}

/**
 * A switch's row, as the iPad's Toggle with its label: [label] (it takes the room left), then the
 * switch. The row takes the touch and is one switch for TalkBack, named by its text.
 */
@Composable
fun SwitchRow(checked: Boolean, onChange: (Boolean) -> Unit, modifier: Modifier = Modifier, label: @Composable RowScope.() -> Unit) {
    Row(
        modifier
            .fillMaxWidth()
            .heightIn(min = Zen.target)
            // Only the switch moves, as on the iPad; the row does not light up.
            .toggleable(value = checked, interactionSource = remember { MutableInteractionSource() }, indication = null, role = Role.Switch, onValueChange = onChange),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        label()
        ZenSwitch(checked, null)
    }
}

/**
 * A row of equal choices in a paper-3 track, as wide as [modifier] makes it (the iPad's segmented
 * pickers fill their row), else as its widest choice allows; the picked one stands on paper with a
 * hairline.
 */
@Composable
fun ZenSegments(options: List<String>, selected: Int, onSelect: (Int) -> Unit, modifier: Modifier = Modifier) {
    val z = Zen.colors
    Row(modifier.width(IntrinsicSize.Max).background(z.paper3, RoundedCornerShape(Zen.control)).padding(2.dp)) {
        options.forEachIndexed { i, label ->
            val on = i == selected
            Box(
                Modifier
                    .weight(1f)
                    .height(32.dp)
                    .clip(RoundedCornerShape(8.dp))
                    .background(if (on) z.paper else Color.Transparent)
                    .then(if (on) Modifier.border(1.dp, z.rule, RoundedCornerShape(8.dp)) else Modifier)
                    .clickable { onSelect(i) }
                    .semantics { this.selected = on }
                    .padding(horizontal = 8.dp),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    label,
                    style = MaterialTheme.typography.labelMedium,
                    fontWeight = if (on) FontWeight.SemiBold else FontWeight.Normal,
                    color = if (on) z.ink else z.ink2,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
    }
}

// MARK: The eraser's settings

/** The eraser's card (EraserInspector on iPad): what it takes, its size in points, how to borrow it. */
@Composable
private fun EraserSettings(state: EditorState) {
    val z = Zen.colors
    Text(stringResource(R.string.eraser), style = MaterialTheme.typography.titleMedium, color = z.ink)
    ZenSegments(
        options = listOf(stringResource(R.string.eraser_whole_stroke), stringResource(R.string.eraser_partial)),
        selected = if (state.eraserMode == EraserMode.STROKE) 0 else 1,
        onSelect = { state.eraserMode = if (it == 0) EraserMode.STROKE else EraserMode.PARTIAL },
        modifier = Modifier.fillMaxWidth(),
    )
    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
        LabelRow(stringResource(R.string.eraser_size), state.eraserSize.roundToInt().toString())
        ZenSlider(state.eraserSize, { state.eraserSize = it }, 6f..60f, stringResource(R.string.eraser_size))
    }
    Text(stringResource(R.string.eraser_help), style = MaterialTheme.typography.bodySmall, color = z.muted)
}

// MARK: The shape tool's settings

/**
 * The shapes (ShapePicker on iPad): a tile for each, its glyph over its name, the one in use filled
 * with the accent; a tap takes the shape and closes the popover. Then the dashes, the polygon's
 * sides and how the tool works.
 */
@Composable
private fun ShapeSettings(state: EditorState, close: () -> Unit) {
    val z = Zen.colors
    Text(stringResource(R.string.shapes), style = MaterialTheme.typography.titleMedium, color = z.ink)
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        for (row in ShapeKind.entries.chunked(3)) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                for (kind in row) {
                    ShapeTile(kind, selected = state.shapeKind == kind, modifier = Modifier.weight(1f)) {
                        state.shapeKind = kind
                        if (state.tool !is Tool.Shape) state.tool = Tool.Shape
                        close()
                    }
                }
                repeat(3 - row.size) { Spacer(Modifier.weight(1f)) }
            }
        }
    }
    SwitchRow(state.shapeDashed, { state.shapeDashed = it }) {
        Icon(Icons.Outlined.DensityMedium, contentDescription = null, tint = z.ink2, modifier = Modifier.size(22.dp))
        Spacer(Modifier.width(12.dp))
        Text(stringResource(R.string.dashed_line), style = MaterialTheme.typography.bodyLarge, color = z.ink2, modifier = Modifier.weight(1f))
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

/** A shape's tile: its glyph over its name in two lines at most; the one in use in the accent with white. */
@Composable
private fun ShapeTile(kind: ShapeKind, selected: Boolean, modifier: Modifier, onClick: () -> Unit) {
    val z = Zen.colors
    val shape = RoundedCornerShape(Zen.control)
    val content = if (selected) Color.White else z.ink2
    Column(
        modifier
            .heightIn(min = 64.dp)
            .clip(shape)
            .background(if (selected) z.accent else z.paper2)
            .then(if (selected) Modifier else Modifier.border(1.dp, z.rule, shape))
            .clickable(onClick = onClick)
            .semantics { this.selected = selected }
            .padding(horizontal = 4.dp, vertical = 8.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(5.dp, Alignment.CenterVertically),
    ) {
        ShapeGlyph(kind, content, size = 24.dp)
        Text(
            kind.shapeName.localizedTitle(),
            style = MaterialTheme.typography.labelSmall.copy(fontSize = 11.sp, lineHeight = 13.sp, fontWeight = FontWeight.Normal),
            color = content,
            textAlign = TextAlign.Center,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

@Composable
private fun Stepper(icon: ImageVector, enabled: Boolean, onClick: () -> Unit) {
    val z = Zen.colors
    Box(
        Modifier
            .size(36.dp)
            .clip(RoundedCornerShape(Zen.control))
            .border(1.dp, z.rule, RoundedCornerShape(Zen.control))
            .clickable(enabled = enabled, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, contentDescription = null, tint = if (enabled) z.ink2 else z.rule, modifier = Modifier.size(18.dp))
    }
}
