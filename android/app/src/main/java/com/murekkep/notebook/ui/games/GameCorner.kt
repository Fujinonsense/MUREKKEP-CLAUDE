package com.murekkep.notebook.ui.games

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.calculateEndPadding
import androidx.compose.foundation.layout.calculateStartPadding
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowLeft
import androidx.compose.material.icons.outlined.Apps
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.CloseFullscreen
import androidx.compose.material.icons.outlined.Grid3x3
import androidx.compose.material.icons.outlined.LocalCafe
import androidx.compose.material.icons.outlined.LooksOne
import androidx.compose.material.icons.outlined.OpenInFull
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material.icons.outlined.SportsEsports
import androidx.compose.material.icons.outlined.WaterDrop
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.paneTitle
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.murekkep.notebook.R
import com.murekkep.notebook.games.GamePanelSize
import com.murekkep.notebook.ui.PaletteEdge
import com.murekkep.notebook.ui.Zen
import com.murekkep.notebook.ui.ZenSegments
import com.murekkep.notebook.ui.floating
import com.murekkep.notebook.ui.springStiffness

// The break corner (the iPad's GameCorner.swift): a small tile at the bottom left of the page opens a
// card with the games to play: the ink bubbles, XOX and kare kapmaca against the device, Sudoku. Free,
// nothing leaves the device; what is kept (the difficulty, the best scores, wins and times, a
// half-done Sudoku) lives in the preferences under the iPad's keys (GameProgressStore). The card
// keeps every touch to itself, so no stroke reaches the page beneath; the pen plays like a finger.
// The iPad's things to make (Ebru, the living ink, the mandala) and its levelled games (the flying
// drop, the colour popper) are not on Android yet, so their tiles are not shown.

/** The two layers of the break card: games to play, and things to make. */
internal enum class BreakLayer(val raw: String, val title: Int) {
    GAMES("games", R.string.games_layer_games),
    CREATIVE("creative", R.string.games_layer_creative);

    companion object {
        fun fromRaw(raw: String?): BreakLayer = entries.firstOrNull { it.raw == raw } ?: GAMES
    }
}

/** The games of the break corner Android has, in the order the iPad's tiles stand. */
internal enum class MiniGame(val id: String, val layer: BreakLayer, val title: Int, val hint: Int, val icon: ImageVector) {
    BUBBLES("bubbles", BreakLayer.GAMES, R.string.games_bubbles, R.string.games_bubbles_hint, Icons.Outlined.WaterDrop),
    XOX("xox", BreakLayer.GAMES, R.string.games_xox, R.string.games_xox_hint, Icons.Outlined.Grid3x3),
    DOTS("dots", BreakLayer.GAMES, R.string.games_dots, R.string.games_dots_hint, Icons.Outlined.Apps),
    SUDOKU("sudoku", BreakLayer.GAMES, R.string.games_sudoku, R.string.games_sudoku_hint, Icons.Outlined.LooksOne);

    val hasDifficulty: Boolean get() = layer == BreakLayer.GAMES
}

/** The layers that have tiles on Android: the card shows its layer picker only when there are two. */
internal val shownLayers: List<BreakLayer> get() = BreakLayer.entries.filter { layer -> MiniGame.entries.any { it.layer == layer } }

/** The tile's hit area (44, the spec's target) and its margin from the canvas's corner. */
private val TileTarget = Zen.target
private val TileMargin = 6.dp
/** The panel's margin from the canvas's edges, and its gap above the tile. */
private val PanelMargin = 12.dp
private val PanelGap = 8.dp
/**
 * How high the lasso's bar reaches over a pen bar along the bottom while it shows: 52 up
 * (EditorScreen), 56 tall (its 44 dp actions, 6 above and below them).
 */
private val SelectionBarTop = 52.dp + 56.dp

/** The panel springs in and out from its corner (the iPad's spring: response 0.38, damping 0.82). */
private fun <T> cornerSpring() = spring<T>(dampingRatio = 0.82f, stiffness = springStiffness(0.38f))

