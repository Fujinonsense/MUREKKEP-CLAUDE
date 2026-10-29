package com.murekkep.notebook

import android.content.pm.ApplicationInfo
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.murekkep.notebook.data.AppearancePreferences
import com.murekkep.notebook.data.NotebookStore
import com.murekkep.notebook.export.PdfShare
import com.murekkep.notebook.ui.ActivityBars
import com.murekkep.notebook.ui.AppTheme
import com.murekkep.notebook.ui.EditorBar
import com.murekkep.notebook.ui.EditorScreen
import com.murekkep.notebook.ui.EditorState
import com.murekkep.notebook.ui.LibraryScreen
import com.murekkep.notebook.ui.MurekkepTheme
import com.murekkep.notebook.ui.SettingsScreen
import com.murekkep.notebook.ui.Zen
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        val store = NotebookStore.get(this)
        val appearance = AppearancePreferences(this)
        // The emulator check (DemoInk): debuggable builds only.
        val debuggable = (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
        val demo = debuggable && savedInstanceState == null && intent?.getStringExtra(DemoInk.EXTRA) != null
        setContent {
            var theme by remember { mutableStateOf(appearance.theme) }
            MurekkepTheme(theme = theme) {
                Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
                    MurekkepApp(
                        store, demo, theme,
                        onTheme = {
                            theme = it
                            appearance.theme = it
                        },
                    )
                }
            }
        }
    }
}

/**
 * The library, with Ayarlar as a sheet over it, and the editor in its place while a notebook is
 * open: plain state, no navigation library. The library keeps its section, search and scroll
 * while a note is open, as the iPad's stays under the pushed editor.
 */
@Composable
private fun MurekkepApp(store: NotebookStore, demo: Boolean, theme: AppTheme, onTheme: (AppTheme) -> Unit) {
    var openId by rememberSaveable { mutableStateOf<String?>(null) }
    var settingsOpen by rememberSaveable { mutableStateOf(false) }
    var editor by remember { mutableStateOf<EditorState?>(null) }
    val library = rememberSaveableStateHolder()
    if (demo) {
        LaunchedEffect(Unit) {
            store.load()
            val meta = store.create("Demo")
            val state = store.open(meta)
            DemoInk.fill(state)
            editor = state
            openId = meta.id
        }
    }
    val id = openId
    // The bars follow the screen in front: the library in its picture's look, the editor in the system's.
    val systemDark = Zen.colors.dark
    ActivityBars(if (id == null) theme.libraryDark(systemDark) else systemDark)
    if (id == null) {
        Box(Modifier.fillMaxSize()) {
            library.SaveableStateProvider("library") {
                LibraryScreen(
                    store = store,
                    onOpen = {
                        settingsOpen = false
                        openId = it.id
                    },
                    onSettings = { settingsOpen = true },
                )
            }
            if (settingsOpen) {
                SettingsScreen(theme = theme, onTheme = onTheme, onBack = { settingsOpen = false })
            }
        }
        return
    }

    val close = {
        editor?.let { store.saveNow(it) }
        editor = null
        openId = null
    }
    BackHandler(onBack = close)

    LaunchedEffect(id) {
        // Already open (the demo hands its notebook over open).
        if (editor?.notebookId == id) return@LaunchedEffect
        store.load()
        val meta = store.notebook(id)
        if (meta == null) {
            openId = null
            return@LaunchedEffect
        }
        editor = store.open(meta)
    }

    val state = editor
    if (state == null || state.notebookId != id) {
        Opening(store.notebook(id)?.title ?: "", onBack = close)
    } else {
        val context = LocalContext.current
        val scope = rememberCoroutineScope()
        var sharing by remember { mutableStateOf(false) }
        var exportFailed by remember { mutableStateOf(false) }
        EditorScreen(
            state = state,
            onBack = close,
            onShare = {
                if (!sharing) {
                    sharing = true
                    scope.launch {
                        try {
                            val file = PdfShare.write(context, state)
                            PdfShare.share(context, file, state.title)
                        } catch (e: CancellationException) {
                            throw e
                        } catch (e: Exception) {
                            exportFailed = true
                        } finally {
                            sharing = false
                        }
                    }
                }
            },
            settings = { close -> SettingsScreen(theme = theme, onTheme = onTheme, onBack = close) },
        )
        // A failed export is an alert, as on the iPad, and the share button is free again at once.
        if (exportFailed) {
            AlertDialog(
                onDismissRequest = { exportFailed = false },
                title = { Text(stringResource(R.string.export_failed_title)) },
                text = { Text(stringResource(R.string.export_failed)) },
                confirmButton = { TextButton(onClick = { exportFailed = false }) { Text(stringResource(R.string.ok)) } },
            )
        }
    }
}

/**
 * A note on its way in, while its ink (and an imported PDF's pages) are read off the main thread:
 * the editor's ground and its bar with "‹ Notlar" and the title at once, so the note opens as the
 * editor appearing, as the iPad's does with no loading screen. Only a read that takes longer than
 * 300 ms brings in a spinner and "Açılıyor…".
 */
@Composable
private fun Opening(title: String, onBack: () -> Unit) {
    val z = Zen.colors
    var slow by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) {
        delay(300)
        slow = true
    }
    Column(Modifier.fillMaxSize().background(z.paper3)) {
        EditorBar(title, onBack) {}
        Box(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) {
            if (slow) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    CircularProgressIndicator(Modifier.size(28.dp), color = z.muted, strokeWidth = 2.5.dp)
                    Spacer(Modifier.height(16.dp))
                    Text(stringResource(R.string.opening), style = MaterialTheme.typography.bodyMedium, color = z.muted)
                }
            }
        }
    }
}
