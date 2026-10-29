package com.murekkep.notebook.games

import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt

/** A bubble of ink on its way up, or a blot, which must not be popped. */
data class Bubble(
    val id: Int,
    val kind: Kind,
    /** The column it rises in (dp); [x] swings around it. */
    val home: Double,
    var x: Double,
    /** Its centre from the top of the field (dp). */
    var y: Double,
    val radius: Double,
    /** Dp per second, upwards. */
    val speed: Double,
    /** How far it swings, and where in the swing it started. */
    val sway: Double,
    val phase: Double,
    val hue: Double,
    var age: Double = 0.0,
) {
    enum class Kind { INK, BLOT }

    /** Small bubbles are worth most; a blot is worth nothing but trouble. */
    val worth: Int
        get() = when (kind) {
            Kind.BLOT -> 0
            Kind.INK -> if (radius < 15) 3 else if (radius < 21) 2 else 1
        }
}

/** The splash a popped bubble (or a touched blot) leaves, for a moment. */
data class Splash(val x: Double, val y: Double, val radius: Double, val hue: Double, val blot: Boolean, var age: Double = 0.0) {
    val done: Boolean get() = age >= LIFE

    companion object {
        const val LIFE = 0.45
    }
}

/** What one touch of the field did. */
sealed interface PopResult {
    data class Popped(val points: Int, val combo: Int) : PopResult
    data class Blot(val points: Int, val seconds: Int) : PopResult
    data object Miss : PopResult
}

/**
 * Sixty seconds of bubbles rising through a field [width] x [height] dp; each touch pops the bubble
 * under it (the iPad's BubbleField). They come faster and smaller as the clock runs, blots rise among
 * them (a touch costs points and seconds), and quick pops in a row multiply the points. The field is
 * stepped by [advance]; nothing in it knows about the screen.
 */
