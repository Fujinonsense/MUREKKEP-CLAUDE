package com.murekkep.notebook.ink

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.sqrt

// The freehand half of StrokeBuilder has no check in tools/swiftcheck; those are the iPad numbers
// worked out by hand. Hold-to-shape is held to the fixture of tools/shapecheck, which ran the real
// Swift StrokeBuilder over the same pen samples.
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

    // MARK: Hold-to-shape

    /** Runs a fixture case's pen samples, snaps and checks through the builder, as the iPad's ran. */
    private fun replay(c: FixtureCase) {
        val head = c.first("brush").tokens
        val b = StrokeBuilder(Brush.fromRaw(head[0].toInt()), black, head[1].toFloat(), 0.5f)
        b.nibAngle = head[2].toFloat()
        b.useRoll = head[3] == "1"
        val records = c.records
        var i = 1
        while (i < records.size) {
            val r = records[i]
            val what = "${c.name}: ${r.key} at $i"
            when (r.key) {
                "sample" -> {
                    val t = r.tokens
                    b.add(
                        InputSample(
                            t[0].toFloat(), t[1].toFloat(), t[2].toFloat(), t[3].toDouble(),
                            altitude = t[4].toFloat(), roll = t[6].toFloat(), isPencil = t[5] == "1",
                        ),
                    )
                    i++
                }
                "snapline" -> {
                    val got = b.snapToLine()
                    assertEquals(what, records[i + 1].value == "1", got)
                    i += 2
                }
                "snapshape" -> {
                    val got = b.snapToShape()
                    val want = records[i + 1].value
                    assertEquals(what, want, got?.titleTr ?: "-")
                    i += 2
                }
                "points" -> {
                    Same.ink(what, r.inkPoints(), b.points)
                    i++
                }
                "straight" -> {
                    assertEquals(what, r.value == "1", b.isStraight)
                    i++
                }
                "adjust" -> {
                    if (r.value == "-") {
                        assertNull(what, b.shapeAdjustment)
                    } else {
                        val a = b.shapeAdjustment
                        assertNotNull(what, a)
                        Same.value("$what scale", r.doubles()[0], a!!.scale)
                        assertEquals("$what degrees", r.tokens[1].toInt(), a.degrees)
                    }
                    i++
                }
                "editable" -> {
                    assertNull(what, b.editable)
                    i++
                }
                "shape" -> {
                    val (block, after) = ShapeBlock.parse(records, i)
                    val e = b.editable
                    assertNotNull(what, e)
                    block.check(what, e!!)
                    i = after
                }
                "drawn" -> {
                    Same.points(what, r.points(), b.drawnPath)
                    i++
                }
                "tip" -> {
                    if (r.value == "-") {
                        assertNull(what, b.tip)
                    } else {
                        Same.vec(what, r.vecs()[0], b.tip!!)
                    }
                    i++
                }
                "preview" -> {
                    Same.ink(what, r.inkPoints(), b.preview(emptyList()))
                    i++
                }
                "finish" -> {
                    val got = b.finish()
                    assertEquals(what, "points", records[i + 1].key)
                    Same.ink("$what points", records[i + 1].inkPoints(), got)
                    i += 2
                }
                else -> error("$what: unknown record")
            }
        }
    }

    @Test
    fun holdToShapeMatchesTheIPad() {
        val cases = ShapeFixture.cases("builder")
        assertTrue("${cases.size} strokes", cases.size >= 10)
        for (c in cases) replay(c)
        // Lines, a square, a circle, a triangle, a curve and a scribble that stays as it is.
        val results = cases.map { c -> c.records.firstOrNull { it.key == "result" }?.value }
        assertTrue(results.contains("Doğru") && results.contains("Kare") && results.contains("Daire") && results.contains("Eğri") && results.contains("-"))
    }

    /** Pen samples 2 points apart along the corners (and back to the first), `dt` apart. */
    private fun trace(b: StrokeBuilder, corners: List<Pt>, closed: Boolean, t0: Double = 0.0): Pt {
        val stops = if (closed) corners + corners[0] else corners
        var n = 0
        var last = corners[0]
        for (i in 0 until stops.size - 1) {
            val a = stops[i]
            val c = stops[i + 1]
            val steps = (Geo.dist(a, c) / 2).toInt()
            for (k in 0 until steps) {
                val t = k.toDouble() / steps
                last = Pt(a.x + (c.x - a.x) * t, a.y + (c.y - a.y) * t)
                b.add(sample(last.x.toFloat(), last.y.toFloat(), t0 + n / 240.0))
                n++
            }
        }
        last = stops.last()
        b.add(sample(last.x.toFloat(), last.y.toFloat(), t0 + n / 240.0))
        return last
    }

    @Test
    fun aHeldStrokeBecomesALineThatFollowsThePen() {
        val b = builder(Brush.PEN)
        assertFalse(b.snapToLine()) // nothing drawn yet
        trace(b, listOf(Pt(10.0, 10.0), Pt(90.0, 60.0)), closed = false)
        val before = b.points.size
        assertTrue(before > 10)
        assertTrue(b.snapToLine())
        assertTrue(b.isStraight)
        assertFalse(b.snapToLine()) // only once
        // Two points, the average width and ink, from the start to the pen.
        assertEquals(2, b.points.size)
        assertEquals(Vec2(10f, 10f), b.points[0].position)
        assertEquals(Vec2(90f, 60f), b.points[1].position)
        assertEquals(1.1f, b.points[0].r, 1e-5f)
        assertEquals(b.points[0].r, b.points[1].r, 0f)
        assertEquals(b.points[0].ink, b.points[1].ink, 0f)
        val line = b.editable!!
        assertEquals(EditableShape.Kind.Polyline, line.kind)
        assertEquals(ShapeName.LINE, line.name)
        assertEquals(listOf(Pt(10.0, 10.0), Pt(90.0, 60.0)), line.points)
        assertNull(b.shapeAdjustment)
        // The pen moves on: the end follows, nothing else is added, the preview shows no tip.
        b.add(sample(120f, 40f, 1.0))
        assertEquals(2, b.points.size)
        assertEquals(Vec2(120f, 40f), b.points[1].position)
        assertEquals(listOf(Pt(10.0, 10.0), Pt(120.0, 40.0)), b.editable!!.points)
        assertEquals(2, b.preview(listOf(InputSample(200f, 200f, 1f, 1.1, predicted = true))).size)
        assertEquals(listOf(Pt(10.0, 10.0), Pt(120.0, 40.0)), b.drawnPath)
        assertEquals(2, b.finish().size)
    }

    @Test
    fun aLineNeedsSixPointsOfInk() {
        val b = builder(Brush.PEN)
        b.add(sample(10f, 10f, 0.0))
        b.add(sample(12f, 11f, 1.0 / 240))
        b.add(sample(14f, 12f, 2.0 / 240))
        assertFalse(b.snapToLine())
        assertFalse(b.isStraight)
        assertNull(b.editable)
    }

    @Test
    fun aHeldSquareSnapsAndThePenTurnsItInFifteenDegreeClicks() {
        val b = builder(Brush.PEN)
        val corners = listOf(Pt(50.0, 50.0), Pt(130.0, 50.0), Pt(130.0, 130.0), Pt(50.0, 130.0))
        val grab = trace(b, corners, closed = true)
        val freehand = b.points.size
        assertEquals(ShapeName.SQUARE, b.snapToShape())
        assertTrue(b.isStraight)
        assertNull(b.snapToShape()) // only once
        // The stroke is now the square's outline, denser than the pen's own samples, in the same ink.
        assertTrue(b.points.size > freehand)
        assertTrue(b.points.all { abs(it.r - 1.1f) < 1e-6f })
        assertEquals(ShapeAdjustment(1.0, 0), b.shapeAdjustment)
        val square = b.editable!!
        assertEquals(EditableShape.Kind.Polygon, square.kind)
        assertEquals(4, square.points.size)
        // The pen swings round the middle by 14°: the square turns 15°, as big as before.
        val anchor = square.middle
        fun at(degrees: Double, scale: Double): InputSample {
            val a = degrees * Math.PI / 180
            val dx = (grab.x - anchor.x) * scale
            val dy = (grab.y - anchor.y) * scale
            return sample((anchor.x + dx * cos(a) - dy * sin(a)).toFloat(), (anchor.y + dx * sin(a) + dy * cos(a)).toFloat(), 1.0)
        }
        b.add(at(14.0, 1.0))
        assertEquals(15, b.shapeAdjustment!!.degrees)
        assertEquals(1.0, b.shapeAdjustment!!.scale, 0.01)
        // By 7° only, half as far out: no click, half the size.
        b.add(at(7.0, 0.5))
        assertEquals(7, b.shapeAdjustment!!.degrees)
        assertEquals(0.5, b.shapeAdjustment!!.scale, 0.01)
        // Backwards, between two clicks: -23°.
        b.add(at(-22.6, 1.0))
        assertEquals(-23, b.shapeAdjustment!!.degrees)
        // The handles follow the pen.
        val turned = b.editable!!
        assertEquals(4, turned.points.size)
        Same.point("middle", anchor, turned.middle, 1e-6)
        assertTrue(Geo.dist(turned.points[0], square.points[0]) > 10)
        assertTrue(b.finish().size > 4)
    }

    @Test
    fun aWobbleWhileLiftingThePenChangesNothing() {
        val b = builder(Brush.PEN)
        val grab = trace(b, listOf(Pt(50.0, 50.0), Pt(130.0, 50.0), Pt(130.0, 130.0), Pt(50.0, 130.0)), closed = true)
        assertEquals(ShapeName.SQUARE, b.snapToShape())
        val points = b.points.toList()
        b.add(sample((grab.x + 3).toFloat(), (grab.y - 2).toFloat(), 1.0))
        assertEquals(points, b.points)
        assertEquals(ShapeAdjustment(1.0, 0), b.shapeAdjustment)
    }

    @Test
    fun aScribbleStaysAsItIs() {
        val b = builder(Brush.PEN)
        // A scrawl within 6 points: long enough, but too small across to be anything.
        for (i in 0 until 40) {
            b.add(sample(100f + 3f * cos(i * 1.0).toFloat(), 100f + 3f * sin(i * 1.7).toFloat(), i / 240.0))
        }
        val before = b.points.toList()
        assertTrue(before.size > 10)
        assertNull(b.snapToShape())
        assertFalse(b.isStraight)
        assertNull(b.editable)
        assertNull(b.shapeAdjustment)
        assertEquals(before, b.points)
        // The lift still adds the tip.
        b.add(sample(110f, 100f, 1.0))
        assertTrue(b.finish().size > before.size)
    }

    @Test
    fun applyReplacesTheStrokeWithAPathInItsOwnInk() {
        val b = builder(Brush.WET) // width 3.8, sensitivity 0.65
        line(b, 21, 2f, 1.0 / 240, force = 2.25f)
        val r = b.points.map { it.r }.average().toFloat()
        val ink = b.points.map { it.ink }.average().toFloat()
        b.apply(listOf(Pt(0.0, 0.0), Pt(30.0, 0.0), Pt(30.0, 40.0)))
        assertTrue(b.isStraight)
        // Corners stay points of the stroke; the spacing is max(1.5, 0.7 r).
        assertEquals(Vec2(0f, 0f), b.points.first().position)
        assertEquals(Vec2(30f, 40f), b.points.last().position)
        assertTrue(b.points.any { it.position == Vec2(30f, 0f) })
        for (p in b.points) {
            assertEquals(r, p.r, 1e-5f)
            assertEquals(ink, p.ink, 1e-5f)
        }
        // A path with one point, or an empty stroke, is left alone.
        val count = b.points.size
        b.apply(listOf(Pt(5.0, 5.0)))
        assertEquals(count, b.points.size)
        val empty = builder(Brush.PEN)
        empty.apply(listOf(Pt(0.0, 0.0), Pt(10.0, 0.0)))
        assertTrue(empty.points.isEmpty())
        assertFalse(empty.isStraight)
    }
}
