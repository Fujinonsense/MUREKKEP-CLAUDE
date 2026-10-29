package com.murekkep.notebook.ui

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

// The pen bar's docking against the iPad's checks (tools/swiftcheck/main.swift, "pen bar dock: ..."):
// the bar goes to the top, the bottom or the right side, wherever the finger lets go of its grip;
// never to the left, which holds the drafting rail.
class PaletteEdgeTest {
    private fun nearest(x: Float, y: Float, current: PaletteEdge) = PaletteEdge.nearest(x, y, 1_200f, 1_000f, current)

    @Test
    fun letGoLowItGoesToTheBottom() {
        assertEquals(PaletteEdge.BOTTOM, nearest(600f, 900f, PaletteEdge.TOP))
    }

    @Test
    fun letGoOnTheRightItGoesRight() {
        assertEquals(PaletteEdge.TRAILING, nearest(1_150f, 500f, PaletteEdge.TOP))
    }

    @Test
    fun letGoHighItGoesToTheTop() {
        assertEquals(PaletteEdge.TOP, nearest(600f, 80f, PaletteEdge.BOTTOM))
    }

    @Test
    fun letGoOnTheLeftItGoesToTheNearerOfTopAndBottom() {
        assertEquals(PaletteEdge.TOP, nearest(30f, 300f, PaletteEdge.TRAILING))
        assertEquals(PaletteEdge.BOTTOM, nearest(30f, 700f, PaletteEdge.TOP))
    }

    @Test
    fun aTieKeepsTheEdgeItStandsOn() {
        assertEquals(PaletteEdge.BOTTOM, nearest(30f, 500f, PaletteEdge.BOTTOM))
    }

    @Test
    fun noLeftEdgeAndUnknownStoredEdgesAreTheBottom() {
        assertFalse(PaletteEdge.entries.any { it.raw.contains("leading") || it.raw.contains("left") })
        assertEquals(PaletteEdge.TRAILING, PaletteEdge.fromRaw("trailing"))
        assertEquals(PaletteEdge.BOTTOM, PaletteEdge.fromRaw("leading"))
        assertEquals(PaletteEdge.BOTTOM, PaletteEdge.fromRaw(null))
    }
}
