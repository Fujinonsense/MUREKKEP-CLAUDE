package com.murekkep.notebook.games

import kotlin.math.floor
import kotlin.math.min
import kotlin.math.sqrt

/** Kolay, Orta, Zor: each game reads it its own way. [raw] is the iPad's stored value. */
enum class GameDifficulty(val raw: String) {
    EASY("easy"),
    MEDIUM("medium"),
    HARD("hard");

    companion object {
        fun fromRaw(raw: String?): GameDifficulty? = entries.firstOrNull { it.raw == raw }
    }
}

/**
 * What a player keeps of one game: the levels opened, the stars of each, the best score at each
 * difficulty and the difficulty chosen (the iPad's GameProgress). Kept in the preferences under [Keys].
 */
data class GameProgress(
    val unlockedLevel: Int = 1,
    val stars: Map<Int, Int> = emptyMap(),
    val best: Map<GameDifficulty, Int> = emptyMap(),
    val difficulty: GameDifficulty = GameDifficulty.MEDIUM,
) {
    val totalStars: Int get() = stars.values.sum()

    fun starsAt(level: Int): Int = stars[level] ?: 0

    fun isUnlocked(level: Int): Boolean = level in 1..unlockedLevel

    /**
     * A level played to its end: its stars stay the best they ever were, and with any star at all
     * the next level opens (up to [levels]).
     */
    fun complete(level: Int, earned: Int, levels: Int): GameProgress {
        val got = earned.coerceIn(0, 3)
        val opened = if (got > 0) maxOf(unlockedLevel, min(levels, level + 1)) else unlockedLevel
        return copy(stars = stars + (level to maxOf(starsAt(level), got)), unlockedLevel = opened)
    }

    /**
     * A round played to its end: [Recorded.isBest] when [score] is the best so far at [difficulty]
     * (a first score of nothing is no record; a time is a record when it is shorter).
     */
    fun record(score: Int, difficulty: GameDifficulty, lowerIsBetter: Boolean = false): Recorded {
        val old = best[difficulty] ?: return Recorded(copy(best = best + (difficulty to score)), lowerIsBetter || score > 0)
        val better = if (lowerIsBetter) score < old else score > old
        return Recorded(if (better) copy(best = best + (difficulty to score)) else this, better)
    }

    data class Recorded(val progress: GameProgress, val isBest: Boolean)

    /** The preferences' keys, per game id ("bubbles", "sudoku"…): the iPad's UserDefaults keys. */
    object Keys {
        fun unlocked(game: String) = "break.$game.unlocked"
        fun stars(game: String) = "break.$game.stars"
        fun best(game: String, difficulty: GameDifficulty) = "break.$game.best.${difficulty.raw}"
        fun difficulty(game: String) = "break.$game.difficulty"
        /** A game left half-way (Sudoku), to go on with later. */
        fun saved(game: String) = "break.$game.saved"
        /** The break card's layer last open (games or things to make). */
        const val LAYER = "break.layer"
    }
}

/** A panel's size in dp. */
data class PanelSize(val width: Double, val height: Double)

/**
 * How big the break panel may be: compact, or one step larger that never takes more than a quarter
 * of the canvas, so the notebook stays in view and in reach beside it (the iPad's GamePanelSize).
 */
object GamePanelSize {
    val compact = PanelSize(340.0, 420.0)
    val larger = PanelSize(400.0, 500.0)

    /**
     * The larger step inside a canvas with the given room kept clear at each edge: at most
     * 400 x 500, at most a quarter of the canvas, never past its edges; the compact size when even
     * that would not fit.
     */
    fun larger(canvasWidth: Double, canvasHeight: Double, leading: Double, trailing: Double, top: Double, bottom: Double): PanelSize {
        var width = min(larger.width, canvasWidth - leading - trailing)
        var height = min(larger.height, canvasHeight - top - bottom)
        val quarter = canvasWidth * canvasHeight / 4
        if (width * height > quarter) {
            val k = sqrt(quarter / (width * height))
            width *= k
            height *= k
        }
        if (width < compact.width || height < compact.height) return compact
        return PanelSize(floor(width), floor(height))
    }

    /**
     * Where the panel's bottom stands, from the canvas's bottom edge: [aboveTile] (over the corner's
     * tile) while the compact panel fits between it and [top]; on a shorter window (a phone on its
     * side) it comes down to [low], over the tile, which it hides while it is open.
     */
    fun bottom(canvasHeight: Double, top: Double, aboveTile: Double, low: Double): Double =
        if (canvasHeight - top - aboveTile >= compact.height) aboveTile else low

    /**
     * Android's windows run smaller than any iPad's (a phone, a split screen): [size] cut down to
     * the room there is, so the panel never runs off the canvas. The iPad keeps the compact size.
     */
    fun fitted(size: PanelSize, roomWidth: Double, roomHeight: Double): PanelSize =
        PanelSize(floor(min(size.width, roomWidth.coerceAtLeast(0.0))), floor(min(size.height, roomHeight.coerceAtLeast(0.0))))
}
