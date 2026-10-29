package com.murekkep.notebook.canvas

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.opengl.GLSurfaceView
import android.os.Build
import android.view.MotionEvent
import android.view.ScaleGestureDetector
import android.view.Surface
import android.view.SurfaceHolder
import android.view.VelocityTracker
import android.widget.OverScroller
import androidx.input.motionprediction.MotionEventPredictor
import com.murekkep.notebook.ink.Brush
import com.murekkep.notebook.ink.InputSample
import com.murekkep.notebook.ink.Stroke
import com.murekkep.notebook.ink.StrokeBuilder
import com.murekkep.notebook.ink.Vec2
import com.murekkep.notebook.ink.referenceNow
import com.murekkep.notebook.render.ActiveStroke
import com.murekkep.notebook.render.FrameInput
import com.murekkep.notebook.render.InkRenderer
import com.murekkep.notebook.render.PageLayout
import com.murekkep.notebook.ui.EditorState
import com.murekkep.notebook.ui.Tool
import javax.microedition.khronos.egl.EGLConfig
import javax.microedition.khronos.opengles.GL10
import kotlin.math.PI
import kotlin.math.max
import kotlin.math.min
import kotlin.random.Random

// The iPad's CanvasView (Murekkep.swiftpm/CanvasView.swift) on Android: the pages, the pen and
// the fingers. Android pens bring what the Apple Pencil does on iPad, mapped as follows:
// - pressure, tilt (AXIS_TILT) and direction (AXIS_ORIENTATION) drive the stroke builder;
// - the pen's side button (S Pen, USI) is the temporary eraser, as the Pencil Pro's squeeze;
// - an eraser end (TOOL_TYPE_ERASER) erases;
// - once a pen has touched the screen, fingers only move and zoom the pages (palm rejection), and a
//   touch the system cancels as a palm (FLAG_CANCELED) takes its stroke back;
// - pen events come unbatched (requestUnbufferedDispatch) and the line under the tip runs a little
//   ahead of the pen with Jetpack's motion prediction;
// - the screen runs at its highest refresh rate (120 Hz where the tablet has it).
/** A pen hovering over the canvas: where (view pixels) and the radius of what it would draw or erase. */
data class HoverRing(val x: Float, val y: Float, val radius: Float, val erasing: Boolean)

class InkCanvasView(context: Context, private val state: EditorState) : GLSurfaceView(context) {
    private val renderer = InkRenderer()
    @Volatile private var frameInput: FrameInput? = null

    /** Told where a hovering pen is (null when it leaves or touches): the screen draws the ring. */
    var onHover: ((HoverRing?) -> Unit)? = null

    // Where the document is: its origin in view pixels and view pixels per document point.
    private var originX = 0f
    private var originY = 0f
    private var zoom = 1f
    private var fitted = false
    private var fitZoom = 1f

    // The pen.
    private var penPointer = -1
    private var penIsStylus = false
    private var builder: StrokeBuilder? = null
    private var active: ActiveStroke? = null
    private var strokeStart = 0.0
    private var eraserPage: Int? = null
    private var lastEraser: Vec2? = null
    private var temporaryEraser = false
    private var stylusSeen = false
    private val predictor: MotionEventPredictor = MotionEventPredictor.newInstance(this)

    // The fingers.
    private val scaleDetector = ScaleGestureDetector(context, ScaleListener())
    private val scroller = OverScroller(context)
    private var velocity: VelocityTracker? = null
    private var panPointer = -1
    private var lastPanX = 0f
    private var lastPanY = 0f
    private var navigating = false

    init {
        setEGLContextClientVersion(3)
        setEGLConfigChooser(8, 8, 8, 8, 24, 0)
        preserveEGLContextOnPause = true
        setRenderer(object : Renderer {
            override fun onSurfaceCreated(gl: GL10?, config: EGLConfig?) {
                renderer.onSurfaceCreated()
            }

            override fun onSurfaceChanged(gl: GL10?, width: Int, height: Int) {
                renderer.onSurfaceChanged(width, height)
            }

            override fun onDrawFrame(gl: GL10?) {
                val input = frameInput ?: return
                val fps = renderer.drawFrame(input)
                post { setAnimating(fps > 0) }
            }
        })
        renderMode = RENDERMODE_WHEN_DIRTY
        state.onInkChange = { requestFrame() }
        isFocusable = true
    }

    /** The screen is going away: frees the GL resources. */
    fun release() {
        state.onInkChange = null
        queueEvent { renderer.release() }
    }

    // MARK: frames

    private fun requestFrame() {
        val pages = state.pages
        frameInput = FrameInput(
            pages = pages,
            layout = PageLayout(pages.size),
            originX = originX,
            originY = originY,
            zoom = zoom,
            active = active,
            paperStyle = 1,
            animate = true,
        )
        requestRender()
    }

