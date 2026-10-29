package com.murekkep.notebook.render

import com.murekkep.notebook.ink.Brush
import com.murekkep.notebook.ink.InkColor
import com.murekkep.notebook.ink.InkPoint
import com.murekkep.notebook.ink.PageInk
import com.murekkep.notebook.ink.Vec2

/** A page's size in points. */
data class PageSize(val width: Float, val height: Float) {
    companion object {
        /** A notebook's page (NoteMeta.a4 on iPad). */
        val A4 = PageSize(595.28f, 841.89f)
    }
}

/** Pages stacked from the top (DocumentLayout on iPad): page `i` covers (left(i), top(i)) to
 *  (left(i) + width(i), top(i) + height(i)) in document points. A notebook's pages are all A4; an
 *  imported PDF's have its own sizes, the narrower ones centered on the widest. Ink is kept in each
 *  page's own points (`toPage`, `toDoc`). */
class PageLayout(val sizes: List<PageSize>, val gap: Float = 24f) {
    /** `pageCount` A4 pages (a notebook). */
    constructor(pageCount: Int) : this(List(pageCount) { PageSize.A4 })

    val pageCount: Int get() = sizes.size

    /** The widest page: the column the pages are centered in. */
    val pageWidth: Float = sizes.maxOfOrNull { it.width } ?: PageSize.A4.width

    private val tops = FloatArray(sizes.size).also { t ->
        var y = 0f
        for (i in sizes.indices) {
            t[i] = y
            y += sizes[i].height + gap
        }
    }

    val totalHeight: Float = if (sizes.isEmpty()) 0f else tops.last() + sizes.last().height

    /** Past the last page: where A4 pages after it would stand. */
    fun top(i: Int): Float = when {
        i <= 0 -> 0f
        i < tops.size -> tops[i]
        else -> totalHeight + gap + (i - tops.size) * (PageSize.A4.height + gap)
    }

    fun left(i: Int): Float = (pageWidth - width(i)) / 2f

    fun width(i: Int): Float = sizes.getOrNull(i)?.width ?: PageSize.A4.width

    fun height(i: Int): Float = sizes.getOrNull(i)?.height ?: PageSize.A4.height

    /** A document point in page `i`'s own points. */
    fun toPage(i: Int, x: Float, y: Float): Vec2 = Vec2(x - left(i), y - top(i))

    /** A point of page `i` in document points. */
    fun toDoc(i: Int, x: Float, y: Float): Vec2 = Vec2(x + left(i), y + top(i))

    /** The pages any part of which lies between `minY` and `maxY` (document points). */
    fun pagesBetween(minY: Float, maxY: Float): List<Int> {
        if (sizes.isEmpty()) return emptyList()
        // The first page whose bottom reaches minY.
        var lo = 0
        var hi = sizes.size - 1
        while (lo < hi) {
            val mid = (lo + hi) / 2
            if (tops[mid] + sizes[mid].height < minY) lo = mid + 1 else hi = mid
        }
        val out = ArrayList<Int>()
        var i = lo
        while (i < sizes.size && tops[i] <= maxY) {
            if (tops[i] + sizes[i].height >= minY) out.add(i)
            i++
        }
        return out
    }

    /** The page under a document point, within `tolerance` points of its edges. */
    fun pageAt(x: Float, y: Float, tolerance: Float = 0f): Int? {
        for (i in pagesBetween(y - tolerance, y + tolerance)) {
            val l = left(i)
            if (x >= l - tolerance && x <= l + width(i) + tolerance &&
                y >= tops[i] - tolerance && y <= tops[i] + sizes[i].height + tolerance
            ) {
                return i
            }
        }
        return null
    }
}

/** The stroke under the pen, drawn every frame from its preview points (ActiveStroke on iPad). */
class ActiveStroke(
    val page: Int,
    val brush: Brush,
    val color: InkColor,
    val width: Float,
    val seed: Float,
    val points: List<InkPoint>,
    /** Reference seconds (2001) when the pen touched down. */
    val startTime: Double,
)

/** Everything a frame shows, handed from the UI thread to the GL thread in one piece. */
class FrameInput(
    val pages: List<PageInk>,
    val layout: PageLayout,
    /** Where the document's origin is in the view, in pixels. */
    val originX: Float,
    val originY: Float,
    /** View pixels per document point. */
    val zoom: Float,
    val active: ActiveStroke?,
    /** PaperStyle.shaderIndex on iPad: 0 plain, 1 lined, 2 grid, 3 dotted. */
    val paperStyle: Int,
    val animate: Boolean,
    val dryDuration: Float = 4f,
    val coolDuration: Float = 6f,
    /** An imported PDF's pages, drawn under the ink instead of paper. */
    val pdf: PdfTextures? = null,
    /** View pixels per point when the widest page fits the width: the PDF pages' base pictures. */
    val fitScale: Float = 1f,
    /** The ground round the pages (the theme's paper-3), rgb in 0..1. */
    val ground: FloatArray = floatArrayOf(0.93f, 0.93f, 0.95f),
)
