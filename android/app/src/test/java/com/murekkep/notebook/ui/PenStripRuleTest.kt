package com.murekkep.notebook.ui

import com.murekkep.notebook.ink.Brush
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

// The pen bar's rule against the iPad's checks (tools/swiftcheck/main.swift, "pen bar: ..."):
// favourites first, then the pens used last, five in all, two recent pens beside many favourites.
class PenStripRuleTest {
    private val order = listOf("pen", "pencil", "fountain", "marker", "highlighter", "lava", "gold", "brush")

    @Test
    fun withoutFavouritesTheFiveUsedLastInThePanelsOrder() {
        val (favorites, recent) = PenStripRule.pens(emptyList(), listOf("gold", "pen", "brush", "pencil", "lava", "marker"), order)
        assertTrue(favorites.isEmpty())
        assertEquals(listOf("pen", "pencil", "lava", "gold", "brush"), recent)
    }

    @Test
    fun favouritesStayAndRecentPensFillUpToFive() {
        val (favorites, recent) = PenStripRule.pens(listOf("gold", "pencil"), listOf("gold", "pen", "brush", "pencil", "lava"), order)
        assertEquals(listOf("pencil", "gold"), favorites)
        assertEquals(listOf("pen", "lava", "brush"), recent)
    }

    @Test
    fun twoRecentPensStayBesideManyFavourites() {
        val (favorites, recent) = PenStripRule.pens(
            listOf("pen", "pencil", "fountain", "marker", "highlighter", "lava"), listOf("brush", "gold", "pen"), order,
        )
        assertEquals(6, favorites.size)
        assertEquals(listOf("gold", "brush"), recent)
    }

    @Test
    fun starringAndUnstarring() {
        assertEquals(listOf("pen", "gold"), PenStripRule.toggled("gold", listOf("pen")))
        assertEquals(listOf("gold"), PenStripRule.toggled("pen", listOf("pen", "gold")))
    }

    @Test
    fun aPickedPenMovesToTheFrontOfTheRecentList() {
        assertEquals(listOf("lava", "pen", "pencil"), PenStripRule.remembered("lava", listOf("pen", "pencil")))
        assertEquals(listOf("pencil", "pen"), PenStripRule.remembered("pencil", listOf("pen", "pencil")))
        val same = listOf("pen", "pencil")
        assertTrue(same === PenStripRule.remembered("pen", same))
        val six = PenStripRule.remembered("g", listOf("a", "b", "c", "d", "e", "f", "x"))
        assertEquals(listOf("g", "a", "b", "c", "d", "e"), six)
    }

    @Test
    fun aNewUserStartsWithTheWritingPens() {
        assertEquals(listOf(Brush.PEN, Brush.PENCIL, Brush.FOUNTAIN, Brush.HIGHLIGHTER), PenStripRule.defaultRecent)
        val (_, recent) = PenStripRule.pens(emptyList(), PenStripRule.defaultRecent, Brush.paletteOrder)
        assertEquals(PenStripRule.defaultRecent, recent)
    }
}
