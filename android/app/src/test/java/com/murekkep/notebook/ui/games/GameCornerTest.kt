package com.murekkep.notebook.ui.games

import android.content.Context
import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.layout.FirstBaseline
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.SemanticsNodeInteraction
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.click
import androidx.compose.ui.test.getAlignmentLinePosition
import androidx.compose.ui.test.getBoundsInRoot
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.isDialog
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.murekkep.notebook.games.GameDifficulty
import com.murekkep.notebook.games.GameProgress
import com.murekkep.notebook.games.Sudoku
import com.murekkep.notebook.games.SudokuSave
import com.murekkep.notebook.ui.MurekkepTheme
import com.murekkep.notebook.ui.PaletteEdge
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.ConscryptMode
import kotlin.math.roundToInt

// The break corner in a 1280 x 800 dp canvas with the pen bar along the bottom: the tile opens the
// compact card with the four games Android has (no sheet, no second window), one step larger on
// request, the games play and keep what they should, and their clocks stop when the card closes or
// the app goes to the background.
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], qualifiers = "w1280dp-h800dp")
// Conscrypt's native library is looked up by a name lower-cased in the machine's language, which a
// Turkish JVM spells "wındows": the screen needs no TLS, so the test runs without it.
@ConscryptMode(ConscryptMode.Mode.OFF)
class GameCornerTest {
    @get:Rule
    val compose = createAndroidComposeRule<ComponentActivity>()

    private val prefs get() = compose.activity.getSharedPreferences("games", Context.MODE_PRIVATE)

    private val tiles = listOf(
        "Ink bubbles. Pop the bubbles, leave the blots. 60 seconds.",
        "Tic-tac-toe. Against the device; you are X.",
        "Dots and boxes. Join the dots; whoever closes a box takes it and goes again.",
        "Sudoku. 1–9 in every row, column and box.",
    )

    @Before
    fun freshProgress() {
        prefs.edit().clear().commit()
    }

    /** The lasso's bar showing in the editor. */
    private var selecting by mutableStateOf(false)

    private fun show(width: Dp = 1280.dp, height: Dp = 800.dp) {
        compose.setContent {
            MurekkepTheme {
                Box(Modifier.size(width, height)) { BreakCorner(PaletteEdge.BOTTOM, 90.dp, width, height, selectionBar = selecting) }
            }
        }
    }

    private fun openGame(tile: String? = null) {
        compose.onNodeWithContentDescription("Break: small games").performClick()
        if (tile != null) compose.onNodeWithContentDescription(tile).performClick()
    }

    private fun state(text: String) = SemanticsMatcher.expectValue(SemanticsProperties.StateDescription, text)

    private val panel get() = compose.onNode(SemanticsMatcher.keyIsDefined(SemanticsProperties.PaneTitle))

    @Test
    fun theTileOpensTheBreakWithTheGamesAndClosesIt() {
        show()
        openGame()
        compose.onNodeWithText("Break").assertIsDisplayed()
        compose.onNodeWithText("A short break; with the pen or a finger.").assertIsDisplayed()
        for (tile in tiles) compose.onNodeWithContentDescription(tile).assertIsDisplayed()
        // Only the games Android has: no layer picker, nothing to make; no sheet, no dialog.
        compose.onAllNodes(hasText("Create")).assertCountEquals(0)
        compose.onAllNodes(isDialog()).assertCountEquals(0)
        compose.onNodeWithContentDescription("Close the break").performClick()
        compose.onAllNodes(hasText("Break")).assertCountEquals(0)
        compose.onNodeWithContentDescription("Break: small games").assertIsDisplayed()
    }

    @Test
    fun thePanelIsCompactAndOneStepLargerAndCloses() {
        show()
        openGame()
        fun size() = panel.getBoundsInRoot().let { (it.right - it.left).value.roundToInt() to (it.bottom - it.top).value.roundToInt() }
        assertEquals(340 to 420, size())
        compose.onNodeWithContentDescription("Enlarge").performClick()
        assertEquals("at most 400 x 500 and a quarter of the canvas", 400 to 500, size())
        compose.onNodeWithContentDescription("Shrink").performClick()
        assertEquals(340 to 420, size())
        compose.onNodeWithContentDescription("Close").performClick()
        panel.assertDoesNotExist()
    }

