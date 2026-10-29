package com.murekkep.notebook.ink

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import kotlin.math.abs
import kotlin.math.max

// The fixture android/app/src/test/resources/shapes.txt, written by tools/shapecheck from the iPad's
// real Swift shape code (ShapeRecognizer.swift, ShapeEditing.swift, Instruments.swift,
// StrokeBuilder.swift) over deterministic hand-drawn strokes. The shape tests read it and hold the
// Kotlin ports to its kinds, names, labels and points, within 1e-6.
//
// Lines are "key value…" grouped in "case <type> <name>" … "end"; a "shape" line starts a block
// (shape, spoints, soval or scurve, handles, middle, and spath once per shape) describing an
// EditableShape.

class FixtureRecord(val key: String, val value: String) {
    val tokens: List<String> get() = if (value.isEmpty()) emptyList() else value.split(' ')

    fun doubles(): DoubleArray = tokens.map { it.toDouble() }.toDoubleArray()

    fun floats(): FloatArray = tokens.map { it.toFloat() }.toFloatArray()

    fun points(): List<Pt> {
        val d = doubles()
        return List(d.size / 2) { Pt(d[2 * it], d[2 * it + 1]) }
    }

    fun vecs(): List<Vec2> {
        val v = floats()
        return List(v.size / 2) { Vec2(v[2 * it], v[2 * it + 1]) }
    }

    fun inkPoints(): List<InkPoint> {
        val v = floats()
        return List(v.size / 4) { InkPoint(v[4 * it], v[4 * it + 1], v[4 * it + 2], v[4 * it + 3]) }
    }
}

class FixtureCase(val type: String, val name: String, val records: List<FixtureRecord>) {
    fun first(key: String): FixtureRecord = records.firstOrNull { it.key == key } ?: error("$name: no $key")

    fun all(key: String): List<FixtureRecord> = records.filter { it.key == key }
}

/** One EditableShape as the fixture writes it. */
class ShapeBlock(
    val kind: String,
    val title: String,
    val points: List<Pt>,
    val oval: DoubleArray?,
    val curve: DoubleArray?,
    val handles: List<Pt>,
    val middle: Pt,
    val path: List<Pt>?,
) {
    /** The port's shape must be this one. */
    fun check(what: String, shape: EditableShape) {
        val kindName = when (shape.kind) {
            EditableShape.Kind.Polygon -> "polygon"
            EditableShape.Kind.Polyline -> "polyline"
            is EditableShape.Kind.Oval -> "oval"
            is EditableShape.Kind.Curve -> "curve"
        }
        assertEquals("$what: kind", kind, kindName)
        assertEquals("$what: title", title, shape.name.titleTr)
        Same.points("$what: points", points, shape.points)
        val o = oval
        if (o != null) {
            val k = shape.kind as EditableShape.Kind.Oval
            Same.point("$what: oval center", Pt(o[0], o[1]), k.center)
            Same.value("$what: oval rx", o[2], k.rx)
            Same.value("$what: oval ry", o[3], k.ry)
            Same.value("$what: oval angle", o[4], k.angle)
        }
        val c = curve
        if (c != null) {
            val k = shape.kind as EditableShape.Kind.Curve
            Same.point("$what: curve start", Pt(c[0], c[1]), k.curve.start)
            Same.point("$what: curve control", Pt(c[2], c[3]), k.curve.control)
            Same.point("$what: curve end", Pt(c[4], c[5]), k.curve.end)
        }
        Same.points("$what: handles", handles, shape.handles)
        Same.point("$what: middle", middle, shape.middle)
        val p = path
        if (p != null) Same.points("$what: path", p, shape.path())
    }

    companion object {
        /** Reads the block that starts at `records[start]` (a "shape" line); returns it and the index after it. */
        fun parse(records: List<FixtureRecord>, start: Int): Pair<ShapeBlock, Int> {
            var i = start
            val head = records[i++]
            check(head.key == "shape") { "a shape block starts with shape, not ${head.key}" }
            val kind = head.value.substringBefore(' ')
            val title = head.value.substringAfter(' ')
            var points: List<Pt> = emptyList()
            var oval: DoubleArray? = null
            var curve: DoubleArray? = null
            var handles: List<Pt> = emptyList()
            var middle = Pt.ZERO
            var path: List<Pt>? = null
            while (i < records.size) {
                val r = records[i]
                when (r.key) {
                    "spoints" -> points = r.points()
                    "soval" -> oval = r.doubles()
                    "scurve" -> curve = r.doubles()
                    "handles" -> handles = r.points()
                    "middle" -> middle = r.points()[0]
                    "spath" -> path = r.points()
                    else -> break
                }
                i++
            }
            return Pair(ShapeBlock(kind, title, points, oval, curve, handles, middle, path), i)
        }
    }
}

