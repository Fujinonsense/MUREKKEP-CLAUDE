package com.murekkep.notebook.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.outlined.Brush
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.LibraryAdd
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.murekkep.notebook.R
import com.murekkep.notebook.canvas.CanvasOverlay
import com.murekkep.notebook.ink.Lasso
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin

// What the canvas shows over the ink and the lasso's bar (CanvasOverlay.swift and DraftingTools.swift
// SelectionBar on iPad): the lasso's loop, the selection's frame, a recognized shape's handles, the
// shape tool's preview and the measurement next to the pen; the bar of what can be done with the
// selection; the lasso's glyph for the pen dock.

/** The overlay's blue: the brand's ink blue (the iPad's overlay colour). */
private val Accent = Color(0xFF2457D6)

/** The lasso's loop, the selection's dashed frame with its turn handle and corner handles, the
 *  shape tool's preview, a recognized shape's handles and the measurement next to the pen, as the
 *  canvas reports them in view pixels. Touches go through. */
@Composable
fun CanvasOverlayLayer(overlay: CanvasOverlay) {
    val measurer = rememberTextMeasurer()
    val labelStyle = TextStyle(color = Color.White, fontSize = 13.sp)
    Canvas(Modifier.fillMaxSize()) {
        val dash = PathEffect.dashPathEffect(floatArrayOf(Lasso.DASH.dp.toPx(), Lasso.GAP.dp.toPx()))
        overlay.lasso?.let { a ->
            val path = Path()
            path.moveTo(a[0], a[1])
            for (i in 1 until a.size / 2) path.lineTo(a[2 * i], a[2 * i + 1])
            drawPath(path, Accent, style = Stroke(width = 1.4.dp.toPx(), pathEffect = dash))
        }
        overlay.selection?.let { box ->
            val pad = Lasso.FRAME_PAD.dp.toPx()
            drawSelectionFrame(Rect(box.left - pad, box.top - pad, box.right + pad, box.bottom + pad), dash)
        }
        overlay.preview?.let { paths ->
            val line = Stroke(width = 1.6.dp.toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round)
            for (a in paths) {
                if (a.size < 4) continue
                val path = Path()
                path.moveTo(a[0], a[1])
                for (i in 1 until a.size / 2) path.lineTo(a[2 * i], a[2 * i + 1])
                drawPath(path, Accent.copy(alpha = 0.9f), style = line)
            }
        }
        overlay.shapeHandles?.let { drawShapeHandles(it) }
        overlay.label?.let { label ->
            val text = measurer.measure(label.text, labelStyle)
            val padX = 8.dp.toPx()
            val padY = 4.dp.toPx()
            val w = text.size.width + 2 * padX
            val h = text.size.height + 2 * padY
            // Above and to the right of the pen, clear of the hand.
            val left = (label.x + 26.dp.toPx() - w / 2).coerceIn(0f, (size.width - w).coerceAtLeast(0f))
            val top = (label.y - 30.dp.toPx() - h / 2).coerceAtLeast(0f)
            drawRoundRect(Color(0xE6202124), Offset(left, top), Size(w, h), CornerRadius(h / 2))
            drawText(text, topLeft = Offset(left + padX, top + padY))
        }
    }
}

/** The frame round the selection: a light fill, a dashed outline, a turn handle on a short stem
 *  above it and a resize handle on every corner (view pixels). */
private fun DrawScope.drawSelectionFrame(frame: Rect, dash: PathEffect) {
    drawRect(Accent.copy(alpha = 0.06f), frame.topLeft, frame.size)
    drawRect(Accent, frame.topLeft, frame.size, style = Stroke(width = 1.4.dp.toPx(), pathEffect = dash))
    val turn = Offset(frame.center.x, frame.top - Lasso.TURN_HANDLE_OFFSET.dp.toPx())
    drawLine(Accent, Offset(turn.x, frame.top), Offset(turn.x, turn.y + 9.dp.toPx()), strokeWidth = 1.2.dp.toPx())
    drawCircle(Accent, radius = 10.dp.toPx(), center = turn)
    // A white turning arrow inside the disc.
    val r = 5.dp.toPx()
    val glyph = Stroke(width = 1.6.dp.toPx(), cap = StrokeCap.Round)
    drawArc(
        Color.White, startAngle = -153f, sweepAngle = 252f, useCenter = false,
        topLeft = Offset(turn.x - r, turn.y - r), size = Size(2 * r, 2 * r), style = glyph,
    )
    val tip = Offset(turn.x + r * cos(0.55 * PI).toFloat(), turn.y + r * sin(0.55 * PI).toFloat())
    val head = Path().apply {
        moveTo(tip.x + 2.6.dp.toPx(), tip.y - 0.4.dp.toPx())
        lineTo(tip.x, tip.y)
        lineTo(tip.x + 0.6.dp.toPx(), tip.y - 2.8.dp.toPx())
    }
    drawPath(head, Color.White, style = glyph)
    for (c in listOf(frame.topLeft, frame.topRight, frame.bottomRight, frame.bottomLeft)) {
        drawCircle(Color.White, radius = 8.dp.toPx(), center = c)
        drawCircle(Accent, radius = 7.dp.toPx(), center = c, style = Stroke(width = 2.dp.toPx()))
    }
}

