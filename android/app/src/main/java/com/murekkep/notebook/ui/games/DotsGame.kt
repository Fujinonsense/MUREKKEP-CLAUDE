package com.murekkep.notebook.ui.games

import android.view.View
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.murekkep.notebook.R
import com.murekkep.notebook.games.DotsAI
import com.murekkep.notebook.games.DotsBoard
import com.murekkep.notebook.games.DotsEdge
import com.murekkep.notebook.games.DotsPlayer
import com.murekkep.notebook.games.GameDifficulty
import com.murekkep.notebook.games.GameRandom
import com.murekkep.notebook.ui.Zen
import kotlin.math.max
import kotlin.math.sqrt
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext

// Kare kapmaca against the device, the game of a notebook's back pages (the iPad's DotsGame.swift):
// tap between two neighbouring dots, or draw the line, to join them; close a box to take it and draw
// again. Kolay is 3x3, Orta 4x4, Zor 5x5 against a device that counts the end through. "Tekrar"
// starts again with the other side first; wins are counted per difficulty.

/** The device's lines and boxes, in amber against the player's ink (the iPad's game ink 3). */
private val DeviceInk = Color.hsv(0.10f * 360, 0.78f, 0.92f)

/** A game on the board: its lines and boxes, the line under the pen, the device's turns. */
private class DotsPlay(private val store: GameProgressStore, private val view: View) {
    var board by mutableStateOf(DotsBoard(DotsBoard.size(store[MiniGame.DOTS].difficulty)))
        private set
    /** The line under the pen before it lifts, and the line drawn last. */
    var hover by mutableStateOf<DotsEdge?>(null)
    var latest by mutableStateOf<DotsEdge?>(null)
        private set
    /** Counts the device's turns; each one runs the reply afresh. */
    var pendingReply by mutableIntStateOf(0)
        private set
    private var rng = GameRandom.clock()
    private var humanFirst = true
    private var counted = false

    val difficulty: GameDifficulty get() = store[MiniGame.DOTS].difficulty
    val wins: Int get() = store[MiniGame.DOTS].best[difficulty] ?: 0

    /** The free line whose middle is nearest [point], if it is within four tenths of a gap of it. */
    fun edgeNear(point: Offset, inset: Float, step: Float): DotsEdge? {
        var nearest: DotsEdge? = null
        var reach = step * 0.4f
        for (edge in board.freeEdges) {
            val mid = if (edge.horizontal) {
                Offset(inset + (edge.col + 0.5f) * step, inset + edge.row * step)
            } else {
                Offset(inset + edge.col * step, inset + (edge.row + 0.5f) * step)
            }
            val dx = mid.x - point.x
            val dy = mid.y - point.y
            val distance = sqrt(dx * dx + dy * dy)
            if (distance < reach) {
                reach = distance
                nearest = edge
            }
        }
        return nearest
    }

    /** The player's line; when it closes nothing, the device thinks. */
    fun play(edge: DotsEdge) {
        if (board.isOver || board.turn != DotsPlayer.YOU) return
        draw(edge)
        if (!board.isOver && board.turn == DotsPlayer.DEVICE) pendingReply += 1
    }

    private fun draw(edge: DotsEdge) {
        val next = board.copy()
        val closed = next.draw(edge) ?: return
        board = next
        latest = edge
        if (closed.isNotEmpty()) view.gameKnock() else view.gameTick()
        if (next.isOver && !counted) {
            counted = true
            if (next.winner == DotsPlayer.YOU) {
                store.record(MiniGame.DOTS, wins + 1, difficulty)
                view.gameSuccess()
            }
        }
    }

    /**
     * The device's turn: a line every moment until one closes nothing or the game ends; Zor's search
     * runs off the main thread. Cancelled with the game if the panel closes first.
     */
    suspend fun reply() {
        while (pendingReply > 0 && !board.isOver && board.turn == DotsPlayer.DEVICE) {
            delay(450)
            if (board.isOver || board.turn != DotsPlayer.DEVICE) return
            val snapshot = board
            val level = difficulty
            val random = rng.copy()
            val move = withContext(Dispatchers.Default) { DotsAI.move(snapshot, level, random) }
            if (board !== snapshot || move == null) return
            rng = random
            draw(move)
        }
    }

    /** A new game at the chosen size; the other side starts, unless the difficulty changed mid-game. */
    fun restart(keepTurn: Boolean = false) {
        if (!keepTurn) humanFirst = !humanFirst
        board = DotsBoard(DotsBoard.size(difficulty), if (humanFirst) DotsPlayer.YOU else DotsPlayer.DEVICE)
        counted = false
        hover = null
        latest = null
        if (!humanFirst) pendingReply += 1
    }
}

