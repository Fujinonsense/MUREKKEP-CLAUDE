package com.murekkep.notebook.ui

import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import com.murekkep.notebook.ink.Brush
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.hypot

// The pure parts of the pen artwork (ToolArt.kt) against the numbers in Murekkep.swiftpm/ToolPalette.swift:
// which body each pen gets, the barrel and metal colors, the gloss stops, the star, trapezoid, petal and
// nib geometry, and the two conversions (the iPad's shadow radius to Android's blur radius, SwiftUI's
// spring response to Compose's stiffness).
class ToolArtTest {
    private val eps = 1e-4f

    /** Compose keeps sRGB colors in 8 bits a channel, so a color's numbers come back rounded to 1/255. */
    private val tint = 1f / 255f
    private val ink = Color(0.2f, 0.4f, 0.6f)

    private fun assertOffset(expected: Offset, actual: Offset) {
        assertEquals(expected.x, actual.x, eps)
        assertEquals(expected.y, actual.y, eps)
    }

    @Test
    fun eachPenGetsTheiPadsBody() {
        assertEquals(NibStyle.CHISEL, Brush.HIGHLIGHTER.nibStyle)
        assertEquals(NibStyle.FLAT, Brush.CALLIGRAPHY.nibStyle)
        assertEquals(NibStyle.FLAT, Brush.FOUNTAIN.nibStyle)
        for (brush in listOf(Brush.WATERCOLOR, Brush.WAVE, Brush.SEA, Brush.IMPASTO, Brush.BLOOM)) {
            assertEquals(brush.name, NibStyle.BRUSH, brush.nibStyle)
        }
        assertEquals(NibStyle.LEAF, Brush.GRASS.nibStyle)
        val cones = Brush.entries.filter { it.nibStyle == NibStyle.CONE }
        assertEquals(14, cones.size)
        assertTrue(Brush.PENCIL in cones) // drawn as the pencil before the nib style is asked
        assertTrue(Brush.entries.none { it.nibStyle == NibStyle.ERASER })
    }

    @Test
    fun everyBarrelIsAGradientOfAtLeastTwoColors() {
        for (brush in Brush.entries) {
            assertTrue(brush.name, brush.barrel(ink).size >= 2)
        }
        assertEquals(6, Brush.RAINBOW.barrel(ink).size)
        assertEquals(listOf(Color(0.97f, 0.97f, 0.97f), Color(0.84f, 0.84f, 0.84f)), Brush.PEN.barrel(ink))
    }

    @Test
    fun theSeeThroughBarrelsAreTheInkFadedThenTheInk() {
        val jelly = Brush.JELLY.barrel(ink)
        assertEquals(0.55f, jelly[0].alpha, tint)
        assertEquals(ink.red, jelly[0].red, tint)
        assertEquals(ink, jelly[1])
        val marker = Brush.HIGHLIGHTER.barrel(ink)
        assertEquals(0.75f, marker[0].alpha, tint)
        assertEquals(ink, marker[1])
        // A half-transparent ink fades further, as SwiftUI's opacity() scales the color's own.
        assertEquals(0.5f * 0.55f, Brush.JELLY.barrel(ink.copy(alpha = 0.5f))[0].alpha, tint)
    }

    @Test
    fun goldTrimOnTheFiveDressPens() {
        val gold = Brush.entries.filter { it.trimIsGold }.toSet()
        assertEquals(setOf(Brush.FOUNTAIN, Brush.GOLD, Brush.GALAXY, Brush.LAVA, Brush.PEARL), gold)
    }

    @Test
    fun theGlossRunsDarkEdgeHighlightDarkEdge() {
        val stops = ToolArt.glossStops(0.55f)
        assertEquals(listOf(0f, 0.12f, 0.30f, 0.50f, 0.68f, 1f), stops.map { it.first })
        val alphas = stops.map { it.second.alpha }
        assertEquals(0.22f, alphas[0], tint)
        assertEquals(0f, alphas[1], tint)
        assertEquals(0.55f, alphas[2], tint)
        assertEquals(0f, alphas[3], tint)
        assertEquals(0f, alphas[4], tint)
        assertEquals(0.32f, alphas[5], tint)
        // The edges are black, the highlight white; the clear stops keep their color so the gradient blends like the iPad's.
        assertEquals(0f, stops[0].second.red, tint)
        assertEquals(1f, stops[1].second.red, tint)
        assertEquals(1f, stops[2].second.red, tint)
        assertEquals(0f, stops[4].second.red, tint)
        assertEquals(0.3f, ToolArt.glossStops(0.3f)[2].second.alpha, tint)
    }

