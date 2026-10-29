@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

package com.murekkep.notebook.ui

import android.icu.text.RelativeDateTimeFormatter
import android.text.format.DateUtils
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.calculateEndPadding
import androidx.compose.foundation.layout.calculateStartPadding
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExtendedFloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.murekkep.notebook.R
import com.murekkep.notebook.data.NotebookMeta
import com.murekkep.notebook.data.NotebookStore
import com.murekkep.notebook.data.PaperStyle
import java.text.DateFormat
import java.util.Date

// The library (Murekkep.swiftpm/LibraryView): a grid of notebook cards, newest first, with a button
// for a new notebook; each card's menu renames or deletes it (deleting asks first).

@Composable
fun LibraryScreen(store: NotebookStore, onOpen: (NotebookMeta) -> Unit) {
    LaunchedEffect(store) { store.load() }
    var renaming by remember { mutableStateOf<NotebookMeta?>(null) }
    var deleting by remember { mutableStateOf<NotebookMeta?>(null) }
    val titlePrefix = stringResource(R.string.notebook_default_title)
    val direction = LocalLayoutDirection.current

    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.library_title), style = MaterialTheme.typography.titleLarge) },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.background),
            )
        },
        floatingActionButton = {
            ExtendedFloatingActionButton(
                onClick = { onOpen(store.create(newNotebookTitle(titlePrefix))) },
                icon = { Icon(Icons.Filled.Add, contentDescription = null) },
                text = { Text(stringResource(R.string.new_notebook)) },
                containerColor = MaterialTheme.colorScheme.primary,
                contentColor = MaterialTheme.colorScheme.onPrimary,
            )
        },
    ) { padding ->
        val notebooks = store.notebooks
        if (store.loaded && notebooks.isEmpty()) {
            EmptyLibrary(Modifier.fillMaxSize().padding(padding))
        } else {
            LazyVerticalGrid(
                columns = GridCells.Adaptive(minSize = 168.dp),
                modifier = Modifier.fillMaxSize(),
                contentPadding = PaddingValues(
                    start = padding.calculateStartPadding(direction) + 24.dp,
                    top = padding.calculateTopPadding() + 8.dp,
                    end = padding.calculateEndPadding(direction) + 24.dp,
                    bottom = padding.calculateBottomPadding() + 96.dp,
                ),
                horizontalArrangement = Arrangement.spacedBy(20.dp),
                verticalArrangement = Arrangement.spacedBy(24.dp),
            ) {
                items(notebooks, key = { it.id }) { meta ->
                    NotebookCard(
                        meta = meta,
                        onOpen = { onOpen(meta) },
                        onRename = { renaming = meta },
                        onDelete = { deleting = meta },
                    )
                }
            }
        }
    }

    renaming?.let { meta ->
        RenameDialog(
            meta = meta,
            onDismiss = { renaming = null },
            onRename = { title ->
                store.rename(meta.id, title)
                renaming = null
            },
        )
    }
    deleting?.let { meta ->
        DeleteDialog(
            meta = meta,
            onDismiss = { deleting = null },
            onDelete = {
                store.delete(meta.id)
                deleting = null
            },
        )
    }
}

/** "Note" and the moment, as the iPad names a new notebook. */
private fun newNotebookTitle(prefix: String): String {
    val stamp = DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT).format(Date())
    return "$prefix $stamp"
}