@Composable
internal fun DotsGame(store: GameProgressStore) {
    val z = Zen.colors
    val view = LocalView.current
    val play = remember { DotsPlay(store, view) }
    val board = play.board
    val difficulty = play.difficulty
    val status = when {
        board.isOver -> when (board.winner) {
            DotsPlayer.YOU -> stringResource(R.string.games_you_won)
            DotsPlayer.DEVICE -> stringResource(R.string.games_device_won)
            null -> stringResource(R.string.games_draw)
        }
        board.turn == DotsPlayer.YOU -> stringResource(R.string.games_dots_your_turn)
        else -> stringResource(R.string.games_device_thinking)
    }
    LaunchedEffect(play.pendingReply) { play.reply() }

    Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        DifficultyPicker(difficulty) {
            if (it != difficulty) {
                store.setDifficulty(it, MiniGame.DOTS)
                play.restart(keepTurn = true)
            }
        }
        Row(Modifier.fillMaxWidth().height(24.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Tally(stringResource(R.string.games_you), board.score(DotsPlayer.YOU), z.accent, turn = board.turn == DotsPlayer.YOU && !board.isOver)
            Box(Modifier.weight(1f), contentAlignment = Alignment.Center) {
                FitText(
                    status,
                    GameText.subheadline.copy(fontWeight = FontWeight.SemiBold),
                    if (board.isOver) z.accent else z.muted,
                    minScale = 0.75f,
                )
            }
            Tally(stringResource(R.string.games_device), board.score(DotsPlayer.DEVICE), DeviceInk, turn = board.turn == DotsPlayer.DEVICE && !board.isOver)
        }
        BoxWithConstraints(Modifier.weight(1f).fillMaxWidth()) {
            val side = minOf(maxWidth, maxHeight)
            DotsBoardView(play, status, Modifier.size(side).align(Alignment.Center))
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            val hint = when (difficulty) {
                GameDifficulty.HARD -> R.string.games_dots_hard
                GameDifficulty.EASY -> R.string.games_dots_easy
                GameDifficulty.MEDIUM -> R.string.games_dots_medium
            }
            FitText(stringResource(hint), GameText.caption2, z.muted, Modifier.weight(1f), minScale = 0.7f)
            AgainButton(visible = board.isOver) { play.restart() }
        }
    }
}

/** A side's name and boxes, underlined while it is their turn. */
@Composable
private fun Tally(name: String, boxes: Int, ink: Color, turn: Boolean) {
    Column(Modifier.width(IntrinsicSize.Max).semantics(mergeDescendants = true) {}) {
        Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            val style = GameText.subheadline.copy(fontWeight = FontWeight.SemiBold)
            Text(name, style = style, color = ink, maxLines = 1)
            Text("$boxes", style = style.numeric(), color = ink)
        }
        Box(
            Modifier
                .padding(top = 2.dp)
                .fillMaxWidth()
                .height(2.dp)
                .alpha(if (turn) 1f else 0f)
                .background(ink, RoundedCornerShape(1.dp)),
        )
    }
}

/**
 * The board: the taken boxes washed in their taker's ink with a name, the line under the pen, the
 * lines drawn (the last one bolder), and the dots over them. A touch draws the free line nearest the
 * middle of where it began and where it is.
 */
@Composable
private fun DotsBoardView(play: DotsPlay, status: String, modifier: Modifier) {
    val z = Zen.colors
    val label = stringResource(R.string.games_dots_board)
    val you = stringResource(R.string.games_you)
    val device = stringResource(R.string.games_device)
    val measurer = rememberTextMeasurer()
    fun geometry(width: Float): Pair<Float, Float> {
        val inset = width * 0.09f
        return inset to (width - 2 * inset) / play.board.size
    }
    fun near(start: Offset, now: Offset, size: IntSize): DotsEdge? {
        val (inset, step) = geometry(size.width.toFloat())
        return play.edgeNear((start + now) / 2f, inset, step)
    }
    Canvas(
        modifier
            .gameBoard()
            .onDrag(
                onMove = { start, now, size -> play.hover = near(start, now, size) },
                onEnd = { start, now, size ->
                    play.hover = null
                    near(start, now, size)?.let { play.play(it) }
                },
                onCancel = { play.hover = null },
            )
            .semantics {
                contentDescription = label
                stateDescription = status
            },
    ) {
        val board = play.board
        val (inset, step) = geometry(size.width)
        val n = board.size
        for ((box, owner) in board.owners) {
            val pad = 4.dp.toPx()
            val rect = Rect(inset + (box % n) * step + pad, inset + (box / n) * step + pad, inset + (box % n + 1) * step - pad, inset + (box / n + 1) * step - pad)
            val ink = if (owner == DotsPlayer.YOU) z.accent else DeviceInk
            drawRoundRect(ink.copy(alpha = 0.14f), rect.topLeft, rect.size, CornerRadius(5.dp.toPx()))
            val name = measurer.measure(
                if (owner == DotsPlayer.YOU) you else device,
                TextStyle(color = ink, fontSize = max(9.sp.toPx(), step * 0.2f).toSp(), fontWeight = FontWeight.SemiBold),
            )
            drawText(name, topLeft = rect.center - Offset(name.size.width / 2f, name.size.height / 2f))
        }
        val hover = play.hover
        if (hover != null && board.turn == DotsPlayer.YOU && !board.isOver) {
            val (from, to) = ends(hover, inset, step)
            drawLine(
                z.accent.copy(alpha = 0.35f), from, to, 3.dp.toPx(), StrokeCap.Round,
                PathEffect.dashPathEffect(floatArrayOf(4.dp.toPx(), 5.dp.toPx())),
            )
        }
        for ((edge, player) in board.lines) {
            val (from, to) = ends(edge, inset, step)
            drawLine(if (player == DotsPlayer.YOU) z.accent else DeviceInk, from, to, (if (edge == play.latest) 4.5f else 3.2f).dp.toPx(), StrokeCap.Round)
        }
        val dot = 3.5.dp.toPx()
        for (row in 0..n) for (col in 0..n) drawCircle(z.ink.copy(alpha = 0.75f), dot, Offset(inset + col * step, inset + row * step))
    }
}

/** A line's two dots on the board. */
private fun ends(edge: DotsEdge, inset: Float, step: Float): Pair<Offset, Offset> {
    val from = Offset(inset + edge.col * step, inset + edge.row * step)
    return from to if (edge.horizontal) Offset(from.x + step, from.y) else Offset(from.x, from.y + step)
}
