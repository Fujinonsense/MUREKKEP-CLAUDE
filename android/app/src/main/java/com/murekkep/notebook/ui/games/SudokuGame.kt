package com.murekkep.notebook.ui.games

import android.content.SharedPreferences
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.AutoAwesome
import androidx.compose.material.icons.automirrored.outlined.Backspace
import androidx.compose.material.icons.outlined.EditNote
import androidx.compose.material.icons.outlined.LooksOne
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.murekkep.notebook.R
import com.murekkep.notebook.games.GameDifficulty
import com.murekkep.notebook.games.GameProgress
import com.murekkep.notebook.games.Sudoku
import com.murekkep.notebook.games.SudokuSave
import com.murekkep.notebook.ui.Zen
import com.murekkep.notebook.ui.ZenMenu
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

// Sudoku (the iPad's SudokuGame.swift): tap a cell, then a digit on the pad (or a pencil mark with
// Notlar on); repeated digits show softly in red; a solved grid stops the clock, and the best time of
// each difficulty is kept. The puzzle on screen is kept in the preferences between visits (the
// panel closes, the app goes away).

/** The puzzle on screen and what is picked on it. */
internal class SudokuModel(private val prefs: SharedPreferences) {
    var save by mutableStateOf<SudokuSave?>(null)
        private set
    var selected by mutableStateOf<Int?>(null)
    var notesMode by mutableStateOf(false)
    var generating by mutableStateOf(false)
        private set
    var solved by mutableStateOf(false)
        private set

    init {
        SudokuSave.decode(prefs.getString(KEY, null))?.let {
            save = it
            solved = Sudoku.isSolved(it.entries)
        }
    }

    val conflicts: Set<Int> get() = save?.let { Sudoku.conflicts(it.entries) } ?: emptySet()
    val elapsed: Int get() = save?.elapsed ?: 0
    /** A puzzle begun and not yet solved. */
    val inProgress: Boolean get() = save?.let { !solved && it.entries != it.givens } ?: false

    /** A fresh puzzle, made off the main thread (a hard one takes a moment). */
    suspend fun newPuzzle(difficulty: GameDifficulty) {
        if (generating) return
        generating = true
        solved = false
        selected = null
        try {
            val seed = System.currentTimeMillis().toULong()
            val puzzle = withContext(Dispatchers.Default) { Sudoku.generate(difficulty, seed) }
            save = SudokuSave(difficulty, puzzle.givens, puzzle.solution, puzzle.givens, emptyMap(), 0)
            persist()
        } finally {
            generating = false
        }
    }

    /** A digit for the selected cell: written, or as a pencil mark in notes mode; the same digit again clears it. */
    fun enter(digit: Int) {
        val kept = save ?: return
        val i = selected ?: return
        if (kept.givens[i] != 0 || solved) return
        val next = if (notesMode) {
            val marks = kept.notes[i].orEmpty().toMutableSet().apply { if (!add(digit)) remove(digit) }
            kept.copy(
                notes = if (marks.isEmpty()) kept.notes - i else kept.notes + (i to marks.sorted()),
                entries = kept.entries.toMutableList().apply { this[i] = 0 },
            )
        } else {
            kept.copy(entries = kept.entries.toMutableList().apply { this[i] = if (this[i] == digit) 0 else digit }, notes = kept.notes - i)
        }
        save = next
        if (Sudoku.isSolved(next.entries)) solved = true
        persist()
    }

    fun erase() {
        val kept = save ?: return
        val i = selected ?: return
        if (kept.givens[i] != 0 || solved) return
        save = kept.copy(entries = kept.entries.toMutableList().apply { this[i] = 0 }, notes = kept.notes - i)
        persist()
    }

    /** One second more on the clock. */
    fun tick() {
        val kept = save ?: return
        if (solved || generating) return
        save = kept.copy(elapsed = kept.elapsed + 1)
        if ((kept.elapsed + 1) % 5 == 0) persist()
    }

    fun abandon() {
        save = null
        solved = false
        selected = null
        prefs.edit().remove(KEY).apply()
    }

    fun persist() {
        save?.let { prefs.edit().putString(KEY, it.encoded()).apply() }
    }

    companion object {
        val KEY = GameProgress.Keys.saved("sudoku")
    }
}

@Composable
internal fun SudokuGame(store: GameProgressStore) {
    val model = remember { SudokuModel(store.prefs) }
    var newBest by remember { mutableStateOf(false) }
    val view = LocalView.current
    // A solved grid is timed once: a record when it is the shortest yet at its difficulty.
    LaunchedEffect(model) {
        snapshotFlow { model.solved }.drop(1).collect { done ->
            val kept = model.save
            if (done && kept != null) {
                newBest = store.record(MiniGame.SUDOKU, kept.elapsed, kept.difficulty, lowerIsBetter = true)
                view.gameSuccess()
            }
        }
    }
    // The seconds since the last save go into the preferences when the panel closes.
    DisposableEffect(model) { onDispose { model.persist() } }
    val kept = model.save
    if (kept == null) {
        SudokuStart(store, model) { newBest = false }
    } else {
        SudokuPuzzle(model, kept, newBest)
    }
}

