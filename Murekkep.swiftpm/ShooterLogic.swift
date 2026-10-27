import Foundation

// Renk patlat, without its screen (checked in tools/gamescheck): ink bubbles hang from the top of
// the page in a honeycomb; one is shot from the pen at the bottom, three of a colour together pop,
// and whatever is left hanging on nothing falls. Hand-made levels, a limited number of shots; the
// colour in the pen can be swapped with the next, and a big pop earns an ink blot that bursts
// whatever it reaches. Foundation only.

/// A place in the honeycomb: `row` from the top, `col` from the left. Odd rows stand half a cell
/// to the right and hold one cell fewer.
struct ShooterCell: Hashable, Equatable {
    let row: Int
    let col: Int

    init(_ row: Int, _ col: Int) {
        self.row = row
        self.col = col
    }
}

/// The honeycomb in points: `cols` cells across an even row, each `radius` wide.
struct HexGrid: Equatable {
    let cols: Int
    let radius: Double

    var rowHeight: Double { radius * 3.0.squareRoot() }
    var width: Double { 2 * radius * Double(cols) }

    func width(ofRow row: Int) -> Int { row % 2 == 0 ? cols : cols - 1 }

    func contains(_ cell: ShooterCell) -> Bool {
        cell.row >= 0 && cell.col >= 0 && cell.col < width(ofRow: cell.row)
    }

    func centre(_ cell: ShooterCell) -> CGPoint {
        let shift = cell.row % 2 == 1 ? radius : 0
        return CGPoint(x: radius + Double(cell.col) * 2 * radius + shift, y: radius + Double(cell.row) * rowHeight)
    }

    func neighbours(of cell: ShooterCell) -> [ShooterCell] {
        let r = cell.row
        let c = cell.col
        let beside = [ShooterCell(r, c - 1), ShooterCell(r, c + 1)]
        let aboveBelow = r % 2 == 0
            ? [ShooterCell(r - 1, c - 1), ShooterCell(r - 1, c), ShooterCell(r + 1, c - 1), ShooterCell(r + 1, c)]
            : [ShooterCell(r - 1, c), ShooterCell(r - 1, c + 1), ShooterCell(r + 1, c), ShooterCell(r + 1, c + 1)]
        return (beside + aboveBelow).filter(contains)
    }

    /// The nearest cell to `point` that is in the honeycomb and not in `taken`.
    func nearestFreeCell(to point: CGPoint, taken: Set<ShooterCell>) -> ShooterCell {
        let row = max(0, Int(((Double(point.y) - radius) / rowHeight).rounded()))
        let col = Int(((Double(point.x) - radius) / (2 * radius)).rounded())
        var best: ShooterCell?
        var bestDistance = Double.infinity
        for r in max(0, row - 2)...(row + 2) {
            for c in (col - 2)...(col + 2) {
                let cell = ShooterCell(r, c)
                guard contains(cell), !taken.contains(cell) else { continue }
                let centre = self.centre(cell)
                let dx = Double(centre.x - point.x)
                let dy = Double(centre.y - point.y)
                let distance = dx * dx + dy * dy
                if distance < bestDistance {
                    bestDistance = distance
                    best = cell
                }
            }
        }
        return best ?? ShooterCell(row, max(0, min(width(ofRow: row) - 1, col)))
    }
}

/// A hand-made level: rows of letters (R B G Y P O for the colours, "." for nothing) and the shots
/// it allows at Orta.
struct ShooterLevel: Equatable {
    let rows: [String]
    let shots: Int
}

enum ShooterLevels {
    static let letters: [Character] = ["R", "B", "G", "Y", "P", "O"]

