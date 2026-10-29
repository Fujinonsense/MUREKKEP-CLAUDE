package com.murekkep.notebook.ui

import com.murekkep.notebook.ink.Brush
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

// The pen panel's shelves against the iPad's checks (tools/swiftcheck/main.swift, "pen shelves: ..."):
// each pen on exactly one shelf, the 3D inks together, the favourites in the panel's order.
class PenShelfTest {
    @Test
    fun everyPenOnce() {
        val shelved = PenShelf.entries.filter { it != PenShelf.FAVORITES }.flatMap { it.brushes(emptyList()) }
        assertEquals(Brush.entries.size, shelved.size)
        assertEquals(Brush.entries.toSet(), shelved.toSet())
    }

    @Test
    fun theThreeDInksHaveTheirOwnShelf() {
        assertTrue(PenShelf.THREE_D.brushes(emptyList()).all { it.isPremium })
        val others = PenShelf.entries.filter { it != PenShelf.THREE_D && it != PenShelf.FAVORITES }
        assertTrue(others.all { shelf -> shelf.brushes(emptyList()).none { it.isPremium } })
    }

    @Test
    fun theNatureShelfHoldsExactlyTheTrialInks() {
        assertTrue(PenShelf.NATURE.brushes(emptyList()).all { it.isTrialInk })
        assertTrue(Brush.entries.filter { it.isTrialInk }.all { PenShelf.shelf(it) == PenShelf.NATURE })
    }

    @Test
    fun favouritesInThePanelsOrder() {
        assertEquals(listOf(Brush.PEN, Brush.LAVA), PenShelf.FAVORITES.brushes(listOf(Brush.LAVA, Brush.PEN)))
    }

    @Test
    fun aPensOwnShelf() {
        assertEquals(PenShelf.THREE_D, PenShelf.shelf(Brush.GOLD))
        assertEquals(PenShelf.WRITING, PenShelf.shelf(Brush.PENCIL))
        assertEquals(PenShelf.NATURE, PenShelf.shelf(Brush.GRASS))
        assertEquals(PenShelf.PAINT, PenShelf.shelf(Brush.NEON))
    }

    @Test
    fun whichShelfThePanelOpensOn() {
        assertEquals(PenShelf.PAINT, PenShelf.opening("", emptyList(), Brush.NEON))
        assertEquals(PenShelf.FAVORITES, PenShelf.opening("", listOf(Brush.PEN), Brush.NEON))
        assertEquals(PenShelf.NATURE, PenShelf.opening("nature", listOf(Brush.PEN), Brush.NEON))
        assertEquals(PenShelf.THREE_D, PenShelf.opening("favorites", emptyList(), Brush.LAVA))
        assertEquals(PenShelf.WRITING, PenShelf.opening(null, emptyList(), Brush.PEN))
    }
}
