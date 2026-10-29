package com.murekkep.notebook.ink

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt

// `smoothed` is checked as tests/test_dense_paths.py checks its Python twin (tests/ports/ribbon.py);
// the mesh layout follows RibbonBuilder.swift and the GL table in android/PORTING.md.
class RibbonBuilderTest {
    private val floats = RibbonBuilder.FLOATS_PER_VERTEX

    /** Element by element within 1e-6 (a negated zero offset is still zero). */
    private fun assertFloats(expected: List<Float>, actual: List<Float>) {
        assertEquals(expected.size, actual.size)
        for (i in expected.indices) {
            assertEquals("element $i of $actual", expected[i], actual[i], 1e-6f)
        }
    }

    /** `StrokeText.strokes` as tests/ports/ribbon.py ports it: straight pieces filled in. */
    private fun strokePoints(path: List<Pair<Float, Float>>, width: Float): List<InkPoint> {
        val r = max(width * 0.5f, 0.35f)
        val spacing = max(0.6f, r * 0.5f)
        val out = ArrayList<InkPoint>()
        for (i in path.indices) {
            val (x, y) = path[i]
            out.add(InkPoint(x, y, r, 0f))
            if (i + 1 < path.size) {
                val (nx, ny) = path[i + 1]
                val n = (hypot(nx - x, ny - y) / spacing).toInt()
                for (k in 1 until n) {
                    val t = k.toFloat() / n
                    out.add(InkPoint(x + (nx - x) * t, y + (ny - y) * t, r, 0f))
                }
            }
        }
        return out
    }

    private fun octagon(radius: Double = 60.0, cx: Double = 100.0, cy: Double = 100.0): List<Pair<Float, Float>> {
        val pts = (0 until 8).map {
            Pair((cx + radius * cos(2 * PI * it / 8)).toFloat(), (cy + radius * sin(2 * PI * it / 8)).toFloat())
        }
        return pts + pts[0]
    }

    private fun distanceToPolygon(p: InkPoint, poly: List<Pair<Float, Float>>): Float {
        var best = Float.POSITIVE_INFINITY
        for (i in 0 until poly.size - 1) {
            val (ax, ay) = poly[i]
            val (bx, by) = poly[i + 1]
            val dx = bx - ax
            val dy = by - ay
            val l2 = dx * dx + dy * dy
            val t = if (l2 == 0f) 0f else max(0f, min(1f, ((p.x - ax) * dx + (p.y - ay) * dy) / l2))
            best = min(best, hypot(p.x - ax - t * dx, p.y - ay - t * dy))
        }
        return best
    }

    private fun maxDeviation(width: Float): Float {
        val poly = octagon()
        val drawn = RibbonBuilder.smoothed(strokePoints(poly, width))
        return drawn.maxOf { distanceToPolygon(it, poly) }
    }

    @Test
    fun anOctagonWithThePenKeepsItsSides() {
        assertTrue(maxDeviation(2.2f) < 0.6f)
    }

    @Test
    fun anOctagonWithThickInkKeepsItsSides() {
        assertTrue(maxDeviation(12f) < 0.6f)
    }

    @Test
    fun smoothedKeepsShortInputsAndStartsAtTheFirstPoint() {
        val two = listOf(InkPoint(0f, 0f, 1f, 1f), InkPoint(10f, 0f, 1f, 1f))
        assertEquals(two, RibbonBuilder.smoothed(two))
        assertTrue(RibbonBuilder.smoothed(emptyList()).isEmpty())
        val three = listOf(InkPoint(0f, 0f, 1f, 0f), InkPoint(10f, 0f, 2f, 0.5f), InkPoint(20f, 0f, 3f, 1f))
        val curve = RibbonBuilder.smoothed(three)
        assertEquals(three[0], curve.first())
        // Straight segments of 10 points with step max(0.5, 0.45 * min r): 10 / 0.5 = 20 samples, then
        // ceil(10 / 0.9) = 12.
        assertEquals(1 + 20 + 12, curve.size)
        assertEquals(20f, curve.last().x, 1e-4f)
        assertEquals(3f, curve.last().r, 1e-5f)
        assertEquals(1f, curve.last().ink, 1e-5f)
        assertTrue(curve.all { it.y == 0f })
        assertTrue(curve.zipWithNext().all { (a, b) -> b.x > a.x })
    }

