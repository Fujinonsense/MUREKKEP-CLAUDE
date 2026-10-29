package com.murekkep.notebook.export

import com.murekkep.notebook.render.PageSize
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

// The shared file's name from the note's title: what no file system takes, and "%", becomes "-"
// as on the iPad, an empty title is "Not", ".pdf" once, and a name never longer than a file
// system takes. The imported pages' pictures: twice their size while all of them fit in memory.
class PdfShareTest {
    @Test
    fun theTitleBecomesTheFileName() {
        assertEquals("Not 25 Eki 2026 21-35.pdf", PdfShare.fileName("Not 25 Eki 2026 21:35"))
        assertEquals("Hücre biyolojisi.pdf", PdfShare.fileName("Hücre biyolojisi"))
        assertEquals("a-b-c-d.pdf", PdfShare.fileName("a/b\\c|d"))
        assertEquals("100- tamam- -ya da- -x-.pdf", PdfShare.fileName("100% tamam? *ya da* <x>"))
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

    // An imported PDF's pages are pictures PdfDocument keeps until it writes the file.

    private fun a4(pages: Int) = List(pages) { PageSize.A4 }

    private fun pictureBytes(sizes: List<PageSize>, scale: Float) =
        sizes.sumOf { 4.0 * it.width * scale * it.height * scale }

    @Test
    fun aShortPdfKeepsTwiceItsSize() {
        assertEquals(PdfShare.PDF_PAGE_SCALE, PdfShare.importedPageScale(a4(20), 1_000_000_000L), 0f)
        assertEquals(PdfShare.PDF_PAGE_SCALE, PdfShare.importedPageScale(emptyList(), 1_000_000_000L), 0f)
    }

    @Test
    fun aLongPdfsPicturesFitTheBudget() {
        val budget = 400_000_000L
        val pages = a4(300)
        val scale = PdfShare.importedPageScale(pages, budget)
        assertTrue(scale < PdfShare.PDF_PAGE_SCALE)
        assertTrue(pictureBytes(pages, scale) <= budget * 1.0001)
        // It uses the budget: a tenth more per point would not fit.
        assertTrue(pictureBytes(pages, scale * 1.1f) > budget)
    }

    @Test
    fun slidesAndA4PagesShareOneScale() {
        val pages = a4(40) + List(60) { PageSize(960f, 540f) }
        val scale = PdfShare.importedPageScale(pages, 200_000_000L)
        assertTrue(pictureBytes(pages, scale) <= 200_000_000L * 1.0001)
        assertEquals(PdfShare.PDF_PAGE_SCALE, PdfShare.importedPageScale(pages, 2_000_000_000L), 0f)
    }
}
