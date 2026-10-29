package com.murekkep.notebook.export

import com.murekkep.notebook.ink.InkColor
import com.murekkep.notebook.ink.InkPoint
import com.murekkep.notebook.ink.Vec3
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.hypot

// The numbers of FlatInk.swift, checked by hand: the plain line's width, the runs a polyline is
// stroked in, the pearls and sparkles along a line, the glow's blur and the colours.
class FlatInkGeometryTest {
    private fun line(count: Int, r: Float, spacing: Float = 10f) =
        (0 until count).map { InkPoint(it * spacing, 0f, r, 0.5f) }

    @Test
    fun thePlainLineIsAboutHalfThePenNeverHairlineNorFat() {
        assertEquals(1.4f, FlatInkGeometry.plainWidth(2.2f), 1e-6f)
        assertEquals(2.2f, FlatInkGeometry.plainWidth(4f), 1e-6f)
        assertEquals(3.0f, FlatInkGeometry.plainWidth(16f), 1e-6f)
    }

    @Test
    fun lighteningMovesTowardsWhiteAndKeepsTheAlpha() {
        val c = FlatInkGeometry.lighten(InkColor(0f, 0.5f, 1f, 0.4f), 0.5f)
        assertEquals(0.5f, c.r, 1e-6f)
        assertEquals(0.75f, c.g, 1e-6f)
        assertEquals(1f, c.b, 1e-6f)
        assertEquals(0.4f, c.a, 1e-6f)
        assertEquals(InkColor(0.2f, 0.3f, 0.4f, 1f), FlatInkGeometry.lighten(InkColor(0.2f, 0.3f, 0.4f, 1f), 0f))
    }

    @Test
    fun theArgbIntIsClampedAndRounded() {
        assertEquals(-1, FlatInkGeometry.argb(1f, 1f, 1f, 1f))
        assertEquals(0xFF000000.toInt(), FlatInkGeometry.argb(0f, 0f, 0f, 1f))
        assertEquals(0x80FF0000.toInt(), FlatInkGeometry.argb(2f, -1f, 0f, 0.5f))
        assertEquals(0x00000000, FlatInkGeometry.argb(Float.NaN, 0f, 0f, 0f))
        assertEquals(0xFF1C1C1E.toInt(), FlatInkGeometry.argb(InkColor.hex(0x1C1C1E)))
        assertEquals(0x40FF8000.toInt(), FlatInkGeometry.argb(Vec3(1f, 0.5f, 0f), 0.25f))
    }

    @Test
    fun runsOfSimilarWidthShareTheirEndsAndHoldAtMost49Points() {
        val runs = FlatInkGeometry.polylineRuns(line(100, 3f))
        assertEquals(listOf(PolylineRun(0, 48, 6f), PolylineRun(48, 96, 6f), PolylineRun(96, 99, 6f)), runs)
    }

    @Test
    fun aJumpInWidthStartsANewRunAtItsMeanDiameter() {
        val pts = (0 until 20).map { InkPoint(it * 10f, 0f, if (it < 10) 2f else 3f, 0.5f) }
        assertEquals(listOf(PolylineRun(0, 9, 4f), PolylineRun(9, 10, 5f), PolylineRun(10, 19, 6f)), FlatInkGeometry.polylineRuns(pts))
        assertTrue(FlatInkGeometry.polylineRuns(line(1, 2f)).isEmpty())
        assertTrue(FlatInkGeometry.polylineRuns(emptyList()).isEmpty())
    }

    @Test
    fun pearlsSitEveryTwoRadiiAlongTheLineFromItsStartToItsEnd() {
        val beads = FlatInkGeometry.along(listOf(InkPoint(0f, 0f, 5f, 0f), InkPoint(100f, 0f, 5f, 0f))) { it * 2f }
        assertEquals(11, beads.size)
        for ((k, bead) in beads.withIndex()) {
            assertEquals(k * 10f, bead.x, 1e-3f)
        }
        assertTrue(beads.all { it.y == 0f && it.r == 5f })
        assertEquals(listOf(Spot(3f, 4f, 2f)), FlatInkGeometry.along(listOf(InkPoint(3f, 4f, 2f, 0f))) { it * 2f })
        assertTrue(FlatInkGeometry.along(emptyList()) { it * 2f }.isEmpty())
    }

