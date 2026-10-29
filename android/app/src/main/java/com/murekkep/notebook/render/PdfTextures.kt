package com.murekkep.notebook.render

import android.graphics.Bitmap
import android.opengl.GLES30
import android.opengl.GLUtils
import com.murekkep.notebook.data.PdfSource
import java.io.File
import java.util.concurrent.ConcurrentLinkedQueue
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference
import kotlin.math.max
import kotlin.math.min

// An imported PDF's pages as textures (PDFTextureCache on iPad): each page near the screen gets a
// picture at about the size it has when it fits the width (the base); zoomed in, the part of a page
// on screen gets a sharper picture at the view's scale (the detail). PdfRenderer draws them on a
// worker thread, the GL thread uploads them and draws them under the ink; the view is asked for a
// frame when one is ready. Only the newest detail request is drawn: while the pages move, older
// ones are dropped, so the detail arrives once the view settles.

class PdfTextures(file: File, private val requestRender: () -> Unit) {
    /** A picture of `left, top, width, height` (page points) of a page, at `scale` pixels per point. */
    class Texture(val id: Int, val scale: Float, val left: Float, val top: Float, val width: Float, val height: Float) {
        fun covers(l: Float, t: Float, w: Float, h: Float) =
            l >= left - 0.5f && t >= top - 0.5f && l + w <= left + width + 0.5f && t + h <= top + height + 0.5f
    }

    /** A part of a page on screen (page points). */
    class Region(val page: Int, val left: Float, val top: Float, val width: Float, val height: Float)

    private class Picture(
        val page: Int, val detail: Boolean, val bitmap: Bitmap, val scale: Float,
        val left: Float, val top: Float, val width: Float, val height: Float, val generation: Int,
    )

    private class DetailRequest(val regions: List<Region>, val scale: Float, val generation: Int)

    private val worker: ExecutorService = Executors.newSingleThreadExecutor { r ->
        Thread(r, "pdf-pages").apply { priority = Thread.NORM_PRIORITY - 1 }
    }
    private val source: PdfSource? = try {
        PdfSource(file)
    } catch (e: Exception) {
        null
    }
    private val finished = ConcurrentLinkedQueue<Picture>()
    private val nextDetail = AtomicReference<DetailRequest?>(null)
    private val detailGeneration = AtomicInteger(0)

    // GL thread only.
    private val base = HashMap<Int, Texture>()
    private val detail = HashMap<Int, Texture>()
    private val pendingBase = HashSet<Int>()
    @Volatile private var maxTextureSize = 0
    private var released = false

    /** GL thread, at the start of a frame: uploads the pictures that are ready. */
    fun upload() {
        if (maxTextureSize == 0) {
            val v = IntArray(1)
            GLES30.glGetIntegerv(GLES30.GL_MAX_TEXTURE_SIZE, v, 0)
            maxTextureSize = max(v[0], 2048)
        }
        while (true) {
            val p = finished.poll() ?: break
            if (released || (p.detail && p.generation != detailGeneration.get())) {
                p.bitmap.recycle()
                continue
            }
            val id = newTexture(p.bitmap, mipmaps = !p.detail)
            p.bitmap.recycle()
            val t = Texture(id, p.scale, p.left, p.top, p.width, p.height)
            if (p.detail) {
                detail.put(p.page, t)?.let { delete(it) }
            } else {
                base.put(p.page, t)?.let { delete(it) }
                pendingBase.remove(p.page)
            }
        }
    }

    /** GL thread: the page's base picture (null until it is ready; it is asked for then). `scale` is
     *  the page's pixels per point when it fits the width; very large pages get a smaller picture. */
    fun base(page: Int, size: PageSize, scale: Float): Texture? {
        val t = base[page]
        if (t == null && page !in pendingBase && source != null) {
            pendingBase.add(page)
            val s = min(scale, BASE_LIMIT.toFloat() / max(size.width, size.height))
            worker.execute {
                val bitmap = renderOrNull(page, 0f, 0f, size.width, size.height, s) ?: return@execute
                finished.add(Picture(page, false, bitmap, s, 0f, 0f, size.width, size.height, 0))
                requestRender()
            }
        }
        return t
    }

    /** GL thread: the sharper picture of the part of the page on screen, when there is one. */
    fun detail(page: Int): Texture? = detail[page]

