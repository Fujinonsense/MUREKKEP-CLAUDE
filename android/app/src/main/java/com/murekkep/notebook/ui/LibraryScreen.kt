@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class, androidx.compose.foundation.ExperimentalFoundationApi::class)

package com.murekkep.notebook.ui

import android.graphics.BitmapFactory
import android.icu.text.RelativeDateTimeFormatter
import android.text.format.DateUtils
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.LibraryBooks
import androidx.compose.material.icons.outlined.Book
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.ExpandMore
import androidx.compose.material.icons.outlined.Menu
import androidx.compose.material.icons.outlined.MoreHoriz
import androidx.compose.material.icons.outlined.PictureAsPdf
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.DrawerValue
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalDrawerSheet
import androidx.compose.material3.ModalNavigationDrawer
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberDrawerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.RectangleShape
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.murekkep.notebook.R
import com.murekkep.notebook.data.NoteKind
import com.murekkep.notebook.data.NotebookMeta
import com.murekkep.notebook.data.NotebookStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.text.DateFormat
import java.util.Date

// The library, the spec's home: a sidebar on paper-2 (the "Mürekkep" wordmark, search, Tüm notlar,
// Son açılanlar, Defterler, PDF'ler with their counts, Ayarlar at the bottom) and the main area
// (the section's title, "PDF içe aktar" and "Yeni not", Hepsi / Defterler / PDF'ler, the order, the
// notes as the covers of their first pages with the title and "3 sayfa, dün" under them). A note's
// menu (a long press, or the dots by its title) renames or deletes it; deleting asks first. Under
// 600 dp the sidebar folds into a drawer behind a menu button.

/** The sidebar's width, the mockup's 288 points. */
private val SidebarWidth = 288.dp

/** Under this width the sidebar is a drawer. */
private val WideLayout = 600.dp

