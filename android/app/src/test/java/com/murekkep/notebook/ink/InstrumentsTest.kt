package com.murekkep.notebook.ink

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.sin

// The drafting instruments against the iPad: android/app/src/test/resources/instruments.txt is written
// by tools/instrumentcheck from the iPad's real Instruments.swift (outlines, edges, what an instrument
// covers, its angle in degrees, the edge or protractor ray a pen follows and where its points land).
// The rules the iPad's canvas keeps in CanvasView.swift (the turn settling at 15° steps, the reading
// next to the pen, the compass's arc, fingers carrying and turning an instrument) are checked by hand.
class InstrumentsTest {
    private val cases: List<FixtureCase> by lazy { load() }

    private fun load(): List<FixtureCase> {
        val stream = InstrumentsTest::class.java.getResourceAsStream("/instruments.txt")
            ?: error("instruments.txt is missing from the test resources: run tools/instrumentcheck/run.ps1")
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
        return out
    }

    private fun instrumentOf(c: FixtureCase): Instrument {
        val t = c.first("in").tokens
        val kind = InstrumentKind.fromRaw(t[0]) ?: error("${c.name}: unknown kind ${t[0]}")
        return Instrument(kind, Pt(t[1].toDouble(), t[2].toDouble()), t[3].toDouble())
    }

    @Test
    fun theFixtureHasEveryInstrument() {
        val kinds = cases.filter { it.type == "instrument" }.map { instrumentOf(it).kind }.toSet()
        assertEquals(InstrumentKind.entries.toSet(), kinds)
    }

    @Test
    fun outlinesEdgesAndAnglesAreTheIpads() {
        for (c in cases.filter { it.type == "instrument" }) {
            val ins = instrumentOf(c)
            Same.points("${c.name}: local outline", c.first("local").points(), ins.localOutline)
            Same.points("${c.name}: outline", c.first("outline").points(), ins.outline)
            val edges = c.first("edges").points()
            assertEquals("${c.name}: edges", edges.size / 2, ins.edges.size)
            for ((i, e) in ins.edges.withIndex()) {
                Same.point("${c.name}: edge $i start", edges[2 * i], e.first)
                Same.point("${c.name}: edge $i end", edges[2 * i + 1], e.second)
            }
            assertEquals("${c.name}: degrees", c.first("degrees").value.toInt(), ins.degrees)
        }
    }

    @Test
    fun aPenFollowsTheEdgeOrRayTheIpadsDoes() {
        var probes = 0
        var followed = 0
        for (c in cases.filter { it.type == "instrument" }) {
            val ins = instrumentOf(c)
            val tolerance = c.first("tolerance").value.toDouble()
            var probe: Pt? = null
            var snap: EdgeSnap? = null
            for (r in c.records) {
                when (r.key) {
                    "probe" -> {
                        probe = r.points()[0]
                        probes++
                    }
                    "contains" -> assertEquals("${c.name}: contains $probe", r.value == "1", ins.contains(probe!!))
                    "tolocal" -> Same.point("${c.name}: toLocal $probe", r.points()[0], ins.toLocal(probe!!))
                    "todoc" -> Same.point("${c.name}: toDocument $probe", r.points()[0], ins.toDocument(probe!!))
                    "dist" -> {
                        val d = r.doubles()
                        for ((i, e) in ins.edges.withIndex()) {
                            Same.value("${c.name}: distance of $probe to edge $i", d[i], EdgeSnap.distance(probe!!, e.first, e.second))
                        }
                    }
                    "snap" -> {
                        snap = EdgeSnap.find(ins, probe!!, tolerance)
                        if (r.value.isEmpty()) {
                            assertNull("${c.name}: nothing to follow at $probe", snap)
                        } else {
                            val d = r.doubles()
                            val s = snap ?: error("${c.name}: the iPad follows an edge at $probe, the port nothing")
                            Same.point("${c.name}: snap start at $probe", Pt(d[0], d[1]), s.a)
                            Same.point("${c.name}: snap end at $probe", Pt(d[2], d[3]), s.b)
                            assertEquals("${c.name}: ray at $probe", d[4] == 1.0, s.isRay)
                        }
                    }
                    "start" -> Same.point("${c.name}: where the pen starts from $probe", r.points()[0], snap!!.project(probe!!))
                    "follow" -> {
                        val (q, landed) = r.points()
                        Same.point("${c.name}: $q followed from $probe", landed, snap!!.project(q))
                        followed++
                    }
                }
            }
        }
        assertTrue("probes read ($probes)", probes > 400)
        assertTrue("points followed ($followed)", followed > 500)
    }

    @Test
    fun theAngleShownIsTheIpads() {
        val c = cases.single { it.type == "degrees" }
        val angles = c.first("angles").doubles()
        val values = c.first("values").tokens.map { it.toInt() }
        for ((i, a) in angles.withIndex()) {
            assertEquals("degrees of $a", values[i], Instrument(InstrumentKind.RULER, Pt.ZERO, a).degrees)
        }
    }

