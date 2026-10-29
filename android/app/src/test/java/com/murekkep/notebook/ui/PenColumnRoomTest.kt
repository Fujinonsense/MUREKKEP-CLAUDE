package com.murekkep.notebook.ui

import androidx.compose.ui.unit.dp
import com.murekkep.notebook.ink.Brush
import org.junit.Assert.assertEquals
import org.junit.Test

// The pen bar down the right side on a short window (R2-04): its margins above and below give way
// before the tray scrolls, so the pens (the one in hand among them) stay in view.
class PenColumnRoomTest {
    @Test
    fun theWholeBarCountsEveryPenOfTheTray() {
        val state = EditorState()
        // The four pens used first and the eraser: 5 slots of 30, 4 gaps of 4, 4 + 4 at the ends.
        val tray = 5 * 30 + 4 * 4 + 8
        // Grip, undo, redo, every pen, colour, lasso, shapes, Sayfa ekle, three dividers, the fold,
        // the bar's padding and its gaps, then the gap to the tray.
        val rest = 10 * 2 + 16 + 44 * 7 + 13 * 3 + 26 + 2 * 11 + 2
        assertEquals((rest + tray).dp, penColumnLength(state))
        // A favourite adds a slot and the hairline between the favourites and the pens used last.
        state.toggleFavorite(Brush.LAVA)
        assertEquals((rest + tray + 30 + 4 + 7 + 4).dp, penColumnLength(state))
    }

    @Test
    fun aTallCanvasKeepsTheIpadsSixtyAndAShortOneGivesItUp() {
        val bar = 641.dp
        assertEquals(60.dp, columnMargin(900.dp, 0.dp, bar))
        // The emulator's landscape tablet: a 692 dp canvas leaves 25.5 dp above and below.
        assertEquals(25.5.dp, columnMargin(692.dp, 0.dp, bar))
        // Never closer than the bar's 12 dp from the side: the tray scrolls from there.
        assertEquals(12.dp, columnMargin(560.dp, 0.dp, bar))
        // The navigation bar's room is not the bar's.
        assertEquals(12.dp, columnMargin(692.dp, 48.dp, bar))
    }
}