    @Test
    fun metalHasFiveBandsBrightestSecond() {
        for (gold in listOf(true, false)) {
            val bands = ToolArt.metal(gold)
            assertEquals(5, bands.size)
            val brightest = bands.indices.maxBy { bands[it].red + bands[it].green + bands[it].blue }
            assertEquals(1, brightest)
        }
        assertTrue(ToolArt.metal(false).all { it.red == it.green && it.green == it.blue })
        assertTrue(ToolArt.metal(true).all { it.red > it.blue })
    }

    @Test
    fun theStarHasTenPointsTheFirstStraightUp() {
        val c = Offset(15f, 50f)
        val points = ToolArt.starPoints(c, 2.6f)
        assertEquals(10, points.size)
        assertOffset(Offset(15f, 47.4f), points[0])
        points.forEachIndexed { i, p ->
            val r = hypot(p.x - c.x, p.y - c.y)
            assertEquals(if (i % 2 == 0) 2.6f else 2.6f * 0.45f, r, eps)
        }
    }

    @Test
    fun aTrapezoidStandsOnItsBottomCenteredOnFifteen() {
        val corners = ToolArt.trapezoidCorners(top = 24f, topHalf = 8f, bottom = 32.5f, bottomHalf = 10.2f)
        assertEquals(4, corners.size)
        assertOffset(Offset(4.8f, 32.5f), corners[0])
        assertOffset(Offset(7f, 24f), corners[1])
        assertOffset(Offset(23f, 24f), corners[2])
        assertOffset(Offset(25.2f, 32.5f), corners[3])
        assertOffset(Offset(8f, 9f), ToolArt.trapezoidCorners(9f, 2f, 20f, 5f, cx = 10f)[1])
    }

    @Test
    fun fivePetalsRoundTheFlowerTheFirstStraightUp() {
        val flower = Offset(15.5f, 4.6f)
        val petals = ToolArt.petals(flower)
        assertEquals(5, petals.size)
        for (petal in petals) {
            assertEquals(3.4f, petal.width, eps)
            assertEquals(3.4f, petal.height, eps)
            assertEquals(2.2f, hypot(petal.center.x - flower.x, petal.center.y - flower.y), eps)
        }
        assertOffset(Offset(15.5f, 2.4f), petals[0].center)
    }

    @Test
    fun theNibTipIsADotOnTheFountainPenAndTheWholeEdgeOnTheCalligraphyNib() {
        val dot = ToolArt.nibTip(broad = false)
        assertEquals(1.8f, dot.width, eps)
        assertEquals(1.0f, dot.top, eps)
        val edge = ToolArt.nibTip(broad = true)
        assertEquals(7.2f, edge.width, eps)
        assertEquals(2.6f, edge.top, eps)
        for (tip in listOf(dot, edge)) {
            assertEquals(15f, tip.center.x, eps)
            assertEquals(1.3f, tip.height, eps)
        }
    }

    @Test
    fun theBladesStandAcrossTheFerruleLeaningOutward() {
        val blades = ToolArt.blades
        assertEquals(5, blades.size)
        assertEquals(listOf(9f, 11.5f, 15f, 18.5f, 21f), blades.map { it.base })
        assertTrue(blades.first().tip.x < blades.first().base)
        assertTrue(blades.last().tip.x > blades.last().base)
        assertEquals(4.5f, blades.minOf { it.tip.y }, eps) // the middle blade reaches highest, under the flower
    }

    @Test
    fun blurRadiusUndoesAndroidsSigmaFormula() {
        for (sigma in listOf(3.6f, 7.5f, 15f)) {
            val radius = blurRadiusForSigma(sigma)
            assertEquals(sigma, 0.57735f * radius + 0.5f, 1e-3f)
        }
        assertEquals(0f, blurRadiusForSigma(0.4f), eps)
        assertEquals(0f, blurRadiusForSigma(0f), eps)
    }

    @Test
    fun springStiffnessFromTheiPadsResponse() {
        // response 0.32 s: an undamped period of 0.32 s is a stiffness of (2 pi / 0.32)^2 on unit mass.
        assertEquals(385.5f, springStiffness(0.32f), 0.1f)
        assertEquals(1f, Math.PI.toFloat() * 2f / kotlin.math.sqrt(springStiffness(1f)), 1e-3f)
    }
}
