@file:OptIn(androidx.compose.foundation.layout.ExperimentalLayoutApi::class)

package com.murekkep.notebook.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.MenuBook
import androidx.compose.material.icons.automirrored.outlined.ShowChart
import androidx.compose.material.icons.outlined.AccountBalance
import androidx.compose.material.icons.outlined.Bolt
import androidx.compose.material.icons.outlined.Book
import androidx.compose.material.icons.outlined.Eco
import androidx.compose.material.icons.outlined.Folder
import androidx.compose.material.icons.outlined.Laptop
import androidx.compose.material.icons.outlined.MedicalServices
import androidx.compose.material.icons.outlined.MonitorHeart
import androidx.compose.material.icons.outlined.MusicNote
import androidx.compose.material.icons.outlined.Palette
import androidx.compose.material.icons.outlined.Psychology
import androidx.compose.material.icons.outlined.Public
import androidx.compose.material.icons.outlined.Science
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.PathBuilder
import androidx.compose.ui.graphics.vector.path
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.res.stringArrayResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.murekkep.notebook.R
import com.murekkep.notebook.data.NoteSection
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.roundToInt
import kotlin.math.sin

// A course's look and its editor (Sections.swift: NoteSection.colors and symbols, SectionEditor).
// The editor is a sheet over the library on paper-3, as Ayarlar: "Yeni bölüm" or "Bölümü düzenle",
// "Vazgeç" and "Oluştur" (or "Kaydet", which wait for a name) at its bar's ends; the name, then the
// symbols in a grid of 44 dp tiles (the picked one filled with the colour, the others on a tenth of
// it), then the eight colours (the picked one in a ring). The iPad's note under them is about the
// assistant's "Tüm bölüm", which Android does not have, so it is left out. The symbols are the
// iPad's SF Symbols names, drawn with Material's outlined icons, or with glyphs of their own where
// Material has none (f(x), the square root, the atom, the two gears).

/** The courses' colours, in their order (NoteSection.colors on iPad); the same in the dark look. */
internal val CourseColors = listOf(
    Color(0.10f, 0.33f, 0.80f), Color(0.45f, 0.30f, 0.96f), Color(0.07f, 0.60f, 0.70f), Color(0.16f, 0.62f, 0.32f),
    Color(0.92f, 0.55f, 0.10f), Color(0.85f, 0.22f, 0.30f), Color(0.88f, 0.36f, 0.62f), Color(0.40f, 0.42f, 0.48f),
)

internal val NoteSection.color: Color get() = CourseColors[colorSlot]

/** A course's symbol: the SF Symbol [symbol] names, as near as Android draws it; a folder for one
 *  this build does not know (a newer iPad's). */
internal fun courseGlyph(symbol: String): ImageVector = when (symbol) {
    "function" -> FunctionGlyph
    "x.squareroot" -> SquareRootGlyph
    "atom" -> AtomGlyph
    "flask" -> Icons.Outlined.Science
    "cross.case" -> Icons.Outlined.MedicalServices
    "heart.text.square" -> Icons.Outlined.MonitorHeart
    "brain.head.profile" -> Icons.Outlined.Psychology
    "gearshape.2" -> GearsGlyph
    "bolt" -> Icons.Outlined.Bolt
    "building.columns" -> Icons.Outlined.AccountBalance
    "globe.europe.africa" -> Icons.Outlined.Public
    "chart.line.uptrend.xyaxis" -> Icons.AutoMirrored.Outlined.ShowChart
    "book.closed" -> Icons.Outlined.Book
    "text.book.closed" -> Icons.AutoMirrored.Outlined.MenuBook
    "music.note" -> Icons.Outlined.MusicNote
    "paintpalette" -> Icons.Outlined.Palette
    "laptopcomputer" -> Icons.Outlined.Laptop
    "leaf" -> Icons.Outlined.Eco
    else -> Icons.Outlined.Folder
}

/** A glyph of lines 1.8 wide on the icons' 24 grid, as the app's own glyphs are drawn. */
private fun lineGlyph(name: String, draw: PathBuilder.() -> Unit): ImageVector =
    ImageVector.Builder(name, 24.dp, 24.dp, 24f, 24f).path(
        stroke = SolidColor(Color.Black),
        strokeLineWidth = 1.8f,
        strokeLineCap = StrokeCap.Round,
        strokeLineJoin = StrokeJoin.Round,
        pathBuilder = draw,
    ).build()