    @Test
    fun onAShortCanvasTheCardComesDownOverItsTileButNeverOverThePenBar() {
        // A phone on its side, the pen bar along the bottom (18 + 64 + 8): no room for the card over
        // its tile, so it comes down over the tile, 12 over the bar, and is cut to the room up to the top.
        show(800.dp, 330.dp)
        openGame()
        val card = panel.getBoundsInRoot()
        assertEquals(12f, card.top.value, 0.5f)
        assertEquals(330f - 90f - 12f, card.bottom.value, 0.5f)
        // Nor over the lasso's bar while it shows: cut to the room above that.
        selecting = true
        compose.waitForIdle()
        assertEquals(12f, panel.getBoundsInRoot().top.value, 0.5f)
        assertEquals(330f - 90f - 116f, panel.getBoundsInRoot().bottom.value, 0.5f)
    }

    @Test
    fun theCardStandsOverTheLassosBarWhileItShows() {
        // A phone upright, the pen bar along the bottom. The lasso's bar stands 52 over the bar's room
        // and is 56 tall, and the card over its tile (58 up) would hide most of it: while it shows the
        // card rises to 8 over it, as the iPad's panel clears its bar's buttons, and comes down after.
        show(411.dp, 760.dp)
        openGame()
        fun card() = panel.getBoundsInRoot()
        assertEquals(760f - 90f - 58f, card().bottom.value, 0.5f)
        selecting = true
        compose.waitForIdle()
        assertEquals(760f - 90f - 116f, card().bottom.value, 0.5f)
        assertEquals("the compact card whole", 420f, (card().bottom - card().top).value, 0.5f)
        selecting = false
        compose.waitForIdle()
        assertEquals(760f - 90f - 58f, card().bottom.value, 0.5f)
    }

    @Test
    fun aTileOpensItsGameAndBackLeavesIt() {
        show()
        openGame(tiles[3])
        compose.onNodeWithText("Sudoku").assertIsDisplayed()
        compose.onNodeWithText("New puzzle").assertIsDisplayed()
        compose.onNodeWithContentDescription("Restart").assertIsDisplayed()
        compose.onNodeWithContentDescription("Back to the games").performClick()
        compose.onNodeWithText("A short break; with the pen or a finger.").assertIsDisplayed()
        // Back leaves a game first, then closes the card.
        compose.onNodeWithContentDescription(tiles[1]).performClick()
        compose.runOnUiThread { compose.activity.onBackPressedDispatcher.onBackPressed() }
        compose.onNodeWithContentDescription(tiles[1]).assertIsDisplayed()
        compose.runOnUiThread { compose.activity.onBackPressedDispatcher.onBackPressed() }
        panel.assertDoesNotExist()
    }

    @Test
    fun aDifficultyIsKeptAndShownOnTheGamesLine() {
        show()
        openGame(tiles[1])
        compose.onNodeWithText("Hard").performClick()
        compose.onNodeWithText("Wins: 0 · Hard").assertIsDisplayed()
        compose.onNodeWithText("Hard: the device makes no mistakes; a draw is a win.").assertIsDisplayed()
        assertEquals("hard", prefs.getString("break.xox.difficulty", null))
    }

    @Test
    fun xoxTheDeviceAnswersAfterAMoment() {
        show()
        openGame(tiles[1])
        val board = compose.onNodeWithContentDescription("Tic-tac-toe board")
        board.assert(state("Your turn: draw an X."))
        board.performTouchInput { click(Offset(width / 6f, height / 6f)) }
        board.assert(state("The device is thinking…"))
        compose.mainClock.advanceTimeBy(600)
        board.assert(state("Your turn: draw an X."))
    }

