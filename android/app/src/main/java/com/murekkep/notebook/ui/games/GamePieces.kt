package com.murekkep.notebook.ui.games

import android.os.Build
import android.view.HapticFeedbackConstants
import android.view.View
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.text.TextAutoSize
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material.icons.outlined.StarOutline
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.PointerInputChange
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.disabled
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.currentStateAsState
import com.murekkep.notebook.R
import com.murekkep.notebook.games.GameDifficulty
import com.murekkep.notebook.games.GameProgress
import com.murekkep.notebook.ui.Zen
import com.murekkep.notebook.ui.ZenSegments

// The pieces every game of the break corner shares (the second half of the iPad's GameCorner.swift):
// the iPad's text sizes, the difficulty picker, the board's frame, the stars, the card at the end of a
// round, the levelled games' map, the taps and knocks, the clock.

/** The iPad's text styles in the games (caption 2 is 11 pt, title 3 is 20), the system font throughout. */
internal object GameText {
    val caption2: TextStyle @Composable get() = MaterialTheme.typography.labelSmall.copy(fontSize = 11.sp, lineHeight = 13.sp, fontWeight = FontWeight.Normal)
    val caption: TextStyle @Composable get() = MaterialTheme.typography.bodySmall.copy(fontSize = 12.sp, lineHeight = 16.sp)
    val footnote: TextStyle @Composable get() = MaterialTheme.typography.bodySmall
    val subheadline: TextStyle @Composable get() = MaterialTheme.typography.bodyMedium.copy(fontSize = 15.sp, lineHeight = 20.sp)
    val headline: TextStyle @Composable get() = MaterialTheme.typography.titleMedium.numeric()
    /** A title: bold and tight, as every heading of the zen look. */
    val title3: TextStyle @Composable get() = MaterialTheme.typography.titleLarge.copy(fontSize = 20.sp, lineHeight = 24.sp, fontWeight = FontWeight.Bold)
}

/** Digits of one width, so a running number does not shake. */
internal fun TextStyle.numeric(): TextStyle = merge(TextStyle(fontFeatureSettings = "tnum"))

/** One line of text that shrinks to [minScale] of its size before it is cut short (the iPad's minimumScaleFactor). */
@Composable
internal fun FitText(text: String, style: TextStyle, color: Color, modifier: Modifier = Modifier, minScale: Float = 0.8f, align: TextAlign = TextAlign.Start) {
    val size = style.fontSize
    BasicText(
        text,
        modifier,
        style = style.copy(color = color, textAlign = align),
        maxLines = 1,
        overflow = TextOverflow.Ellipsis,
        autoSize = TextAutoSize.StepBased(minFontSize = size * minScale, maxFontSize = size, stepSize = 0.5.sp),
    )
}

internal val GameDifficulty.titleRes: Int
    get() = when (this) {
        GameDifficulty.EASY -> R.string.games_easy
        GameDifficulty.MEDIUM -> R.string.games_medium
        GameDifficulty.HARD -> R.string.games_hard
    }

/** Kolay / Orta / Zor, in the app's segmented track. */
@Composable
internal fun DifficultyPicker(difficulty: GameDifficulty, onChange: (GameDifficulty) -> Unit) {
    val label = stringResource(R.string.games_difficulty)
    ZenSegments(
        options = GameDifficulty.entries.map { stringResource(it.titleRes) },
        selected = difficulty.ordinal,
        onSelect = { onChange(GameDifficulty.entries[it]) },
        modifier = Modifier.fillMaxWidth().semantics { contentDescription = label },
    )
}

/** A card's corners in the zen look (cards and covers 10 to 12). */
internal val CardCorner = 12.dp

/** The frame every game's field stands in: paper, a hairline, a card's corners. */
@Composable
internal fun Modifier.gameBoard(): Modifier {
    val z = Zen.colors
    val shape = RoundedCornerShape(CardCorner)
    return clip(shape).background(z.paper).border(1.dp, z.rule, shape)
}

