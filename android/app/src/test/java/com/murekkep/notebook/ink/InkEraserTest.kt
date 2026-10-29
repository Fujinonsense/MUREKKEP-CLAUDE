package com.murekkep.notebook.ink

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs
import kotlin.math.sqrt

// InkEraser has no check in tools/swiftcheck; these are the iPad numbers worked out by hand.
class InkEraserTest {
    private val black = InkColor(0f, 0f, 0f)

    /** A pen line along y = 0 from x = 0 to 100, a point every 10, radius 2. */
    private fun line() = Stroke(Brush.PEN, black, 4f, 0.0, 0f, (0..10).map { InkPoint(it * 10f, 0f, 2f, 1f) })

    @Test
    fun pointToSegmentDistance() {
        assertEquals(1f, InkEraser.distance(Vec2(0f, 1f), Vec2(-1f, 0f), Vec2(1f, 0f)), 1e-6f)
        assertEquals(2f, InkEraser.distance(Vec2(3f, 0f), Vec2(-1f, 0f), Vec2(1f, 0f)), 1e-6f)
        // A segment of no length is a point.
        assertEquals(sqrt(18f), InkEraser.distance(Vec2(5f, 5f), Vec2(2f, 2f), Vec2(2f, 2f)), 1e-6f)
    }

    @Test
    fun segmentToSegmentDistance() {
        assertEquals(1f, InkEraser.distance(Vec2(0f, 0f), Vec2(10f, 0f), Vec2(0f, 1f), Vec2(10f, 1f)), 1e-6f)
        assertEquals(0f, InkEraser.distance(Vec2(0f, 0f), Vec2(10f, 10f), Vec2(0f, 10f), Vec2(10f, 0f)), 1e-6f)
        assertEquals(4f, InkEraser.distance(Vec2(0f, 0f), Vec2(1f, 0f), Vec2(5f, 0f), Vec2(6f, 0f)), 1e-6f)
        assertEquals(5f, InkEraser.distance(Vec2(1f, 1f), Vec2(1f, 1f), Vec2(4f, 5f), Vec2(4f, 5f)), 1e-6f)
        assertEquals(3f, InkEraser.distance(Vec2(0f, 0f), Vec2(0f, 0f), Vec2(-5f, 3f), Vec2(5f, 3f)), 1e-6f)
        assertEquals(3f, InkEraser.distance(Vec2(-5f, 3f), Vec2(5f, 3f), Vec2(0f, 0f), Vec2(0f, 0f)), 1e-6f)
    }

    @Test
    fun theEraserHitsAStrokeWithinItsRadiusAndEightTenthsOfTheInk() {
        val s = line()
        // 10 points above the line: 5 + 2 * 0.8 does not reach, 9 + 1.6 does.
        assertFalse(InkEraser.hits(s, Vec2(50f, 10f), Vec2(50f, 10f), 5f))
        assertTrue(InkEraser.hits(s, Vec2(50f, 10f), Vec2(50f, 10f), 9f))
        // A moving eraser crossing the line.
        assertTrue(InkEraser.hits(s, Vec2(50f, 30f), Vec2(50f, -30f), 1f))
        // Far away: the boxes do not meet.
        assertFalse(InkEraser.hits(s, Vec2(500f, 500f), Vec2(600f, 500f), 20f))
    }

    @Test
    fun aDotIsHitWithinTheRadiusAndItsWholeInk() {
        val dot = Stroke(Brush.PEN, black, 4f, 0.0, 0f, listOf(InkPoint(50f, 0f, 2f, 1f)))
        assertTrue(InkEraser.hits(dot, Vec2(50f, 6f), Vec2(50f, 6f), 4f))
        assertFalse(InkEraser.hits(dot, Vec2(50f, 6f), Vec2(50f, 6f), 3f))
        val empty = Stroke(Brush.PEN, black, 4f, 0.0, 0f, emptyList())
        assertFalse(InkEraser.hits(empty, Vec2(0f, 0f), Vec2(0f, 0f), 100f))
    }

