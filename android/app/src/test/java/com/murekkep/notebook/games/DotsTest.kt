package com.murekkep.notebook.games

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

// Kare kapmaca: tools/gamescheck's checks of the iPad's DotsBoard and DotsAI, and whole games and
// tallies a seed gives on the iPad (printed by its DotsLogic.swift).
class DotsTest {
    private fun across(row: Int, col: Int) = DotsEdge(true, row, col)
    private fun down(row: Int, col: Int) = DotsEdge(false, row, col)
    private fun name(e: DotsEdge) = (if (e.horizontal) "h" else "v") + e.row + e.col

    @Test
    fun aBoardItsLinesAndItsBoxes() {
        val board = DotsBoard(3)
        assertTrue(board.edges.size == 24 && board.freeEdges.size == 24 && board.turn == DotsPlayer.YOU && !board.isOver)
        assertEquals(listOf(3, 4, 5), GameDifficulty.entries.map { DotsBoard.size(it) })
        assertEquals(listOf(1), board.boxesBeside(across(0, 1)))
        assertEquals(listOf(1, 4), board.boxesBeside(across(1, 1)))
        assertEquals(listOf(8), board.boxesBeside(down(2, 3)))
        assertTrue((0 until 9).all { box -> board.edgesOfBox(box).all { box in board.boxesBeside(it) } })
        assertEquals(emptyList<Int>(), board.draw(across(0, 0)))
        assertTrue("a line that closes nothing passes the turn; a line is drawn once", board.turn == DotsPlayer.DEVICE && board.draw(across(0, 0)) == null)
        board.draw(down(0, 0))
        board.draw(across(1, 0))
        assertTrue(board.closes(down(0, 1)) == 1 && !board.opens(down(2, 3)) && board.turn == DotsPlayer.DEVICE)
        assertEquals(listOf(0), board.draw(down(0, 1)))
        assertTrue("the box is the device's, and it draws again", board.owners[0] == DotsPlayer.DEVICE && board.turn == DotsPlayer.DEVICE && board.score(DotsPlayer.DEVICE) == 1)
    }

    @Test
    fun ortaTakesWhatItCanAndHandsOverNothingWhileItCan() {
        val rng = GameRandom(6uL)
        val greedy = DotsBoard(3).apply { listOf(across(0, 0), down(0, 0), across(1, 0)).forEach { draw(it) } }
        assertEquals(down(0, 1), DotsAI.move(greedy, GameDifficulty.MEDIUM, rng))
        val careful = DotsBoard(4)
        var neverGave = true
        var moves = 0
        while (!careful.isOver) {
            val move = DotsAI.move(careful, GameDifficulty.MEDIUM, rng) ?: break
            val couldTake = careful.freeEdges.any { careful.closes(it) > 0 }
            val hadSafe = careful.freeEdges.any { careful.closes(it) == 0 && !careful.opens(it) }
            if (!couldTake && hadSafe && careful.opens(move)) neverGave = false
            careful.draw(move)
            moves += 1
        }
        assertTrue(neverGave && careful.isOver && moves == 40 && careful.score(DotsPlayer.YOU) + careful.score(DotsPlayer.DEVICE) == 16)
        val giving = DotsBoard(2).apply {
            listOf(across(0, 0), across(0, 1), down(0, 0), down(0, 2), down(1, 0), down(1, 2), across(2, 0), across(2, 1)).forEach { draw(it) }
        }
        assertTrue(giving.freeEdges.size == 4 && giving.freeEdges.all { giving.opens(it) })
        assertEquals("one line here hands over all four boxes", 4, DotsAI.handedOver(down(0, 1), giving))
    }

    /** What a position is worth to the side to move, every set of lines searched (gamescheck's oracle). */
    private fun oracleValue(board: DotsBoard): Int {
        val edges = board.edges
        val index = edges.withIndex().associate { (i, e) -> e to i }
        val boxMasks = LongArray(board.size * board.size) { box -> board.edgesOfBox(box).fold(0L) { m, e -> m or (1L shl index.getValue(e)) } }
        val beside = edges.map { board.boxesBeside(it) }
        val full = (1L shl edges.size) - 1
        var drawn = 0L
        for ((i, e) in edges.withIndex()) if (e in board.lines) drawn = drawn or (1L shl i)
        val memo = HashMap<Long, Int>()
        fun value(mask: Long): Int {
            if (mask == full) return 0
            memo[mask]?.let { return it }
            var best = Int.MIN_VALUE
            for (i in edges.indices) {
                if (mask and (1L shl i) != 0L) continue
                val after = mask or (1L shl i)
                val gained = beside[i].count { after and boxMasks[it] == boxMasks[it] }
                best = maxOf(best, if (gained > 0) gained + value(after) else -value(after))
            }
            memo[mask] = best
            return best
        }
        return value(drawn)
    }

