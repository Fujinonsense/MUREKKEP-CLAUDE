package com.murekkep.notebook.export

import android.content.Context
import com.murekkep.notebook.ink.Stroke
import com.murekkep.notebook.render.PageSize
import com.tom_roush.pdfbox.android.PDFBoxResourceLoader
import com.tom_roush.pdfbox.cos.COSName
import com.tom_roush.pdfbox.io.MemoryUsageSetting
import com.tom_roush.pdfbox.multipdf.LayerUtility
import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.pdmodel.PDPageContentStream
import com.tom_roush.pdfbox.util.Matrix
import java.io.File
import kotlin.math.abs

// An imported PDF shared as the iPad shares it: exportPDF draws each of the source's own pages
// (PDFGeometry.draw, vectors and text as they are), then the ink over it. Android cannot draw one
// PDF's page into another, so the ink is written alone (PdfExport.writeInk: no paper, no white) and
// laid onto the source's pages with PDFBox: each inked page of it becomes a form on its page,
// placed through the page's crop box and /Rotate the way the editor shows the page (PdfRenderer,
// and PDFGeometry's turn on the iPad). Pages without ink stay exactly as they were, and so does the
// rest of the file; a password that only guards the file's permissions is dropped, as the iPad's
// new file has none.

object PdfOverlay {
    /** The most of the source kept in memory while it is rewritten; the rest goes to scratch files. */
    private const val MAIN_MEMORY = 32L shl 20

    /** How far PDFBox's size of a page may be from PdfRenderer's, which counts whole points. */
    private const val SIZE_TOLERANCE = 1.5f

    /** An inked page as PDFBox reads it: its crop box (left, bottom, width, height) and its turn. */
    class Placed(val index: Int, val left: Float, val bottom: Float, val width: Float, val height: Float, val rotation: Int) {
        /** The page as it is shown: the crop box turned. */
        val shown: PageSize get() = shownSize(width, height, rotation)
    }

    /**
     * Writes [source] with [pages]' ink over its pages into [out]; [sizes] are the pages as the
     * editor shows them (PdfRenderer's). False when PDFBox reads the source otherwise than
     * PdfRenderer does (another page count, or a page of another size), as the ink would not land
     * where it was written. Throws when PDFBox cannot read or write it. [scratch] is an empty folder
     * for the files on the way.
     */
    fun write(context: Context, source: File, pages: List<List<Stroke>>, sizes: List<PageSize>, out: File, scratch: File): Boolean {
        if (pages.all { it.isEmpty() }) {
            // No ink: the PDF as it came in.
            source.copyTo(out, overwrite = true)
            return true
        }
        PDFBoxResourceLoader.init(context.applicationContext)
        scratch.mkdirs()
        val memory = MemoryUsageSetting.setupMixed(MAIN_MEMORY).setTempDir(scratch)
        PDDocument.load(source, memory).use { doc ->
            val placed = inkedPages(doc, pages, sizes) ?: return false
            val shownByPage = placed.associate { it.index to it.shown }
            val inkSizes = pages.indices.map { i ->
                val s = shownByPage[i] ?: sizes[i]
                s.width to s.height
            }
            val inkFile = File(scratch, "ink.pdf")
            inkFile.outputStream().buffered().use { PdfExport.writeInk(it, pages, inkSizes) }
            PDDocument.load(inkFile, MemoryUsageSetting.setupMainMemoryOnly()).use { ink ->
                layInk(doc, ink, placed)
            }
            if (doc.isEncrypted) doc.isAllSecurityToBeRemoved = true
            doc.save(out)
        }
        return true
    }

    /** The pages that have ink, each as PDFBox reads it; null when the source does not match the
     *  editor's pages ([sizes], PdfRenderer's) in count or in a page's size. */
    internal fun inkedPages(doc: PDDocument, pages: List<List<Stroke>>, sizes: List<PageSize>): List<Placed>? {
        if (doc.numberOfPages != pages.size || sizes.size != pages.size) return null
        val placed = ArrayList<Placed>()
        for (i in pages.indices) {
            if (pages[i].isEmpty()) continue
            val page = doc.getPage(i)
            // The crop box clipped to the media box, as PdfRenderer and Core Graphics take it.
            val box = page.cropBox
            val p = Placed(i, box.lowerLeftX, box.lowerLeftY, box.width, box.height, page.rotation)
            val shown = p.shown
            if (abs(shown.width - sizes[i].width) > SIZE_TOLERANCE || abs(shown.height - sizes[i].height) > SIZE_TOLERANCE) return null
            placed.add(p)
        }
        return placed
    }

    /** Lays each of [placed]'s ink pages (from [ink], page for page) over its page of [doc]. */
    internal fun layInk(doc: PDDocument, ink: PDDocument, placed: List<Placed>) {
        val layers = LayerUtility(doc)
        for (p in placed) {
            val form = layers.importPageAsForm(ink, p.index)
            // Not a transparency group of its own: the highlighter multiplies with the page under it.
            form.cosObject.removeItem(COSName.GROUP)
            val m = placement(p.left, p.bottom, p.width, p.height, p.rotation, ink.getPage(p.index).mediaBox.height)
            // Appended after the page's own content, which is wrapped in q/Q so it starts from the page's space.
            PDPageContentStream(doc, doc.getPage(p.index), PDPageContentStream.AppendMode.APPEND, true, true).use { cs ->
                cs.saveGraphicsState()
                cs.transform(Matrix(m[0], m[1], m[2], m[3], m[4], m[5]))
                cs.drawForm(form)
                cs.restoreGraphicsState()
            }
        }
    }

    /** A page's size as shown: [width] x [height] turned by [rotation] degrees. */
    fun shownSize(width: Float, height: Float, rotation: Int): PageSize =
        if (rotation % 180 == 90) PageSize(height, width) else PageSize(width, height)

    /**
     * The matrix (a b c d e f, as PDF's cm takes it) from an ink page's space (y up, [inkHeight]
     * tall, the shown page's top-left at (0, inkHeight)) to the space of a source page whose crop
     * box starts at ([left], [bottom]), is [width] x [height] and turns [rotation] degrees clockwise:
     * what the editor drew at (u, v) on the shown page (y down) lands where the page shows (u, v).
     * The inverse of the iPad's PDFGeometry.concatPageTransform.
     */
    fun placement(left: Float, bottom: Float, width: Float, height: Float, rotation: Int, inkHeight: Float): FloatArray = when (rotation) {
        90 -> floatArrayOf(0f, 1f, -1f, 0f, left + inkHeight, bottom)
        180 -> floatArrayOf(-1f, 0f, 0f, -1f, left + width, bottom + inkHeight)
        270 -> floatArrayOf(0f, -1f, 1f, 0f, left + width - inkHeight, bottom + height)
        else -> floatArrayOf(1f, 0f, 0f, 1f, left, bottom + height - inkHeight)
    }
}