@Composable
fun LibraryScreen(store: NotebookStore, onOpen: (NotebookMeta) -> Unit, onSettings: () -> Unit = {}) {
    LaunchedEffect(store) { store.load() }
    val z = Zen.colors
    var section by rememberSaveable { mutableStateOf(LibrarySection.ALL) }
    var sort by rememberSaveable { mutableStateOf(LibrarySort.MODIFIED) }
    var query by rememberSaveable { mutableStateOf("") }
    var renaming by remember { mutableStateOf<NotebookMeta?>(null) }
    var deleting by remember { mutableStateOf<NotebookMeta?>(null) }
    var importFailed by remember { mutableStateOf(false) }
    var importing by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val pickPdf = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        importing = true
        scope.launch {
            val meta = store.importPdf(uri)
            importing = false
            if (meta == null) importFailed = true else onOpen(meta)
        }
    }
    val titlePrefix = stringResource(R.string.notebook_default_title)
    val notes = store.notebooks
    val shown = remember(notes, section, sort, query) { LibraryRules.shown(notes, section, sort, query) }

    val sidebar: @Composable (onPicked: () -> Unit) -> Unit = { onPicked ->
        Sidebar(
            notes = notes,
            section = section,
            query = query,
            onQuery = { query = it },
            onSection = {
                section = it
                onPicked()
            },
            onSettings = onSettings,
        )
    }
    val main: @Composable (menu: (() -> Unit)?) -> Unit = { menu ->
        MainArea(
            store = store,
            notes = shown,
            allEmpty = store.loaded && notes.isEmpty(),
            section = section,
            sort = sort,
            importing = importing,
            onSection = { section = it },
            onSort = { sort = it },
            onNew = { onOpen(store.create(newNotebookTitle(titlePrefix))) },
            onImport = { pickPdf.launch(arrayOf("application/pdf")) },
            onOpen = onOpen,
            onRename = { renaming = it },
            onDelete = { deleting = it },
            onMenu = menu,
        )
    }

    BoxWithConstraints(Modifier.fillMaxSize().background(z.paper)) {
        if (maxWidth >= WideLayout) {
            Row(Modifier.fillMaxSize()) {
                Box(Modifier.width(SidebarWidth).fillMaxHeight()) { sidebar {} }
                Box(Modifier.width(1.dp).fillMaxHeight().background(z.rule))
                Box(Modifier.weight(1f).fillMaxHeight()) { main(null) }
            }
        } else {
            val drawer = rememberDrawerState(DrawerValue.Closed)
            ModalNavigationDrawer(
                drawerState = drawer,
                drawerContent = {
                    ModalDrawerSheet(drawerContainerColor = z.paper2, drawerShape = RectangleShape, modifier = Modifier.width(SidebarWidth)) {
                        sidebar { scope.launch { drawer.close() } }
                    }
                },
            ) {
                main { scope.launch { drawer.open() } }
            }
        }
    }

    if (importFailed) {
        AlertDialog(
            onDismissRequest = { importFailed = false },
            confirmButton = { TextButton(onClick = { importFailed = false }) { Text(stringResource(R.string.ok)) } },
            title = { Text(stringResource(R.string.pdf_unreadable_title)) },
            text = { Text(stringResource(R.string.pdf_unreadable_message)) },
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

// MARK: The sidebar

@Composable
private fun Sidebar(
    notes: List<NotebookMeta>,
    section: LibrarySection,
    query: String,
    onQuery: (String) -> Unit,
    onSection: (LibrarySection) -> Unit,
    onSettings: () -> Unit,
) {
    val z = Zen.colors
    val (all, notebooks, pdfs) = LibraryRules.counts(notes)
    Column(
        Modifier
            .fillMaxSize()
            .background(z.paper2)
            .windowInsetsPadding(WindowInsets.safeDrawing.only(WindowInsetsSides.Top + WindowInsetsSides.Start + WindowInsetsSides.Bottom))
            .padding(horizontal = 16.dp, vertical = 20.dp),
        verticalArrangement = Arrangement.spacedBy(20.dp),
    ) {
        Box(Modifier.height(Zen.target).padding(start = 8.dp), contentAlignment = Alignment.CenterStart) {
            Text(
                stringResource(R.string.app_name),
                style = MaterialTheme.typography.headlineSmall.copy(fontSize = 22.sp, letterSpacing = (-0.4).sp),
                color = z.ink,
            )
        }
        SearchField(query, onQuery)
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            NavRow(Icons.AutoMirrored.Outlined.LibraryBooks, stringResource(R.string.library_all_notes), all, section == LibrarySection.ALL) { onSection(LibrarySection.ALL) }
            NavRow(Icons.Outlined.Schedule, stringResource(R.string.library_recent), null, section == LibrarySection.RECENT) { onSection(LibrarySection.RECENT) }
            NavRow(Icons.Outlined.Book, stringResource(R.string.library_notebooks), notebooks, section == LibrarySection.NOTEBOOKS) { onSection(LibrarySection.NOTEBOOKS) }
            NavRow(Icons.Outlined.PictureAsPdf, stringResource(R.string.library_pdfs), pdfs, section == LibrarySection.PDFS) { onSection(LibrarySection.PDFS) }
        }
        Spacer(Modifier.weight(1f))
        Column(Modifier.padding(top = 12.dp)) {
            Box(Modifier.fillMaxWidth().height(1.dp).background(z.rule))
            Spacer(Modifier.height(12.dp))
            NavRow(Icons.Outlined.Settings, stringResource(R.string.settings), null, false, onClick = onSettings)
        }
    }
}

/** A row of the sidebar: its glyph, its name and, for a section, how many notes it holds. */
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
        if (count != null) {
            Text(
                count.toString(),
                style = MaterialTheme.typography.bodyMedium.merge(TextStyle(fontFeatureSettings = "tnum")),
                color = z.muted,
            )
        }
    }
}

/** The search over the titles: a 38 dp field in a hairline on paper. */
@Composable
private fun SearchField(query: String, onQuery: (String) -> Unit) {
    val z = Zen.colors
    val label = stringResource(R.string.search)
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
                    .padding(start = 11.dp, end = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Icon(Icons.Outlined.Search, contentDescription = null, tint = z.muted, modifier = Modifier.size(18.dp))
                Box(Modifier.weight(1f)) {
                    if (query.isEmpty()) Text(label, style = MaterialTheme.typography.bodyLarge, color = z.muted)
                    inner()
                }
            }
        },
    )
}

// MARK: The main area

