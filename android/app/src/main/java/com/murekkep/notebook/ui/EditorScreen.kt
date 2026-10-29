package com.murekkep.notebook.ui

import android.content.Context
import android.content.ContextWrapper
import android.os.Build
import android.view.HapticFeedbackConstants
import android.view.View
import androidx.activity.compose.BackHandler
import androidx.compose.animation.core.VectorConverter
import androidx.compose.animation.core.animate
import androidx.compose.animation.core.spring
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowLeft
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.outlined.AutoAwesome
import androidx.compose.material.icons.outlined.Draw
import androidx.compose.material.icons.outlined.Gesture
import androidx.compose.material.icons.outlined.GridView
import androidx.compose.material.icons.outlined.IosShare
import androidx.compose.material.icons.outlined.MoreHoriz
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.path
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.ui.layout.findRootCoordinates
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.toggleableState
import androidx.compose.ui.state.ToggleableState
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.LifecycleOwner
import com.murekkep.notebook.R
import com.murekkep.notebook.canvas.CanvasOverlay
import com.murekkep.notebook.canvas.Clearance
import com.murekkep.notebook.canvas.HoverRing
import com.murekkep.notebook.canvas.InkCanvasView
import com.murekkep.notebook.data.LoadProblem
import kotlin.math.roundToInt
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.launch

// One open notebook, the spec's editor: a quiet top bar on paper-2 ("‹ Notlar", the title in the
// middle, Paylaş and Diğer), the page edge to edge under it, the lasso's bar and the floating pen
// bar over it along an edge (PenStrip.kt), the page badge "1 / 1" at the bottom right. Diğer holds
// the switches of the iPad's that Android has and Ayarlar, which opens over the note. The canvas is
// a GLSurfaceView: it pauses and resumes with the screen's lifecycle and is released when the screen
// leaves; the notebook is saved at both moments.

