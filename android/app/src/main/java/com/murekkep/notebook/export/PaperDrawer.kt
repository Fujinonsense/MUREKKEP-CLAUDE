package com.murekkep.notebook.export

import android.graphics.Canvas
import android.graphics.Paint
import com.murekkep.notebook.data.PaperStyle

// Port of PaperDrawer in Murekkep.swiftpm/Templates.swift for the templates the Android edition
// draws (plain, lined, grid, dotted), with the iPad's spacing, margins and colours. The paper shader
// PAPER_FRAGMENT_MAIN in render/InkShaders.kt draws the same paper on screen: rules 28 points apart
// from 84 down, the margin at 72, the grid every 20, dots 0.9 wide every 20, the same blues and
// greys. (The shader's rules run to the page's foot; here, as on the iPad's page, they stop 8
// points above it.)

/** Draws a template into a canvas whose user space is page points (y down), white first. */
object PaperDrawer {
    /** The colours of Templates.swift's `Draw`. */
    private val LINE_BLUE = FlatInkGeometry.argb(0.66f, 0.80f, 0.95f, 1f)
    private val GRID_BLUE = FlatInkGeometry.argb(0.78f, 0.85f, 0.93f, 1f)
    private val MARGIN = FlatInkGeometry.argb(0.96f, 0.62f, 0.62f, 1f)
    private val DOT = FlatInkGeometry.argb(0.60f, 0.64f, 0.70f, 1f)
    private val WHITE = FlatInkGeometry.argb(1f, 1f, 1f, 1f)

    /** Lined paper: a rule every 28 points from 84 down to 8 above the foot, the margin at 72. */
    const val RULE_SPACING = 28f
    const val RULE_TOP = 84f
    const val RULE_FOOT = 8f
    const val MARGIN_X = 72f
    const val RULE_WIDTH = 0.9f

    /** Grid paper: a line every 20 points from the page's corner, 0.7 wide. */
    const val GRID_STEP = 20f
    const val GRID_WIDTH = 0.7f

    /** Dotted paper: a dot 0.9 in radius every 20 points from the page's corner. */
    const val DOT_STEP = 20f
    const val DOT_RADIUS = 0.9f

    fun draw(style: PaperStyle, width: Float, height: Float, canvas: Canvas) {
        canvas.save()
        canvas.drawRect(0f, 0f, width, height, fill(WHITE))
        when (exported(style)) {
            PaperStyle.PLAIN -> Unit
            PaperStyle.GRID -> grid(canvas, width, height, GRID_STEP, GRID_BLUE, GRID_WIDTH)
            PaperStyle.DOTTED -> dotted(canvas, width, height)
            else -> lined(canvas, width, height, RULE_SPACING, RULE_TOP, MARGIN_X)
        }
        canvas.restore()
    }

    /** What a notebook's template exports as: the four the screen draws as themselves, every
     *  other as lined (the Android canvas shows lined paper for every notebook today). */
    fun exported(style: PaperStyle): PaperStyle = when (style) {
        PaperStyle.PLAIN, PaperStyle.LINED, PaperStyle.GRID, PaperStyle.DOTTED -> style
        else -> PaperStyle.LINED
    }

    /** `from, from + step, ...` up to and including `to`: the iPad's `rules` and `grid` loops,
     *  summed in double as CGFloat is. */
    fun positions(from: Float, to: Float, step: Float): FloatArray {
        if (step <= 0f) return floatArrayOf()
        val out = ArrayList<Float>()
        var v = from.toDouble()
        while (v <= to) {
            out.add(v.toFloat())
            v += step
        }
        return out.toFloatArray()
    }

    private fun lined(canvas: Canvas, w: Float, h: Float, spacing: Float, top: Float, margin: Float) {
        val rule = stroke(LINE_BLUE, RULE_WIDTH)
        for (y in positions(top, h - RULE_FOOT, spacing)) {
            canvas.drawLine(0f, y, w, y, rule)
        }
        canvas.drawLine(margin, 0f, margin, h, stroke(MARGIN, RULE_WIDTH))
    }

    private fun grid(canvas: Canvas, w: Float, h: Float, step: Float, color: Int, width: Float) {
        val line = stroke(color, width)
        for (x in positions(0f, w, step)) {
            canvas.drawLine(x, 0f, x, h, line)
        }
        for (y in positions(0f, h, step)) {
            canvas.drawLine(0f, y, w, y, line)
        }
    }

    private fun dotted(canvas: Canvas, w: Float, h: Float) {
        val dot = fill(DOT)
        for (y in positions(0f, h, DOT_STEP)) {
            for (x in positions(0f, w, DOT_STEP)) {
                canvas.drawOval(x - DOT_RADIUS, y - DOT_RADIUS, x + DOT_RADIUS, y + DOT_RADIUS, dot)
            }
        }
    }

    private fun fill(color: Int) = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
        this.color = color
    }

    /** A hairline as Core Graphics strokes it: butt caps. */
    private fun stroke(color: Int, width: Float) = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        this.color = color
        strokeWidth = width
    }
}