    static let all: [ShooterLevel] = [
        ShooterLevel(rows: ["RRRBBBGGG", "RRRBBBGG", "BBBGGGRRR", "BBBGGGRR"], shots: 10),
        ShooterLevel(rows: ["RBGRBGRBG", "RBGRBGRB", "RBGRBGRBG", "RBGRBGRB"], shots: 12),
        ShooterLevel(rows: ["RBRBRBRBR", "BRBRBRBR", "RBRBRBRBR", "BRBRBRBR", "YYYYYYYYY"], shots: 12),
        ShooterLevel(rows: ["..RRBBB..", ".RRYYBB.", "RRYYYYBBB", ".RRYYBB.", "..RRBBB.."], shots: 12),
        ShooterLevel(rows: ["RR.GG.BB.", "R..G..B.", "RR.GG.BB.", "Y..Y..Y.", "YY.YY.YY."], shots: 14),
        ShooterLevel(rows: ["....R....", "...RR...", "...BRB...", "..BGGB..", "..YBGGBY.", "...YBBY.", "....YY..."], shots: 14),
        ShooterLevel(rows: ["RRRR.BBBB", "RRR..BBB", "GGGR.BYYY", "GGG..YYY", "GG.....YY"], shots: 14),
        ShooterLevel(rows: ["RRRRRRRRR", "BBBBBBBB", "GGGGGGGGG", "YYYYYYYY", "RRRRRRRRR", "BBBBBBBB"], shots: 16),
        ShooterLevel(rows: ["R.B.G.Y.R", "RB.G.Y.R", "RBBGGYYRR", "BBGGYYRR", ".BGG.YYR."], shots: 16),
        ShooterLevel(rows: ["RRRRRRRRR", "R......R", "RB.....BR", "RBB...BB", "RBBGGGBBR", ".GGGGG.."], shots: 16),
        ShooterLevel(rows: ["RBGYRBGYR", "BGYRBGYR", "GYRBGYRBG", "YRBGYRBG", "RBGYRBGYR", "BGYRBGYR"], shots: 18),
        ShooterLevel(rows: ["RRRBBBGGG", "R..B..G.", "R..B..G..", "Y..Y..Y.", "YY.YY.YY.", "GG.RR.BB"], shots: 16),
        ShooterLevel(rows: ["..RR.RR..", "RRRRRRRR", "RRBBBBBRR", "RRBBBBRR", ".RRBBRR..", "..RRRR..", "...RRR...", "....R..."], shots: 16),
        ShooterLevel(rows: ["RBGYPRBGY", "PRBGYPRB", "GYPRBGYPR", "BGYPRBGY", "PRBGYPRBG", "YPRBGYPR"], shots: 20),
    ]

    static var count: Int { all.count }
}

/// What one shot did: where the bubble landed, which bubbles popped, which fell, and the points.
struct ShotResult: Equatable {
    let landed: ShooterCell
    let popped: [ShooterCell]
    let fell: [ShooterCell]
    let scored: Int
    /// The bubble's way there, for the screen to fly it along.
    let path: [CGPoint]
}

/// A level in play.
struct ShooterBoard: Equatable {
    enum Phase: Equatable {
        case playing, won, lost
    }

    static let cols = 9
    /// A bubble that comes to rest this far down loses the level.
    static let deadRow = 9
    static let popSize = 3
    static let popPoints = 10
    static let fallPoints = 20
    /// Steps of the flight, points.
    static let flightStep = 3.0
    /// The ink blot: not a colour but a shot of its own. A shot that pops `blotPops` bubbles or
    /// drops `blotFalls` earns one as the next shot; where it lands it bursts every bubble around it.
    static let blot = -1
    static let blotPops = 6
    static let blotFalls = 4

    private(set) var cells: [ShooterCell: Int]
    private(set) var shotsLeft: Int
    private(set) var score = 0
    private(set) var phase: Phase = .playing
    /// The colour in the pen and the one after it (either may be the blot).
    private(set) var loaded: Int
    private(set) var next: Int
    /// Blots earned in the level.
    private(set) var blotsEarned = 0
    /// How many colours the level uses at this difficulty.
    let colours: Int
    /// The points the level's bubbles are worth popped: the measure of the stars.
    let par: Int
    private var rng: GameRandom

    static func colours(_ difficulty: GameDifficulty) -> Int {
        switch difficulty {
        case .easy: return 3
        case .medium: return 4
        case .hard: return 5
        }
    }

    static func shots(_ base: Int, _ difficulty: GameDifficulty) -> Int {
        switch difficulty {
        case .easy: return base + 6
        case .medium: return base
        case .hard: return max(4, base - 3)
        }
    }

    /// The level's bubbles at `difficulty`: Kolay folds the letters to three colours, Orta keeps the
    /// four, Zor scatters a fifth across them.
    static func cells(of level: ShooterLevel, difficulty: GameDifficulty) -> [ShooterCell: Int] {
        let count = colours(difficulty)
        var out: [ShooterCell: Int] = [:]
        for (row, text) in level.rows.enumerated() {
            let width = row % 2 == 0 ? cols : cols - 1
            for (col, letter) in text.prefix(width).enumerated() {
                guard let index = ShooterLevels.letters.firstIndex(of: letter) else { continue }
                var colour = index % min(count, 4)
                if difficulty == .hard, (row * 5 + col * 3) % 7 == 0 { colour = 4 }
                out[ShooterCell(row, col)] = colour
            }
        }
        return out
    }

    init(level: ShooterLevel, difficulty: GameDifficulty, seed: UInt64) {
        cells = Self.cells(of: level, difficulty: difficulty)
        colours = Self.colours(difficulty)
        shotsLeft = Self.shots(level.shots, difficulty)
        par = cells.count * Self.popPoints
        rng = GameRandom(seed: seed)
        loaded = 0
        next = 0
        loaded = pick()
        next = pick()
    }

    var coloursOnBoard: Set<Int> { Set(cells.values) }
    var isOver: Bool { phase != .playing }

    /// One star for clearing the level, two with a fifth more than par, three with six tenths more.
    var stars: Int {
        guard phase == .won else { return 0 }
        if score * 10 >= par * 16 { return 3 }
        if score * 10 >= par * 12 { return 2 }
        return 1
    }