    @Test
    fun karekapmacaTheDeviceAnswersALine() {
        show()
        openGame(tiles[2])
        val board = compose.onNodeWithContentDescription("Dots and boxes board")
        board.assert(state("Your turn: draw a line."))
        // Between the first two dots of the top row (Orta: 4 x 4 boxes).
        board.performTouchInput {
            val inset = width * 0.09f
            val step = (width - 2 * inset) / 4
            click(Offset(inset + step / 2, inset))
        }
        board.assert(state("The device is thinking…"))
        compose.mainClock.advanceTimeBy(500)
        // The device's line is worked out off the main thread.
        compose.waitUntil(5_000) { compose.onAllNodes(state("Your turn: draw a line.")).fetchSemanticsNodes().isNotEmpty() }
        board.assert(state("Your turn: draw a line."))
    }

    /** A medium puzzle with its last empty cell left: (cell, digit). */
    private fun nearlySolved(elapsed: Int): Pair<Int, Int> {
        val puzzle = Sudoku.generate(GameDifficulty.MEDIUM, 2uL)
        val last = puzzle.givens.indexOfFirst { it == 0 }
        val entries = puzzle.solution.toMutableList().apply { this[last] = 0 }
        val save = SudokuSave(GameDifficulty.MEDIUM, puzzle.givens, puzzle.solution, entries, emptyMap(), elapsed)
        prefs.edit().putString(GameProgress.Keys.saved("sudoku"), save.encoded()).commit()
        return last to puzzle.solution[last]
    }

    @Test
    fun theSudokuClockIsTextThatRunsOnlyWhileThePuzzleIsOnScreen() {
        nearlySolved(elapsed = 0)
        show()
        openGame(tiles[3])
        compose.onNodeWithText("0:00").assertIsDisplayed()
        compose.mainClock.autoAdvance = false
        compose.mainClock.advanceTimeBy(2_000)
        compose.onNodeWithText("0:02").assertIsDisplayed()
        compose.mainClock.autoAdvance = true
        compose.onNodeWithContentDescription("Close the break").performClick()
        compose.waitForIdle()
        val kept = SudokuSave.decode(prefs.getString(GameProgress.Keys.saved("sudoku"), null))!!.elapsed
        compose.mainClock.advanceTimeBy(10_000)
        assertEquals("the closed card's clock stands still", kept, SudokuSave.decode(prefs.getString(GameProgress.Keys.saved("sudoku"), null))!!.elapsed)
        openGame(tiles[3])
        compose.onNodeWithText(clock(kept)).assertIsDisplayed()
    }

    @Test
    fun theClockStopsWithTheAppItselfWithoutWaitingForAFrame() {
        // A screen switched off at once gives no frame between pausing and stopping, so the clock may
        // not wait for a recomposition to stop: nothing here reads the lifecycle's state, and still
        // the seconds behind another app count for nothing.
        var ticks = 0
        compose.setContent {
            val lifecycle = LocalLifecycleOwner.current.lifecycle
            LaunchedEffect(lifecycle) { tickWhileInFront(lifecycle) { ticks += 1 } }
        }
        compose.mainClock.autoAdvance = false
        compose.mainClock.advanceTimeBy(2_000)
        assertEquals(2, ticks)
        compose.activityRule.scenario.moveToState(Lifecycle.State.STARTED)
        compose.mainClock.advanceTimeBy(5_000)
        assertEquals("behind another app the clock stands", 2, ticks)
        compose.activityRule.scenario.moveToState(Lifecycle.State.RESUMED)
        compose.mainClock.advanceTimeBy(1_000)
        assertEquals(3, ticks)
    }

    @Test
    fun aSolvedSudokuIsTimedAndItsBestKept() {
        val (cell, digit) = nearlySolved(elapsed = 75)
        show()
        openGame(tiles[3])
        compose.onNodeWithContentDescription("Sudoku board").performTouchInput {
            click(Offset((Sudoku.col(cell) + 0.5f) * width / 9, (Sudoku.row(cell) + 0.5f) * height / 9))
        }
        compose.onNodeWithContentDescription("Digit $digit").performClick()
        compose.onNodeWithText("Solved!").assertIsDisplayed()
        compose.onNodeWithText("Time: 1:15").assertIsDisplayed()
        compose.onNodeWithText("New best!").assertIsDisplayed()
        compose.onNodeWithText("Best time: 1:15 · Medium").assertIsDisplayed()
        assertEquals(75, prefs.getInt(GameProgress.Keys.best("sudoku", GameDifficulty.MEDIUM), 0))
    }