    @Test
    fun aPresetTurnsCounterclockwiseOnPaper() {
        for (d in Instrument.PRESET_DEGREES) {
            assertEquals(d, Instrument(InstrumentKind.RULER, Pt.ZERO, Instrument.angleFor(d.toDouble())).degrees)
        }
        // 30° counterclockwise: the ruler's right end rises (y down).
        val ruler = Instrument(InstrumentKind.RULER, Pt(100.0, 100.0), Instrument.angleFor(30.0))
        val right = ruler.toDocument(Pt(10.0, 0.0))
        assertTrue(right.y < 100.0 && right.x > 100.0)
    }

    // MARK: Turning with two fingers

    @Test
    fun aTurnSettlesWithinOnePointSixDegreesOfAFifteenDegreeStep() {
        fun deg(d: Double) = d * PI / 180
        val (a, step) = InstrumentDrag.settleTurn(deg(14.0))
        assertEquals(15, step)
        Same.value("14° settles at 15°", deg(15.0), a)
        assertEquals(Pair(deg(13.0), null), InstrumentDrag.settleTurn(deg(13.0)))
        assertEquals(-45, InstrumentDrag.settleTurn(deg(-43.5)).second)
        assertNull(InstrumentDrag.settleTurn(deg(-43.3)).second)
        assertEquals(0, InstrumentDrag.settleTurn(deg(1.5)).second)
        assertEquals(375, InstrumentDrag.settleTurn(deg(374.0)).second)
    }

    @Test
    fun oneFingerCarriesTheInstrument() {
        val start = Instrument(InstrumentKind.RULER, Pt(300.0, 400.0), 0.0)
        val drag = InstrumentDrag(start)
        drag.down(7, Pt(250.0, 400.0))
        assertFalse(drag.move(mapOf(7 to Pt(270.0, 390.0))))
        assertEquals(Instrument(InstrumentKind.RULER, Pt(320.0, 390.0), 0.0), drag.instrument)
        assertFalse(drag.isTurning)
    }

    @Test
    fun twoFingersTurnItAndItClicksAtEachStepOnce() {
        val start = Instrument(InstrumentKind.SET_SQUARE_45, Pt(300.0, 400.0), 0.0)
        val drag = InstrumentDrag(start)
        drag.down(1, Pt(200.0, 400.0))
        drag.down(2, Pt(400.0, 400.0))
        assertTrue(drag.isTurning)
        // The fingers turn 14° about their middle: the turn settles at 15° and clicks.
        fun at(deg: Double): Map<Int, Pt> {
            val a = deg * PI / 180
            return mapOf(1 to Pt(300 - 100 * cos(a), 400 - 100 * sin(a)), 2 to Pt(300 + 100 * cos(a), 400 + 100 * sin(a)))
        }
        assertTrue(drag.move(at(14.0)))
        Same.value("settled", 15 * PI / 180, drag.instrument.angle)
        assertEquals(15, drag.settled)
        // Still within the step: no second click.
        assertFalse(drag.move(at(15.5)))
        // Past it the turn follows the fingers.
        assertFalse(drag.move(at(20.0)))
        Same.value("free", 20 * PI / 180, drag.instrument.angle)
        assertNull(drag.settled)
        // The middle stayed where it was: the instrument did not move.
        Same.point("center", Pt(300.0, 400.0), drag.instrument.center)
        // Turned 20° clockwise on screen: counterclockwise on paper is 160°.
        assertEquals(160, drag.instrument.degrees)
    }

    @Test
    fun aFingerLiftedLeavesTheInstrumentWhereItIs() {
        val drag = InstrumentDrag(Instrument(InstrumentKind.PROTRACTOR, Pt(300.0, 400.0), 0.0))
        drag.down(1, Pt(250.0, 400.0))
        drag.down(2, Pt(350.0, 400.0))
        drag.move(mapOf(1 to Pt(250.0, 420.0), 2 to Pt(350.0, 420.0)))
        Same.point("both carried it", Pt(300.0, 420.0), drag.instrument.center)
        drag.up(1)
        assertFalse(drag.isTurning)
        val before = drag.instrument
        // The finger left carries it on from where it is, without a jump.
        drag.move(mapOf(2 to Pt(355.0, 425.0)))
        Same.point("carried on", Pt(before.center.x + 5, before.center.y + 5), drag.instrument.center)
        Same.value("not turned", before.angle, drag.instrument.angle)
        drag.up(2)
        assertTrue(drag.isEmpty)
    }

    @Test
    fun aTurnStartsAgainFromWhereTheInstrumentIs() {
        val drag = InstrumentDrag(Instrument(InstrumentKind.RULER, Pt(0.0, 0.0), 0.0))
        drag.down(1, Pt(-100.0, 0.0))
        drag.down(2, Pt(100.0, 0.0))
        drag.move(mapOf(1 to Pt(0.0, -100.0), 2 to Pt(0.0, 100.0)))
        assertEquals(90, drag.settled)
        drag.up(2)
        drag.down(3, Pt(50.0, 50.0))
        // The new pair starts its turn from 90°; turning it 30° more lands at 120°.
        val a = atan2(50.0 - (-100.0), 50.0 - 0.0) + 30 * PI / 180
        val r = hypot(150.0, 50.0)
        drag.move(mapOf(1 to Pt(0.0, -100.0), 3 to Pt(r * cos(a), -100 + r * sin(a))))
        assertEquals(120, drag.settled)
    }

