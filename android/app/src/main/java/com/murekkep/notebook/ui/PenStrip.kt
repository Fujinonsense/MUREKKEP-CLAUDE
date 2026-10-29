@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

package com.murekkep.notebook.ui

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.outlined.Category
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Slider
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.VerticalDivider
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.murekkep.notebook.R
import com.murekkep.notebook.ink.Brush
import com.murekkep.notebook.ink.BrushGroup
import com.murekkep.notebook.ink.EraserMode
import com.murekkep.notebook.ink.InkColor
import com.murekkep.notebook.ink.ShapeKind
import com.murekkep.notebook.ink.ShapeName
import java.util.Locale

// The pen dock under the canvas (Murekkep.swiftpm/PenStrip.swift, ToolPalette.swift, DraftingTools.swift
// ShapePicker): the eraser, the lasso, the shapes and every pen by group in one scrolling strip, each
// pen named in the user's language and the Pro pens starred (all usable for now; Play Billing comes
// later). Under it, the chosen pen's six colors and a width slider, or for the eraser its mode
// (whole stroke, partial) and size; the shapes add their kinds, dashes and a polygon's sides.

fun InkColor.toColor(): Color = Color(r, g, b, a)

private val isTurkish: Boolean
    get() = Locale.getDefault().language == "tr"

/** The pen's name in the user's language: Turkish, else English. */
fun Brush.localizedTitle(): String = if (isTurkish) titleTr else titleEn

fun BrushGroup.localizedTitle(): String = if (isTurkish) titleTr else titleEn

/** A shape's name in the user's language: Turkish, else English. */
fun ShapeName.localizedTitle(): String = if (isTurkish) titleTr else titleEn

@Composable
fun ToolDock(state: EditorState) {
    val tool = state.tool
    Surface(
        color = MaterialTheme.colorScheme.surface,
        tonalElevation = 2.dp,
        shadowElevation = 8.dp,
        shape = RoundedCornerShape(topStart = 20.dp, topEnd = 20.dp),
    ) {
        Column(
            Modifier
                .fillMaxWidth()
                .windowInsetsPadding(WindowInsets.safeDrawing.only(WindowInsetsSides.Bottom + WindowInsetsSides.Horizontal))
                .padding(top = 10.dp, bottom = 8.dp),
        ) {
            PenStrip(state)
            Spacer(Modifier.height(8.dp))
            if (tool is Tool.Eraser) {
                EraserOptions(state)
            } else {
                if (tool is Tool.Shape) {
                    ShapeOptions(state)
                    Spacer(Modifier.height(8.dp))
                }
                PenOptions(state, state.activeBrush)
            }
        }
    }
}

