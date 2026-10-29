package com.murekkep.notebook.ui

import com.murekkep.notebook.ink.Brush
import com.murekkep.notebook.ink.CompassState
import com.murekkep.notebook.ink.Instrument
import com.murekkep.notebook.ink.InstrumentKind
import com.murekkep.notebook.ink.Pt
import com.murekkep.notebook.ink.Vec2
import com.murekkep.notebook.render.PageLayout
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

// The drafting instruments and the compass in EditorState, as EditorModel.swift has them: an
// instrument is laid where the view's middle is, takes another kind where it lies, turns to a
// round angle and goes; the compass's setting goes with its tool; an arc is a stroke in the last
// pen's ink, one undo step.
class EditorStateInstrumentTest {
    @Test
    fun anInstrumentLiesWhereTheViewsMiddleIs() {
        val state = EditorState(initialPages = listOf(emptyList(), emptyList()))
        state.viewCenter = Pair(1, Vec2(200f, 300f))
        var frames = 0
        state.onInkChange = { frames++ }
        state.showInstrument(InstrumentKind.RULER)
        val layout = PageLayout(state.pageCount)
        val expected = layout.toDoc(1, 200f, 300f)
        assertEquals(Instrument(InstrumentKind.RULER, Pt(expected.x.toDouble(), expected.y.toDouble()), 0.0), state.instrument)
        assertEquals(InstrumentKind.RULER, state.instrumentKind)
        // The canvas draws it: a change asks for a frame.
        assertEquals(1, frames)
    }

    @Test
    fun withoutAViewItLiesAcrossTheFirstPage() {
        val state = EditorState()
        state.showInstrument(InstrumentKind.PROTRACTOR)
        assertEquals(Pt(PageLayout(1).pageWidth / 2.0, 320.0), state.instrument!!.center)
    }

    @Test
    fun anotherKindTakesThePlaceAndTheTurnOfTheOneThere() {
        val state = EditorState()
        state.viewCenter = Pair(0, Vec2(100f, 120f))
        state.showInstrument(InstrumentKind.SET_SQUARE_45)
        state.setInstrumentAngle(30.0)
        val before = state.instrument!!
        assertEquals(30, before.degrees)
        state.viewCenter = Pair(0, Vec2(400f, 700f))
        state.showInstrument(InstrumentKind.PROTRACTOR)
        assertEquals(before.copy(kind = InstrumentKind.PROTRACTOR), state.instrument)
        assertEquals(InstrumentKind.PROTRACTOR, state.instrumentKind)
    }

    @Test
    fun kaldirPutsItAway() {
        val state = EditorState()
        state.showInstrument(InstrumentKind.RULER)
        state.showInstrument(null)
        assertNull(state.instrument)
        assertNull(state.instrumentKind)
        // With nothing on the page an angle turns nothing.
        state.setInstrumentAngle(45.0)
        assertNull(state.instrument)
    }

    @Test
    fun everyPresetAngleReadsAsItself() {
        val state = EditorState()
        state.showInstrument(InstrumentKind.RULER)
        for (d in Instrument.PRESET_DEGREES) {
            state.setInstrumentAngle(d.toDouble())
            assertEquals(d, state.instrument!!.degrees)
        }
    }

    @Test
    fun anotherToolPutsTheCompassSettingAway() {
        val state = EditorState()
        state.tool = Tool.Compass
        state.compass = CompassState(0, Pt(100.0, 100.0), 40.0)
        // The eraser borrowed by the pen's button takes it away too (EditorModel.tool's didSet).
        state.temporaryEraser = true
        assertNull(state.compass)
        state.temporaryEraser = false
        assertEquals(Tool.Compass, state.tool)
        state.compass = CompassState(0, Pt(100.0, 100.0), 40.0)
        state.tool = Tool.Brush(Brush.PENCIL)
        assertNull(state.compass)
    }

    @Test
    fun anInstrumentStaysWhateverTheTool() {
        val state = EditorState()
        state.showInstrument(InstrumentKind.RULER)
        state.tool = Tool.Lasso
        state.tool = Tool.Compass
        assertEquals(InstrumentKind.RULER, state.instrumentKind)
    }

    @Test
    fun anArcIsAStrokeOfTheLastPenAndOneUndoStep() {
        val state = EditorState()
        state.tool = Tool.Brush(Brush.FOUNTAIN)
        state.tool = Tool.Compass
        val points = (0..45).map { i ->
            val a = i * Math.PI / 90
            Pt(100 + 50 * Math.cos(a), 100 + 50 * Math.sin(a))
        }
        state.addArc(0, points)
        val stroke = state.strokes(0).single()
        assertEquals(Brush.FOUNTAIN, stroke.brush)
        assertEquals(state.color(Brush.FOUNTAIN), stroke.color)
        assertEquals(state.width(Brush.FOUNTAIN), stroke.width)
        assertEquals(points.size, stroke.points.size)
        for ((p, q) in points.zip(stroke.points)) {
            assertEquals(p.x.toFloat(), q.x)
            assertEquals(p.y.toFloat(), q.y)
            assertEquals(state.width(Brush.FOUNTAIN) * 0.5f, q.r)
            assertEquals(0.55f, q.ink)
        }
        assertTrue(state.canUndo)
        state.undo()
        assertTrue(state.strokes(0).isEmpty())
    }

    @Test
    fun aSinglePointDrawsNoArc() {
        val state = EditorState()
        state.addArc(0, listOf(Pt(10.0, 10.0)))
        assertTrue(state.strokes(0).isEmpty())
        assertFalse(state.canUndo)
    }
}
