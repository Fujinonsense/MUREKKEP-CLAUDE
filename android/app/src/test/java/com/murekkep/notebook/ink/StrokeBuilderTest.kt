package com.murekkep.notebook.ink

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs
import kotlin.math.pow
import kotlin.math.sqrt

// StrokeBuilder has no check in tools/swiftcheck; these are the iPad numbers worked out by hand.
class StrokeBuilderTest {
    private val black = InkColor(0f, 0f, 0f)
    private val upright = 1.5707964f

    private fun sample(x: Float, y: Float, t: Double, force: Float = 1f, altitude: Float = upright, isPencil: Boolean = true) =
        InputSample(x, y, force, t, altitude = altitude, isPencil = isPencil)

    private fun builder(brush: Brush) = StrokeBuilder(brush, black, brush.defaultWidth, 0.5f)

    /** `count` samples every `step` points along +x (or +y), `dt` seconds apart. */
    private fun line(b: StrokeBuilder, count: Int, step: Float, dt: Double, vertical: Boolean = false, force: Float = 1f) {
        for (i in 0 until count) {
            val d = i * step
            b.add(sample(if (vertical) 0f else d, if (vertical) d else 0f, i * dt, force))
        }
    }

    @Test
    fun theRadiusFollowsTheSquareRootOfTheForce() {
        val pen = builder(Brush.PEN) // width 2.2, sensitivity 0.45
        assertEquals(1.1f, pen.radius(1f), 1e-6f)
        // No force reported reads as the average press.
        assertEquals(1.1f, pen.radius(0f), 1e-6f)
        // Clamped to 0.05...3 before the square root.
        assertEquals(1.1f * (0.55f + 0.45f * sqrt(3f)), pen.radius(4f), 1e-5f)
        assertEquals(1.1f * (0.55f + 0.45f * sqrt(0.05f)), pen.radius(0.01f), 1e-5f)
        // The highlighter ignores pressure.
        val marker = builder(Brush.HIGHLIGHTER)
        assertEquals(8f, marker.radius(3f), 0f)
        assertEquals(8f, marker.radius(0.1f), 0f)
    }

    @Test
    fun aTapIsOneDot() {
        val b = builder(Brush.PEN)
        b.add(sample(10f, 20f, 0.0))
        assertEquals(1, b.points.size)
        val points = b.finish()
        assertEquals(listOf(InkPoint(10f, 20f, 1.1f, 1f)), points)
    }

    @Test
    fun nothingDrawnGivesNoPoints() {
        val b = builder(Brush.PEN)
        assertTrue(b.finish().isEmpty())
        b.add(sample(Float.NaN, 0f, 0.0))
        b.add(sample(0f, Float.POSITIVE_INFINITY, 0.0))
        assertTrue(b.points.isEmpty())
        assertTrue(b.preview(emptyList()).isEmpty())
    }

    @Test
    fun aLineIsSmoothedDecimatedAndEndsAtThePen() {
        val b = builder(Brush.PEN)
        // 241 samples a quarter point apart: about every third one is far enough (0.6) to be kept.
        line(b, 241, 0.25f, 1.0 / 240)
        val points = b.finish()
        assertTrue(points.size > 10)
        assertTrue(points.size < 120)
        assertEquals(0f, points.first().x, 0f)
        assertEquals(0f, points.first().y, 0f)
        // The smoothed line lags the pen; the lift adds the pen's own position.
        assertEquals(60f, points.last().x, 0f)
        assertTrue(points.all { it.y == 0f && it.r == 1.1f && it.ink > 0f && it.ink <= 1f })
        for (i in 1 until points.size) {
            assertTrue(points[i].x > points[i - 1].x)
        }
        // Committed points keep the spacing of max(0.6, 0.4 r).
        for (i in 1 until points.size - 1) {
            assertTrue(points[i].x - points[i - 1].x >= 0.6f - 1e-5f)
        }
    }