    @Test
    fun theBeadsRadiusFollowsTheLineAndNeverPacksCloserThanAPoint() {
        val beads = FlatInkGeometry.along(listOf(InkPoint(0f, 0f, 0f, 0f), InkPoint(0f, 4f, 0f, 0f))) { it * 2f }
        assertEquals(listOf(0f, 1f, 2f, 3f, 4f), beads.map { it.y })
        // The radius grows 2 to 6 over 40 points: beads at 0 (r 2, spacing 4), 4 (r 2.4, spacing 4.8), 8.8.
        val growing = FlatInkGeometry.along(listOf(InkPoint(0f, 0f, 2f, 0f), InkPoint(40f, 0f, 6f, 0f))) { it * 2f }
        assertEquals(2f, growing.first().r, 1e-6f)
        assertEquals(0f, growing[0].x, 1e-4f)
        assertEquals(4f, growing[1].x, 1e-4f)
        assertEquals(8.8f, growing[2].x, 1e-4f)
    }

    @Test
    fun everyOtherPointRollsForASparkleAndTheHighRollsGetOne() {
        // Index times 2654435761, low 16 bits, over 65535: 2 -> 0.9507 ... 18 -> 0.5564 sparkle,
        // 0 -> 0 and 20 -> 0.5071 do not, odd indices never roll.
        val sparkles = FlatInkGeometry.sparkles(line(21, 5f))
        assertEquals(9, sparkles.size)
        assertEquals(20f, sparkles[0].x, 5f * 0.6f)
        assertTrue(sparkles.none { hypot(it.x - 0f, it.y) <= 3f || hypot(it.x - 200f, it.y) <= 3f })
        val h2 = 62306f / 65535f
        assertEquals(5f * 0.6f * h2, hypot(sparkles[0].x - 20f, sparkles[0].y), 1e-3f)
        assertEquals(0.7f, sparkles[0].r, 1e-6f)
        assertTrue(FlatInkGeometry.sparkles(line(21, 1f)).all { it.r == 0.35f })
        assertTrue(FlatInkGeometry.sparkles(line(1, 5f)).isEmpty())
    }

    @Test
    fun theShadowRadiusGivesSkiaTheIPadsBlurAsItsSigma() {
        val radius = FlatInkGeometry.shadowRadius(8.8f)
        assertEquals(8.8f, 0.57735f * radius + 0.5f, 1e-4f)
        assertEquals(0.25f, FlatInkGeometry.shadowRadius(0.1f), 0f)
    }

    @Test
    fun theRainbowCyclesOnceEvery220Points() {
        assertEquals(0.1f, FlatInkGeometry.rainbowHue(0.9f, 44f), 1e-5f)
        assertEquals(0.5f, FlatInkGeometry.rainbowHue(0.5f, 220f), 1e-5f)
        assertEquals(0f, FlatInkGeometry.rainbowHue(0f, 0f), 0f)
    }

    @Test
    fun theGlassFlowerIsATouchWiderThanTallAndAlwaysTheSame() {
        for (spin in listOf(0f, 1.3f, 4.9f, 6.28f)) {
            for (radius in listOf(1.6f, 3.2f, 7.5f)) {
                val shape = FlatInkGeometry.glassFlowerShape(spin, radius)
                assertTrue(shape.aspect >= 0.78f && shape.aspect <= 0.95f)
                assertTrue(shape.seed >= 0f && shape.seed < 1f)
                assertEquals(shape, FlatInkGeometry.glassFlowerShape(spin, radius))
            }
        }
        val seed = (1.3f * 0.15915494f + 3.2f * 0.731f) % 1f
        assertEquals(0.78f + 0.17f * ((seed * 7.13f + 0.37f) % 1f), FlatInkGeometry.glassFlowerShape(1.3f, 3.2f).aspect, 1e-6f)
    }
}
