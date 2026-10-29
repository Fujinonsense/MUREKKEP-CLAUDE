package com.murekkep.notebook.data

import com.tom_roush.pdfbox.cos.COSDictionary
import com.tom_roush.pdfbox.io.MemoryUsageSetting
import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.pdmodel.interactive.documentnavigation.outline.PDOutlineNode
import java.io.File
import java.util.Collections
import java.util.IdentityHashMap

// An imported PDF's table of contents for the page navigator's İçindekiler (OutlineEntry in
// Murekkep.swiftpm/PageNavigator.swift, which PDFKit reads): each heading's title and the page it
// points at, read with PDFBox, which follows the same destinations (a page, a named destination, a
// GoTo action's). PdfRenderer has no outline. A heading met twice (a damaged file whose headings run
// in a loop) is read once.

/** One heading of a PDF's table of contents. */
data class OutlineEntry(
    val title: String,
    /** 0-based page the heading points at (null when it points nowhere in this file). */
    val page: Int?,
    /** The headings under it; null when there are none. */
    val children: List<OutlineEntry>?,
)

object PdfOutline {
    /** Headings under a heading this deep are not read (the iPad's `depth < 8`). */
    private const val MAX_DEPTH = 8

    /** The headings of the PDF in [file]; empty when it has none or cannot be read. Reads the file:
     *  off the main thread. */
    fun read(file: File): List<OutlineEntry> = try {
        PDDocument.load(file, MemoryUsageSetting.setupMainMemoryOnly()).use { doc ->
            doc.documentCatalog.documentOutline?.let { outline ->
                val pages = IdentityHashMap<COSDictionary, Int>()
                doc.pages.forEachIndexed { i, page -> pages[page.cosObject] = i }
                entries(outline, doc, pages, 0, Collections.newSetFromMap(IdentityHashMap()))
            } ?: emptyList()
        }
    } catch (e: Exception) {
        emptyList()
    }

    private fun entries(
        node: PDOutlineNode,
        doc: PDDocument,
        pages: Map<COSDictionary, Int>,
        depth: Int,
        seen: MutableSet<COSDictionary>,
    ): List<OutlineEntry> {
        val result = ArrayList<OutlineEntry>()
        var child = node.firstChild
        while (child != null && seen.add(child.cosObject)) {
            val page = try {
                child.findDestinationPage(doc)?.let { pages[it.cosObject] }
            } catch (e: Exception) {
                null
            }
            val kids = if (depth < MAX_DEPTH) entries(child, doc, pages, depth + 1, seen) else emptyList()
            val title = (child.title ?: "").trim()
            result.add(OutlineEntry(title.ifEmpty { "—" }, page, kids.ifEmpty { null }))
            child = child.nextSibling
        }
        return result
    }
}