/** Round handles on the corners (or axis ends) of a recognized shape, and a filled one with arrows
 *  in its middle (the last) that moves it whole. */
private fun DrawScope.drawShapeHandles(a: FloatArray) {
    val n = a.size / 2
    for (i in 0 until n) {
        val c = Offset(a[2 * i], a[2 * i + 1])
        if (i == n - 1) {
            drawCircle(Accent.copy(alpha = 0.9f), radius = 11.dp.toPx(), center = c)
            val arrow = Stroke(width = 1.5.dp.toPx(), cap = StrokeCap.Round)
            for ((dx, dy) in listOf(1f to 0f, -1f to 0f, 0f to 1f, 0f to -1f)) {
                val tip = Offset(c.x + dx * 6.5f.dp.toPx(), c.y + dy * 6.5f.dp.toPx())
                val w = 2.2f.dp.toPx()
                val path = Path().apply {
                    moveTo(c.x + dx * 2.dp.toPx(), c.y + dy * 2.dp.toPx())
                    lineTo(tip.x, tip.y)
                    moveTo(tip.x - dx * w + dy * w, tip.y - dy * w + dx * w)
                    lineTo(tip.x, tip.y)
                    lineTo(tip.x - dx * w - dy * w, tip.y - dy * w - dx * w)
                }
                drawPath(path, Color.White, style = arrow)
            }
        } else {
            drawCircle(Color.White, radius = 9.dp.toPx(), center = c)
            drawCircle(Accent, radius = 8.dp.toPx(), center = c, style = Stroke(width = 2.dp.toPx()))
        }
    }
}

/** What can be done with the lasso's strokes: delete them, duplicate them, give them the current
 *  pen, or let them go. A capsule over the page, on the pen bar's paper (the iPad's SelectionBar);
 *  every touch on it stays on it. */
@Composable
fun SelectionBar(state: EditorState, modifier: Modifier = Modifier) {
    val z = Zen.colors
    Row(
        modifier
            .floating(28.dp)
            .pointerInput(Unit) {}
            .padding(horizontal = 8.dp, vertical = 6.dp),
        horizontalArrangement = Arrangement.spacedBy(4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        SelectionAction(stringResource(R.string.delete), Icons.Outlined.Delete, MaterialTheme.colorScheme.error) {
            state.deleteSelection()
        }
        SelectionAction(stringResource(R.string.duplicate), Icons.Outlined.LibraryAdd) { state.duplicateSelection() }
        SelectionAction(stringResource(R.string.apply_ink), Icons.Outlined.Brush) { state.restyleSelection() }
        Box(Modifier.size(1.dp, 26.dp).background(z.rule))
        SelectionAction(stringResource(R.string.done), Icons.Filled.Check) { state.clearSelection() }
    }
}

/** An action of the selection bar: an 18 dp icon over its 11 sp name, in ink (delete in red). */
@Composable
private fun SelectionAction(title: String, icon: ImageVector, tint: Color = Color.Unspecified, onClick: () -> Unit) {
    val color = if (tint == Color.Unspecified) Zen.colors.ink else tint
    Column(
        Modifier
            .clip(RoundedCornerShape(Zen.control))
            .clickable(onClick = onClick)
            .defaultMinSize(minWidth = 52.dp, minHeight = 44.dp)
            .padding(horizontal = 8.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(2.dp, Alignment.CenterVertically),
    ) {
        Icon(icon, contentDescription = null, tint = color, modifier = Modifier.size(18.dp))
        Text(
            title,
            style = MaterialTheme.typography.labelSmall.copy(fontSize = 11.sp, lineHeight = 13.sp, fontWeight = FontWeight.Medium),
            color = color,
            maxLines = 1,
        )
    }
}

/** A dashed loop with a short tail: the lasso (no such icon in the Material set). */
@Composable
fun LassoGlyph(modifier: Modifier, color: Color) {
    Canvas(modifier) {
        val w = size.width
        val h = size.height
        val dash = PathEffect.dashPathEffect(floatArrayOf(w * 0.16f, w * 0.1f))
        val line = 1.5.dp.toPx()
        drawOval(color, Offset(w * 0.06f, h * 0.08f), Size(w * 0.88f, h * 0.6f), style = Stroke(width = line, pathEffect = dash))
        val tail = Path().apply {
            moveTo(w * 0.3f, h * 0.66f)
            quadraticTo(w * 0.2f, h * 0.84f, w * 0.38f, h * 0.96f)
        }
        drawPath(tail, color, style = Stroke(width = line, cap = StrokeCap.Round))
    }
}
