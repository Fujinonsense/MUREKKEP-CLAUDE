package com.murekkep.notebook.ink

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.PI

// The lasso against the iPad's rules (EditorModel.swift selectStrokes, selectItem,
// transformSelection; CanvasView.swift selectionGrab, lassoMoved) and tests/test_lasso_pages.py's
// dash ticks.
class LassoTest {
    private val black = InkColor(0f, 0f, 0f)

    /** A pen stroke through the given x positions on y = 50, radius 2. */
    private fun row(xs: List<Float>, y: Float = 50f) = Stroke(Brush.PEN, black, 4f, 0.0, 0f, xs.map { InkPoint(it, y, 2f, 1f) })

    private val square = listOf(Vec2(0f, 0f), Vec2(100f, 0f), Vec2(100f, 100f), Vec2(0f, 100f))

    @Test
    fun aLoopContainsWhatItGoesRound() {
        assertTrue(Lasso.contains(square, 50f, 50f))
        assertFalse(Lasso.contains(square, 150f, 50f))
        assertFalse(Lasso.contains(square, -1f, 50f))
        assertFalse(Lasso.contains(square.take(2), 50f, 0f))
    }

    @Test
    fun aLoopThatCrossesItselfTakesBothLobes() {
        // A bow tie: both triangles are inside by the nonzero rule, as CGPath.contains fills it.
        val bowTie = listOf(Vec2(0f, 0f), Vec2(100f, 100f), Vec2(100f, 0f), Vec2(0f, 100f))
        assertTrue(Lasso.contains(bowTie, 20f, 50f))
        assertTrue(Lasso.contains(bowTie, 80f, 50f))
        assertFalse(Lasso.contains(bowTie, 50f, 10f))
        // Round twice: still inside.
        assertTrue(Lasso.contains(square + square, 50f, 50f))
    }

    @Test
    fun aStrokeIsTakenWhenAtLeastHalfOfItIsInside() {
        val inside = row((1..9).map { it * 10f })
        val half = row((0..8).map { 55f + it * 10f }) // 5 of 9 inside
        val mostlyOut = row((0..8).map { 65f + it * 10f }) // 4 of 9 inside
        val ids = Lasso.select(listOf(inside, half, mostlyOut), square)
        assertEquals(setOf(inside.id, half.id), ids)
        assertTrue(Lasso.select(listOf(inside), square.take(2)).isEmpty())
    }

    @Test
    fun aLongStrokeIsJudgedOnAboutTwentyFourOfItsPoints() {
        // 100 points, every 4th checked: the first 52 inside the square are 13 of 25.
        val xs = (0 until 100).map { if (it < 52) 50f else 500f }
        val s = Stroke(Brush.PEN, black, 4f, 0.0, 0f, xs.mapIndexed { i, x -> InkPoint(x, 1f + i * 0.5f, 2f, 1f) })
        assertEquals(setOf(s.id), Lasso.select(listOf(s), square))
    }

    @Test
    fun aTapPicksTheTopmostStrokeUnderThePen() {
        val under = row(listOf(0f, 100f))
        val over = Stroke(Brush.PEN, black, 4f, 0.0, 0f, listOf(InkPoint(50f, 0f, 2f, 1f), InkPoint(50f, 100f, 2f, 1f)))
        assertSame(over, Lasso.strokeAt(listOf(under, over), Vec2(50f, 50f), 4f))
        assertSame(under, Lasso.strokeAt(listOf(under, over), Vec2(20f, 52f), 4f))
        assertNull(Lasso.strokeAt(listOf(under, over), Vec2(20f, 80f), 4f))
    }

    @Test
    fun theBoxIsTheSelectedStrokesWithTheirRadius() {
        val a = row(listOf(10f, 20f))
        val b = row(listOf(60f, 90f), y = 70f)
        val box = Lasso.bounds(listOf(a, b), setOf(a.id, b.id))!!
        assertEquals(InkRect(8f, 48f, 92f, 72f), box)
        assertNull(Lasso.bounds(listOf(a), setOf(b.id)))
    }

