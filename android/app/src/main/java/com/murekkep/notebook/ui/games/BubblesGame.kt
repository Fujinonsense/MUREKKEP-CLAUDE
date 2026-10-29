package com.murekkep.notebook.ui.games

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.PanTool
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChanged
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.murekkep.notebook.R
import com.murekkep.notebook.games.Bubble
import com.murekkep.notebook.games.BubbleField
import com.murekkep.notebook.games.GameDifficulty
import com.murekkep.notebook.games.PopResult
import com.murekkep.notebook.games.Splash
import com.murekkep.notebook.ui.Zen
import kotlin.math.PI
import kotlin.math.ceil
import kotlin.math.cos
import kotlin.math.sin

// Ink bubbles (the iPad's BubblesGame.swift): they rise and sway for sixty seconds, faster and
// smaller as the clock runs; a tap or a touch of the pen pops the one under it. Quick pops in a row
// multiply the points; the dark blots must be left alone (a touch costs points and seconds). Kolay,
// Orta and Zor set the pace, the reach of a touch and the blots.

/**
 * The bubbles on screen: the field, the clock, the score and the row. The field is stepped every
 * frame while the round runs; the numbers on screen change only when they do, and [frame] (read only
 * by the drawing) redraws the field without composing the game again.
 */
internal class BubbleGameModel(difficulty: GameDifficulty) {
    /** A few words that float up from a pop: "+6 ×2", or a blot's cost. */
    class Floater(val x: Double, val y: Double, val points: Int, val combo: Int, val blot: Boolean, val at: Double) {
        companion object {
            const val LIFE = 0.8
        }
    }

    var score by mutableIntStateOf(0)
        private set
    var secondsLeft by mutableIntStateOf(BubbleField.ROUND.toInt())
        private set
    var isOver by mutableStateOf(false)
        private set
    var popped by mutableIntStateOf(0)
        private set
    var combo by mutableIntStateOf(1)
        private set
    var blotsHit by mutableIntStateOf(0)
        private set
    var frame by mutableLongStateOf(0L)
        private set
    var field = newField(316.0, 300.0, difficulty)
        private set
    val floaters = mutableListOf<Floater>()
    private var last: Long? = null

    private fun newField(width: Double, height: Double, difficulty: GameDifficulty) =
        BubbleField(width, height, System.currentTimeMillis().toULong(), difficulty)

    fun resize(width: Double, height: Double) {
        if (width <= 0 || height <= 0 || (width == field.width && height == field.height)) return
        field.width = width
        field.height = height
    }

    /** Steps the field on to the frame at [nanos]; the first step after a pause starts the clock again. */
    fun advance(nanos: Long) {
        if (isOver) return
        val dt = last?.let { (nanos - it) / 1e9 } ?: 0.0
        last = nanos
        field.advance(dt)
        floaters.removeAll { field.elapsed - it.at > Floater.LIFE }
        val left = ceil(field.timeLeft).toInt()
        if (left != secondsLeft) secondsLeft = left
        if (field.combo != combo) combo = field.combo
        if (field.isOver) isOver = true
        frame += 1
    }

    fun pause() {
        last = null
    }

    fun pop(x: Double, y: Double): PopResult {
        if (isOver) return PopResult.Miss
        val result = field.pop(x, y)
        when (result) {
            is PopResult.Popped -> {
                score = field.score
                popped += 1
                if (result.combo != combo) combo = result.combo
                floaters.add(Floater(x, y, result.points, result.combo, blot = false, at = field.elapsed))
            }
            is PopResult.Blot -> {
                score = field.score
                blotsHit += 1
                if (combo != 1) combo = 1
                floaters.add(Floater(x, y, result.points, result.seconds, blot = true, at = field.elapsed))
            }
            PopResult.Miss -> if (combo != 1) combo = 1
        }
        frame += 1
        return result
    }

    /** A fresh round at [difficulty]. */
    fun restart(difficulty: GameDifficulty) {
        field = newField(field.width, field.height, difficulty)
        floaters.clear()
        last = null
        score = 0
        popped = 0
        combo = 1
        blotsHit = 0
        secondsLeft = BubbleField.ROUND.toInt()
        isOver = false
        frame += 1
    }
}