@Composable
private fun PenStrip(state: EditorState) {
    val tool = state.tool
    Row(
        Modifier
            .fillMaxWidth()
            .horizontalScroll(rememberScrollState())
            .padding(horizontal = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        EraserChip(selected = tool is Tool.Eraser, onClick = { state.toggleEraser() })
        LassoChip(
            selected = tool is Tool.Lasso,
            onClick = { state.tool = if (tool is Tool.Lasso) Tool.Brush(state.lastBrush) else Tool.Lasso },
        )
        ToolChip(
            title = stringResource(R.string.shapes),
            selected = tool is Tool.Shape,
            onClick = { state.tool = if (tool is Tool.Shape) Tool.Brush(state.lastBrush) else Tool.Shape },
        ) { Icon(Icons.Outlined.Category, contentDescription = null, modifier = Modifier.size(16.dp)) }
        VerticalDivider(Modifier.height(24.dp).padding(horizontal = 4.dp))
        for (group in BrushGroup.entries) {
            Text(
                group.localizedTitle().uppercase(Locale.getDefault()),
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(start = 6.dp, end = 2.dp),
            )
            for (brush in group.brushes) {
                PenChip(
                    brush = brush,
                    color = state.color(brush),
                    selected = tool is Tool.Brush && tool.brush == brush,
                    onClick = { state.tool = Tool.Brush(brush) },
                )
            }
        }
    }
}

@Composable
private fun PenChip(brush: Brush, color: InkColor, selected: Boolean, onClick: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    Surface(
        onClick = onClick,
        shape = RoundedCornerShape(12.dp),
        color = if (selected) scheme.primaryContainer else scheme.surfaceVariant.copy(alpha = 0.55f),
        contentColor = if (selected) scheme.onPrimaryContainer else scheme.onSurface,
        border = if (selected) BorderStroke(1.dp, scheme.primary.copy(alpha = 0.6f)) else null,
    ) {
        Row(
            Modifier.padding(start = 10.dp, end = 12.dp, top = 7.dp, bottom = 7.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(7.dp),
        ) {
            Box(
                Modifier
                    .size(12.dp)
                    .clip(CircleShape)
                    .background(color.toColor())
                    .border(1.dp, scheme.onSurface.copy(alpha = 0.15f), CircleShape),
            )
            Text(brush.localizedTitle(), style = MaterialTheme.typography.labelLarge, maxLines = 1)
            if (brush.isPremium) {
                Icon(
                    Icons.Filled.Star,
                    contentDescription = stringResource(R.string.premium_pen),
                    tint = PremiumGold,
                    modifier = Modifier.size(12.dp),
                )
            }
        }
    }
}

@Composable
private fun EraserChip(selected: Boolean, onClick: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    Surface(
        onClick = onClick,
        shape = RoundedCornerShape(12.dp),
        color = if (selected) scheme.primaryContainer else scheme.surfaceVariant.copy(alpha = 0.55f),
        contentColor = if (selected) scheme.onPrimaryContainer else scheme.onSurface,
        border = if (selected) BorderStroke(1.dp, scheme.primary.copy(alpha = 0.6f)) else null,
    ) {
        Row(
            Modifier.padding(start = 10.dp, end = 12.dp, top = 7.dp, bottom = 7.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(7.dp),
        ) {
            EraserGlyph(Modifier.size(16.dp))
            Text(stringResource(R.string.eraser), style = MaterialTheme.typography.labelLarge, maxLines = 1)
        }
    }
}

/** The lasso (CanvasChrome.kt): pick strokes by drawing round them. */
@Composable
private fun LassoChip(selected: Boolean, onClick: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    ToolChip(stringResource(R.string.lasso), selected, onClick) {
        LassoGlyph(Modifier.size(16.dp), if (selected) scheme.onPrimaryContainer else scheme.onSurface)
    }
}

/** A tool in the strip: its glyph and name, highlighted while it is the one in the hand. */
@Composable
private fun ToolChip(title: String, selected: Boolean, onClick: () -> Unit, glyph: @Composable () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    Surface(
        onClick = onClick,
        shape = RoundedCornerShape(12.dp),
        color = if (selected) scheme.primaryContainer else scheme.surfaceVariant.copy(alpha = 0.55f),
        contentColor = if (selected) scheme.onPrimaryContainer else scheme.onSurface,
        border = if (selected) BorderStroke(1.dp, scheme.primary.copy(alpha = 0.6f)) else null,
    ) {
        Row(
            Modifier.padding(start = 10.dp, end = 12.dp, top = 7.dp, bottom = 7.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(7.dp),
        ) {
            glyph()
            Text(title, style = MaterialTheme.typography.labelLarge, maxLines = 1)
        }
    }
}

// MARK: The shape tool's options

/** The shape tool's kinds, dashed lines and a regular polygon's sides, then how it works. */
@Composable
private fun ShapeOptions(state: EditorState) {
    Column(Modifier.fillMaxWidth()) {
        Row(
            Modifier
                .fillMaxWidth()
                .horizontalScroll(rememberScrollState())
                .padding(horizontal = 16.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            for (kind in ShapeKind.entries) {
                ModeChip(label = kind.shapeName.localizedTitle(), selected = state.shapeKind == kind, onClick = { state.shapeKind = kind })
            }
            VerticalDivider(Modifier.height(24.dp).padding(horizontal = 4.dp))
            ModeChip(
                label = stringResource(R.string.dashed_line),
                selected = state.shapeDashed,
                onClick = { state.shapeDashed = !state.shapeDashed },
            )
            if (state.shapeKind == ShapeKind.POLYGON) {
                IconButton(onClick = { state.polygonSides = (state.polygonSides - 1).coerceAtLeast(3) }, enabled = state.polygonSides > 3) {
                    Icon(Icons.Filled.Remove, contentDescription = null)
                }
                Text(stringResource(R.string.polygon_sides, state.polygonSides), style = MaterialTheme.typography.labelLarge)
                IconButton(onClick = { state.polygonSides = (state.polygonSides + 1).coerceAtMost(12) }, enabled = state.polygonSides < 12) {
                    Icon(Icons.Filled.Add, contentDescription = null)
                }
            }
        }
        Text(
            stringResource(R.string.shapes_help),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 2.dp),
        )
    }
}

/** A small pink eraser with a dark band, drawn on a slant (no such icon in the Material set). */
@Composable
private fun EraserGlyph(modifier: Modifier) {
    val body = Color(0xFFE88BA0)
    val band = Color(0xFF4A5B9E)
    Canvas(modifier) {
        rotate(-40f) {
            val w = size.width * 0.96f
            val h = size.height * 0.5f
            val left = (size.width - w) / 2f
            val top = (size.height - h) / 2f
            drawRoundRect(color = body, topLeft = Offset(left, top), size = Size(w, h), cornerRadius = CornerRadius(h * 0.3f))
            clipRect(left, top, left + w * 0.42f, top + h) {
                drawRoundRect(color = band, topLeft = Offset(left, top), size = Size(w, h), cornerRadius = CornerRadius(h * 0.3f))
            }
        }
    }
}

// MARK: The chosen pen's controls

@Composable
private fun PenOptions(state: EditorState, brush: Brush) {
    val current = state.color(brush)
    val width = state.width(brush)
    BoxWithConstraints(Modifier.fillMaxWidth().padding(horizontal = 16.dp)) {
        if (maxWidth >= 520.dp) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Palette(brush, current) { state.setColor(brush, it) }
                Spacer(Modifier.width(24.dp))
                WidthControl(brush, current, width, Modifier.weight(1f)) { state.setWidth(brush, it) }
            }
        } else {
            Column {
                Palette(brush, current) { state.setColor(brush, it) }
                Spacer(Modifier.height(6.dp))
                WidthControl(brush, current, width, Modifier.fillMaxWidth()) { state.setWidth(brush, it) }
            }
        }
    }
}

@Composable
private fun Palette(brush: Brush, current: InkColor, onPick: (InkColor) -> Unit) {
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
        brush.palette.forEachIndexed { index, color ->
            ColorDot(
                color = color,
                selected = color == current,
                label = stringResource(R.string.color_number, index + 1),
                onClick = { onPick(color) },
            )
        }
    }
}

@Composable
private fun ColorDot(color: InkColor, selected: Boolean, label: String, onClick: () -> Unit) {
    val ring = MaterialTheme.colorScheme.onSurface
    Box(
        Modifier
            .size(32.dp)
            .clip(CircleShape)
            .clickable(onClick = onClick)
            .semantics { contentDescription = label }
            .then(if (selected) Modifier.border(2.dp, ring, CircleShape) else Modifier)
            .padding(6.dp)
            .clip(CircleShape)
            .background(color.toColor())
            .border(1.dp, ring.copy(alpha = 0.15f), CircleShape),
    )
}

@Composable
private fun WidthControl(brush: Brush, color: InkColor, width: Float, modifier: Modifier, onChange: (Float) -> Unit) {
    val range = brush.widthRange
    val label = stringResource(R.string.pen_width)
    val fraction = ((width - range.start) / (range.endInclusive - range.start)).coerceIn(0f, 1f)
    Row(modifier, verticalAlignment = Alignment.CenterVertically) {
        // The line as it would land: a dot of the pen's color that grows with the width.
        Box(Modifier.size(34.dp), contentAlignment = Alignment.Center) {
            Box(
                Modifier
                    .size((6f + 26f * fraction).dp)
                    .clip(CircleShape)
                    .background(color.toColor())
                    .border(1.dp, MaterialTheme.colorScheme.onSurface.copy(alpha = 0.15f), CircleShape),
            )
        }
        Slider(
            value = width,
            onValueChange = onChange,
            valueRange = range,
            modifier = Modifier.weight(1f).semantics { contentDescription = label },
        )
    }
}

// MARK: The eraser's controls

@Composable
private fun EraserOptions(state: EditorState) {
    BoxWithConstraints(Modifier.fillMaxWidth().padding(horizontal = 16.dp)) {
        if (maxWidth >= 520.dp) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                EraserModes(state)
                Spacer(Modifier.width(24.dp))
                EraserSize(state, Modifier.weight(1f))
            }
        } else {
            Column {
                EraserModes(state)
                Spacer(Modifier.height(6.dp))
                EraserSize(state, Modifier.fillMaxWidth())
            }
        }
    }
}

