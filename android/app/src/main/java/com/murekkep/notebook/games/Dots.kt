package com.murekkep.notebook.games

// Kare kapmaca (dots and boxes) without its screen (the iPad's DotsLogic.swift): the player and the
// device take turns drawing a line between two neighbouring dots; whoever closes a box takes it and
// draws again. Kolay is a 3x3 board against a careless device, Orta 4x4 against one that never hands
// over a box it can avoid handing over, Zor 5x5 against one that also counts the endgame through to
// the last box.

enum class DotsPlayer {
    YOU, DEVICE;

    val other: DotsPlayer get() = if (this == YOU) DEVICE else YOU
}

/** A line between two neighbouring dots: from dot (row, col) across to (row, col + 1), or down to (row + 1, col). */
data class DotsEdge(val horizontal: Boolean, val row: Int, val col: Int)

/** The board: [size] boxes a side, the lines drawn and by whom, the boxes taken and whose turn it is. */
class DotsBoard(val size: Int, first: DotsPlayer = DotsPlayer.YOU) {
    private val drawn = HashMap<DotsEdge, DotsPlayer>()
    /** Box `row * size + col` and who closed it. */
    private val taken = HashMap<Int, DotsPlayer>()
    var turn: DotsPlayer = first
        private set

    val lines: Map<DotsEdge, DotsPlayer> get() = drawn
    val owners: Map<Int, DotsPlayer> get() = taken

    /** Every line of the board: the horizontal ones row by row, then the vertical ones. */
    val edges: List<DotsEdge> = (0..size).flatMap { row -> (0 until size).map { col -> DotsEdge(true, row, col) } } +
        (0 until size).flatMap { row -> (0..size).map { col -> DotsEdge(false, row, col) } }

    val freeEdges: List<DotsEdge> get() = edges.filter { it !in drawn }
    val isOver: Boolean get() = taken.size == size * size

    fun score(player: DotsPlayer): Int = taken.values.count { it == player }

    /** Who has more boxes at the end; null while playing and for a draw. */
    val winner: DotsPlayer?
        get() {
            if (!isOver || score(DotsPlayer.YOU) == score(DotsPlayer.DEVICE)) return null
            return if (score(DotsPlayer.YOU) > score(DotsPlayer.DEVICE)) DotsPlayer.YOU else DotsPlayer.DEVICE
        }

    /** The four lines round [box]: top, bottom, left, right. */
    fun edgesOfBox(box: Int): List<DotsEdge> {
        val row = box / size
        val col = box % size
        return listOf(DotsEdge(true, row, col), DotsEdge(true, row + 1, col), DotsEdge(false, row, col), DotsEdge(false, row, col + 1))
    }

    /** The boxes a line borders: one at the edge of the board, two inside it. */
    fun boxesBeside(edge: DotsEdge): List<Int> {
        val out = ArrayList<Int>(2)
        if (edge.horizontal) {
            if (edge.row > 0) out.add((edge.row - 1) * size + edge.col)
            if (edge.row < size) out.add(edge.row * size + edge.col)
        } else {
            if (edge.col > 0) out.add(edge.row * size + edge.col - 1)
            if (edge.col < size) out.add(edge.row * size + edge.col)
        }
        return out
    }

    /** How many lines are drawn round a box. */
    fun sides(box: Int): Int = edgesOfBox(box).count { it in drawn }

    /** How many boxes drawing [edge] would close now. */
    fun closes(edge: DotsEdge): Int {
        if (edge in drawn) return 0
        return boxesBeside(edge).count { sides(it) == 3 }
    }

    /** True when drawing [edge] (closing nothing) would leave a box with three sides for the other side. */
    fun opens(edge: DotsEdge): Boolean = edge !in drawn && boxesBeside(edge).any { sides(it) == 2 }

    /**
     * Draws [edge] for the side whose turn it is: the boxes it closes are theirs and they draw again,
     * otherwise the turn passes. Null when the line is there already or the game is over.
     */
    fun draw(edge: DotsEdge): List<Int>? {
        if (isOver || edge in drawn || edge !in edges) return null
        val mover = turn
        drawn[edge] = mover
        val closed = boxesBeside(edge).filter { sides(it) == 4 && it !in taken }
        for (box in closed) taken[box] = mover
        if (closed.isEmpty()) turn = mover.other
        return closed
    }

    fun copy(): DotsBoard = DotsBoard(size, turn).also {
        it.drawn.putAll(drawn)
        it.taken.putAll(taken)
    }

