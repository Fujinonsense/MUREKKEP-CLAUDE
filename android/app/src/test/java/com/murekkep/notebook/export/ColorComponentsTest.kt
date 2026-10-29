package com.murekkep.notebook.export

import com.murekkep.notebook.ink.InkColor
import org.junit.Assert.assertEquals
import org.junit.Test

// UIColorComponents of FlatInk.swift against hand-computed values: the rainbow's hue wheel.
class ColorComponentsTest {
    private fun assertHsv(h: Float, s: Float, v: Float, actual: Hsv) {
        assertEquals("h", h, actual.h, 1e-5f)
        assertEquals("s", s, actual.s, 1e-5f)
        assertEquals("v", v, actual.v, 1e-5f)
    }

    @Test
    fun thePrimariesSitAtThirdsOfTheHueWheel() {
        assertHsv(0f, 1f, 1f, ColorComponents.hsv(1f, 0f, 0f))
        assertHsv(1f / 3f, 1f, 1f, ColorComponents.hsv(0f, 1f, 0f))
        assertHsv(2f / 3f, 1f, 1f, ColorComponents.hsv(0f, 0f, 1f))
        assertHsv(0.5f, 1f, 1f, ColorComponents.hsv(0f, 1f, 1f))
    }

    @Test
    fun greysHaveNoHueAndNoSaturation() {
        assertHsv(0f, 0f, 0.5f, ColorComponents.hsv(0.5f, 0.5f, 0.5f))
        assertHsv(0f, 0f, 0f, ColorComponents.hsv(0f, 0f, 0f))
        assertHsv(0f, 0f, 1f, ColorComponents.hsv(1f, 1f, 1f))
    }

    @Test
    fun aHueBelowRedWrapsToTheTopOfTheWheel() {
        // Red with half blue: (g - b) / d = -0.5, truncated by 6, over 6, plus one turn.
        assertHsv(11f / 12f, 1f, 1f, ColorComponents.hsv(1f, 0f, 0.5f))
        // Orange, the rainbow pen's fourth colour: hue 28.7 of 360.
        val orange = ColorComponents.hsv(1f, 122f / 255f, 0f)
        assertEquals(122f / 255f / 6f, orange.h, 1e-5f)
        assertEquals(1f, orange.s, 1e-5f)
        assertEquals(1f, orange.v, 1e-5f)
    }

    private fun assertRgb(r: Float, g: Float, b: Float, actual: InkColor) {
        assertEquals("r", r, actual.r, 1e-5f)
        assertEquals("g", g, actual.g, 1e-5f)
        assertEquals("b", b, actual.b, 1e-5f)
        assertEquals("a", 1f, actual.a, 0f)
    }

    @Test
    fun rgbOfAHueGivesThePureColourBack() {
        assertRgb(1f, 0f, 0f, ColorComponents.rgb(0f, 1f, 1f))
        assertRgb(0f, 1f, 0f, ColorComponents.rgb(1f / 3f, 1f, 1f))
        assertRgb(0f, 1f, 1f, ColorComponents.rgb(0.5f, 1f, 1f))
        assertRgb(0.5f, 0.5f, 0.5f, ColorComponents.rgb(0.7f, 0f, 0.5f))
        // The rainbow pen never goes paler or darker than this.
        assertRgb(0.35f, 0.2625f, 0.2625f, ColorComponents.rgb(0f, 0.25f, 0.35f))
    }

    @Test
    fun hsvAndRgbAreEachOthersInverse() {
        for ((r, g, b) in listOf(Triple(0.2f, 0.6f, 0.9f), Triple(0.95f, 0.3f, 0.1f), Triple(0.5f, 0.9f, 0.2f), Triple(0.7f, 0.1f, 0.6f))) {
            val hsv = ColorComponents.hsv(r, g, b)
            val back = ColorComponents.rgb(hsv.h, hsv.s, hsv.v)
            assertEquals(r, back.r, 1e-4f)
            assertEquals(g, back.g, 1e-4f)
            assertEquals(b, back.b, 1e-4f)
        }
    }
}
