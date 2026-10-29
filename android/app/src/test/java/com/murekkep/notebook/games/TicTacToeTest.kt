package com.murekkep.notebook.games

import com.murekkep.notebook.games.TicTacToe.Mark
import com.murekkep.notebook.games.TicTacToe.Outcome
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

// XOX against the device: tools/gamescheck's checks of the iPad's TicTacToe, and whole games a seed
// gives on the iPad (printed by its MiniGameLogic.swift).
class TicTacToeTest {
    private fun played(moves: List<Int>, first: Mark = Mark.X) = TicTacToe(first).apply { moves.forEach { play(it) } }

    @Test
    fun movesInTurnAndALineWins() {
        val board = TicTacToe()
        assertTrue(board.turn == Mark.X && board.outcome == null && board.free.size == 9)
        assertTrue(board.play(4) && board.cells[4] == Mark.X && board.turn == Mark.O)
        assertTrue("a taken cell is refused", !board.play(4) && board.turn == Mark.O)
        assertTrue("cells outside the board are refused", !board.play(9) && !board.play(-1))
        assertTrue(board.play(0) && board.play(1) && board.play(8) && board.play(7))
        assertEquals(Outcome.Won(Mark.X, listOf(1, 4, 7)), board.outcome)
        assertTrue("no move after the end", board.isOver && !board.play(2))
        assertEquals(Outcome.Won(Mark.X, listOf(0, 1, 2)), played(listOf(0, 3, 1, 4, 2)).outcome)
        assertEquals(Outcome.Won(Mark.O, listOf(2, 4, 6)), played(listOf(0, 4, 1, 2, 3, 6)).outcome)
        assertEquals(Outcome.Draw, played(listOf(0, 1, 2, 4, 3, 5, 7, 6, 8)).outcome)
        assertNull("one cell left, no result yet", played(listOf(0, 1, 2, 4, 3, 5, 7, 6)).outcome)
        assertEquals(Mark.O, played(emptyList(), first = Mark.O).turn)
    }

    @Test
    fun theDeviceWinsBlocksAndTakesTheCentreOrACorner() {
        val rng = GameRandom(11uL)
        assertTrue(played(listOf(0, 3, 1)).winningCell(Mark.X) == 2 && played(listOf(0, 3, 1)).winningCell(Mark.O) == null)
        assertEquals("a win, whatever its whim", 2, played(listOf(0, 3, 1, 4)).bestMove(Mark.X, rng, whim = 1.0))
        assertEquals("a block, whatever its whim", 2, played(listOf(0, 3, 1)).bestMove(Mark.O, rng, whim = 1.0))
        assertEquals("a block before anything else", 5, played(listOf(0, 2, 4, 8, 3)).bestMove(Mark.O, rng, whim = 1.0))
        assertEquals("the centre when it is free", 4, played(listOf(0)).bestMove(Mark.O, rng, whim = 0.0))
        assertTrue(played(listOf(4)).bestMove(Mark.O, rng, whim = 0.0) in TicTacToe.CORNERS)
        assertTrue("a fork is still answered with a block", played(listOf(0, 4, 8, 2, 6)).bestMove(Mark.O, rng, whim = 0.0) in listOf(3, 7))
        assertEquals("with the centre and the corners gone, O takes its row", 5, played(listOf(0, 4, 2, 1, 6, 3, 8)).bestMove(Mark.O, rng, whim = 0.0))
        assertNull(played(listOf(0, 1, 2, 4, 3, 5, 7, 6, 8)).bestMove(Mark.X, rng))
        val whimsy = mutableSetOf<Int>()
        repeat(40) { played(listOf(0)).bestMove(Mark.O, rng, whim = 0.5)?.let { whimsy.add(it) } }
        assertTrue("a little whim varies the reply, always to a free cell: $whimsy", 4 in whimsy && whimsy.size > 1 && 0 !in whimsy)
    }

    @Test
    fun ortaCanBeBeatenByTheCornerTrap() {
        val rng = GameRandom(11uL)
        val trap = TicTacToe()
        trap.play(0)
        assertEquals(4, trap.bestMove(Mark.O, rng, whim = 0.0))
        trap.play(4)
        trap.play(8)
        val reply = trap.bestMove(Mark.O, rng, whim = 0.0)!!
        assertTrue(reply in TicTacToe.CORNERS)
        trap.play(reply)
        trap.play(trap.bestMove(Mark.X, rng, whim = 0.0)!!)
        assertNull("X blocks", trap.outcome)
        trap.play(trap.bestMove(Mark.O, rng, whim = 0.0)!!)
        trap.play(trap.bestMove(Mark.X, rng, whim = 0.0)!!)
        assertTrue("X wins, so the device can be beaten", (trap.outcome as? Outcome.Won)?.mark == Mark.X)
    }

