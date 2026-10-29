package com.murekkep.notebook

import android.content.pm.ApplicationInfo
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.murekkep.notebook.data.AppearancePreferences
import com.murekkep.notebook.data.NotebookStore
import com.murekkep.notebook.export.PdfShare
import com.murekkep.notebook.ui.AppTheme
import com.murekkep.notebook.ui.EditorScreen
import com.murekkep.notebook.ui.EditorState
import com.murekkep.notebook.ui.LibraryScreen
import com.murekkep.notebook.ui.MurekkepTheme
import com.murekkep.notebook.ui.SettingsScreen
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

/** The library (or the settings), and the editor over it while a notebook is open: plain state, no navigation library. */
@Composable
private fun MurekkepApp(store: NotebookStore, demo: Boolean, theme: AppTheme, onTheme: (AppTheme) -> Unit) {
    var openId by rememberSaveable { mutableStateOf<String?>(null) }
    var settingsOpen by rememberSaveable { mutableStateOf(false) }
    var editor by remember { mutableStateOf<EditorState?>(null) }
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
    if (id == null) {
        if (settingsOpen) {
            BackHandler { settingsOpen = false }
            SettingsScreen(theme = theme, onTheme = onTheme, onBack = { settingsOpen = false })
        } else {
            LibraryScreen(store = store, onOpen = { openId = it.id }, onSettings = { settingsOpen = true })
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
        Opening()
    } else {
        val context = LocalContext.current
        val scope = rememberCoroutineScope()
        val snackbar = remember { SnackbarHostState() }
        val exportFailed = stringResource(R.string.export_failed)
        var sharing by remember { mutableStateOf(false) }
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
                        } catch (e: Exception) {
                            snackbar.showSnackbar(exportFailed)
                        } finally {
                            sharing = false
                        }
                    }
                }
            },
            onRename = { title ->
                store.rename(id, title)
                state.title = title
            },
            snackbar = snackbar,
        )
    }
}

@Composable
private fun Opening() {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            CircularProgressIndicator()
            Spacer(Modifier.height(16.dp))
            Text(
                stringResource(R.string.opening),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}