@Composable
fun EditorScreen(
    state: EditorState,
    onBack: () -> Unit,
    onShare: () -> Unit = {},
    /** Ayarlar over the open note, given the way back to it; null leaves it out of Diğer. */
    settings: (@Composable (close: () -> Unit) -> Unit)? = null,
    snackbar: SnackbarHostState = remember { SnackbarHostState() },
) {
    val context = LocalContext.current
    val z = Zen.colors
    val lifecycleOwner = remember(context) { context.findLifecycleOwner() }
    var hover by remember { mutableStateOf<HoverRing?>(null) }
    var overlay by remember { mutableStateOf<CanvasOverlay?>(null) }
    val canvas = remember(state) {
        InkCanvasView(context, state).also {
            it.onHover = { ring -> hover = ring }
            it.onOverlay = { o -> overlay = o }
        }
    }
    // The ground round the pages follows the theme.
    val ground = z.groundRgb
    remember(ground[0], ground[1], ground[2]) { canvas.ground = ground }

    DisposableEffect(lifecycleOwner, canvas) {
        val observer = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_RESUME -> canvas.onResume()
                Lifecycle.Event.ON_PAUSE -> {
                    canvas.onPause()
                    state.requestSave()
                }
                else -> {}
            }
        }
        lifecycleOwner?.lifecycle?.addObserver(observer)
        onDispose {
            lifecycleOwner?.lifecycle?.removeObserver(observer)
            canvas.release()
            state.requestSave()
        }
    }

    val safe = WindowInsets.safeDrawing.asPaddingValues()
    val layoutDirection = LocalLayoutDirection.current
    val bottomInset = safe.calculateBottomPadding()
    val leftInset = safe.calculateLeftPadding(layoutDirection)
    val rightInset = safe.calculateRightPadding(layoutDirection)
    val density = LocalDensity.current
    val edge = state.paletteEdge
    // The bar's drag on its grip: how far the finger has carried it, and the edge it would go to.
    var paletteDrag by remember { mutableStateOf(Offset.Zero) }
    var paletteTarget by remember { mutableStateOf<PaletteEdge?>(null) }
    val canvasPlace = remember { CanvasPlace() }
    val scope = rememberCoroutineScope()
    val view = LocalView.current
    // The bar's way back to its place on the iPad's spring; the grip taken again stops it.
    var settling by remember { mutableStateOf<Job?>(null) }
    val settle = {
        val from = paletteDrag
        settling = scope.launch {
            animate(Offset.VectorConverter, from, Offset.Zero, animationSpec = spring(dampingRatio = 0.82f, stiffness = springStiffness(0.38f))) { value, _ ->
                paletteDrag = value
            }
        }
    }
    // A soft knock whenever the bar settles on another edge, by its grip, its menu or TalkBack (the
    // iPad's sensoryFeedback on its dock).
    LaunchedEffect(state, view) {
        snapshotFlow { state.paletteEdge }.drop(1).collect { view.dockThud() }
    }
    // Ayarlar › 3B mürekkep changes the same ink settings, over this note too: the canvas follows at
    // once (the moving ink starts or stops, drying and cooling take the new times).
    LaunchedEffect(state) {
        snapshotFlow { listOf(state.animations, state.batterySaver, state.dryDuration, state.coolDuration) }
            .drop(1)
            .collect { state.onInkChange?.invoke() }
    }
    // What stands along the bottom (the page badge, the lasso's bar) moves up over a bar there.
    val bottomClearance = if (edge == PaletteEdge.BOTTOM) PenBarMargin + PenBarHeight + 8.dp else 0.dp
    SideEffect {
        canvas.clearance = with(density) {
            when (edge) {
                PaletteEdge.TOP -> Clearance(top = (PaletteTopMargin + PenBarHeight).toPx())
                PaletteEdge.BOTTOM -> Clearance(bottom = (bottomInset + PenBarMargin + PenBarHeight).toPx())
                PaletteEdge.TRAILING -> Clearance(right = (rightInset + PaletteSideMargin + PenBarHeight).toPx())
            }
        }
    }

    var settingsOpen by rememberSaveable { mutableStateOf(false) }
    var templatesOpen by rememberSaveable { mutableStateOf(false) }
    Box(Modifier.fillMaxSize()) {
        Column(Modifier.fillMaxSize().background(z.paper3)) {
            EditorTopBar(state, onBack, onShare, onTemplates = { templatesOpen = true }, onSettings = settings?.let { { settingsOpen = true } })
            BoxWithConstraints(
                Modifier
                    .weight(1f)
                    .fillMaxWidth()
                    .onGloballyPositioned { canvasPlace.coordinates = it },
            ) {
                AndroidView(factory = { canvas }, modifier = Modifier.fillMaxSize())
                overlay?.let { CanvasOverlayLayer(it) }
                // A hovering pen (S Pen, USI) shows the size of what it would draw, or erase in red.
                hover?.let { ring ->
                    Canvas(Modifier.fillMaxSize()) {
                        drawCircle(
                            color = if (ring.erasing) Color(0x99D93025) else z.accent.copy(alpha = 0.5f),
                            radius = ring.radius,
                            center = Offset(ring.x, ring.y),
                            style = Stroke(width = 1.5.dp.toPx()),
                        )
                    }
                }
                if (state.loadProblems.isNotEmpty()) {
                    LoadNotice(state.loadProblems, Modifier.align(Alignment.Center).padding(24.dp).widthIn(max = 520.dp))
                }
                if (state.tool is Tool.Lasso && state.selection != null) {
                    SelectionBar(state, Modifier.align(Alignment.BottomCenter).padding(bottom = bottomInset + 52.dp + bottomClearance))
                }
                paletteTarget?.let { target ->
                    PaletteDockHint(target, Modifier.align(target.alignment).padding(paletteInsets(target, bottomInset, leftInset, rightInset)))
                }
                // Against the canvas as it is now: a drag outlives a turn of the tablet.
                val nearest = { finger: Offset ->
                    val place = canvasPlace.coordinates
                    val at = place?.let { it.localPositionOf(it.findRootCoordinates(), finger) } ?: finger
                    val size = place?.size ?: IntSize(constraints.maxWidth, constraints.maxHeight)
                    PaletteEdge.nearest(at.x, at.y, size.width.toFloat(), size.height.toFloat(), edge)
                }
                PenBar(
                    state,
                    popoverRoom = popoverRoom(edge, maxHeight, bottomInset),
                    onGripMove = { finger, moved ->
                        settling?.cancel()
                        paletteDrag = moved
                        val target = nearest(finger)
                        if (paletteTarget != null && paletteTarget != target) view.selectionTick()
                        paletteTarget = target
                    },
                    onGripDrop = { finger ->
                        val target = nearest(finger)
                        paletteTarget = null
                        if (target == edge) {
                            settle()
                        } else {
                            state.paletteEdge = target
                            paletteDrag = Offset.Zero
                        }
                    },
                    onGripCancel = {
                        paletteTarget = null
                        settle()
                    },
                    modifier = Modifier
                        .align(edge.alignment)
                        .padding(paletteInsets(edge, bottomInset, leftInset, rightInset))
                        .offset { IntOffset(paletteDrag.x.roundToInt(), paletteDrag.y.roundToInt()) },
                )
                PageBadge(state, Modifier.align(Alignment.BottomEnd).padding(end = 16.dp + rightInset, bottom = bottomInset + 8.dp + bottomClearance))
                SnackbarHost(snackbar, Modifier.align(Alignment.TopCenter))
            }
        }
        if (settingsOpen && settings != null) {
            BackHandler { settingsOpen = false }
            // Over the note, as the iPad's sheet: nothing reaches the page beneath.
            Box(Modifier.fillMaxSize().pointerInput(Unit) {}) { settings { settingsOpen = false } }
        }
        // "Şablonu değiştir": the templates with the notebook's own marked; a pick puts every page on it.
        if (templatesOpen) {
            TemplateSheet(
                title = stringResource(R.string.change_template_title),
                current = state.paper,
                onDismiss = { templatesOpen = false },
                onPick = {
                    templatesOpen = false
                    state.changePaper(it)
                },
            )
        }
    }
}