    private fun setAnimating(on: Boolean) {
        val mode = if (on) RENDERMODE_CONTINUOUSLY else RENDERMODE_WHEN_DIRTY
        if (renderMode != mode) renderMode = mode
    }

    override fun surfaceCreated(holder: SurfaceHolder) {
        super.surfaceCreated(holder)
        preferFastestRefresh(holder)
    }

    /** The display's highest refresh rate at the current resolution (120 Hz on ProMotion-like panels). */
    private fun preferFastestRefresh(holder: SurfaceHolder) {
        val activity = findActivity(context) ?: return
        @Suppress("DEPRECATION")
        val display = (if (Build.VERSION.SDK_INT >= 30) activity.display else activity.windowManager.defaultDisplay) ?: return
        val current = display.mode
        val best = display.supportedModes
            .filter { it.physicalWidth == current.physicalWidth && it.physicalHeight == current.physicalHeight }
            .maxByOrNull { it.refreshRate } ?: return
        val params = activity.window.attributes
        if (params.preferredDisplayModeId != best.modeId) {
            params.preferredDisplayModeId = best.modeId
            activity.window.attributes = params
        }
        if (Build.VERSION.SDK_INT >= 30) {
            holder.surface.setFrameRate(best.refreshRate, Surface.FRAME_RATE_COMPATIBILITY_DEFAULT)
        }
    }

    private fun findActivity(c: Context): Activity? {
        var ctx: Context? = c
        while (ctx is ContextWrapper) {
            if (ctx is Activity) return ctx
            ctx = ctx.baseContext
        }
        return null
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        val layout = PageLayout(1)
        val margin = 24f * resources.displayMetrics.density
        val oldFit = fitZoom
        fitZoom = max(0.1f, (w - 2 * margin) / layout.pageWidth)
        if (!fitted) {
            zoom = fitZoom
            originY = margin
            fitted = true
        } else {
            // A turned tablet or a resized window: the same zoom against the page's width (a fitted
            // page stays fitted) and the same spot of the page at the top left.
            val left = docX(0f)
            val top = docY(0f)
            zoom = zoom * fitZoom / oldFit
            originX = -left * zoom
            originY = -top * zoom
        }
        clamp()
        requestFrame()
    }

    // MARK: document geometry

    private fun pageLayout() = PageLayout(state.pages.size)

    private fun clamp() {
        val l = pageLayout()
        val contentW = l.pageWidth * zoom
        originX = if (contentW <= width) (width - contentW) / 2 else min(0f, max(width - contentW, originX))
        val contentH = l.totalHeight * zoom
        val margin = 24f * resources.displayMetrics.density
        val minY = min(margin, height - contentH - margin)
        originY = originY.coerceIn(minY, margin)
    }

    private fun docX(x: Float) = (x - originX) / zoom
    private fun docY(y: Float) = (y - originY) / zoom

    // MARK: hover

    /** A pen above the screen (S Pen, USI) shows the size of its line, or of the eraser while its
     *  side button is held or its eraser end is down, as the Pencil's hover preview on iPad. */
    override fun onHoverEvent(event: MotionEvent): Boolean {
        val tool = event.getToolType(0)
        if (tool != MotionEvent.TOOL_TYPE_STYLUS && tool != MotionEvent.TOOL_TYPE_ERASER) return super.onHoverEvent(event)
        when (event.actionMasked) {
            MotionEvent.ACTION_HOVER_ENTER, MotionEvent.ACTION_HOVER_MOVE -> {
                stylusSeen = true
                val erasing = state.tool is Tool.Eraser || tool == MotionEvent.TOOL_TYPE_ERASER ||
                    event.isButtonPressed(MotionEvent.BUTTON_STYLUS_PRIMARY) ||
                    event.isButtonPressed(MotionEvent.BUTTON_STYLUS_SECONDARY)
                val brush = (state.tool as? Tool.Brush)?.brush ?: state.activeBrush
                val radius = if (erasing) state.eraserSize / 2f else state.width(brush) / 2f
                onHover?.invoke(HoverRing(event.x, event.y, max(radius * zoom, 3f), erasing))
            }
            MotionEvent.ACTION_HOVER_EXIT -> onHover?.invoke(null)
        }
        return true
    }

    // MARK: touches