/** Three stars, [stars] of them filled in the accent. */
@Composable
internal fun StarRow(stars: Int, size: Dp = 12.dp, modifier: Modifier = Modifier) {
    val z = Zen.colors
    val label = stringResource(R.string.games_stars, stars)
    Row(modifier.clearAndSetSemantics { contentDescription = label }, horizontalArrangement = Arrangement.spacedBy(2.dp)) {
        for (i in 0 until 3) {
            Icon(
                if (i < stars) Icons.Filled.Star else Icons.Outlined.StarOutline,
                contentDescription = null,
                tint = if (i < stars) z.accent else z.muted.copy(alpha = 0.4f),
                modifier = Modifier.size(size),
            )
        }
    }
}

/**
 * A button of the games, 40 dp tall as the app's ZenButton: [prominent] in ink with paper text,
 * else paper-2 in a hairline; [icon] before the label, a small busy ring in its place while [busy].
 */
@Composable
internal fun GameButton(
    label: String,
    prominent: Boolean,
    modifier: Modifier = Modifier,
    icon: ImageVector? = null,
    enabled: Boolean = true,
    busy: Boolean = false,
    height: Dp = 40.dp,
    onClick: () -> Unit,
) {
    val z = Zen.colors
    val shape = RoundedCornerShape(Zen.control)
    val ink = when {
        !enabled && !busy -> z.muted
        prominent -> z.paper
        else -> z.ink
    }
    Row(
        modifier
            .height(height)
            .clip(shape)
            .background(if (prominent) z.ink else z.paper2)
            .border(1.dp, if (prominent) z.ink else z.rule, shape)
            .clickable(enabled = enabled && !busy, role = Role.Button, onClick = onClick)
            .padding(horizontal = if (height < 40.dp) 10.dp else 16.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        if (busy) {
            CircularProgressIndicator(color = ink, strokeWidth = 2.dp, modifier = Modifier.size(16.dp))
        } else if (icon != null) {
            Icon(icon, contentDescription = null, tint = ink, modifier = Modifier.size(16.dp))
        }
        Text(label, style = MaterialTheme.typography.labelLarge.copy(fontSize = if (height < 40.dp) 13.sp else 15.sp), color = ink, maxLines = 1)
    }
}

/** A thing to do at the end of a round or a level. */
internal class ResultAction(val title: String, val prominent: Boolean = false, val action: () -> Unit)

/** The card at the end of a round or a level: a bold title, the stars, a line or two, the buttons. */
@Composable
internal fun ResultCard(
    title: String,
    actions: List<ResultAction>,
    modifier: Modifier = Modifier,
    stars: Int? = null,
    lines: List<String> = emptyList(),
    highlight: String? = null,
) {
    val z = Zen.colors
    val shape = RoundedCornerShape(Zen.popover)
    Column(
        modifier
            .widthIn(max = 290.dp)
            .clip(shape)
            .background(z.paper)
            .border(1.dp, z.rule, shape)
            .verticalScroll(rememberScrollState())
            .padding(18.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Text(title, style = GameText.title3, color = z.ink, textAlign = TextAlign.Center)
        if (stars != null) StarRow(stars, size = 20.dp)
        for (line in lines) Text(line, style = GameText.subheadline, color = z.muted, textAlign = TextAlign.Center)
        if (highlight != null) Text(highlight, style = GameText.subheadline.copy(fontWeight = FontWeight.SemiBold), color = z.accent, textAlign = TextAlign.Center)
        Row(Modifier.padding(top = 2.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            for (item in actions) GameButton(item.title, prominent = item.prominent, onClick = item.action)
        }
    }
}

/** A result card that comes in over a board: a slight scale and a fade. */
@Composable
internal fun ResultCardOver(visible: Boolean, modifier: Modifier = Modifier, card: @Composable () -> Unit) {
    AnimatedVisibility(visible, modifier, enter = scaleIn(initialScale = 0.92f) + fadeIn(), exit = scaleOut(targetScale = 0.92f) + fadeOut()) {
        card()
    }
}

/**
 * The level map of a levelled game: the difficulty, then the levels as tiles; locked ones wait, the
 * next one to play is ringed in the accent. Android has no levelled game yet (the iPad's flying drop
 * and colour popper use it).
 */
@Composable
internal fun LevelMap(
    levels: Int,
    kept: GameProgress,
    onDifficulty: (GameDifficulty) -> Unit,
    onStart: (Int) -> Unit,
    modifier: Modifier = Modifier,
) {
    val z = Zen.colors
    Column(modifier, verticalArrangement = Arrangement.spacedBy(10.dp)) {
        DifficultyPicker(kept.difficulty, onDifficulty)
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Filled.Star, contentDescription = null, tint = z.muted, modifier = Modifier.size(12.dp))
            Spacer(Modifier.size(4.dp))
            Text(stringResource(R.string.games_stars_in_all, kept.totalStars), style = GameText.caption, color = z.muted)
            Spacer(Modifier.weight(1f))
            Text(stringResource(R.string.games_level_open, kept.unlockedLevel), style = GameText.caption, color = z.muted)
        }
        Column(Modifier.verticalScroll(rememberScrollState()).padding(vertical = 2.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            for (row in (1..levels).chunked(4)) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    for (level in row) LevelTile(level, kept, Modifier.weight(1f)) { onStart(level) }
                    repeat(4 - row.size) { Spacer(Modifier.weight(1f)) }
                }
            }
        }
    }
}

