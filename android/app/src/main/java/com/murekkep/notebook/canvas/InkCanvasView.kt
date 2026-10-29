package com.murekkep.notebook.canvas

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.opengl.GLSurfaceView
import android.os.Build
import android.os.SystemClock
import android.view.Choreographer
import android.view.HapticFeedbackConstants
import android.view.MotionEvent
import android.view.ScaleGestureDetector
import android.view.Surface
import android.view.SurfaceHolder
import android.view.VelocityTracker
import android.widget.OverScroller
import androidx.input.motionprediction.MotionEventPredictor
import com.murekkep.notebook.R
import com.murekkep.notebook.ink.Brush
import com.murekkep.notebook.ink.Compass
import com.murekkep.notebook.ink.CompassArc
import com.murekkep.notebook.ink.EdgeSnap
import com.murekkep.notebook.ink.EditableShape
import com.murekkep.notebook.ink.Geo
import com.murekkep.notebook.ink.InkPoint
import com.murekkep.notebook.ink.InputSample
import com.murekkep.notebook.ink.Instrument
import com.murekkep.notebook.ink.InstrumentDrag
import com.murekkep.notebook.ink.Lasso
import com.murekkep.notebook.ink.POINTS_PER_MILLIMETRE
import com.murekkep.notebook.ink.Pt
import com.murekkep.notebook.ink.SelectionDrag
import com.murekkep.notebook.ink.ShapeBuilder
import com.murekkep.notebook.ink.ShapeEditState
import com.murekkep.notebook.ink.ShapeName
import com.murekkep.notebook.ink.Stroke
import com.murekkep.notebook.ink.StrokeBuilder
import com.murekkep.notebook.ink.Vec2
import com.murekkep.notebook.ink.referenceNow
import com.murekkep.notebook.render.ActiveStroke
import com.murekkep.notebook.render.FrameInput
import com.murekkep.notebook.render.InkRenderer
import com.murekkep.notebook.render.PageLayout
import com.murekkep.notebook.render.PdfTextures
import com.murekkep.notebook.ui.EditorState
import com.murekkep.notebook.ui.Tool
import com.murekkep.notebook.ui.localizedTitle
import com.murekkep.notebook.ui.shaderIndex
import java.text.DecimalFormatSymbols
import java.text.NumberFormat
import javax.microedition.khronos.egl.EGLConfig
import javax.microedition.khronos.opengles.GL10
import kotlin.math.PI
import kotlin.math.atan2
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

// The iPad's CanvasView (Murekkep.swiftpm/CanvasView.swift) on Android: the pages, the pen and
// the fingers. Android pens bring what the Apple Pencil does on iPad, mapped as follows:
// - pressure, tilt (AXIS_TILT) and direction (AXIS_ORIENTATION) drive the stroke builder;
// - the pen's side button (S Pen, USI) is the temporary eraser, as the Pencil Pro's squeeze;
// - an eraser end (TOOL_TYPE_ERASER) erases;
// - once a pen has touched the screen, fingers only move and zoom the pages (palm rejection), and a
//   touch the system cancels as a palm (FLAG_CANCELED) takes its stroke back;
// - pen events come unbatched (requestUnbufferedDispatch) and the line under the tip runs a little
//   ahead of the pen with Jetpack's motion prediction;
// - the screen runs at its highest refresh rate (120 Hz where the tablet has it), and moving ink is
//   drawn at that rate, or at most 30 times a second with the battery saver (Pil tasarrufu).
// As on iPad, a pen resting at the end of a stroke turns it into a clean shape that then follows
// the pen (size and turn) and keeps handles on its corners after it lifts; the lasso and the shape
// tool draw their loops, frames and previews in the screen's overlay (CanvasOverlay).
/** A pen hovering over the canvas: where (view pixels) and the radius of what it would draw or erase. */
data class HoverRing(val x: Float, val y: Float, val radius: Float, val erasing: Boolean)

/** A rectangle in view pixels. */
data class ViewRect(val left: Float, val top: Float, val right: Float, val bottom: Float)

/** A measurement next to the pen ("%120", "90°"), at a view point. */
data class OverlayLabel(val x: Float, val y: Float, val text: String)

/** What the screen draws over the ink, in view pixels (CanvasOverlay.swift on iPad): the lasso's
 *  loop while it is drawn (x, y pairs), the box of the selected strokes (its dashed frame and
 *  handles go round it), a measurement next to the pen, the handles of a recognized shape (x, y
 *  pairs; the last one moves the whole shape), the shape tool's shape while it is dragged, the
 *  drafting instrument on the page and the compass. */
class CanvasOverlay(
    val lasso: FloatArray?,
    val selection: ViewRect?,
    val label: OverlayLabel?,
    val shapeHandles: FloatArray? = null,
    val preview: List<FloatArray>? = null,
    val instrument: InstrumentOverlay? = null,
    val compass: CompassOverlay? = null,
)

class InkCanvasView(context: Context, private val state: EditorState) : GLSurfaceView(context) {
    companion object {
        /** How long the pen rests before what it drew becomes a shape (StrokeBuilder.snapToShape). */
        private const val HOLD_MILLIS = 550L

        /** How far from a shape's handle (dp) a finger still takes it: a finger is broader than a pen. */
        private const val FINGER_REACH = 34f
    }

    private val renderer = InkRenderer()
    @Volatile private var frameInput: FrameInput? = null

    /** Told where a hovering pen is (null when it leaves or touches): the screen draws the ring. */
    var onHover: ((HoverRing?) -> Unit)? = null

    /** Told what to draw over the ink (null when nothing): the screen draws it. */
    var onOverlay: ((CanvasOverlay?) -> Unit)? = null
    private var overlayShown = false

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

