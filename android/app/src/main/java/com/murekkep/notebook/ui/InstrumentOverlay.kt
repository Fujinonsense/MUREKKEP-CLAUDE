package com.murekkep.notebook.ui

import android.graphics.Paint
import android.graphics.Typeface
import android.os.Build
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.asAndroidPath
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.unit.dp
import com.murekkep.notebook.canvas.CompassOverlay
import com.murekkep.notebook.canvas.InstrumentOverlay
import com.murekkep.notebook.ink.Instrument
import com.murekkep.notebook.ink.InstrumentKind
import com.murekkep.notebook.ink.POINTS_PER_MILLIMETRE
import com.murekkep.notebook.ink.Pt
import com.murekkep.notebook.ink.roundedAwayToInt
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.sin

// The drafting instruments and the compass over the ink, as the iPad's CanvasOverlayView draws them
// (CanvasOverlay.swift: drawInstrument, legTicks, label, drawCompass): a pale blue body with a soft
// shadow and an accent hairline; the ruler's millimetres and centimetres, the set squares' legs and
// corner angles, the protractor's degrees both ways round, the numbers turned with the instrument.
// Its sizes are the iPad's millimetres of the page, so they zoom with it; its lines are dp wide, as
// the iPad's view points. The page stays paper in the dark look, so the instrument keeps its colours.

/** The body: a pale blue, mostly opaque. */
private val Body = Color(0.97f, 0.98f, 1f, 0.72f)

/** The ticks and the numbers, nearly black. */
private val Ticks = Color(0.12f, 0.12f, 0.12f, 0.85f)
private val Numbers = Color(0.15f, 0.15f, 0.15f, 0.9f)

/** A millimetre of the page in points. */
private val MM = POINTS_PER_MILLIMETRE.toFloat()

/** The body's paint, the pale blue with its shadow; made once (Compose draws on the main thread only). */
private val BodyPaint: Paint by lazy { Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Body.toArgb() } }

/** The numbers' paint: the system font's medium weight (the iPad's monospaced digits are the system's
 *  too), centred on their point; made once. */
private val NumberPaint: Paint by lazy {
    Paint(Paint.ANTI_ALIAS_FLAG).apply {
        typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
        textAlign = Paint.Align.CENTER
        // Every digit as wide as the others, as the iPad's monospaced digits.
        fontFeatureSettings = "tnum"
    }
}

/** A number on the instrument: where its middle is in the instrument's own frame and how tall it is
 *  (points); an [inner] one (the protractor's inner scale) is in the accent. */
private class Mark(val text: String, val x: Float, val y: Float, val size: Float, val inner: Boolean)

/** What an instrument of a kind shows in its own frame, level (points): its ticks as segments (x0, y0,
 *  x1, y1 each) and its numbers. */
private class Face(val ticks: FloatArray, val marks: List<Mark>)

/** Every kind's face, worked out once: a redraw only places it. */
private val Faces: Map<InstrumentKind, Face> by lazy { InstrumentKind.entries.associateWith(::faceOf) }

private fun faceOf(kind: InstrumentKind): Face {
    val ticks = ArrayList<Float>()
    val marks = ArrayList<Mark>()
    fun tick(x0: Float, y0: Float, x1: Float, y1: Float) {
        ticks.add(x0)
        ticks.add(y0)
        ticks.add(x1)
        ticks.add(y1)
    }
    fun mark(text: String, x: Float, y: Float, size: Float, inner: Boolean = false) {
        marks.add(Mark(text, x, y, size, inner))
    }
    /** Ticks along a set square's leg from its right-angled corner, a millimetre apart, standing [ix], [iy] inwards. */
    fun legTicks(a: Pt, b: Pt, ix: Float, iy: Float) {
        val length = hypot(b.x - a.x, b.y - a.y)
        if (!(length > 0)) return
        val ux = ((b.x - a.x) / length).toFloat()
        val uy = ((b.y - a.y) / length).toFloat()
        val count = (length / POINTS_PER_MILLIMETRE).toInt() - 6
        if (count <= 6) return
        for (i in 6..count) {
            val px = a.x.toFloat() + ux * i * MM
            val py = a.y.toFloat() + uy * i * MM
            val len = if (i % 10 == 0) 3.6f * MM else if (i % 5 == 0) 2.6f * MM else 1.5f * MM
            tick(px, py, px + ix * len, py + iy * len)
        }
    }
    val outline = Instrument(kind, Pt.ZERO, 0.0).localOutline
    when (kind) {
        InstrumentKind.RULER -> {
            val half = (Instrument.RULER_LENGTH / 2).toFloat()
            val h = (Instrument.RULER_WIDTH / 2).toFloat()
            val count = roundedAwayToInt(Instrument.RULER_LENGTH / POINTS_PER_MILLIMETRE)
            for (i in 0..count) {
                val x = -half + i * MM
                val len = if (i % 10 == 0) 4.2f * MM else if (i % 5 == 0) 3f * MM else 1.7f * MM
                tick(x, -h, x, -h + len)
                tick(x, h, x, h - len)
            }
            for (cm in 0..count / 10) mark("$cm", -half + cm * 10 * MM, -h + 6.4f * MM, 2.7f * MM)
            mark("cm", half - 6 * MM, h - 6.4f * MM, 2.4f * MM)
        }
        InstrumentKind.SET_SQUARE_45, InstrumentKind.SET_SQUARE_3060 -> {
            val a = outline[0]
            val b = outline[1]
            val top = outline[2]
            legTicks(a, b, 0f, -1f)
            legTicks(a, top, 1f, 0f)
            val square45 = kind == InstrumentKind.SET_SQUARE_45
            mark(if (square45) "45°" else "30°", b.x.toFloat() - 16 * MM, b.y.toFloat() - 4 * MM, 3 * MM)
            mark(if (square45) "45°" else "60°", top.x.toFloat() + 5 * MM, top.y.toFloat() + 14 * MM, 3 * MM)
            mark("90°", a.x.toFloat() + 7 * MM, a.y.toFloat() - 6 * MM, 3 * MM)
        }
        InstrumentKind.PROTRACTOR -> {
            val r = Instrument.PROTRACTOR_RADIUS.toFloat()
            for (d in 0..180) {
                val ang = d * PI / 180
                val dx = cos(ang).toFloat()
                val dy = -sin(ang).toFloat()
                val len = if (d % 10 == 0) 5 * MM else if (d % 5 == 0) 3.4f * MM else 2 * MM
                tick(dx * r, dy * r, dx * (r - len), dy * (r - len))
            }
            tick(-r, 0f, r, 0f)
            tick(-3 * MM, 0f, 3 * MM, 0f)
            tick(0f, 0f, 0f, -4 * MM)
            for (d in 0..180 step 10) {
                val ang = d * PI / 180
                val dx = cos(ang).toFloat()
                val dy = -sin(ang).toFloat()
                mark("$d", dx * (r - 8.5f * MM), dy * (r - 8.5f * MM), 2.5f * MM)
                mark("${180 - d}", dx * (r - 13 * MM), dy * (r - 13 * MM), 2 * MM, inner = true)
            }
        }
    }
    return Face(ticks.toFloatArray(), marks)
}