object ShapeFixture {
    val cases: List<FixtureCase> by lazy { load() }

    fun cases(type: String): List<FixtureCase> = cases.filter { it.type == type }

    private fun load(): List<FixtureCase> {
        val stream = ShapeFixture::class.java.getResourceAsStream("/shapes.txt")
            ?: error("shapes.txt is missing from the test resources: run tools/shapecheck/run.ps1")
        val out = ArrayList<FixtureCase>()
        var type = ""
        var name = ""
        var records = ArrayList<FixtureRecord>()
        stream.bufferedReader(Charsets.UTF_8).useLines { lines ->
            for (line in lines) {
                if (line.isEmpty() || line.startsWith("#")) continue
                val space = line.indexOf(' ')
                val key = if (space < 0) line else line.substring(0, space)
                val value = if (space < 0) "" else line.substring(space + 1)
                when (key) {
                    "case" -> {
                        type = value.substringBefore(' ')
                        name = value.substringAfter(' ')
                        records = ArrayList()
                    }
                    "end" -> out.add(FixtureCase(type, name, records))
                    else -> records.add(FixtureRecord(key, value))
                }
            }
        }
        assertTrue("the fixture has cases", out.isNotEmpty())
        return out
    }
}

/** The fixture's comparisons: within 1e-6, naming the case and what differs. */
object Same {
    const val TOL = 1e-6

    fun value(what: String, expected: Double, actual: Double, tol: Double = TOL) {
        if (!(abs(expected - actual) <= tol)) fail("$what: expected $expected, got $actual")
    }

    fun point(what: String, expected: Pt, actual: Pt, tol: Double = TOL) {
        if (!(abs(expected.x - actual.x) <= tol && abs(expected.y - actual.y) <= tol)) {
            fail("$what: expected $expected, got $actual")
        }
    }

    fun points(what: String, expected: List<Pt>, actual: List<Pt>, tol: Double = TOL) {
        assertEquals("$what: count", expected.size, actual.size)
        for (i in expected.indices) point("$what[$i]", expected[i], actual[i], tol)
    }

    fun vec(what: String, expected: Vec2, actual: Vec2, tol: Double = TOL) {
        if (!(abs(expected.x - actual.x) <= tol && abs(expected.y - actual.y) <= tol)) {
            fail("$what: expected $expected, got $actual")
        }
    }

    fun vecs(what: String, expected: List<Vec2>, actual: List<Vec2>, tol: Double = TOL) {
        assertEquals("$what: count", expected.size, actual.size)
        for (i in expected.indices) vec("$what[$i]", expected[i], actual[i], tol)
    }

    /**
     * Float paths that went through `cos` and `sin` in Float: the Swift toolchain's `cosf` and the
     * JVM's `Math.cos` round their last bit differently now and then (the iPad's own libm does too),
     * and a last bit of a cosine times a radius of 250 moves a point by 1.5e-5. So these coordinates
     * are held to eight Float ulps of the path's size instead of 1e-6, which is under one ulp of any
     * coordinate past 16.
     */
    fun floatVecs(what: String, expected: List<Vec2>, actual: List<Vec2>) {
        assertEquals("$what: count", expected.size, actual.size)
        var size = 1f
        for (e in expected) size = max(size, max(abs(e.x), abs(e.y)))
        val tol = max(TOL, (8 * Math.ulp(size)).toDouble())
        for (i in expected.indices) vec("$what[$i]", expected[i], actual[i], tol)
    }

    fun ink(what: String, expected: List<InkPoint>, actual: List<InkPoint>, tol: Double = TOL) {
        assertEquals("$what: count", expected.size, actual.size)
        for (i in expected.indices) {
            val e = expected[i]
            val a = actual[i]
            if (!(abs(e.x - a.x) <= tol && abs(e.y - a.y) <= tol && abs(e.r - a.r) <= tol && abs(e.ink - a.ink) <= tol)) {
                fail("$what[$i]: expected $e, got $a")
            }
        }
    }
}
