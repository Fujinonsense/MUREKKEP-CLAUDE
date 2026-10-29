package com.murekkep.notebook.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.outlined.Architecture
import androidx.compose.material.icons.outlined.ChangeHistory
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.Straighten
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.MenuDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.path
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.murekkep.notebook.R
import com.murekkep.notebook.ink.Instrument
import com.murekkep.notebook.ink.InstrumentKind

// The pen bar's Araçlar (the iPad's toolsMenu in ToolPalette.swift): "Cetvel, gönye ve iletki", a
// submenu of the four instruments (each with its symbol, the one on the page checked) and, while one
// lies on the page, "Açıyı ayarla" with the ten round angles and "Kaldır"; then "Pergel", checked
// while it is in hand. The iPad's other tools there (Metin, Çıkartmalar, El yazısını yazıya çevir,
// Mühendislik, Sayfa açısı) are not in the Android edition yet. A submenu opens in the menu's place
// under a row that goes back to it, as iOS opens one; a pick closes the menu.

/** Which part of the menu is open. */
private enum class ToolsPage { MAIN, INSTRUMENTS, ANGLES }

/** The menu of the Araçlar button, opened under (or over) it. */
@Composable
internal fun ToolsMenu(state: EditorState, expanded: Boolean, onDismiss: () -> Unit) {
    val tick = rememberSelectionTick()
    ZenMenu(expanded = expanded, onDismissRequest = onDismiss) {
        var page by remember { mutableStateOf(ToolsPage.MAIN) }
        val onPage = state.instrumentKind
        when (page) {
            ToolsPage.MAIN -> {
                DropdownMenuItem(
                    text = { Text(stringResource(R.string.tools_instruments)) },
                    trailingIcon = { SubmenuMark(onPage?.symbol ?: InstrumentKind.RULER.symbol) },
                    onClick = { page = ToolsPage.INSTRUMENTS },
                )
                val compassInHand = state.tool is Tool.Compass
                DropdownMenuItem(
                    text = { Text(stringResource(R.string.tools_compass)) },
                    // compass.drawing on iPad: Material's drafting compass.
                    trailingIcon = { Icon(if (compassInHand) Icons.Filled.Check else Icons.Outlined.Architecture, contentDescription = null) },
                    onClick = {
                        // Picking the tool in hand goes back to the last pen.
                        state.tool = if (compassInHand) Tool.Brush(state.lastBrush) else Tool.Compass
                        tick()
                        onDismiss()
                    },
                )
            }
            ToolsPage.INSTRUMENTS -> {
                SubmenuHeader(stringResource(R.string.tools_instruments)) { page = ToolsPage.MAIN }
                for (kind in InstrumentKind.entries) {
                    DropdownMenuItem(
                        text = { Text(stringResource(kind.titleRes)) },
                        trailingIcon = { Icon(if (onPage == kind) Icons.Filled.Check else kind.symbol, contentDescription = null) },
                        onClick = {
                            // A new instrument on the page clicks; another kind takes the one there.
                            if (state.instrumentKind == null) tick()
                            state.showInstrument(kind)
                            onDismiss()
                        },
                    )
                }
                if (onPage != null) {
                    HorizontalDivider(color = Zen.colors.rule)
                    DropdownMenuItem(
                        text = { Text(stringResource(R.string.instrument_set_angle)) },
                        trailingIcon = { SubmenuMark(AngleSymbol) },
                        onClick = { page = ToolsPage.ANGLES },
                    )
                    val red = MaterialTheme.colorScheme.error
                    DropdownMenuItem(
                        text = { Text(stringResource(R.string.instrument_remove)) },
                        trailingIcon = { Icon(Icons.Outlined.Close, contentDescription = null) },
                        colors = MenuDefaults.itemColors(textColor = red, trailingIconColor = red),
                        onClick = {
                            state.showInstrument(null)
                            onDismiss()
                        },
                    )
                }
            }
            ToolsPage.ANGLES -> {
                SubmenuHeader(stringResource(R.string.instrument_set_angle)) { page = ToolsPage.INSTRUMENTS }
                for (degrees in Instrument.PRESET_DEGREES) {
                    DropdownMenuItem(
                        text = { Text("$degrees°") },
                        onClick = {
                            state.setInstrumentAngle(degrees.toDouble())
                            onDismiss()
                        },
                    )
                }
            }
        }
    }
}