/** Before a puzzle: what Sudoku is, the difficulty, the best time, "Yeni bulmaca". */
@Composable
private fun SudokuStart(store: GameProgressStore, model: SudokuModel, onStart: () -> Unit) {
    val z = Zen.colors
    val scope = rememberCoroutineScope()
    val kept = store[MiniGame.SUDOKU]
    Column(Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp, Alignment.CenterVertically)) {
        Icon(Icons.Outlined.LooksOne, contentDescription = null, tint = z.accent, modifier = Modifier.size(40.dp))
        Text(stringResource(R.string.games_sudoku_hint), style = GameText.footnote, color = z.muted)
        DifficultyPicker(kept.difficulty) { store.setDifficulty(it, MiniGame.SUDOKU) }
        kept.best[kept.difficulty]?.let {
            Text(stringResource(R.string.games_best_time, clock(it)), style = GameText.caption, color = z.muted)
        }
        GameButton(stringResource(R.string.games_new_puzzle), prominent = true, icon = Icons.Outlined.AutoAwesome, busy = model.generating) {
            onStart()
            scope.launch { model.newPuzzle(kept.difficulty) }
        }
    }
}

/** A puzzle: its difficulty, the clock and "Yeni"; the board; the pad. */
@Composable
private fun SudokuPuzzle(model: SudokuModel, kept: SudokuSave, newBest: Boolean) {
    val z = Zen.colors
    var confirmNew by remember { mutableStateOf(false) }
    // The clock: a second at a time while the app is in front and the puzzle on screen; the loop ends
    // with the puzzle, and the app's lifecycle itself stops it and starts it again when it comes back.
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    LaunchedEffect(lifecycle, model) { tickWhileInFront(lifecycle) { model.tick() } }
    Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(stringResource(kept.difficulty.titleRes), style = GameText.subheadline.copy(fontWeight = FontWeight.SemiBold), color = z.ink)
            Spacer(Modifier.weight(1f))
            val time = clock(model.elapsed)
            val spoken = stringResource(R.string.games_time, time)
            Text(time, style = GameText.subheadline.numeric(), color = z.muted, modifier = Modifier.semantics { contentDescription = spoken })
            Spacer(Modifier.weight(1f))
            Box {
                GameButton(stringResource(R.string.games_new), prominent = false, icon = Icons.Outlined.Add, height = 32.dp) {
                    if (model.inProgress) confirmNew = true else model.abandon()
                }
                // The iPad's confirmation: a small menu under the button, not a sheet.
                ZenMenu(expanded = confirmNew, onDismissRequest = { confirmNew = false }, alignEnd = true) {
                    Text(
                        stringResource(R.string.games_leave_puzzle),
                        style = GameText.caption,
                        color = z.muted,
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                    )
                    DropdownMenuItem(
                        text = { Text(stringResource(R.string.games_new_puzzle), color = MaterialTheme.colorScheme.error) },
                        onClick = {
                            confirmNew = false
                            model.abandon()
                        },
                    )
                }
            }
        }
        Box(Modifier.weight(1f).fillMaxWidth()) {
            BoxWithConstraints(Modifier.fillMaxSize()) {
                val side = minOf(maxWidth, maxHeight)
                SudokuBoard(model, kept, Modifier.size(side).align(Alignment.Center))
            }
            ResultCardOver(model.solved, Modifier.align(Alignment.Center)) {
                ResultCard(
                    title = stringResource(R.string.games_solved),
                    lines = listOf(stringResource(R.string.games_time, clock(kept.elapsed))),
                    highlight = if (newBest) stringResource(R.string.games_new_best) else null,
                    actions = listOf(ResultAction(stringResource(R.string.games_new_puzzle), prominent = true) { model.abandon() }),
                )
            }
        }
        SudokuPad(model, kept)
    }
}

/**
 * The grid: the selected cell, its digit's twins and its row, column and box washed in the accent,
 * clashes in red; the given digits in ink, the player's in the accent, pencil marks small and grey.
 */