    @Test
    fun aDotIsTwoCaps() {
        val out = RibbonOut()
        RibbonBuilder.append(listOf(InkPoint(5f, 6f, 2f, 0.8f)), stroke = 7, relax = false, out = out)
        assertEquals(24, out.vertexCount)
        assertEquals(60, out.indexCount)
        assertEquals(24 * 48, out.vertexBytes)
        val v = out.vertices
        // The centre vertex: centre (5, 6), no offset, tangent (1, 0), r 2, u 0, side 0, arc 0, ink 0.8, slot 7.
        assertFloats(listOf(5f, 6f, 0f, 0f, 1f, 0f, 2f, 0f, 0f, 0f, 0.8f), v.slice(0 until 11))
        assertEquals(7, v[11].toRawBits())
        // The rim runs from the left edge (0, 1) over the tip (1, 0) to the right edge (0, -1).
        assertEquals(0f, v[floats + 2], 1e-6f)
        assertEquals(1f, v[floats + 3], 1e-6f)
        assertEquals(1f, v[6 * floats + 2], 1e-6f)
        assertEquals(0f, v[6 * floats + 3], 1e-6f)
        assertEquals(0f, v[11 * floats + 2], 1e-6f)
        assertEquals(-1f, v[11 * floats + 3], 1e-6f)
        for (k in 0 until out.vertexCount) {
            assertEquals(7, v[k * floats + 11].toRawBits())
        }
        for (i in 0 until out.indexCount) {
            assertTrue(out.indices[i] in 0 until out.vertexCount)
        }
        // The first triangle fans from the centre.
        assertEquals(listOf(0, 1, 2), out.indices.slice(0 until 3))
        assertEquals(listOf(0, 10, 11), out.indices.slice(27 until 30))
        assertEquals(listOf(12, 13, 14), out.indices.slice(30 until 33))
    }

    @Test
    fun aStraightLineIsRowsOfThreeAndTwoCaps() {
        val out = RibbonOut(vertexCapacity = 1, indexCapacity = 1)
        val line = listOf(InkPoint(0f, 0f, 1f, 0.5f), InkPoint(10f, 0f, 1f, 0.5f))
        RibbonBuilder.append(line, stroke = 3, relax = true, out = out)
        // Two rows of three, then a cap of 12 at each end.
        assertEquals(6 + 24, out.vertexCount)
        assertEquals(12 + 60, out.indexCount)
        val v = out.vertices
        // Left edge, centreline, right edge of the first row.
        assertFloats(listOf(0f, 0f, 0f, 1f, 1f, 0f, 1f, 1f, 1f, 0f, 0.5f), v.slice(0 until 11))
        assertFloats(listOf(0f, 0f, 0f, 0f, 1f, 0f, 1f, 0f, 0f, 0f, 0.5f), v.slice(floats until floats + 11))
        assertFloats(listOf(0f, 0f, 0f, -1f, 1f, 0f, 1f, -1f, -1f, 0f, 0.5f), v.slice(2 * floats until 2 * floats + 11))
        // The second row sits at the end of the line, 10 points along the arc.
        assertEquals(10f, v[3 * floats], 0f)
        assertEquals(10f, v[3 * floats + 9], 1e-6f)
        assertEquals(3, v[3 * floats + 11].toRawBits())
        // The strip: c0 l0 l1, c0 l1 c1, c0 r1 r0, c0 c1 r1.
        assertEquals(listOf(1, 0, 3, 1, 3, 4, 1, 5, 2, 1, 4, 5), out.indices.slice(0 until 12))
        // The start cap faces backwards (its tip at -x), the end cap forwards.
        assertEquals(-1f, v[(6 + 6) * floats + 2], 1e-6f)
        assertEquals(1f, v[(18 + 6) * floats + 2], 1e-6f)
        for (i in 0 until out.indexCount) {
            assertTrue(out.indices[i] in 0 until out.vertexCount)
        }
    }

