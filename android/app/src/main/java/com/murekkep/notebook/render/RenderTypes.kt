package com.murekkep.notebook.render

import com.murekkep.notebook.ink.Brush
import com.murekkep.notebook.ink.InkColor
import com.murekkep.notebook.ink.InkPoint
import com.murekkep.notebook.ink.PageInk
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min

/** Pages stacked from the top: page `i` covers (0, top(i)) to (pageWidth, top(i) + pageHeight) in
 *  document points (A4, as the iPad's notebooks; DocumentLayout there). */
class PageLayout(
    val pageCount: Int,
    val pageWidth: Float = 595.28f,
    val pageHeight: Float = 841.89f,
    val gap: Float = 24f,
) {
    fun top(i: Int) = i * (pageHeight + gap)

    val totalHeight: Float get() = if (pageCount == 0) 0f else pageCount * pageHeight + (pageCount - 1) * gap

    /** The pages any part of which lies between `minY` and `maxY` (document points). */
    fun pagesBetween(minY: Float, maxY: Float): List<Int> {
        if (pageCount == 0) return emptyList()
        val stride = pageHeight + gap
        val first = max(0, floor(minY / stride).toInt())
        val last = min(pageCount - 1, floor(maxY / stride).toInt())
        return (first..last).filter { top(it) <= maxY && top(it) + pageHeight >= minY }
    }

    /** The page under a document point, within `tolerance` points of its edges. */
    fun pageAt(x: Float, y: Float, tolerance: Float = 0f): Int? {
        if (x < -tolerance || x > pageWidth + tolerance) return null
        for (i in pagesBetween(y - tolerance, y + tolerance)) {
            if (y >= top(i) - tolerance && y <= top(i) + pageHeight + tolerance) return i
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
)