/** The top bar's height under the status bar. */
private val TopBarHeight = 52.dp

// The pen bar's room from the edges (the iPad's paletteInsets): under the top bar, from the sides
// along the top and the bottom, and from the right side and from the top and the bottom down it
// (clear of the page badge).
private val PaletteTopMargin = 10.dp
private val PaletteSideMargin = 12.dp
private val PaletteColumnMargin = 60.dp

private fun paletteInsets(edge: PaletteEdge, bottomInset: Dp, leftInset: Dp, rightInset: Dp): PaddingValues = when (edge) {
    PaletteEdge.TOP -> PaddingValues(start = PaletteSideMargin + leftInset, top = PaletteTopMargin, end = PaletteSideMargin + rightInset)
    PaletteEdge.BOTTOM -> PaddingValues(start = PaletteSideMargin + leftInset, end = PaletteSideMargin + rightInset, bottom = bottomInset + PenBarMargin)
    PaletteEdge.TRAILING -> PaddingValues(top = PaletteColumnMargin, end = PaletteSideMargin + rightInset, bottom = PaletteColumnMargin + bottomInset)
}

private val PaletteEdge.alignment: Alignment
    get() = when (this) {
        PaletteEdge.TOP -> Alignment.TopCenter
        PaletteEdge.BOTTOM -> Alignment.BottomCenter
        PaletteEdge.TRAILING -> Alignment.CenterEnd
    }

/**
 * The height a popover of the bar may take over a canvas [canvasHeight] tall: above a bar along the
 * bottom up to the status bar, below a bar along the top down to the navigation bar, the window's
 * height beside a bar down the right side; the popover's gap and margin kept.
 */
private fun popoverRoom(edge: PaletteEdge, canvasHeight: Dp, bottomInset: Dp): Dp = when (edge) {
    PaletteEdge.BOTTOM -> TopBarHeight + canvasHeight - bottomInset - PenBarMargin - PenBarHeight - PopoverGap - PopoverMargin
    PaletteEdge.TOP -> canvasHeight - PaletteTopMargin - PenBarHeight - PopoverGap - bottomInset - PopoverMargin
    PaletteEdge.TRAILING -> TopBarHeight + canvasHeight - bottomInset - PopoverMargin * 2
}

/** Where the canvas is on screen, for the grip's finger (kept out of Compose's state). */
private class CanvasPlace {
    var coordinates: LayoutCoordinates? = null
}

/** Where the pen bar will land while its grip is dragged: the bar's outline in a faint accent. */
@Composable
private fun PaletteDockHint(edge: PaletteEdge, modifier: Modifier) {
    val z = Zen.colors
    val shape = RoundedCornerShape(Zen.bar)
    Box(
        modifier
            .size(if (edge.isVertical) PenBarHeight else 420.dp, if (edge.isVertical) 360.dp else PenBarHeight)
            .background(z.accent.copy(alpha = 0.08f), shape)
            .border(1.5.dp, z.accent.copy(alpha = 0.35f), shape),
    )
}

/** The light tick of a pick: the edge the bar would go to changed under the finger. */
private fun View.selectionTick() {
    performHapticFeedback(if (Build.VERSION.SDK_INT >= 34) HapticFeedbackConstants.SEGMENT_FREQUENT_TICK else HapticFeedbackConstants.CLOCK_TICK)
}