    @Test
    fun theBubblesRunWhileTheAppIsInFrontAndStopBehindIt() {
        show()
        openGame()
        compose.onNodeWithContentDescription(tiles[0]).assertIsDisplayed()
        // The field runs every frame, so the test steps the clock itself from the pick on.
        compose.mainClock.autoAdvance = false
        compose.onNodeWithContentDescription(tiles[0]).performSemanticsAction(SemanticsActions.OnClick)
        compose.waitForIdle()
        compose.mainClock.advanceTimeBy(2_500)
        compose.onNodeWithText("0:58").assertIsDisplayed()
        compose.onNodeWithText("Leave the blots").assertIsDisplayed()
        // Five seconds behind another app count for nothing: one more in front reads 0:57.
        compose.activityRule.scenario.moveToState(Lifecycle.State.STARTED)
        compose.mainClock.advanceTimeBy(5_000)
        compose.activityRule.scenario.moveToState(Lifecycle.State.RESUMED)
        compose.mainClock.advanceTimeBy(1_000)
        compose.onNodeWithText("0:57").assertExists()
    }

    @Test
    fun theBubblesClockStandsOnTheLineOfTheScoreAndTheBest() {
        // The iPad's header is an HStack on the first text baseline: the clock's digits stand on the
        // line of the score's and the best's numbers, not centred against their two lines.
        show()
        openGame()
        compose.waitForIdle()
        compose.mainClock.autoAdvance = false
        compose.onNodeWithContentDescription(tiles[0]).performSemanticsAction(SemanticsActions.OnClick)
        compose.waitForIdle()
        compose.mainClock.advanceTimeBy(1_000)
        fun baseline(node: SemanticsNodeInteraction) = (node.getBoundsInRoot().top + node.getAlignmentLinePosition(FirstBaseline)).value
        val clock = baseline(compose.onNode(hasContentDescription("seconds left", substring = true), useUnmergedTree = true))
        val numbers = compose.onAllNodesWithText("0", useUnmergedTree = true)
        numbers.assertCountEquals(2)
        assertEquals("the score", baseline(numbers[0]), clock, 0.5f)
        assertEquals("the best", baseline(numbers[1]), clock, 0.5f)
    }

    @Test
    fun theGamesKnowWhenTheAppIsBehindAnother() {
        val seen = mutableListOf<Boolean>()
        compose.setContent {
            val front = rememberAppInFront()
            SideEffect { seen.add(front) }
        }
        compose.waitForIdle()
        assertEquals(true, seen.last())
        compose.activityRule.scenario.moveToState(Lifecycle.State.STARTED)
        compose.mainClock.advanceTimeByFrame()
        assertEquals("paused: the clocks and the bubbles stop", false, seen.last())
        compose.activityRule.scenario.moveToState(Lifecycle.State.RESUMED)
        compose.waitForIdle()
        assertEquals(true, seen.last())
    }

    @Test
    fun theLevelMapOpensLevelsInTurn() {
        var started = 0
        compose.setContent {
            MurekkepTheme {
                LevelMap(12, GameProgress(unlockedLevel = 3, stars = mapOf(1 to 3, 2 to 1)), onDifficulty = {}, onStart = { started = it })
            }
        }
        compose.onNodeWithText("4 stars in all").assertIsDisplayed()
        compose.onNodeWithText("Level 3 open").assertIsDisplayed()
        compose.onNodeWithContentDescription("Level 4, locked").assertIsNotEnabled()
        compose.onNodeWithContentDescription("Level 2").performClick()
        assertEquals(2, started)
    }
}
