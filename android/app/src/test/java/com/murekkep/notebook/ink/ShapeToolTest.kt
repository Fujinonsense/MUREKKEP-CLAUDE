package com.murekkep.notebook.ink

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.cos
import kotlin.math.sin

// The shape tool against the iPad: the fixture (tools/shapecheck) holds the paths, live labels,
// dashes and snapped drag ends of the real Swift ShapeBuilder and CanvasView.snappedShapeEnd.
class ShapeToolTest {
    @Test
    fun pathsMeasurementsDashesAndSnappedEndsMatchTheIPad() {
        val cases = ShapeFixture.cases("tool")
        assertTrue("${cases.size} drags", cases.size >= 25)
        var dashed = 0
        for (c in cases) {
            val kind = ShapeKind.fromRaw(c.first("kind").value)
            assertEquals(c.name, c.first("kind").value, kind.raw)
            val a = c.first("from").points()[0]
            val b = c.first("to").points()[0]
            val sides = c.first("sides").value.toInt()
            assertEquals("${c.name}: measurement", c.first("measurement").value, ShapeBuilder.measurement(kind, a, b).format(','))
            Same.point("${c.name}: snapped end", c.first("snapped").points()[0], ShapeBuilder.snappedEnd(kind, b, a))
            val paths = ShapeBuilder.paths(kind, a, b, sides)
            val want = c.all("path")
            assertEquals("${c.name}: paths", want.size, paths.size)
            for (i in want.indices) Same.floatVecs("${c.name}: path $i", want[i].vecs(), paths[i])
            val dashes = c.all("dash")
            if (dashes.isNotEmpty()) {
                val got = ShapeBuilder.dashed(paths)
                assertEquals("${c.name}: dashes", dashes.size, got.size)
                for (i in dashes.indices) Same.floatVecs("${c.name}: dash $i", dashes[i].vecs(), got[i])
                dashed++
            }
        }
        assertTrue("$dashed dashed drags", dashed >= 5)
        for (kind in ShapeKind.entries) {
            assertTrue("a ${kind.raw}", cases.any { it.first("kind").value == kind.raw })
        }
    }

    @Test
    fun linesClickToFifteenDegreesAndBoxesToSquares() {
        val a = Pt(40.0, 100.0)
        // 29° is within 0.05 rad of 30°, 26° is not.
        val near = Pt(40 + 100 * cos(29 * Math.PI / 180), 100 - 100 * sin(29 * Math.PI / 180))
        val snapped = ShapeBuilder.snappedEnd(ShapeKind.LINE, near, a)
        Same.point("30°", Pt(40 + 100 * cos(30 * Math.PI / 180), 100 - 100 * sin(30 * Math.PI / 180)), snapped)
        val far = Pt(40 + 100 * cos(26 * Math.PI / 180), 100 - 100 * sin(26 * Math.PI / 180))
        assertEquals(far, ShapeBuilder.snappedEnd(ShapeKind.ARROW, far, a))
        assertEquals(far, ShapeBuilder.snappedEnd(ShapeKind.DOUBLE_ARROW, far, a))
        // A box 100 by 104 is nearly square: 104 by 104, the way the drag went.
        assertEquals(Pt(144.0, 144.0), ShapeBuilder.snappedEnd(ShapeKind.RECTANGLE, Pt(140.0, 144.0), Pt(40.0, 40.0)))
        assertEquals(Pt(-64.0, 144.0), ShapeBuilder.snappedEnd(ShapeKind.ELLIPSE, Pt(-60.0, 144.0), Pt(40.0, 40.0)))
        assertEquals(Pt(140.0, 160.0), ShapeBuilder.snappedEnd(ShapeKind.RECTANGLE, Pt(140.0, 160.0), Pt(40.0, 40.0)))
        // Triangles, circles and polygons follow the pen.
        assertEquals(near, ShapeBuilder.snappedEnd(ShapeKind.TRIANGLE, near, a))
        assertEquals(Pt(140.0, 144.0), ShapeBuilder.snappedEnd(ShapeKind.CIRCLE, Pt(140.0, 144.0), Pt(40.0, 40.0)))
    }

    @Test
    fun lengthsAreWrittenToATenthInMillimetresAndCentimetres() {
        assertEquals("42,3 mm", ShapeBuilder.mm(42.34))
        assertEquals("42,4 mm", ShapeBuilder.mm(42.36))
        assertEquals("42.3 mm", ShapeBuilder.mm(42.34, '.'))
        assertEquals("8 mm", ShapeBuilder.mm(8.04))
        assertEquals("0 mm", ShapeBuilder.mm(0.0))
        assertEquals("12,3 cm", ShapeBuilder.mm(123.46))
        assertEquals("10 cm", ShapeBuilder.mm(100.0))
        assertEquals("99,9 mm", ShapeBuilder.mm(99.94))
        // No metres on the iPad either.
        assertEquals("100 cm", ShapeBuilder.mm(1000.0))
    }

