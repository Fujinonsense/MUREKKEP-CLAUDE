package com.murekkep.notebook.ui

import com.murekkep.notebook.ink.Brush
import com.murekkep.notebook.ink.InkColor
import com.murekkep.notebook.ink.InkPoint
import com.murekkep.notebook.ink.Stroke
import com.murekkep.notebook.ink.Vec2
import com.murekkep.notebook.render.PageLayout
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

// The lasso's edits in EditorState as EditorModel.swift makes them: a drag is one undo step, a
// selection dropped over another page moves there (one step for both pages), and delete,
// duplicate and restyle each are one step.
class EditorStateLassoTest {
    private val black = InkColor(0f, 0f, 0f)

    private fun line(x0: Float, y: Float, x1: Float) =
        Stroke(Brush.PEN, black, 4f, 1.0, 0.2f, (0..10).map { InkPoint(x0 + (x1 - x0) * it / 10f, y, 2f, 1f) })

    private fun loop(x0: Float, y0: Float, x1: Float, y1: Float) =
        listOf(Vec2(x0, y0), Vec2(x1, y0), Vec2(x1, y1), Vec2(x0, y1))

    private fun lasso(state: EditorState) = state.also { it.tool = Tool.Lasso }

    @Test
    fun aLoopSelectsAndADragIsOneUndoStep() {
        val a = line(100f, 100f, 200f)
        val b = line(100f, 400f, 200f)
        val state = lasso(EditorState(initialPages = listOf(listOf(a, b))))
        assertTrue(state.selectStrokes(0, loop(50f, 50f, 250f, 150f)))
        assertEquals(setOf(a.id), state.selection!!.ids)

        state.beginSelectionEdit()
        state.transformSelection(Vec2(10f, 0f), 1f, Vec2.ZERO)
        state.transformSelection(Vec2(30f, 20f), 1f, Vec2.ZERO)
        // While dragging the selection bar's selection stays; the frame follows the live one.
        assertEquals(setOf(a.id), state.selection!!.ids)
        assertEquals(130f + 0f - 2f, state.displayedSelection!!.bounds.minX)
        state.endSelectionEdit()

        val moved = state.strokes(0).single { it.id != b.id }
        assertEquals(130f, moved.points.first().x)
        assertEquals(120f, moved.points.first().y)
        assertEquals(setOf(moved.id), state.selection!!.ids)
        assertNull(state.liveSelection)

        state.undo()
        assertEquals(listOf(a, b), state.strokes(0))
        assertNull(state.selection)
        assertFalse(state.canUndo)
        state.redo()
        assertEquals(130f, state.strokes(0).single { it.id != b.id }.points.first().x)
    }

    @Test
    fun aSelectionDroppedOverTheNextPageMovesThere() {
        val a = line(100f, 800f, 200f)
        val state = lasso(EditorState(initialPages = listOf(listOf(a), emptyList())))
        assertEquals(2, state.pages.size)
        assertTrue(state.selectStrokes(0, loop(50f, 780f, 250f, 820f)))
        state.beginSelectionEdit()
        // 120 points down: its middle is past the gap, on page 1.
        state.transformSelection(Vec2(0f, 120f), 1f, Vec2.ZERO)
        state.endSelectionEdit()

        val layout = PageLayout(2)
        assertTrue(state.strokes(0).isEmpty())
        val carried = state.strokes(1).single()
        // The same place on the document, now in page 1's own points.
        assertEquals(800f + 120f - (layout.top(1) - layout.top(0)), carried.points.first().y, 1e-3f)
        assertEquals(1, state.selection!!.page)
        // Ink on the last page brings a blank one after it.
        assertEquals(3, state.pages.size)

        state.undo()
        assertEquals(listOf(a), state.strokes(0))
        assertTrue(state.strokes(1).isEmpty())
        assertNull(state.selection)
    }

    @Test
    fun deleteDuplicateAndApplyInkAreOneStepEach() {
        val a = line(100f, 100f, 200f)
        val state = lasso(EditorState(initialPages = listOf(listOf(a))))
        assertTrue(state.selectItem(0, Vec2(150f, 101f), 4f))

        state.duplicateSelection()
        assertEquals(2, state.strokes(0).size)
        val copy = state.strokes(0)[1]
        assertEquals(118f, copy.points.first().x)
        assertEquals(118f, copy.points.first().y)
        assertEquals(setOf(copy.id), state.selection!!.ids)

        state.setColor(Brush.GOLD, state.color(Brush.GOLD))
        state.tool = Tool.Brush(Brush.GOLD)
        state.tool = Tool.Lasso
        assertNull(state.selection)
        assertTrue(state.selectItem(0, Vec2(150f, 101f), 4f))
        state.restyleSelection()
        val gold = state.strokes(0).last()
        assertEquals(Brush.GOLD, gold.brush)
        assertEquals(a.points, gold.points)
        assertTrue(gold.birth > a.birth)

        state.deleteSelection()
        assertNull(state.selection)
        assertEquals(listOf(copy), state.strokes(0))
        state.undo()
        assertEquals(2, state.strokes(0).size)
    }

    @Test
    fun aMissedLoopOrTapSelectsNothing() {
        val state = lasso(EditorState(initialPages = listOf(listOf(line(100f, 100f, 200f)))))
        assertFalse(state.selectStrokes(0, loop(300f, 300f, 400f, 400f)))
        assertNull(state.selection)
        assertFalse(state.selectItem(0, Vec2(150f, 300f), 4f))
        assertNotNull(state.pages)
    }
}