class BubbleField private constructor(
    var width: Double,
    var height: Double,
    val tuning: Tuning,
    private var rng: GameRandom,
) {
    constructor(width: Double, height: Double, seed: ULong, difficulty: GameDifficulty = GameDifficulty.MEDIUM) :
        this(width, height, Tuning.of(difficulty), GameRandom(seed))

    /** How the difficulty reads: the pace, the reach of a touch, the share of blots. */
    data class Tuning(
        /** How much faster than Orta everything comes and rises. */
        val pace: Double,
        /** How far beside a bubble's edge a touch still pops it (a fingertip is wide). */
        val reach: Double,
        /** The share of blots among what comes up, at the start and at the end. */
        val blotsAtStart: Double,
        val blotsAtEnd: Double,
    ) {
        companion object {
            fun of(difficulty: GameDifficulty): Tuning = when (difficulty) {
                GameDifficulty.EASY -> Tuning(pace = 0.8, reach = 14.0, blotsAtStart = 0.06, blotsAtEnd = 0.18)
                GameDifficulty.MEDIUM -> Tuning(pace = 1.0, reach = 10.0, blotsAtStart = 0.12, blotsAtEnd = 0.3)
                GameDifficulty.HARD -> Tuning(pace = 1.3, reach = 7.0, blotsAtStart = 0.18, blotsAtEnd = 0.4)
            }
        }
    }

    private val _bubbles = mutableListOf<Bubble>()
    private val _splashes = mutableListOf<Splash>()
    val bubbles: List<Bubble> get() = _bubbles
    val splashes: List<Splash> get() = _splashes
    var score = 0; private set
    var popped = 0; private set
    var blotsHit = 0; private set
    /** Ink bubbles that got away over the top. */
    var escaped = 0; private set
    var combo = 1; private set
    var elapsed = 0.0; private set
    /** Seconds taken off the clock by blots. */
    var penalty = 0.0; private set
    private var lastPop = -10.0
    private var untilSpawn = 0.5
    private var nextId = 1

    val pace: Double get() = tuning.pace
    /** The clock, with the blots' seconds gone. */
    val timeLeft: Double get() = maxOf(0.0, ROUND - elapsed - penalty)
    val isOver: Boolean get() = elapsed + penalty >= ROUND
    /** 0 at the start, 1 at the end: the bubbles come faster, rise faster and shrink. */
    val difficulty: Double get() = ((elapsed + penalty) / ROUND).coerceIn(0.0, 1.0)
    val spawnInterval: Double get() = (1.0 - 0.65 * difficulty) / pace
    /** Dp per second a new bubble rises at, before its own variation. */
    val riseSpeed: Double get() = (44 + 76 * difficulty) * pace
    /** The sizes new bubbles come in now: they shrink by a third over the round. */
    val radiusRange: ClosedFloatingPointRange<Double>
        get() {
            val k = 1 - 0.35 * difficulty
            return (11 * k)..(28 * k)
        }
    val blotShare: Double get() = tuning.blotsAtStart + (tuning.blotsAtEnd - tuning.blotsAtStart) * difficulty

    /** Moves everything on by [dt] seconds (at most [MAX_STEP]); nothing moves once the round is over. */
    fun advance(dt: Double) {
        if (isOver || dt <= 0) return
        val step = min(min(dt, MAX_STEP), ROUND - elapsed - penalty)
        elapsed += step
        for (b in _bubbles) {
            b.age += step
            b.y -= b.speed * step
            b.x = b.home + b.sway * sin(b.phase + b.age * 1.7)
        }
        val lost = _bubbles.count { it.y + it.radius < 0 && it.kind == Bubble.Kind.INK }
        if (lost > 0) {
            escaped += lost
            combo = 1
        }
        _bubbles.removeAll { it.y + it.radius < 0 }
        for (s in _splashes) s.age += step
        _splashes.removeAll { it.done }
        untilSpawn -= step
        while (untilSpawn <= 0) {
            spawn()
            untilSpawn += spawnInterval
        }
    }

    /**
     * A touch at ([x], [y]): the nearest bubble under it pops and scores (times the row's
     * multiplier); a blot costs; nothing under it breaks the row.
     */
    fun pop(x: Double, y: Double): PopResult {
        if (isOver) return PopResult.Miss
        fun distance(b: Bubble): Double {
            val dx = b.x - x
            val dy = b.y - y
            return sqrt(dx * dx + dy * dy)
        }
        val i = _bubbles.indices.filter { distance(_bubbles[it]) <= _bubbles[it].radius + tuning.reach }.minByOrNull { distance(_bubbles[it]) }
        if (i == null) {
            combo = 1
            return PopResult.Miss
        }
        val bubble = _bubbles.removeAt(i)
        _splashes.add(Splash(bubble.x, bubble.y, bubble.radius, bubble.hue, blot = bubble.kind == Bubble.Kind.BLOT))
        return when (bubble.kind) {
            Bubble.Kind.BLOT -> {
                score = maxOf(0, score - BLOT_POINTS)
                penalty += BLOT_SECONDS
                blotsHit += 1
                combo = 1
                lastPop = -10.0
                PopResult.Blot(BLOT_POINTS, BLOT_SECONDS)
            }
            Bubble.Kind.INK -> {
                combo = if (elapsed - lastPop <= COMBO_WINDOW) min(MAX_COMBO, combo + 1) else 1
                lastPop = elapsed
                val points = bubble.worth * combo
                score += points
                popped += 1
                PopResult.Popped(points, combo)
            }
        }
    }

    private fun spawn() {
        val blot = rng.nextDouble(0.0, 1.0) < blotShare
        val range = radiusRange
        val radius = if (blot) rng.nextDoubleClosed(13.0, 21.0) else rng.nextDoubleClosed(range.start, range.endInclusive)
        val margin = radius + 6
        val home = if (width > 2 * margin) rng.nextDoubleClosed(margin, width - margin) else width / 2
        val speed = riseSpeed * rng.nextDoubleClosed(0.8, 1.25) * sqrt(20 / radius)
        val hue = if (blot) 0.64 else rng.nextDoubleClosed(0.52, 0.72)
        val sway = rng.nextDoubleClosed(4.0, 12.0)
        val phase = rng.nextDoubleClosed(0.0, 2 * Math.PI)
        _bubbles.add(
            Bubble(
                id = nextId, kind = if (blot) Bubble.Kind.BLOT else Bubble.Kind.INK, home = home, x = home, y = height + radius,
                radius = radius, speed = speed, sway = sway, phase = phase, hue = hue,
            ),
        )
        nextId += 1
    }

    /** The same field at the same moment, to be stepped on its own. */
    fun copy(): BubbleField = BubbleField(width, height, tuning, rng.copy()).also { f ->
        f._bubbles.addAll(_bubbles.map { it.copy() })
        f._splashes.addAll(_splashes.map { it.copy() })
        f.score = score
        f.popped = popped
        f.blotsHit = blotsHit
        f.escaped = escaped
        f.combo = combo
        f.elapsed = elapsed
        f.penalty = penalty
        f.lastPop = lastPop
        f.untilSpawn = untilSpawn
        f.nextId = nextId
    }

    private fun state(): List<Any> = listOf(
        width, height, tuning, rng, _bubbles, _splashes, score, popped, blotsHit, escaped, combo, elapsed, penalty, lastPop, untilSpawn, nextId,
    )

    override fun equals(other: Any?): Boolean = other is BubbleField && other.state() == state()

    override fun hashCode(): Int = state().hashCode()

    companion object {
        const val ROUND = 60.0
        /** One step never jumps further than this, whatever the clock says (a pause, a slow frame). */
        const val MAX_STEP = 0.1
        /** Pops within this many seconds of each other are a row; a row multiplies the points, up to [MAX_COMBO]. */
        const val COMBO_WINDOW = 0.9
        const val MAX_COMBO = 4
        /** A touched blot: points off the score and seconds off the clock. */
        const val BLOT_POINTS = 5
        const val BLOT_SECONDS = 3

        fun pace(difficulty: GameDifficulty): Double = Tuning.of(difficulty).pace
    }
}