    // The lasso: the loop being drawn (document points), how long it is on screen (dp) for the
    // pen's ticks, and a drag on the selection with the measurement it shows.
    private var lassoPage: Int? = null
    private val lassoPoints = ArrayList<Vec2>()
    private var lassoTravel = 0f
    private var lastLassoTick = 0L
    private var selectionDrag: SelectionDrag? = null
    private var lastTurnSnap: Int? = null

    /** A measurement or a hint next to the pen (document point, text). */
    private var liveLabel: Pair<Vec2, String>? = null

    // Held shapes: the pen resting still for a moment (view pixels where it rests) turns the stroke
    // into a clean shape; a recognized shape keeps handles until the next touch elsewhere.
    private var holdAnchorX = Float.NaN
    private var holdAnchorY = 0f
    private val holdFire = Runnable { holdFired() }
    private var snappedName: ShapeName? = null
    private var shapeHandleDrag: Int? = null
    private var shapeHandleOffset = Pt(0.0, 0.0)
    private var lastShapeSnapped = false

    // The shape tool: the page and start of the drag (page points) and where it ends now.
    private var shapeStart: Pair<Int, Pt>? = null
    private var shapeEnd: Pt? = null

    // The drafting instruments: fingers on one carry and turn it, its angle shown while they turn;
    // a stroke that starts near its edge (or a protractor's center) runs along it from where it
    // started (document points).
    private var instrumentDrag: InstrumentDrag? = null
    private var instrumentLabel: String? = null
    private var snap: EdgeSnap? = null
    private var snapStart: Pt? = null

    // The compass: its center being set (the drag's page, its center there and the pen in document
    // points), or an arc being drawn round it.
    private class CompassDraft(val page: Int, val center: Pt, var pen: Vec2)

    private var compassDraft: CompassDraft? = null
    private var compassArc: CompassArc? = null

