@file:OptIn(androidx.compose.foundation.layout.ExperimentalLayoutApi::class)

package com.murekkep.notebook.ui

import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.text.TextAutoSize
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.NoteAdd
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.ChevronLeft
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.EditNote
import androidx.compose.material.icons.outlined.Inbox
import androidx.compose.material.icons.outlined.MoreHoriz
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.MenuDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.murekkep.notebook.R
import com.murekkep.notebook.data.NoteKind
import com.murekkep.notebook.data.NoteSection
import com.murekkep.notebook.data.NotebookStore
import kotlin.math.max

// The courses ("Kurslar", LibraryView and LibraryPanes on iPad). In the sidebar under the lists:
// "Kurslar" with its + ("Yeni ders"), "İlk dersini ekle" while there is none, then a row for each
// course, its symbol in its colour, its name and how many notes it holds; a tap opens it, PDFs and
// photos dropped on it go into it, and a long press opens its menu (PDF ya da fotoğraf ekle, Yeni
// defter, Düzenle, Dersi sil). A course's pane: its symbol in a circle, its name, "2 kaynak · 1
// defter", "PDF ya da fotoğraf ekle", "Yeni not" and Diğer (Dersi düzenle, Dersi sil), then
// Kaynaklar / Defterler: the PDFs under the course's drop zone, or the notebooks under "Yeni defter".
// The iPad's Stüdyo tab, its overviews and its "Video özeti yap" need the Studio, which Android does
// not have. A note's menu moves it to a course ("Derse taşı"), and a search finds the courses by
// name ("Dersler") with their notes. Deleting a course asks first; its notes stay in the library.

/** What the courses ask the library to do (LibraryActions on iPad, the courses' part). */
internal class CourseActions(
    /** "Yeni ders": the editor for a new course. */
    val create: () -> Unit,
    /** "Düzenle", "Dersi düzenle": the editor for the course. */
    val edit: (NoteSection) -> Unit,
    /** "Dersi sil": asks first. */
    val delete: (NoteSection) -> Unit,
    /** "PDF ya da fotoğraf ekle" into the course (its id). */
    val import: (String) -> Unit,
    /** "Yeni defter", "Yeni not" in the course: the templates, then the notebook. */
    val newNotebook: (String) -> Unit,
    /** PDFs and photos dropped on the course, and the release of the right to read them. */
    val drop: (List<Uri>, String, () -> Unit) -> Unit,
)

// MARK: The sidebar

/** The sidebar's courses: the header with its +, "İlk dersini ekle" while there are none, and a row
 *  for each course, [selected] the one on screen. */