/** The iPad's function: an italic f before (x). */
private val FunctionGlyph: ImageVector by lazy {
    lineGlyph("Function") {
        moveTo(9.8f, 4.9f)
        curveTo(8.4f, 4.1f, 6.8f, 4.8f, 6.5f, 6.8f)
        lineTo(4.9f, 17.2f)
        curveTo(4.6f, 19.2f, 3.1f, 19.9f, 1.8f, 19.2f)
        moveTo(3.8f, 9.6f)
        lineTo(8.8f, 9.6f)
        moveTo(13.2f, 6.2f)
        curveTo(10.9f, 9.6f, 10.9f, 14.4f, 13.2f, 17.8f)
        moveTo(20.6f, 6.2f)
        curveTo(22.9f, 9.6f, 22.9f, 14.4f, 20.6f, 17.8f)
        moveTo(14.6f, 9.2f)
        lineTo(19.2f, 14.8f)
        moveTo(19.2f, 9.2f)
        lineTo(14.6f, 14.8f)
    }
}

/** The iPad's x.squareroot: the root's sign over an x. */
private val SquareRootGlyph: ImageVector by lazy {
    lineGlyph("SquareRoot") {
        moveTo(2.5f, 13.6f)
        lineTo(5f, 12.3f)
        lineTo(8.2f, 19.5f)
        lineTo(11.6f, 4.5f)
        lineTo(21.5f, 4.5f)
        moveTo(13.8f, 9.2f)
        lineTo(19.4f, 16.4f)
        moveTo(19.4f, 9.2f)
        lineTo(13.8f, 16.4f)
    }
}

/** The iPad's atom: three orbits round a nucleus. */
private val AtomGlyph: ImageVector by lazy {
    ImageVector.Builder("Atom", 24.dp, 24.dp, 24f, 24f).path(
        stroke = SolidColor(Color.Black),
        strokeLineWidth = 1.6f,
        strokeLineCap = StrokeCap.Round,
    ) {
        for (turn in listOf(0f, 60f, 120f)) {
            val a = turn * PI.toFloat() / 180f
            val dx = 9.6f * cos(a)
            val dy = 9.6f * sin(a)
            moveTo(12f + dx, 12f + dy)
            arcTo(9.6f, 3.7f, turn, false, true, 12f - dx, 12f - dy)
            arcTo(9.6f, 3.7f, turn, false, true, 12f + dx, 12f + dy)
            close()
        }
    }.path(fill = SolidColor(Color.Black)) {
        moveTo(10.3f, 12f)
        arcTo(1.7f, 1.7f, 0f, false, true, 13.7f, 12f)
        arcTo(1.7f, 1.7f, 0f, false, true, 10.3f, 12f)
        close()
    }.build()
}

/** The iPad's gearshape.2: a large gear and a small one meshing below it. */
private val GearsGlyph: ImageVector by lazy {
    lineGlyph("Gears") {
        gear(9f, 9.4f, outer = 6.6f, inner = 4.9f, hole = 2.1f, teeth = 8)
        gear(17.6f, 17.6f, outer = 4.6f, inner = 3.3f, hole = 1.3f, teeth = 6)
    }
}

/** A gear's outline round ([x], [y]): [teeth] square-topped teeth from [inner] to [outer], and its hole. */
private fun PathBuilder.gear(x: Float, y: Float, outer: Float, inner: Float, hole: Float, teeth: Int) {
    val quarter = PI.toFloat() / (2 * teeth)
    fun at(r: Float, a: Float) = Pair(x + r * cos(a), y + r * sin(a))
    for (i in 0 until teeth) {
        val a = i * 4 * quarter - PI.toFloat() / 2
        val points = listOf(at(inner, a - quarter), at(outer, a - 0.6f * quarter), at(outer, a + 0.6f * quarter), at(inner, a + quarter))
        for ((j, p) in points.withIndex()) if (i == 0 && j == 0) moveTo(p.first, p.second) else lineTo(p.first, p.second)
    }
    close()
    moveTo(x - hole, y)
    arcTo(hole, hole, 0f, false, true, x + hole, y)
    arcTo(hole, hole, 0f, false, true, x - hole, y)
    close()
}

