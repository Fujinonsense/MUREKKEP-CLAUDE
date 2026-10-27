import Foundation

// Kare kapmaca (dots and boxes) without its screen (checked in tools/gamescheck): the player and the
// iPad take turns drawing a line between two neighbouring dots; whoever closes a box takes it and
// draws again. Kolay is a 3×3 board against a careless iPad, Orta 4×4 against one that never hands
// over a box it can avoid handing over, Zor 5×5 against one that also counts the endgame through to
// the last box. Foundation only.

enum DotsPlayer: Equatable {
    case you, device

    var other: DotsPlayer { self == .you ? .device : .you }
}

/// A line between two neighbouring dots: from dot (row, col) across to (row, col + 1), or down to
/// (row + 1, col).
struct DotsEdge: Hashable {
    let horizontal: Bool
    let row: Int
    let col: Int
}

/// The board: `size` boxes a side, the lines drawn and by whom, the boxes taken and whose turn it is.
struct DotsBoard: Equatable {
    let size: Int
    private(set) var lines: [DotsEdge: DotsPlayer] = [:]
    /// Box `row * size + col` and who closed it.
    private(set) var owners: [Int: DotsPlayer] = [:]
    private(set) var turn: DotsPlayer
    /// Every line of the board: the horizontal ones row by row, then the vertical ones.
    let edges: [DotsEdge]

    static func size(_ difficulty: GameDifficulty) -> Int {
        switch difficulty {
        case .easy: return 3
        case .medium: return 4
        case .hard: return 5
        }
    }

    init(size: Int, first: DotsPlayer = .you) {
        self.size = size
        turn = first
        var all: [DotsEdge] = []
        for row in 0...size {
            for col in 0..<size { all.append(DotsEdge(horizontal: true, row: row, col: col)) }
        }
        for row in 0..<size {
            for col in 0...size { all.append(DotsEdge(horizontal: false, row: row, col: col)) }
        }
        edges = all
    }

    var freeEdges: [DotsEdge] { edges.filter { lines[$0] == nil } }
    var isOver: Bool { owners.count == size * size }

    func score(_ player: DotsPlayer) -> Int { owners.values.filter { $0 == player }.count }

    /// Who has more boxes at the end; nil while playing and for a draw.
    var winner: DotsPlayer? {
        guard isOver, score(.you) != score(.device) else { return nil }
        return score(.you) > score(.device) ? .you : .device
    }

    /// The four lines round box `box`: top, bottom, left, right.
    func edges(ofBox box: Int) -> [DotsEdge] {
        let row = box / size
        let col = box % size
        return [DotsEdge(horizontal: true, row: row, col: col), DotsEdge(horizontal: true, row: row + 1, col: col),
                DotsEdge(horizontal: false, row: row, col: col), DotsEdge(horizontal: false, row: row, col: col + 1)]
    }

    /// The boxes a line borders: one at the edge of the board, two inside it.
    func boxes(beside edge: DotsEdge) -> [Int] {
        var out: [Int] = []
        if edge.horizontal {
            if edge.row > 0 { out.append((edge.row - 1) * size + edge.col) }
            if edge.row < size { out.append(edge.row * size + edge.col) }
        } else {
            if edge.col > 0 { out.append(edge.row * size + edge.col - 1) }
            if edge.col < size { out.append(edge.row * size + edge.col) }
        }
        return out
    }

    /// How many lines are drawn round a box.
    func sides(ofBox box: Int) -> Int {
        edges(ofBox: box).filter { lines[$0] != nil }.count
    }

    /// How many boxes drawing `edge` would close now.
    func closes(_ edge: DotsEdge) -> Int {
        guard lines[edge] == nil else { return 0 }
        return boxes(beside: edge).filter { sides(ofBox: $0) == 3 }.count
    }

    /// True when drawing `edge` (closing nothing) would leave a box with three sides for the other side.
    func opens(_ edge: DotsEdge) -> Bool {
        lines[edge] == nil && boxes(beside: edge).contains { sides(ofBox: $0) == 2 }
    }

    /// Draws `edge` for the side whose turn it is: the boxes it closes are theirs and they draw again,
    /// otherwise the turn passes. Nil when the line is there already or the game is over.
    @discardableResult
    mutating func draw(_ edge: DotsEdge) -> [Int]? {
        guard !isOver, lines[edge] == nil, edges.contains(edge) else { return nil }
        let mover = turn
        lines[edge] = mover
        let closed = boxes(beside: edge).filter { sides(ofBox: $0) == 4 && owners[$0] == nil }
        for box in closed { owners[box] = mover }
        if closed.isEmpty { turn = mover.other }
        return closed
    }
}

/// How the iPad picks its line.
enum DotsAI {
    /// Free lines at or below this count are searched to the end (Zor), within `searchBudget`
    /// positions; a search that would need more gives way to Orta's rules for that line.
    static let searchLimit = 28
    static let searchBudget = 400_000

