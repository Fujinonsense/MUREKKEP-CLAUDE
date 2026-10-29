package com.murekkep.notebook.ui.games

import android.view.View
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.AnimationVector1D
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.LinearOutSlowInEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.murekkep.notebook.R
import com.murekkep.notebook.games.GameDifficulty
import com.murekkep.notebook.games.GameRandom
import com.murekkep.notebook.games.TicTacToe
import com.murekkep.notebook.games.TicTacToe.Mark
import com.murekkep.notebook.ui.Zen
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

// XOX against the device (the iPad's XOXGame.swift): the player is X and taps or draws in a cell;
// the device answers with O after a moment's thought: Kolay mostly at random, Orta with a plan, Zor
// without a single mistake. The marks draw themselves on; three in a row ends the game with a line
// through them, and "Tekrar" starts again with the other side first. Wins are counted per difficulty.

private val Human = Mark.X
private val Device = Mark.O

/** A game on the board: the marks, their drawing on, the device's turns. */
private class XoxPlay(private val store: GameProgressStore, private val scope: CoroutineScope, private val view: View) {
    var game by mutableStateOf(TicTacToe())
        private set
    /** Each placed mark's drawing progress, 0 to 1. */
    val drawn = mutableStateMapOf<Int, Animatable<Float, AnimationVector1D>>()
    var line by mutableStateOf(Animatable(0f))
        private set
    /** Counts the device's turns; each one runs the reply afresh. */
    var pendingReply by mutableIntStateOf(0)
        private set
    private val rng = GameRandom.clock()
    private var humanFirst = true
    private var counted = false

    val difficulty: GameDifficulty get() = store[MiniGame.XOX].difficulty
    val wins: Int get() = store[MiniGame.XOX].best[difficulty] ?: 0

    /** The player's turn: the cell the touch began in takes an X, then the device thinks. */
    fun tap(point: Offset, side: Float) {
        if (game.isOver || game.turn != Human || side <= 0f) return
        val col = (point.x / (side / 3)).toInt()
        val row = (point.y / (side / 3)).toInt()
        if (col !in 0..2 || row !in 0..2 || point.x < 0 || point.y < 0) return
        place(row * 3 + col)
        if (!game.isOver) pendingReply += 1
    }

    /** The device's turn, after a moment; cancelled with the game if the panel closes first. */
    suspend fun reply() {
        if (pendingReply == 0 || game.isOver || game.turn != Device) return
        delay(550)
        if (game.isOver || game.turn != Device) return
        place(game.move(Device, difficulty, rng) ?: return)
    }

    private fun place(cell: Int) {
        val next = game.copy()
        if (!next.play(cell)) return
        game = next
        view.gameTick()
        // The mark draws itself on, and the winning line after it.
        val progress = Animatable(0f)
        drawn[cell] = progress
        scope.launch { progress.animateTo(1f, tween(350, easing = LinearOutSlowInEasing)) }
        if (next.isOver) {
            val through = line
            scope.launch {
                delay(300)
                through.animateTo(1f, tween(400, easing = FastOutSlowInEasing))
            }
            if (!counted) {
                counted = true
                if ((next.outcome as? TicTacToe.Outcome.Won)?.mark == Human) {
                    store.record(MiniGame.XOX, wins + 1, difficulty)
                    view.gameSuccess()
                }
            }
        }
    }

    /** A new game; the other side starts, unless the difficulty changed mid-game. */
    fun restart(keepTurn: Boolean = false) {
        if (!keepTurn) humanFirst = !humanFirst
        game = TicTacToe(if (humanFirst) Human else Device)
        drawn.clear()
        line = Animatable(0f)
        counted = false
        if (!humanFirst) pendingReply += 1
    }
}

@Composable
internal fun XoxGame(store: GameProgressStore) {
    val z = Zen.colors
    val scope = rememberCoroutineScope()
    val view = LocalView.current
    val play = remember { XoxPlay(store, scope, view) }
    val game = play.game
    val difficulty = play.difficulty
    val status = when (val outcome = game.outcome) {
        is TicTacToe.Outcome.Won -> stringResource(if (outcome.mark == Human) R.string.games_you_won else R.string.games_device_won)
        TicTacToe.Outcome.Draw -> stringResource(R.string.games_draw)
        null -> stringResource(if (game.turn == Human) R.string.games_xox_your_turn else R.string.games_device_thinking)
    }
    LaunchedEffect(play.pendingReply) { play.reply() }

    Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        DifficultyPicker(difficulty) {
            if (it != difficulty) {
                store.setDifficulty(it, MiniGame.XOX)
                play.restart(keepTurn = true)
            }
        }
        Row(Modifier.fillMaxWidth().height(22.dp), verticalAlignment = Alignment.CenterVertically) {
            FitText(
                status,
                GameText.subheadline.copy(fontWeight = FontWeight.SemiBold),
                if (game.isOver) z.accent else z.muted,
                Modifier.weight(1f),
            )
            Text(stringResource(R.string.games_wins, play.wins), style = GameText.caption.numeric(), color = z.muted)
        }
        BoxWithConstraints(Modifier.weight(1f).fillMaxWidth()) {
            val side = minOf(maxWidth, maxHeight)
            XoxBoard(play, status, Modifier.size(side).align(Alignment.Center))
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            val hint = when (difficulty) {
                GameDifficulty.HARD -> R.string.games_xox_hard
                GameDifficulty.EASY -> R.string.games_xox_easy
                GameDifficulty.MEDIUM -> R.string.games_xox_medium
            }
            FitText(stringResource(hint), GameText.caption2, z.muted, Modifier.weight(1f), minScale = 0.7f)
            AgainButton(visible = game.isOver) { play.restart() }
        }
    }
}