    /** GL thread: the parts of the pages on screen at the view's scale. Pages whose base picture is
     *  sharp enough need nothing; for the others, unless their detail already covers what is on
     *  screen at this scale, a new detail is asked for (the newest request replaces any waiting one). */
    fun want(regions: List<Region>, scale: Float) {
        if (source == null || maxTextureSize == 0) return
        val needed = regions.filter { r ->
            val b = base[r.page] ?: return@filter false
            if (b.scale >= scale * 0.95f) return@filter false
            val d = detail[r.page]
            d == null || d.scale < scale * 0.95f || !d.covers(r.left, r.top, r.width, r.height)
        }
        if (needed.isEmpty()) return
        val generation = detailGeneration.incrementAndGet()
        nextDetail.set(DetailRequest(needed, scale, generation))
        worker.execute(::renderDetail)
    }

    /** Worker: draws the newest detail request (older ones were replaced before their turn). */
    private fun renderDetail() {
        val request = nextDetail.getAndSet(null) ?: return
        val limit = min(maxTextureSize, DETAIL_LIMIT).toFloat()
        for (r in request.regions) {
            // A margin round what is on screen, so a small move stays sharp.
            val size = source?.sizes?.getOrNull(r.page) ?: continue
            val padX = r.width * 0.15f
            val padY = r.height * 0.15f
            val left = max(0f, r.left - padX)
            val top = max(0f, r.top - padY)
            val width = min(size.width, r.left + r.width + padX) - left
            val height = min(size.height, r.top + r.height + padY) - top
            if (width <= 0f || height <= 0f) continue
            val s = min(request.scale, limit / max(width, height))
            val bitmap = renderOrNull(r.page, left, top, width, height, s) ?: continue
            finished.add(Picture(r.page, true, bitmap, s, left, top, width, height, request.generation))
        }
        requestRender()
    }

    private fun renderOrNull(page: Int, left: Float, top: Float, width: Float, height: Float, scale: Float): Bitmap? =
        try {
            source?.render(page, left, top, width, height, scale)
        } catch (e: Exception) {
            null
        } catch (e: OutOfMemoryError) {
            null
        }

    /** GL thread: forgets the pictures of pages more than two away from the screen. */
    fun keep(visible: List<Int>) {
        if (visible.isEmpty()) return
        val lo = visible.first() - 2
        val hi = visible.last() + 2
        for (k in base.keys.filter { it < lo || it > hi }) base.remove(k)?.let { delete(it) }
        for (k in detail.keys.filter { it !in visible }) detail.remove(k)?.let { delete(it) }
        pendingBase.retainAll { it in lo..hi }
    }

    /** GL thread: deletes every texture; the worker closes the PDF and stops. */
    fun release() {
        released = true
        for (t in base.values + detail.values) delete(t)
        base.clear()
        detail.clear()
        worker.execute { source?.close() }
        worker.shutdown()
    }

    private fun newTexture(bitmap: Bitmap, mipmaps: Boolean): Int {
        val ids = IntArray(1)
        GLES30.glGenTextures(1, ids, 0)
        GLES30.glBindTexture(GLES30.GL_TEXTURE_2D, ids[0])
        GLES30.glTexParameteri(GLES30.GL_TEXTURE_2D, GLES30.GL_TEXTURE_WRAP_S, GLES30.GL_CLAMP_TO_EDGE)
        GLES30.glTexParameteri(GLES30.GL_TEXTURE_2D, GLES30.GL_TEXTURE_WRAP_T, GLES30.GL_CLAMP_TO_EDGE)
        GLES30.glTexParameteri(GLES30.GL_TEXTURE_2D, GLES30.GL_TEXTURE_MAG_FILTER, GLES30.GL_LINEAR)
        GLES30.glTexParameteri(
            GLES30.GL_TEXTURE_2D, GLES30.GL_TEXTURE_MIN_FILTER,
            if (mipmaps) GLES30.GL_LINEAR_MIPMAP_LINEAR else GLES30.GL_LINEAR,
        )
        GLUtils.texImage2D(GLES30.GL_TEXTURE_2D, 0, bitmap, 0)
        if (mipmaps) GLES30.glGenerateMipmap(GLES30.GL_TEXTURE_2D)
        return ids[0]
    }

    private fun delete(t: Texture) {
        GLES30.glDeleteTextures(1, intArrayOf(t.id), 0)
    }

    companion object {
        /** Longest side of a base picture in pixels (a page fits the width of a tablet at about this). */
        private const val BASE_LIMIT = 2560

        /** Longest side of a detail picture: a screen and its margin. */
        private const val DETAIL_LIMIT = 4096
    }
}