/**
 * Makes a course ([section] null) or changes [section]; a new one starts on the first symbol and
 * colour [newColorIndex]. [onSave] gets the name (trimmed, never blank), the symbol and the colour;
 * the caller closes the sheet.
 */
@Composable
fun SectionEditor(section: NoteSection?, newColorIndex: Int, onDismiss: () -> Unit, onSave: (name: String, symbol: String, colorIndex: Int) -> Unit) {
    val z = Zen.colors
    var name by rememberSaveable { mutableStateOf(section?.name ?: "") }
    var symbol by rememberSaveable { mutableStateOf(section?.symbol ?: NoteSection.SYMBOLS[0]) }
    var colorIndex by rememberSaveable { mutableIntStateOf(section?.colorSlot ?: Math.floorMod(newColorIndex, NoteSection.COLOR_COUNT)) }
    val ready = name.isNotBlank()
    ZenSheet(
        title = stringResource(if (section == null) R.string.section_new_title else R.string.section_edit_title),
        ground = z.paper3,
        onDismiss = onDismiss,
        leading = { SheetButton(stringResource(R.string.cancel), onClick = onDismiss) },
        trailing = {
            ConfirmButton(stringResource(if (section == null) R.string.section_create else R.string.save), enabled = ready) {
                onSave(name.trim(), symbol, colorIndex)
            }
        },
    ) {
        Column(
            Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .windowInsetsPadding(WindowInsets.safeDrawing.only(WindowInsetsSides.Horizontal + WindowInsetsSides.Bottom))
                .padding(horizontal = 20.dp, vertical = 24.dp),
        ) {
            FormGroup(header = null) { NameField(name) { name = it } }
            Spacer(Modifier.height(FormGroupSpacing))
            FormGroup(header = stringResource(R.string.section_symbol)) { SymbolGrid(symbol, CourseColors[colorIndex]) { symbol = it } }
            Spacer(Modifier.height(FormGroupSpacing))
            FormGroup(header = stringResource(R.string.color)) { ColorChoices(colorIndex) { colorIndex = it } }
        }
    }
}

/** The room between one group and the next one's header, as in Ayarlar. */
private val FormGroupSpacing = 32.dp

/** A group of the form: its header in muted text, its card of paper in a hairline (Ayarlar's groups). */
@Composable
private fun FormGroup(header: String?, content: @Composable () -> Unit) {
    val z = Zen.colors
    val shape = RoundedCornerShape(12.dp)
    if (header != null) {
        Text(header, style = MaterialTheme.typography.bodySmall, color = z.muted, modifier = Modifier.padding(start = 16.dp, end = 16.dp, bottom = 8.dp))
    }
    Box(Modifier.fillMaxWidth().clip(shape).background(z.paper).border(1.dp, z.rule, shape)) {
        content()
    }
}

/** The name in the iPad's title3 (20 sp), "Bölüm adı (ör. Calculus, Anatomi)" while it is empty, cut
 *  with an ellipsis where a phone's field ends, as the iPad's placeholder; the keyboard's done key
 *  only puts the keyboard away, as Return does in the iPad's form. */
@Composable
private fun NameField(name: String, onName: (String) -> Unit) {
    val z = Zen.colors
    val hint = stringResource(R.string.section_name_hint)
    val focus = LocalFocusManager.current
    val style = MaterialTheme.typography.bodyLarge.copy(fontSize = 20.sp, lineHeight = 26.sp)
    BasicTextField(
        value = name,
        onValueChange = onName,
        singleLine = true,
        textStyle = style.copy(color = z.ink),
        cursorBrush = SolidColor(z.accent),
        keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences, imeAction = ImeAction.Done),
        keyboardActions = KeyboardActions(onDone = { focus.clearFocus() }),
        modifier = Modifier.fillMaxWidth().semantics { contentDescription = hint },
        decorationBox = { inner ->
            Box(Modifier.fillMaxWidth().heightIn(min = 52.dp).padding(horizontal = 16.dp, vertical = 12.dp), contentAlignment = Alignment.CenterStart) {
                if (name.isEmpty()) Text(hint, style = style, color = z.muted, maxLines = 1, softWrap = false, overflow = TextOverflow.Ellipsis)
                inner()
            }
        },
    )
}

