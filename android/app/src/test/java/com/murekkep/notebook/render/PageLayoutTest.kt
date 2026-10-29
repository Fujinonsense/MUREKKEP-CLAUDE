package com.murekkep.notebook.render

import org.junit.Assert.assertEquals
import org.junit.Test

// The pages' margin and gap as the iPad's DocumentLayout keeps them (R2-08): 28 page points round
// the pages and 22 between them, so a fitted page leaves the same paper-3 ground round it.
class PageLayoutTest {
    @Test
    fun pagesStand22PointsApart() {
        val layout = PageLayout(3)
        assertEquals(0f, layout.top(0))
        assertEquals(841.89f + 22f, layout.top(1), 1e-3f)
        assertEquals(2 * (841.89f + 22f), layout.top(2), 1e-3f)
        assertEquals(3 * 841.89f + 2 * 22f, layout.totalHeight, 1e-3f)
    }

    @Test
    fun aFittedPageKeepsTwentyEightPointsAtItsSides() {
        // CanvasView.fitZoom on iPad: the width over the widest page and its two margins. On a
        // 1280 dp canvas that is 1.965 dp a point, 55 dp of ground at either side.
        val fit = 1_280f / (PageSize.A4.width + 2 * PageLayout.MARGIN)
        assertEquals(1.965f, fit, 1e-3f)
        assertEquals(55.0f, PageLayout.MARGIN * fit, 0.1f)
        assertEquals(1_280f, (PageSize.A4.width + 2 * PageLayout.MARGIN) * fit, 1e-2f)
    }
}
