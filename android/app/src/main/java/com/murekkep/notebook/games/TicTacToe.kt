package com.murekkep.notebook.games

/** A game of XOX: nine cells, X and O in turn, three in a row wins (the iPad's TicTacToe). */
class TicTacToe(first: Mark = Mark.X) {
    enum class Mark {
        X, O;

        val other: Mark get() = if (this == X) O else X
    }

    sealed interface Outcome {
        data class Won(val mark: Mark, val line: List<Int>) : Outcome
        data object Draw : Outcome
    }

    private val board = arrayOfNulls<Mark>(9)
    val cells: List<Mark?> get() = board.toList()
    var turn: Mark = first
        private set

    val free: List<Int> get() = (0 until 9).filter { board[it] == null }

    val outcome: Outcome?
        get() {
            for (line in LINES) {
                val mark = board[line[0]] ?: continue
                if (board[line[1]] == mark && board[line[2]] == mark) return Outcome.Won(mark, line)
            }
            return if (free.isEmpty()) Outcome.Draw else null
        }

    val isOver: Boolean get() = outcome != null

    /** Puts the turn's mark in [cell]; false when the cell is taken, out of the board or the game is over. */
    fun play(cell: Int): Boolean {
        if (isOver || cell !in 0 until 9 || board[cell] != null) return false
        board[cell] = turn
        turn = turn.other
        return true
    }

    /** A free cell that completes a line for [mark], if there is one. */
    fun winningCell(mark: Mark): Int? {
        for (line in LINES) {
            if (line.count { board[it] == mark } == 2) {
                val gap = line.firstOrNull { board[it] == null }
                if (gap != null) return gap
            }
        }
        return null
    }

    /**
     * The device's answer for [mark]: a win if there is one, else a block, else the centre, else a
     * corner, else an edge. [whim] (0..1) is how often it plays any free cell instead of the centre
     * or corner, so no two games are alike; a win or a block is never missed. It sees no forks, so
     * a patient player beats it.
     */
    fun bestMove(mark: Mark, rng: GameRandom, whim: Double = 0.2): Int? {
        if (isOver || free.isEmpty()) return null
        winningCell(mark)?.let { return it }
        winningCell(mark.other)?.let { return it }
        if (rng.nextDouble(0.0, 1.0) < whim) return rng.element(free)
        if (board[CENTRE] == null) return CENTRE
        rng.element(CORNERS.filter { board[it] == null })?.let { return it }
        return rng.element(EDGES.filter { board[it] == null }) ?: free.firstOrNull()
    }

    /**
     * The device's answer at each difficulty: Kolay plays any free cell two times in three and only
     * then looks for a win or a block; Orta is [bestMove]; Zor plays perfectly (negamax), so it never
     * loses, but picks among its equally good moves at random.
     */
    fun move(mark: Mark, difficulty: GameDifficulty, rng: GameRandom): Int? {
        if (isOver || free.isEmpty()) return null
        return when (difficulty) {
            GameDifficulty.EASY -> {
                if (rng.nextDouble(0.0, 1.0) < 0.65) return rng.element(free)
                winningCell(mark) ?: winningCell(mark.other) ?: rng.element(free)
            }
            GameDifficulty.MEDIUM -> bestMove(mark, rng)
            GameDifficulty.HARD -> rng.element(perfectMoves(mark))
        }
    }

    /**
     * The moves with the best outcome [mark] can force: a win over a draw over a loss, the sooner
     * the better. On an empty board every move draws, so all nine come back without a search.
     */
    fun perfectMoves(mark: Mark): List<Int> {
        if (isOver) return emptyList()
        val open = free
        if (open.size == 9) return open
        var best = Int.MIN_VALUE
        val moves = mutableListOf<Int>()
        for (cell in open) {
            val next = copy()
            next.board[cell] = mark
            next.turn = mark.other
            val value = -next.negamax(mark.other, 1)
            if (value > best) {
                best = value
                moves.clear()
                moves.add(cell)
            } else if (value == best) {
                moves.add(cell)
            }
        }
        return moves
    }

    /** The value of the board for [mark], who is to move: 10 - depth for a win, depth - 10 for a loss, 0 for a draw. */
    private fun negamax(mark: Mark, depth: Int): Int {
        when (val result = outcome) {
            is Outcome.Won -> return if (result.mark == mark) 10 - depth else depth - 10
            Outcome.Draw -> return 0
            null -> {}
        }
        var best = Int.MIN_VALUE
        for (cell in free) {
            val next = copy()
            next.board[cell] = mark
            next.turn = mark.other
            best = maxOf(best, -next.negamax(mark.other, depth + 1))
        }
        return best
    }

    fun copy(): TicTacToe = TicTacToe(turn).also { board.copyInto(it.board) }

    override fun equals(other: Any?): Boolean = other is TicTacToe && other.turn == turn && other.board.contentEquals(board)

    override fun hashCode(): Int = 31 * board.contentHashCode() + turn.hashCode()

    companion object {
        val LINES: List<List<Int>> = listOf(
            listOf(0, 1, 2), listOf(3, 4, 5), listOf(6, 7, 8), listOf(0, 3, 6), listOf(1, 4, 7), listOf(2, 5, 8), listOf(0, 4, 8), listOf(2, 4, 6),
        )
        const val CENTRE = 4
        val CORNERS = listOf(0, 2, 6, 8)
        val EDGES = listOf(1, 3, 5, 7)
    }
}