/** "Tekrar" once a round is over; it keeps its place, unseen and untouchable, while one is played. */
@Composable
internal fun AgainButton(visible: Boolean, onClick: () -> Unit) {
    val hidden = if (visible) Modifier else Modifier.clearAndSetSemantics {}
    Box(Modifier.alpha(if (visible) 1f else 0f).then(hidden)) {
        GameButton(stringResource(R.string.games_again), prominent = true, icon = Icons.Outlined.Refresh, enabled = visible, onClick = onClick)
    }
}

/** The grid, the marks drawing themselves on, the line through three in a row. */
@Composable
private fun XoxBoard(play: XoxPlay, status: String, modifier: Modifier) {
    val z = Zen.colors
    val label = stringResource(R.string.games_xox_board)
    Canvas(
        modifier
            .gameBoard()
            .onTouchEnd { start, size -> play.tap(start, size.width.toFloat()) }
            .semantics {
                contentDescription = label
                stateDescription = status
            },
    ) {
        val cell = size.width / 3
        val inset = 8.dp.toPx()
        for (i in 1..2) {
            val at = size.width * i / 3
            val grid = z.accent.copy(alpha = 0.35f)
            drawLine(grid, Offset(at, inset), Offset(at, size.height - inset), 2.dp.toPx(), StrokeCap.Round)
            drawLine(grid, Offset(inset, at), Offset(size.width - inset, at), 2.dp.toPx(), StrokeCap.Round)
        }
        val game = play.game
        for (i in 0 until 9) {
            val mark = game.cells[i] ?: continue
            val progress = play.drawn[i]?.value ?: 1f
            val origin = Offset((i % 3) * cell, (i / 3) * cell)
            if (mark == Mark.X) drawX(origin, cell, progress, z.accent) else drawO(origin, cell, progress, z.ink.copy(alpha = 0.7f))
        }
        val won = game.outcome as? TicTacToe.Outcome.Won
        if (won != null) {
            val from = centre(won.line.first(), cell)
            val to = centre(won.line.last(), cell)
            val t = play.line.value
            drawLine(z.accent.copy(alpha = 0.85f), from, from + (to - from) * t, 5.dp.toPx(), StrokeCap.Round)
        }
    }
}

/** A mark's inset in its cell, as a share of the cell. */
private const val MarkInset = 0.27f

private fun centre(cell: Int, side: Float) = Offset((cell % 3 + 0.5f) * side, (cell / 3 + 0.5f) * side)

/** An X: the first stroke in the first half of [progress], the second in the second. */
private fun DrawScope.drawX(origin: Offset, cell: Float, progress: Float, color: Color) {
    val width = 4.dp.toPx()
    val a = origin + Offset(cell * MarkInset, cell * MarkInset)
    val b = origin + Offset(cell * (1 - MarkInset), cell * (1 - MarkInset))
    val c = origin + Offset(cell * (1 - MarkInset), cell * MarkInset)
    val d = origin + Offset(cell * MarkInset, cell * (1 - MarkInset))
    val first = (progress * 2).coerceIn(0f, 1f)
    val second = (progress * 2 - 1).coerceIn(0f, 1f)
    if (first > 0f) drawLine(color, a, a + (b - a) * first, width, StrokeCap.Round)
    if (second > 0f) drawLine(color, c, c + (d - c) * second, width, StrokeCap.Round)
}

/** An O drawn round from the top. */
private fun DrawScope.drawO(origin: Offset, cell: Float, progress: Float, color: Color) {
    val pad = cell * MarkInset
    drawArc(
        color, startAngle = -90f, sweepAngle = 360f * progress, useCenter = false,
        topLeft = origin + Offset(pad, pad), size = Size(cell - 2 * pad, cell - 2 * pad),
        style = Stroke(width = 4.dp.toPx(), cap = StrokeCap.Round),
    )
}