@Composable
private fun EmptyLibrary(modifier: Modifier) {
    Box(modifier, contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.padding(32.dp)) {
            Text(stringResource(R.string.library_empty_title), style = MaterialTheme.typography.titleLarge)
            Spacer(Modifier.height(8.dp))
            Text(
                stringResource(R.string.library_empty_hint),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun NotebookCard(meta: NotebookMeta, onOpen: () -> Unit, onRename: () -> Unit, onDelete: () -> Unit) {
    var menuOpen by remember { mutableStateOf(false) }
    Column {
        Card(
            onClick = onOpen,
            modifier = Modifier.fillMaxWidth().aspectRatio(EditorState.A4_WIDTH / EditorState.A4_HEIGHT),
            shape = MaterialTheme.shapes.medium,
            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
            elevation = CardDefaults.cardElevation(defaultElevation = 1.dp),
        ) {
            Box(Modifier.fillMaxSize()) {
                PaperPreview(meta.paper, Modifier.fillMaxSize())
                Box(Modifier.align(Alignment.TopEnd)) {
                    IconButton(onClick = { menuOpen = true }) {
                        Icon(
                            Icons.Filled.MoreVert,
                            contentDescription = stringResource(R.string.more_actions),
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
                        DropdownMenuItem(
                            text = { Text(stringResource(R.string.rename)) },
                            leadingIcon = { Icon(Icons.Filled.Edit, contentDescription = null) },
                            onClick = {
                                menuOpen = false
                                onRename()
                            },
                        )
                        DropdownMenuItem(
                            text = { Text(stringResource(R.string.delete)) },
                            leadingIcon = { Icon(Icons.Filled.Delete, contentDescription = null) },
                            onClick = {
                                menuOpen = false
                                onDelete()
                            },
                        )
                    }
                }
            }
        }
        Spacer(Modifier.height(10.dp))
        Text(
            meta.title,
            style = MaterialTheme.typography.titleMedium,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
        )
        Spacer(Modifier.height(2.dp))
        Text(
            relativeDate(meta.modified),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

/** "now", "5 min. ago", "Yesterday", "Oct 12": the system's words, in the user's language. The
 *  first minute is "now", as the iPad's named style says it, not "0 min. ago". */
private fun relativeDate(millis: Long): String {
    val now = System.currentTimeMillis()
    if (now - millis < DateUtils.MINUTE_IN_MILLIS) {
        return RelativeDateTimeFormatter.getInstance()
            .format(RelativeDateTimeFormatter.Direction.PLAIN, RelativeDateTimeFormatter.AbsoluteUnit.NOW)
    }
    return DateUtils.getRelativeTimeSpanString(millis, now, DateUtils.MINUTE_IN_MILLIS, DateUtils.FORMAT_ABBREV_RELATIVE).toString()
}

/** A hint of the page's template on the card: lines, squares or dots. */
@Composable
private fun PaperPreview(paper: PaperStyle, modifier: Modifier) {
    val line = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.8f)
    Canvas(modifier) {
        val w = size.width
        val h = size.height
        val step = h / 14f
        val left = w * 0.1f
        val right = w * 0.9f
        when (paper) {
            PaperStyle.LINED, PaperStyle.NARROW_LINED, PaperStyle.HANDWRITING, PaperStyle.CORNELL, PaperStyle.MUSIC -> {
                var y = step * 2.5f
                while (y < h - step * 0.5f) {
                    drawLine(line, Offset(left, y), Offset(right, y), strokeWidth = 1f)
                    y += step
                }
            }
            PaperStyle.GRID, PaperStyle.SMALL_GRID, PaperStyle.ENGINEERING -> {
                var y = step * 1.5f
                while (y < h - step * 0.5f) {
                    drawLine(line, Offset(left, y), Offset(right, y), strokeWidth = 1f)
                    y += step
                }
                var x = left
                while (x <= right + 0.5f) {
                    drawLine(line, Offset(x, step * 1.5f), Offset(x, h - step * 0.5f), strokeWidth = 1f)
                    x += step
                }
            }
            PaperStyle.DOTTED, PaperStyle.ISOMETRIC, PaperStyle.HEXAGON -> {
                var y = step * 1.5f
                while (y < h - step * 0.5f) {
                    var x = left
                    while (x <= right + 0.5f) {
                        drawCircle(line, radius = 1.2f, center = Offset(x, y))
                        x += step
                    }
                    y += step
                }
            }
            else -> {}
        }
    }
}

@Composable
private fun RenameDialog(meta: NotebookMeta, onDismiss: () -> Unit, onRename: (String) -> Unit) {
    var text by remember(meta.id) { mutableStateOf(meta.title) }
    val focus = remember { FocusRequester() }
    val submit: () -> Unit = {
        if (text.isNotBlank()) onRename(text.trim())
    }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.rename_title)) },
        text = {
            OutlinedTextField(
                value = text,
                onValueChange = { text = it },
                singleLine = true,
                label = { Text(stringResource(R.string.notebook_title_label)) },
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                keyboardActions = KeyboardActions(onDone = { submit() }),
                modifier = Modifier.fillMaxWidth().focusRequester(focus),
            )
            // Inside the dialog's own composition, so the field exists when the focus is asked for.
            LaunchedEffect(Unit) { focus.requestFocus() }
        },
        confirmButton = {
            TextButton(onClick = submit, enabled = text.isNotBlank()) { Text(stringResource(R.string.ok)) }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) }
        },
    )
}

@Composable
private fun DeleteDialog(meta: NotebookMeta, onDismiss: () -> Unit, onDelete: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.delete_title)) },
        text = { Text(stringResource(R.string.delete_message, meta.title)) },
        confirmButton = {
            TextButton(
                onClick = onDelete,
                colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error),
            ) { Text(stringResource(R.string.delete)) }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) }
        },
    )
}
