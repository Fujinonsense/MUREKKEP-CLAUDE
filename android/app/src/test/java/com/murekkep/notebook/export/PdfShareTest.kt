package com.murekkep.notebook.export

import org.junit.Assert.assertEquals
import org.junit.Test

// The shared file's name from the note's title: what no file system takes becomes "_", an empty
// title is "Not", ".pdf" once.
class PdfShareTest {
    @Test
    fun theTitleBecomesTheFileName() {
        assertEquals("Not 25 Eki 2026 21_35.pdf", PdfShare.fileName("Not 25 Eki 2026 21:35"))
        assertEquals("Hücre biyolojisi.pdf", PdfShare.fileName("Hücre biyolojisi"))
        assertEquals("a_b_c_d.pdf", PdfShare.fileName("a/b\\c|d"))
    }

    @Test
    fun anEmptyOrDottedTitleStillNamesAFile() {
        assertEquals("Not.pdf", PdfShare.fileName(""))
        assertEquals("Not.pdf", PdfShare.fileName("   "))
        assertEquals("Not.pdf", PdfShare.fileName("..."))
    }

    @Test
    fun pdfIsAddedOnce() {
        assertEquals("book.pdf", PdfShare.fileName("book.pdf"))
        assertEquals("book.PDF", PdfShare.fileName("book.PDF"))
    }
}
