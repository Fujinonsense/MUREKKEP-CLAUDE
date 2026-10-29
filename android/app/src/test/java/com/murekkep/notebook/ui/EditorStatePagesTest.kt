package com.murekkep.notebook.ui

import com.murekkep.notebook.data.LoadProblem
import com.murekkep.notebook.render.PageSize
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

// The page navigator's operations on the note (EditorModel.swift's requestScroll, bookmarks,
// isBookmarked and toggleBookmark on iPad): the ribbon marks a page and takes the mark off again,
// the record hears of the list in order at once; only pages the note has are marked, jumped to or
// listed; a bookmark is no ink change (no undo, no save of the ink) and a read-only note takes one.
class EditorStatePagesTest {
    private fun notebook(pages: Int) = EditorState(initialPages = List(pages) { emptyList() })

    @Test
    fun theRibbonMarksAPageAndTakesTheMarkOffAgain() {
        val state = notebook(3)
        val told = ArrayList<List<Int>>()
        state.onBookmarksChange = { told += it }
        state.toggleBookmark(2)
        assertTrue(state.isBookmarked(2))
        assertEquals(listOf(2), state.bookmarks)
        state.toggleBookmark(0)
        assertEquals(listOf(0, 2), state.bookmarks)
        state.toggleBookmark(2)
        assertFalse(state.isBookmarked(2))
        assertEquals(listOf(0), state.bookmarks)
        state.toggleBookmark(0)
        assertEquals(emptyList<Int>(), state.bookmarks)
        // The record is told the whole list each time, in order, and an empty one at the end.
        assertEquals(listOf(listOf(2), listOf(0, 2), listOf(0), emptyList()), told)
    }

    @Test
    fun aPageTheNoteDoesNotHaveTakesNoBookmarkAndNoJump() {
        val state = notebook(3)
        var told = 0
        val jumps = ArrayList<Int>()
        state.onBookmarksChange = { told++ }
        state.onScrollRequest = { jumps += it }
        state.toggleBookmark(3)
        state.toggleBookmark(-1)
        assertEquals(0, told)
        assertEquals(emptyList<Int>(), state.bookmarks)
        state.requestScroll(1)
        state.requestScroll(3)
        state.requestScroll(-1)
        assertEquals(listOf(1), jumps)
    }

    @Test
    fun theRecordsBookmarksAreListedInOrderForThePagesTheNoteHas() {
        // A PDF of two pages whose record names a page it does not have (the iPad's `bookmarks`
        // filters by the pages and sorts; the record keeps what it has).
        val state = EditorState(initialPages = List(2) { emptyList() }, pageSizes = listOf(PageSize.A4, PageSize.A4), bookmarks = listOf(5, 1, 0))
        assertEquals(listOf(0, 1), state.bookmarks)
        // A page a record names twice is listed once (the grid's tiles are keyed by page).
        assertEquals(listOf(1), EditorState(initialPages = List(2) { emptyList() }, bookmarks = listOf(1, 1)).bookmarks)
        assertTrue(state.isBookmarked(1))
        val told = ArrayList<List<Int>>()
        state.onBookmarksChange = { told += it }
        state.toggleBookmark(1)
        assertEquals(listOf(listOf(0, 5)), told)
        assertEquals(listOf(0), state.bookmarks)
    }

    @Test
    fun aBookmarkIsNoInkChange() {
        val state = notebook(2)
        var saves = 0
        state.onDirty = { saves++ }
        state.toggleBookmark(1)
        assertFalse(state.dirty)
        assertFalse(state.canUndo)
        assertEquals(0, saves)
    }

    @Test
    fun aReadOnlyNoteStillTakesBookmarks() {
        val state = EditorState(initialPages = List(2) { emptyList() }, loadProblems = listOf(LoadProblem.INK_NEWER))
        state.toggleBookmark(1)
        assertEquals(listOf(1), state.bookmarks)
    }

    @Test
    fun aPageAddedAtTheEndCanBeMarked() {
        val state = notebook(1)
        state.addPage()
        state.toggleBookmark(1)
        assertEquals(listOf(1), state.bookmarks)
    }
}
