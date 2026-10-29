package com.murekkep.notebook.ui

import com.murekkep.notebook.ink.Brush
import com.murekkep.notebook.ink.InkColor
import org.junit.Assert.assertEquals
import org.junit.Test

// The custom colour's picker works in hue, saturation and brightness; a colour must come back the
// same from it, so a pen's own colours still show as picked after the picker touched them.
class HsvTest {
    @Test
    fun everyPensColoursComeBackTheSame() {
        for (brush in Brush.entries) for (c in brush.palette) {
            assertEquals("$brush $c", c, Hsv.of(c).toInk())
        }
    }

    @Test
    fun theCornersOfTheField() {
        assertEquals(InkColor(1f, 1f, 1f), Hsv(200f, 0f, 1f, 1f).toInk())
        assertEquals(InkColor(0f, 0f, 0f), Hsv(200f, 1f, 0f, 1f).toInk())
        assertEquals(InkColor(1f, 0f, 0f), Hsv(0f, 1f, 1f, 1f).toInk())
        assertEquals(InkColor(1f, 0f, 0f), Hsv(360f, 1f, 1f, 1f).toInk())
        assertEquals(InkColor(0f, 0f, 1f), Hsv(240f, 1f, 1f, 1f).toInk())
    }

    @Test
    fun aGreyKeepsTheHueThePickerHad() {
        val grey = InkColor.hex(0x808080)
        assertEquals(212f, Hsv.of(grey, hueIfGrey = 212f).h, 0f)
        assertEquals(0f, Hsv.of(grey, hueIfGrey = 212f).s, 0f)
    }

    @Test
    fun opacityOnlyWhereThePenTakesIt() {
        val wash = Hsv(30f, 0.5f, 0.9f, 0.4f)
        assertEquals(0.4f, wash.toInk(opacity = true).a, 1f / 255f)
        assertEquals(1f, wash.toInk(opacity = false).a, 0f)
    }

    @Test
    fun aPickedColourIsKeptInWholeBytes() {
        val c = Hsv(123.4f, 0.37f, 0.61f, 1f).toInk()
        for (channel in listOf(c.r, c.g, c.b)) {
            assertEquals(channel, Math.round(channel * 255f) / 255f, 0f)
        }
    }
}