@Composable
internal fun CourseList(
    sections: List<NoteSection>,
    counts: Map<String, Int>,
    selected: String?,
    onPick: (NoteSection) -> Unit,
    actions: CourseActions,
) {
    val z = Zen.colors
    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Row(Modifier.fillMaxWidth().padding(start = 10.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(
                stringResource(R.string.courses_title),
                style = MaterialTheme.typography.bodySmall,
                fontWeight = FontWeight.SemiBold,
                color = z.muted,
                modifier = Modifier.weight(1f),
            )
            BarButton(stringResource(R.string.course_new), onClick = actions.create) {
                Icon(Icons.Outlined.Add, contentDescription = null, modifier = Modifier.size(20.dp))
            }
        }
        if (sections.isEmpty()) {
            Box(
                Modifier
                    .fillMaxWidth()
                    .height(40.dp)
                    .clip(RoundedCornerShape(Zen.control))
                    .clickable(role = Role.Button, onClick = actions.create)
                    .padding(horizontal = 10.dp),
                contentAlignment = Alignment.CenterStart,
            ) {
                Text(stringResource(R.string.course_first), style = MaterialTheme.typography.bodyLarge, color = z.muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
        for (section in sections) {
            key(section.id) {
                CourseRow(section, counts[section.id] ?: 0, section.id == selected, onPick, actions)
            }
        }
    }
}

/** A course's row: picked, it stands on paper-3; files dragged over it light it up in an accent
 *  outline; a long press opens its menu under it. */
@Composable
private fun CourseRow(section: NoteSection, count: Int, selected: Boolean, onPick: (NoteSection) -> Unit, actions: CourseActions) {
    var menuOpen by remember { mutableStateOf(false) }
    val drop = rememberFileDrop { uris, release -> actions.drop(uris, section.id, release) }
    Box {
        NavRow(
            icon = courseGlyph(section.symbol),
            title = section.name,
            count = count,
            selected = selected,
            tint = section.color,
            targeted = drop.hovering,
            onLongClick = { menuOpen = true },
            longClickLabel = stringResource(R.string.more_actions),
            modifier = Modifier.fileDropTarget(drop),
        ) { onPick(section) }
        ZenMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
            val close = { menuOpen = false }
            MenuItem(stringResource(R.string.import_title), Icons.AutoMirrored.Outlined.NoteAdd) {
                close()
                actions.import(section.id)
            }
            MenuItem(stringResource(R.string.new_notebook_title), Icons.Outlined.EditNote) {
                close()
                actions.newNotebook(section.id)
            }
            MenuItem(stringResource(R.string.course_row_edit), Icons.Outlined.Edit) {
                close()
                actions.edit(section)
            }
            DeleteItem(stringResource(R.string.course_delete_keep)) {
                close()
                actions.delete(section)
            }
        }
    }
}

/** A menu's item with its glyph at the end, as the iPad's menus set them. */
@Composable
private fun MenuItem(label: String, icon: ImageVector, onClick: () -> Unit) {
    DropdownMenuItem(
        text = { Text(label, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.widthIn(max = MenuTextWidth)) },
        trailingIcon = { Icon(icon, contentDescription = null, modifier = Modifier.size(20.dp)) },
        onClick = onClick,
    )
}

/** "Dersi sil (içindekiler kalır)" in the system's red, with its bin. */
@Composable
private fun DeleteItem(label: String, onClick: () -> Unit) {
    val error = MaterialTheme.colorScheme.error
    DropdownMenuItem(
        text = { Text(label) },
        trailingIcon = { Icon(Icons.Outlined.Delete, contentDescription = null, modifier = Modifier.size(20.dp)) },
        onClick = onClick,
        colors = MenuDefaults.itemColors(textColor = error, trailingIconColor = error),
    )
}

/** How wide a course's name may run in a menu before it is cut, as an iOS menu cuts it. */
private val MenuTextWidth = 260.dp

/**
 * "Derse taşı" in a note's menu (the iPad's submenu, opened in the menu's place with its title on
 * top, which folds it back): every course, the note's own ticked, the others with their symbols;
 * "Dersten çıkar" while the note is in one; "Yeni ders…". A rule stands only under something, as
 * iOS drops a Divider with nothing above it: with no courses the title's rule is the only one.
 */
@Composable
internal fun ColumnScope.MoveToCourseItems(
    current: String?,
    sections: List<NoteSection>,
    onBack: () -> Unit,
    onMove: (String?) -> Unit,
    onNewCourse: () -> Unit,
) {
    val rule = Zen.colors.rule
    DropdownMenuItem(
        text = { Text(stringResource(R.string.course_move), fontWeight = FontWeight.SemiBold) },
        leadingIcon = { Icon(Icons.Outlined.ChevronLeft, contentDescription = null, modifier = Modifier.size(20.dp)) },
        onClick = onBack,
    )
    HorizontalDivider(Modifier.padding(vertical = 4.dp), color = rule)
    for (section in sections) {
        MenuItem(section.name, if (section.id == current) Icons.Outlined.Check else courseGlyph(section.symbol)) { onMove(section.id) }
    }
    if (current != null) {
        if (sections.isNotEmpty()) HorizontalDivider(Modifier.padding(vertical = 4.dp), color = rule)
        MenuItem(stringResource(R.string.course_remove), Icons.Outlined.Inbox) { onMove(null) }
    }
    if (sections.isNotEmpty() || current != null) HorizontalDivider(Modifier.padding(vertical = 4.dp), color = rule)
    MenuItem(stringResource(R.string.course_new_more), Icons.Outlined.Add, onClick = onNewCourse)
}

// MARK: The pane

/**
 * A course's pane (CoursePane on iPad), scrolling as one like the notes pane: the header, the
 * Kaynaklar / Defterler tabs ([tab]), then on Kaynaklar the course's drop zone and its PDFs, on
 * Defterler "2 defter" with "Yeni defter" and its notebooks, the last changed first. PDFs and photos
 * dropped anywhere on the pane go into the course and bring Kaynaklar forward; the drop zone lights
 * up meanwhile (there is no overlay, as on iPad).
 */
@Composable
internal fun CoursePane(
    store: NotebookStore,
    section: NoteSection,
    tab: CourseTab,
    onTab: (CourseTab) -> Unit,
    phone: Boolean,
    importing: Boolean,
    onToggle: (() -> Unit)?,
    notes: NoteActions,
    actions: CourseActions,
    modifier: Modifier = Modifier,
) {
    val all = LibraryRules.courseNotes(store.notebooks, section.id)
    val pdfs = all.filter { it.kind == NoteKind.PDF }
    val notebooks = all.filter { it.kind == NoteKind.NOTEBOOK }
    val tabs = listOf(stringResource(R.string.course_sources), stringResource(R.string.library_notebooks))
    val tabLabel = stringResource(R.string.course_tab_label)
    val retab by rememberUpdatedState(onTab)
    val drop = rememberFileDrop { uris, release ->
        retab(CourseTab.SOURCES)
        actions.drop(uris, section.id, release)
    }
    val list = key(section.id) { rememberLazyListState() }
    val insets = paneInsets(phone, sidebarAway = onToggle != null)
    val pane = rememberUpdatedState(
        PaneContent(
            list = list,
            padding = insets.padding,
            // The header and the tabs keep the picture; the wash begins under them.
            washFrom = 2,
            wash = notesWashColor(LocalAppTheme.current.shown),
            overlay = null,
        ) { cardWidth, columns ->
            item(key = "header") { CourseHeader(section, pdfs.size, notebooks.size, importing, onToggle, actions) }
            item(key = "tabs") {
                LibrarySegments(tabs, tab.ordinal, { retab(CourseTab.entries[it]) }, tabLabel, Modifier.widthIn(max = 460.dp).fillMaxWidth())
            }
            when (tab) {
                CourseTab.SOURCES -> {
                    item(key = "drop") {
                        DropZone(
                            drop.hovering,
                            onPick = { actions.import(section.id) },
                            title = stringResource(R.string.course_drop_title),
                            detail = stringResource(R.string.course_drop_detail),
                        )
                    }
                    if (pdfs.isEmpty()) {
                        item(key = "no-sources") {
                            Text(stringResource(R.string.course_no_sources), style = MaterialTheme.typography.bodyMedium, color = Zen.colors.muted)
                        }
                    } else {
                        noteRows(pdfs, columns, cardWidth, store, notes)
                    }
                }
                CourseTab.NOTEBOOKS -> {
                    item(key = "notebooks") {
                        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                            Text(
                                if (notebooks.isEmpty()) {
                                    stringResource(R.string.course_no_notebooks)
                                } else {
                                    pluralStringResource(R.plurals.course_notebook_count, notebooks.size, notebooks.size)
                                },
                                style = MaterialTheme.typography.bodyMedium,
                                color = Zen.colors.muted,
                                modifier = Modifier.weight(1f).padding(end = 12.dp),
                            )
                            ZenButton(stringResource(R.string.new_notebook_title), filled = false) { actions.newNotebook(section.id) }
                        }
                    }
                    noteRows(notebooks, columns, cardWidth, store, notes)
                }
            }
        },
    )
    PaneColumn(pane, drop, modifier)
}

/**
 * The course's name with its symbol (in its colour, in a circle of paper-2), what it holds, its
 * buttons and Diğer. While the name keeps [MinTitleWidth] the buttons stand beside it, as on iPad;
 * a narrower pane (a phone, a tablet upright with the sidebar) puts them under it.
 */
@Composable
private fun CourseHeader(section: NoteSection, sources: Int, notebooks: Int, importing: Boolean, onToggle: (() -> Unit)?, actions: CourseActions) {
    val z = Zen.colors
    val counts = pluralStringResource(R.plurals.course_source_count, sources, sources) + " · " +
        pluralStringResource(R.plurals.course_notebook_count, notebooks, notebooks)
    HeaderLayout(
        lead = {
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                if (onToggle != null) {
                    BarButton(stringResource(R.string.show_sidebar), onClick = onToggle) {
                        Icon(SidebarGlyph, contentDescription = null, modifier = Modifier.size(22.dp))
                    }
                }
                Box(
                    Modifier.size(Zen.target).background(z.paper2, CircleShape).border(1.dp, z.rule, CircleShape),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(courseGlyph(section.symbol), contentDescription = null, tint = section.color, modifier = Modifier.size(20.dp))
                }
            }
        },
        title = {
            Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                val style = MaterialTheme.typography.headlineLarge
                BasicText(
                    section.name,
                    style = style.copy(color = z.ink),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    // The iPad's minimumScaleFactor(0.6).
                    autoSize = TextAutoSize.StepBased(minFontSize = style.fontSize * 0.6f, maxFontSize = style.fontSize, stepSize = 1.sp),
                    modifier = Modifier.semantics { heading() },
                )
                Text(counts, style = MaterialTheme.typography.bodyMedium, color = z.muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        },
        buttons = {
            FlowRow(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                ZenButton(stringResource(if (importing) R.string.importing_pdf else R.string.import_title), filled = false, enabled = !importing) {
                    actions.import(section.id)
                }
                ZenButton(stringResource(R.string.new_notebook), filled = true) { actions.newNotebook(section.id) }
            }
        },
        more = { CourseMore(section, actions) },
    )
}

/** The least room the course's name keeps beside the buttons before they go under it. */
private val MinTitleWidth = 200.dp

/** Lays out the header's [lead], [title], [buttons] and [more] in a row, 12 dp apart, while the title
 *  keeps [MinTitleWidth]; else the buttons go 16 dp under the row. */
@Composable
private fun HeaderLayout(
    lead: @Composable () -> Unit,
    title: @Composable () -> Unit,
    buttons: @Composable () -> Unit,
    more: @Composable () -> Unit,
) {
    Layout(contents = listOf(lead, title, buttons, more), modifier = Modifier.fillMaxWidth()) { (leadParts, titleParts, buttonParts, moreParts), constraints ->
        val width = constraints.maxWidth
        val gap = 12.dp.roundToPx()
        val loose = Constraints(maxWidth = width)
        val l = leadParts.first().measure(loose)
        val m = moreParts.first().measure(loose)
        // What the title and the buttons share, with the gaps between the four.
        val shared = width - l.width - m.width
        val buttonsWide = buttonParts.first().maxIntrinsicWidth(Constraints.Infinity)
        val oneLine = shared - 3 * gap - buttonsWide >= MinTitleWidth.roundToPx()
        val b = buttonParts.first().measure(Constraints(maxWidth = if (oneLine) buttonsWide else width))
        val titleWidth = max(0, if (oneLine) shared - 3 * gap - b.width else shared - 2 * gap)
        val t = titleParts.first().measure(Constraints(minWidth = titleWidth, maxWidth = titleWidth))
        val row = maxOf(l.height, t.height, m.height, if (oneLine) b.height else 0)
        val under = if (oneLine) 0 else 16.dp.roundToPx() + b.height
        layout(width, row + under) {
            var x = 0
            l.placeRelative(x, (row - l.height) / 2)
            x += l.width + gap
            t.placeRelative(x, (row - t.height) / 2)
            x += t.width + gap
            if (oneLine) {
                b.placeRelative(x, (row - b.height) / 2)
                x += b.width + gap
            } else {
                b.placeRelative(0, row + 16.dp.roundToPx())
            }
            m.placeRelative(width - m.width, (row - m.height) / 2)
        }
    }
}

/** Diğer (the iPad's ellipsis menu): Dersi düzenle, Dersi sil. */
@Composable
private fun CourseMore(section: NoteSection, actions: CourseActions) {
    var open by remember { mutableStateOf(false) }
    Box {
        BarButton(stringResource(R.string.more), onClick = { open = true }) {
            Icon(Icons.Outlined.MoreHoriz, contentDescription = null, modifier = Modifier.size(22.dp))
        }
        ZenMenu(expanded = open, onDismissRequest = { open = false }, alignEnd = true) {
            MenuItem(stringResource(R.string.course_edit), Icons.Outlined.Edit) {
                open = false
                actions.edit(section)
            }
            DeleteItem(stringResource(R.string.course_delete_keep)) {
                open = false
                actions.delete(section)
            }
        }
    }
}

// MARK: The search

/** The courses a search found ("Dersler"): a capsule for each, its symbol in its colour and its
 *  name, which opens the course. */
@Composable
internal fun CourseChips(courses: List<NoteSection>, onPick: (NoteSection) -> Unit) {
    val z = Zen.colors
    FlowRow(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        for (section in courses) {
            Row(
                Modifier
                    .height(40.dp)
                    .clip(CircleShape)
                    .background(z.paper2)
                    .border(1.dp, z.rule, CircleShape)
                    .clickable(role = Role.Button) { onPick(section) }
                    .padding(horizontal = 14.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(courseGlyph(section.symbol), contentDescription = null, tint = section.color, modifier = Modifier.size(18.dp))
                Text(section.name, style = MaterialTheme.typography.labelLarge, color = z.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
    }
}

// MARK: Deleting

/** "Ders silinsin mi?": only the course goes; its notebooks and PDFs stay in the library. */
@Composable
internal fun DeleteCourseDialog(onDismiss: () -> Unit, onDelete: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.course_delete_title)) },
        text = { Text(stringResource(R.string.course_delete_message)) },
        confirmButton = {
            TextButton(
                onClick = onDelete,
                colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error),
            ) { Text(stringResource(R.string.course_delete)) }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) }
        },
    )
}