@Composable
private fun LevelTile(level: Int, kept: GameProgress, modifier: Modifier, onStart: () -> Unit) {
    val z = Zen.colors
    val open = kept.isUnlocked(level)
    val next = level == kept.unlockedLevel
    val shape = RoundedCornerShape(CardCorner)
    val label = if (open) stringResource(R.string.games_level, level) else stringResource(R.string.games_level_locked, level)
    Column(
        modifier
            .height(54.dp)
            .clip(shape)
            .background(if (open) z.accent.copy(alpha = 0.08f) else z.ink.copy(alpha = 0.035f))
            .border(if (next) 1.4.dp else 1.dp, if (next) z.accent.copy(alpha = 0.7f) else z.rule, shape)
            .clickable(enabled = open, role = Role.Button, onClick = onStart)
            .clearAndSetSemantics {
                contentDescription = label
                role = Role.Button
                if (open) onClick { onStart(); true } else disabled()
            },
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(4.dp, Alignment.CenterVertically),
    ) {
        if (open) {
            Text("$level", style = GameText.headline, color = if (next) z.accent else z.ink)
        } else {
            Icon(Icons.Outlined.Lock, contentDescription = null, tint = z.muted, modifier = Modifier.size(14.dp))
        }
        StarRow(kept.starsAt(level), size = 8.dp, modifier = Modifier.alpha(if (open) 1f else 0.35f))
    }
}

/** The end of a level: stars, a line of detail, and what to do next. */
@Composable
internal fun LevelResultCard(won: Boolean, stars: Int, detail: String, hasNext: Boolean, onLevels: () -> Unit, onRetry: () -> Unit, onNext: () -> Unit) {
    val actions = mutableListOf(
        ResultAction(stringResource(R.string.games_levels), action = onLevels),
        ResultAction(stringResource(R.string.games_again), prominent = !(won && hasNext), action = onRetry),
    )
    if (won && hasNext) actions.add(ResultAction(stringResource(R.string.games_next), prominent = true, action = onNext))
    ResultCard(
        title = stringResource(if (won) R.string.games_level_done else R.string.games_not_this_time),
        actions = actions,
        stars = if (won) stars else null,
        lines = listOf(detail),
    )
}