/** A soft knock: the bar settled on another edge. */
private fun View.dockThud() {
    performHapticFeedback(if (Build.VERSION.SDK_INT >= 30) HapticFeedbackConstants.GESTURE_END else HapticFeedbackConstants.CONTEXT_CLICK)
}

/** The activity behind a Compose context (a ComponentActivity is a LifecycleOwner). */
private fun Context.findLifecycleOwner(): LifecycleOwner? {
    var c: Context? = this
    while (c != null) {
        if (c is LifecycleOwner) return c
        c = (c as? ContextWrapper)?.baseContext
    }
    return null
}

/** Paylaş ("PDF olarak paylaş") and Diğer on the editor's bar. Diğer holds the iPad's: for a
 *  notebook "Şablonu değiştir (Çizgili)", then the pen-only drawing, the held shape, the animations
 *  and the battery saver as switches, and Ayarlar under a divider. */
@Composable
private fun EditorTopBar(state: EditorState, onBack: () -> Unit, onShare: () -> Unit, onTemplates: () -> Unit, onSettings: (() -> Unit)?) {
    val z = Zen.colors
    var menuOpen by remember { mutableStateOf(false) }
    EditorBar(state.title, onBack) {
        BarButton(stringResource(R.string.share_pdf), onClick = onShare) {
            Icon(Icons.Outlined.IosShare, contentDescription = null, modifier = Modifier.size(22.dp))
        }
        Box {
            BarButton(stringResource(R.string.more), onClick = { menuOpen = true }) {
                Icon(Icons.Outlined.MoreHoriz, contentDescription = null, modifier = Modifier.size(22.dp))
            }
            ZenMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
                if (!state.isPdf) {
                    DropdownMenuItem(
                        text = { Text(stringResource(R.string.change_template, stringResource(state.paper.titleRes))) },
                        leadingIcon = { Spacer(Modifier.size(24.dp)) },
                        trailingIcon = { Icon(Icons.Outlined.GridView, contentDescription = null) },
                        enabled = !state.readOnly,
                        onClick = {
                            menuOpen = false
                            onTemplates()
                        },
                    )
                }
                MenuSwitch(stringResource(R.string.editor_pen_only), Icons.Outlined.Draw, state.penOnly) {
                    state.penOnly = it
                    menuOpen = false
                }
                MenuSwitch(stringResource(R.string.editor_straighten_on_hold), Icons.Outlined.Gesture, state.straightLine) {
                    state.straightLine = it
                    menuOpen = false
                }
                MenuSwitch(stringResource(R.string.editor_animations), Icons.Outlined.AutoAwesome, state.animations) {
                    state.animations = it
                    menuOpen = false
                }
                MenuSwitch(stringResource(R.string.editor_battery_saver), BatteryHalfGlyph, state.batterySaver) {
                    state.batterySaver = it
                    menuOpen = false
                }
                if (onSettings != null) {
                    HorizontalDivider(color = z.rule)
                    DropdownMenuItem(
                        text = { Text(stringResource(R.string.settings)) },
                        leadingIcon = { Spacer(Modifier.size(24.dp)) },
                        trailingIcon = { Icon(Icons.Outlined.Settings, contentDescription = null) },
                        onClick = {
                            menuOpen = false
                            onSettings()
                        },
                    )
                }
            }
        }
    }
}

/**
 * The editor's top bar (the iPad's navigation bar): "‹ Notlar" in the accent on the left, [title] in
 * the middle, [actions] on the right, on paper-2 over a hairline. A note on its way in shows it with
 * no actions yet.
 */