@Composable
private fun EraserModes(state: EditorState) {
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
        ModeChip(
            label = stringResource(R.string.eraser_whole_stroke),
            selected = state.eraserMode == EraserMode.STROKE,
            onClick = { state.eraserMode = EraserMode.STROKE },
        )
        ModeChip(
            label = stringResource(R.string.eraser_partial),
            selected = state.eraserMode == EraserMode.PARTIAL,
            onClick = { state.eraserMode = EraserMode.PARTIAL },
        )
    }
}

@Composable
private fun ModeChip(label: String, selected: Boolean, onClick: () -> Unit) {
    FilterChip(
        selected = selected,
        onClick = onClick,
        label = { Text(label) },
        leadingIcon = if (selected) {
            { Icon(Icons.Filled.Check, contentDescription = null, modifier = Modifier.size(16.dp)) }
        } else {
            null
        },
    )
}

@Composable
private fun EraserSize(state: EditorState, modifier: Modifier) {
    val label = stringResource(R.string.eraser_size)
    val fraction = ((state.eraserSize - 4f) / 60f).coerceIn(0f, 1f)
    Row(modifier, verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(34.dp), contentAlignment = Alignment.Center) {
            Box(
                Modifier
                    .size((6f + 26f * fraction).dp)
                    .clip(CircleShape)
                    .border(1.5.dp, MaterialTheme.colorScheme.onSurface, CircleShape),
            )
        }
        Slider(
            value = state.eraserSize,
            onValueChange = { state.eraserSize = it },
            valueRange = 4f..64f,
            modifier = Modifier.weight(1f).semantics { contentDescription = label },
        )
    }
}
