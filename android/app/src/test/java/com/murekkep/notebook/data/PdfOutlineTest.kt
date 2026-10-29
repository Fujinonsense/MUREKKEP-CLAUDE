package com.murekkep.notebook.data

import com.tom_roush.pdfbox.cos.COSName
import com.tom_roush.pdfbox.pdmodel.PDDestinationNameTreeNode
import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.pdmodel.PDDocumentNameDictionary
import com.tom_roush.pdfbox.pdmodel.PDPage
import com.tom_roush.pdfbox.pdmodel.common.PDRectangle
import com.tom_roush.pdfbox.pdmodel.interactive.action.PDActionGoTo
import com.tom_roush.pdfbox.pdmodel.interactive.documentnavigation.destination.PDNamedDestination
import com.tom_roush.pdfbox.pdmodel.interactive.documentnavigation.destination.PDPageFitDestination
import com.tom_roush.pdfbox.pdmodel.interactive.documentnavigation.outline.PDDocumentOutline
import com.tom_roush.pdfbox.pdmodel.interactive.documentnavigation.outline.PDOutlineItem
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

// A PDF's contents as the iPad's OutlineEntry.entries reads them with PDFKit: each heading's title
// (trimmed, "—" when blank) and the page it points at, by a page destination, a GoTo action's or a
// named one; nowhere when it points at nothing; headings nest nine deep at most (depth < 8); a
// file without contents, or one that is no PDF, has none; a damaged file whose headings run in a
// loop reads each once.
class PdfOutlineTest {
    @get:Rule
    val folder = TemporaryFolder()

    private fun pdf(pages: Int, build: (PDDocument, PDDocumentOutline) -> Unit = { _, _ -> }): File {
        val file = File(folder.root, "outline.pdf")
        PDDocument().use { doc ->
            repeat(pages) { doc.addPage(PDPage(PDRectangle.A4)) }
            val outline = PDDocumentOutline()
            build(doc, outline)
            if (outline.hasChildren()) doc.documentCatalog.documentOutline = outline
            doc.save(file)
        }
        return file
    }

    private fun heading(title: String?) = PDOutlineItem().apply { if (title != null) this.title = title }

    private fun PDDocument.to(index: Int): PDPageFitDestination {
        val target = getPage(index)
        return PDPageFitDestination().apply { page = target }
    }

    @Test
    fun headingsGoToTheirPagesWhicheverWayTheyPointThere() {
        val file = pdf(3) { doc, outline ->
            val one = heading("Chapter 1").apply { destination = doc.to(0) }
            one.addLast(heading("1.1 Intro").apply { action = PDActionGoTo().apply { destination = doc.to(1) } })
            one.addLast(heading("  \n").apply { destination = doc.to(2) })
            outline.addLast(one)
            // A named destination, kept in the catalogue's name tree.
            val names = PDDocumentNameDictionary(doc.documentCatalog)
            names.dests = PDDestinationNameTreeNode().apply { this.names = mapOf("ch2" to doc.to(2)) }
            doc.documentCatalog.names = names
            outline.addLast(heading("Chapter 2").apply { destination = PDNamedDestination("ch2") })
            outline.addLast(heading("Nowhere"))
            outline.addLast(heading(null).apply { destination = PDNamedDestination("missing") })
        }
        assertEquals(
            listOf(
                OutlineEntry("Chapter 1", 0, listOf(OutlineEntry("1.1 Intro", 1, null), OutlineEntry("—", 2, null))),
                OutlineEntry("Chapter 2", 2, null),
                OutlineEntry("Nowhere", null, null),
                OutlineEntry("—", null, null),
            ),
            PdfOutline.read(file),
        )
    }

    @Test
    fun headingsNestNineDeepAtMost() {
        val file = pdf(1) { doc, outline ->
            var parent = heading("0").apply { destination = doc.to(0) }
            outline.addLast(parent)
            for (level in 1..10) {
                val child = heading("$level")
                parent.addLast(child)
                parent = child
            }
        }
        var entry = PdfOutline.read(file).single()
        for (level in 0 until 8) {
            assertEquals("$level", entry.title)
            entry = entry.children!!.single()
        }
        assertEquals("8", entry.title)
        assertNull(entry.children)
    }

    @Test
    fun aFileWithoutContentsOrNoPdfAtAllHasNone() {
        assertEquals(emptyList<OutlineEntry>(), PdfOutline.read(pdf(2)))
        val notPdf = File(folder.root, "notes.pdf").apply { writeText("not a PDF") }
        assertEquals(emptyList<OutlineEntry>(), PdfOutline.read(notPdf))
        assertEquals(emptyList<OutlineEntry>(), PdfOutline.read(File(folder.root, "missing.pdf")))
    }

    @Test
    fun headingsThatRunInALoopAreReadOnce() {
        val file = pdf(2) { doc, outline ->
            val a = heading("A").apply { destination = doc.to(0) }
            val b = heading("B").apply { destination = doc.to(1) }
            outline.addLast(a)
            outline.addLast(b)
            // B's next sibling is A again.
            b.cosObject.setItem(COSName.NEXT, a.cosObject)
        }
        assertEquals(listOf(OutlineEntry("A", 0, null), OutlineEntry("B", 1, null)), PdfOutline.read(file))
    }
}
