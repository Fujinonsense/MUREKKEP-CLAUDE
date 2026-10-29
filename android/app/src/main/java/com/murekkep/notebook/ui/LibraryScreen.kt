@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class, androidx.compose.foundation.ExperimentalFoundationApi::class)

package com.murekkep.notebook.ui

import android.content.res.Resources
import android.graphics.BitmapFactory
import android.icu.text.RelativeDateTimeFormatter
import android.net.Uri
import android.os.Build
import android.util.LruCache
import androidx.activity.compose.LocalActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.draganddrop.dragAndDropTarget
import androidx.compose.foundation.layout.Arrangement
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
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.layout.wrapContentSize
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.NoteAdd
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material.icons.filled.FileDownload
import androidx.compose.material.icons.outlined.Book
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Description
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.EditNote
import androidx.compose.material.icons.outlined.ExpandMore
import androidx.compose.material.icons.outlined.GridView
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DrawerValue
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.MenuDefaults
import androidx.compose.material3.ModalDrawerSheet
import androidx.compose.material3.ModalNavigationDrawer
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberDrawerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draganddrop.DragAndDropEvent
import androidx.compose.ui.draganddrop.DragAndDropTarget
import androidx.compose.ui.draganddrop.mimeTypes
import androidx.compose.ui.draganddrop.toAndroidDragEvent
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.RectangleShape
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.path
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.murekkep.notebook.R
import com.murekkep.notebook.data.LibraryImport
import com.murekkep.notebook.data.LibraryPreferences
import com.murekkep.notebook.data.NoteKind
import com.murekkep.notebook.data.NotebookMeta
import com.murekkep.notebook.data.NotebookStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.text.DateFormat
import java.time.ZoneId
import java.util.Date
import kotlin.math.max

// The library, the spec's home (LibraryView and LibraryPanes on iPad): a sidebar on paper-2 (the
// "Mürekkep" wordmark with the button that hides the sidebar, search, Tüm notlar, Son açılanlar,
// Defterler, PDF'ler with their counts, Ayarlar pinned under them) and the notes pane, which
// scrolls as one: the section's title with "PDF içe aktar" and "Yeni not", Hepsi / Defterler /
// PDF'ler on Tüm notlar, the order, the PDFs' drop zone, and the notes as the covers of their first
// pages with the title and "3 sayfa, dün" under them. A search shows its results over every note.
// A long press on a note opens its menu (rename, delete; deleting asks first). PDFs and photos can
// be dropped in from other apps. Under 600 dp the sidebar folds into a drawer. The section, the
// filter and the order come back after a relaunch.

/** The sidebar's width, the mockup's 288 points. */
private val SidebarWidth = 288.dp

/** Under this width the sidebar is a drawer. */
private val WideLayout = 600.dp

/** The covers' columns: 190 to 260 dp wide, 28 apart (NoteGrid on iPad). */
private const val CARD_MIN = 190f
private const val CARD_MAX = 260f
private const val CARD_SPACING = 28f

/** How many photos the gallery hands over at once (the iPad's picker takes 30). */
private const val MAX_PHOTOS = 30

/** The warm bath of paper over a light picture (Theme.paperWarm on iPad). */
private val PaperWarm = Color(0xFFFCFAF5)