/**
 * A touch on a board, a finger's or the pen's: [onEnd] gets where it began, and the board's size,
 * once it lifts (the iPad's DragGesture(minimumDistance: 0).onEnded with its startLocation). A touch
 * the system cancels (a palm, a gesture of the system's) does nothing.
 */
@Composable
internal fun Modifier.onTouchEnd(onEnd: (start: Offset, size: IntSize) -> Unit): Modifier {
    val latest by rememberUpdatedState(onEnd)
    return pointerInput(Unit) {
        awaitEachGesture {
            val down = awaitFirstDown()
            down.consume()
            while (true) {
                val change = awaitPointerEvent().changes.firstOrNull { it.id == down.id } ?: return@awaitEachGesture
                val cancelled = change.cancelledLift()
                change.consume()
                if (!change.pressed) {
                    if (!cancelled) latest(down.position, size)
                    return@awaitEachGesture
                }
            }
        }
    }
}

/**
 * A drag on a board: [onMove] with where it began, where it is now and the board's size, from the
 * first touch on; [onEnd] with the same once it lifts, or [onCancel] when the system takes the touch
 * back (the iPad's DragGesture with its @GestureState falling back).
 */
@Composable
internal fun Modifier.onDrag(
    onMove: (start: Offset, now: Offset, size: IntSize) -> Unit,
    onEnd: (start: Offset, now: Offset, size: IntSize) -> Unit,
    onCancel: () -> Unit,
): Modifier {
    val move by rememberUpdatedState(onMove)
    val end by rememberUpdatedState(onEnd)
    val cancel by rememberUpdatedState(onCancel)
    return pointerInput(Unit) {
        awaitEachGesture {
            val down = awaitFirstDown()
            down.consume()
            move(down.position, down.position, size)
            while (true) {
                val change = awaitPointerEvent().changes.firstOrNull { it.id == down.id }
                if (change == null) {
                    cancel()
                    return@awaitEachGesture
                }
                val cancelled = change.cancelledLift()
                change.consume()
                if (!change.pressed) {
                    if (cancelled) cancel() else end(down.position, change.position, size)
                    return@awaitEachGesture
                }
                move(down.position, change.position, size)
            }
        }
    }
}

/**
 * True for the lift of a touch the system took back (ACTION_CANCEL: a palm, a gesture of the
 * system's): Compose hands it over as a lift that is consumed already, where a real lift comes fresh.
 */
private fun PointerInputChange.cancelledLift(): Boolean = !pressed && isConsumed

/** "1:05": minutes and seconds. */
internal fun clock(seconds: Int): String = "%d:%02d".format(seconds / 60, seconds % 60)

/** True while the app is in front (the iPad's scenePhase == .active): the clocks and the bubbles stop when it is not. */
@Composable
internal fun rememberAppInFront(): Boolean {
    val state by LocalLifecycleOwner.current.lifecycle.currentStateAsState()
    return state.isAtLeast(Lifecycle.State.RESUMED)
}

// The iPad's sensoryFeedback in the games, as Android's haptic constants (the system's touch
// feedback setting applies).

/** A pick: a mark or a line placed. */
internal fun View.gameTick() {
    performHapticFeedback(if (Build.VERSION.SDK_INT >= 34) HapticFeedbackConstants.SEGMENT_FREQUENT_TICK else HapticFeedbackConstants.CLOCK_TICK)
}

/** A light knock: a bubble popped, a box taken. */
internal fun View.gameKnock() {
    performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
}

/** A game won, a puzzle solved. */
internal fun View.gameSuccess() {
    performHapticFeedback(if (Build.VERSION.SDK_INT >= 30) HapticFeedbackConstants.CONFIRM else HapticFeedbackConstants.VIRTUAL_KEY)
}

/** A blot touched. */
internal fun View.gameWarning() {
    performHapticFeedback(if (Build.VERSION.SDK_INT >= 30) HapticFeedbackConstants.REJECT else HapticFeedbackConstants.LONG_PRESS)
}
