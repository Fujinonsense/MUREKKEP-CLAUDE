package com.murekkep.notebook.canvas

import android.view.InputDevice
import android.view.MotionEvent
import androidx.activity.ComponentActivity
import com.murekkep.notebook.ink.Brush
import com.murekkep.notebook.ink.Instrument
import com.murekkep.notebook.ink.InstrumentKind
import com.murekkep.notebook.ink.Pt
import com.murekkep.notebook.ui.EditorState
import com.murekkep.notebook.ui.Tool
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.ConscryptMode
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.sin

// The canvas's touches with a drafting instrument and the compass, as the iPad's CanvasView routes
// them: a finger on an instrument carries it and draws nothing, two turn it (settling at 15°, the
// angle shown over it); a pen starting by an edge draws along it; the compass's first drag sets
// its center and radius, the next draws an arc of that radius; a tap draws nothing.
@RunWith(RobolectricTestRunner::class)
// Android 10: Jetpack's motion predictor runs its own Kalman filter there and finds the display
// through the window manager, which Robolectric's contexts have.
@Config(sdk = [29], qualifiers = "w1280dp-h800dp-mdpi")
@ConscryptMode(ConscryptMode.Mode.OFF)
class InstrumentInputTest {
    private lateinit var state: EditorState
    private lateinit var canvas: InkCanvasView
    private var overlay: CanvasOverlay? = null
    private var time = 1000L

    @Before
    fun canvas() {
        state = EditorState()
        // An activity's context: the motion predictor reads its display's refresh rate.
        val activity = Robolectric.buildActivity(ComponentActivity::class.java).setup().get()
        canvas = InkCanvasView(activity, state)
        canvas.onOverlay = { overlay = it }
        canvas.layout(0, 0, 1280, 800)
    }

    @After
    fun release() {
        canvas.release()
    }

    private fun field(name: String): Float = InkCanvasView::class.java.getDeclaredField(name).let {
        it.isAccessible = true
        it.getFloat(canvas)
    }

    private val zoom get() = field("zoom")

    /** A document point in view pixels. */
    private fun view(p: Pt): Pair<Float, Float> = Pair(field("originX") + p.x.toFloat() * zoom, field("originY") + p.y.toFloat() * zoom)

    private fun touch(action: Int, tool: Int, pointers: List<Pair<Int, Pt>>, index: Int = 0) {
        val props = pointers.map { (id, _) ->
            MotionEvent.PointerProperties().apply {
                this.id = id
                toolType = tool
            }
        }.toTypedArray()
        val coords = pointers.map { (_, p) ->
            val (x, y) = view(p)
            MotionEvent.PointerCoords().apply {
                this.x = x
                this.y = y
                pressure = 0.5f
                size = 0.1f
            }
        }.toTypedArray()
        val masked = if (action == MotionEvent.ACTION_POINTER_DOWN || action == MotionEvent.ACTION_POINTER_UP) {
            action or (index shl MotionEvent.ACTION_POINTER_INDEX_SHIFT)
        } else {
            action
        }
        val source = if (tool == MotionEvent.TOOL_TYPE_STYLUS) InputDevice.SOURCE_STYLUS else InputDevice.SOURCE_TOUCHSCREEN
        val event = MotionEvent.obtain(1000L, time, masked, pointers.size, props, coords, 0, 0, 1f, 1f, 0, 0, source, 0)
        time += 8
        canvas.onTouchEvent(event)
        event.recycle()
    }

    private fun finger(action: Int, vararg pointers: Pair<Int, Pt>, index: Int = 0) =
        touch(action, MotionEvent.TOOL_TYPE_FINGER, pointers.toList(), index)

    /** A pen stroke through [points] (document points). */
    private fun pen(vararg points: Pt) {
        touch(MotionEvent.ACTION_DOWN, MotionEvent.TOOL_TYPE_STYLUS, listOf(0 to points.first()))
        for (p in points.drop(1)) touch(MotionEvent.ACTION_MOVE, MotionEvent.TOOL_TYPE_STYLUS, listOf(0 to p))
        touch(MotionEvent.ACTION_UP, MotionEvent.TOOL_TYPE_STYLUS, listOf(0 to points.last()))
    }

