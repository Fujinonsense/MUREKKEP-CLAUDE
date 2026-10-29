package com.murekkep.notebook.ui

import com.murekkep.notebook.data.PaperStyle
import com.murekkep.notebook.render.PageSize
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.ConscryptMode

// The page navigator's pictures: the iPad's size (the width given, the height the page's at that
// scale, rounded); which pictures stay when they take more than their budget: the ones drawn first
// go, the newest always stays, a page drawn again counts once; and a picture narrower than its tile
// is drawn again as wide as the tile, while a wider one stays.
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
// Conscrypt's native library is looked up by a name lower-cased in the machine's language, which a
// Turkish JVM spells "wındows": the pictures need no TLS, so the test runs without it.
@ConscryptMode(ConscryptMode.Mode.OFF)
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

    @Test
    fun aPictureNarrowerThanItsTileIsDrawnAgainAsWideAsIt() {
        val pictures = PageThumbnails(pdfFile = null, paper = PaperStyle.LINED)
        try {
            runBlocking {
                pictures.load(0, emptyList(), PageSize.A4, 120)
                assertEquals(120, pictures.image(0)?.width)
                assertEquals(170, pictures.image(0)?.height)
                // The tile grew (a wider window): drawn again as wide.
                pictures.load(0, emptyList(), PageSize.A4, 160)
                assertEquals(160, pictures.image(0)?.width)
                // A narrower tile keeps the wider picture.
                pictures.load(0, emptyList(), PageSize.A4, 120)
                assertEquals(160, pictures.image(0)?.width)
            }
        } finally {
            pictures.close()
        }
    }
}