@Composable
internal fun BubblesGame(store: GameProgressStore) {
    val z = Zen.colors
    val view = LocalView.current
    val difficulty = store[MiniGame.BUBBLES].difficulty
    val best = store[MiniGame.BUBBLES].best[difficulty] ?: 0
    val model = remember { BubbleGameModel(difficulty) }
    var newBest by remember { mutableStateOf(false) }
    val paused = model.isOver || !rememberAppInFront()
    LaunchedEffect(paused) {
        if (paused) {
            model.pause()
        } else {
            while (true) withFrameNanos { model.advance(it) }
        }
    }
    LaunchedEffect(model.isOver) {
        if (model.isOver) newBest = store.record(MiniGame.BUBBLES, model.score, difficulty)
    }

    Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        DifficultyPicker(difficulty) {
            if (it != difficulty) {
                store.setDifficulty(it, MiniGame.BUBBLES)
                newBest = false
                model.restart(it)
            }
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            Stat(stringResource(R.string.games_score), "${model.score}")
            Spacer(Modifier.weight(1f))
            val spoken = stringResource(R.string.games_seconds_left, model.secondsLeft)
            Text(
                clock(model.secondsLeft),
                style = GameText.title3.copy(fontWeight = FontWeight.SemiBold).numeric(),
                color = if (model.secondsLeft <= 10 && !model.isOver) MaterialTheme.colorScheme.error else z.ink,
                modifier = Modifier.semantics { contentDescription = spoken },
            )
            Spacer(Modifier.weight(1f))
            Stat(stringResource(R.string.games_best_label), "$best")
        }
        Box(Modifier.weight(1f).fillMaxWidth().gameBoard()) {
            BubbleArea(model) { result ->
                when (result) {
                    is PopResult.Popped -> view.gameKnock()
                    is PopResult.Blot -> view.gameWarning()
                    PopResult.Miss -> {}
                }
            }
            Row(Modifier.fillMaxWidth().padding(8.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Outlined.PanTool, contentDescription = null, tint = z.muted, modifier = Modifier.size(12.dp))
                Spacer(Modifier.size(4.dp))
                Text(stringResource(R.string.games_leave_the_blots), style = GameText.caption2, color = z.muted)
                Spacer(Modifier.weight(1f))
                val multiplier = stringResource(R.string.games_multiplier, model.combo)
                AnimatedVisibility(model.combo > 1, enter = scaleIn() + fadeIn(), exit = scaleOut() + fadeOut()) {
                    Text(
                        "×${model.combo}",
                        style = GameText.caption.copy(fontWeight = FontWeight.Bold).numeric(),
                        color = Color.White,
                        modifier = Modifier
                            .background(z.accent, CircleShape)
                            .padding(horizontal = 8.dp, vertical = 3.dp)
                            .clearAndSetSemantics { contentDescription = multiplier },
                    )
                }
            }
            ResultCardOver(model.isOver, Modifier.align(Alignment.Center)) {
                ResultCard(
                    title = stringResource(R.string.games_times_up),
                    lines = listOf(
                        stringResource(R.string.games_score_value, model.score),
                        stringResource(R.string.games_bubbles_blots, model.popped, model.blotsHit),
                    ),
                    highlight = if (newBest) stringResource(R.string.games_new_best) else stringResource(R.string.games_best, best),
                    actions = listOf(
                        ResultAction(stringResource(R.string.games_again), prominent = true) {
                            newBest = false
                            model.restart(difficulty)
                        },
                    ),
                )
            }
        }
    }
}

/** A number over its name: the score, the best. */
@Composable
private fun Stat(title: String, value: String) {
    val z = Zen.colors
    Column(Modifier.widthIn(min = 56.dp).semantics(mergeDescendants = true) {}, horizontalAlignment = Alignment.CenterHorizontally) {
        Text(value, style = GameText.headline, color = z.ink)
        Text(title, style = GameText.caption2, color = z.muted)
    }
}

/** The field: the bubbles, the blots, the splashes and the floating points; a touch, held or dragged, pops what it meets. */
@Composable
private fun BubbleArea(model: BubbleGameModel, onPop: (PopResult) -> Unit) {
    val z = Zen.colors
    val density = LocalDensity.current.density
    val label = stringResource(R.string.games_bubble_field)
    val blotCost = stringResource(R.string.games_blot_cost, BubbleField.BLOT_POINTS, BubbleField.BLOT_SECONDS)
    val clash = MaterialTheme.colorScheme.error
    val measurer = rememberTextMeasurer()
    Canvas(
        Modifier
            .fillMaxSize()
            .onSizeChanged { model.resize(it.width / density.toDouble(), it.height / density.toDouble()) }
            .pointerInput(model, density) {
                awaitEachGesture {
                    val down = awaitFirstDown()
                    down.consume()
                    onPop(model.pop(down.position.x / density.toDouble(), down.position.y / density.toDouble()))
                    while (true) {
                        val event = awaitPointerEvent()
                        val change = event.changes.firstOrNull { it.id == down.id } ?: break
                        if (!change.pressed) break
                        change.consume()
                        if (change.positionChanged()) onPop(model.pop(change.position.x / density.toDouble(), change.position.y / density.toDouble()))
                    }
                }
            }
            .semantics { contentDescription = label },
    ) {
        model.frame
        val field = model.field
        for (bubble in field.bubbles) {
            if (bubble.kind == Bubble.Kind.INK) inkBubble(bubble, density) else blot(bubble, density, clash)
        }
        for (splash in field.splashes) splash(splash, density)
        for (floater in model.floaters) {
            val t = ((field.elapsed - floater.at) / BubbleGameModel.Floater.LIFE).toFloat().coerceIn(0f, 1f)
            val text = when {
                floater.blot -> blotCost
                floater.combo > 1 -> "+${floater.points} ×${floater.combo}"
                else -> "+${floater.points}"
            }
            floaterText(measurer, text, (if (floater.blot) clash else z.accent).copy(alpha = 1 - t), Offset(floater.x.toFloat() * density, (floater.y.toFloat() - 14 - 28 * t) * density))
        }
    }
}

