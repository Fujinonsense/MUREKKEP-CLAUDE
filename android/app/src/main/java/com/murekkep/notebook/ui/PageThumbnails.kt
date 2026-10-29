package com.murekkep.notebook.ui

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.unit.dp
import com.murekkep.notebook.data.PaperStyle
import com.murekkep.notebook.data.PdfSource
import com.murekkep.notebook.export.FlatInk
import com.murekkep.notebook.export.PaperDrawer
import com.murekkep.notebook.ink.Stroke
import com.murekkep.notebook.render.PageSize
import java.io.Closeable
import java.io.File
import java.util.concurrent.Executors
import kotlin.math.max
import kotlin.math.roundToInt
import kotlinx.coroutines.asCoroutineDispatcher
import kotlinx.coroutines.withContext

// Small pictures of a note's pages for the page navigator (PageThumbnails in
// Murekkep.swiftpm/PageNavigator.swift): the paper or the PDF's own page with the ink on it, 120 dp
// across, drawn one at a time on a worker thread as their tiles come into view, and kept while the
// navigator is open. The iPad keeps every picture; here the ones drawn first go once the pictures
// take more than a budget (a long PDF's pages), and a tile whose picture went draws it again.

class PageThumbnails(
    private val pdfFile: File?,
    private val paper: PaperStyle,
    /** A picture's width in pixels ([WIDTH] on this screen). */
    private val pixelWidth: Int,
    budget: Long = BUDGET,
) : Closeable {
    companion object {
        /** A picture's width (PageThumbnails.width on iPad, 120 points there). */
        val WIDTH = 120.dp

        /** The most the pictures take, in bytes: about 150 A4 pages at twice the dp. */
        const val BUDGET = 48L shl 20

        /** A picture's size in pixels, [pixelWidth] across, for a page of [width] x [height] points
         *  (the iPad's: the width over the page's, the height rounded). */
        fun pixelSize(width: Float, height: Float, pixelWidth: Int): Pair<Int, Int> =
            pixelWidth to max(1, (height * pixelWidth / max(width, 1f)).roundToInt())
    }

    /** The pictures drawn, by page (main thread). */
    private val images = mutableStateMapOf<Int, ImageBitmap>()
    private val kept = ThumbnailBudget(budget)
    private val executor = Executors.newSingleThreadExecutor { r ->
        Thread(r, "page-thumbnails").apply { priority = Thread.NORM_PRIORITY - 1 }
    }
    private val worker = executor.asCoroutineDispatcher()

    // The worker's only: the PDF, opened the first time one of its pages is drawn.
    private var source: PdfSource? = null
    private var sourceOpened = false

    /** Page [page]'s picture once it is drawn; observable. */
    fun image(page: Int): ImageBitmap? = images[page]

    /** Draws page [page] ([strokes] on a page of [size] points) unless its picture is here. Called
     *  on the main thread; the drawing waits its turn on the worker. */
    suspend fun load(page: Int, strokes: List<Stroke>, size: PageSize) {
        if (images.containsKey(page)) return
        val bitmap = withContext(worker) { draw(page, strokes, size) } ?: return
        images[page] = bitmap.asImageBitmap()
        for (gone in kept.add(page, bitmap.allocationByteCount.toLong())) images.remove(gone)
    }

    /** The navigator closed: the worker closes the PDF and ends. */
    override fun close() {
        executor.execute {
            source?.close()
            source = null
        }
        executor.shutdown()
    }

    /** White, the PDF's page or the paper, then the ink, at the picture's scale (on the worker). */
    private fun draw(page: Int, strokes: List<Stroke>, size: PageSize): Bitmap? = try {
        val pdf = pdf()?.takeIf { page < it.pageCount }
        val shown = pdf?.sizes?.get(page) ?: size
        val (w, h) = pixelSize(shown.width, shown.height, pixelWidth)
        val scale = w / max(shown.width, 1f)
        val bitmap = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        bitmap.eraseColor(Color.WHITE)
        val canvas = Canvas(bitmap)
        if (pdf != null) {
            val picture = pdf.renderPage(page, scale)
            canvas.drawBitmap(picture, 0f, 0f, null)
            picture.recycle()
        }
        canvas.scale(scale, scale)
        if (pdf == null) PaperDrawer.draw(paper, shown.width, shown.height, canvas)
        FlatInk.draw(strokes, canvas)
        bitmap
    } catch (e: Exception) {
        null
    }

    /** The note's PDF; null for a notebook, or a PDF PdfRenderer cannot open (its pages get paper;
     *  on a JVM without Android's file descriptors, as in the tests, it opens none). */
    private fun pdf(): PdfSource? {
        if (!sourceOpened) {
            sourceOpened = true
            source = pdfFile?.let {
                try {
                    PdfSource(it)
                } catch (e: Exception) {
                    null
                } catch (e: LinkageError) {
                    null
                }
            }
        }
        return source
    }
}

/** Which pictures stay: once they take more than [budget] bytes the ones drawn first go, never the newest. */
internal class ThumbnailBudget(private val budget: Long) {
    private val sizes = LinkedHashMap<Int, Long>()
    private var total = 0L

    /** Counts page [page]'s new picture of [bytes]; returns the pages whose pictures go to make room. */
    fun add(page: Int, bytes: Long): List<Int> {
        sizes.remove(page)?.let { total -= it }
        sizes[page] = bytes
        total += bytes
        val gone = ArrayList<Int>()
        val oldest = sizes.entries.iterator()
        while (total > budget && sizes.size > 1) {
            val e = oldest.next()
            total -= e.value
            gone.add(e.key)
            oldest.remove()
        }
        return gone
    }
}