/**
 * The break corner in the editor's canvas ([canvasWidth] x [canvasHeight]), over the page: the tile
 * at the bottom left, raised over a pen bar along the bottom by [bottomClearance], and the panel
 * above it, clear of the pen bar on [edge] and of the lasso's bar while [selectionBar] shows:
 * compact, or one step larger that is never more than a quarter of the canvas. Back leaves a game,
 * then closes the panel.
 */
@Composable
fun BreakCorner(edge: PaletteEdge, bottomClearance: Dp, canvasWidth: Dp, canvasHeight: Dp, selectionBar: Boolean = false) {
    val context = LocalContext.current
    val store = remember(context) { GameProgressStore(context) }
    var open by rememberSaveable { mutableStateOf(false) }
    var expanded by rememberSaveable { mutableStateOf(false) }
    val safe = WindowInsets.safeDrawing.asPaddingValues()
    val direction = LocalLayoutDirection.current
    val bottomInset = safe.calculateBottomPadding()
    val startInset = safe.calculateStartPadding(direction)
    val endInset = safe.calculateEndPadding(direction)
    // The room kept clear at each edge (the iPad's gamePanelSize): the pen bar along the top
    // (10 + 64 + 10) or down the side (12 + 64 + 14), the tile below. On a short canvas the panel
    // comes down over its tile, but never over a pen bar along the bottom, nor over the lasso's bar
    // while that shows (the iPad's, 104 up, clears its buttons): it rises to 8 over that bar, cut to
    // the room left.
    val leading = PanelMargin + startInset
    val trailing = (if (edge == PaletteEdge.TRAILING) 90.dp else PanelMargin) + endInset
    val top = if (edge == PaletteEdge.TOP) 84.dp else PanelMargin
    val low = bottomInset + bottomClearance + (if (selectionBar) SelectionBarTop + PanelGap else PanelMargin)
    val aboveTile = maxOf(bottomInset + bottomClearance + TileMargin + TileTarget + PanelGap, low)
    val bottom = GamePanelSize.bottom(canvasHeight.value.toDouble(), top.value.toDouble(), aboveTile.value.toDouble(), low.value.toDouble()).dp
    val step = if (expanded) {
        GamePanelSize.larger(canvasWidth.value.toDouble(), canvasHeight.value.toDouble(), leading.value.toDouble(), trailing.value.toDouble(), top.value.toDouble(), bottom.value.toDouble())
    } else {
        GamePanelSize.compact
    }
    val size = GamePanelSize.fitted(step, (canvasWidth - leading - trailing).value.toDouble(), (canvasHeight - top - bottom).value.toDouble())
    val width by animateDpAsState(size.width.dp, cornerSpring(), label = "panel width")
    val height by animateDpAsState(size.height.dp, cornerSpring(), label = "panel height")
    // Up over the lasso's bar and down again on the size's spring, so the panel's top moves as one.
    val lift by animateDpAsState(bottom, cornerSpring(), label = "panel bottom")

    Box(Modifier.fillMaxSize()) {
        GameCornerButton(
            open = open,
            onToggle = { open = !open },
            modifier = Modifier.align(Alignment.BottomStart).padding(start = TileMargin + startInset, bottom = bottomInset + bottomClearance + TileMargin),
        )
        AnimatedVisibility(
            visible = open,
            modifier = Modifier.align(Alignment.BottomStart).padding(start = leading, bottom = lift),
            enter = scaleIn(cornerSpring(), initialScale = 0.86f, transformOrigin = TransformOrigin(0f, 1f)) + fadeIn(cornerSpring()),
            exit = scaleOut(cornerSpring(), targetScale = 0.86f, transformOrigin = TransformOrigin(0f, 1f)) + fadeOut(cornerSpring()),
        ) {
            GameCornerPanel(width, height, expanded, onExpand = { expanded = !expanded }, onClose = { open = false }, store = store)
        }
    }
}

/**
 * The tile that opens and closes the break panel: a 38 dp rounded square with the game controller,
 * on paper with a hairline while the panel is shut, solid accent with a white glyph while it is open;
 * its hit area 44.
 */