@Composable
internal fun EditorBar(title: String, onBack: () -> Unit, actions: @Composable RowScope.() -> Unit) {
    val z = Zen.colors
    Box(
        Modifier
            .fillMaxWidth()
            .background(z.paper2)
            .windowInsetsPadding(WindowInsets.safeDrawing.only(WindowInsetsSides.Top + WindowInsetsSides.Horizontal))
            .height(TopBarHeight),
    ) {
        Row(Modifier.fillMaxSize().padding(horizontal = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            Row(
                Modifier
                    .height(Zen.target)
                    .clip(RoundedCornerShape(Zen.control))
                    .clickable(role = Role.Button, onClick = onBack)
                    .padding(start = 6.dp, end = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(Icons.AutoMirrored.Outlined.KeyboardArrowLeft, contentDescription = null, tint = z.accent, modifier = Modifier.size(24.dp))
                Text(stringResource(R.string.notes), style = MaterialTheme.typography.bodyLarge, color = z.accent)
            }
            Spacer(Modifier.weight(1f))
            actions()
        }
        Text(
            title,
            style = MaterialTheme.typography.titleMedium,
            color = z.ink,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            textAlign = TextAlign.Center,
            modifier = Modifier.align(Alignment.Center).fillMaxWidth(0.5f),
        )
        Box(Modifier.align(Alignment.BottomCenter).fillMaxWidth().height(1.dp).background(z.rule))
    }
}

/** The iPad's battery.50: a battery on its side, half full, in a 24-unit box. */
internal val BatteryHalfGlyph: ImageVector by lazy {
    ImageVector.Builder("BatteryHalf", 24.dp, 24.dp, 24f, 24f)
        .path(stroke = SolidColor(Color.Black), strokeLineWidth = 1.5f) {
            // The case.
            moveTo(5f, 7.25f)
            horizontalLineTo(17f)
            arcTo(2.75f, 2.75f, 0f, false, true, 19.75f, 10f)
            verticalLineTo(14f)
            arcTo(2.75f, 2.75f, 0f, false, true, 17f, 16.75f)
            horizontalLineTo(5f)
            arcTo(2.75f, 2.75f, 0f, false, true, 2.25f, 14f)
            verticalLineTo(10f)
            arcTo(2.75f, 2.75f, 0f, false, true, 5f, 7.25f)
            close()
        }
        .path(fill = SolidColor(Color.Black)) {
            // The cap.
            moveTo(21f, 10.25f)
            arcTo(1f, 1f, 0f, false, true, 22f, 11.25f)
            verticalLineTo(12.75f)
            arcTo(1f, 1f, 0f, false, true, 21f, 13.75f)
            close()
            // Half the charge.
            moveTo(5.25f, 9.25f)
            horizontalLineTo(11f)
            verticalLineTo(14.75f)
            horizontalLineTo(5.25f)
            arcTo(1f, 1f, 0f, false, true, 4.25f, 13.75f)
            verticalLineTo(10.25f)
            arcTo(1f, 1f, 0f, false, true, 5.25f, 9.25f)
            close()
        }
        .build()
}

/** A switch in a menu, as iPadOS draws one: a check before it while it is on, its symbol after it. */
@Composable
private fun MenuSwitch(title: String, icon: ImageVector, on: Boolean, onChange: (Boolean) -> Unit) {
    DropdownMenuItem(
        text = { Text(title) },
        leadingIcon = {
            if (on) Icon(Icons.Filled.Check, contentDescription = null) else Spacer(Modifier.size(24.dp))
        },
        trailingIcon = { Icon(icon, contentDescription = null) },
        onClick = { onChange(!on) },
        modifier = Modifier.semantics {
            role = Role.Switch
            toggleableState = ToggleableState(on)
        },
    )
}

/** "1 / 1": the page under the middle of the view and how many there are, in plain text on the page,
 *  in a 44 dp box with 12 dp at its sides (the iPad's PageBadge). */
@Composable
private fun PageBadge(state: EditorState, modifier: Modifier) {
    val z = Zen.colors
    val page = state.currentPage + 1
    val count = state.pageCount
    val description = stringResource(R.string.page_badge_description, page, count)
    Box(
        modifier
            .height(Zen.target)
            .padding(horizontal = 12.dp)
            .clearAndSetSemantics { contentDescription = description },
        contentAlignment = Alignment.Center,
    ) {
        Text(
            stringResource(R.string.page_badge, page, count),
            style = MaterialTheme.typography.bodySmall.merge(TextStyle(fontFeatureSettings = "tnum")),
            color = z.onPage,
        )
    }
}

/** Why the note opened read-only, a floating paper card in the middle of the page (the iPad's
 *  loadError): the PDF's problem, then the ink's, a blank line between them. */
@Composable
private fun LoadNotice(problems: List<LoadProblem>, modifier: Modifier) {
    val text = problems.map { stringResource(it.messageRes) }.joinToString("\n\n")
    Text(
        text,
        style = MaterialTheme.typography.bodyLarge,
        color = Zen.colors.ink,
        modifier = modifier.floating(14.dp).padding(16.dp),
    )
}

private val LoadProblem.messageRes: Int
    get() = when (this) {
        LoadProblem.PDF_UNREADABLE -> R.string.load_pdf_unreadable
        LoadProblem.INK_NEWER -> R.string.load_ink_newer
        LoadProblem.INK_DAMAGED -> R.string.load_ink_damaged
    }
