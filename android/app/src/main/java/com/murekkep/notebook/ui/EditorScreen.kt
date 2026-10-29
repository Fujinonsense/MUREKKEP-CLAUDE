package com.murekkep.notebook.ui

import android.content.Context
import android.content.ContextWrapper
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowLeft
import androidx.compose.material.icons.outlined.MoreHoriz
import androidx.compose.material.icons.outlined.Share
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.LifecycleOwner
import com.murekkep.notebook.R
import com.murekkep.notebook.canvas.CanvasOverlay
import com.murekkep.notebook.canvas.HoverRing
import com.murekkep.notebook.canvas.InkCanvasView

// One open notebook, the spec's editor: a quiet top bar on paper-2 ("‹ Notlar", the title in the
// middle, Paylaş and Diğer), the page edge to edge under it, the lasso's bar and the floating pen
// bar over it (PenStrip.kt), the page badge "1 / 1" at the bottom right. The canvas is a
// GLSurfaceView: it pauses and resumes with the screen's lifecycle and is released when the screen
// leaves; the notebook is saved at both moments.

@Composable
fun EditorScreen(
    state: EditorState,
    onBack: () -> Unit,
    onShare: () -> Unit = {},
    onRename: ((String) -> Unit)? = null,
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

    val bottomInset = WindowInsets.safeDrawing.only(WindowInsetsSides.Bottom).asPaddingValues().calculateBottomPadding()
    Column(Modifier.fillMaxSize().background(z.paper3)) {
        EditorTopBar(state, onBack, onShare, onRename)
        Box(Modifier.weight(1f).fillMaxWidth()) {
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
            if (state.readOnly) {
                ReadOnlyNotice(Modifier.align(Alignment.TopCenter).padding(12.dp))
            }
            if (state.tool is Tool.Lasso && state.selection != null) {
                SelectionBar(state, Modifier.align(Alignment.BottomCenter).padding(bottom = bottomInset + PenBarMargin + PenBarHeight + 12.dp))
            }
            PenBar(state, Modifier.align(Alignment.BottomCenter).padding(bottom = bottomInset + PenBarMargin))
            PageBadge(state, Modifier.align(Alignment.BottomEnd).padding(end = 16.dp, bottom = bottomInset + 26.dp))
            SnackbarHost(snackbar, Modifier.align(Alignment.TopCenter))
        }
    }
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

/** "‹ Notlar" on the left, the title in the middle, Paylaş and Diğer on the right, on paper-2 over a hairline. */
@Composable
private fun EditorTopBar(state: EditorState, onBack: () -> Unit, onShare: () -> Unit, onRename: ((String) -> Unit)?) {
    val z = Zen.colors
    var menuOpen by remember { mutableStateOf(false) }
    var renaming by remember { mutableStateOf(false) }
    Box(
        Modifier
            .fillMaxWidth()
            .background(z.paper2)
            .windowInsetsPadding(WindowInsets.safeDrawing.only(WindowInsetsSides.Top + WindowInsetsSides.Horizontal))
            .height(52.dp),
    ) {
        Row(Modifier.fillMaxSize().padding(horizontal = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            Row(
                Modifier
                    .height(Zen.target)
                    .clip(RoundedCornerShape(Zen.control))
                    .clickable(onClick = onBack)
                    .padding(start = 6.dp, end = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(Icons.AutoMirrored.Outlined.KeyboardArrowLeft, contentDescription = null, tint = z.ink2, modifier = Modifier.size(24.dp))
                Text(stringResource(R.string.notes), style = MaterialTheme.typography.bodyLarge, color = z.ink2)
            }
            Spacer(Modifier.weight(1f))
            BarButton(stringResource(R.string.share), onClick = onShare) {
                Icon(Icons.Outlined.Share, contentDescription = null, modifier = Modifier.size(22.dp))
            }
            Box {
                BarButton(stringResource(R.string.more), onClick = { menuOpen = true }) {
                    Icon(Icons.Outlined.MoreHoriz, contentDescription = null, modifier = Modifier.size(22.dp))
                }
                ZenMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
                    if (onRename != null) {
                        DropdownMenuItem(
                            text = { Text(stringResource(R.string.rename_note)) },
                            onClick = {
                                menuOpen = false
                                renaming = true
                            },
                        )
                    }
                    DropdownMenuItem(
                        text = { Text(stringResource(R.string.share_pdf)) },
                        onClick = {
                            menuOpen = false
                            onShare()
                        },
                    )
                }
            }
        }
        Text(
            state.title,
            style = MaterialTheme.typography.titleSmall,
            color = z.ink,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            textAlign = TextAlign.Center,
            modifier = Modifier.align(Alignment.Center).fillMaxWidth(0.5f),
        )
        Box(Modifier.align(Alignment.BottomCenter).fillMaxWidth().height(1.dp).background(z.rule))
    }
    if (renaming && onRename != null) {
        RenameDialog(
            initial = state.title,
            onDismiss = { renaming = false },
            onRename = { title ->
                onRename(title)
                renaming = false
            },
        )
    }
}

/** "1 / 1": the page under the middle of the view and how many there are, in plain text on the page. */
@Composable
private fun PageBadge(state: EditorState, modifier: Modifier) {
    val z = Zen.colors
    val page = state.currentPage + 1
    val count = state.pageCount
    val description = stringResource(R.string.page_badge_description, page, count)
    Text(
        stringResource(R.string.page_badge, page, count),
        style = MaterialTheme.typography.bodySmall.merge(TextStyle(fontFeatureSettings = "tnum")),
        color = z.onPage,
        modifier = modifier.semantics { contentDescription = description },
    )
}

@Composable
private fun ReadOnlyNotice(modifier: Modifier) {
    Surface(
        modifier = modifier,
        shape = MaterialTheme.shapes.small,
        color = MaterialTheme.colorScheme.errorContainer,
        contentColor = MaterialTheme.colorScheme.onErrorContainer,
        shadowElevation = 2.dp,
    ) {
        Text(
            stringResource(R.string.read_only_notice),
            modifier = Modifier.padding(horizontal = 14.dp, vertical = 8.dp),
            style = MaterialTheme.typography.bodyMedium,
        )
    }
}
