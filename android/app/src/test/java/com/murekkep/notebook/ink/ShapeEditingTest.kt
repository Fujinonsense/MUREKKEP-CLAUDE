package com.murekkep.notebook.ink

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

// A recognized shape's handles against the iPad: the fixture (tools/shapecheck) drags the handles of
// every recognized shape as the real Swift EditableShape did, and redraws a stroke along it.
class ShapeEditingTest {
    private val black = InkColor(0f, 0f, 0f)

    @Test
    fun handlesMovesTransformsAndRedrawsMatchTheIPad() {
        var shapes = 0
        var moves = 0
        for (c in ShapeFixture.cases("recognize")) {
            val match = ShapeRecognizer.recognize(c.first("in").points()) ?: continue
            val records = c.records
            var i = records.indexOfFirst { it.key == "shape" || it.key == "editable" }
            if (i < 0) continue
            if (records[i].key == "editable") {
                assertNull("${c.name}: no handles", EditableShape.from(match))
                continue
            }
            var shape = EditableShape.from(match) ?: error("${c.name}: the match has no handles")
            val (first, next) = ShapeBlock.parse(records, i)
            first.check("${c.name}: as recognized", shape)
            shapes++
            i = next
            while (i < records.size) {
                val r = records[i]
                when (r.key) {
                    "restroke_in" -> {
                        val stroke = Stroke(Brush.WET, black, 3.8f, 12.5, 0.25f, r.inkPoints(), 1.5)
                        val redrawn = restroke(stroke, shape.path())
                        val want = records[i + 1]
                        assertEquals("${c.name}: restroke_out", "restroke_out", want.key)
                        Same.ink("${c.name}: redrawn", want.inkPoints(), redrawn.points)
                        assertEquals(stroke.brush, redrawn.brush)
                        assertEquals(stroke.color, redrawn.color)
                        assertEquals(stroke.width, redrawn.width, 0f)
                        assertEquals(stroke.birth, redrawn.birth, 0.0)
                        assertEquals(stroke.seed, redrawn.seed, 0f)
                        assertEquals(stroke.duration, redrawn.duration, 0.0)
                        assertNotEquals(stroke.id, redrawn.id)
                        i += 2
                    }
                    "move" -> {
                        val v = r.doubles()
                        val moved = shape.move(v[0].toInt(), Pt(v[1], v[2]), v[3])
                        val what = "${c.name}: move ${v[0].toInt()}"
                        assertEquals("$what: label", "label", records[i + 1].key)
                        val label = moved.feedback.label?.format({ it.titleTr }, ',') ?: "-"
                        assertEquals("$what: label", records[i + 1].value, label)
                        assertEquals("$what: snapped", records[i + 2].value == "1", moved.feedback.snapped)
                        val (block, after) = ShapeBlock.parse(records, i + 3)
                        block.check(what, moved.shape)
                        shape = moved.shape
                        moves++
                        i = after
                    }
                    "transform" -> {
                        val v = r.doubles()
                        shape = shape.transformed(Pt(v[0], v[1]), v[2], v[3])
                        val (block, after) = ShapeBlock.parse(records, i + 1)
                        block.check("${c.name}: transformed", shape)
                        i = after
                    }
                    else -> i++
                }
            }
        }
        assertTrue("$shapes shapes, $moves moves", shapes >= 50 && moves >= 200)
    }

    @Test
    fun labelsReadAsOnTheIPad() {
        val tr = { n: ShapeName -> n.titleTr }
        val en = { n: ShapeName -> n.titleEn }
        assertEquals("90°", ShapeLabel.Degrees(90).format(tr))
        assertEquals("42,3 mm", ShapeLabel.Length(42.34).format(tr))
        assertEquals("42.3 mm", ShapeLabel.Length(42.34).format(en, '.'))
        assertEquals("8 mm", ShapeLabel.Length(8.04).format(tr))
        assertEquals("0 mm", ShapeLabel.Length(0.0).format(tr))
        assertEquals("12,3 cm", ShapeLabel.Length(123.46).format(tr))
        assertEquals("10 cm", ShapeLabel.Length(100.0).format(tr))
        assertEquals("99,9 mm", ShapeLabel.Length(99.94).format(tr))
        assertEquals("Eğri", ShapeLabel.Title(ShapeName.CURVE).format(tr))
        assertEquals("Curve", ShapeLabel.Title(ShapeName.CURVE).format(en))
        assertEquals("Daire · 24 mm", ShapeLabel.OvalSize(ShapeName.CIRCLE, 24.0, null).format(tr))
        assertEquals("Elips · 24 mm × 16,5 mm", ShapeLabel.OvalSize(ShapeName.ELLIPSE, 24.0, 16.5).format(tr))
        assertEquals("Ellipse · 24 mm × 16.5 mm", ShapeLabel.OvalSize(ShapeName.ELLIPSE, 24.0, 16.5).format(en, '.'))
        // Swift's rounding behind the degrees: halves go away from zero.
        assertEquals(-23.0, roundedAway(-22.5), 0.0)
        assertEquals(23.0, roundedAway(22.5), 0.0)
        assertEquals(2.0, roundedAway(1.5), 0.0)
        assertEquals(3.0, roundedAway(2.5), 0.0)
        assertEquals(-3.0, roundedAway(-2.5), 0.0)
        assertEquals(2.0, roundedAway(2.4999999), 0.0)
        assertEquals(0.0, roundedAway(0.49999999999999994), 0.0)
        assertEquals(3.0, roundedAway(2.9), 0.0)
        assertEquals(-3, roundedAwayToInt(-2.5))
    }