    @Test
    fun slowStrokesPoolMoreInkThanFastOnes() {
        val slow = builder(Brush.WET)
        line(slow, 41, 1f, 1.0 / 24)
        val fast = builder(Brush.WET)
        line(fast, 41, 4f, 1.0 / 480)
        val slowInk = slow.points[20].ink
        val fastInk = fast.points[20].ink
        assertTrue("slow $slowInk, fast $fastInk", slowInk > 0.9f && fastInk < 0.1f && slowInk > fastInk)
    }

    @Test
    fun wetInkAndTheFountainPenPoolAtTheLift() {
        // A fast line: the ink level settles at 0.05, the lift adds 0.25, wet ink and the fountain pen 0.35 more.
        val wet = builder(Brush.WET)
        line(wet, 41, 4f, 1.0 / 480)
        assertEquals(0.65f, wet.finish().last().ink, 0.01f)
        val fountain = builder(Brush.FOUNTAIN)
        line(fountain, 41, 4f, 1.0 / 480)
        assertEquals(0.65f, fountain.finish().last().ink, 0.01f)
        val pen = builder(Brush.PEN)
        line(pen, 41, 4f, 1.0 / 480)
        assertEquals(0.30f, pen.finish().last().ink, 0.01f)
    }

    @Test
    fun thePreviewAddsTheTipAndThePredictedSamplesButCommitsNeither() {
        val b = builder(Brush.PEN)
        b.add(sample(0f, 0f, 0.0))
        b.add(sample(0.3f, 0f, 1.0 / 240)) // too close to commit: the tip moves on
        assertEquals(1, b.points.size)
        assertEquals(Vec2(0.3f, 0f), b.tip)
        val predicted = listOf(
            InputSample(1f, 0f, 1f, 2.0 / 240, predicted = true),
            InputSample(2f, 0f, 1f, 3.0 / 240, predicted = true),
            InputSample(Float.NaN, 0f, 1f, 4.0 / 240, predicted = true),
        )
        val preview = b.preview(predicted)
        assertEquals(listOf(0f, 0.3f, 1f, 2f), preview.map { it.x })
        assertTrue(preview.all { it.r == 1.1f && it.ink == 1f })
        // A predicted sample never becomes a point.
        for (p in predicted) b.add(p)
        assertEquals(1, b.points.size)
        // The tip within 0.05 of the last point is not shown twice.
        val still = builder(Brush.PEN)
        still.add(sample(0f, 0f, 0.0))
        assertEquals(1, still.preview(emptyList()).size)
    }

    @Test
    fun thePencilShadesWithTiltAndPressure() {
        val straight = builder(Brush.PENCIL) // width 2.6, sensitivity 0.35
        straight.add(sample(0f, 0f, 0.0, altitude = upright))
        assertEquals(1.3f, straight.points[0].r, 1e-5f)
        assertEquals(0.75f, straight.points[0].ink, 1e-5f)
        val flat = builder(Brush.PENCIL)
        flat.add(sample(0f, 0f, 0.0, altitude = 0f))
        assertEquals(1.3f * 4.2f, flat.points[0].r, 1e-5f)
        assertEquals(0.75f * 0.45f, flat.points[0].ink, 1e-5f)
        // Fingers have no tilt.
        val finger = builder(Brush.PENCIL)
        finger.add(sample(0f, 0f, 0.0, altitude = 0f, isPencil = false))
        assertEquals(1.3f, finger.points[0].r, 1e-5f)
        // Light pressure: paler graphite, never below 0.12.
        val light = builder(Brush.PENCIL)
        light.add(sample(0f, 0f, 0.0, force = 0.05f, altitude = 0f))
        assertEquals(0.37f * 0.45f, light.points[0].ink, 1e-5f)
        // The watercolor spreads with tilt.
        val wash = builder(Brush.WATERCOLOR) // width 16, sensitivity 0.55
        wash.add(sample(0f, 0f, 0.0, altitude = 0f))
        assertEquals(8f * 1.8f, wash.points[0].r, 1e-4f)
    }