    @Test
    fun thePartialEraserCutsTheLineInTwo() {
        val s = line()
        val pieces = requireNotNull(InkEraser.erase(s, Vec2(50f, 0f), Vec2(50f, 0f), 5f))
        assertEquals(2, pieces.size)
        // Points within 5 + 2 * 0.5 of the eraser go; the line is densified every 10 / 6 points first.
        assertEquals(43.333f, pieces[0].points.last().x, 0.01f)
        assertEquals(56.667f, pieces[1].points.first().x, 0.01f)
        assertEquals(27, pieces[0].points.size)
        assertEquals(27, pieces[1].points.size)
        assertEquals(0f, pieces[0].points.first().x, 0f)
        assertEquals(100f, pieces[1].points.last().x, 0f)
        for (piece in pieces) {
            assertTrue(piece.points.all { abs(it.x - 50f) > 6f && it.y == 0f && it.r == 2f })
            assertEquals(s.brush, piece.brush)
            assertEquals(s.color, piece.color)
            assertEquals(s.width, piece.width, 0f)
            assertEquals(s.seed, piece.seed, 0f)
            assertTrue(piece.id != s.id)
        }
    }

    @Test
    fun anUntouchedStrokeStaysNull() {
        val s = line()
        // The boxes do not meet.
        assertNull(InkEraser.erase(s, Vec2(50f, 20f), Vec2(50f, 20f), 5f))
        // The boxes meet, no point is within reach.
        assertNull(InkEraser.erase(s, Vec2(50f, 9f), Vec2(50f, 9f), 5f))
    }

    @Test
    fun aStrokeErasedWholeLeavesNoPieces() {
        val s = Stroke(Brush.PEN, black, 2f, 0.0, 0f, listOf(InkPoint(0f, 0f, 1f, 1f), InkPoint(3f, 0f, 1f, 1f)))
        val pieces = InkEraser.erase(s, Vec2(1.5f, 0f), Vec2(1.5f, 0f), 5f)
        assertNotNull(pieces)
        assertTrue(pieces!!.isEmpty())
    }

    @Test
    fun aPieceNeedsTwoPoints() {
        // Densified every 0.5 points; only the last point is further than 1.2 + 0.5 from the eraser: no piece.
        val s = Stroke(Brush.PEN, black, 2f, 0.0, 0f, listOf(InkPoint(0f, 0f, 1f, 1f), InkPoint(2f, 0f, 1f, 1f)))
        val pieces = InkEraser.erase(s, Vec2(0f, 0f), Vec2(0f, 0f), 1.2f)
        assertNotNull(pieces)
        assertTrue(pieces!!.isEmpty())
    }

    @Test
    fun densifyFillsInEvenlySpacedPoints() {
        val dense = InkEraser.densify(listOf(InkPoint(0f, 0f, 1f, 0f), InkPoint(10f, 0f, 3f, 1f)), 3f)
        assertEquals(5, dense.size)
        assertEquals(listOf(0f, 2.5f, 5f, 7.5f, 10f), dense.map { it.x })
        assertEquals(listOf(1f, 1.5f, 2f, 2.5f, 3f), dense.map { it.r })
        assertEquals(listOf(0f, 0.25f, 0.5f, 0.75f, 1f), dense.map { it.ink })
        val one = listOf(InkPoint(4f, 4f, 1f, 1f))
        assertEquals(one, InkEraser.densify(one, 3f))
        val two = listOf(InkPoint(0f, 0f, 1f, 1f), InkPoint(1f, 0f, 1f, 1f))
        assertEquals(two, InkEraser.densify(two, 0f))
        assertEquals(two, InkEraser.densify(two, 3f))
    }

    @Test
    fun theEraserModesKeepTheirTitles() {
        assertEquals("Tüm çizgi", EraserMode.STROKE.titleTr)
        assertEquals("Whole stroke", EraserMode.STROKE.titleEn)
        assertEquals("Kısmi", EraserMode.PARTIAL.titleTr)
        assertEquals("Partial", EraserMode.PARTIAL.titleEn)
        assertEquals(listOf(EraserMode.STROKE, EraserMode.PARTIAL), EraserMode.entries.toList())
    }
}
