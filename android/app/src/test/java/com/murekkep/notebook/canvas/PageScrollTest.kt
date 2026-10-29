package com.murekkep.notebook.canvas

import org.junit.Assert.assertEquals
import org.junit.Test

// The pages can always come out from under the floating pen bar (bugs-last-page-under-bar): a view
// 1000 tall and 800 wide, a margin of 24, the bar's room along one edge.
class PageScrollTest {
    @Test
    fun withoutABarTheLastPageStopsAMarginAboveTheBottom() {
        assertEquals(-1_024f..24f, PageScroll.verticalRange(1_000f, 2_000f, 24f, Clearance()))
    }

    @Test
    fun aBarAlongTheBottomLetsTheLastPageRiseAboveIt() {
        val range = PageScroll.verticalRange(1_000f, 2_000f, 24f, Clearance(bottom = 100f))
        assertEquals(-1_124f, range.start)
        assertEquals(24f, range.endInclusive)
    }

    @Test
    fun aBarAlongTheTopLetsTheFirstPageComeDownBelowIt() {
        assertEquals(-1_024f..98f, PageScroll.verticalRange(1_000f, 2_000f, 24f, Clearance(top = 74f)))
    }

    @Test
    fun aShortDocumentStaysAtTheTopBelowTheBar() {
        assertEquals(98f..98f, PageScroll.verticalRange(1_000f, 400f, 24f, Clearance(top = 74f)))
    }

    @Test
    fun aPageThatFitsStaysInTheMiddle() {
        assertEquals(100f, PageScroll.clampX(0f, 800f, 600f, Clearance()))
        assertEquals(100f, PageScroll.clampX(300f, 800f, 600f, Clearance()))
    }

    @Test
    fun aWidePagePansBetweenItsEdges() {
        assertEquals(0f, PageScroll.clampX(50f, 800f, 1_000f, Clearance()))
        assertEquals(-200f, PageScroll.clampX(-500f, 800f, 1_000f, Clearance()))
    }

    @Test
    fun aBarDownTheRightSideLetsThePagesRightEdgeComeOutFromUnderIt() {
        // Fitted with 24 on each side, the page's right 52 lie under a bar 76 wide: it may move left by 52.
        assertEquals(-28f, PageScroll.clampX(-100f, 800f, 752f, Clearance(right = 76f)))
        assertEquals(24f, PageScroll.clampX(100f, 800f, 752f, Clearance(right = 76f)))
        // Zoomed in, the right edge goes as far as the bar's left side.
        assertEquals(-276f, PageScroll.clampX(-500f, 800f, 1_000f, Clearance(right = 76f)))
        // A narrow page already clear of the bar stays in the middle.
        assertEquals(250f, PageScroll.clampX(0f, 800f, 300f, Clearance(right = 76f)))
    }

    @Test
    fun aJumpPutsThePageHalfAGapUnderTheTop() {
        // CanvasView.scrollToPage: the page's top 11 points (half the gap of 22) under the view's
        // top, at the zoom in force; under a bar along the top, below the bar.
        assertEquals(22f, PageScroll.pageOriginY(0f, 22f, 2f, Clearance()))
        val third = 2 * (841.89f + 22f)
        assertEquals(-(third - 11f) * 0.5f, PageScroll.pageOriginY(third, 22f, 0.5f, Clearance()), 1e-3f)
        assertEquals(74f + 11f - third, PageScroll.pageOriginY(third, 22f, 1f, Clearance(top = 74f)), 1e-3f)
        // The last page of a short note cannot rise past the end: the range keeps the canvas's limit.
        val range = PageScroll.verticalRange(1_000f, 1_705.78f, 28f, Clearance())
        assertEquals(range.start, PageScroll.pageOriginY(863.89f, 22f, 1f, Clearance()).coerceIn(range))
    }

    @Test
    fun besideABarDownTheRightSideAFittedPageStaysWhereTheCanvasPutsIt() {
        // The clamp does not centre it (the canvas puts a page it first fits in the middle itself).
        assertEquals(24f, PageScroll.clampX(24f, 800f, 752f, Clearance(right = 76f)))
        assertEquals(0f, PageScroll.clampX(0f, 800f, 752f, Clearance(right = 76f)))
    }
}