    private fun ruler(): Instrument {
        state.showInstrument(InstrumentKind.RULER)
        return state.instrument!!
    }

    @Test
    fun aFingerOnTheRulerCarriesItAndDrawsNothing() {
        val start = ruler()
        val c = start.center
        finger(MotionEvent.ACTION_DOWN, 0 to c)
        finger(MotionEvent.ACTION_MOVE, 0 to Pt(c.x + 30, c.y + 12))
        finger(MotionEvent.ACTION_MOVE, 0 to Pt(c.x + 60, c.y + 24))
        finger(MotionEvent.ACTION_UP, 0 to Pt(c.x + 60, c.y + 24))
        val moved = state.instrument!!
        assertEquals(c.x + 60, moved.center.x, 0.01)
        assertEquals(c.y + 24, moved.center.y, 0.01)
        assertEquals(0.0, moved.angle, 1e-9)
        // A finger draws on a tablet whose pen has not been seen, but never on an instrument.
        assertTrue(state.strokes(0).isEmpty())
        // Off the ruler the same finger draws.
        finger(MotionEvent.ACTION_DOWN, 0 to Pt(100.0, 700.0))
        finger(MotionEvent.ACTION_MOVE, 0 to Pt(140.0, 720.0))
        finger(MotionEvent.ACTION_UP, 0 to Pt(180.0, 740.0))
        assertEquals(1, state.strokes(0).size)
    }

    @Test
    fun twoFingersTurnItSettlingAtFifteenDegrees() {
        val c = ruler().center
        fun at(deg: Double): Array<Pair<Int, Pt>> {
            val a = deg * PI / 180
            return arrayOf(0 to Pt(c.x - 100 * cos(a), c.y - 100 * sin(a)), 1 to Pt(c.x + 100 * cos(a), c.y + 100 * sin(a)))
        }
        finger(MotionEvent.ACTION_DOWN, at(0.0)[0])
        finger(MotionEvent.ACTION_POINTER_DOWN, *at(0.0), index = 1)
        for (d in 1..14) finger(MotionEvent.ACTION_MOVE, *at(d.toDouble()))
        // 14° clockwise on screen settles at 15°: 165° counterclockwise as on paper, shown over it.
        assertEquals(15 * PI / 180, state.instrument!!.angle, 1e-9)
        assertEquals("165°", overlay?.instrument?.label)
        finger(MotionEvent.ACTION_POINTER_UP, *at(14.0), index = 1)
        assertNull(overlay?.instrument?.label)
        finger(MotionEvent.ACTION_UP, at(14.0)[0])
        assertEquals(c.x, state.instrument!!.center.x, 0.01)
        assertEquals(c.y, state.instrument!!.center.y, 0.01)
        assertTrue(state.strokes(0).isEmpty())
    }

    @Test
    fun aPenStartingByTheEdgeDrawsAlongIt() {
        val ruler = ruler()
        val (a, b) = ruler.edges[0]
        // 3 points over the top edge, then wandering 8 points off it either way.
        val y = a.y
        pen(Pt(a.x + 40, y - 3), Pt(a.x + 120, y - 8), Pt(a.x + 200, y + 8), Pt(a.x + 300, y - 2))
        val stroke = state.strokes(0).single()
        for (p in stroke.points) assertEquals("on the edge", y, p.y.toDouble(), 0.02)
        assertTrue(stroke.points.first().x < a.x + 45 && stroke.points.last().x > a.x + 295)
        assertTrue(b.x > a.x)
    }