@Composable
private fun MainArea(
    store: NotebookStore,
    notes: List<NotebookMeta>,
    allEmpty: Boolean,
    section: LibrarySection,
    sort: LibrarySort,
    importing: Boolean,
    onSection: (LibrarySection) -> Unit,
    onSort: (LibrarySort) -> Unit,
    onNew: () -> Unit,
    onImport: () -> Unit,
    onOpen: (NotebookMeta) -> Unit,
    onRename: (NotebookMeta) -> Unit,
    onDelete: (NotebookMeta) -> Unit,
    onMenu: (() -> Unit)?,
) {
    val z = Zen.colors
    val narrow = onMenu != null
    val side = if (narrow) 16.dp else 40.dp
    Column(
        Modifier
            .fillMaxSize()
            .windowInsetsPadding(WindowInsets.safeDrawing.only(WindowInsetsSides.Top + WindowInsetsSides.End))
            .padding(top = if (narrow) 12.dp else 28.dp),
        verticalArrangement = Arrangement.spacedBy(24.dp),
    ) {
        Row(
            Modifier.fillMaxWidth().padding(horizontal = side),
            horizontalArrangement = Arrangement.spacedBy(16.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (onMenu != null) {
                BarButton(stringResource(R.string.menu), onClick = onMenu) {
                    Icon(Icons.Outlined.Menu, contentDescription = null, modifier = Modifier.size(22.dp))
                }
            }
            Text(
                stringResource(section.titleRes),
                style = if (narrow) MaterialTheme.typography.headlineMedium else MaterialTheme.typography.headlineLarge,
                color = z.ink,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f),
            )
            ZenButton(stringResource(if (importing) R.string.importing_pdf else R.string.import_pdf), filled = false, enabled = !importing, onClick = onImport)
            ZenButton(stringResource(R.string.new_notebook), filled = true, onClick = onNew)
        }
        Row(
            Modifier.fillMaxWidth().padding(horizontal = side),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            ZenSegments(
                options = listOf(stringResource(R.string.all), stringResource(R.string.library_notebooks), stringResource(R.string.library_pdfs)),
                selected = when (section) {
                    LibrarySection.ALL -> 0
                    LibrarySection.NOTEBOOKS -> 1
                    LibrarySection.PDFS -> 2
                    LibrarySection.RECENT -> -1
                },
                onSelect = { onSection(listOf(LibrarySection.ALL, LibrarySection.NOTEBOOKS, LibrarySection.PDFS)[it]) },
            )
            SortMenu(sort, onSort)
        }
        when {
            allEmpty -> EmptyLibrary(Modifier.fillMaxSize())
            notes.isEmpty() -> Text(
                stringResource(R.string.library_section_empty),
                style = MaterialTheme.typography.bodyMedium,
                color = z.muted,
                modifier = Modifier.padding(horizontal = side),
            )
            else -> LazyVerticalGrid(
                columns = GridCells.Adaptive(minSize = 176.dp),
                modifier = Modifier.fillMaxSize(),
                contentPadding = PaddingValues(start = side, end = side, bottom = 40.dp),
                horizontalArrangement = Arrangement.spacedBy(28.dp),
                verticalArrangement = Arrangement.spacedBy(32.dp),
            ) {
                items(notes, key = { it.id }) { meta ->
                    NoteCard(
                        meta = meta,
                        cover = store.thumbFile(meta.id),
                        coverVersion = store.coverVersion,
                        onOpen = { onOpen(meta) },
                        onRename = { onRename(meta) },
                        onDelete = { onDelete(meta) },
                    )
                }
            }
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

/** "Son düzenlenen ▾": the order of the notes. */
@Composable
private fun SortMenu(sort: LibrarySort, onSort: (LibrarySort) -> Unit) {
    val z = Zen.colors
    var open by remember { mutableStateOf(false) }
    Box {
        Row(
            Modifier
                .height(36.dp)
                .clip(RoundedCornerShape(Zen.control))
                .clickable { open = true }
                .padding(horizontal = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Text(stringResource(sort.titleRes), style = MaterialTheme.typography.bodyMedium, color = z.ink2)
            Icon(Icons.Outlined.ExpandMore, contentDescription = null, tint = z.ink2, modifier = Modifier.size(16.dp))
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            for (option in LibrarySort.entries) {
                DropdownMenuItem(
                    text = { Text(stringResource(option.titleRes)) },
                    trailingIcon = if (option == sort) {
                        { Icon(Icons.Outlined.Check, contentDescription = null, modifier = Modifier.size(18.dp)) }
                    } else {
                        null
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
        LibrarySort.CREATED -> R.string.sort_created
    }

@Composable
private fun EmptyLibrary(modifier: Modifier) {
    val z = Zen.colors
    Box(modifier, contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.padding(32.dp)) {
            Text(stringResource(R.string.library_empty_title), style = MaterialTheme.typography.titleLarge, color = z.ink)
            Spacer(Modifier.height(8.dp))
            Text(stringResource(R.string.library_empty_hint), style = MaterialTheme.typography.bodyMedium, color = z.muted)
        }
    }
}

// MARK: A note's cover

/** A note on the shelf: its first page as the cover, the title, "3 sayfa, dün"; the dots open its menu. */
@Composable
private fun NoteCard(meta: NotebookMeta, cover: File, coverVersion: Int, onOpen: () -> Unit, onRename: () -> Unit, onDelete: () -> Unit) {
    val z = Zen.colors
    var menuOpen by remember { mutableStateOf(false) }
    val pages = LibraryRules.pagesShown(meta.kind, meta.pageCount)
    val pagesText = pluralStringResource(R.plurals.pages, pages, pages)
    val line = buildList {
        if (meta.kind == NoteKind.PDF) add(stringResource(R.string.pdf_label))
        add(pagesText)
        add(relativeDate(meta.modified))
    }.joinToString(", ")
    val more = stringResource(R.string.more_actions)
    Column(
        Modifier
            .clip(RoundedCornerShape(Zen.control))
            .combinedClickable(onClick = onOpen, onLongClick = { menuOpen = true })
            .semantics { contentDescription = meta.title },
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Box(
            Modifier
                .fillMaxWidth()
                .aspectRatio(EditorState.A4_WIDTH / EditorState.A4_HEIGHT)
                .clip(RoundedCornerShape(Zen.control))
                .background(Color.White)
                .border(1.dp, z.rule, RoundedCornerShape(Zen.control)),
        ) {
            CoverPicture(cover, coverVersion, meta.kind, Modifier.fillMaxSize())
        }
        Row(verticalAlignment = Alignment.Top) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(meta.title, style = MaterialTheme.typography.titleMedium.copy(fontSize = 16.sp), color = z.ink, maxLines = 2, overflow = TextOverflow.Ellipsis)
                Text(line, style = MaterialTheme.typography.bodySmall, color = z.muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
            Box {
                Box(
                    Modifier
                        .size(32.dp)
                        .clip(RoundedCornerShape(8.dp))
                        .clickable { menuOpen = true }
                        .semantics { contentDescription = more },
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(Icons.Outlined.MoreHoriz, contentDescription = null, tint = z.muted, modifier = Modifier.size(18.dp))
                }
                DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
                    DropdownMenuItem(
                        text = { Text(stringResource(R.string.rename)) },
                        onClick = {
                            menuOpen = false
                            onRename()
                        },
                    )
                    DropdownMenuItem(
                        text = { Text(stringResource(R.string.delete), color = MaterialTheme.colorScheme.error) },
                        onClick = {
                            menuOpen = false
                            onDelete()
                        },
                    )
                }
            }
        }
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

/** The cover: the note's first page (`thumb.jpg`, read off the main thread, read again when it
 *  is written anew), else ruled paper, as the mockup shows a note without ink. */
@Composable
private fun CoverPicture(file: File, version: Int, kind: NoteKind, modifier: Modifier) {
    val picture by produceState<ImageBitmap?>(null, file, version) {
        value = withContext(Dispatchers.IO) {
            try {
                if (file.isFile) BitmapFactory.decodeFile(file.path)?.asImageBitmap() else null
            } catch (e: Exception) {
                null
            }
        }
    }
    val p = picture
    when {
        p != null -> Image(p, contentDescription = null, contentScale = ContentScale.Crop, alignment = Alignment.TopStart, modifier = modifier)
        kind == NoteKind.PDF -> Box(modifier.background(Zen.colors.paper2), contentAlignment = Alignment.Center) {
            Text(stringResource(R.string.pdf_label), style = MaterialTheme.typography.bodySmall, color = Zen.colors.muted)
        }
        else -> RuledPaper(modifier)
    }
}

/** Ruled paper: blue lines and a red margin on white, the mockup's cover of a note without ink. */
@Composable
private fun RuledPaper(modifier: Modifier) {
    val rule = Color(0xFFBFD3EA)
    val margin = Color(0xFFE6A5A5)
    Canvas(modifier) {
        val step = size.height / 26f
        var y = step * 3f
        while (y < size.height) {
            drawLine(rule, Offset(0f, y), Offset(size.width, y), strokeWidth = 1.dp.toPx())
            y += step
        }
        val x = size.width * 0.12f
        drawLine(margin, Offset(x, 0f), Offset(x, size.height), strokeWidth = 1.dp.toPx())
    }
}

// MARK: Dialogs

@Composable
internal fun RenameDialog(initial: String, onDismiss: () -> Unit, onRename: (String) -> Unit) {
    var text by remember(initial) { mutableStateOf(initial) }
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