    /// The iPad's next line. Kolay often takes a box it can, otherwise plays loosely; Orta takes every
    /// box it can, then plays a line that gives nothing away, and when every line gives something,
    /// the one that gives least; Zor plays like Orta until the end is near, then searches it through.
    static func move<R: RandomNumberGenerator>(on board: DotsBoard, difficulty: GameDifficulty, rng: inout R) -> DotsEdge? {
        let free = board.freeEdges
        guard !free.isEmpty else { return nil }
        let taking = free.filter { board.closes($0) > 0 }
        let safe = free.filter { board.closes($0) == 0 && !board.opens($0) }
        switch difficulty {
        case .easy:
            if !taking.isEmpty, Double.random(in: 0..<1, using: &rng) < 0.6 { return taking.randomElement(using: &rng) }
            if !safe.isEmpty, Double.random(in: 0..<1, using: &rng) < 0.5 { return safe.randomElement(using: &rng) }
            return free.randomElement(using: &rng)
        case .medium:
            if let take = taking.randomElement(using: &rng) { return take }
            if let calm = safe.randomElement(using: &rng) { return calm }
            return cheapest(free, on: board)
        case .hard:
            if free.count <= searchLimit, let choice = best(on: board) { return choice }
            if let take = taking.first { return take }
            if let calm = safe.randomElement(using: &rng) { return calm }
            return cheapest(free, on: board)
        }
    }

    /// Of lines that each hand something over, the one after which the other side can take the
    /// fewest boxes in a row.
    static func cheapest(_ lines: [DotsEdge], on board: DotsBoard) -> DotsEdge? {
        lines.min { handedOver(by: $0, on: board) < handedOver(by: $1, on: board) }
    }

    /// The boxes the other side can take one after another once `edge` is drawn.
    static func handedOver(by edge: DotsEdge, on board: DotsBoard) -> Int {
        var after = board
        guard after.draw(edge) != nil else { return 0 }
        var taken = 0
        while let take = after.freeEdges.first(where: { after.closes($0) > 0 }) {
            taken += after.draw(take)?.count ?? 0
        }
        return taken
    }

    /// A position's worth to the side to move: exact, or a bound found when the search cut it short.
    private struct Known {
        enum Kind { case exact, atLeast, atMost }
        let value: Int
        let kind: Kind
    }

    /// The line that leaves the mover the most boxes, the other side answering as well as it can,
    /// searched to the last line: alpha-beta over the drawn lines as bits, lines that close a box
    /// tried first and those that give one away last, every position met kept in a table. Nil when
    /// the board has more than 64 lines or the search would pass `budget` positions.
    static func best(on board: DotsBoard, budget: Int = searchBudget) -> DotsEdge? {
        let edges = board.edges
        guard edges.count <= 64 else { return nil }
        let index = Dictionary(uniqueKeysWithValues: edges.enumerated().map { ($1, $0) })
        let boxMasks: [UInt64] = (0..<(board.size * board.size)).map { box in
            board.edges(ofBox: box).reduce(UInt64(0)) { $0 | (1 << UInt64(index[$1] ?? 0)) }
        }
        let beside: [[Int]] = edges.map { board.boxes(beside: $0) }
        let full: UInt64 = edges.count == 64 ? ~0 : (1 << UInt64(edges.count)) - 1
        var drawn: UInt64 = 0
        for (i, edge) in edges.enumerated() where board.lines[edge] != nil { drawn |= 1 << UInt64(i) }
        var table: [UInt64: Known] = [:]
        var visited = 0
        var exhausted = false

        func closed(_ i: Int, _ mask: UInt64) -> Int {
            let after = mask | (1 << UInt64(i))
            var count = 0
            for box in beside[i] where after & boxMasks[box] == boxMasks[box] { count += 1 }
            return count
        }

        func ordered(_ mask: UInt64) -> [Int] {
            var taking: [Int] = []
            var calm: [Int] = []
            var giving: [Int] = []
            for i in 0..<edges.count where mask & (1 << UInt64(i)) == 0 {
                let after = mask | (1 << UInt64(i))
                if closed(i, mask) > 0 {
                    taking.append(i)
                } else if beside[i].contains(where: { (after & boxMasks[$0]).nonzeroBitCount == 3 }) {
                    giving.append(i)
                } else {
                    calm.append(i)
                }
            }
            return taking + calm + giving
        }

        func search(_ mask: UInt64, _ low: Int, _ high: Int) -> Int {
            if mask == full { return 0 }
            visited += 1
            if visited > budget {
                exhausted = true
                return 0
            }
            var alpha = low
            var beta = high
            if let known = table[mask] {
                switch known.kind {
                case .exact: return known.value
                case .atLeast: alpha = max(alpha, known.value)
                case .atMost: beta = min(beta, known.value)
                }
                if alpha >= beta { return known.value }
            }
            let start = alpha
            var bestValue = Int.min
            for i in ordered(mask) {
                let gained = closed(i, mask)
                let next = mask | (1 << UInt64(i))
                let v = gained > 0 ? gained + search(next, alpha - gained, beta - gained) : -search(next, -beta, -alpha)
                if exhausted { return 0 }
                bestValue = max(bestValue, v)
                alpha = max(alpha, v)
                if alpha >= beta { break }
            }
            let kind: Known.Kind = bestValue <= start ? .atMost : (bestValue >= beta ? .atLeast : .exact)
            table[mask] = Known(value: bestValue, kind: kind)
            return bestValue
        }

        let left = board.size * board.size - board.owners.count
        var choice: DotsEdge?
        var alpha = -left - 1
        for i in ordered(drawn) {
            let gained = closed(i, drawn)
            let next = drawn | (1 << UInt64(i))
            let v = gained > 0 ? gained + search(next, alpha - gained, left + 1 - gained) : -search(next, -(left + 1), -alpha)
            if exhausted { return nil }
            if v > alpha {
                alpha = v
                choice = edges[i]
            }
        }
        return choice
    }
}