    @Test
    fun aTouchTheSystemTakesBackPutsTheInstrumentBack() {
        val start = ruler()
        val c = start.center
        finger(MotionEvent.ACTION_DOWN, 0 to c)
        finger(MotionEvent.ACTION_MOVE, 0 to Pt(c.x + 40, c.y + 40))
        assertEquals(c.x + 40, state.instrument!!.center.x, 0.01)
        // A palm, say.
        finger(MotionEvent.ACTION_CANCEL, 0 to Pt(c.x + 40, c.y + 40))
        assertEquals(start, state.instrument)
    }

    @Test
    fun fromTheProtractorsCenterThePenReadsTheRaysAngle() {
        state.showInstrument(InstrumentKind.PROTRACTOR)
        val c = state.instrument!!.center
        val a = 29.7 * PI / 180
        val out = Pt(c.x + 120 * cos(a), c.y - 120 * sin(a))
        touch(MotionEvent.ACTION_DOWN, MotionEvent.TOOL_TYPE_STYLUS, listOf(0 to Pt(c.x + 2, c.y - 1)))
        touch(MotionEvent.ACTION_MOVE, MotionEvent.TOOL_TYPE_STYLUS, listOf(0 to Pt(c.x + 60 * cos(a), c.y - 60 * sin(a))))
        touch(MotionEvent.ACTION_MOVE, MotionEvent.TOOL_TYPE_STYLUS, listOf(0 to out))
        assertEquals("30°", overlay?.label?.text)
        touch(MotionEvent.ACTION_UP, MotionEvent.TOOL_TYPE_STYLUS, listOf(0 to out))
        // The line runs out from the center along the 30° ray.
        val last = state.strokes(0).single().points.last()
        assertEquals(30.0, kotlin.math.atan2(c.y - last.y, last.x - c.x) * 180 / PI, 0.05)
        assertNull(overlay?.label)
    }

    @Test
    fun aPenFarFromTheInstrumentDrawsFreely() {
        ruler()
        pen(Pt(100.0, 700.0), Pt(150.0, 760.0), Pt(200.0, 700.0))
        val ys = state.strokes(0).single().points.map { it.y }
        assertTrue(ys.maxOrNull()!! - ys.minOrNull()!! > 30)
    }

    @Test
    fun theCompassSetsItsRadiusThenDrawsArcs() {
        state.tool = Tool.Brush(Brush.PENCIL)
        state.tool = Tool.Compass
        // The first drag: the center and the radius.
        pen(Pt(200.0, 300.0), Pt(230.0, 340.0), Pt(260.0, 380.0))
        val set = state.compass
        assertNotNull(set)
        assertEquals(200.0, set!!.center.x, 0.01)
        assertEquals(300.0, set.center.y, 0.01)
        assertEquals(100.0, set.radius, 0.01)
        assertNotNull(overlay?.compass)
        assertTrue(state.strokes(0).isEmpty())
        // A tap away from the center draws nothing.
        pen(Pt(300.0, 300.0))
        assertTrue(state.strokes(0).isEmpty())
        // The next drag swings an arc of that radius, in the last pen's ink.
        pen(Pt(320.0, 300.0), Pt(290.0, 360.0), Pt(200.0, 420.0))
        val arc = state.strokes(0).single()
        assertEquals(Brush.PENCIL, arc.brush)
        for (p in arc.points) assertEquals(100.0, hypot(p.x - 200.0, p.y - 300.0), 0.01)
        // From 0° to 90° (y down), a point every 2° at most.
        assertTrue(arc.points.size >= 46)
        assertEquals(300f, arc.points.first().x, 0.01f)
        assertEquals(400f, arc.points.last().y, 0.01f)
        // The compass stays set for the next arc; another tool puts it away.
        assertNotNull(state.compass)
        state.tool = Tool.Lasso
        assertNull(state.compass)
        assertNull(overlay?.compass)
    }

    @Test
    fun aDragTooShortSetsNoCompass() {
        state.tool = Tool.Compass
        pen(Pt(200.0, 300.0), Pt(201.0, 301.0))
        assertNull(state.compass)
    }
}
