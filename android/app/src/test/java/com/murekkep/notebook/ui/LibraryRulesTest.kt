package com.murekkep.notebook.ui

import com.murekkep.notebook.data.NoteKind
import com.murekkep.notebook.data.NotebookMeta
import com.murekkep.notebook.data.PaperStyle
import org.junit.Assert.assertEquals
import org.junit.Test

// The library's rules: the page count a cover shows, the sections, the orders, the search, the counts.
class LibraryRulesTest {
    private fun note(title: String, kind: NoteKind = NoteKind.NOTEBOOK, modified: Long = 0, created: Long = 0, opened: Long = modified, pages: Int = 1) =
        NotebookMeta(id = title, title = title, created = created, modified = modified, pageCount = pages, paper = PaperStyle.LINED, kind = kind, opened = opened)

    @Test
    fun aNotebooksBlankLastPageIsNotCounted() {
        assertEquals(1, LibraryRules.pagesShown(NoteKind.NOTEBOOK, 1))
        assertEquals(1, LibraryRules.pagesShown(NoteKind.NOTEBOOK, 2))
        assertEquals(3, LibraryRules.pagesShown(NoteKind.NOTEBOOK, 4))
        assertEquals(1, LibraryRules.pagesShown(NoteKind.NOTEBOOK, 0))
    }

    @Test
    fun aPdfHasExactlyItsPages() {
        assertEquals(204, LibraryRules.pagesShown(NoteKind.PDF, 204))
        assertEquals(1, LibraryRules.pagesShown(NoteKind.PDF, 1))
    }

    @Test
    fun theSectionsFilterByKindAndKeepTheOrder() {
        val notes = listOf(
            note("Hücre", modified = 3), note("Türev", modified = 5), note("Kitap", kind = NoteKind.PDF, modified = 4),
        )
        assertEquals(listOf("Türev", "Kitap", "Hücre"), LibraryRules.shown(notes, LibrarySection.ALL, LibrarySort.MODIFIED, "").map { it.title })
        assertEquals(listOf("Türev", "Hücre"), LibraryRules.shown(notes, LibrarySection.NOTEBOOKS, LibrarySort.MODIFIED, "").map { it.title })
        assertEquals(listOf("Kitap"), LibraryRules.shown(notes, LibrarySection.PDFS, LibrarySort.MODIFIED, "").map { it.title })
    }

    @Test
    fun recentlyOpenedIsByTheOpenedTimeAndShort() {
        val notes = (1..20).map { note("n$it", modified = it.toLong(), opened = (21 - it).toLong()) }
        val recent = LibraryRules.shown(notes, LibrarySection.RECENT, LibrarySort.MODIFIED, "")
        assertEquals(LibraryRules.RECENT_COUNT, recent.size)
        assertEquals("n1", recent.first().title)
        assertEquals("n12", recent.last().title)
    }

    @Test
    fun theOrdersAndTheSearch() {
        val notes = listOf(note("b", modified = 1, created = 3), note("A", modified = 2, created = 2), note("c", modified = 3, created = 1))
        assertEquals(listOf("A", "b", "c"), LibraryRules.sorted(notes, LibrarySort.TITLE).map { it.title })
        assertEquals(listOf("b", "A", "c"), LibraryRules.sorted(notes, LibrarySort.CREATED).map { it.title })
        assertEquals(listOf("c", "A", "b"), LibraryRules.sorted(notes, LibrarySort.MODIFIED).map { it.title })
        assertEquals(listOf("A"), LibraryRules.shown(notes, LibrarySection.ALL, LibrarySort.MODIFIED, " a ").map { it.title })
    }

    @Test
    fun theSidebarCounts() {
        val notes = listOf(note("a"), note("b"), note("p", kind = NoteKind.PDF))
        assertEquals(Triple(3, 2, 1), LibraryRules.counts(notes))
    }
}
