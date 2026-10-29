package com.murekkep.notebook.ui

import com.murekkep.notebook.ink.Brush
import com.murekkep.notebook.ink.EditableShape
import com.murekkep.notebook.ink.InkColor
import com.murekkep.notebook.ink.InkPoint
import com.murekkep.notebook.ink.Pt
import com.murekkep.notebook.ink.ShapeKind
import com.murekkep.notebook.ink.ShapeName
import com.murekkep.notebook.ink.Stroke
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

// A recognized shape's handles and the shape tool in EditorState, as EditorModel.swift has them: a
// handle drag redraws the stroke in place and is one undo step; undo puts the handles away; the
// shape tool draws with the last pen.
class EditorStateShapeTest {
    private val black = InkColor(0f, 0f, 0f)

    /** A square stroke 100..200 and its editable shape. */
    private fun square(): Pair<Stroke, EditableShape> {
        val corners = listOf(Pt(100.0, 100.0), Pt(200.0, 100.0), Pt(200.0, 200.0), Pt(100.0, 200.0))
        val pts = (corners + corners.first()).map { InkPoint(it.x.toFloat(), it.y.toFloat(), 2f, 1f) }
        return Pair(Stroke(Brush.PEN, black, 4f, 1.0, 0.2f, pts), EditableShape(EditableShape.Kind.Polygon, corners, ShapeName.SQUARE))
    }

    @Test
    fun aHandleDragRedrawsTheShapeAndIsOneUndoStep() {
        val (stroke, shape) = square()
        val state = EditorState(initialPages = listOf(listOf(stroke)))
        state.startShapeEdit(0, stroke.id, shape)
        assertNotNull(state.shapeEdit)

        state.beginShapeHandleDrag()
        state.moveShapeHandle(2, Pt(230.0, 240.0), snap = 1.0)
        val feedback = state.moveShapeHandle(2, Pt(260.0, 260.0), snap = 1.0)
        assertNotNull(feedback)
        state.endShapeHandleDrag()

        val redrawn = state.strokes(0).single()
        assertNotEquals(stroke.id, redrawn.id)
        assertEquals(redrawn.id, state.shapeEdit!!.strokeId)
        assertEquals(Pt(260.0, 260.0), state.shapeEdit!!.shape.points[2])
        // The redrawn stroke goes through the dragged corner.
        assertTrue(redrawn.points.any { it.x == 260f && it.y == 260f })

        state.undo()
        assertEquals(listOf(stroke), state.strokes(0))
        assertNull(state.shapeEdit)
        assertTrue(state.canRedo)
    }

    @Test
    fun aTouchElsewhereEndsTheEditAndKeepsTheShape() {
        val (stroke, shape) = square()
        val state = EditorState(initialPages = listOf(listOf(stroke)))
        state.startShapeEdit(0, stroke.id, shape)
        state.finishShapeEdit()
        assertNull(state.shapeEdit)
        assertEquals(listOf(stroke), state.strokes(0))
        // A stroke that is not on the page gets no handles.
        state.startShapeEdit(0, -1, shape)
        assertNull(state.shapeEdit)
    }

    @Test
    fun theShapeToolDrawsWithTheLastPenAsOneStep() {
        val state = EditorState(initialPages = listOf(emptyList()))
        state.tool = Tool.Brush(Brush.GOLD)
        state.tool = Tool.Shape
        state.shapeKind = ShapeKind.RECTANGLE
        state.addShape(0, Pt(100.0, 100.0), Pt(200.0, 150.0))
        val drawn = state.strokes(0)
        assertEquals(1, drawn.size)
        assertEquals(Brush.GOLD, drawn[0].brush)
        assertEquals(state.width(Brush.GOLD), drawn[0].width)
        // Dashed: the outline in pieces.
        state.shapeDashed = true
        state.addShape(0, Pt(300.0, 100.0), Pt(400.0, 150.0))
        assertTrue(state.strokes(0).size > 10)
        // A drag of a point or two draws nothing.
        val before = state.strokes(0).size
        state.addShape(0, Pt(10.0, 10.0), Pt(11.0, 11.0))
        assertEquals(before, state.strokes(0).size)
        state.undo()
        assertEquals(1, state.strokes(0).size)
    }
}
