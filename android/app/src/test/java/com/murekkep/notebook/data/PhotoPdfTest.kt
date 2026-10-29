package com.murekkep.notebook.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.ByteArrayOutputStream

// Photos as one PDF (PhotoPDF.swift on iPad): the pages' sizes, the photos' scaling, the file's
// name, and a PDF whose cross-reference table finds every object.
class PhotoPdfTest {
    @Test
    fun aPageTakesThePhotosShapeAsLongAsA4() {
        assertEquals(842 to 632, PhotoPdf.pageSize(2400, 1800))
        assertEquals(632 to 842, PhotoPdf.pageSize(1800, 2400))
        assertEquals(842 to 842, PhotoPdf.pageSize(500, 500))
        assertEquals(595 to 842, PhotoPdf.pageSize(0, 10))
    }

    @Test
    fun photosAreScaledDownNeverUp() {
        assertEquals(2400 to 1800, PhotoPdf.scaledPixels(4000, 3000))
        assertEquals(1800 to 2400, PhotoPdf.scaledPixels(3000, 4000))
        assertEquals(1000 to 500, PhotoPdf.scaledPixels(1000, 500))
    }

    @Test
    fun theFileNameHoldsNoForbiddenCharacters() {
        assertEquals("Fotoğraf 29 Eki 2026 11-06", PhotoPdf.fileName("Fotoğraf 29 Eki 2026 11:06"))
        assertEquals("a-b-c", PhotoPdf.fileName(" a/b\\c "))
        assertEquals("Photos", PhotoPdf.fileName("  "))
    }

    @Test
    fun thePhotosBecomeAPdfWhoseTableFindsEveryObject() {
        val first = ByteArray(100) { it.toByte() }
        val second = ByteArray(37) { 7 }
        val out = ByteArrayOutputStream()
        val done = ArrayList<Int>()
        val pages = PhotoPdf.write(
            out,
            3,
            page = { i ->
                when (i) {
                    0 -> PhotoPdf.Page(first, 2400, 1800)
                    1 -> null
                    else -> PhotoPdf.Page(second, 1800, 2400)
                }
            },
        ) { n, total ->
            done.add(n)
            assertEquals(3, total)
        }
        // The photo that could not be read is left out; the count still goes through it.
        assertEquals(2, pages)
        assertEquals(listOf(1, 2, 3), done)

        val bytes = out.toByteArray()
        val text = String(bytes, Charsets.ISO_8859_1)
        assertTrue(text.startsWith("%PDF-1.4\n"))
        assertTrue(text.endsWith("%%EOF\n"))
        val xref = Regex("startxref\n(\\d+)\n").find(text)!!.groupValues[1].toInt()
        assertTrue(text.startsWith("xref\n0 9\n0000000000 65535 f \n", xref))
        val entries = text.substring(xref).split("\n").drop(3).take(8)
        entries.forEachIndexed { i, entry ->
            assertEquals(19, entry.length)
            assertTrue("object ${i + 1}", text.startsWith("${i + 1} 0 obj\n", entry.substring(0, 10).toInt()))
        }
        assertTrue(text.contains("/Kids [3 0 R 6 0 R] /Count 2"))
        assertTrue(text.contains("/MediaBox [0 0 842 632]"))
        assertTrue(text.contains("/MediaBox [0 0 632 842]"))
        assertTrue(text.contains("/Width 2400 /Height 1800 /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Length 100"))
        // The photos go in as they are: the JPEG is the PDF's own image data.
        assertTrue(text.contains("stream\n" + String(first, Charsets.ISO_8859_1) + "\nendstream"))
        assertTrue(text.contains("stream\nq\n842 0 0 632 0 0 cm\n/Im0 Do\nQ\n\nendstream"))
    }

    @Test
    fun noReadablePhotoIsNoPdf() {
        assertEquals(0, PhotoPdf.write(ByteArrayOutputStream(), 2, page = { null }))
    }
}
