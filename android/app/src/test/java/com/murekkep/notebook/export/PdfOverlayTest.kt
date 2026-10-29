package com.murekkep.notebook.export

import com.murekkep.notebook.ink.Brush
import com.murekkep.notebook.ink.InkColor
import com.murekkep.notebook.ink.InkPoint
import com.murekkep.notebook.ink.Stroke
import com.murekkep.notebook.render.PageSize
import com.tom_roush.pdfbox.contentstream.operator.Operator
import com.tom_roush.pdfbox.cos.COSDictionary
import com.tom_roush.pdfbox.cos.COSName
import com.tom_roush.pdfbox.cos.COSNumber
import com.tom_roush.pdfbox.pdfparser.PDFStreamParser
import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.pdmodel.PDPage
import com.tom_roush.pdfbox.pdmodel.PDPageContentStream
import com.tom_roush.pdfbox.pdmodel.common.PDRectangle
import com.tom_roush.pdfbox.pdmodel.graphics.form.PDFormXObject
import java.io.ByteArrayOutputStream
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

// A shared imported PDF keeps its pages, and the ink goes onto them where the editor drew it: the
// ink page's space taken through the page's crop box and /Rotate to the page's own, the inverse of
// the iPad's PDFGeometry.concatPageTransform, for every turn and a crop box off the origin; and
// PDFBox lays the ink on as a form that blends with the page (no transparency group of its own),
// after the page's own content.
class PdfOverlayTest {
    /** Where the iPad shows a point of the page's own space (concatPageTransform, then y down). */
    private fun shownAt(x: Float, y: Float, left: Float, bottom: Float, width: Float, height: Float, rotation: Int): Pair<Float, Float> {
        val dx = x - left
        val dy = y - bottom
        return when (rotation) {
            90 -> dy to dx
            180 -> (width - dx) to dy
            270 -> (height - dy) to (width - dx)
            else -> dx to (height - dy)
        }
    }

    private fun apply(m: FloatArray, p: Float, q: Float): Pair<Float, Float> =
        (m[0] * p + m[2] * q + m[4]) to (m[1] * p + m[3] * q + m[5])

    @Test
    fun theInkLandsWhereTheEditorDrewItOnEveryTurn() {
        val left = 18f
        val bottom = 30f
        val width = 559.28f
        val height = 780.89f
        for (rotation in listOf(0, 90, 180, 270)) {
            val shown = PdfOverlay.shownSize(width, height, rotation)
            // The ink page is whole points, rounded up.
            val inkHeight = PdfExport.inkPageSize(shown.height).toFloat()
            val m = PdfOverlay.placement(left, bottom, width, height, rotation, inkHeight)
            for ((u, v) in listOf(0f to 0f, shown.width to 0f, 0f to shown.height, shown.width to shown.height, 120.5f to 333.25f)) {
                // The editor's (u, v), y down, is (u, inkHeight - v) on the ink page.
                val (x, y) = apply(m, u, inkHeight - v)
                val (su, sv) = shownAt(x, y, left, bottom, width, height, rotation)
                assertEquals("turn $rotation, u of ($u, $v)", u, su, 0.01f)
                assertEquals("turn $rotation, v of ($u, $v)", v, sv, 0.01f)
            }
        }
    }

    @Test
    fun aTurnedPageIsShownOnItsSide() {
        assertEquals(PageSize(612f, 792f), PdfOverlay.shownSize(612f, 792f, 0))
        assertEquals(PageSize(792f, 612f), PdfOverlay.shownSize(612f, 792f, 90))
        assertEquals(PageSize(612f, 792f), PdfOverlay.shownSize(612f, 792f, 180))
        assertEquals(PageSize(792f, 612f), PdfOverlay.shownSize(612f, 792f, 270))
        assertEquals(842, PdfExport.inkPageSize(841.89f))
        assertEquals(595, PdfExport.inkPageSize(595f))
    }

    private val line = Stroke(Brush.PEN, InkColor(0f, 0f, 0f), 2f, 1.0, 0.2f, (0..10).map { InkPoint(100f + it * 5f, 100f, 1f, 0.5f) })

    private fun source(): PDDocument {
        val doc = PDDocument()
        // A plain page, and a landscape page made by turning a portrait one, its crop box off the origin.
        doc.addPage(PDPage(PDRectangle(612f, 792f)))
        doc.addPage(PDPage(PDRectangle(612f, 792f)).apply {
            cropBox = PDRectangle(20f, 40f, 560f, 700f)
            rotation = 90
        })
        doc.addPage(PDPage(PDRectangle(612f, 792f)))
        for (page in doc.pages) {
            PDPageContentStream(doc, page).use { cs ->
                cs.addRect(50f, 50f, 100f, 100f)
                cs.fill()
            }
        }
        return doc
    }