@Composable
fun LibraryScreen(store: NotebookStore, onOpen: (NotebookMeta) -> Unit, onSettings: () -> Unit = {}) {
    LaunchedEffect(store) { store.load() }
    val context = LocalContext.current
    val prefs = remember(context) { LibraryPreferences(context) }
    val importer = remember(context) { LibraryImport.get(context) }
    var section by rememberSaveable { mutableStateOf(prefs.section) }
    var filter by rememberSaveable { mutableStateOf(prefs.filter) }
    var sort by rememberSaveable { mutableStateOf(prefs.sort) }
    var query by rememberSaveable { mutableStateOf("") }
    var sidebarShown by rememberSaveable { mutableStateOf(true) }
    var renaming by remember { mutableStateOf<NotebookMeta?>(null) }
    var deleting by remember { mutableStateOf<NotebookMeta?>(null) }
    var askingSource by remember { mutableStateOf(false) }
    var choosingTemplate by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()

    // An import from the buttons opens the one note it brought in while the library is here.
    val opener by rememberUpdatedState(onOpen)
    DisposableEffect(importer) {
        importer.onOpen = { opener(it) }
        onDispose { importer.onOpen = null }
    }
    val pickFiles = rememberLauncherForActivityResult(ActivityResultContracts.OpenMultipleDocuments()) { uris ->
        if (uris.isNotEmpty()) importer.importFiles(uris)
    }
    val pickPhotos = rememberLauncherForActivityResult(ActivityResultContracts.PickMultipleVisualMedia(MAX_PHOTOS)) { uris ->
        if (uris.isNotEmpty()) importer.importPhotos(uris)
    }
    val titlePrefix = stringResource(R.string.notebook_default_title)
    val notes = store.notebooks
    val shown = remember(notes, section, filter, sort, query) {
        if (query.isNotBlank()) LibraryRules.searched(notes, query) else LibraryRules.shown(notes, section, filter, sort)
    }

    val appTheme = LocalAppTheme.current.shown
    val picture = rememberBackdropPicture(appTheme.picture)
    // The sidebar and the notes in the picture's look; "Yeni defter" and the dialogs below keep the system's.
    LibraryLook {
        val z = Zen.colors
        BoxWithConstraints(Modifier.fillMaxSize().background(z.paper)) {
            val full = DpSize(maxWidth, maxHeight)
            // A Pro theme's picture (or the ruled paper) lies behind the sidebar and the notes.
            Backdrop(appTheme, picture)
            val sidebar: @Composable (inDrawer: Boolean, onPicked: () -> Unit, onHide: () -> Unit) -> Unit = { inDrawer, onPicked, onHide ->
                Sidebar(
                    notes = notes,
                    section = section,
                    query = query,
                    onQuery = { query = it },
                    onSection = {
                        section = it
                        prefs.section = it
                        query = ""
                        onPicked()
                    },
                    onSettings = onSettings,
                    onHide = onHide,
                    ground = { SidebarGround(picture, full, inDrawer) },
                )
            }
            val main: @Composable (narrow: Boolean, onToggle: (() -> Unit)?) -> Unit = { narrow, onToggle ->
                NotesArea(
                    store = store,
                    notes = shown,
                    loaded = store.loaded,
                    section = section,
                    filter = filter,
                    sort = sort,
                    query = query.trim(),
                    narrow = narrow,
                    importing = importer.running > 0,
                    onToggle = onToggle,
                    onFilter = {
                        filter = it
                        prefs.filter = it
                    },
                    onSort = {
                        sort = it
                        prefs.sort = it
                    },
                    onNew = { choosingTemplate = true },
                    onImport = { askingSource = true },
                    onOpen = onOpen,
                    onRename = { renaming = it },
                    onDelete = { deleting = it },
                    onDrop = { uris, release -> importer.importDropped(uris, release) },
                )
            }
            if (maxWidth >= WideLayout) {
                Row(Modifier.fillMaxSize()) {
                    if (sidebarShown) {
                        Box(Modifier.width(SidebarWidth).fillMaxHeight()) { sidebar(false, {}, { sidebarShown = false }) }
                        Box(Modifier.width(1.dp).fillMaxHeight().background(z.rule))
                    }
                    Box(Modifier.weight(1f).fillMaxHeight()) {
                        main(false, if (sidebarShown) null else ({ sidebarShown = true }))
                    }
                }
            } else {
                val drawer = rememberDrawerState(DrawerValue.Closed)
                val close: () -> Unit = { scope.launch { drawer.close() } }
                ModalNavigationDrawer(
                    drawerState = drawer,
                    drawerContent = {
                        // The sheet given the drawer's state takes Back while the drawer is open.
                        ModalDrawerSheet(
                            drawerState = drawer,
                            drawerContainerColor = Color.Transparent,
                            drawerShape = RectangleShape,
                            windowInsets = WindowInsets(0),
                            modifier = Modifier.width(SidebarWidth),
                        ) {
                            sidebar(true, close, close)
                        }
                    },
                ) {
                    main(true) { scope.launch { drawer.open() } }
                }
            }
            importer.photoProgress?.let { progress ->
                val bottom = WindowInsets.safeDrawing.only(WindowInsetsSides.Bottom).asPaddingValues().calculateBottomPadding()
                PhotoProgressBanner(progress, Modifier.align(Alignment.BottomCenter).padding(start = 16.dp, end = 16.dp, bottom = bottom + 24.dp))
            }
        }
    }

    if (choosingTemplate) {
        TemplateSheet(
            onDismiss = { choosingTemplate = false },
            onPick = { paper ->
                choosingTemplate = false
                onOpen(store.create(newNotebookTitle(titlePrefix), paper))
            },
        )
    }
    if (askingSource) {
        ImportSourceDialog(
            onDismiss = { askingSource = false },
            onFiles = {
                askingSource = false
                pickFiles.launch(arrayOf("application/pdf", "image/*"))
            },
            onPhotos = {
                askingSource = false
                pickPhotos.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
            },
        )
    }
    val failed = importer.failed
    if (failed.isNotEmpty()) {
        AlertDialog(
            onDismissRequest = { importer.clearFailed() },
            confirmButton = { TextButton(onClick = { importer.clearFailed() }) { Text(stringResource(R.string.ok)) } },
            title = { Text(stringResource(R.string.error)) },
            text = { Text(stringResource(R.string.import_failed, failed.joinToString(", "))) },
        )
    }
    renaming?.let { meta ->
        RenameDialog(
            initial = meta.title,
            onDismiss = { renaming = null },
            onRename = { title ->
                store.rename(meta.id, title)
                renaming = null
            },
        )
    }
    deleting?.let { meta ->
        DeleteDialog(
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

// MARK: The backdrop

/** The theme's picture ([res]): at once when the library comes back from a note, else read off the main thread. */
@Composable
private fun rememberBackdropPicture(res: Int?): ImageBitmap? {
    val resources = LocalContext.current.resources
    val picture by produceState(res?.let { BackdropPictures.last(it) }, res) {
        value = res?.let { BackdropPictures.last(it) ?: withContext(Dispatchers.IO) { BackdropPictures.load(resources, it) } }
    }
    return picture
}

/**
 * The theme's picture (2048 px, 16 MB in memory), read once and kept for the process: the library
 * leaves the composition while a note is open, and its picture is back in the first frame. Only
 * the picture in use is kept.
 */
private object BackdropPictures {
    private var res = 0
    private var picture: ImageBitmap? = null

    /** The picture of [res] if it is the one kept, without touching the disk (for the first frame). */
    @Synchronized
    fun last(res: Int): ImageBitmap? = if (res == this.res) picture else null

    /** The picture of [res], from memory or read from the resources (off the main thread). */
    fun load(resources: Resources, res: Int): ImageBitmap? {
        last(res)?.let { return it }
        val read = try {
            BitmapFactory.decodeResource(resources, res)?.asImageBitmap()
        } catch (e: Exception) {
            null
        } ?: return null
        synchronized(this) {
            this.res = res
            picture = read
        }
        return read
    }
}

/** A picture theme's picture under its wash (night over a dark picture, warm paper over a light
 *  one), or the Defter theme's ruled paper; nothing in black and white. */
@Composable
private fun Backdrop(theme: AppTheme, picture: ImageBitmap?) {
    when {
        picture != null -> {
            Image(picture, contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
            Box(Modifier.fillMaxSize().background((if (theme.darkLook == true) Color.Black else PaperWarm).copy(alpha = theme.wash)))
        }
        theme == AppTheme.RULED -> ThemeRuledPaper(spacing = 34.dp, top = 92.dp, modifier = Modifier.fillMaxSize())
    }
}

/**
 * What the sidebar stands on: paper-2 in black and white. Over a Pro theme it is a material (the
 * iPad's .regularMaterial): from Android 12 the picture behind it, blurred, under paper-2 at 70 %;
 * otherwise paper-2 at 84 %, and plain paper-2 in the drawer, which lies over the covers.
 */
@Composable
private fun SidebarGround(picture: ImageBitmap?, full: DpSize, inDrawer: Boolean) {
    val z = Zen.colors
    when {
        !z.proTheme -> Box(Modifier.fillMaxSize().background(z.paper2))
        picture != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> Box(Modifier.fillMaxSize().clipToBounds()) {
            // The picture at the library's size and crop, so the sidebar shows the part it covers.
            Image(
                picture,
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.wrapContentSize(Alignment.TopStart, unbounded = true).requiredSize(full).blur(30.dp),
            )
            Box(Modifier.fillMaxSize().background(z.paper2.copy(alpha = 0.70f)))
        }
        else -> Box(Modifier.fillMaxSize().background(if (inDrawer) z.paper2 else z.paper2.copy(alpha = 0.84f)))
    }
}

// MARK: The sidebar

/** The sidebar: its upper part scrolls (the wordmark, search, the sections), Ayarlar stays under a hairline at the bottom. */
@Composable
private fun Sidebar(
    notes: List<NotebookMeta>,
    section: LibrarySection,
    query: String,
    onQuery: (String) -> Unit,
    onSection: (LibrarySection) -> Unit,
    onSettings: () -> Unit,
    onHide: () -> Unit,
    ground: @Composable () -> Unit,
) {
    val z = Zen.colors
    val (all, notebooks, pdfs) = LibraryRules.counts(notes)
    Box(Modifier.fillMaxSize()) {
        ground()
        Column(Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.safeDrawing.only(WindowInsetsSides.Top + WindowInsetsSides.Start + WindowInsetsSides.Bottom))) {
            Column(
                Modifier
                    .weight(1f)
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = 16.dp)
                    .padding(top = 20.dp, bottom = 16.dp),
                verticalArrangement = Arrangement.spacedBy(20.dp),
            ) {
                Row(Modifier.fillMaxWidth().height(Zen.target).padding(start = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        stringResource(R.string.app_name),
                        style = MaterialTheme.typography.headlineSmall.copy(fontSize = 22.sp, letterSpacing = (-0.4).sp),
                        color = z.ink,
                        maxLines = 1,
                        modifier = Modifier.weight(1f),
                    )
                    BarButton(stringResource(R.string.hide_sidebar), onClick = onHide) {
                        Icon(SidebarGlyph, contentDescription = null, modifier = Modifier.size(22.dp))
                    }
                }
                SearchField(query, onQuery)
                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    NavRow(Icons.Outlined.GridView, stringResource(R.string.library_all_notes), all, section == LibrarySection.ALL) { onSection(LibrarySection.ALL) }
                    NavRow(Icons.Outlined.Schedule, stringResource(R.string.library_recent), null, section == LibrarySection.RECENT) { onSection(LibrarySection.RECENT) }
                    NavRow(Icons.Outlined.Book, stringResource(R.string.library_notebooks), notebooks, section == LibrarySection.NOTEBOOKS) { onSection(LibrarySection.NOTEBOOKS) }
                    NavRow(Icons.Outlined.Description, stringResource(R.string.library_pdfs), pdfs, section == LibrarySection.PDFS) { onSection(LibrarySection.PDFS) }
                }
            }
            Box(Modifier.fillMaxWidth().height(1.dp).background(z.rule))
            Column(Modifier.padding(horizontal = 16.dp, vertical = 12.dp)) {
                NavRow(Icons.Outlined.Settings, stringResource(R.string.settings), null, false, onClick = onSettings)
            }
        }
    }
}

/** The sidebar's glyph (the mockup's and the iPad's sidebar.left): a rounded window with a column on its left. */
private val SidebarGlyph: ImageVector by lazy {
    ImageVector.Builder("Sidebar", 24.dp, 24.dp, 24f, 24f).path(
        stroke = SolidColor(Color.Black),
        strokeLineWidth = 1.6f,
        strokeLineCap = StrokeCap.Round,
        strokeLineJoin = StrokeJoin.Round,
    ) {
        moveTo(5.5f, 5f)
        horizontalLineTo(18.5f)
        arcTo(2f, 2f, 0f, false, true, 20.5f, 7f)
        verticalLineTo(17f)
        arcTo(2f, 2f, 0f, false, true, 18.5f, 19f)
        horizontalLineTo(5.5f)
        arcTo(2f, 2f, 0f, false, true, 3.5f, 17f)
        verticalLineTo(7f)
        arcTo(2f, 2f, 0f, false, true, 5.5f, 5f)
        close()
        moveTo(9.5f, 5f)
        verticalLineTo(19f)
    }.build()
}

/** A row of the sidebar: its glyph, its name and, for a section that holds any, how many notes. */
@Composable
private fun NavRow(icon: ImageVector, title: String, count: Int?, selected: Boolean, onClick: () -> Unit) {
    val z = Zen.colors
    Row(
        Modifier
            .fillMaxWidth()
            .height(40.dp)
            .clip(RoundedCornerShape(Zen.control))
            .background(if (selected) z.paper3 else Color.Transparent)
            .clickable(onClick = onClick)
            .semantics { this.selected = selected }
            .padding(horizontal = 10.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, contentDescription = null, tint = if (selected) z.ink else z.ink2, modifier = Modifier.size(20.dp))
        Text(
            title,
            style = MaterialTheme.typography.bodyLarge,
            fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal,
            color = if (selected) z.ink else z.ink2,
            modifier = Modifier.weight(1f),
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        if (count != null && count > 0) {
            Text(
                count.toString(),
                style = MaterialTheme.typography.bodyMedium.merge(TextStyle(fontFeatureSettings = "tnum")),
                color = z.muted,
            )
        }
    }
}

/** The search over the titles: a 38 dp field in a hairline on paper, with a clear button while it holds a query. */
@Composable
private fun SearchField(query: String, onQuery: (String) -> Unit) {
    val z = Zen.colors
    val label = stringResource(R.string.search)
    val clear = stringResource(R.string.clear_search)
    BasicTextField(
        value = query,
        onValueChange = onQuery,
        singleLine = true,
        textStyle = MaterialTheme.typography.bodyLarge.copy(color = z.ink),
        cursorBrush = SolidColor(z.accent),
        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
        modifier = Modifier.fillMaxWidth().semantics { contentDescription = label },
        decorationBox = { inner ->
            Row(
                Modifier
                    .fillMaxWidth()
                    .height(38.dp)
                    .background(z.paper, RoundedCornerShape(Zen.control))
                    .border(1.dp, z.rule, RoundedCornerShape(Zen.control))
                    .padding(start = 11.dp, end = if (query.isEmpty()) 12.dp else 3.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Icon(Icons.Outlined.Search, contentDescription = null, tint = z.muted, modifier = Modifier.size(18.dp))
                Box(Modifier.weight(1f)) {
                    if (query.isEmpty()) Text(label, style = MaterialTheme.typography.bodyLarge, color = z.muted)
                    inner()
                }
                if (query.isNotEmpty()) {
                    Box(
                        Modifier
                            .size(32.dp)
                            .clip(CircleShape)
                            .clickable { onQuery("") }
                            .semantics { contentDescription = clear },
                        contentAlignment = Alignment.Center,
                    ) {
                        Icon(Icons.Filled.Cancel, contentDescription = null, tint = z.muted, modifier = Modifier.size(18.dp))
                    }
                }
            }
        },
    )
}

// MARK: The notes

/**
 * The notes pane (NotesPane on iPad), or a search's results over every note (SearchPane): one
 * scrolling column of the header, the filter and order, the drop zone, and the covers in rows of
 * the iPad's adaptive grid, start-aligned.
 */
@Composable
private fun NotesArea(
    store: NotebookStore,
    notes: List<NotebookMeta>,
    loaded: Boolean,
    section: LibrarySection,
    filter: LibraryFilter,
    sort: LibrarySort,
    query: String,
    narrow: Boolean,
    importing: Boolean,
    onToggle: (() -> Unit)?,
    onFilter: (LibraryFilter) -> Unit,
    onSort: (LibrarySort) -> Unit,
    onNew: () -> Unit,
    onImport: () -> Unit,
    onOpen: (NotebookMeta) -> Unit,
    onRename: (NotebookMeta) -> Unit,
    onDelete: (NotebookMeta) -> Unit,
    onDrop: (List<Uri>, () -> Unit) -> Unit,
) {
    val searching = query.isNotEmpty()
    val side = if (narrow) 16.dp else 40.dp
    var dropping by remember { mutableStateOf(false) }
    val activity = LocalActivity.current
    val dropper by rememberUpdatedState(onDrop)
    val target = remember(activity) {
        object : DragAndDropTarget {
            override fun onEntered(event: DragAndDropEvent) {
                dropping = true
            }

            override fun onExited(event: DragAndDropEvent) {
                dropping = false
            }

            override fun onEnded(event: DragAndDropEvent) {
                dropping = false
            }

            override fun onDrop(event: DragAndDropEvent): Boolean {
                dropping = false
                val drag = event.toAndroidDragEvent()
                val clip = drag.clipData ?: return false
                val uris = (0 until clip.itemCount).mapNotNull { clip.getItemAt(it).uri }
                if (uris.isEmpty()) return false
                // Another app's files can be read only while the drop's permissions are held.
                val permissions = activity?.requestDragAndDropPermissions(drag)
                dropper(uris) { permissions?.release() }
                return true
            }
        }
    }
    val bottom = WindowInsets.safeDrawing.only(WindowInsetsSides.Bottom).asPaddingValues().calculateBottomPadding()
    // Each section, and the search, keeps its own place in the list.
    val list = key(section, searching) { rememberLazyListState() }
    // The start edge is the sidebar's, unless the sidebar is away.
    val edges = if (onToggle != null) WindowInsetsSides.Top + WindowInsetsSides.Horizontal else WindowInsetsSides.Top + WindowInsetsSides.End
    BoxWithConstraints(
        Modifier
            .fillMaxSize()
            .windowInsetsPadding(WindowInsets.safeDrawing.only(edges))
            .then(
                if (searching) {
                    Modifier
                } else {
                    Modifier.dragAndDropTarget(
                        shouldStartDragAndDrop = { event -> event.mimeTypes().any { it == "application/pdf" || it.startsWith("image/") } },
                        target = target,
                    )
                },
            ),
    ) {
        val (columns, width) = LibraryRules.adaptiveColumns((maxWidth - side * 2).value, CARD_MIN, CARD_MAX, CARD_SPACING)
        val cardWidth = (width - 0.5f).dp
        val rows = remember(notes, columns) { notes.chunked(columns) }
        LazyColumn(
            state = list,
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(start = side, end = side, top = if (narrow) 12.dp else 28.dp, bottom = bottom + 40.dp),
            verticalArrangement = Arrangement.spacedBy(24.dp),
        ) {
            item(key = "header") {
                if (searching) {
                    PaneHeader("“$query”", pluralStringResource(R.plurals.search_results, notes.size, notes.size), narrow, onToggle) {}
                } else {
                    PaneHeader(stringResource(section.titleRes), null, narrow, onToggle) {
                        ZenButton(stringResource(if (importing) R.string.importing_pdf else R.string.import_pdf), filled = false, enabled = !importing, onClick = onImport)
                        ZenButton(stringResource(R.string.new_notebook), filled = true, onClick = onNew)
                    }
                }
            }
            if (!searching && section != LibrarySection.RECENT) {
                item(key = "order") { OrderRow(section, filter, sort, onFilter, onSort) }
            }
            if (!searching && section == LibrarySection.PDFS) {
                item(key = "drop") { DropZone(dropping, onImport) }
            }
            when {
                notes.isEmpty() -> if (loaded) item(key = "empty") { EmptyNotes(section, query) }
                else -> {
                    if (searching) {
                        item(key = "notes") {
                            Text(stringResource(R.string.notes), style = MaterialTheme.typography.titleLarge.copy(fontSize = 20.sp), color = Zen.colors.ink)
                        }
                    }
                    items(rows, key = { "row:" + it.first().id }) { row ->
                        Row(Modifier.padding(bottom = 8.dp), horizontalArrangement = Arrangement.spacedBy(CARD_SPACING.dp)) {
                            for (meta in row) {
                                key(meta.id) {
                                    NoteCard(
                                        meta = meta,
                                        cover = store.thumbFile(meta.id),
                                        coverVersion = store.coverVersion,
                                        onOpen = { onOpen(meta) },
                                        onRename = { onRename(meta) },
                                        onDelete = { onDelete(meta) },
                                        modifier = Modifier.width(cardWidth),
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
        // A drag over any section but PDF'ler (whose drop zone lights up instead).
        if (dropping && section != LibrarySection.PDFS) {
            DropOverlay(Modifier.matchParentSize().padding(16.dp))
        }
    }
}

private val LibrarySection.titleRes: Int
    get() = when (this) {
        LibrarySection.ALL -> R.string.library_all_notes
        LibrarySection.RECENT -> R.string.library_recent
        LibrarySection.NOTEBOOKS -> R.string.library_notebooks
        LibrarySection.PDFS -> R.string.library_pdfs
    }

/** The big title, the sidebar's button while the sidebar is away, and the pane's buttons on the right. */
@Composable
private fun PaneHeader(title: String, subtitle: String?, narrow: Boolean, onToggle: (() -> Unit)?, trailing: @Composable RowScope.() -> Unit) {
    val z = Zen.colors
    Row(
        Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (onToggle != null) {
            BarButton(stringResource(R.string.show_sidebar), onClick = onToggle) {
                Icon(SidebarGlyph, contentDescription = null, modifier = Modifier.size(22.dp))
            }
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(
                title,
                style = if (narrow) MaterialTheme.typography.headlineMedium else MaterialTheme.typography.headlineLarge,
                color = z.ink,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            if (subtitle != null) {
                Text(subtitle, style = MaterialTheme.typography.bodyMedium, color = z.muted, maxLines = 2)
            }
        }
        trailing()
    }
}

/** Hepsi / Defterler / PDF'ler on Tüm notlar (up to 320 dp) and the order, except on Son açılanlar. */
@Composable
private fun OrderRow(section: LibrarySection, filter: LibraryFilter, sort: LibrarySort, onFilter: (LibraryFilter) -> Unit, onSort: (LibrarySort) -> Unit) {
    Row(
        Modifier.fillMaxWidth(),
        horizontalArrangement = if (section == LibrarySection.ALL) Arrangement.SpaceBetween else Arrangement.End,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (section == LibrarySection.ALL) {
            FilterSegments(filter, onFilter, Modifier.weight(1f, fill = false).widthIn(max = 320.dp))
        }
        SortMenu(sort, onSort, Modifier.padding(start = 12.dp))
    }
}

/**
 * The filter as the iPad's segmented picker: a paper-3 track, the picked segment on paper with a
 * hairline, the labels at the picker's 13 sp. The segments are equal while every label fits in an
 * equal share; on a phone, where one would be cut, each takes its label's width
 * ([LibraryRules.segmentWidths]).
 */
@Composable
private fun FilterSegments(filter: LibraryFilter, onFilter: (LibraryFilter) -> Unit, modifier: Modifier) {
    val z = Zen.colors
    val label = stringResource(R.string.filter_label)
    Layout(
        content = {
            for (option in LibraryFilter.entries) {
                val on = option == filter
                Box(
                    Modifier
                        .height(32.dp)
                        .clip(RoundedCornerShape(8.dp))
                        .background(if (on) z.paper else Color.Transparent)
                        .then(if (on) Modifier.border(1.dp, z.rule, RoundedCornerShape(8.dp)) else Modifier)
                        .clickable { onFilter(option) }
                        .semantics { this.selected = on }
                        .padding(horizontal = 4.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        stringResource(option.titleRes),
                        style = MaterialTheme.typography.bodySmall,
                        fontWeight = if (on) FontWeight.SemiBold else FontWeight.Normal,
                        color = if (on) z.ink else z.ink2,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }
        },
        modifier = modifier.background(z.paper3, RoundedCornerShape(Zen.control)).padding(2.dp).semantics { contentDescription = label },
    ) { segments, constraints ->
        val natural = segments.map { it.maxIntrinsicWidth(constraints.maxHeight) }
        val total = if (constraints.hasBoundedWidth) constraints.maxWidth else natural.sum()
        val widths = LibraryRules.segmentWidths(natural, total)
        val placed = segments.mapIndexed { i, segment -> segment.measure(Constraints.fixedWidth(widths[i])) }
        layout(widths.sum(), placed.maxOf { it.height }) {
            var x = 0
            for (p in placed) {
                p.placeRelative(x, 0)
                x += p.width
            }
        }
    }
}

private val LibraryFilter.titleRes: Int
    get() = when (this) {
        LibraryFilter.ALL -> R.string.all
        LibraryFilter.NOTEBOOKS -> R.string.library_notebooks
        LibraryFilter.PDFS -> R.string.library_pdfs
    }

/** A 40 dp button: in ink with paper text when [filled], else paper-2 in a hairline. */
@Composable
fun ZenButton(label: String, filled: Boolean, enabled: Boolean = true, onClick: () -> Unit) {
    val z = Zen.colors
    val shape = RoundedCornerShape(Zen.control)
    Box(
        Modifier
            .height(40.dp)
            .clip(shape)
            .background(if (filled) z.ink else z.paper2)
            .border(1.dp, if (filled) z.ink else z.rule, shape)
            .clickable(enabled = enabled, onClick = onClick)
            .padding(horizontal = 16.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            label,
            style = MaterialTheme.typography.labelLarge,
            color = when {
                !enabled -> z.muted
                filled -> z.paper
                else -> z.ink
            },
            maxLines = 1,
        )
    }
}

/** "Son düzenlenen ⌄": the order of the notes, the chosen one ticked in its menu. */
@Composable
private fun SortMenu(sort: LibrarySort, onSort: (LibrarySort) -> Unit, modifier: Modifier) {
    val z = Zen.colors
    var open by remember { mutableStateOf(false) }
    val label = stringResource(R.string.sort_label)
    Box(modifier) {
        Row(
            Modifier
                .height(36.dp)
                .clip(RoundedCornerShape(Zen.control))
                .clickable { open = true }
                .semantics { contentDescription = label }
                .padding(horizontal = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Text(stringResource(sort.titleRes), style = MaterialTheme.typography.bodyMedium, color = z.ink2, maxLines = 1)
            Icon(Icons.Outlined.ExpandMore, contentDescription = null, tint = z.ink2, modifier = Modifier.size(16.dp))
        }
        ZenMenu(expanded = open, onDismissRequest = { open = false }) {
            for (option in LibrarySort.entries) {
                DropdownMenuItem(
                    text = { Text(stringResource(option.titleRes)) },
                    leadingIcon = {
                        if (option == sort) {
                            Icon(Icons.Outlined.Check, contentDescription = null, modifier = Modifier.size(18.dp))
                        } else {
                            Spacer(Modifier.size(18.dp))
                        }
                    },
                    onClick = {
                        open = false
                        onSort(option)
                    },
                )
            }
        }
    }
}

private val LibrarySort.titleRes: Int
    get() = when (this) {
        LibrarySort.MODIFIED -> R.string.sort_modified
        LibrarySort.TITLE -> R.string.sort_title
    }

/** The empty pane's word for each section (ContentUnavailableView on iPad), 30 dp under the filter. */
@Composable
private fun EmptyNotes(section: LibrarySection, query: String) {
    when {
        query.isNotEmpty() -> EmptyState(Icons.Outlined.Search, stringResource(R.string.search_empty, query), stringResource(R.string.search_empty_hint))
        section == LibrarySection.NOTEBOOKS -> EmptyState(Icons.Outlined.Book, stringResource(R.string.empty_notebooks_title), stringResource(R.string.empty_notebooks_text))
        section == LibrarySection.PDFS -> EmptyState(Icons.Outlined.Description, stringResource(R.string.empty_pdfs_title), stringResource(R.string.empty_pdfs_text))
        else -> EmptyState(Icons.Outlined.EditNote, stringResource(R.string.library_empty_title), stringResource(R.string.empty_home_text))
    }
}

@Composable
private fun EmptyState(icon: ImageVector, title: String, text: String) {
    val z = Zen.colors
    Column(
        Modifier.fillMaxWidth().padding(top = 30.dp, start = 16.dp, end = 16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Icon(icon, contentDescription = null, tint = z.muted, modifier = Modifier.size(44.dp))
        Spacer(Modifier.height(16.dp))
        Text(title, style = MaterialTheme.typography.headlineSmall, color = z.ink, textAlign = TextAlign.Center)
        Spacer(Modifier.height(8.dp))
        Text(text, style = MaterialTheme.typography.bodyMedium, color = z.muted, textAlign = TextAlign.Center)
    }
}

// MARK: Dropping and importing

/** PDF'ler's dashed box to drop PDFs on, with a button for the picker; it lights up in the accent while a drag hovers. */
@Composable
private fun DropZone(targeted: Boolean, onPick: () -> Unit) {
    val z = Zen.colors
    val edge = if (targeted) z.accent else z.rule
    Row(
        Modifier
            .fillMaxWidth()
            .background(if (targeted) z.accent.copy(alpha = 0.06f) else z.paper2, RoundedCornerShape(12.dp))
            .dashedBorder(edge, 1.dp, 12.dp, 6.dp, 4.dp)
            .padding(16.dp),
        horizontalArrangement = Arrangement.spacedBy(16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.size(Zen.target), contentAlignment = Alignment.Center) {
            Icon(
                if (targeted) Icons.Filled.FileDownload else Icons.AutoMirrored.Outlined.NoteAdd,
                contentDescription = null,
                tint = if (targeted) z.accent else z.ink2,
                modifier = Modifier.size(26.dp),
            )
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(
                stringResource(if (targeted) R.string.drop_release else R.string.drop_title),
                style = MaterialTheme.typography.bodyLarge,
                fontWeight = FontWeight.SemiBold,
                color = z.ink,
            )
            Text(stringResource(R.string.drop_detail), style = MaterialTheme.typography.bodyMedium, color = z.muted)
        }
        ZenButton(stringResource(R.string.drop_choose), filled = false, onClick = onPick)
    }
}

/** Over the pane while PDFs are dragged across it: a dashed frame in the accent, "PDF'leri kütüphaneye bırak". */
@Composable
private fun DropOverlay(modifier: Modifier) {
    val z = Zen.colors
    Box(
        modifier
            .background(z.accent.copy(alpha = 0.05f), RoundedCornerShape(12.dp))
            .dashedBorder(z.accent, 2.dp, 12.dp, 8.dp, 6.dp),
        contentAlignment = Alignment.Center,
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Filled.FileDownload, contentDescription = null, tint = z.accent, modifier = Modifier.size(22.dp))
            Text(stringResource(R.string.drop_library), style = MaterialTheme.typography.titleMedium, color = z.accent)
        }
    }
}

/** A dashed hairline inside the box's edge, [dash] on and [gap] off, with [corner] corners. */
private fun Modifier.dashedBorder(color: Color, width: Dp, corner: Dp, dash: Dp, gap: Dp): Modifier = drawBehind {
    val w = width.toPx()
    drawRoundRect(
        color = color,
        topLeft = Offset(w / 2f, w / 2f),
        size = Size(size.width - w, size.height - w),
        cornerRadius = CornerRadius(corner.toPx() - w / 2f),
        style = Stroke(width = w, pathEffect = PathEffect.dashPathEffect(floatArrayOf(dash.toPx(), gap.toPx()))),
    )
}

/** "PDF ya da fotoğraf ekle": the files (PDFs or photos) or the gallery, as the iPad asks. */
@Composable
private fun ImportSourceDialog(onDismiss: () -> Unit, onFiles: () -> Unit, onPhotos: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.import_title)) },
        text = {
            Column {
                Text(stringResource(R.string.import_message))
                Spacer(Modifier.height(12.dp))
                SourceChoice(stringResource(R.string.import_from_files), onFiles)
                SourceChoice(stringResource(R.string.import_from_photos), onPhotos)
            }
        },
        confirmButton = {},
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) } },
    )
}

@Composable
private fun SourceChoice(label: String, onClick: () -> Unit) {
    Box(
        Modifier
            .fillMaxWidth()
            .heightIn(min = 48.dp)
            .clip(RoundedCornerShape(Zen.control))
            .clickable(onClick = onClick)
            .padding(horizontal = 4.dp),
        contentAlignment = Alignment.CenterStart,
    ) {
        Text(label, style = MaterialTheme.typography.bodyLarge, color = Zen.colors.accent)
    }
}

/** Photos on their way into one PDF: the count, so thirty photos do not look like a hang. */
@Composable
private fun PhotoProgressBanner(progress: LibraryImport.PhotoProgress, modifier: Modifier) {
    val z = Zen.colors
    Row(
        modifier
            .widthIn(max = 520.dp)
            .fillMaxWidth()
            .floating(Zen.popover)
            .padding(14.dp),
        horizontalArrangement = Arrangement.spacedBy(14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        CircularProgressIndicator(Modifier.size(20.dp), color = z.ink2, strokeWidth = 2.dp)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(
                stringResource(R.string.import_photo_progress, progress.done, progress.total),
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.SemiBold,
                color = z.ink,
            )
            LinearProgressIndicator(
                progress = { progress.done / max(1, progress.total).toFloat() },
                modifier = Modifier.fillMaxWidth(),
                color = z.accent,
                trackColor = z.paper3,
            )
        }
    }
}

// MARK: A note's cover

/** A note on the shelf: its first page as the 3:4 cover, the title on one line, "3 sayfa, dün"; a long press opens its menu. */
@Composable
private fun NoteCard(
    meta: NotebookMeta,
    cover: File,
    coverVersion: Int,
    onOpen: () -> Unit,
    onRename: () -> Unit,
    onDelete: () -> Unit,
    modifier: Modifier,
) {
    val z = Zen.colors
    var menuOpen by remember { mutableStateOf(false) }
    val locale = LocalConfiguration.current.locales[0]
    val formatter = remember(locale) { RelativeDateTimeFormatter.getInstance(locale) }
    val pages = LibraryRules.pagesShown(meta.pageCount)
    val pagesText = pluralStringResource(R.plurals.pages, pages, pages)
    val line = buildList {
        if (meta.kind == NoteKind.PDF) add(stringResource(R.string.pdf_label))
        add(pagesText)
        add(relativeDate(meta.modified, formatter))
    }.joinToString(", ")
    val more = stringResource(R.string.more_actions)
    val shape = RoundedCornerShape(Zen.control)
    Column(
        modifier
            .clip(shape)
            .combinedClickable(onClick = onOpen, onLongClickLabel = more, onLongClick = { menuOpen = true })
            .semantics { contentDescription = meta.title },
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Box(
            Modifier
                .fillMaxWidth()
                .aspectRatio(0.75f)
                .clip(shape)
                .background(Color.White)
                .border(1.dp, z.rule, shape),
        ) {
            CoverPicture(cover, coverVersion, meta, Modifier.fillMaxSize())
        }
        // The menu opens under the title.
        Box {
            Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(meta.title, style = MaterialTheme.typography.titleMedium.copy(fontSize = 16.sp), color = z.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(line, style = MaterialTheme.typography.bodySmall, color = z.muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
            NoteMenu(
                expanded = menuOpen,
                onDismiss = { menuOpen = false },
                onRename = {
                    menuOpen = false
                    onRename()
                },
                onDelete = {
                    menuOpen = false
                    onDelete()
                },
            )
        }
    }
}

/** A note's menu (NoteMenu on iPad): Yeniden adlandır with its pencil, then Sil in red with its bin. */
@Composable
private fun NoteMenu(expanded: Boolean, onDismiss: () -> Unit, onRename: () -> Unit, onDelete: () -> Unit) {
    val error = MaterialTheme.colorScheme.error
    ZenMenu(expanded = expanded, onDismissRequest = onDismiss) {
        DropdownMenuItem(
            text = { Text(stringResource(R.string.rename)) },
            trailingIcon = { Icon(Icons.Outlined.Edit, contentDescription = null, modifier = Modifier.size(20.dp)) },
            onClick = onRename,
        )
        HorizontalDivider(Modifier.padding(vertical = 4.dp), color = Zen.colors.rule)
        DropdownMenuItem(
            text = { Text(stringResource(R.string.delete)) },
            trailingIcon = { Icon(Icons.Outlined.Delete, contentDescription = null, modifier = Modifier.size(20.dp)) },
            onClick = onDelete,
            colors = MenuDefaults.itemColors(textColor = error, trailingIconColor = error),
        )
    }
}

/**
 * The time under a cover in the iPad's named words, spelled out: "8 saniye önce", "15 dakika
 * önce", "dün", "evvelsi gün", "geçen hafta", "3 hafta önce", "geçen ay"; "şimdi" for this very
 * second. The named forms are the language's own and only where it has one ("evvelsi gün" in
 * Turkish, "2 days ago" in English).
 */
private fun relativeDate(millis: Long, formatter: RelativeDateTimeFormatter): String {
    val age = LibraryRules.relativeAge(millis, System.currentTimeMillis(), ZoneId.systemDefault())
    val n = age.count
    if (n == 0) return formatter.format(RelativeDateTimeFormatter.Direction.PLAIN, RelativeDateTimeFormatter.AbsoluteUnit.NOW)
    val absolute = when (age.unit) {
        AgeUnit.DAY -> RelativeDateTimeFormatter.AbsoluteUnit.DAY
        AgeUnit.WEEK -> RelativeDateTimeFormatter.AbsoluteUnit.WEEK
        AgeUnit.MONTH -> RelativeDateTimeFormatter.AbsoluteUnit.MONTH
        AgeUnit.YEAR -> RelativeDateTimeFormatter.AbsoluteUnit.YEAR
        else -> null
    }
    if (absolute != null && n == 1) {
        formatter.format(RelativeDateTimeFormatter.Direction.LAST, absolute)?.takeIf { it.isNotEmpty() }?.let { return it }
    }
    if (absolute == RelativeDateTimeFormatter.AbsoluteUnit.DAY && n == 2) {
        formatter.format(RelativeDateTimeFormatter.Direction.LAST_2, absolute)?.takeIf { it.isNotEmpty() }?.let { return it }
    }
    val unit = when (age.unit) {
        AgeUnit.SECOND -> RelativeDateTimeFormatter.RelativeUnit.SECONDS
        AgeUnit.MINUTE -> RelativeDateTimeFormatter.RelativeUnit.MINUTES
        AgeUnit.HOUR -> RelativeDateTimeFormatter.RelativeUnit.HOURS
        AgeUnit.DAY -> RelativeDateTimeFormatter.RelativeUnit.DAYS
        AgeUnit.WEEK -> RelativeDateTimeFormatter.RelativeUnit.WEEKS
        AgeUnit.MONTH -> RelativeDateTimeFormatter.RelativeUnit.MONTHS
        AgeUnit.YEAR -> RelativeDateTimeFormatter.RelativeUnit.YEARS
    }
    return formatter.format(n.toDouble(), RelativeDateTimeFormatter.Direction.LAST, unit)
}

/** The cover: the note's first page (`thumb.jpg`, read off the main thread and kept in memory, so
 *  a card coming back into view shows it at once), else a notebook's own blank page or, for a PDF
 *  not drawn yet, its glyph on white: the page stays paper at night. */
@Composable
private fun CoverPicture(file: File, version: Int, meta: NotebookMeta, modifier: Modifier) {
    val picture by produceState(CoverCache.last(file), file, version) {
        value = withContext(Dispatchers.IO) { CoverCache.load(file) }
    }
    val p = picture
    when {
        p != null -> Image(p, contentDescription = null, contentScale = ContentScale.Crop, modifier = modifier)
        meta.kind == NoteKind.PDF -> Box(modifier.background(Color.White), contentAlignment = Alignment.Center) {
            Icon(Icons.Outlined.Description, contentDescription = null, tint = Zen.colors.muted, modifier = Modifier.size(30.dp))
        }
        else -> PaperPage(meta.paper, modifier)
    }
}

/**
 * The covers read so far (cachedThumbnail on iPad), by file, with the file's time and size: the
 * card shows the last one at once and swaps it only when the file has changed.
 */
private object CoverCache {
    private class Entry(val stamp: Long, val picture: ImageBitmap)

    private val entries = object : LruCache<String, Entry>((Runtime.getRuntime().maxMemory() / 8).coerceAtMost(64L shl 20).toInt()) {
        override fun sizeOf(key: String, value: Entry): Int = value.picture.width * value.picture.height * 4
    }

    /** The cover last read for this file, without touching the disk (for the first frame). */
    fun last(file: File): ImageBitmap? = entries.get(file.path)?.picture

    /** The cover on disk now, from memory while the file is unchanged (off the main thread). */
    fun load(file: File): ImageBitmap? {
        if (!file.isFile) {
            entries.remove(file.path)
            return null
        }
        val stamp = file.lastModified() * 31 + file.length()
        entries.get(file.path)?.takeIf { it.stamp == stamp }?.let { return it.picture }
        val picture = try {
            BitmapFactory.decodeFile(file.path)?.asImageBitmap()
        } catch (e: Exception) {
            null
        } ?: return null
        entries.put(file.path, Entry(stamp, picture))
        return picture
    }
}

// MARK: Dialogs

/** The iPad's rename alert: "Yeniden adlandır", the name with the cursor after it, "Vazgeç" and "Kaydet". */
@Composable
internal fun RenameDialog(initial: String, onDismiss: () -> Unit, onRename: (String) -> Unit) {
    // The cursor starts after the name, as the alert's field puts it: typing goes on from its end.
    var value by remember(initial) { mutableStateOf(TextFieldValue(initial, TextRange(initial.length))) }
    val focus = remember { FocusRequester() }
    val submit: () -> Unit = {
        if (value.text.isNotBlank()) onRename(value.text.trim())
    }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.rename_title)) },
        text = {
            OutlinedTextField(
                value = value,
                onValueChange = { value = it },
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
            TextButton(onClick = submit, enabled = value.text.isNotBlank()) { Text(stringResource(R.string.save)) }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) }
        },
    )
}

/** "Bu not silinsin mi?": the note and everything written on it go for good. */
@Composable
private fun DeleteDialog(onDismiss: () -> Unit, onDelete: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.delete_title)) },
        text = { Text(stringResource(R.string.delete_message)) },
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