@Composable
private fun SudokuBoard(model: SudokuModel, kept: SudokuSave, modifier: Modifier) {
    val z = Zen.colors
    val clash = MaterialTheme.colorScheme.error
    val label = stringResource(R.string.games_sudoku_board)
    val measurer = rememberTextMeasurer(cacheSize = 32)
    Canvas(
        modifier
            .clip(RoundedCornerShape(8.dp))
            .background(z.paper)
            .onTouchEnd { start, size ->
                if (size.width > 0 && !model.solved) {
                    val col = (start.x / (size.width / 9f)).toInt()
                    val row = (start.y / (size.width / 9f)).toInt()
                    if (col in 0..8 && row in 0..8 && start.x >= 0 && start.y >= 0) model.selected = row * 9 + col
                }
            }
            .semantics { contentDescription = label },
    ) {
        val cell = size.width / 9
        val conflicts = model.conflicts
        val selected = model.selected
        val selectedDigit = selected?.let { kept.entries[it] } ?: 0
        for (i in 0 until Sudoku.CELLS) {
            val row = Sudoku.row(i)
            val col = Sudoku.col(i)
            val topLeft = Offset(col * cell, row * cell)
            var tint: Color? = null
            if (selected != null) {
                tint = when {
                    i == selected -> z.accent.copy(alpha = 0.22f)
                    selectedDigit != 0 && kept.entries[i] == selectedDigit -> z.accent.copy(alpha = 0.14f)
                    Sudoku.row(selected) == row || Sudoku.col(selected) == col || Sudoku.box(selected) == Sudoku.box(i) -> z.accent.copy(alpha = 0.06f)
                    else -> null
                }
            }
            if (i in conflicts) tint = clash.copy(alpha = 0.16f)
            if (tint != null) drawRect(tint, topLeft, Size(cell, cell))
            val digit = kept.entries[i]
            if (digit != 0) {
                val given = kept.givens[i] != 0
                val text = measurer.measure(
                    "$digit",
                    TextStyle(fontSize = (cell * 0.55f).toSp(), fontWeight = if (given) FontWeight.SemiBold else FontWeight.Normal, color = if (given) z.ink else z.accent),
                )
                drawText(text, topLeft = topLeft + Offset((cell - text.size.width) / 2, (cell - text.size.height) / 2))
            } else {
                for (mark in kept.notes[i].orEmpty()) {
                    val text = measurer.measure("$mark", TextStyle(fontSize = (cell * 0.26f).toSp(), color = z.muted))
                    val x = topLeft.x + cell * (((mark - 1) % 3) + 0.5f) / 3
                    val y = topLeft.y + cell * (((mark - 1) / 3) + 0.5f) / 3
                    drawText(text, topLeft = Offset(x - text.size.width / 2f, y - text.size.height / 2f))
                }
            }
        }
        val thin = z.accent.copy(alpha = 0.25f)
        val thick = z.accent.copy(alpha = 0.75f)
        for (k in 0..9) {
            val at = k * cell
            val color = if (k % 3 == 0) thick else thin
            val width = (if (k % 3 == 0) 1.6f else 0.6f).dp.toPx()
            drawLine(color, Offset(at, 0f), Offset(at, size.height), width)
            drawLine(color, Offset(0f, at), Offset(size.width, at), width)
        }
    }
}

/** The digits 1 to 9 (grey once all nine stand), Notlar, Sil and a line of help. */
@Composable
private fun SudokuPad(model: SudokuModel, kept: SudokuSave) {
    val z = Zen.colors
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            for (digit in 1..9) {
                val placed = kept.entries.count { it == digit }
                val label = stringResource(R.string.games_digit, digit)
                Box(
                    Modifier
                        .weight(1f)
                        .height(32.dp)
                        .clip(RoundedCornerShape(9.dp))
                        .background(z.accent.copy(alpha = if (placed >= 9) 0.04f else 0.1f))
                        .clickable(role = Role.Button) { model.enter(digit) }
                        .clearAndSetSemantics {
                            contentDescription = label
                            role = Role.Button
                            onClick { model.enter(digit); true }
                        },
                    contentAlignment = Alignment.Center,
                ) {
                    Text("$digit", style = TextStyle(fontSize = 17.sp, fontWeight = FontWeight.SemiBold).numeric(), color = if (placed >= 9) z.muted else z.accent)
                }
            }
        }
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            PadChip(stringResource(R.string.games_notes), Icons.Outlined.EditNote, on = model.notesMode, onToggle = { model.notesMode = it })
            PadChip(stringResource(R.string.games_erase), Icons.AutoMirrored.Outlined.Backspace, on = null) { model.erase() }
            FitText(
                stringResource(if (model.notesMode) R.string.games_sudoku_notes_mode else R.string.games_sudoku_pick),
                GameText.caption2,
                z.muted,
                Modifier.weight(1f),
                align = TextAlign.End,
            )
        }
    }
}

/**
 * A small button of the pad, 32 dp tall: a toggle when [on] is given (in the accent while on), else
 * a plain button.
 */
@Composable
private fun PadChip(label: String, icon: ImageVector, on: Boolean?, onToggle: (Boolean) -> Unit) {
    val z = Zen.colors
    val shape = RoundedCornerShape(Zen.control)
    val lit = on == true
    val ink = if (lit) Color.White else z.ink
    val touch = if (on != null) {
        Modifier.toggleable(value = on, role = Role.Switch, onValueChange = onToggle)
    } else {
        Modifier.clickable(role = Role.Button) { onToggle(true) }
    }
    Row(
        Modifier
            .height(32.dp)
            .clip(shape)
            .background(if (lit) z.accent else z.paper2)
            .border(1.dp, if (lit) z.accent else z.rule, shape)
            .then(touch)
            .padding(horizontal = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Icon(icon, contentDescription = null, tint = ink, modifier = Modifier.size(14.dp))
        Text(label, style = GameText.caption.copy(fontWeight = FontWeight.SemiBold), color = ink, maxLines = 1)
    }
}