/** The symbols as the iPad's adaptive grid: 44 dp tiles, columns at least 44 wide and 10 apart,
 *  each tile in the middle of its column; rows 10 apart. */
@Composable
private fun SymbolGrid(picked: String, color: Color, onPick: (String) -> Unit) {
    val names = stringArrayResource(R.array.section_symbol_names)
    Layout(
        content = {
            NoteSection.SYMBOLS.forEachIndexed { i, symbol ->
                SymbolTile(courseGlyph(symbol), names.getOrElse(i) { symbol }, symbol == picked, color) { onPick(symbol) }
            }
        },
        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 14.dp).selectableGroup(),
    ) { measurables, constraints ->
        val tile = Zen.target.roundToPx()
        val gap = 10.dp.roundToPx()
        val width = constraints.maxWidth
        val (columns, cell) = LibraryRules.adaptiveColumns(width.toFloat(), tile.toFloat(), Float.MAX_VALUE, gap.toFloat())
        val placeables = measurables.map { it.measure(Constraints.fixed(tile, tile)) }
        val rows = (placeables.size + columns - 1) / columns
        layout(width, max(0, rows * tile + (rows - 1) * gap)) {
            placeables.forEachIndexed { i, p ->
                val x = (i % columns) * (cell + gap) + (cell - tile) / 2f
                p.placeRelative(x.roundToInt(), (i / columns) * (tile + gap))
            }
        }
    }
}

/** A symbol: white on its colour when picked, in its colour on a tenth of it otherwise. */
@Composable
private fun SymbolTile(glyph: ImageVector, name: String, picked: Boolean, color: Color, onClick: () -> Unit) {
    val shape = RoundedCornerShape(Zen.control)
    Box(
        Modifier
            .size(Zen.target)
            .clip(shape)
            .background(if (picked) color else color.copy(alpha = 0.10f))
            .selectable(selected = picked, role = Role.RadioButton, onClick = onClick)
            .semantics { contentDescription = name },
        contentAlignment = Alignment.Center,
    ) {
        Icon(glyph, contentDescription = null, tint = if (picked) Color.White else color, modifier = Modifier.size(22.dp))
    }
}

/** The eight colours, 30 dp dots in 44 dp targets; the picked one in a ring of ink. */
@Composable
private fun ColorChoices(picked: Int, onPick: (Int) -> Unit) {
    val names = stringArrayResource(R.array.section_color_names)
    val ring = Zen.colors.ink.copy(alpha = 0.8f)
    FlowRow(Modifier.fillMaxWidth().padding(horizontal = 10.dp, vertical = 6.dp).selectableGroup()) {
        CourseColors.forEachIndexed { i, color ->
            Box(
                Modifier
                    .size(Zen.target)
                    .clip(CircleShape)
                    .selectable(selected = i == picked, role = Role.RadioButton) { onPick(i) }
                    .semantics { contentDescription = names.getOrElse(i) { "" } },
                contentAlignment = Alignment.Center,
            ) {
                if (i == picked) Box(Modifier.size(40.dp).border(2.dp, ring, CircleShape))
                Box(Modifier.size(30.dp).background(color, CircleShape))
            }
        }
    }
}

/** The sheet's confirming button ("Oluştur", "Kaydet"): the accent in semibold, grey and still
 *  until there is a name, as the iPad's disabled confirmation action. */
@Composable
private fun ConfirmButton(label: String, enabled: Boolean, onClick: () -> Unit) {
    val z = Zen.colors
    Box(
        Modifier
            .height(Zen.target)
            .clip(RoundedCornerShape(Zen.control))
            .clickable(enabled = enabled, role = Role.Button, onClick = onClick)
            .padding(horizontal = 12.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            label,
            style = MaterialTheme.typography.bodyLarge,
            fontWeight = FontWeight.SemiBold,
            color = if (enabled) z.accent else z.muted.copy(alpha = 0.6f),
            maxLines = 1,
        )
    }
}