    @Test
    fun theLiveLabelNamesTheLengthAndAngleTheRadiusOrTheSize() {
        val ppm = POINTS_PER_MILLIMETRE
        val line = ShapeBuilder.measurement(ShapeKind.LINE, Pt(0.0, 0.0), Pt(30 * ppm, -40 * ppm))
        assertTrue(line is ShapeMeasurement.Length)
        assertEquals(50.0, (line as ShapeMeasurement.Length).lengthMm, 1e-9)
        assertEquals(53, line.degrees)
        assertEquals("50 mm · 53°", line.format())
        // Down the page is a negative angle on paper: 360° minus it.
        assertEquals("50 mm · 307°", ShapeBuilder.measurement(ShapeKind.ARROW, Pt(0.0, 0.0), Pt(30 * ppm, 40 * ppm)).format())
        assertEquals("r = 50 mm", ShapeBuilder.measurement(ShapeKind.CIRCLE, Pt(0.0, 0.0), Pt(30 * ppm, -40 * ppm)).format())
        assertEquals("r = 50 mm", ShapeBuilder.measurement(ShapeKind.POLYGON, Pt(0.0, 0.0), Pt(30 * ppm, -40 * ppm)).format())
        assertEquals("30 mm × 40 mm", ShapeBuilder.measurement(ShapeKind.RECTANGLE, Pt(0.0, 0.0), Pt(-30 * ppm, 40 * ppm)).format())
        assertEquals("30 mm × 40 mm", ShapeBuilder.measurement(ShapeKind.ELLIPSE, Pt(0.0, 0.0), Pt(-30 * ppm, 40 * ppm)).format())
        assertEquals("30 mm × 40 mm", ShapeBuilder.measurement(ShapeKind.TRIANGLE, Pt(0.0, 0.0), Pt(-30 * ppm, 40 * ppm)).format())
        assertEquals("30 cm × 40 cm", ShapeBuilder.measurement(ShapeKind.RIGHT_TRIANGLE, Pt(0.0, 0.0), Pt(-300 * ppm, 400 * ppm)).format('.'))
        assertEquals("12.3 cm · 45°", ShapeBuilder.measurement(ShapeKind.LINE, Pt(0.0, 0.0), Pt(87.26 * ppm, -87.26 * ppm)).format('.'))
    }

    @Test
    fun arrowsHaveAHeadAndDashesBreakAtSixAndFour() {
        val arrow = ShapeBuilder.paths(ShapeKind.ARROW, Pt(0.0, 0.0), Pt(100.0, 0.0), 6)
        assertEquals(1, arrow.size)
        // Shaft, tip, a wing, tip again, the other wing; the head is 16 points long at most.
        Same.vecs("arrow", listOf(Vec2(0f, 0f), Vec2(100f, 0f), Vec2(84f, 7.2f), Vec2(100f, 0f), Vec2(84f, -7.2f)), arrow[0], 1e-5)
        val both = ShapeBuilder.paths(ShapeKind.DOUBLE_ARROW, Pt(0.0, 0.0), Pt(100.0, 0.0), 6)
        assertEquals(2, both.size)
        Same.vecs("second head", listOf(Vec2(16f, -7.2f), Vec2(0f, 0f), Vec2(16f, 7.2f)), both[1], 1e-5)
        // A head is at least 6 points long, and no head at all on a dot.
        Same.vec("short head", Vec2(9f, 2.7f), ShapeBuilder.paths(ShapeKind.ARROW, Pt(0.0, 0.0), Pt(15.0, 0.0), 6)[0][2], 1e-5)
        assertEquals(listOf(Vec2(0f, 0f), Vec2(0.2f, 0f)), ShapeBuilder.paths(ShapeKind.ARROW, Pt(0.0, 0.0), Pt(0.2, 0.0), 6)[0])
        val dashes = ShapeBuilder.dashed(listOf(listOf(Vec2(0f, 0f), Vec2(25f, 0f))))
        assertEquals(3, dashes.size)
        Same.vecs("dash 0", listOf(Vec2(0f, 0f), Vec2(6f, 0f)), dashes[0], 1e-5)
        Same.vecs("dash 1", listOf(Vec2(10f, 0f), Vec2(16f, 0f)), dashes[1], 1e-5)
        Same.vecs("dash 2", listOf(Vec2(20f, 0f), Vec2(25f, 0f)), dashes[2], 1e-5)
        // The regular polygon has its sides clamped to 3…24 and closes on its first corner.
        val many = ShapeBuilder.paths(ShapeKind.POLYGON, Pt(0.0, 0.0), Pt(50.0, 0.0), 40)[0]
        assertEquals(25, many.size)
        val few = ShapeBuilder.paths(ShapeKind.POLYGON, Pt(0.0, 0.0), Pt(50.0, 0.0), 1)[0]
        assertEquals(4, few.size)
        assertEquals(Vec2(50f, 0f), few[0])
    }
}