    @Test
    fun zorsLineIsTheBestLineInEveryEndgameTried() {
        var checked = 0
        var agrees = 0
        for (size in listOf(3, 4)) {
            for (seed in 1..12) {
                val board = DotsBoard(size)
                val random = GameRandom((seed * 7).toULong())
                while (board.freeEdges.size > 11 + seed % 5) {
                    board.draw(DotsAI.move(board, GameDifficulty.MEDIUM, random) ?: break)
                }
                if (board.isOver) continue
                val pick = DotsAI.best(board) ?: continue
                val after = board.copy()
                val gained = after.draw(pick)?.size ?: 0
                val rest = oracleValue(after)
                checked += 1
                if (gained + (if (after.turn == board.turn) rest else -rest) == oracleValue(board)) agrees += 1
            }
        }
        assertTrue("$agrees of $checked", checked >= 20 && agrees == checked)
        assertNull("a search past its budget gives way", DotsAI.best(DotsBoard(5), budget = 10))
    }

    private fun duel(size: Int, you: GameDifficulty, device: GameDifficulty, seed: ULong): Pair<DotsBoard, List<String>> {
        val board = DotsBoard(size, if (seed % 2uL == 0uL) DotsPlayer.YOU else DotsPlayer.DEVICE)
        val random = GameRandom(seed)
        val moves = mutableListOf<String>()
        while (!board.isOver) {
            val move = DotsAI.move(board, if (board.turn == DotsPlayer.YOU) you else device, random) ?: break
            board.draw(move)
            moves.add(name(move))
        }
        return board to moves
    }

    /** Games won by the device and by the player over [games] seeds. */
    private fun tally(size: Int, you: GameDifficulty, device: GameDifficulty, games: Int): Pair<Int, Int> {
        var deviceWins = 0
        var youWins = 0
        for (seed in 1..games) {
            when (duel(size, you, device, seed.toULong()).first.winner) {
                DotsPlayer.DEVICE -> deviceWins += 1
                DotsPlayer.YOU -> youWins += 1
                null -> {}
            }
        }
        return deviceWins to youWins
    }

    @Test
    fun aSeedPlaysTheIpadsGames() {
        val e = GameDifficulty.EASY
        val m = GameDifficulty.MEDIUM
        val h = GameDifficulty.HARD
        val expected = listOf(
            listOf(3, e, m, 1, 8, 1, "v01,v23,h30,v12,v20,h11,v10,v00,h31,h21,v11,h32,v03,v13,h02,h00,h10,h20,v21,v22,h22,h12,v02,h01"),
            listOf(3, m, h, 2, 1, 8, "v02,v12,v01,h10,v20,h12,h31,h30,v10,h21,v23,h32,h00,v00,h02,v03,h01,h11,v11,h20,v21,v22,h22,v13"),
            listOf(
                4, e, m, 3, 9, 7,
                "h10,v04,h02,v11,h12,h43,v31,v20,h41,v14,v23,h11,h13,v30,v34,h01,v00,h32,h42,v24,v21,v10,h20,h30,h40,h21,v12,v03,h03,v02,v01,h00,h22,v22,v13,h23,h31,v32,v33,h33",
            ),
            listOf(
                4, m, h, 4, 6, 10,
                "h41,v30,v23,h43,h32,v03,v32,h33,h10,v00,v13,v10,h40,v04,v20,h11,v14,h01,v12,h02,v21,v33,v34,h42,h03,h13,v24,h23,h00,v01,v02,h12,v22,h22,h20,h30,v11,h21,h31,v31",
            ),
            listOf(2, h, e, 5, 1, 3, "v10,h00,h01,h11,v00,v11,v12,h21,h10,v01,h20,v02"),
        )
        for (game in expected) {
            val (board, moves) = duel(game[0] as Int, game[1] as GameDifficulty, game[2] as GameDifficulty, (game[3] as Int).toULong())
            assertEquals("seed ${game[3]}", game[6], moves.joinToString(","))
            assertEquals(game[4], board.score(DotsPlayer.YOU))
            assertEquals(game[5], board.score(DotsPlayer.DEVICE))
        }
    }

    @Test
    fun ortaBeatsKolayAndZorBeatsOrta() {
        // The iPad's tallies for these seeds: 19 to 1, 19 to 0, 3 to 1.
        assertEquals(19 to 1, tally(4, GameDifficulty.EASY, GameDifficulty.MEDIUM, 20))
        assertEquals(19 to 0, tally(4, GameDifficulty.MEDIUM, GameDifficulty.HARD, 20))
        val start = System.nanoTime()
        assertEquals(3 to 1, tally(5, GameDifficulty.MEDIUM, GameDifficulty.HARD, 4))
        val seconds = (System.nanoTime() - start) / 1e9
        assertTrue("four 5x5 games in $seconds s", seconds < 30)
        assertFalse(DotsBoard(4) == DotsBoard(4).apply { draw(across(0, 0)) })
    }
}
