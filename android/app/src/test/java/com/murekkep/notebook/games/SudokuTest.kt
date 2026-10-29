package com.murekkep.notebook.games

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

// Sudoku's maker and solver: tools/gamescheck's checks of the iPad's Sudoku, and the grids and
// puzzles a seed gives on the iPad (printed by its SudokuLogic.swift).
class SudokuTest {
    private fun grid(digits: String): List<Int> = digits.map { it.digitToInt() }

    @Test
    fun rowsColumnsBoxesAndPeers() {
        assertTrue(Sudoku.row(40) == 4 && Sudoku.col(40) == 4 && Sudoku.box(40) == 4 && Sudoku.box(80) == 8 && Sudoku.box(20) == 0)
        val peers = Sudoku.peers(0)
        assertTrue(peers.size == 20 && 10 in peers && 0 !in peers && 30 !in peers)
        val empty = List(81) { 0 }
        assertEquals((1..9).toList(), Sudoku.candidates(empty, 0))
        assertEquals("an empty grid has many solutions", 2, Sudoku.solutionCount(empty, limit = 2))
        assertNotNull(Sudoku.solve(empty))
    }

    @Test
    fun aFilledGridIsASolutionAndTheIpads() {
        val full = Sudoku.fill(4uL)
        assertEquals(grid("428169375695837214137542689286351497719284563543796128361975842872413956954628731"), full)
        assertEquals(grid("459872361378156924612394587945287613281963745736415892824739156167528439593641278"), Sudoku.fill(5uL))
        assertTrue(Sudoku.isSolved(full) && Sudoku.conflicts(full).isEmpty() && Sudoku.fill(4uL) == full)
        val broken = full.toMutableList().apply { this[0] = this[1] }
        // Cell 0 now repeats cell 1's digit, which also stands once in column 0: three cells show it.
        val conflicts = Sudoku.conflicts(broken)
        assertTrue(conflicts.containsAll(listOf(0, 1)) && conflicts.size == 3 && !Sudoku.isSolved(broken))
        val gapped = full.toMutableList().apply { this[3] = 0 }
        assertTrue(!Sudoku.isFull(gapped) && !Sudoku.isSolved(gapped) && Sudoku.candidates(gapped, 3) == listOf(full[3]) && Sudoku.solve(gapped) == full)
    }

    @Test
    fun puzzlesHaveOneSolutionAndTheDifficultysClues() {
        val ipad = mapOf(
            GameDifficulty.EASY to "342000071007402800060071000000200050001008627075600438006000980903760210024083760",
            GameDifficulty.MEDIUM to "342000071007000800060071000000200050001008627005600438006000900903060200020083700",
            GameDifficulty.HARD to "342000001007000800060071000000200050001008027000000430006000900903060000020083700",
        )
        val solution = grid("342896571517432896869571342638247159491358627275619438756124983983765214124983765")
        for (difficulty in GameDifficulty.entries) {
            val puzzle = Sudoku.generate(difficulty, 11uL)
            assertEquals("the iPad's puzzle at ${difficulty.raw}", grid(ipad.getValue(difficulty)), puzzle.givens)
            assertEquals(solution, puzzle.solution)
            val target = Sudoku.clues(difficulty)
            assertTrue("${puzzle.clueCount} clues for $target", puzzle.clueCount in 17..target + 6)
            assertTrue(Sudoku.solutionCount(puzzle.givens, limit = 2) == 1 && Sudoku.solve(puzzle.givens) == puzzle.solution)
            assertTrue(Sudoku.isSolved(puzzle.solution) && puzzle.givens.zip(puzzle.solution).all { (g, s) -> g == 0 || g == s })
            assertEquals(puzzle, Sudoku.generate(difficulty, 11uL))
            assertNotEquals(puzzle, Sudoku.generate(difficulty, 12uL))
        }
        assertEquals(listOf(40, 32, 26), GameDifficulty.entries.map { Sudoku.generate(it, 11uL).clueCount })
        assertEquals(grid("030759000000000000859000076024908060906503000100620950790000025000100039000890000"), Sudoku.generate(GameDifficulty.MEDIUM, 2uL).givens)
    }

    @Test
    fun aHalfDonePuzzleSurvivesASave() {
        val puzzle = Sudoku.generate(GameDifficulty.MEDIUM, 2uL)
        val entries = puzzle.givens.toMutableList().apply { this[0] = 1 }
        val save = SudokuSave(GameDifficulty.MEDIUM, puzzle.givens, puzzle.solution, entries, mapOf(3 to listOf(1, 2), 40 to listOf(7)), 95)
        assertEquals(save, SudokuSave.decode(save.encoded()))
        val bare = save.copy(notes = emptyMap(), elapsed = 0)
        assertEquals(bare, SudokuSave.decode(bare.encoded()))
        for (broken in listOf(null, "", "{}", "nonsense", save.encoded().replace("sudoku1", "sudoku9"), save.encoded().dropLast(3) + ";x",
            save.encoded().replace(";medium;", ";expert;"), save.encoded().replace("3=12", "99=12"), save.encoded().replace("3=12", "3=10"))) {
            assertNull("broken: $broken", SudokuSave.decode(broken))
        }
    }
}