    @Test
    fun againstItselfEveryGameEnds() {
        var ended = 0
        var draws = 0
        for (seed in 1..200) {
            val r = GameRandom(seed.toULong())
            val g = TicTacToe(if (seed % 2 == 0) Mark.X else Mark.O)
            var moves = 0
            while (!g.isOver && moves < 9) {
                val m = g.bestMove(g.turn, r, whim = 0.3) ?: break
                if (!g.play(m)) break
                moves += 1
            }
            if (g.isOver) ended += 1
            if (g.outcome == Outcome.Draw) draws += 1
        }
        assertEquals(200, ended)
        assertTrue("$draws draws", draws in 21..199)
    }

    @Test
    fun zorPlaysPerfectlyAndNeverLoses() {
        assertEquals(9, TicTacToe().perfectMoves(Mark.X).size)
        assertEquals("against two corners only an edge holds the draw", listOf(1, 3, 5, 7), played(listOf(0, 4, 8)).perfectMoves(Mark.O).sorted())
        assertEquals("the block comes first", listOf(6), played(listOf(0, 4, 8, 2)).perfectMoves(Mark.X))
        assertEquals("a win is taken at once", listOf(2), played(listOf(0, 4, 1)).perfectMoves(Mark.O))
        var lost = 0
        var won = 0
        for (seed in 1..300) {
            val r = GameRandom(seed.toULong())
            val device = if (seed % 2 == 0) Mark.O else Mark.X
            val g = TicTacToe(Mark.X)
            while (!g.isOver) {
                g.play(if (g.turn == device) g.move(device, GameDifficulty.HARD, r)!! else r.element(g.free)!!)
            }
            val winner = (g.outcome as? Outcome.Won)?.mark
            if (winner == device) won += 1 else if (winner != null) lost += 1
        }
        assertTrue("$lost lost, $won won of 300", lost == 0 && won > 100)
    }

    @Test
    fun kolayWandersAndOrtaIsTheHeuristic() {
        var kolayLost = 0
        for (seed in 1..300) {
            val r = GameRandom(seed.toULong() * 7uL)
            val g = TicTacToe(if (seed % 2 == 0) Mark.X else Mark.O)
            while (!g.isOver) {
                g.play(if (g.turn == Mark.O) g.move(Mark.O, GameDifficulty.EASY, r)!! else g.move(Mark.X, GameDifficulty.MEDIUM, r)!!)
            }
            if ((g.outcome as? Outcome.Won)?.mark == Mark.X) kolayLost += 1
        }
        assertTrue("$kolayLost of 300", kolayLost > 60)
        val rng = GameRandom(11uL)
        assertEquals(2, played(listOf(0, 3, 1)).move(Mark.O, GameDifficulty.MEDIUM, rng))
        val easyMoves = mutableSetOf<Int>()
        repeat(60) { played(listOf(0, 3, 1)).move(Mark.O, GameDifficulty.EASY, rng)?.let { easyMoves.add(it) } }
        assertTrue("sometimes blocks, often wanders: $easyMoves", easyMoves.size > 3 && 2 in easyMoves)
        assertNull("no move on a finished board", played(listOf(0, 1, 2, 4, 3, 5, 7, 6, 8)).move(Mark.O, GameDifficulty.HARD, rng))
    }

    @Test
    fun aSeedPlaysTheIpadsGames() {
        val expected = mapOf(
            1 to "4,6,2,3,0,8,1", 2 to "5,4,6,8,1,0", 3 to "6,4,1,5,3,8,0", 4 to "3,4,8,2,5,6", 5 to "3,7,4,0,5",
            6 to "6,0,1,7,2,3,8,5,4", 7 to "4,0,6,3,2", 8 to "5,4,6,7,0,1", 9 to "6,2,1,0,8,3,5,4,7",
        )
        val difficulties = listOf(GameDifficulty.EASY, GameDifficulty.MEDIUM, GameDifficulty.HARD)
        for ((seed, moves) in expected) {
            val r = GameRandom(seed.toULong())
            val g = TicTacToe(if (seed % 2 == 0) Mark.X else Mark.O)
            val sequence = mutableListOf<Int>()
            while (!g.isOver) {
                val m = if (g.turn == Mark.O) g.move(Mark.O, difficulties[seed % 3], r)!! else r.element(g.free)!!
                g.play(m)
                sequence.add(m)
            }
            assertEquals("seed $seed", moves, sequence.joinToString(","))
        }
        val whim = GameRandom(31uL)
        assertEquals("4,4,4,5,4,5,7,3,4,3,4,3", List(12) { played(listOf(0)).bestMove(Mark.O, whim, whim = 0.5) }.joinToString(","))
    }
}
