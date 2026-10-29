package com.murekkep.notebook.export

import com.murekkep.notebook.ink.Brush
import com.murekkep.notebook.ink.InkColor
import com.murekkep.notebook.ink.InkPoint
import com.murekkep.notebook.ink.Stroke
import org.junit.Assert.assertEquals
import org.junit.Test

// How many pages exportPDF writes (EditorModel.swift): a notebook's blank pages at the end stay
// out, at least one page goes; an imported PDF keeps all its pages.
class PdfExportTest {
    private val ink = listOf(Stroke(Brush.PEN, InkColor(0f, 0f, 0f), 2.2f, 0.0, 0.37f, listOf(InkPoint(10f, 10f, 1f, 0.5f))))
    private val blank = emptyList<Stroke>()

    @Test
    fun aNotebookEndsAtItsLastPageWithInk() {
        assertEquals(3, PdfExport.exportedPageCount(listOf(ink, blank, ink, blank, blank), isPdf = false))
        assertEquals(1, PdfExport.exportedPageCount(listOf(ink, blank), isPdf = false))
        assertEquals(2, PdfExport.exportedPageCount(listOf(blank, ink, blank), isPdf = false))
    }

    @Test
    fun anEmptyNotebookStillGivesOnePage() {
        assertEquals(1, PdfExport.exportedPageCount(listOf(blank, blank, blank), isPdf = false))
        assertEquals(1, PdfExport.exportedPageCount(listOf(blank), isPdf = false))
    }

    @Test
    fun anImportedPdfKeepsEveryPage() {
        assertEquals(5, PdfExport.exportedPageCount(listOf(blank, ink, blank, blank, blank), isPdf = true))
        assertEquals(2, PdfExport.exportedPageCount(listOf(blank, blank), isPdf = true))
    }

    @Test
    fun pageEdgesAreWholePointsNeverUnderOne() {
        assertEquals(595, PdfExport.pointSize(595.28f))
        assertEquals(842, PdfExport.pointSize(841.89f))
        assertEquals(1, PdfExport.pointSize(0.2f))
    }
}