    @Test
    fun aTouchTurnsResizesMovesOrMissesTheSelection() {
        val box = InkRect(100f, 100f, 200f, 160f)
        // Zoom 2: half a page point per dp. The frame is 4 points out, the turn handle 15 above it.
        val unit = 0.5f
        val turn = Lasso.grab(Vec2(150f, 81f), box, unit)
        assertTrue(turn is SelectionDrag.Rotate)
        assertEquals(Vec2(150f, 130f), (turn as SelectionDrag.Rotate).center)
        // The top left corner of the frame: the bottom right corner of the box stays.
        val corner = Lasso.grab(Vec2(97f, 97f), box, unit)
        assertTrue(corner is SelectionDrag.Scale)
        assertEquals(Vec2(200f, 160f), (corner as SelectionDrag.Scale).anchor)
        val inside = Lasso.grab(Vec2(150f, 140f), box, unit)
        assertEquals(SelectionDrag.Move(Vec2(150f, 140f)), inside)
        assertNull(Lasso.grab(Vec2(260f, 140f), box, unit))
    }

    @Test
    fun aSelectionMovesScalesAndTurns() {
        val s = Stroke(Brush.PEN, black, 4f, 7.0, 0.3f, listOf(InkPoint(10f, 0f, 2f, 0.5f), InkPoint(20f, 0f, 2f, 0.5f)))
        val other = row(listOf(0f, 1f))
        val moved = Lasso.transform(listOf(other, s), setOf(s.id), Vec2(5f, 6f), 1f, Vec2.ZERO, 0f)
        assertSame(other, moved[0])
        assertEquals(listOf(InkPoint(15f, 6f, 2f, 0.5f), InkPoint(25f, 6f, 2f, 0.5f)), moved[1].points)
        assertEquals(7.0, moved[1].birth, 0.0)
        assertEquals(0.3f, moved[1].seed)

        val scaled = Lasso.transform(listOf(s), setOf(s.id), Vec2.ZERO, 2f, Vec2(10f, 0f), 0f)[0]
        assertEquals(listOf(InkPoint(10f, 0f, 4f, 0.5f), InkPoint(30f, 0f, 4f, 0.5f)), scaled.points)
        assertEquals(8f, scaled.width)

        // A quarter turn on a page whose y runs down: right of the anchor goes below it.
        val turned = Lasso.transform(listOf(s), setOf(s.id), Vec2.ZERO, 1f, Vec2.ZERO, (PI / 2).toFloat())[0]
        assertEquals(0f, turned.points[1].x, 1e-4f)
        assertEquals(20f, turned.points[1].y, 1e-4f)
    }

    @Test
    fun aTurnSettlesAtRightAnglesWithinSevenDegrees() {
        fun deg(d: Double) = (d * PI / 180).toFloat()
        val (a, settled) = Lasso.settleTurn(deg(85.0))
        assertEquals(90, settled)
        assertEquals((PI / 2).toFloat(), a, 1e-6f)
        assertNull(Lasso.settleTurn(deg(80.0)).second)
        assertEquals(deg(80.0), Lasso.settleTurn(deg(80.0)).first, 1e-6f)
        assertEquals(0, Lasso.settleTurn(deg(-6.0)).second)
        assertEquals(-180, Lasso.settleTurn(deg(-179.0)).second)
        // More than half a turn wraps round first.
        assertEquals(-90, Lasso.settleTurn(deg(272.0)).second)
    }

    @Test
    fun thePenTicksOncePerDashPeriodOnScreen() {
        // test_lasso_pages.py: a 200 pt loop at zoom 1 ticks once per 10 pt; nothing before 10.
        assertEquals(20, Lasso.dashCount(200f))
        assertEquals(40, Lasso.dashCount(400f))
        assertEquals(0, Lasso.dashCount(9.9f))
    }
}
