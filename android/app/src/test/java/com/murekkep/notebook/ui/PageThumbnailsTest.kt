package com.murekkep.notebook.ui

import org.junit.Assert.assertEquals
import org.junit.Test

// The page navigator's pictures: the iPad's size (the width given, the height the page's at that
// scale, rounded), and which pictures stay when they take more than their budget: the ones drawn
// first go, the newest always stays, a page drawn again counts once.
class PageThumbnailsTest {
    @Test
    fun aPictureHasThePagesShape() {
        assertEquals(240 to 339, PageThumbnails.pixelSize(595.28f, 841.89f, 240))
        assertEquals(240 to 170, PageThumbnails.pixelSize(842f, 595f, 240))
        assertEquals(210 to 297, PageThumbnails.pixelSize(595.28f, 841.89f, 210))
        // A page of no size still gets a pixel.
        assertEquals(240 to 1, PageThumbnails.pixelSize(0f, 0f, 240))
    }

    @Test
    fun theFirstPicturesDrawnGoWhenTheyTakeTooMuch() {
        val budget = ThumbnailBudget(100)
        assertEquals(emptyList<Int>(), budget.add(0, 40))
        assertEquals(emptyList<Int>(), budget.add(1, 40))
        assertEquals(listOf(0), budget.add(2, 40))
        // A page drawn again replaces its own picture.
        assertEquals(emptyList<Int>(), budget.add(2, 40))
        // One too big for the budget stays alone.
        assertEquals(listOf(1, 2), budget.add(3, 200))
        assertEquals(emptyList<Int>(), budget.add(3, 10))
        assertEquals(emptyList<Int>(), budget.add(4, 90))
        assertEquals(listOf(3), budget.add(5, 10))
    }
}