    @Test
    fun theFountainPenSpreadsWithPressureAndOnDownstrokes() {
        val b = builder(Brush.FOUNTAIN) // width 3.2
        b.add(sample(0f, 0f, 0.0))
        // Average press, moving along +x: 1.6 * 1.0 * 0.82.
        assertEquals(1.312f, b.points[0].r, 1e-5f)
        val unknown = builder(Brush.FOUNTAIN)
        unknown.add(sample(0f, 0f, 0.0, force = 0f))
        assertEquals(1.312f, unknown.points[0].r, 1e-5f)
        val hard = builder(Brush.FOUNTAIN)
        hard.add(sample(0f, 0f, 0.0, force = 9f)) // clamped to 3.5
        assertEquals(1.6f * (0.22f + 0.78f * 3.5f.pow(0.85f)) * 0.82f, hard.points[0].r, 1e-4f)
        // A downstroke comes out fuller as the direction turns to +y.
        val down = builder(Brush.FOUNTAIN)
        line(down, 41, 2f, 1.0 / 240, vertical = true)
        assertTrue(down.points.last().r > 1.6f)
        assertTrue(down.points.last().r <= 1.6f * 1.07f + 1e-5f)
    }

    @Test
    fun theCalligraphyNibLeavesAHairlineAlongItsEdge() {
        val along = builder(Brush.CALLIGRAPHY) // width 7, sensitivity 0.3
        along.nibAngle = 0f
        along.useRoll = false
        along.add(sample(0f, 0f, 0.0))
        // The first point moves along +x, the nib edge too: 3.5 * 0.16.
        assertEquals(0.56f, along.points[0].r, 1e-5f)
        // Across the edge the stroke reaches the full width.
        val across = builder(Brush.CALLIGRAPHY)
        across.nibAngle = 0f
        across.useRoll = false
        line(across, 41, 2f, 1.0 / 240, vertical = true)
        assertTrue(across.points.last().r > 3.3f)
        assertTrue(across.points.last().r <= 3.5f + 1e-5f)
        // The barrel roll turns the nib: rolled a quarter turn, a stroke along +x is the full width.
        val rolled = builder(Brush.CALLIGRAPHY)
        rolled.nibAngle = 0f
        rolled.useRoll = true
        rolled.add(InputSample(0f, 0f, 1f, 0.0, roll = 1.5707964f))
        assertEquals(3.5f, rolled.points[0].r, 1e-4f)
        // The nib angle plus the roll, unless the roll is switched off.
        val fresh = StrokeBuilder(Brush.CALLIGRAPHY, black, 7f, 0f)
        assertEquals(0.66f + 0.5f, fresh.nib(0.5f), 1e-6f)
        fresh.useRoll = false
        assertEquals(0.66f, fresh.nib(0.5f), 1e-6f)
    }

    @Test
    fun theBuilderKeepsWhatTheCanvasReads() {
        val b = StrokeBuilder(Brush.GRASS, InkColor.hex(0x3F9B2F), 10f, 2.37f)
        assertEquals(Brush.GRASS, b.brush)
        assertEquals(InkColor.hex(0x3F9B2F), b.color)
        assertEquals(10f, b.width, 0f)
        assertEquals(2.37f, b.seed, 0f)
        assertNull(b.tip)
        assertEquals(0.66f, b.nibAngle, 0f)
        assertTrue(b.useRoll)
    }

    @Test
    fun theForceOfAnAndroidPenMapsOntoTheIPadScale() {
        assertEquals(InputSample.PENCIL_MAX_FORCE, InputSample.force(1f, stylus = true), 0f)
        assertEquals(1f, InputSample.force(0.24f, stylus = true), 0.01f)
        assertEquals(0f, InputSample.force(0.5f, stylus = false), 0f)
        assertEquals(0f, InputSample.force(0f, stylus = true), 0f)
        assertTrue(abs(InputSample(0f, 0f, 0f, 0.0).altitude - 1.5707964f) < 1e-7f)
    }
}