private fun DrawScope.floaterText(measurer: TextMeasurer, text: String, color: Color, at: Offset) {
    val layout = measurer.measure(text, TextStyle(fontSize = 12.sp, fontWeight = FontWeight.Bold, color = color, fontFeatureSettings = "tnum"))
    drawText(layout, topLeft = at - Offset(layout.size.width / 2f, layout.size.height / 2f))
}

private fun hsb(hue: Double, saturation: Float, brightness: Float) = Color.hsv((hue * 360).toFloat().coerceIn(0f, 360f), saturation, brightness)

/** A glossy ink bubble: a soft gradient, a rim, a glint. */
private fun DrawScope.inkBubble(bubble: Bubble, d: Float) {
    val centre = Offset(bubble.x.toFloat() * d, bubble.y.toFloat() * d)
    val r = bubble.radius.toFloat() * d
    val tint = hsb(bubble.hue, 0.7f, 0.95f)
    drawCircle(Brush.radialGradient(listOf(tint.copy(alpha = 0.1f), tint.copy(alpha = 0.4f)), centre, r), r, centre)
    drawCircle(tint.copy(alpha = 0.85f), r, centre, style = Stroke(1.4f * d))
    drawOval(Color.White.copy(alpha = 0.55f), Offset(centre.x - r * 0.55f, centre.y - r * 0.62f), Size(r * 0.36f, r * 0.22f))
}

/** A blot: a dark, uneven splatter of ink with a faint red rim, not to be touched. */
private fun DrawScope.blot(bubble: Bubble, d: Float, red: Color) {
    val points = 9
    val shape = Path()
    for (k in 0..points) {
        val angle = (k % points) * 2 * PI / points + bubble.age * 0.4
        val wobble = 0.78 + 0.22 * sin((k % points) * 2.3 + bubble.id)
        val r = bubble.radius * wobble
        val x = ((bubble.x + cos(angle) * r) * d).toFloat()
        val y = ((bubble.y + sin(angle) * r) * d).toFloat()
        if (k == 0) shape.moveTo(x, y) else shape.lineTo(x, y)
    }
    shape.close()
    val dark = hsb(0.64, 0.6f, 0.22f)
    drawPath(shape, dark.copy(alpha = 0.92f))
    drawPath(shape, red.copy(alpha = 0.45f), style = Stroke(1f * d))
    // A few satellite drops.
    for (k in 0 until 3) {
        val angle = k * 2.1 + bubble.id
        val reach = bubble.radius * 1.25
        drawCircle(dark.copy(alpha = 0.8f), 2f * d, Offset(((bubble.x + cos(angle) * reach) * d).toFloat(), ((bubble.y + sin(angle) * reach) * d).toFloat()))
    }
}

/** A popped bubble's ring and six droplets flying out, fading over [Splash.LIFE]. */
private fun DrawScope.splash(splash: Splash, d: Float) {
    val t = (splash.age / Splash.LIFE).toFloat()
    val fade = 1 - t
    val tint = if (splash.blot) hsb(0.64, 0.5f, 0.3f) else hsb(splash.hue, 0.7f, 0.95f)
    val centre = Offset(splash.x.toFloat() * d, splash.y.toFloat() * d)
    val r = splash.radius.toFloat() * (1 + 1.4f * t) * d
    drawCircle(tint.copy(alpha = (0.7f * fade).coerceIn(0f, 1f)), r, centre, style = Stroke((2 * fade + 0.5f) * d))
    val reach = splash.radius * (0.6 + 1.6 * t)
    for (k in 0 until 6) {
        val angle = k * PI / 3 + splash.radius
        val drop = Offset(((splash.x + cos(angle) * reach) * d).toFloat(), ((splash.y + sin(angle) * reach) * d).toFloat())
        drawCircle(tint.copy(alpha = (0.8f * fade).coerceIn(0f, 1f)), 2f * d, drop)
    }
}