/** An open submenu's first row: its title after a chevron back, a tap returning to the menu above. */
@Composable
private fun SubmenuHeader(title: String, onBack: () -> Unit) {
    val back = stringResource(R.string.back)
    DropdownMenuItem(
        text = { Text(title, fontWeight = FontWeight.SemiBold) },
        leadingIcon = {
            ChevronGlyph(Chevron.LEFT, LocalContentColor.current, size = 14.dp, modifier = Modifier.semantics { contentDescription = back })
        },
        onClick = onBack,
    )
    HorizontalDivider(color = Zen.colors.rule)
}

/** A row that opens a submenu: its symbol, then a chevron. */
@Composable
private fun SubmenuMark(symbol: ImageVector) {
    Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(symbol, contentDescription = null)
        ChevronGlyph(Chevron.RIGHT, LocalContentColor.current, size = 12.dp)
    }
}

/** The instrument's name in the menu (InstrumentKind.title on iPad). */
val InstrumentKind.titleRes: Int
    get() = when (this) {
        InstrumentKind.RULER -> R.string.instrument_ruler
        InstrumentKind.SET_SQUARE_45 -> R.string.instrument_set_square_45
        InstrumentKind.SET_SQUARE_3060 -> R.string.instrument_set_square_3060
        InstrumentKind.PROTRACTOR -> R.string.instrument_protractor
    }

/** The instrument's symbol (InstrumentKind.symbol on iPad, an SF Symbol) as its Material twin, or
 *  drawn where the Material set has none. */
val InstrumentKind.symbol: ImageVector
    get() = when (this) {
        InstrumentKind.RULER -> Icons.Outlined.Straighten // ruler
        InstrumentKind.SET_SQUARE_45 -> Icons.Outlined.ChangeHistory // triangle
        InstrumentKind.SET_SQUARE_3060 -> TriangleRightHalfSymbol // triangle.righthalf.filled
        InstrumentKind.PROTRACTOR -> AngleSymbol // angle
    }

/** The iPad's triangle.righthalf.filled: a triangle's outline with its right half filled. */
val TriangleRightHalfSymbol: ImageVector by lazy {
    ImageVector.Builder("TriangleRightHalf", 24.dp, 24.dp, 24f, 24f)
        .path(fill = SolidColor(Color.Black)) {
            moveTo(12f, 4.5f)
            lineTo(21f, 19.5f)
            lineTo(12f, 19.5f)
            close()
        }
        .path(stroke = SolidColor(Color.Black), strokeLineWidth = 1.7f, strokeLineJoin = StrokeJoin.Round) {
            moveTo(12f, 4.5f)
            lineTo(21f, 19.5f)
            lineTo(3f, 19.5f)
            close()
        }
        .build()
}

/** The iPad's angle: two arms from a corner at the lower left, an arc between them. */
val AngleSymbol: ImageVector by lazy {
    ImageVector.Builder("Angle", 24.dp, 24.dp, 24f, 24f)
        .path(stroke = SolidColor(Color.Black), strokeLineWidth = 1.7f, strokeLineCap = StrokeCap.Round, strokeLineJoin = StrokeJoin.Round) {
            moveTo(20.5f, 19f)
            lineTo(3.5f, 19f)
            lineTo(14.5f, 4.5f)
            // The arc, 8 from the corner, from the floor up to the slanted arm.
            moveTo(11.5f, 19f)
            arcTo(8f, 8f, 0f, false, false, 8.33f, 12.63f)
        }
        .build()
}