    override fun equals(other: Any?): Boolean =
        other is DotsBoard && other.size == size && other.turn == turn && other.drawn == drawn && other.taken == taken

    override fun hashCode(): Int = ((size * 31 + turn.hashCode()) * 31 + drawn.hashCode()) * 31 + taken.hashCode()

    companion object {
        fun size(difficulty: GameDifficulty): Int = when (difficulty) {
            GameDifficulty.EASY -> 3
            GameDifficulty.MEDIUM -> 4
            GameDifficulty.HARD -> 5
        }
    }
}

/** How the device picks its line. */
object DotsAI {
    /**
     * Free lines at or below this count are searched to the end (Zor), within [SEARCH_BUDGET]
     * positions; a search that would need more gives way to Orta's rules for that line.
     */
    const val SEARCH_LIMIT = 28
    const val SEARCH_BUDGET = 400_000

    /**
     * The device's next line. Kolay often takes a box it can, otherwise plays loosely; Orta takes every
     * box it can, then plays a line that gives nothing away, and when every line gives something,
     * the one that gives least; Zor plays like Orta until the end is near, then searches it through.
     */
    fun move(board: DotsBoard, difficulty: GameDifficulty, rng: GameRandom): DotsEdge? {
        val free = board.freeEdges
        if (free.isEmpty()) return null
        val taking = free.filter { board.closes(it) > 0 }
        val safe = free.filter { board.closes(it) == 0 && !board.opens(it) }
        return when (difficulty) {
            GameDifficulty.EASY -> {
                if (taking.isNotEmpty() && rng.nextDouble(0.0, 1.0) < 0.6) return rng.element(taking)
                if (safe.isNotEmpty() && rng.nextDouble(0.0, 1.0) < 0.5) return rng.element(safe)
                rng.element(free)
            }
            GameDifficulty.MEDIUM -> rng.element(taking) ?: rng.element(safe) ?: cheapest(free, board)
            GameDifficulty.HARD -> {
                if (free.size <= SEARCH_LIMIT) best(board)?.let { return it }
                taking.firstOrNull() ?: rng.element(safe) ?: cheapest(free, board)
            }
        }
    }

    /** Of lines that each hand something over, the one after which the other side can take the fewest boxes in a row. */
    fun cheapest(lines: List<DotsEdge>, board: DotsBoard): DotsEdge? = lines.minByOrNull { handedOver(it, board) }

    /** The boxes the other side can take one after another once [edge] is drawn. */
    fun handedOver(edge: DotsEdge, board: DotsBoard): Int {
        val after = board.copy()
        if (after.draw(edge) == null) return 0
        var taken = 0
        while (true) {
            val take = after.freeEdges.firstOrNull { after.closes(it) > 0 } ?: break
            taken += after.draw(take)?.size ?: 0
        }
        return taken
    }

    /**
     * The line that leaves the mover the most boxes, the other side answering as well as it can,
     * searched to the last line: alpha-beta over the drawn lines as bits, lines that close a box
     * tried first and those that give one away last, every position met kept in a table. Null when
     * the board has more than 64 lines or the search would pass [budget] positions.
     */
    fun best(board: DotsBoard, budget: Int = SEARCH_BUDGET): DotsEdge? {
        val edges = board.edges
        if (edges.size > 64) return null
        return EndgameSearch(board, budget).choice()
    }

    /** One search of [best]: the lines as bit numbers, the boxes as masks of their four lines. */
    private class EndgameSearch(private val board: DotsBoard, private val budget: Int) {
        private val edges = board.edges
        private val count = edges.size
        private val index: Map<DotsEdge, Int> = edges.withIndex().associate { (i, e) -> e to i }
        private val boxMasks = LongArray(board.size * board.size) { box ->
            board.edgesOfBox(box).fold(0L) { mask, e -> mask or (1L shl (index[e] ?: 0)) }
        }
        private val beside: Array<IntArray> = Array(count) { board.boxesBeside(edges[it]).toIntArray() }
        private val full: Long = if (count == 64) -1L else (1L shl count) - 1
        private val table = PositionTable()
        private var visited = 0
        private var exhausted = false

        fun choice(): DotsEdge? {
            var drawn = 0L
            for ((i, edge) in edges.withIndex()) if (edge in board.lines) drawn = drawn or (1L shl i)
            val left = board.size * board.size - board.owners.size
            var choice: DotsEdge? = null
            var alpha = -left - 1
            for (i in ordered(drawn)) {
                val gained = closed(i, drawn)
                val next = drawn or (1L shl i)
                val v = if (gained > 0) gained + search(next, alpha - gained, left + 1 - gained) else -search(next, -(left + 1), -alpha)
                if (exhausted) return null
                if (v > alpha) {
                    alpha = v
                    choice = edges[i]
                }
            }
            return choice
        }