    private fun inkFor(sizes: List<PageSize>): PDDocument {
        val ink = PDDocument()
        for (s in sizes) {
            val page = PDPage(PDRectangle(PdfExport.inkPageSize(s.width).toFloat(), PdfExport.inkPageSize(s.height).toFloat()))
            ink.addPage(page)
            PDPageContentStream(ink, page).use { cs ->
                cs.addRect(10f, 10f, 20f, 20f)
                cs.fill()
            }
        }
        return ink
    }

    @Test
    fun onlyPagesWithInkAreTouchedAndTheyMustMatchTheEditorsPages() {
        source().use { doc ->
            val pages = listOf(listOf(line), listOf(line), emptyList())
            val sizes = listOf(PageSize(612f, 792f), PageSize(700f, 560f), PageSize(612f, 792f))
            val placed = PdfOverlay.inkedPages(doc, pages, sizes)!!
            assertEquals(listOf(0, 1), placed.map { it.index })
            assertEquals(PageSize(700f, 560f), placed[1].shown)
            // PdfRenderer counts whole points: a fraction off is the same page.
            assertNotNull(PdfOverlay.inkedPages(doc, pages, listOf(PageSize(611f, 791f), PageSize(700f, 560f), PageSize(1f, 1f))))
            // Another size or another count: the ink would not land where it was drawn.
            assertNull(PdfOverlay.inkedPages(doc, pages, listOf(PageSize(612f, 792f), PageSize(560f, 700f), PageSize(612f, 792f))))
            assertNull(PdfOverlay.inkedPages(doc, pages.take(2), sizes.take(2)))
        }
    }

    @Test
    fun theInkGoesOnAfterThePagesOwnContentAsAFormThatBlendsWithIt() {
        source().use { doc ->
            val pages = listOf(listOf(line), listOf(line), emptyList())
            val sizes = listOf(PageSize(612f, 792f), PageSize(700f, 560f), PageSize(612f, 792f))
            val placed = PdfOverlay.inkedPages(doc, pages, sizes)!!
            inkFor(sizes).use { ink ->
                // A form taken from a page keeps the page's transparency group (Skia's pages may
                // carry one); the overlay takes it away.
                val group = COSDictionary().apply {
                    setItem(COSName.TYPE, COSName.GROUP)
                    setItem(COSName.getPDFName("S"), COSName.TRANSPARENCY)
                }
                ink.getPage(1).cosObject.setItem(COSName.GROUP, group)
                PdfOverlay.layInk(doc, ink, placed)
            }
            for (p in placed) {
                val page = doc.getPage(p.index)
                val tokens = PDFStreamParser(page).apply { parse() }.tokens
                fun at(name: String, from: Int = 0) = (from until tokens.size).first { (tokens[it] as? Operator)?.name == name }
                // The page's own rectangle comes first, wrapped in q/Q; the ink is drawn after it.
                assertEquals("q", (tokens.first { it is Operator } as Operator).name)
                val fill = at("f")
                val cm = at("cm", fill)
                val draw = at("Do", cm)
                assertTrue(at("Q", fill) < cm)
                val numbers = tokens.subList(cm - 6, cm).map { (it as COSNumber).floatValue() }.toFloatArray()
                val inkHeight = PdfExport.inkPageSize(p.shown.height).toFloat()
                assertArrayEquals(PdfOverlay.placement(p.left, p.bottom, p.width, p.height, p.rotation, inkHeight), numbers, 0.001f)
                val name = tokens[draw - 1] as COSName
                val form = page.resources.getXObject(name) as PDFormXObject
                assertNull(form.cosObject.getDictionaryObject(COSName.GROUP))
                assertEquals(inkHeight, form.bBox.height, 0.001f)
            }
            // The page without ink is as it was.
            assertEquals(listOf("re", "f"), PDFStreamParser(doc.getPage(2)).apply { parse() }.tokens.filterIsInstance<Operator>().map { it.name })
            // And the file is whole: it reads back with its three pages.
            val bytes = ByteArrayOutputStream().also { doc.save(it) }.toByteArray()
            PDDocument.load(bytes).use { assertEquals(3, it.numberOfPages) }
        }
    }
}