/** The instrument [o] with its ticks and numbers, its outline in [accent]. */
internal fun DrawScope.drawInstrument(o: InstrumentOverlay, accent: Color) {
    val z = o.zoom
    val c = cos(o.angle)
    val s = sin(o.angle)
    val outline = Instrument(o.kind, Pt.ZERO, 0.0).localOutline
    val body = Path()
    for ((i, p) in outline.withIndex()) {
        val lx = p.x.toFloat()
        val ly = p.y.toFloat()
        val vx = o.x + (lx * c - ly * s) * z
        val vy = o.y + (lx * s + ly * c) * z
        if (i == 0) body.moveTo(vx, vy) else body.lineTo(vx, vy)
    }
    body.close()
    // The body's shadow falls down the screen however the instrument is turned.
    drawIntoCanvas { canvas ->
        val paint = BodyPaint
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            paint.setShadowLayer(shadowRadius(5.dp.toPx()), 0f, 3.dp.toPx(), Color.Black.copy(alpha = 0.18f).toArgb())
        }
        canvas.nativeCanvas.drawPath(body.asAndroidPath(), paint)
    }
    drawPath(body, accent.copy(alpha = 0.55f), style = Stroke(width = 1.1.dp.toPx()))

    val face = Faces.getValue(o.kind)
    // Level round the instrument's middle: the canvas turns them into place below.
    val ticks = Path()
    val t = face.ticks
    for (k in t.indices step 4) {
        ticks.moveTo(o.x + t[k] * z, o.y + t[k + 1] * z)
        ticks.lineTo(o.x + t[k + 2] * z, o.y + t[k + 3] * z)
    }
    rotate(o.angle * 180f / PI.toFloat(), pivot = Offset(o.x, o.y)) {
        drawPath(ticks, Ticks, style = Stroke(width = 0.7.dp.toPx()))
        drawIntoCanvas { canvas ->
            val paint = NumberPaint
            val numbers = Numbers.toArgb()
            val inner = accent.toArgb()
            for (m in face.marks) {
                paint.color = if (m.inner) inner else numbers
                paint.textSize = m.size * z
                canvas.nativeCanvas.drawText(m.text, o.x + m.x * z, o.y + m.y * z - (paint.ascent() + paint.descent()) / 2, paint)
            }
        }
    }
}

/** The compass [o]: its circle dashed, a cross on its center, and the leg to the pen while it moves. */
internal fun DrawScope.drawCompass(o: CompassOverlay, accent: Color) {
    val center = Offset(o.x, o.y)
    if (o.radius > 1.dp.toPx()) {
        val dash = PathEffect.dashPathEffect(floatArrayOf(5.dp.toPx(), 5.dp.toPx()))
        drawCircle(accent.copy(alpha = 0.45f), radius = o.radius, center = center, style = Stroke(width = 1.dp.toPx(), pathEffect = dash))
    }
    val arm = 7.dp.toPx()
    val line = 1.6.dp.toPx()
    drawLine(accent, Offset(o.x - arm, o.y), Offset(o.x + arm, o.y), strokeWidth = line)
    drawLine(accent, Offset(o.x, o.y - arm), Offset(o.x, o.y + arm), strokeWidth = line)
    o.pen?.let { drawLine(accent, center, Offset(it.x, it.y), strokeWidth = line) }
}

/** The radius Android's shadow takes for a Gaussian of [sigma] (it blurs with sigma = 0.57735 r + 0.5);
 *  the iPad's blur of 10 points is about a sigma of 5. */
private fun shadowRadius(sigma: Float): Float = if (sigma > 0.5f) (sigma - 0.5f) / 0.57735f else 0f