    /// The bubble's flight from `origin` along `direction` (unit, pointing up): straight, one bounce
    /// off a wall, until it touches a bubble, the top, or a second wall. Its resting cell comes with it.
    func flight(from origin: CGPoint, direction: CGPoint, grid: HexGrid) -> (path: [CGPoint], landing: ShooterCell) {
        var x = Double(origin.x)
        var y = Double(origin.y)
        var dx = Double(direction.x)
        let dy = Double(direction.y)
        let r = grid.radius
        let touch = 2 * r - 0.5
        let occupied = cells.keys.map { ($0, grid.centre($0)) }
        var path = [origin]
        var bounces = 0
        var steps = 0
        while steps < 4000 {
            steps += 1
            x += dx * Self.flightStep
            y += dy * Self.flightStep
            if x < r {
                x = 2 * r - x
                dx = -dx
                bounces += 1
            } else if x > grid.width - r {
                x = 2 * (grid.width - r) - x
                dx = -dx
                bounces += 1
            }
            if bounces > 1 || y <= r { break }
            if occupied.contains(where: { _, c in
                let ex = Double(c.x) - x
                let ey = Double(c.y) - y
                return ex * ex + ey * ey < touch * touch
            }) { break }
            if steps % 4 == 0 { path.append(CGPoint(x: x, y: y)) }
        }
        let stop = CGPoint(x: x, y: max(r, y))
        path.append(stop)
        return (path, grid.nearestFreeCell(to: stop, taken: Set(cells.keys)))
    }

    /// Swaps the colour in the pen with the next one, as often as liked.
    mutating func swapLoaded() {
        guard phase == .playing else { return }
        (loaded, next) = (next, loaded)
    }

    /// Shoots the loaded colour; nil when the level is over or the aim points down. A blot bursts
    /// the bubbles around the cell it reaches and stays nowhere.
    mutating func shoot(from origin: CGPoint, direction: CGPoint, grid: HexGrid) -> ShotResult? {
        guard phase == .playing, direction.y < 0 else { return nil }
        let colour = loaded
        let (path, landing) = flight(from: origin, direction: direction, grid: grid)
        shotsLeft -= 1
        var popped: [ShooterCell] = []
        if colour == Self.blot {
            popped = grid.neighbours(of: landing).filter { cells[$0] != nil }.sorted { ($0.row, $0.col) < ($1.row, $1.col) }
            for cell in popped { cells[cell] = nil }
        } else {
            cells[landing] = colour
            let cluster = sameColour(from: landing, grid: grid)
            if cluster.count >= Self.popSize {
                popped = cluster.sorted { ($0.row, $0.col) < ($1.row, $1.col) }
                for cell in popped { cells[cell] = nil }
            }
        }
        let fell = popped.isEmpty ? [] : fallOrphans(grid: grid)
        let scored = popped.count * Self.popPoints + fell.count * Self.fallPoints
        score += scored
        loaded = next
        next = pick()
        if colour != Self.blot, popped.count >= Self.blotPops || fell.count >= Self.blotFalls, loaded != Self.blot {
            next = Self.blot
            blotsEarned += 1
        }
        if cells.isEmpty {
            phase = .won
        } else if cells.keys.contains(where: { $0.row >= Self.deadRow }) || shotsLeft <= 0 {
            phase = .lost
        }
        return ShotResult(landed: landing, popped: popped, fell: fell, scored: scored, path: path)
    }

    /// The bubbles of `cell`'s colour that touch it, through each other.
    func sameColour(from cell: ShooterCell, grid: HexGrid) -> Set<ShooterCell> {
        guard let colour = cells[cell] else { return [] }
        var seen: Set<ShooterCell> = [cell]
        var queue = [cell]
        while let current = queue.popLast() {
            for n in grid.neighbours(of: current) where cells[n] == colour && !seen.contains(n) {
                seen.insert(n)
                queue.append(n)
            }
        }
        return seen
    }

    /// Takes down every bubble that no longer hangs from the top row, and says which.
    @discardableResult
    mutating func fallOrphans(grid: HexGrid) -> [ShooterCell] {
        var held = Set(cells.keys.filter { $0.row == 0 })
        var queue = Array(held)
        while let current = queue.popLast() {
            for n in grid.neighbours(of: current) where cells[n] != nil && !held.contains(n) {
                held.insert(n)
                queue.append(n)
            }
        }
        let fell = cells.keys.filter { !held.contains($0) }.sorted { ($0.row, $0.col) < ($1.row, $1.col) }
        for cell in fell { cells[cell] = nil }
        return fell
    }

    /// A colour still on the board, so no shot is useless.
    private mutating func pick() -> Int {
        let present = coloursOnBoard.sorted()
        guard !present.isEmpty else { return loaded }
        return present[Int(rng.next() % UInt64(present.count))]
    }
}
