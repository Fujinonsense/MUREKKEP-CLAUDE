package com.murekkep.notebook.data

import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor
import com.murekkep.notebook.render.PageSize
import java.io.Closeable
import java.io.File
import kotlin.math.ceil
import kotlin.math.max

// An imported PDF read with Android's PdfRenderer (PDFGeometry and the rasterizing of
// PDFTextureCache on iPad): its pages' sizes, and pictures of any part of a page at any scale.
// PdfRenderer has one page open at a time, so every call is serialized; the canvas and the export
// each open their own source.

class PdfSource(file: File) : Closeable {
    private val descriptor = ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
    private val renderer: PdfRenderer = try {
        PdfRenderer(descriptor)
    } catch (e: Exception) {
        descriptor.close()
        throw e
    }

    val pageCount: Int = renderer.pageCount

    /** Each page's size in points as it is shown (PdfRenderer turns rotated pages). */
    val sizes: List<PageSize> = synchronized(this) {
        (0 until pageCount).map { i -> renderer.openPage(i).use { PageSize(it.width.toFloat(), it.height.toFloat()) } }
    }

    /** `region` of page `index` (page points: left, top, width, height) at `scale` pixels per point,
     *  on white (a PDF page need not paint its own background). */
    @Synchronized
    fun render(index: Int, left: Float, top: Float, width: Float, height: Float, scale: Float): Bitmap {
        val bitmap = Bitmap.createBitmap(max(1, ceil(width * scale).toInt()), max(1, ceil(height * scale).toInt()), Bitmap.Config.ARGB_8888)
        bitmap.eraseColor(Color.WHITE)
        renderer.openPage(index).use { page ->
            val m = Matrix()
            m.setScale(scale, scale)
            m.postTranslate(-left * scale, -top * scale)
            page.render(bitmap, null, m, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
        }
        return bitmap
    }

    /** The whole of page `index` at `scale` pixels per point. */
    fun renderPage(index: Int, scale: Float): Bitmap {
        val s = sizes[index]
        return render(index, 0f, 0f, s.width, s.height, scale)
    }

    @Synchronized
    override fun close() {
        renderer.close()
        descriptor.close()
    }
}