    override fun onTouchEvent(event: MotionEvent): Boolean {
        predictor.record(event)
        val index = event.actionIndex
        val tool = event.getToolType(index)
        val pen = tool == MotionEvent.TOOL_TYPE_STYLUS || tool == MotionEvent.TOOL_TYPE_ERASER
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN, MotionEvent.ACTION_POINTER_DOWN -> {
                if (pen) {
                    stylusSeen = true
                    onHover?.invoke(null)
                    if (penPointer == -1) {
                        requestUnbufferedDispatch(event)
                        penDown(event, index, stylus = true)
                    }
                    return true
                }
                // A finger: draws only on a device whose pen has not been seen, and only alone.
                if (penPointer != -1 && penIsStylus) return true
                if (!stylusSeen && event.pointerCount == 1 && penPointer == -1 && !navigating) {
                    penDown(event, index, stylus = false)
                    return true
                }
                if (penPointer != -1 && !penIsStylus) cancelPen()
                if (navigating) navigate(event) else startNavigation(event)
            }
            MotionEvent.ACTION_MOVE -> {
                if (penPointer != -1) {
                    val i = event.findPointerIndex(penPointer)
                    if (i >= 0) penMoved(event, i)
                }
                if (navigating) navigate(event)
            }
            MotionEvent.ACTION_POINTER_UP, MotionEvent.ACTION_UP -> {
                val id = event.getPointerId(index)
                if (id == penPointer) {
                    val canceled = Build.VERSION.SDK_INT >= 33 && (event.flags and MotionEvent.FLAG_CANCELED) != 0
                    if (canceled) cancelPen() else penUp(event, index)
                } else if (navigating) {
                    if (event.actionMasked == MotionEvent.ACTION_UP) endNavigation(event) else navigate(event)
                }
            }
            MotionEvent.ACTION_CANCEL -> {
                if (penPointer != -1) cancelPen()
                navigating = false
                velocity?.recycle()
                velocity = null
            }
        }
        return true
    }

    private fun sample(event: MotionEvent, i: Int, h: Int, predicted: Boolean = false): InputSample {
        val x = if (h >= 0) event.getHistoricalX(i, h) else event.getX(i)
        val y = if (h >= 0) event.getHistoricalY(i, h) else event.getY(i)
        val pressure = if (h >= 0) event.getHistoricalPressure(i, h) else event.getPressure(i)
        val tilt = if (h >= 0) event.getHistoricalAxisValue(MotionEvent.AXIS_TILT, i, h) else event.getAxisValue(MotionEvent.AXIS_TILT, i)
        val orientation = if (h >= 0) event.getHistoricalAxisValue(MotionEvent.AXIS_ORIENTATION, i, h)
            else event.getAxisValue(MotionEvent.AXIS_ORIENTATION, i)
        val millis = if (h >= 0) event.getHistoricalEventTime(h) else event.eventTime
        val page = active?.page ?: eraserPage ?: 0
        val top = pageLayout().top(page)
        val stylus = event.getToolType(i) == MotionEvent.TOOL_TYPE_STYLUS || event.getToolType(i) == MotionEvent.TOOL_TYPE_ERASER
        return InputSample(
            x = docX(x),
            y = docY(y) - top,
            // The iPad's raw force scale: a full press is the Pencil's full width, a finger reads as average.
            force = InputSample.force(pressure, stylus),
            timestamp = millis / 1000.0,
            altitude = if (stylus) (PI.toFloat() / 2f - tilt).coerceIn(0f, PI.toFloat() / 2f) else PI.toFloat() / 2f,
            azimuth = if (stylus) orientation - PI.toFloat() / 2f else 0f,
            isPencil = stylus,
            predicted = predicted,
        )
    }

    private fun penDown(event: MotionEvent, i: Int, stylus: Boolean) {
        val x = docX(event.getX(i))
        val y = docY(event.getY(i))
        val l = pageLayout()
        val page = l.pageAt(x, y, tolerance = 24f) ?: return
        penPointer = event.getPointerId(i)
        penIsStylus = stylus
        val sideButton = event.isButtonPressed(MotionEvent.BUTTON_STYLUS_PRIMARY) ||
            event.isButtonPressed(MotionEvent.BUTTON_STYLUS_SECONDARY)
        val eraserEnd = event.getToolType(i) == MotionEvent.TOOL_TYPE_ERASER
        temporaryEraser = stylus && (sideButton || eraserEnd)
        if (state.tool is Tool.Eraser || temporaryEraser) {
            state.temporaryEraser = temporaryEraser
            eraserPage = page
            val p = Vec2(x, y - l.top(page))
            lastEraser = p
            state.beginErase(page)
            state.erase(page, p, p)
            requestFrame()
            return
        }
        val brush: Brush = (state.tool as? Tool.Brush)?.brush ?: state.activeBrush
        val b = StrokeBuilder(brush, state.color(brush), state.width(brush), Random.nextFloat())
        strokeStart = referenceNow()
        active = ActiveStroke(page, brush, b.color, b.width, b.seed, emptyList(), strokeStart)
        b.add(sample(event, i, -1))
        builder = b
        active = ActiveStroke(page, brush, b.color, b.width, b.seed, b.preview(emptyList()), strokeStart)
        requestFrame()
    }

    private fun penMoved(event: MotionEvent, i: Int) {
        val page = eraserPage
        if (page != null) {
            for (h in 0 until event.historySize) erasePoint(page, sample(event, i, h))
            erasePoint(page, sample(event, i, -1))
            return
        }
        val b = builder ?: return
        val a = active ?: return
        for (h in 0 until event.historySize) b.add(sample(event, i, h))
        b.add(sample(event, i, -1))
        val predicted = ArrayList<InputSample>()
        predictor.predict()?.let { p ->
            val pi = p.findPointerIndex(penPointer)
            if (pi >= 0) {
                for (h in 0 until p.historySize) predicted.add(sample(p, pi, h, predicted = true))
                predicted.add(sample(p, pi, -1, predicted = true))
            }
            p.recycle()
        }
        active = ActiveStroke(a.page, a.brush, a.color, a.width, a.seed, b.preview(predicted), a.startTime)
        requestFrame()
    }

    private fun erasePoint(page: Int, s: InputSample) {
        val p = Vec2(s.x, s.y)
        state.erase(page, lastEraser ?: p, p)
        lastEraser = p
    }

    private fun penUp(event: MotionEvent, i: Int) {
        if (eraserPage != null) {
            penMoved(event, i)
            state.endErase()
            finishEraser()
            return
        }
        val b = builder
        val a = active
        if (b != null && a != null) {
            b.add(sample(event, i, -1))
            val points = b.finish()
            if (points.isNotEmpty()) {
                val now = referenceNow()
                state.addStroke(a.page, Stroke(a.brush, a.color, a.width, now, a.seed, points, max(0.0, now - strokeStart)))
            }
        }
        builder = null
        active = null
        penPointer = -1
        requestFrame()
    }

    private fun cancelPen() {
        if (eraserPage != null) {
            state.cancelErase()
            finishEraser()
            return
        }
        builder = null
        active = null
        penPointer = -1
        requestFrame()
    }

    private fun finishEraser() {
        eraserPage = null
        lastEraser = null
        penPointer = -1
        if (temporaryEraser) state.temporaryEraser = false
        temporaryEraser = false
        requestFrame()
    }

    // MARK: fingers: move and zoom the pages

    private fun startNavigation(event: MotionEvent) {
        scroller.forceFinished(true)
        navigating = true
        velocity?.recycle()
        velocity = VelocityTracker.obtain().also { it.addMovement(event) }
        val i = event.actionIndex
        panPointer = event.getPointerId(i)
        lastPanX = event.getX(i)
        lastPanY = event.getY(i)
        scaleDetector.onTouchEvent(event)
    }

    private fun navigate(event: MotionEvent) {
        velocity?.addMovement(event)
        scaleDetector.onTouchEvent(event)
        if (event.actionMasked == MotionEvent.ACTION_POINTER_UP) {
            // Another finger keeps the pan going from where it is.
            val up = event.actionIndex
            val keep = (0 until event.pointerCount).firstOrNull { it != up && event.getPointerId(it) != penPointer } ?: return
            panPointer = event.getPointerId(keep)
            lastPanX = event.getX(keep)
            lastPanY = event.getY(keep)
            return
        }
        val i = event.findPointerIndex(panPointer)
        if (i < 0) return
        val x = event.getX(i)
        val y = event.getY(i)
        if (!scaleDetector.isInProgress) {
            originX += x - lastPanX
            originY += y - lastPanY
            clamp()
            requestFrame()
        }
        lastPanX = x
        lastPanY = y
    }

    private fun endNavigation(event: MotionEvent) {
        navigating = false
        val v = velocity ?: return
        v.addMovement(event)
        v.computeCurrentVelocity(1000)
        val vy = v.getYVelocity(panPointer)
        v.recycle()
        velocity = null
        val l = pageLayout()
        val margin = 24f * resources.displayMetrics.density
        val minY = min(margin, height - l.totalHeight * zoom - margin)
        scroller.fling(0, originY.toInt(), 0, vy.toInt(), 0, 0, minY.toInt(), margin.toInt())
        postOnAnimation(::flingStep)
    }

    private fun flingStep() {
        if (navigating || !scroller.computeScrollOffset()) return
        originY = scroller.currY.toFloat()
        clamp()
        requestFrame()
        postOnAnimation(::flingStep)
    }

    private inner class ScaleListener : ScaleGestureDetector.SimpleOnScaleGestureListener() {
        override fun onScale(detector: ScaleGestureDetector): Boolean {
            val newZoom = (zoom * detector.scaleFactor).coerceIn(fitZoom * 0.5f, fitZoom * 6f)
            val k = newZoom / zoom
            // Zooms around the fingers' focus.
            originX = detector.focusX - (detector.focusX - originX) * k
            originY = detector.focusY - (detector.focusY - originY) * k
            zoom = newZoom
            clamp()
            requestFrame()
            return true
        }
    }
}
