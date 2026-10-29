package com.murekkep.notebook.games

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

// What a player keeps of each game and the panel's two sizes: tools/gamescheck's checks of the
// iPad's GameProgress and GamePanelSize.
class GameProgressTest {
    @Test
    fun levelsOpenAndStarsStayTheBestTheyWere() {
        var p = GameProgress()
        assertTrue(p.unlockedLevel == 1 && p.isUnlocked(1) && !p.isUnlocked(2) && p.difficulty == GameDifficulty.MEDIUM)
        p = p.complete(level = 1, earned = 2, levels = 12)
        assertTrue("a finished level opens the next", p.unlockedLevel == 2 && p.starsAt(1) == 2 && p.totalStars == 2)
        p = p.complete(level = 1, earned = 1, levels = 12)
        assertEquals("stars never go down", 2, p.starsAt(1))
        p = p.complete(level = 1, earned = 3, levels = 12)
        assertTrue("better stars are kept", p.starsAt(1) == 3 && p.unlockedLevel == 2)
        p = p.complete(level = 2, earned = 0, levels = 12)
        assertTrue("a failed level opens nothing", p.unlockedLevel == 2 && p.starsAt(2) == 0)
        p = p.complete(level = 12, earned = 5, levels = 12)
        assertTrue("the last level stays last, stars stop at three", p.unlockedLevel == 12 && p.starsAt(12) == 3)
    }

    @Test
    fun aRecordIsAHigherScoreOrAShorterTime() {
        var p = GameProgress()
        fun record(score: Int, difficulty: GameDifficulty, lowerIsBetter: Boolean = false): Boolean {
            val r = p.record(score, difficulty, lowerIsBetter)
            p = r.progress
            return r.isBest
        }
        assertFalse("a first score of nothing is no record", record(0, GameDifficulty.MEDIUM))
        assertEquals(0, p.best[GameDifficulty.MEDIUM])
        assertTrue(record(12, GameDifficulty.MEDIUM) && !record(12, GameDifficulty.MEDIUM) && record(13, GameDifficulty.MEDIUM))
        assertTrue(
            record(300, GameDifficulty.HARD, lowerIsBetter = true) && record(250, GameDifficulty.HARD, lowerIsBetter = true) &&
                !record(260, GameDifficulty.HARD, lowerIsBetter = true) && p.best[GameDifficulty.HARD] == 250,
        )
        assertNull("each difficulty has its own best", p.best[GameDifficulty.EASY])
    }

    @Test
    fun theKeysAreTheIpads() {
        assertEquals("break.flyer.unlocked", GameProgress.Keys.unlocked("flyer"))
        assertEquals("break.shooter.stars", GameProgress.Keys.stars("shooter"))
        assertEquals("break.bubbles.best.hard", GameProgress.Keys.best("bubbles", GameDifficulty.HARD))
        assertEquals("break.xox.difficulty", GameProgress.Keys.difficulty("xox"))
        assertEquals("break.sudoku.saved", GameProgress.Keys.saved("sudoku"))
        assertEquals("break.layer", GameProgress.Keys.LAYER)
        assertEquals(GameDifficulty.HARD, GameDifficulty.fromRaw("hard"))
        assertNull(GameDifficulty.fromRaw("expert"))
    }

    @Test
    fun theLargerStepIsAtMostAQuarterOfTheCanvas() {
        assertEquals(PanelSize(340.0, 420.0), GamePanelSize.compact)
        assertEquals(PanelSize(400.0, 500.0), GamePanelSize.larger)
        // The iPad's numbers (its GamePanelSize printed for these canvases): 400x500, 388x486, 382x462.
        assertEquals(PanelSize(400.0, 500.0), GamePanelSize.larger(1180.0, 760.0, 72.0, 12.0, 12.0, 104.0))
        val tight = GamePanelSize.larger(1080.0, 700.0, 72.0, 12.0, 12.0, 104.0)
        assertEquals(PanelSize(388.0, 486.0), tight)
        assertTrue(tight.width * tight.height <= 1080.0 * 700 / 4 + 1)
        assertEquals("the larger step keeps its shape", 0.8, tight.width / tight.height, 0.01)
        val low = GamePanelSize.larger(1180.0, 600.0, 72.0, 12.0, 12.0, 104.0)
        assertEquals(PanelSize(382.0, 462.0), low)
        assertEquals("a quarter less than compact stays compact", GamePanelSize.compact, GamePanelSize.larger(700.0, 600.0, 72.0, 12.0, 12.0, 104.0))
        assertEquals("a narrow window stays compact", GamePanelSize.compact, GamePanelSize.larger(320.0, 900.0, 12.0, 12.0, 12.0, 104.0))
    }

    @Test
    fun aSmallWindowCutsThePanelToItsRoom() {
        assertEquals(GamePanelSize.compact, GamePanelSize.fitted(GamePanelSize.compact, 1000.0, 1000.0))
        assertEquals(PanelSize(336.0, 420.0), GamePanelSize.fitted(GamePanelSize.compact, 336.4, 600.0))
        assertEquals(PanelSize(340.0, 250.0), GamePanelSize.fitted(GamePanelSize.compact, 700.0, 250.0))
        assertEquals(PanelSize(0.0, 0.0), GamePanelSize.fitted(GamePanelSize.compact, -10.0, -1.0))
    }
}
