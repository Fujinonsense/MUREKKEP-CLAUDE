import Foundation

// Sudoku, without its screen (checked in tools/gamescheck): a solver, a check for conflicts, and a
// maker of puzzles with one solution at three difficulties. Grids are 81 digits, row by row, 0 for
// an empty cell. Foundation only.

enum Sudoku {
    static let cells = 81

    /// A puzzle and its one solution.
    struct Puzzle: Equatable {
        let givens: [Int]
        let solution: [Int]

        var clueCount: Int { givens.filter { $0 != 0 }.count }
    }

    /// How many clues a fresh puzzle keeps: Kolay 40, Orta 32, Zor 26.
    static func clues(_ difficulty: GameDifficulty) -> Int {
        switch difficulty {
        case .easy: return 40
        case .medium: return 32
        case .hard: return 26
        }
    }

    static func row(_ i: Int) -> Int { i / 9 }
    static func col(_ i: Int) -> Int { i % 9 }
    static func box(_ i: Int) -> Int { (i / 27) * 3 + (i % 9) / 3 }

    /// The cells that share a row, a column or a box with `i` (twenty each, tabled once).
    static func peers(of i: Int) -> [Int] { peerTable[i] }

    private static let peerTable: [[Int]] = (0..<cells).map { i in
        (0..<cells).filter { j in j != i && (row(j) == row(i) || col(j) == col(i) || box(j) == box(i)) }
    }

    /// The digits that could go in empty cell `i`.
    static func candidates(_ grid: [Int], at i: Int) -> [Int] {
        var used = Set<Int>()
        for j in peers(of: i) where grid[j] != 0 { used.insert(grid[j]) }
        return (1...9).filter { !used.contains($0) }
    }

    /// The cells whose digit is repeated in their row, column or box.
    static func conflicts(_ grid: [Int]) -> Set<Int> {
        var out = Set<Int>()
        for i in 0..<cells where grid[i] != 0 {
            for j in peers(of: i) where grid[j] == grid[i] {
                out.insert(i)
                break
            }
        }
        return out
    }

    static func isFull(_ grid: [Int]) -> Bool { !grid.contains(0) }
    static func isSolved(_ grid: [Int]) -> Bool { grid.count == cells && isFull(grid) && conflicts(grid).isEmpty }

    /// The first solution, or nil.
    static func solve(_ grid: [Int]) -> [Int]? {
        var work = grid
        var found: [Int]?
        var count = 0
        search(&work, count: &count, limit: 1, first: &found)
        return found
    }

    /// How many solutions there are, counting up to `limit`.
    static func solutionCount(_ grid: [Int], limit: Int = 2) -> Int {
        var work = grid
        var found: [Int]?
        var count = 0
        search(&work, count: &count, limit: limit, first: &found)
        return count
    }

    /// Backtracking from the emptiest-choice cell; true once `limit` solutions are counted.
    @discardableResult
    private static func search(_ grid: inout [Int], count: inout Int, limit: Int, first: inout [Int]?) -> Bool {
        var bestCell = -1
        var bestOptions: [Int] = []
        for i in 0..<cells where grid[i] == 0 {
            let options = candidates(grid, at: i)
            if options.isEmpty { return false }
            if bestCell < 0 || options.count < bestOptions.count {
                bestCell = i
                bestOptions = options
                if options.count == 1 { break }
            }
        }
        if bestCell < 0 {
            count += 1
            if first == nil { first = grid }
            return count >= limit
        }
        for digit in bestOptions {
            grid[bestCell] = digit
            if search(&grid, count: &count, limit: limit, first: &first) {
                grid[bestCell] = 0
                return true
            }
        }
        grid[bestCell] = 0
        return false
    }

    /// A full grid, filled in a random order.
    static func fill(seed: UInt64) -> [Int] {
        var rng = GameRandom(seed: seed)
        var grid = Array(repeating: 0, count: cells)
        _ = fill(&grid, rng: &rng)
        return grid
    }

    private static func fill(_ grid: inout [Int], rng: inout GameRandom) -> Bool {
        guard let i = grid.firstIndex(of: 0) else { return true }
        for digit in candidates(grid, at: i).shuffled(using: &rng) {
            grid[i] = digit
            if fill(&grid, rng: &rng) { return true }
        }
        grid[i] = 0
        return false
    }

    /// A puzzle with one solution: a full grid with cells taken away in a random order as long as
    /// the solution stays the only one, down to the difficulty's clues.
    static func generate(difficulty: GameDifficulty, seed: UInt64) -> Puzzle {
        let solution = fill(seed: seed)
        var rng = GameRandom(seed: seed &+ 0x51_7C_C1_B7_27_22_0A_95)
        var givens = solution
        var clues = cells
        let target = self.clues(difficulty)
        for i in Array(0..<cells).shuffled(using: &rng) where clues > target {
            let digit = givens[i]
            givens[i] = 0
            if solutionCount(givens, limit: 2) == 1 {
                clues -= 1
            } else {
                givens[i] = digit
            }
        }
        return Puzzle(givens: givens, solution: solution)
    }
}

/// A puzzle left half-way, kept to go on with later.
struct SudokuSave: Codable, Equatable {
    var difficulty: GameDifficulty
    var givens: [Int]
    var solution: [Int]
    var entries: [Int]
    /// Pencil marks per cell.
    var notes: [Int: [Int]]
    var elapsed: Int

    func encoded() -> Data? { try? JSONEncoder().encode(self) }

    static func decode(_ data: Data) -> SudokuSave? {
        guard let save = try? JSONDecoder().decode(SudokuSave.self, from: data),
              save.givens.count == Sudoku.cells, save.solution.count == Sudoku.cells, save.entries.count == Sudoku.cells
        else { return nil }
        return save
    }
}
