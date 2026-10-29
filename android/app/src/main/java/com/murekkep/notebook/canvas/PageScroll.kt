package com.murekkep.notebook.canvas

import kotlin.math.max
import kotlin.math.min

// How far the pages may be moved (view pixels). The pen bar floats over the canvas along one edge,
// so the pages can always be brought out from under it: the first page's top below a bar along the
// top, the last page's bottom above a bar along the bottom, the page's right edge left of a bar down
// the right side (the iPad leaves a free margin of a third of the view round its pages instead).

/** The room the floating pen bar takes along the canvas's edges, in view pixels. */
data class Clearance(val top: Float = 0f, val bottom: Float = 0f, val right: Float = 0f)

internal object PageScroll {
    /** The document origin's y: from the last page's bottom `margin` above the bottom (and the bar
     *  along it) to the first page's top `margin` below the top (and the bar along it). */
    fun verticalRange(viewHeight: Float, contentHeight: Float, margin: Float, clear: Clearance): ClosedFloatingPointRange<Float> {
        val highest = margin + clear.top
        return min(highest, viewHeight - contentHeight - margin - clear.bottom)..highest
    }

    /** The document origin's x: a page that fits stays in the middle, one that does not pans between
     *  its left edge at the view's and its right edge clear of a bar down the right side. */
    fun clampX(x: Float, viewWidth: Float, contentWidth: Float, clear: Clearance): Float {
        val middle = (viewWidth - contentWidth) / 2
        return x.coerceIn(min(middle, viewWidth - clear.right - contentWidth), max(middle, 0f))
    }

    /** The document origin's y that puts a page whose top is `pageTop` (document points) half a
     *  `gap` under the view's top, and under a bar along it (CanvasView.scrollToPage: the page's top
     *  less half the gap at the top of the scroll view). The caller keeps it in [verticalRange]. */
    fun pageOriginY(pageTop: Float, gap: Float, zoom: Float, clear: Clearance): Float =
        clear.top + (gap / 2 - pageTop) * zoom
}
