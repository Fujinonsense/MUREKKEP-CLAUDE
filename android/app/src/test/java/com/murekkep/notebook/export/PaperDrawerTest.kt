package com.murekkep.notebook.export

import com.murekkep.notebook.data.PaperStyle
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Test

// The template geometry of Templates.swift on an A4 page (595.28 x 841.89 points).
class PaperDrawerTest {
    private val w = 595.28f
    private val h = 841.89f

    @Test
    fun linedPaperRulesEvery28PointsFrom84DownToEightAboveTheFoot() {
        val rules = PaperDrawer.positions(PaperDrawer.RULE_TOP, h - PaperDrawer.RULE_FOOT, PaperDrawer.RULE_SPACING)
        assertEquals(27, rules.size)
        assertEquals(84f, rules.first(), 0f)
        assertEquals(812f, rules.last(), 0f)
        assertEquals(28f, rules[1] - rules[0], 0f)
        assertEquals(72f, PaperDrawer.MARGIN_X, 0f)
    }

    @Test
    fun gridAndDotsStartAtThePagesCornerEvery20PointsAndStayOnThePage() {
        val columns = PaperDrawer.positions(0f, w, PaperDrawer.GRID_STEP)
        val rows = PaperDrawer.positions(0f, h, PaperDrawer.GRID_STEP)
        assertEquals(30, columns.size)
        assertEquals(580f, columns.last(), 0f)
        assertEquals(43, rows.size)
        assertEquals(840f, rows.last(), 0f)
        assertEquals(PaperDrawer.GRID_STEP, PaperDrawer.DOT_STEP, 0f)
        assertEquals(0.9f, PaperDrawer.DOT_RADIUS, 0f)
    }

    @Test
    fun theLastPositionMayLandExactlyOnTheEnd() {
        assertArrayEquals(floatArrayOf(0f, 20f, 40f, 60f), PaperDrawer.positions(0f, 60f, 20f), 0f)
        assertArrayEquals(floatArrayOf(), PaperDrawer.positions(10f, 5f, 20f), 0f)
        assertArrayEquals(floatArrayOf(), PaperDrawer.positions(0f, 60f, 0f), 0f)
    }

    @Test
    fun theFourTemplatesExportAsThemselvesEveryOtherAsLined() {
        for (style in listOf(PaperStyle.PLAIN, PaperStyle.LINED, PaperStyle.GRID, PaperStyle.DOTTED)) {
            assertEquals(style, PaperDrawer.exported(style))
        }
        for (style in PaperStyle.entries) {
            if (style !in listOf(PaperStyle.PLAIN, PaperStyle.GRID, PaperStyle.DOTTED)) {
                assertEquals(PaperStyle.LINED, PaperDrawer.exported(style))
            }
        }
    }
}
