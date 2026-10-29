package com.murekkep.notebook.ui

import com.murekkep.notebook.data.InkSettings
import com.murekkep.notebook.ink.Brush
import com.murekkep.notebook.ink.GrassGenerator
import com.murekkep.notebook.ink.InkColor
import com.murekkep.notebook.ink.InkPoint
import com.murekkep.notebook.ink.Pt
import com.murekkep.notebook.ink.Stroke
import com.murekkep.notebook.ink.Vec2
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

// The ink's settings in EditorState as AppSettings has them on iPad: the custom colours picked
// lately, the drying and cooling times, and the grass's flower level, which every new grass stroke
// carries in its seed (drawn, given to a selection or drawn as a shape).
class EditorStateInkSettingsTest {
    @Test
    fun recentColoursNewestFirstEightKept() {
        val state = EditorState()
        val colors = (1..10).map { InkColor.hex(it * 0x101010) }
        colors.forEach(state::rememberColor)
        assertEquals(colors.takeLast(8).reversed(), state.recentColors)
        state.rememberColor(colors[5])
        assertEquals(colors[5], state.recentColors.first())
        assertEquals(8, state.recentColors.toSet().size)
    }

    @Test
    fun theTimesTheInkTakesToDryAndCoolAskForAFrame() {
        // The canvas hands them to the renderer with every frame: ink drying or cooling on the page
        // follows a change at once, as the iPad's canvas reads them live.
        val state = EditorState()
        var frames = 0
        state.onInkChange = { frames++ }
        state.dryDuration = 8f
        assertEquals(1, frames)
        state.coolDuration = 12f
        assertEquals(2, frames)
        state.dryDuration = 8f
        assertEquals(2, frames)
        assertEquals(8f, state.dryDuration)
        assertEquals(12f, state.coolDuration)
    }

    @Test
    fun theInkSettingsStartAtTheIpadsDefaults() {
        val ink = InkSettings()
        assertTrue(ink.animations)
        assertFalse(ink.batterySaver)
        assertTrue(ink.straightLine)
        assertEquals(4f, ink.dryDuration)
        assertEquals(6f, ink.coolDuration)
        assertEquals(1, ink.flowerLevel)
        assertEquals(38f, ink.nibAngle)
    }

    @Test
    fun ayarlarAndTheEditorShareOneSetOfInkSettings() {
        val state = EditorState()
        var frames = 0
        state.onInkChange = { frames++ }
        // Ayarlar › 3B mürekkep writes the shared settings; the editor reads them back at once (its
        // screen asks the canvas for a frame).
        state.ink.animations = false
        state.ink.dryDuration = 9f
        state.ink.flowerLevel = 2
        assertFalse(state.animations)
        assertEquals(9f, state.dryDuration)
        assertEquals(2, GrassGenerator.flowerLevel(state.newSeed(Brush.GRASS)))
        // A pen's popover and Diğer write through the editor; Ayarlar shows the same values.
        state.batterySaver = true
        state.coolDuration = 11f
        state.straightLine = false
        assertTrue(state.ink.batterySaver)
        assertEquals(11f, state.ink.coolDuration)
        assertFalse(state.ink.straightLine)
        assertEquals(2, frames)
    }

    @Test
    fun newGrassStrokesFlowerAsSetSomeByDefault() {
        val state = EditorState()
        assertEquals(1, GrassGenerator.flowerLevel(state.newSeed(Brush.GRASS)))
        state.flowerLevel = 2
        assertEquals(2, GrassGenerator.flowerLevel(state.newSeed(Brush.GRASS)))
        state.flowerLevel = 0
        assertEquals(0, GrassGenerator.flowerLevel(state.newSeed(Brush.GRASS)))
        assertTrue(state.newSeed(Brush.PEN) < 1f)
    }

    @Test
    fun aShapeDrawnWithTheGrassPenCarriesTheLevel() {
        val state = EditorState(initialPages = listOf(emptyList()))
        state.tool = Tool.Brush(Brush.GRASS)
        state.flowerLevel = 2
        state.addShape(0, Pt(10.0, 10.0), Pt(120.0, 10.0))
        val stroke = state.strokes(0).single()
        assertEquals(Brush.GRASS, stroke.brush)
        assertEquals(2, GrassGenerator.flowerLevel(stroke.seed))
    }

    @Test
    fun grassGivenToASelectionCarriesTheLevel() {
        val line = Stroke(Brush.PEN, InkColor(0f, 0f, 0f), 2f, 1.0, 0.2f, (0..20).map { InkPoint(100f + it * 5f, 100f, 1f, 0.5f) })
        val state = EditorState(initialPages = listOf(listOf(line)))
        // The last pen picked is what the selection is given.
        state.tool = Tool.Brush(Brush.GRASS)
        state.tool = Tool.Lasso
        assertTrue(state.selectItem(0, Vec2(150f, 100f), 8f))
        state.restyleSelection()
        val grass = state.strokes(0).single()
        assertEquals(Brush.GRASS, grass.brush)
        assertEquals(1, GrassGenerator.flowerLevel(grass.seed))
    }
}
