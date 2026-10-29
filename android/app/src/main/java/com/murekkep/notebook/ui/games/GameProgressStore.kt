package com.murekkep.notebook.ui.games

import android.content.Context
import android.content.SharedPreferences
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.res.stringResource
import com.murekkep.notebook.R
import com.murekkep.notebook.games.GameDifficulty
import com.murekkep.notebook.games.GameProgress

/**
 * What the player keeps of every game, read from and written to the preferences under the iPad's
 * keys (GameProgressStore in GameCorner.swift): the chosen difficulty and the best score, wins or
 * time at each difficulty, and the layer last open. Compose state, so every tile and header follows.
 */
internal class GameProgressStore(internal val prefs: SharedPreferences) {
    constructor(context: Context) : this(context.applicationContext.getSharedPreferences("games", Context.MODE_PRIVATE))

    private val progress = mutableStateMapOf<MiniGame, GameProgress>()

    init {
        for (game in MiniGame.entries) progress[game] = load(game)
    }

    operator fun get(game: MiniGame): GameProgress = progress[game] ?: GameProgress()

    fun setDifficulty(difficulty: GameDifficulty, game: MiniGame) {
        val kept = this[game]
        if (kept.difficulty == difficulty) return
        progress[game] = kept.copy(difficulty = difficulty)
        prefs.edit().putString(GameProgress.Keys.difficulty(game.id), difficulty.raw).apply()
    }

    /** A round played to its end; true when it is a record. */
    fun record(game: MiniGame, score: Int, difficulty: GameDifficulty, lowerIsBetter: Boolean = false): Boolean {
        val recorded = this[game].record(score, difficulty, lowerIsBetter)
        progress[game] = recorded.progress
        if (recorded.isBest) prefs.edit().putInt(GameProgress.Keys.best(game.id, difficulty), score).apply()
        return recorded.isBest
    }

    /** The layer last open; games the first time, as the corner's tile is a game controller. */
    var layer: BreakLayer by mutableStateOf(BreakLayer.fromRaw(prefs.getString(GameProgress.Keys.LAYER, null)))
        private set

    fun pickLayer(picked: BreakLayer) {
        layer = picked
        prefs.edit().putString(GameProgress.Keys.LAYER, picked.raw).apply()
    }

    private fun load(game: MiniGame): GameProgress {
        val best = GameDifficulty.entries.mapNotNull { difficulty ->
            val key = GameProgress.Keys.best(game.id, difficulty)
            if (prefs.contains(key)) difficulty to prefs.getInt(key, 0) else null
        }.toMap()
        val difficulty = GameDifficulty.fromRaw(prefs.getString(GameProgress.Keys.difficulty(game.id), null)) ?: GameDifficulty.MEDIUM
        return GameProgress(best = best, difficulty = difficulty)
    }
}

/** One line about a game for its tile and the panel's header: its best, its wins, its time, at the difficulty chosen. */
@Composable
internal fun summary(game: MiniGame, kept: GameProgress): String {
    val level = stringResource(kept.difficulty.titleRes)
    val best = kept.best[kept.difficulty]
    return when (game) {
        MiniGame.BUBBLES -> stringResource(R.string.games_best, best ?: 0) + " · " + level
        MiniGame.XOX, MiniGame.DOTS -> stringResource(R.string.games_wins, best ?: 0) + " · " + level
        MiniGame.SUDOKU -> if (best != null) stringResource(R.string.games_best_time, clock(best)) + " · " + level else level
    }
}