@Composable
internal fun GameCornerButton(open: Boolean, onToggle: () -> Unit, modifier: Modifier = Modifier) {
    val z = Zen.colors
    val shape = RoundedCornerShape(Zen.control)
    val label = stringResource(if (open) R.string.games_tile_close else R.string.games_tile_open)
    Box(
        modifier
            .size(TileTarget)
            .clip(RoundedCornerShape(Zen.control))
            .clickable(role = Role.Button, onClick = onToggle)
            .clearAndSetSemantics {
                contentDescription = label
                role = Role.Button
                onClick { onToggle(); true }
            },
        contentAlignment = Alignment.Center,
    ) {
        Box(
            Modifier
                .size(38.dp)
                .background(if (open) z.accent else z.paper, shape)
                .border(1.dp, if (open) z.accent else z.rule, shape),
            contentAlignment = Alignment.Center,
        ) {
            Icon(Icons.Outlined.SportsEsports, contentDescription = null, tint = if (open) Color.White else z.ink2, modifier = Modifier.size(20.dp))
        }
    }
}

/**
 * The break card, [width] x [height]: a header, the games' tiles to pick from, the game itself.
 * Every touch inside it stays in it. Leaving it (closed) ends what was being played; a Sudoku is
 * kept to go on with.
 */
@Composable
internal fun GameCornerPanel(width: Dp, height: Dp, expanded: Boolean, onExpand: () -> Unit, onClose: () -> Unit, store: GameProgressStore) {
    val z = Zen.colors
    var game by remember { mutableStateOf<MiniGame?>(null) }
    /** Counts the restarts; each one builds the game afresh. */
    var round by remember { mutableIntStateOf(0) }
    BackHandler { if (game != null) game = null else onClose() }
    val title = game?.let { stringResource(it.title) } ?: stringResource(R.string.games_break)
    Column(
        Modifier
            .size(width, height)
            .floating(Zen.popover)
            .clip(RoundedCornerShape(Zen.popover))
            // The card keeps every touch to itself: nothing reaches the page beneath it.
            .pointerInput(Unit) {}
            .semantics { paneTitle = title },
    ) {
        PanelHeader(title, game, store, expanded, onBack = { game = null }, onRestart = { round += 1 }, onExpand = onExpand, onClose = onClose)
        Box(Modifier.fillMaxWidth().height(1.dp).background(z.rule))
        Box(Modifier.weight(1f).fillMaxWidth().clipToBounds().padding(12.dp)) {
            AnimatedContent(
                targetState = game,
                transitionSpec = { (slideInHorizontally { it } + fadeIn()) togetherWith fadeOut() },
                label = "break page",
            ) { shown ->
                if (shown == null) {
                    GamePicker(store) { game = it }
                } else {
                    key(round) { GameView(shown, store) }
                }
            }
        }
    }
}

@Composable
private fun GameView(game: MiniGame, store: GameProgressStore) {
    when (game) {
        MiniGame.BUBBLES -> BubblesGame(store)
        MiniGame.XOX -> XoxGame(store)
        MiniGame.DOTS -> DotsGame(store)
        MiniGame.SUDOKU -> SudokuGame(store)
    }
}