        /** The boxes line [i] closes when drawn over [mask]. */
        private fun closed(i: Int, mask: Long): Int {
            val after = mask or (1L shl i)
            var n = 0
            for (box in beside[i]) if (after and boxMasks[box] == boxMasks[box]) n += 1
            return n
        }

        /** The free lines: those that close a box first, then the calm ones, then those that give a box away. */
        private fun ordered(mask: Long): IntArray {
            val taking = IntArray(count)
            val calm = IntArray(count)
            val giving = IntArray(count)
            var t = 0
            var c = 0
            var g = 0
            for (i in 0 until count) {
                if (mask and (1L shl i) != 0L) continue
                val after = mask or (1L shl i)
                if (closed(i, mask) > 0) {
                    taking[t++] = i
                } else if (beside[i].any { java.lang.Long.bitCount(after and boxMasks[it]) == 3 }) {
                    giving[g++] = i
                } else {
                    calm[c++] = i
                }
            }
            val out = IntArray(t + c + g)
            taking.copyInto(out, 0, 0, t)
            calm.copyInto(out, t, 0, c)
            giving.copyInto(out, t + c, 0, g)
            return out
        }

        /** The worth of [mask] to the side to move, searched within ([low], [high]). */
        private fun search(mask: Long, low: Int, high: Int): Int {
            if (mask == full) return 0
            visited += 1
            if (visited > budget) {
                exhausted = true
                return 0
            }
            var alpha = low
            var beta = high
            val known = table[mask]
            if (known != PositionTable.ABSENT) {
                val value = known shr 2
                when (known and 3) {
                    EXACT -> return value
                    AT_LEAST -> alpha = maxOf(alpha, value)
                    AT_MOST -> beta = minOf(beta, value)
                }
                if (alpha >= beta) return value
            }
            val start = alpha
            var best = Int.MIN_VALUE
            for (i in ordered(mask)) {
                val gained = closed(i, mask)
                val next = mask or (1L shl i)
                val v = if (gained > 0) gained + search(next, alpha - gained, beta - gained) else -search(next, -beta, -alpha)
                if (exhausted) return 0
                best = maxOf(best, v)
                alpha = maxOf(alpha, v)
                if (alpha >= beta) break
            }
            val kind = if (best <= start) AT_MOST else if (best >= beta) AT_LEAST else EXACT
            table[mask] = (best shl 2) or kind
            return best
        }

        private companion object {
            const val EXACT = 0
            const val AT_LEAST = 1
            const val AT_MOST = 2
        }
    }

    /** Positions met in a search (their lines as bits) and what each was worth, without boxing: open addressing. */
    private class PositionTable {
        private var keys = LongArray(1 shl 12)
        private var values = IntArray(1 shl 12)
        private var used = BooleanArray(1 shl 12)
        private var size = 0

        operator fun get(key: Long): Int {
            var slot = slot(key, keys.size)
            while (used[slot]) {
                if (keys[slot] == key) return values[slot]
                slot = (slot + 1) and (keys.size - 1)
            }
            return ABSENT
        }

        operator fun set(key: Long, value: Int) {
            if (2 * (size + 1) > keys.size) grow()
            var slot = slot(key, keys.size)
            while (used[slot]) {
                if (keys[slot] == key) {
                    values[slot] = value
                    return
                }
                slot = (slot + 1) and (keys.size - 1)
            }
            used[slot] = true
            keys[slot] = key
            values[slot] = value
            size += 1
        }

        private fun grow() {
            val oldKeys = keys
            val oldValues = values
            val oldUsed = used
            keys = LongArray(oldKeys.size * 2)
            values = IntArray(oldKeys.size * 2)
            used = BooleanArray(oldKeys.size * 2)
            size = 0
            for (i in oldKeys.indices) if (oldUsed[i]) set(oldKeys[i], oldValues[i])
        }

        private fun slot(key: Long, capacity: Int): Int {
            var h = key * -0x61c8864680b583ebL
            h = h xor (h ushr 29)
            return h.toInt() and (capacity - 1)
        }

        companion object {
            /** No value: a stored value is (worth shl 2) or kind, and worths stay far above Int.MIN_VALUE shr 2. */
            const val ABSENT = Int.MIN_VALUE
        }
    }
}