    // The fingers.
    private val scaleDetector = ScaleGestureDetector(context, ScaleListener())
    private val scroller = OverScroller(context)
    private var velocity: VelocityTracker? = null
    private var panPointer = -1
    private var lastPanX = 0f
    private var lastPanY = 0f
    private var navigating = false
    private var tapX = 0f
    private var tapY = 0f

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
        saverLoop.running = false
        state.onInkChange = null
        val pdf = pdfTextures
        queueEvent {
            renderer.release()
            pdf?.release()
        }
    }

    /** The ground round the pages, rgb in 0..1: the theme's paper-3, set by the screen. */
    @Volatile
    var ground: FloatArray = floatArrayOf(0.93f, 0.93f, 0.95f)
        set(value) {
            field = value
            requestFrame()
        }

    /** The room the floating pen bar takes along the canvas's edges (view pixels), set by the screen:
     *  the pages can always be moved out from under it. */
    var clearance = Clearance()
        set(value) {
            if (field == value) return
            field = value
            if (!fitted) return
            clamp()
            requestFrame()
        }

    /** An imported PDF's pages as textures (made once; the GL thread uses and frees them). */
    private val pdfTextures: PdfTextures? = state.pdfFile?.let { file -> PdfTextures(file) { requestRender() } }

    // MARK: frames

    private fun requestFrame() {
        val pages = state.pages
        frameInput = FrameInput(
            pages = pages,
            layout = pageLayout(),
            originX = originX,
            originY = originY,
            zoom = zoom,
            active = active,
            paperStyle = state.paper.shaderIndex,
            animate = state.animations,
            dryDuration = state.dryDuration,
            coolDuration = state.coolDuration,
            pdf = pdfTextures,
            fitScale = fitZoom,
            ground = ground,
        )
        requestRender()
        publishOverlay()
        publishCurrentPage()
    }

    /** The page under the middle of the view, for the page badge. */
    private fun publishCurrentPage() {
        val l = pageLayout()
        if (l.pageCount == 0 || height <= 0) return
        val y = docY(height / 2f)
        // The last page that starts above the middle (the gap between pages belongs to the page above).
        var page = 0
        while (page + 1 < l.pageCount && l.top(page + 1) <= y) page++
        if (state.currentPage != page) state.currentPage = page
        state.viewCenter = Pair(page, viewMiddle(l, page))
    }

    /** The view's middle on [page], kept 40 points inside its sides and 60 inside its top and bottom
     *  (CanvasView.reportCurrentPage): where an instrument is laid. */
    private fun viewMiddle(l: PageLayout, page: Int): Vec2 {
        val left = l.left(page)
        val top = l.top(page)
        val x = min(max(docX(width / 2f), left + 40f), left + l.width(page) - 40f)
        val y = min(max(docY(height / 2f), top + 60f), top + l.height(page) - 60f)
        return Vec2(x - left, y - top)
    }

    /** Hands the screen the lasso, the selection's box and the measurement in view pixels; they
     *  follow every scroll and zoom, as every change asks for a frame. */
    private fun publishOverlay() {
        val sel = if (state.tool is Tool.Lasso) state.displayedSelection else null
        val loop = if (lassoPage != null && lassoPoints.size >= 2) {
            FloatArray(lassoPoints.size * 2).also { a ->
                for ((i, p) in lassoPoints.withIndex()) {
                    a[2 * i] = viewX(p.x)
                    a[2 * i + 1] = viewY(p.y)
                }
            }
        } else {
            null
        }
        val label = liveLabel
        val l = pageLayout()
        val handles = state.shapeEdit?.let { edit ->
            val left = l.left(edit.page)
            val top = l.top(edit.page)
            val hs = edit.shape.handles
            FloatArray(hs.size * 2).also { a ->
                for ((i, h) in hs.withIndex()) {
                    a[2 * i] = viewX(left + h.x.toFloat())
                    a[2 * i + 1] = viewY(top + h.y.toFloat())
                }
            }
        }
        val preview = shapeStart?.let { (page, from) ->
            val end = shapeEnd ?: return@let null
            val left = l.left(page)
            val top = l.top(page)
            state.shapePaths(from, end).map { path ->
                FloatArray(path.size * 2).also { a ->
                    for ((i, q) in path.withIndex()) {
                        a[2 * i] = viewX(left + q.x)
                        a[2 * i + 1] = viewY(top + q.y)
                    }
                }
            }
        }
        val instrument = state.instrument?.let {
            InstrumentOverlay(it.kind, viewX(it.center.x.toFloat()), viewY(it.center.y.toFloat()), it.angle.toFloat(), zoom, instrumentLabel)
        }
        val compass = compassOverlay(l)
        if (sel == null && loop == null && label == null && handles == null && preview == null && instrument == null && compass == null) {
            if (overlayShown) {
                overlayShown = false
                onOverlay?.invoke(null)
            }
            return
        }
        val box = sel?.let { s ->
            val left = l.left(s.page)
            val top = l.top(s.page)
            ViewRect(viewX(left + s.bounds.minX), viewY(top + s.bounds.minY), viewX(left + s.bounds.maxX), viewY(top + s.bounds.maxY))
        }
        overlayShown = true
        onOverlay?.invoke(
            CanvasOverlay(
                loop, box, label?.let { (p, text) -> OverlayLabel(viewX(p.x), viewY(p.y), text) }, handles, preview,
                instrument = instrument, compass = compass,
            ),
        )
    }

    /** The compass while its tool is in hand (view pixels): the center and radius being dragged, or
     *  the set ones with the pen at the arc's end while it draws. */
    private fun compassOverlay(l: PageLayout): CompassOverlay? {
        compassDraft?.let { d ->
            val c = l.toDoc(d.page, d.center.x.toFloat(), d.center.y.toFloat())
            val r = hypot(d.pen.x - c.x, d.pen.y - c.y)
            return CompassOverlay(viewX(c.x), viewY(c.y), r * zoom, Vec2(viewX(d.pen.x), viewY(d.pen.y)))
        }
        val set = state.compass ?: return null
        if (state.tool !is Tool.Compass) return null
        val c = l.toDoc(set.page, set.center.x.toFloat(), set.center.y.toFloat())
        val pen = compassArc?.points?.lastOrNull()?.let { p -> l.toDoc(set.page, p.x.toFloat(), p.y.toFloat()) }
        return CompassOverlay(viewX(c.x), viewY(c.y), set.radius.toFloat() * zoom, pen?.let { Vec2(viewX(it.x), viewY(it.y)) })
    }

    /** While ink on screen moves the canvas draws at the display's full rate, as the iPad's loop; with
     *  the battery saver at most 30 times a second (the pen's own moves still draw at once). */
    private fun setAnimating(on: Boolean) {
        val saver = on && state.batterySaver
        val mode = if (on && !saver) RENDERMODE_CONTINUOUSLY else RENDERMODE_WHEN_DIRTY
        if (renderMode != mode) renderMode = mode
        saverLoop.running = saver
    }

    /** The battery saver's frames. */
    private val saverLoop = SaverLoop { requestRender() }

    override fun onPause() {
        saverLoop.running = false
        super.onPause()
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
        val layout = pageLayout()
        val oldFit = fitZoom
        // The iPad's fit (CanvasView.fitZoom): the widest page with its margin on either side fills
        // the width, so the margins and the gaps are page points that zoom with the pages.
        fitZoom = max(0.1f, w / (layout.pageWidth + 2 * PageLayout.MARGIN))
        if (!fitted) {
            zoom = fitZoom
            // In the middle: with a bar down the right side the clamp lets a fitted page stand left of
            // the middle, so it would leave it at the left edge.
            originX = (w - layout.pageWidth * zoom) / 2f
            originY = PageLayout.MARGIN * zoom + clearance.top
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

    private fun pageLayout() = state.layout()

    /** A document point in page `page`'s own points (where its ink lives). */
    private fun toPage(page: Int, doc: Vec2): Vec2 = pageLayout().toPage(page, doc.x, doc.y)

    /** A point of page `page` in document points. */
    private fun toDoc(page: Int, x: Float, y: Float): Vec2 = pageLayout().toDoc(page, x, y)

    private fun clamp() {
        val l = pageLayout()
        originX = PageScroll.clampX(originX, width.toFloat(), l.pageWidth * zoom, clearance)
        originY = originY.coerceIn(verticalRange())
    }

    /** Where the document's origin may stand vertically (view pixels). */
    private fun verticalRange(): ClosedFloatingPointRange<Float> =
        PageScroll.verticalRange(height.toFloat(), pageLayout().totalHeight * zoom, PageLayout.MARGIN * zoom, clearance)

    private fun docX(x: Float) = (x - originX) / zoom
    private fun docY(y: Float) = (y - originY) / zoom
    private fun viewX(x: Float) = originX + x * zoom
    private fun viewY(y: Float) = originY + y * zoom

    /** Document points per dp at the current zoom: the iPad's view points become dp here. */
    private fun unit() = resources.displayMetrics.density / zoom

    // MARK: hover

    /** A pen above the screen (S Pen, USI) shows the size of its line, or of the eraser while its
     *  side button is held or its eraser end is down, as the Pencil's hover preview on iPad. */
    override fun onHoverEvent(event: MotionEvent): Boolean {
        val tool = event.getToolType(0)
        if (tool != MotionEvent.TOOL_TYPE_STYLUS && tool != MotionEvent.TOOL_TYPE_ERASER) return super.onHoverEvent(event)
        when (event.actionMasked) {
            MotionEvent.ACTION_HOVER_ENTER, MotionEvent.ACTION_HOVER_MOVE -> {
                stylusSeen = true
                // Ayarlar › Kalem › Havada önizleme turned off: no ring.
                if (!state.ink.hoverPreview) {
                    onHover?.invoke(null)
                    return true
                }
                val erasing = state.tool is Tool.Eraser || tool == MotionEvent.TOOL_TYPE_ERASER ||
                    event.isButtonPressed(MotionEvent.BUTTON_STYLUS_PRIMARY) ||
                    event.isButtonPressed(MotionEvent.BUTTON_STYLUS_SECONDARY)
                // The lasso draws no ink: no ring.
                if (state.tool is Tool.Lasso && !erasing) {
                    onHover?.invoke(null)
                    return true
                }
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
                // A new touch: no finger is left on an instrument from before.
                if (event.actionMasked == MotionEvent.ACTION_DOWN) endInstrumentDrag()
                if (pen) {
                    stylusSeen = true
                    onHover?.invoke(null)
                    if (penPointer == -1) {
                        requestUnbufferedDispatch(event)
                        penDown(event, index, stylus = true)
                    }
                    return true
                }
                // A finger: draws only on a device whose pen has not been seen, and only alone, unless
                // Yalnızca kalemle çiz is on; it can still take a recognized shape's handles.
                if (penPointer != -1 && penIsStylus) return true
                if (fingerOnInstrument(event, index)) return true
                val edit = state.shapeEdit
                val fingerDraws = !stylusSeen && !state.ink.penOnly
                if (!fingerDraws && edit != null && event.pointerCount == 1 && penPointer == -1 && !navigating &&
                    shapeHandle(Vec2(docX(event.getX(index)), docY(event.getY(index))), edit, FINGER_REACH) != null
                ) {
                    penDown(event, index, stylus = false)
                    return true
                }
                if (fingerDraws && event.pointerCount == 1 && penPointer == -1 && !navigating) {
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
                instrumentDrag?.let { moveInstrument(event, it) }
                if (navigating) navigate(event)
            }
            MotionEvent.ACTION_POINTER_UP, MotionEvent.ACTION_UP -> {
                val id = event.getPointerId(index)
                val drag = instrumentDrag
                if (drag != null && id in drag) {
                    val canceled = Build.VERSION.SDK_INT >= 33 && (event.flags and MotionEvent.FLAG_CANCELED) != 0
                    if (canceled) {
                        cancelInstrumentDrag()
                    } else {
                        drag.up(id)
                        if (drag.isEmpty) {
                            endInstrumentDrag()
                        } else if (!drag.isTurning && instrumentLabel != null) {
                            instrumentLabel = null
                            requestFrame()
                        }
                    }
                } else if (id == penPointer) {
                    val canceled = Build.VERSION.SDK_INT >= 33 && (event.flags and MotionEvent.FLAG_CANCELED) != 0
                    if (canceled) cancelPen() else penUp(event, index)
                } else if (navigating) {
                    if (event.actionMasked == MotionEvent.ACTION_UP) endNavigation(event) else navigate(event)
                }
            }
            MotionEvent.ACTION_CANCEL -> {
                if (penPointer != -1) cancelPen()
                cancelInstrumentDrag()
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
        val l = pageLayout()
        val left = l.left(page)
        val top = l.top(page)
        val stylus = event.getToolType(i) == MotionEvent.TOOL_TYPE_STYLUS || event.getToolType(i) == MotionEvent.TOOL_TYPE_ERASER
        var dx = docX(x)
        var dy = docY(y)
        // A stroke along an instrument keeps to its edge (or protractor ray).
        snap?.let { s ->
            val p = s.project(Pt(dx.toDouble(), dy.toDouble()))
            dx = p.x.toFloat()
            dy = p.y.toFloat()
        }
        return InputSample(
            x = dx - left,
            y = dy - top,
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
        val sideButton = event.isButtonPressed(MotionEvent.BUTTON_STYLUS_PRIMARY) ||
            event.isButtonPressed(MotionEvent.BUTTON_STYLUS_SECONDARY)
        val eraserEnd = event.getToolType(i) == MotionEvent.TOOL_TYPE_ERASER
        val borrowsEraser = stylus && (sideButton || eraserEnd)
        // A recognized shape shows handles on its corners: a handle is dragged, any other touch puts
        // them away (and then does what the tool does).
        state.shapeEdit?.let { edit ->
            val index = if (borrowsEraser) null else shapeHandle(Vec2(x, y), edit, if (stylus) 16f else FINGER_REACH)
            if (index != null) {
                val h = edit.shape.handles[index]
                shapeHandleDrag = index
                val at = l.toPage(edit.page, x, y)
                shapeHandleOffset = Pt(h.x - at.x, h.y - at.y)
                lastShapeSnapped = false
                state.beginShapeHandleDrag()
                penPointer = event.getPointerId(i)
                penIsStylus = stylus
                return
            }
            state.finishShapeEdit()
        }
        if (state.tool is Tool.Compass && !borrowsEraser) {
            if (!compassBegan(Vec2(x, y))) return
            penPointer = event.getPointerId(i)
            penIsStylus = stylus
            return
        }
        if (state.tool is Tool.Shape && !borrowsEraser) {
            val page = l.pageAt(x, y) ?: return
            val at = l.toPage(page, x, y)
            val start = Pt(at.x.toDouble(), at.y.toDouble())
            shapeStart = Pair(page, start)
            shapeEnd = start
            penPointer = event.getPointerId(i)
            penIsStylus = stylus
            requestFrame()
            return
        }
        if (state.tool is Tool.Lasso && !borrowsEraser) {
            if (!lassoBegan(Vec2(x, y))) return
            penPointer = event.getPointerId(i)
            penIsStylus = stylus
            return
        }
        val page = l.pageAt(x, y, tolerance = 24f) ?: return
        penPointer = event.getPointerId(i)
        penIsStylus = stylus
        temporaryEraser = borrowsEraser
        if (state.tool is Tool.Eraser || temporaryEraser) {
            state.temporaryEraser = temporaryEraser
            eraserPage = page
            val p = l.toPage(page, x, y)
            lastEraser = p
            state.beginErase(page)
            state.erase(page, p, p)
            requestFrame()
            return
        }
        val brush: Brush = (state.tool as? Tool.Brush)?.brush ?: state.activeBrush
        val b = StrokeBuilder(brush, state.color(brush), state.width(brush), state.newSeed(brush))
        b.nibAngle = state.nibAngle * PI.toFloat() / 180f
        // Near an instrument's edge (or a protractor's center) the stroke runs along it.
        val down = Pt(x.toDouble(), y.toDouble())
        snap = state.instrument?.let { EdgeSnap.find(it, down, EdgeSnap.TOLERANCE * unit()) }
        snapStart = snap?.project(down)
        strokeStart = referenceNow()
        active = ActiveStroke(page, brush, b.color, b.width, b.seed, emptyList(), strokeStart)
        b.add(sample(event, i, -1))
        builder = b
        active = ActiveStroke(page, brush, b.color, b.width, b.seed, b.preview(emptyList()), strokeStart)
        holdAnchorX = Float.NaN
        if (snap == null) trackHold(event.getX(i), event.getY(i)) else showSnapReading(Vec2(x, y))
        requestFrame()
    }

    private fun penMoved(event: MotionEvent, i: Int) {
        val page = eraserPage
        if (page != null) {
            for (h in 0 until event.historySize) erasePoint(page, sample(event, i, h))
            erasePoint(page, sample(event, i, -1))
            return
        }
        val handle = shapeHandleDrag
        if (handle != null) {
            dragShapeHandle(handle, Vec2(docX(event.getX(i)), docY(event.getY(i))))
            return
        }
        if (shapeStart != null) {
            updateShapePreview(Vec2(docX(event.getX(i)), docY(event.getY(i))))
            return
        }
        if (compassDraft != null || compassArc != null) {
            compassMoved(Vec2(docX(event.getX(i)), docY(event.getY(i))))
            return
        }
        if (selectionDrag != null) {
            // Only where the pen is now matters to a drag.
            lassoMoved(Vec2(docX(event.getX(i)), docY(event.getY(i))))
            return
        }
        if (lassoPage != null) {
            for (h in 0 until event.historySize) lassoMoved(Vec2(docX(event.getHistoricalX(i, h)), docY(event.getHistoricalY(i, h))))
            lassoMoved(Vec2(docX(event.getX(i)), docY(event.getY(i))))
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
        // A snapped shape follows the pen: show its size and turn.
        val name = snappedName
        val adjustment = b.shapeAdjustment
        val tip = b.tip
        if (name != null && adjustment != null && tip != null) {
            val scale = NumberFormat.getPercentInstance().format(adjustment.scale)
            liveLabel = Pair(toDoc(a.page, tip.x, tip.y), "${name.localizedTitle()} · $scale · ${adjustment.degrees}°")
        }
        if (snap == null) trackHold(event.getX(i), event.getY(i)) else showSnapReading(Vec2(docX(event.getX(i)), docY(event.getY(i))))
        requestFrame()
    }

    private fun erasePoint(page: Int, s: InputSample) {
        val p = Vec2(s.x, s.y)
        state.erase(page, lastEraser ?: p, p)
        lastEraser = p
    }

    private fun penUp(event: MotionEvent, i: Int) {
        cancelHold()
        if (shapeHandleDrag != null) {
            penMoved(event, i)
            shapeHandleDrag = null
            liveLabel = null
            state.endShapeHandleDrag()
            penPointer = -1
            requestFrame()
            return
        }
        val shape = shapeStart
        if (shape != null) {
            penMoved(event, i)
            val end = shapeEnd
            shapeStart = null
            shapeEnd = null
            liveLabel = null
            penPointer = -1
            if (end != null) state.addShape(shape.first, shape.second, end)
            requestFrame()
            return
        }
        if (compassDraft != null || compassArc != null) {
            compassEnded(Vec2(docX(event.getX(i)), docY(event.getY(i))))
            return
        }
        if (eraserPage != null) {
            penMoved(event, i)
            state.endErase()
            finishEraser()
            return
        }
        if (selectionDrag != null || lassoPage != null) {
            penMoved(event, i)
            lassoEnded()
            return
        }
        val b = builder
        val a = active
        if (b != null && a != null) {
            b.add(sample(event, i, -1))
            val straight = b.isStraight
            val points = b.finish()
            if (points.isNotEmpty()) {
                val now = referenceNow()
                val stroke = Stroke(a.brush, a.color, a.width, now, a.seed, points, max(0.0, now - strokeStart))
                state.addStroke(a.page, stroke)
                // The shape keeps handles on its corners until the next touch elsewhere.
                b.editable?.let { state.startShapeEdit(a.page, stroke.id, it) }
                if (straight || snap != null) confirm()
            }
        }
        builder = null
        active = null
        snappedName = null
        snap = null
        snapStart = null
        liveLabel = null
        penPointer = -1
        requestFrame()
    }

    private fun cancelPen() {
        if (eraserPage != null) {
            state.cancelErase()
            finishEraser()
            return
        }
        cancelHold()
        if (shapeHandleDrag != null) state.endShapeHandleDrag()
        shapeHandleDrag = null
        shapeStart = null
        shapeEnd = null
        snappedName = null
        snap = null
        snapStart = null
        // A cancelled compass drag sets nothing and a cancelled arc draws nothing, as on iPad.
        compassDraft = null
        compassArc = null
        // A cancelled drag keeps where the selection got to, as on iPad; a cancelled loop selects nothing.
        if (selectionDrag != null) state.endSelectionEdit()
        selectionDrag = null
        liveLabel = null
        lassoPage = null
        lassoPoints.clear()
        builder = null
        active = null
        penPointer = -1
        requestFrame()
    }

    // MARK: lasso

    /** The pen touched down with the lasso: on the selection's frame or a handle it takes the
     *  selection (the turn handle may stand above the page); anywhere else on a page it starts a new
     *  loop. False off the pages. */
    private fun lassoBegan(doc: Vec2): Boolean {
        val l = pageLayout()
        state.displayedSelection?.let { sel ->
            val drag = Lasso.grab(l.toPage(sel.page, doc.x, doc.y), sel.bounds, unit())
            if (drag != null) {
                selectionDrag = drag
                // A turn starts settled at 0°: no click until it leaves and comes back.
                lastTurnSnap = if (drag is SelectionDrag.Rotate) 0 else null
                state.beginSelectionEdit()
                return true
            }
        }
        val page = l.pageAt(doc.x, doc.y, tolerance = 16f) ?: return false
        state.clearSelection()
        lassoPage = page
        lassoPoints.clear()
        lassoPoints.add(doc)
        lassoTravel = 0f
        requestFrame()
        return true
    }

    private fun lassoMoved(doc: Vec2) {
        val drag = selectionDrag
        if (drag != null) {
            val sel = state.displayedSelection ?: return
            val p = toPage(sel.page, doc)
            when (drag) {
                is SelectionDrag.Move -> state.transformSelection(p - drag.start, 1f, Vec2.ZERO)
                is SelectionDrag.Scale -> {
                    val k = hypot(p.x - drag.anchor.x, p.y - drag.anchor.y) / drag.startDistance
                    liveLabel = Pair(doc, NumberFormat.getPercentInstance().format(k.toDouble().coerceIn(0.05, 20.0)))
                    state.transformSelection(Vec2.ZERO, k, drag.anchor)
                }
                is SelectionDrag.Rotate -> {
                    val (angle, settled) = Lasso.settleTurn(atan2(p.y - drag.center.y, p.x - drag.center.x) - drag.startAngle)
                    if (settled != null) {
                        if (lastTurnSnap != settled) {
                            lastTurnSnap = settled
                            tick()
                        }
                    } else {
                        lastTurnSnap = null
                    }
                    liveLabel = Pair(doc, "${(-angle * 180.0 / PI).roundToInt()}°")
                    state.transformSelection(Vec2.ZERO, 1f, drag.center, angle)
                }
            }
            return
        }
        if (lassoPage == null) return
        val last = lassoPoints.last()
        val step = hypot(doc.x - last.x, doc.y - last.y)
        if (step < 2f) return
        // The pen ticks each time the loop grows by one dash and gap of its outline on screen.
        val before = Lasso.dashCount(lassoTravel)
        lassoTravel += step / unit()
        val now = SystemClock.uptimeMillis()
        if (Lasso.dashCount(lassoTravel) > before && now - lastLassoTick > 25) {
            lastLassoTick = now
            tick()
        }
        lassoPoints.add(doc)
        requestFrame()
    }

    private fun lassoEnded() {
        if (selectionDrag != null) {
            selectionDrag = null
            liveLabel = null
            state.endSelectionEdit()
            penPointer = -1
            requestFrame()
            return
        }
        val page = lassoPage
        penPointer = -1
        if (page == null) return
        val polygon = lassoPoints.map { toPage(page, it) }
        lassoPage = null
        lassoPoints.clear()
        var length = 0f
        for (j in 1 until polygon.size) length += hypot(polygon[j].x - polygon[j - 1].x, polygon[j].y - polygon[j - 1].y)
        // A tap (no loop drawn) picks the stroke under the pen.
        val took = if (length < Lasso.TAP_LENGTH * unit()) {
            state.selectItem(page, polygon.first(), 8f * unit())
        } else {
            state.selectStrokes(page, polygon)
        }
        if (took) confirm()
        requestFrame()
    }

    // MARK: held shapes

    /** Waits for the pen to rest: every move farther than 4 dp from where it rested starts the wait again. */
    private fun trackHold(vx: Float, vy: Float) {
        val b = builder ?: return
        if (b.isStraight || !state.straightLine) return
        if (!holdAnchorX.isNaN() && hypot(vx - holdAnchorX, vy - holdAnchorY) < 4f * resources.displayMetrics.density) return
        holdAnchorX = vx
        holdAnchorY = vy
        removeCallbacks(holdFire)
        postDelayed(holdFire, HOLD_MILLIS)
    }

    private fun cancelHold() {
        removeCallbacks(holdFire)
        holdAnchorX = Float.NaN
    }

    /** The pen rested: what it drew becomes a line, circle, ellipse, curve, rectangle or polygon in
     *  the same ink; a shape other than a line then follows the pen (size and turn). */
    private fun holdFired() {
        val b = builder ?: return
        val a = active ?: return
        if (penPointer == -1) return
        val last = b.drawnPath.lastOrNull()
        val name = b.snapToShape() ?: return
        active = ActiveStroke(a.page, a.brush, a.color, a.width, a.seed, b.preview(emptyList()), a.startTime)
        snappedName = name
        tick()
        if (last != null) {
            val title = name.localizedTitle()
            val text = if (b.shapeAdjustment == null) title else context.getString(R.string.shape_hold_hint, title)
            liveLabel = Pair(toDoc(a.page, last.x.toFloat(), last.y.toFloat()), text)
        }
        requestFrame()
    }

    /** The handle of the recognized shape under the pen (or finger), if any; `reach` in dp. With
     *  `inside`, a touch within a closed shape (or along an open one) that misses the corner handles
     *  takes the move handle, so the shape moves from anywhere on it. */
    private fun shapeHandle(doc: Vec2, edit: ShapeEditState, reach: Float, inside: Boolean = true): Int? {
        val at = toPage(edit.page, doc)
        val p = Pt(at.x.toDouble(), at.y.toDouble())
        val handles = edit.shape.handles
        var best: Int? = null
        var bestDistance = (reach * unit()).toDouble()
        for ((i, h) in handles.withIndex()) {
            val d = hypot(p.x - h.x, p.y - h.y)
            if (d < bestDistance) {
                bestDistance = d
                best = i
            }
        }
        if (best != null || !inside || handles.isEmpty()) return best
        val outline = edit.shape.path()
        if (outline.size < 2) return null
        when (edit.shape.kind) {
            is EditableShape.Kind.Polygon, is EditableShape.Kind.Oval -> {
                val loop = outline.map { Vec2(it.x.toFloat(), it.y.toFloat()) }
                if (Lasso.contains(loop, p.x.toFloat(), p.y.toFloat())) return handles.size - 1
            }
            is EditableShape.Kind.Polyline, is EditableShape.Kind.Curve -> {
                val tolerance = 14.0 * unit()
                for (j in 1 until outline.size) {
                    if (Geo.segmentDistance(p, outline[j - 1], outline[j]) <= tolerance) return handles.size - 1
                }
            }
        }
        return null
    }

    private fun dragShapeHandle(index: Int, doc: Vec2) {
        val edit = state.shapeEdit ?: return
        val at = toPage(edit.page, doc)
        val p = Pt(at.x + shapeHandleOffset.x, at.y + shapeHandleOffset.y)
        val feedback = state.moveShapeHandle(index, p, snap = 9.0 * unit()) ?: return
        if (feedback.snapped && !lastShapeSnapped) tick()
        lastShapeSnapped = feedback.snapped
        val separator = DecimalFormatSymbols.getInstance().decimalSeparator
        liveLabel = feedback.label?.let { Pair(doc, it.format({ n -> n.localizedTitle() }, separator)) }
        requestFrame()
    }

    // MARK: the shape tool

    /** The shape from where the pen went down to where it is, its end settling at 15° steps for
     *  lines and on squares for boxes, with its size next to the pen. */
    private fun updateShapePreview(doc: Vec2) {
        val (page, from) = shapeStart ?: return
        val at = toPage(page, doc)
        val end = ShapeBuilder.snappedEnd(state.shapeKind, Pt(at.x.toDouble(), at.y.toDouble()), from)
        shapeEnd = end
        val separator = DecimalFormatSymbols.getInstance().decimalSeparator
        liveLabel = Pair(toDoc(page, end.x.toFloat(), end.y.toFloat()), ShapeBuilder.measurement(state.shapeKind, from, end).format(separator))
        requestFrame()
    }

    // MARK: drafting instruments

    /** A finger came down: on the instrument (the iPad's instrumentPan and instrumentTurn) it takes
     *  the instrument and never draws, and while one finger holds it the next joins it wherever it
     *  lands. False when the finger is not the instrument's. */
    private fun fingerOnInstrument(event: MotionEvent, i: Int): Boolean {
        val at = Pt(docX(event.getX(i)).toDouble(), docY(event.getY(i)).toDouble())
        val drag = instrumentDrag
        if (drag != null) {
            drag.down(event.getPointerId(i), at)
            return true
        }
        val instrument = state.instrument ?: return false
        if (navigating || penPointer != -1 || !instrument.contains(at)) return false
        // A fling still running stops: the pages stay put under the instrument.
        scroller.forceFinished(true)
        instrumentDrag = InstrumentDrag(instrument).also { it.down(event.getPointerId(i), at) }
        return true
    }

    /** The fingers on the instrument moved: it goes with them, turned by two (its angle shown, a
     *  tick at every 15° it settles on). */
    private fun moveInstrument(event: MotionEvent, drag: InstrumentDrag) {
        val current = state.instrument
        if (current == null) {
            // Put away meanwhile.
            endInstrumentDrag()
            return
        }
        val positions = HashMap<Int, Pt>()
        for (j in 0 until event.pointerCount) {
            val id = event.getPointerId(j)
            if (id in drag) positions[id] = Pt(docX(event.getX(j)).toDouble(), docY(event.getY(j)).toDouble())
        }
        val settled = drag.move(positions)
        val moved = drag.instrument
        instrumentLabel = if (drag.isTurning) "${moved.degrees}°" else null
        if (settled) tick()
        val next = Instrument(current.kind, moved.center, moved.angle)
        // A new place asks for a frame itself; a frame for the angle alone otherwise.
        if (next == current) requestFrame() else state.instrument = next
    }

    private fun endInstrumentDrag() {
        if (instrumentDrag == null && instrumentLabel == null) return
        instrumentDrag = null
        instrumentLabel = null
        requestFrame()
    }

    /** The system took the touch back (a palm, as for a stroke): the instrument goes back to where
     *  the fingers found it. */
    private fun cancelInstrumentDrag() {
        val drag = instrumentDrag
        val current = state.instrument
        if (drag != null && current != null) state.instrument = Instrument(current.kind, drag.start.center, drag.start.angle)
        endInstrumentDrag()
    }

    /** Next to a pen along an instrument: the length drawn along its edge, or the angle of the
     *  protractor's ray (CanvasView.updateSnapLabel). */
    private fun showSnapReading(doc: Vec2) {
        val s = snap
        val start = snapStart
        val instrument = state.instrument
        if (s == null || start == null || instrument == null) {
            liveLabel = null
            return
        }
        val (at, reading) = s.reading(instrument, start, Pt(doc.x.toDouble(), doc.y.toDouble()))
        val separator = DecimalFormatSymbols.getInstance().decimalSeparator
        liveLabel = Pair(Vec2(at.x.toFloat(), at.y.toFloat()), reading.format(separator))
    }

    // MARK: the compass

    /** The pen came down with the compass: far enough from a set compass's center it swings an arc
     *  of its radius; anywhere else (on the old center too) it starts setting a new center and radius.
     *  False off the pages. */
    private fun compassBegan(doc: Vec2): Boolean {
        val l = pageLayout()
        val page = l.pageAt(doc.x, doc.y, tolerance = 8f) ?: return false
        val at = l.toPage(page, doc.x, doc.y)
        val p = Pt(at.x.toDouble(), at.y.toDouble())
        val set = state.compass
        if (set != null && Compass.startsArc(set, page, p, Compass.CENTER_REACH * unit())) {
            compassArc = CompassArc(set, p)
            strokeStart = referenceNow()
            showArc()
            return true
        }
        state.compass = null
        compassDraft = CompassDraft(page, p, doc)
        requestFrame()
        return true
    }

    private fun compassMoved(doc: Vec2) {
        val draft = compassDraft
        if (draft != null) {
            draft.pen = doc
            val c = toDoc(draft.page, draft.center.x.toFloat(), draft.center.y.toFloat())
            val r = hypot(doc.x - c.x, doc.y - c.y)
            val separator = DecimalFormatSymbols.getInstance().decimalSeparator
            liveLabel = Pair(doc, "r = " + ShapeBuilder.mm(r / POINTS_PER_MILLIMETRE, separator))
            requestFrame()
            return
        }
        val arc = compassArc ?: return
        val p = toPage(arc.compass.page, doc)
        arc.swing(Pt(p.x.toDouble(), p.y.toDouble()))
        showArc()
    }

    /** The arc so far as the stroke under the pen, in the last pen's ink and width. */
    private fun showArc() {
        val arc = compassArc ?: return
        val brush = state.activeBrush
        val width = state.width(brush)
        val r = width * 0.5f
        val points = arc.points.map { InkPoint(it.x.toFloat(), it.y.toFloat(), r, 0.55f) }
        active = ActiveStroke(arc.compass.page, brush, state.color(brush), width, 0.5f, points, strokeStart)
        requestFrame()
    }

    /** The pen lifted at [doc]: a drag long enough to there sets the compass (a tick); an arc becomes
     *  a stroke as it stands (a tap draws nothing). */
    private fun compassEnded(doc: Vec2) {
        val draft = compassDraft
        val arc = compassArc
        compassDraft = null
        compassArc = null
        liveLabel = null
        penPointer = -1
        if (draft != null) {
            val end = toPage(draft.page, doc)
            val set = Compass.set(draft.page, draft.center, Pt(end.x.toDouble(), end.y.toDouble()))
            state.compass = set
            if (set != null) tick()
        }
        if (arc != null) {
            active = null
            state.addArc(arc.compass.page, arc.points)
        }
        requestFrame()
    }

    /** A firm click: a selection made, a stroke straightened into a shape. */
    private fun confirm() {
        performHapticFeedback(if (Build.VERSION.SDK_INT >= 30) HapticFeedbackConstants.CONFIRM else HapticFeedbackConstants.VIRTUAL_KEY)
    }

    /** A light click: the loop growing by a dash, a turn settling at a right angle. */
    private fun tick() {
        performHapticFeedback(if (Build.VERSION.SDK_INT >= 34) HapticFeedbackConstants.SEGMENT_FREQUENT_TICK else HapticFeedbackConstants.CLOCK_TICK)
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
        tapX = event.getX(event.actionIndex)
        tapY = event.getY(event.actionIndex)
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
        // A finger tap (no pan) puts a recognized shape's handles away.
        if (state.shapeEdit != null && hypot(event.x - tapX, event.y - tapY) < 10f * resources.displayMetrics.density) {
            state.finishShapeEdit()
        }
        val v = velocity ?: return
        v.addMovement(event)
        v.computeCurrentVelocity(1000)
        val vy = v.getYVelocity(panPointer)
        v.recycle()
        velocity = null
        val range = verticalRange()
        scroller.fling(0, originY.toInt(), 0, vy.toInt(), 0, 0, range.start.toInt(), range.endInclusive.toInt())
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

/**
 * The battery saver's loop: asks for a frame on the display's vsync at most every 1/30 s while it
 * runs (the iPad's preferredFramesPerSecond = 30): every other vsync at 60 Hz, every fourth at 120.
 * Main thread only.
 */
private class SaverLoop(private val frame: () -> Unit) : Choreographer.FrameCallback {
    private var last = 0L

    var running = false
        set(value) {
            if (field == value) return
            field = value
            val choreographer = Choreographer.getInstance()
            if (value) {
                last = 0L
                choreographer.postFrameCallback(this)
            } else {
                choreographer.removeFrameCallback(this)
            }
        }

    override fun doFrame(frameTimeNanos: Long) {
        if (!running) return
        // A vsync a little before the 1/30 s is on time (a 60 Hz panel's second one comes at 33.3 ms).
        if (frameTimeNanos - last >= INTERVAL_NANOS - SLACK_NANOS) {
            last = frameTimeNanos
            frame()
        }
        Choreographer.getInstance().postFrameCallback(this)
    }

    private companion object {
        const val INTERVAL_NANOS = 1_000_000_000L / 30
        const val SLACK_NANOS = 4_000_000L
    }
}