    @Test
    fun strokesAppendAfterEachOtherWithAbsoluteIndices() {
        val out = RibbonOut()
        RibbonBuilder.append(listOf(InkPoint(0f, 0f, 1f, 1f), InkPoint(10f, 0f, 1f, 1f)), 0, false, out)
        val firstVertices = out.vertexCount
        val firstIndices = out.indexCount
        RibbonBuilder.append(listOf(InkPoint(0f, 20f, 1f, 1f), InkPoint(10f, 20f, 1f, 1f)), 1, false, out)
        assertEquals(2 * firstVertices, out.vertexCount)
        assertEquals(2 * firstIndices, out.indexCount)
        for (i in firstIndices until out.indexCount) {
            assertTrue(out.indices[i] in firstVertices until out.vertexCount)
        }
        assertEquals(0, out.vertices[11].toRawBits())
        assertEquals(1, out.vertices[firstVertices * floats + 11].toRawBits())
        // Nothing to append leaves the mesh as it is.
        RibbonBuilder.append(emptyList(), 2, false, out)
        assertEquals(2 * firstVertices, out.vertexCount)
        out.clear()
        assertEquals(0, out.vertexCount)
        assertEquals(0, out.indexCount)
        RibbonBuilder.append(listOf(InkPoint(0f, 0f, 1f, 1f), InkPoint(10f, 0f, 1f, 1f)), 5, false, out)
        assertEquals(firstVertices, out.vertexCount)
        assertEquals(1, out.indices[0])
    }

    @Test
    fun aSharpTurnGetsAFanOfRowsAndTheArraysGrow() {
        val out = RibbonOut(vertexCapacity = 4, indexCapacity = 4)
        val corner = listOf(InkPoint(0f, 0f, 3f, 1f), InkPoint(20f, 0f, 3f, 1f), InkPoint(20f, 20f, 3f, 1f))
        RibbonBuilder.append(corner, 0, false, out)
        val straight = RibbonOut()
        RibbonBuilder.append(listOf(InkPoint(0f, 0f, 3f, 1f), InkPoint(20f, 0f, 3f, 1f), InkPoint(40f, 0f, 3f, 1f)), 0, false, straight)
        assertTrue(out.vertexCount > straight.vertexCount)
        assertTrue(out.vertices.size >= out.vertexCount * floats)
        assertTrue(out.indices.size >= out.indexCount)
        for (i in 0 until out.indexCount) {
            assertTrue(out.indices[i] in 0 until out.vertexCount)
        }
        // Every row's tangent is a unit vector and its centre lies on or near the corner's two legs.
        for (k in 0 until out.vertexCount) {
            val tx = out.vertices[k * floats + 4]
            val ty = out.vertices[k * floats + 5]
            assertEquals(1f, sqrt(tx * tx + ty * ty), 1e-4f)
        }
        // The arc grows monotonically along the rows (the caps come after them).
        val rows = (out.vertexCount - 24) / 3
        for (i in 1 until rows) {
            assertTrue(out.vertices[i * 3 * floats + 9] >= out.vertices[(i - 1) * 3 * floats + 9])
        }
        // The straight line's last row is at the end of its 40 points; its two caps follow.
        val straightRows = (straight.vertexCount - 24) / 3
        assertEquals(31, straightRows)
        assertEquals(40f, straight.vertices[(straightRows - 1) * 3 * floats + 9], 1e-3f)
        assertEquals(40f, straight.vertices[(straightRows - 1) * 3 * floats], 1e-3f)
    }

    @Test
    fun thickInkBendsThroughACornerThinInkKeepsIt() {
        fun corner(r: Float): List<InkPoint> {
            val pts = ArrayList<InkPoint>()
            for (i in 0..20) pts.add(InkPoint(i.toFloat(), 0f, r, 1f))
            for (i in 1..20) pts.add(InkPoint(20f, i.toFloat(), r, 1f))
            return pts
        }
        val thick = RibbonBuilder.relaxed(corner(5f))
        val thin = RibbonBuilder.relaxed(corner(1f))
        // The ends stay where they were drawn.
        assertEquals(0f, thick.first().x, 1e-4f)
        assertEquals(0f, thick.first().y, 1e-4f)
        assertEquals(20f, thick.last().x, 1e-4f)
        assertEquals(20f, thick.last().y, 1e-4f)
        assertTrue(thick.all { it.r == 5f && it.ink == 1f })
        // The thick corner is pulled inside the bend, the thin one hardly moves.
        val bent = thick[20]
        assertTrue("corner moved to $bent", bent.x < 20f - 1f && bent.y > 1f)
        val kept = thin[20]
        assertTrue(hypot(kept.x - 20f, kept.y) < 0.01f)
        assertEquals(41, thick.size)
        // Short inputs are returned as they are.
        val two = listOf(InkPoint(0f, 0f, 5f, 1f), InkPoint(9f, 9f, 5f, 1f))
        assertEquals(two, RibbonBuilder.relaxed(two))
    }
}
