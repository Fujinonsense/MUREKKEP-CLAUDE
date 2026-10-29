package com.murekkep.notebook.export

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

// The shared file's name from the note's title: what no file system takes becomes "_", an empty
// title is "Not", ".pdf" once, and a name never longer than a file system takes.
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

    // A file name takes at most 255 bytes, and ğ, ş, ı... are two bytes each in UTF-8.

    private fun bytes(name: String) = name.toByteArray(Charsets.UTF_8).size

    @Test
    fun aTitleThatFitsKeepsItsWholeName() {
        val ascii = "a".repeat(PdfShare.NAME_BYTES)
        assertEquals("$ascii.pdf", PdfShare.fileName(ascii))
        val turkish = "ğ".repeat(PdfShare.NAME_BYTES / 2)
        assertEquals("$turkish.pdf", PdfShare.fileName(turkish))
    }

    @Test
    fun aLongTurkishTitleIsCutToWhatAFileNameTakes() {
        val name = PdfShare.fileName("ş".repeat(200))
        assertEquals("ş".repeat(PdfShare.NAME_BYTES / 2) + ".pdf", name)
        assertTrue(bytes(name) <= 255)
        // A pasted page of text as the title is cut in one pass, to the same length.
        assertEquals(name, PdfShare.fileName("ş".repeat(100_000)))
    }

    @Test
    fun theCutNeverSplitsACharacter() {
        // Each emoji is two chars (a surrogate pair) and four bytes: 1 + 59 * 4 = 237 bytes fit, 60 do not.
        val name = PdfShare.fileName("a" + "😀".repeat(100))
        assertEquals("a" + "😀".repeat(59) + ".pdf", name)
        assertTrue(bytes(name) <= 255)
        // A half emoji would not survive UTF-8 (it becomes "?").
        assertEquals(name, String(name.toByteArray(Charsets.UTF_8), Charsets.UTF_8))
    }

    @Test
    fun aCutTitleKeepsItsExtensionAndLosesTrailingSpaces() {
        assertEquals("x".repeat(PdfShare.NAME_BYTES) + ".PDF", PdfShare.fileName("x".repeat(300) + ".PDF"))
        assertEquals("b".repeat(239) + ".pdf", PdfShare.fileName("b".repeat(239) + " c d e"))
    }
}
