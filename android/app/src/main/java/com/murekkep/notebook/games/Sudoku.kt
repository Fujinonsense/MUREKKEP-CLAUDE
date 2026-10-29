package com.murekkep.notebook.games

/**
 * Sudoku without its screen (the iPad's SudokuLogic.swift): a solver, a check for conflicts, and a
 * maker of puzzles with one solution at three difficulties. Grids are 81 digits, row by row, 0 for
 * an empty cell.
 */
object Sudoku {
    const val CELLS = 81

    /** A puzzle and its one solution. */
    data class Puzzle(val givens: List<Int>, val solution: List<Int>) {
        val clueCount: Int get() = givens.count { it != 0 }
    }

    /** How many clues a fresh puzzle keeps: Kolay 40, Orta 32, Zor 26. */
    fun clues(difficulty: GameDifficulty): Int = when (difficulty) {
        GameDifficulty.EASY -> 40
        GameDifficulty.MEDIUM -> 32
        GameDifficulty.HARD -> 26
    }

    fun row(i: Int): Int = i / 9
    fun col(i: Int): Int = i % 9
    fun box(i: Int): Int = (i / 27) * 3 + (i % 9) / 3

    /** The cells that share a row, a column or a box with each cell (twenty each, tabled once). */
    private val peerTable: Array<IntArray> = Array(CELLS) { i ->
        (0 until CELLS).filter { j -> j != i && (row(j) == row(i) || col(j) == col(i) || box(j) == box(i)) }.toIntArray()
    }

    fun peers(i: Int): List<Int> = peerTable[i].toList()

    /** The digits that could go in empty cell [i], in order. */
    fun candidates(grid: List<Int>, i: Int): List<Int> = candidates(grid.toIntArray(), i)

    private fun candidates(grid: IntArray, i: Int): List<Int> {
        val used = BooleanArray(10)
        for (j in peerTable[i]) used[grid[j]] = true
        return (1..9).filter { !used[it] }
    }

    /** The cells whose digit is repeated in their row, column or box. */
    fun conflicts(grid: List<Int>): Set<Int> {
        val out = mutableSetOf<Int>()
        for (i in 0 until CELLS) {
            if (grid[i] == 0) continue
            if (peerTable[i].any { grid[it] == grid[i] }) out.add(i)
        }
        return out
    }

    fun isFull(grid: List<Int>): Boolean = 0 !in grid
    fun isSolved(grid: List<Int>): Boolean = grid.size == CELLS && isFull(grid) && conflicts(grid).isEmpty()

    /** The first solution, or null. */
    fun solve(grid: List<Int>): List<Int>? = Search(grid, limit = 1).also { it.run() }.first?.toList()

    /** How many solutions there are, counting up to [limit]. */
    fun solutionCount(grid: List<Int>, limit: Int = 2): Int = Search(grid, limit).also { it.run() }.count

    /** Backtracking from the cell with the fewest choices, until [limit] solutions are counted. */
    private class Search(grid: List<Int>, private val limit: Int) {
        private val work = grid.toIntArray()
        var count = 0
        var first: IntArray? = null

        fun run() {
            search()
        }

        /** True once [limit] solutions are counted. */
        private fun search(): Boolean {
            var bestCell = -1
            var bestOptions: List<Int> = emptyList()
            for (i in 0 until CELLS) {
                if (work[i] != 0) continue
                val options = candidates(work, i)
                if (options.isEmpty()) return false
                if (bestCell < 0 || options.size < bestOptions.size) {
                    bestCell = i
                    bestOptions = options
                    if (options.size == 1) break
                }
            }
            if (bestCell < 0) {
                count += 1
                if (first == null) first = work.copyOf()
                return count >= limit
            }
            for (digit in bestOptions) {
                work[bestCell] = digit
                if (search()) {
                    work[bestCell] = 0
                    return true
                }
            }
            work[bestCell] = 0
            return false
        }
    }

    /** A full grid, filled in a random order. */
    fun fill(seed: ULong): List<Int> {
        val rng = GameRandom(seed)
        val grid = IntArray(CELLS)
        fill(grid, rng)
        return grid.toList()
    }

    private fun fill(grid: IntArray, rng: GameRandom): Boolean {
        val i = grid.indexOf(0)
        if (i < 0) return true
        for (digit in rng.shuffled(candidates(grid, i))) {
            grid[i] = digit
            if (fill(grid, rng)) return true
        }
        grid[i] = 0
        return false
    }

    /**
     * A puzzle with one solution: a full grid with cells taken away in a random order as long as
     * the solution stays the only one, down to the difficulty's clues.
     */
    fun generate(difficulty: GameDifficulty, seed: ULong): Puzzle {
        val solution = fill(seed)
        val rng = GameRandom(seed + 0x517C_C1B7_2722_0A95uL)
        val givens = solution.toMutableList()
        var clues = CELLS
        val target = clues(difficulty)
        for (i in rng.shuffled((0 until CELLS).toList())) {
            if (clues <= target) continue
            val digit = givens[i]
            givens[i] = 0
            if (solutionCount(givens, limit = 2) == 1) {
                clues -= 1
            } else {
                givens[i] = digit
            }
        }
        return Puzzle(givens.toList(), solution)
    }
}

/**
 * A puzzle left half-way, kept to go on with later (the iPad's SudokuSave). [notes] are the pencil
 * marks per cell. Kept as one line of text: the difficulty, the three grids, the marks, the seconds.
 */
data class SudokuSave(
    val difficulty: GameDifficulty,
    val givens: List<Int>,
    val solution: List<Int>,
    val entries: List<Int>,
    val notes: Map<Int, List<Int>>,
    val elapsed: Int,
) {
    fun encoded(): String = listOf(
        VERSION,
        difficulty.raw,
        givens.joinToString(""),
        solution.joinToString(""),
        entries.joinToString(""),
        notes.toSortedMap().entries.joinToString(",") { (cell, marks) -> "$cell=${marks.joinToString("")}" },
        elapsed.toString(),
    ).joinToString(";")

    companion object {
        private const val VERSION = "sudoku1"

        /** The save in [text], or null when it is missing or broken. */
        fun decode(text: String?): SudokuSave? {
            val parts = text?.split(";") ?: return null
            if (parts.size != 7 || parts[0] != VERSION) return null
            val difficulty = GameDifficulty.fromRaw(parts[1]) ?: return null
            val givens = grid(parts[2]) ?: return null
            val solution = grid(parts[3]) ?: return null
            val entries = grid(parts[4]) ?: return null
            val notes = mutableMapOf<Int, List<Int>>()
            if (parts[5].isNotEmpty()) {
                for (item in parts[5].split(",")) {
                    val cell = item.substringBefore("=", "").toIntOrNull() ?: return null
                    val marks = item.substringAfter("=", "").map { it.digitToIntOrNull() ?: return null }
                    if (cell !in 0 until Sudoku.CELLS || marks.isEmpty() || marks.any { it !in 1..9 }) return null
                    notes[cell] = marks
                }
            }
            val elapsed = parts[6].toIntOrNull()?.takeIf { it >= 0 } ?: return null
            return SudokuSave(difficulty, givens, solution, entries, notes, elapsed)
        }

        private fun grid(text: String): List<Int>? {
            if (text.length != Sudoku.CELLS) return null
            return text.map { c -> c.digitToIntOrNull()?.takeIf { it in 0..9 } ?: return null }
        }
    }
}
