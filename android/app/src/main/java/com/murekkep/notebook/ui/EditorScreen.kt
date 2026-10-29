package com.murekkep.notebook.ui

import android.content.Context
import android.content.ContextWrapper
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Redo
import androidx.compose.material.icons.automirrored.filled.Undo
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
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
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.LifecycleOwner
import com.murekkep.notebook.R
import com.murekkep.notebook.canvas.HoverRing
import com.murekkep.notebook.canvas.InkCanvasView

// One open notebook: a calm top bar (back, title, undo, redo), the ink canvas, and the pen dock
// under it (PenStrip.kt). The canvas is a GLSurfaceView: it pauses and resumes with the screen's
// lifecycle and is released when the screen leaves; the notebook is saved at both moments.

@Composable
fun EditorScreen(state: EditorState, onBack: () -> Unit) {
    val context = LocalContext.current
    val lifecycleOwner = remember(context) { context.findLifecycleOwner() }
    var hover by remember { mutableStateOf<HoverRing?>(null) }
    val canvas = remember(state) { InkCanvasView(context, state).also { it.onHover = { ring -> hover = ring } } }

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

    Column(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background)) {
        EditorTopBar(state, onBack)
        Box(Modifier.weight(1f).fillMaxWidth()) {
            AndroidView(factory = { canvas }, modifier = Modifier.fillMaxSize())
            // A hovering pen (S Pen, USI) shows the size of what it would draw, or erase in red.
            hover?.let { ring ->
                Canvas(Modifier.fillMaxSize()) {
                    drawCircle(
                        color = if (ring.erasing) Color(0x99D93025) else Color(0x661E2A5A),
                        radius = ring.radius,
                        center = Offset(ring.x, ring.y),
                        style = Stroke(width = 1.5.dp.toPx()),
                    )
                }
            }
            if (state.readOnly) {
                ReadOnlyNotice(Modifier.align(Alignment.TopCenter).padding(12.dp))
            }
        }
        ToolDock(state)
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

@Composable
private fun EditorTopBar(state: EditorState, onBack: () -> Unit) {
    Surface(color = MaterialTheme.colorScheme.surface, tonalElevation = 2.dp, shadowElevation = 1.dp) {
        Row(
            Modifier
                .fillMaxWidth()
                .windowInsetsPadding(WindowInsets.safeDrawing.only(WindowInsetsSides.Top + WindowInsetsSides.Horizontal))
                .height(56.dp)
                .padding(horizontal = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            IconButton(onClick = onBack) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = stringResource(R.string.back))
            }
            Text(
                state.title,
                style = MaterialTheme.typography.titleMedium,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f).padding(horizontal = 8.dp),
            )
            IconButton(onClick = state::undo, enabled = state.canUndo) {
                Icon(Icons.AutoMirrored.Filled.Undo, contentDescription = stringResource(R.string.undo))
            }
            IconButton(onClick = state::redo, enabled = state.canRedo) {
                Icon(Icons.AutoMirrored.Filled.Redo, contentDescription = stringResource(R.string.redo))
            }
        }
    }
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
