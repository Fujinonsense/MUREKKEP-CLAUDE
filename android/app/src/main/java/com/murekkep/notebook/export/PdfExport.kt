package com.murekkep.notebook.export

import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.pdf.PdfDocument
import com.murekkep.notebook.data.PaperStyle
import com.murekkep.notebook.ink.Stroke
import java.io.OutputStream
import kotlin.math.ceil
import kotlin.math.roundToInt

// Port of exportPDF in Murekkep.swiftpm/EditorModel.swift: the note flattened into a vector PDF
// for sharing. For each page the paper template (or the imported page, when the caller draws it),
// then the ink as FlatInk draws it. A notebook's blank pages at the end (there is always one) stay
// out of the shared file; an imported PDF keeps all its pages. For an imported PDF the ink is also
// written alone (writeInk), for PdfOverlay to lay over the PDF's own pages.

object PdfExport {
    /**
     * Writes the PDF to `out`: one page per entry of `pages`, `sizes[i]` its width and height in
     * points. The page is filled white, then `background` draws on it when given (an imported PDF
     * page's picture), else the `paper` template; then the ink. `isPdf` says the note is an
     * imported PDF, which keeps every page; a notebook drops the blank pages at its end.
     *
     * android.graphics.pdf.PdfDocument takes whole points for the page size, so A4 (595.28 x
     * 841.89) comes out 595 x 842; the ink keeps its page coordinates.
     */
    fun write(
        out: OutputStream,
        pages: List<List<Stroke>>,
        sizes: List<Pair<Float, Float>>,
        paper: PaperStyle,
        isPdf: Boolean,
        background: ((page: Int, canvas: Canvas) -> Unit)? = null,
    ) {
        require(pages.isNotEmpty()) { "a note has at least one page" }
        require(pages.size == sizes.size) { "one size per page: ${pages.size} pages, ${sizes.size} sizes" }
        val count = exportedPageCount(pages, isPdf)
        val white = Paint().apply {
            style = Paint.Style.FILL
            color = FlatInkGeometry.argb(1f, 1f, 1f, 1f)
        }
        val document = PdfDocument()
        try {
            for (i in 0 until count) {
                val (width, height) = sizes[i]
                val info = PdfDocument.PageInfo.Builder(pointSize(width), pointSize(height), i + 1).create()
                val page = document.startPage(info)
                // The page is finished even when drawing it throws (an imported page's picture that
                // does not fit in memory): close() refuses a document with an open page, so it would
                // keep every page's picture and its own error would take the place of this one.
                try {
                    val canvas = page.canvas
                    canvas.drawRect(0f, 0f, width, height, white)
                    if (background != null) {
                        background(i, canvas)
                    } else {
                        PaperDrawer.draw(paper, width, height, canvas)
                    }
                    FlatInk.draw(pages[i], canvas)
                } finally {
                    document.finishPage(page)
                }
            }
            document.writeTo(out)
        } finally {
            document.close()
        }
    }

    /**
     * Writes the ink alone to `out`, one page per entry of `pages` on a clear page (no white, no
     * paper): `sizes[i]` its width and height in points, rounded up to the whole points PdfDocument
     * takes ([inkPageSize]), so the page holds all of the page it goes onto. PdfOverlay lays these
     * pages over an imported PDF's own.
     */
    fun writeInk(out: OutputStream, pages: List<List<Stroke>>, sizes: List<Pair<Float, Float>>) {
        require(pages.size == sizes.size) { "one size per page: ${pages.size} pages, ${sizes.size} sizes" }
        val document = PdfDocument()
        try {
            for (i in pages.indices) {
                val (width, height) = sizes[i]
                val page = document.startPage(PdfDocument.PageInfo.Builder(inkPageSize(width), inkPageSize(height), i + 1).create())
                try {
                    FlatInk.draw(pages[i], page.canvas)
                } finally {
                    document.finishPage(page)
                }
            }
            document.writeTo(out)
        } finally {
            document.close()
        }
    }

    /** An ink page's edge in whole points, rounded up and never under one. */
    fun inkPageSize(points: Float): Int = ceil(points).toInt().coerceAtLeast(1)

    /**
     * How many pages the file gets: all of an imported PDF; of a notebook, up to the last page
     * with ink on it, and at least one (the iPad's `(pages.indices.last(where: pageIsUsed) ?? 0) + 1`).
     */
    fun exportedPageCount(pages: List<List<Stroke>>, isPdf: Boolean): Int =
        if (isPdf) pages.size else pages.indexOfLast { it.isNotEmpty() }.coerceAtLeast(0) + 1

    /** A page edge in the whole points PdfDocument takes, never under one. */
    fun pointSize(points: Float): Int = points.roundToInt().coerceAtLeast(1)
}