/** The card's header: back (or the cup), the title over a line about the game, restart, the larger step, close. */
@Composable
private fun PanelHeader(
    title: String,
    game: MiniGame?,
    store: GameProgressStore,
    expanded: Boolean,
    onBack: () -> Unit,
    onRestart: () -> Unit,
    onExpand: () -> Unit,
    onClose: () -> Unit,
) {
    val z = Zen.colors
    val subtitle = when {
        game == null -> stringResource(R.string.games_break_subtitle)
        game.hasDifficulty -> summary(game, store[game])
        else -> stringResource(game.hint)
    }
    Row(Modifier.fillMaxWidth().height(56.dp).padding(horizontal = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        if (game != null) {
            HeaderButton(Icons.AutoMirrored.Outlined.KeyboardArrowLeft, stringResource(R.string.games_back), onBack)
        } else {
            Box(Modifier.size(Zen.target), contentAlignment = Alignment.Center) {
                Box(Modifier.size(30.dp).background(z.accent.copy(alpha = 0.1f), CircleShape), contentAlignment = Alignment.Center) {
                    Icon(Icons.Outlined.LocalCafe, contentDescription = null, tint = z.accent, modifier = Modifier.size(16.dp))
                }
            }
        }
        Column(Modifier.weight(1f).padding(horizontal = 4.dp), verticalArrangement = Arrangement.spacedBy(1.dp)) {
            FitText(title, GameText.title3, z.ink, minScale = 0.85f)
            FitText(subtitle, GameText.caption2, z.muted)
        }
        if (game != null) HeaderButton(Icons.Outlined.Refresh, stringResource(R.string.games_restart), onRestart)
        HeaderButton(
            if (expanded) Icons.Outlined.CloseFullscreen else Icons.Outlined.OpenInFull,
            stringResource(if (expanded) R.string.games_shrink else R.string.games_enlarge),
            onExpand,
        )
        HeaderButton(Icons.Outlined.Close, stringResource(R.string.games_close), onClose)
    }
}

/** A round 30 dp button of the header, on paper-2 in a hairline, in a 44 dp target. */
@Composable
private fun HeaderButton(icon: ImageVector, label: String, onClick: () -> Unit) {
    val z = Zen.colors
    Box(
        Modifier
            .size(Zen.target)
            .clip(CircleShape)
            .clickable(role = Role.Button, onClick = onClick)
            .semantics { contentDescription = label },
        contentAlignment = Alignment.Center,
    ) {
        Box(Modifier.size(30.dp).background(z.paper2, CircleShape).border(1.dp, z.rule, CircleShape), contentAlignment = Alignment.Center) {
            Icon(icon, contentDescription = null, tint = z.ink2, modifier = Modifier.size(16.dp))
        }
    }
}

/** The layer picker (while two layers have tiles) and the tiles of the layer on show, two to a row. */
@Composable
private fun GamePicker(store: GameProgressStore, onPick: (MiniGame) -> Unit) {
    val layers = shownLayers
    val layer = store.layer.takeIf { it in layers } ?: layers.first()
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        if (layers.size > 1) {
            val label = stringResource(R.string.games_layer)
            ZenSegments(
                options = layers.map { stringResource(it.title) },
                selected = layers.indexOf(layer),
                onSelect = { store.pickLayer(layers[it]) },
                modifier = Modifier.fillMaxWidth().semantics { contentDescription = label },
            )
        }
        Column(Modifier.verticalScroll(rememberScrollState()).padding(vertical = 2.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            for (row in MiniGame.entries.filter { it.layer == layer }.chunked(2)) {
                Row(Modifier.height(IntrinsicSize.Max), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    for (game in row) GameTile(game, store, Modifier.weight(1f).fillMaxHeight()) { onPick(game) }
                    if (row.size == 1) Spacer(Modifier.weight(1f))
                }
            }
        }
    }
}

/** A game's tile: its glyph on a faint accent square, its name, its line (best, wins, time). */
@Composable
private fun GameTile(game: MiniGame, store: GameProgressStore, modifier: Modifier, onPick: () -> Unit) {
    val z = Zen.colors
    val shape = RoundedCornerShape(CardCorner)
    val title = stringResource(game.title)
    val description = title + ". " + stringResource(game.hint)
    Column(
        modifier
            .clip(shape)
            .background(z.paper)
            .border(1.dp, z.rule, shape)
            .clickable(role = Role.Button, onClick = onPick)
            .clearAndSetSemantics {
                contentDescription = description
                role = Role.Button
                onClick { onPick(); true }
            }
            .padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Box(Modifier.size(40.dp).background(z.accent.copy(alpha = 0.12f), RoundedCornerShape(Zen.control)), contentAlignment = Alignment.Center) {
            Icon(game.icon, contentDescription = null, tint = z.accent, modifier = Modifier.size(22.dp))
        }
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            FitText(title, GameText.subheadline.copy(fontWeight = FontWeight.SemiBold), z.ink)
            FitText(summary(game, store[game]), GameText.caption2, z.muted)
        }
    }
}
