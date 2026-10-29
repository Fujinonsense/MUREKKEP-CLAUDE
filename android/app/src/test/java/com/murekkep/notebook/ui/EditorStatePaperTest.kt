package com.murekkep.notebook.ui

import com.murekkep.notebook.data.InkSettings
import com.murekkep.notebook.data.LoadProblem
import com.murekkep.notebook.data.PaperStyle
import com.murekkep.notebook.render.PageSize
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

// Diğer › Şablonu değiştir (EditorModel.setPaper on iPad): every page of a notebook goes on the
// template picked, the store hears of it and a save follows (the cover is drawn on the new paper);
// a PDF's own pages, a read-only note and the template it already has are left alone. And the pen
// settings Ayarlar › Kalem adds.
class EditorStatePaperTest {
    @Test
    fun aNotebookTakesTheTemplatePicked() {
        val state = EditorState(paper = PaperStyle.LINED)
        val told = ArrayList<PaperStyle>()
        var saves = 0
        var frames = 0
        state.onPaperChange = { told += it }
        state.onDirty = { saves++ }
        state.onInkChange = { frames++ }
        state.changePaper(PaperStyle.GRID)
        assertEquals(PaperStyle.GRID, state.paper)
        assertEquals(listOf(PaperStyle.GRID), told)
        assertEquals(1, saves)
        assertEquals(1, frames)
        assertTrue(state.dirty)
        // The same template again changes nothing.
        state.changePaper(PaperStyle.GRID)
        assertEquals(1, told.size)
        assertEquals(1, saves)
    }

    @Test
    fun aPdfAndAReadOnlyNoteKeepTheirPages() {
        val pdf = EditorState(pageSizes = listOf(PageSize.A4), paper = PaperStyle.PLAIN)
        pdf.changePaper(PaperStyle.GRID)
        assertEquals(PaperStyle.PLAIN, pdf.paper)
        val readOnly = EditorState(loadProblems = listOf(LoadProblem.INK_NEWER), paper = PaperStyle.LINED)
        readOnly.changePaper(PaperStyle.DOTTED)
        assertEquals(PaperStyle.LINED, readOnly.paper)
        assertFalse(readOnly.dirty)
    }

    @Test
    fun thePenSettingsStartWithFingersDrawingAndTheHoverRingOn() {
        // Fingers draw until a pen is seen (tablets without a pen are drawn on with a finger); the
        // iPad's switch starts on, as every iPad user writes with the Pencil.
        val ink = InkSettings()
        assertFalse(ink.penOnly)
        assertTrue(ink.hoverPreview)
        val state = EditorState()
        state.penOnly = true
        assertTrue(state.ink.penOnly)
    }
}