    // MARK: Reading next to the pen

    @Test
    fun alongAnEdgeThePenReadsTheLengthDrawn() {
        val ruler = Instrument(InstrumentKind.RULER, Pt(300.0, 400.0), 0.0)
        val snap = EdgeSnap.find(ruler, Pt(200.0, 370.0), 18.0)
        assertNotNull(snap)
        val start = snap!!.project(Pt(200.0, 370.0))
        val (at, reading) = snap.reading(ruler, start, Pt(200.0 + 120 * POINTS_PER_MILLIMETRE, 365.0))
        Same.point("on the edge", Pt(200.0 + 120 * POINTS_PER_MILLIMETRE, ruler.edges[0].first.y), at)
        assertEquals("12 cm", reading.format(','))
        val (_, short) = snap.reading(ruler, start, Pt(200.0 + 42.34 * POINTS_PER_MILLIMETRE, 370.0))
        assertEquals("42,3 mm", short.format(','))
        assertEquals("42.3 mm", short.format('.'))
    }

    @Test
    fun onAProtractorsRayThePenReadsItsAngle() {
        val protractor = Instrument(InstrumentKind.PROTRACTOR, Pt(300.0, 400.0), 0.0)
        val snap = EdgeSnap.find(protractor, Pt(305.0, 398.0), 18.0)!!
        assertTrue(snap.isRay)
        // 30° up from the base, on paper; the ray holds whole degrees (29.7° reads 30°).
        val a = 29.7 * PI / 180
        val (at, reading) = snap.reading(protractor, snap.a, Pt(300 + 100 * cos(a), 400 - 100 * sin(a)))
        assertEquals(InstrumentReading.Angle(30), reading)
        assertEquals("30°", reading.format())
        Same.value("on the 30° ray", 30.0, atan2(400 - at.y, at.x - 300) * 180 / PI, 1e-9)
        // Below the base it reads past 180.
        val (_, below) = snap.reading(protractor, snap.a, Pt(300.0 - 50, 400.0 + 50))
        assertEquals(InstrumentReading.Angle(225), below)
    }

    // MARK: The compass

    @Test
    fun aPenFarFromTheCenterSwingsAnArc() {
        val c = CompassState(0, Pt(100.0, 100.0), 50.0)
        assertTrue(Compass.startsArc(c, 0, Pt(100.0, 115.0), 14.0))
        // Near the center, or on another page, it sets a new center.
        assertFalse(Compass.startsArc(c, 0, Pt(110.0, 105.0), 14.0))
        assertFalse(Compass.startsArc(c, 1, Pt(100.0, 115.0), 14.0))
        assertFalse(Compass.startsArc(null, 0, Pt(100.0, 115.0), 14.0))
    }

    @Test
    fun theArcStartsOnTheCircleAndFollowsThePenEveryTwoDegrees() {
        val c = CompassState(0, Pt(100.0, 100.0), 50.0)
        // The pen comes down 20 points right of the center: the arc starts on the circle there.
        val arc = CompassArc(c, Pt(120.0, 100.0))
        Same.points("first", listOf(Pt(150.0, 100.0)), arc.points)
        // Turned 89° down (y down): 45 even steps, none longer than 2°.
        val a = 89 * PI / 180
        arc.swing(Pt(100 + 80 * cos(a), 100 + 80 * sin(a)))
        assertEquals(46, arc.points.size)
        for (p in arc.points) Same.value("on the circle", 50.0, hypot(p.x - 100, p.y - 100), 1e-9)
        Same.point("last", Pt(100 + 50 * cos(a), 100 + 50 * sin(a)), arc.points.last())
        for (i in 1 until arc.points.size) {
            val step = atan2(arc.points[i].y - 100, arc.points[i].x - 100) - atan2(arc.points[i - 1].y - 100, arc.points[i - 1].x - 100)
            Same.value("an even step", a / 45, step, 1e-12)
        }
        // A tiny move still adds a point.
        arc.swing(Pt(99.9, 180.0))
        assertEquals(47, arc.points.size)
    }

    @Test
    fun theArcGoesRoundTheShortWayPastHalfATurn() {
        val c = CompassState(0, Pt(0.0, 0.0), 10.0)
        val arc = CompassArc(c, Pt(-10.0, 0.1))
        // From just below the left (y down: +179.4°) to just above it (-179.4°): 1.1° the short way,
        // not 358.9° the long way.
        arc.swing(Pt(-10.0, -0.1))
        assertEquals(2, arc.points.size)
        assertTrue(abs(arc.points.last().x + 10.0) < 0.01)
    }

    @Test
    fun aShortDragSetsNoCompass() {
        assertNull(Compass.set(0, Pt(10.0, 10.0), Pt(12.0, 12.0)))
        assertEquals(CompassState(2, Pt(10.0, 10.0), 5.0), Compass.set(2, Pt(10.0, 10.0), Pt(13.0, 14.0)))
    }
}
