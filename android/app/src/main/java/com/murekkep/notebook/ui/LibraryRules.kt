package com.murekkep.notebook.ui

import com.murekkep.notebook.data.NoteKind
import com.murekkep.notebook.data.NotebookMeta
import java.util.Locale
import kotlin.math.max

// The library's pure rules: which notes a section shows, in what order, and what a cover's line
// says ("3 sayfa, dün").

/** The sidebar's sections. */
enum class LibrarySection { ALL, RECENT, NOTEBOOKS, PDFS }

/** The main area's orders. */
enum class LibrarySort { MODIFIED, TITLE, CREATED }

object LibraryRules {
    /** How many notes "Son açılanlar" shows. */
    const val RECENT_COUNT = 12

    /**
     * How many pages the cover says a note has. A notebook always ends in a blank page (the one
     * waiting for the pen), which is not counted, and a notebook has at least one page; an imported
     * PDF has exactly its own pages.
     */
    fun pagesShown(kind: NoteKind, pageCount: Int): Int = when (kind) {
        NoteKind.NOTEBOOK -> max(1, pageCount - 1)
        NoteKind.PDF -> max(1, pageCount)
    }

    /** The notes of a section that match the search, in the section's order. */
    fun shown(notes: List<NotebookMeta>, section: LibrarySection, sort: LibrarySort, query: String): List<NotebookMeta> {
        val q = query.trim().lowercase(Locale.getDefault())
        val matching = if (q.isEmpty()) notes else notes.filter { q in it.title.lowercase(Locale.getDefault()) }
        return when (section) {
            LibrarySection.ALL -> sorted(matching, sort)
            LibrarySection.NOTEBOOKS -> sorted(matching.filter { it.kind == NoteKind.NOTEBOOK }, sort)
            LibrarySection.PDFS -> sorted(matching.filter { it.kind == NoteKind.PDF }, sort)
            LibrarySection.RECENT -> matching.sortedByDescending { it.opened }.take(RECENT_COUNT)
        }
    }

    fun sorted(notes: List<NotebookMeta>, sort: LibrarySort): List<NotebookMeta> = when (sort) {
        LibrarySort.MODIFIED -> notes.sortedByDescending { it.modified }
        LibrarySort.CREATED -> notes.sortedByDescending { it.created }
        LibrarySort.TITLE -> notes.sortedWith(compareBy(String.CASE_INSENSITIVE_ORDER) { it.title })
    }

    /** The sidebar's counts: all notes, notebooks, PDFs. */
    fun counts(notes: List<NotebookMeta>): Triple<Int, Int, Int> {
        val pdfs = notes.count { it.kind == NoteKind.PDF }
        return Triple(notes.size, notes.size - pdfs, pdfs)
    }
}