    @Test
    fun theMiddleHandleMovesTheWholeShapeWithoutALabel() {
        val square = EditableShape(
            EditableShape.Kind.Polygon,
            listOf(Pt(0.0, 0.0), Pt(40.0, 0.0), Pt(40.0, 40.0), Pt(0.0, 40.0)),
            ShapeName.SQUARE,
        )
        assertEquals(Pt(20.0, 20.0), square.middle)
        assertEquals(5, square.handles.size)
        val moved = square.move(4, Pt(30.0, 15.0), 9.0)
        assertNull(moved.feedback.label)
        assertFalse(moved.feedback.snapped)
        assertEquals(listOf(Pt(10.0, -5.0), Pt(50.0, -5.0), Pt(50.0, 35.0), Pt(10.0, 35.0)), moved.shape.points)
        assertEquals(ShapeName.SQUARE, moved.shape.name)
        // A handle that does not exist changes nothing.
        assertEquals(square, square.move(7, Pt(1.0, 1.0), 9.0).shape)
        // The outline closes back on the first corner.
        assertEquals(5, square.path().size)
        assertEquals(square.points[0], square.path()[4])
    }

    @Test
    fun aCornerSettlesLevelWithItsNeighbourAndTellsTheAngle() {
        val square = EditableShape(
            EditableShape.Kind.Polygon,
            listOf(Pt(0.0, 0.0), Pt(40.0, 0.0), Pt(40.0, 40.0), Pt(0.0, 40.0)),
            ShapeName.SQUARE,
        )
        val moved = square.move(1, Pt(60.0, 3.0), 9.0)
        assertTrue(moved.feedback.snapped)
        assertEquals(Pt(60.0, 0.0), moved.shape.points[1])
        // The angle at the corner, between its neighbours (0, 0) and (40, 40): 90° became 63°.
        assertEquals(ShapeLabel.Degrees(63), moved.feedback.label)
        // An end of a line reports its length instead: 44,7 points is 15,8 mm.
        val line = EditableShape(EditableShape.Kind.Polyline, listOf(Pt(0.0, 0.0), Pt(40.0, 0.0)), ShapeName.LINE)
        val end = line.move(1, Pt(40.0, 20.0), 9.0)
        assertFalse(end.feedback.snapped)
        assertEquals("15,8 mm", end.feedback.label!!.format({ it.titleTr }))
        // Upright with its neighbour: the x settles.
        val upright = line.move(1, Pt(4.0, 30.0), 9.0)
        assertTrue(upright.feedback.snapped)
        assertEquals(Pt(0.0, 30.0), upright.shape.points[1])
    }

    @Test
    fun redrawingKeepsTheAverageWidthAndInkAndGivesAFreshId() {
        val points = listOf(InkPoint(0f, 0f, 1f, 0.2f), InkPoint(10f, 0f, 3f, 0.6f), InkPoint(20f, 0f, 2f, 1f))
        val stroke = Stroke(Brush.PEN, black, 2.2f, 100.0, 0.5f, points, 0.3)
        val redrawn = restroke(stroke, listOf(Pt(0.0, 0.0), Pt(0.0, 9.0)))
        assertNotEquals(stroke.id, redrawn.id)
        assertEquals(stroke.brush, redrawn.brush)
        assertEquals(stroke.birth, redrawn.birth, 0.0)
        // Points every max(1.5, 0.7 r) = 1.5 along the 9-point path, the corners kept.
        assertEquals(7, redrawn.points.size)
        assertEquals(Vec2(0f, 0f), redrawn.points.first().position)
        assertEquals(Vec2(0f, 9f), redrawn.points.last().position)
        for (p in redrawn.points) {
            assertEquals(2f, p.r, 1e-6f)
            assertEquals(0.6f, p.ink, 1e-6f)
            assertEquals(0f, p.x, 0f)
        }
        // A path too short to draw leaves no points, and an empty stroke a width of nothing.
        assertEquals(1, restroke(stroke, listOf(Pt(3.0, 4.0))).points.size)
        assertTrue(restroke(Stroke(Brush.PEN, black, 2.2f, 100.0, 0.5f, emptyList()), listOf(Pt(0.0, 0.0), Pt(3.0, 0.0))).points.all { it.r == 0f })
    }
}
