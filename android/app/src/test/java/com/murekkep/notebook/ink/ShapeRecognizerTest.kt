package com.murekkep.notebook.ink

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

// Hold-to-shape against the iPad: every stroke of the fixture (tools/shapecheck) must give the same
// kind, name and points as the real Swift recognizer did.
class ShapeRecognizerTest {
    private fun kindName(k: ShapeMatch.Kind) = when (k) {
        ShapeMatch.Kind.LINE -> "line"
        ShapeMatch.Kind.POLYLINE -> "polyline"
        ShapeMatch.Kind.POLYGON -> "polygon"
        ShapeMatch.Kind.RECTANGLE -> "rectangle"
        ShapeMatch.Kind.CIRCLE -> "circle"
        ShapeMatch.Kind.ELLIPSE -> "ellipse"
        ShapeMatch.Kind.CURVE -> "curve"
    }

    @Test
    fun everyFixtureStrokeIsRecognizedAsOnTheIPad() {
        val cases = ShapeFixture.cases("recognize")
        assertTrue("${cases.size} strokes", cases.size >= 60)
        for (c in cases) {
            val match = ShapeRecognizer.recognize(c.first("in").points())
            val want = c.first("match").value
            if (want == "-") {
                assertNull("${c.name}: nothing", match)
                continue
            }
            assertNotNull("${c.name}: a shape", match)
            match!!
            assertEquals("${c.name}: kind", want.substringBefore(' '), kindName(match.kind))
            assertEquals("${c.name}: name", want.substringAfter(' '), match.name.titleTr)
            assertEquals("${c.name}: closed", c.first("closed").value == "1", match.isClosed)
            Same.points("${c.name}: path", c.first("path").points(), match.path)
            Same.points("${c.name}: corners", c.first("corners").points(), match.corners)
            val oval = c.records.firstOrNull { it.key == "oval" }?.doubles()
            if (oval == null) {
                assertNull("${c.name}: no oval", match.oval)
            } else {
                val o = match.oval!!
                Same.point("${c.name}: oval center", Pt(oval[0], oval[1]), o.center)
                Same.value("${c.name}: oval rx", oval[2], o.rx)
                Same.value("${c.name}: oval ry", oval[3], o.ry)
                Same.value("${c.name}: oval angle", oval[4], o.angle)
            }
            val curve = c.records.firstOrNull { it.key == "curve" }?.doubles()
            if (curve == null) {
                assertNull("${c.name}: no curve", match.curve)
            } else {
                val k = match.curve!!
                Same.point("${c.name}: curve start", Pt(curve[0], curve[1]), k.start)
                Same.point("${c.name}: curve control", Pt(curve[2], curve[3]), k.control)
                Same.point("${c.name}: curve end", Pt(curve[4], curve[5]), k.end)
            }
        }
    }

    @Test
    fun theFixtureCoversEveryKindAndName() {
        val matches = ShapeFixture.cases("recognize").map { it.first("match").value }
        assertTrue("strokes that are nothing", matches.count { it == "-" } >= 6)
        for (kind in listOf("line", "polyline", "polygon", "rectangle", "circle", "ellipse", "curve")) {
            assertTrue("a $kind", matches.any { it.substringBefore(' ') == kind })
        }
        val recognized = listOf(
            ShapeName.LINE, ShapeName.POLYLINE, ShapeName.CURVE, ShapeName.CIRCLE, ShapeName.ELLIPSE, ShapeName.SQUARE,
            ShapeName.RECTANGLE, ShapeName.TRIANGLE, ShapeName.RIGHT_TRIANGLE, ShapeName.EQUILATERAL_TRIANGLE,
            ShapeName.ISOSCELES_TRIANGLE, ShapeName.QUADRILATERAL, ShapeName.PENTAGON, ShapeName.HEXAGON,
            ShapeName.HEPTAGON, ShapeName.OCTAGON,
        )
        for (name in recognized) {
            assertTrue("a ${name.titleTr}", matches.any { it != "-" && it.substringAfter(' ') == name.titleTr })
        }
    }

    @Test
    fun tooLittleIsNothing() {
        assertNull(ShapeRecognizer.recognize(emptyList()))
        assertNull(ShapeRecognizer.recognize(listOf(Pt(0.0, 0.0), Pt(50.0, 30.0))))
        // Under 14 points of ink, or under 8 points across.
        assertNull(ShapeRecognizer.recognize(listOf(Pt(0.0, 0.0), Pt(4.0, 1.0), Pt(8.0, 2.0), Pt(12.0, 3.0))))
        assertNull(ShapeRecognizer.recognize((0..20).map { Pt(it * 0.3, (it % 2) * 6.0) }))
    }

    @Test
    fun aCleanSquareIsASquareWithItsCorners() {
        val corners = listOf(Pt(50.0, 50.0), Pt(130.0, 50.0), Pt(130.0, 130.0), Pt(50.0, 130.0))
        val stroke = ArrayList<Pt>()
        for (i in 0 until 4) {
            val a = corners[i]
            val b = corners[(i + 1) % 4]
            for (k in 0 until 40) stroke.add(Pt(a.x + (b.x - a.x) * k / 40, a.y + (b.y - a.y) * k / 40))
        }
        stroke.add(Pt(50.0, 50.0))
        stroke.add(Pt(54.0, 50.0))
        val m = ShapeRecognizer.recognize(stroke)!!
        assertEquals(ShapeMatch.Kind.RECTANGLE, m.kind)
        assertEquals(ShapeName.SQUARE, m.name)
        assertTrue(m.isClosed)
        assertEquals(4, m.corners.size)
        assertEquals(5, m.path.size)
        for (c in corners) {
            assertTrue("$c among ${m.corners}", m.corners.any { Geo.dist(it, c) < 1.5 })
        }
        val shape = EditableShape.from(m)!!
        assertEquals(EditableShape.Kind.Polygon, shape.kind)
        assertEquals(5, shape.handles.size)
    }

    @Test
    fun aStraightStrokeIsALineFromItsStartToItsEnd() {
        val m = ShapeRecognizer.recognize((0..50).map { Pt(10.0 + it * 2, 20.0 + it * 0.5 + (it % 2) * 0.4) })!!
        assertEquals(ShapeMatch.Kind.LINE, m.kind)
        assertEquals(ShapeName.LINE, m.name)
        assertEquals(listOf(Pt(10.0, 20.0), Pt(110.0, 45.0)), m.path)
        assertEquals(m.path, m.corners)
        assertTrue(!m.isClosed)
    }
}
