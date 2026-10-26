import Foundation

// The break corner's games without their screens (checked in tools/gamescheck): the mandala's
// mirror, the bubbles' rise and score, the XOX board and the iPad's moves, and what a player keeps
// of every game. Foundation only. The flyer, the bubble shooter and Sudoku have files of their own.

/// Kolay, Orta, Zor: each game reads it its own way.
enum GameDifficulty: String, CaseIterable, Identifiable, Codable {
    case easy, medium, hard

    var id: String { rawValue }
}

/// What a player keeps of one game: the levels opened, the stars of each, the best score at each
/// difficulty and the difficulty chosen. Kept in UserDefaults under `Keys`.
struct GameProgress: Equatable {
    var unlockedLevel = 1
    var stars: [Int: Int] = [:]
    var best: [GameDifficulty: Int] = [:]
    var difficulty: GameDifficulty = .medium

    var totalStars: Int { stars.values.reduce(0, +) }

    func stars(at level: Int) -> Int { stars[level] ?? 0 }

    func isUnlocked(_ level: Int) -> Bool { level >= 1 && level <= unlockedLevel }

    /// A level played to its end: its stars stay the best they ever were, and with any star at all
    /// the next level opens (up to `levels`).
    mutating func complete(level: Int, stars earned: Int, levels: Int) {
        let got = max(0, min(3, earned))
        stars[level] = max(stars[level] ?? 0, got)
        if got > 0 { unlockedLevel = max(unlockedLevel, min(levels, level + 1)) }
    }

    /// A round played to its end: true when `score` is the best so far at `difficulty` (a first
    /// score of nothing is no record; a time is a record when it is shorter).
    @discardableResult
    mutating func record(score: Int, at difficulty: GameDifficulty, lowerIsBetter: Bool = false) -> Bool {
        guard let old = best[difficulty] else {
            best[difficulty] = score
            return lowerIsBetter || score > 0
        }
        let better = lowerIsBetter ? score < old : score > old
        if better { best[difficulty] = score }
        return better
    }

    /// The UserDefaults keys, per game id ("flyer", "sudoku"…).
    enum Keys {
        static func unlocked(_ game: String) -> String { "break.\(game).unlocked" }
        static func stars(_ game: String) -> String { "break.\(game).stars" }
        static func best(_ game: String, _ difficulty: GameDifficulty) -> String { "break.\(game).best.\(difficulty.rawValue)" }
        static func difficulty(_ game: String) -> String { "break.\(game).difficulty" }
        /// A game left half-way (Sudoku), to go on with later.
        static func saved(_ game: String) -> String { "break.\(game).saved" }
        /// The bubbles' best from before the difficulties, read once when the medium best is empty.
        static let legacyBubblesBest = "breakBubblesBest"
    }
}

/// How big the break panel may be: compact, or one step larger that never takes more than a quarter
/// of the canvas, so the notebook stays in view and in reach beside it.
enum GamePanelSize {
    static let compact = CGSize(width: 340, height: 420)
    static let larger = CGSize(width: 400, height: 500)

    /// The larger step inside a canvas with the given room kept clear at each edge: at most
    /// 400×500, at most a quarter of the canvas, never past its edges; the compact size when even
    /// that would not fit.
    static func larger(in canvas: CGSize, leading: Double, trailing: Double, top: Double, bottom: Double) -> CGSize {
        var width = min(Double(larger.width), Double(canvas.width) - leading - trailing)
        var height = min(Double(larger.height), Double(canvas.height) - top - bottom)
        let quarter = Double(canvas.width) * Double(canvas.height) / 4
        if width * height > quarter {
            let k = (quarter / (width * height)).squareRoot()
            width *= k
            height *= k
        }
        if width < Double(compact.width) || height < Double(compact.height) { return compact }
        return CGSize(width: width.rounded(.down), height: height.rounded(.down))
    }
}

/// A small seedable random source, so the games' checks run the same every time (SplitMix64).
struct GameRandom: RandomNumberGenerator, Equatable {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    /// Seeded from the clock.
    init() {
        self.init(seed: UInt64(max(0, Date().timeIntervalSinceReferenceDate * 1000)))
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

// MARK: - Ink mandala

/// The ink mandala: every point of a stroke is drawn `folds` times around the centre, each turn
/// with its mirror image, so one line opens into a flower.
enum MandalaSymmetry {
    static let folds = 8
    /// The ink's colour goes once round the wheel in this many seconds.
    static let huePeriod: TimeInterval = 24

    /// The copies of `point` around `centre`: `folds` turns, each followed by its mirror image
    /// (the point reflected in the vertical axis, then turned the same way). The first copy is the
    /// point itself.
    static func copies(of point: CGPoint, around centre: CGPoint, folds: Int = folds) -> [CGPoint] {
        let dx = Double(point.x - centre.x)
        let dy = Double(point.y - centre.y)
        var out: [CGPoint] = []
        out.reserveCapacity(folds * 2)
        for k in 0..<folds {
            let a = Double(k) * 2 * .pi / Double(folds)
            let c = cos(a)
            let s = sin(a)
            out.append(CGPoint(x: Double(centre.x) + dx * c - dy * s, y: Double(centre.y) + dx * s + dy * c))
            out.append(CGPoint(x: Double(centre.x) - dx * c - dy * s, y: Double(centre.y) - dx * s + dy * c))
        }
        return out
    }

    /// The hue (0…1) of a stroke begun at `time`: it drifts slowly round the wheel.
    static func hue(at time: TimeInterval) -> Double {
        let turn = (time / huePeriod).truncatingRemainder(dividingBy: 1)
        return turn < 0 ? turn + 1 : turn
    }
}

// MARK: - Ink bubbles

/// A bubble of ink on its way up, or a blot, which must not be popped.
struct Bubble: Equatable {
    enum Kind: Equatable {
        case ink, blot
    }

    let id: Int
    let kind: Kind
    /// The column it rises in (points); `x` swings around it.
    let home: Double
    var x: Double
    /// Its centre from the top of the field (points).
    var y: Double
    let radius: Double
    /// Points per second, upwards.
    let speed: Double
    /// How far it swings, and where in the swing it started.
    let sway: Double
    let phase: Double
    let hue: Double
    var age: TimeInterval = 0

    /// Small bubbles are worth most; a blot is worth nothing but trouble.
    var worth: Int {
        switch kind {
        case .blot: return 0
        case .ink: return radius < 15 ? 3 : radius < 21 ? 2 : 1
        }
    }
}

/// The splash a popped bubble (or a touched blot) leaves, for a moment.
struct Splash: Equatable {
    let x: Double
    let y: Double
    let radius: Double
    let hue: Double
    let blot: Bool
    var age: TimeInterval = 0

    static let life: TimeInterval = 0.45
    var done: Bool { age >= Self.life }
}

/// What one touch of the field did.
enum PopResult: Equatable {
    case popped(points: Int, combo: Int)
    case blot(points: Int, seconds: Int)
    case miss
}

/// Sixty seconds of bubbles rising through a field `size` big; each touch pops the bubble under it.
/// They come faster and smaller as the clock runs, blots rise among them (a touch costs points and
/// seconds), and quick pops in a row multiply the points. The field is stepped by `advance(by:)`;
/// nothing in it knows about the screen.
struct BubbleField: Equatable {
    static let round: TimeInterval = 60
    static let bestKey = GameProgress.Keys.legacyBubblesBest
    /// One step never jumps further than this, whatever the clock says (a pause, a slow frame).
    static let maxStep: TimeInterval = 0.1
    /// Pops within this many seconds of each other are a row; a row multiplies the points, up to `maxCombo`.
    static let comboWindow: TimeInterval = 0.9
    static let maxCombo = 4
    /// A touched blot: points off the score and seconds off the clock.
    static let blotPoints = 5
    static let blotSeconds = 3

    /// How the difficulty reads: the pace, the reach of a touch, the share of blots.
    struct Tuning: Equatable {
        /// How much faster than Orta everything comes and rises.
        var pace: Double
        /// How far beside a bubble's edge a touch still pops it (a fingertip is wide).
        var reach: Double
        /// The share of blots among what comes up, at the start and at the end.
        var blotsAtStart: Double
        var blotsAtEnd: Double

        static func tuning(_ difficulty: GameDifficulty) -> Tuning {
            switch difficulty {
            case .easy: return Tuning(pace: 0.8, reach: 14, blotsAtStart: 0.06, blotsAtEnd: 0.18)
            case .medium: return Tuning(pace: 1, reach: 10, blotsAtStart: 0.12, blotsAtEnd: 0.3)
            case .hard: return Tuning(pace: 1.3, reach: 7, blotsAtStart: 0.18, blotsAtEnd: 0.4)
            }
        }
    }

    var size: CGSize
    let tuning: Tuning
    private(set) var bubbles: [Bubble] = []
    private(set) var splashes: [Splash] = []
    private(set) var score = 0
    private(set) var popped = 0
    private(set) var blotsHit = 0
    /// Ink bubbles that got away over the top.
    private(set) var escaped = 0
    private(set) var combo = 1
    private(set) var elapsed: TimeInterval = 0
    /// Seconds taken off the clock by blots.
    private(set) var penalty: TimeInterval = 0
    private var lastPop: TimeInterval = -10
    private var untilSpawn: TimeInterval = 0.5
    private var nextID = 1
    private var rng: GameRandom

    init(size: CGSize, seed: UInt64, difficulty: GameDifficulty = .medium) {
        self.size = size
        tuning = Tuning.tuning(difficulty)
        rng = GameRandom(seed: seed)
    }

    static func pace(_ difficulty: GameDifficulty) -> Double { Tuning.tuning(difficulty).pace }

    var pace: Double { tuning.pace }
    /// The clock, with the blots' seconds gone.
    var timeLeft: TimeInterval { max(0, Self.round - elapsed - penalty) }
    var isOver: Bool { elapsed + penalty >= Self.round }
    /// 0 at the start, 1 at the end: the bubbles come faster, rise faster and shrink.
    var difficulty: Double { min(1, max(0, (elapsed + penalty) / Self.round)) }
    var spawnInterval: TimeInterval { (1.0 - 0.65 * difficulty) / pace }
    /// Points per second a new bubble rises at, before its own variation.
    var riseSpeed: Double { (44 + 76 * difficulty) * pace }
    /// The sizes new bubbles come in now: they shrink by a third over the round.
    var radiusRange: ClosedRange<Double> {
        let k = 1 - 0.35 * difficulty
        return (11 * k)...(28 * k)
    }
    var blotShare: Double { tuning.blotsAtStart + (tuning.blotsAtEnd - tuning.blotsAtStart) * difficulty }

    /// Moves everything on by `dt` seconds (at most `maxStep`); nothing moves once the round is over.
    mutating func advance(by dt: TimeInterval) {
        guard !isOver, dt > 0 else { return }
        let step = min(dt, Self.maxStep, Self.round - elapsed - penalty)
        elapsed += step
        for i in bubbles.indices {
            bubbles[i].age += step
            bubbles[i].y -= bubbles[i].speed * step
            bubbles[i].x = bubbles[i].home + bubbles[i].sway * sin(bubbles[i].phase + bubbles[i].age * 1.7)
        }
        let lost = bubbles.filter { $0.y + $0.radius < 0 && $0.kind == .ink }.count
        if lost > 0 {
            escaped += lost
            combo = 1
        }
        bubbles.removeAll { $0.y + $0.radius < 0 }
        for i in splashes.indices {
            splashes[i].age += step
        }
        splashes.removeAll(where: \.done)
        untilSpawn -= step
        while untilSpawn <= 0 {
            spawn()
            untilSpawn += spawnInterval
        }
    }

    /// A touch at `point`: the nearest bubble under it pops and scores (times the row's multiplier);
    /// a blot costs; nothing under it breaks the row.
    @discardableResult
    mutating func pop(at point: CGPoint) -> PopResult {
        guard !isOver else { return .miss }
        func distance(_ b: Bubble) -> Double {
            let dx = b.x - Double(point.x)
            let dy = b.y - Double(point.y)
            return (dx * dx + dy * dy).squareRoot()
        }
        let hit = bubbles.indices.filter { distance(bubbles[$0]) <= bubbles[$0].radius + tuning.reach }
        guard let i = hit.min(by: { distance(bubbles[$0]) < distance(bubbles[$1]) }) else {
            combo = 1
            return .miss
        }
        let bubble = bubbles.remove(at: i)
        splashes.append(Splash(x: bubble.x, y: bubble.y, radius: bubble.radius, hue: bubble.hue, blot: bubble.kind == .blot))
        switch bubble.kind {
        case .blot:
            score = max(0, score - Self.blotPoints)
            penalty += TimeInterval(Self.blotSeconds)
            blotsHit += 1
            combo = 1
            lastPop = -10
            return .blot(points: Self.blotPoints, seconds: Self.blotSeconds)
        case .ink:
            combo = elapsed - lastPop <= Self.comboWindow ? min(Self.maxCombo, combo + 1) : 1
            lastPop = elapsed
            let points = bubble.worth * combo
            score += points
            popped += 1
            return .popped(points: points, combo: combo)
        }
    }

    private mutating func spawn() {
        let blot = Double.random(in: 0..<1, using: &rng) < blotShare
        let radius = blot ? Double.random(in: 13...21, using: &rng) : Double.random(in: radiusRange, using: &rng)
        let margin = radius + 6
        let width = Double(size.width)
        let home = width > 2 * margin ? Double.random(in: margin...(width - margin), using: &rng) : width / 2
        let speed = riseSpeed * Double.random(in: 0.8...1.25, using: &rng) * (20 / radius).squareRoot()
        let hue = blot ? 0.64 : Double.random(in: 0.52...0.72, using: &rng)
        bubbles.append(Bubble(id: nextID, kind: blot ? .blot : .ink, home: home, x: home, y: Double(size.height) + radius, radius: radius,
                              speed: speed, sway: Double.random(in: 4...12, using: &rng), phase: Double.random(in: 0...(2 * .pi), using: &rng), hue: hue))
        nextID += 1
    }
}

// MARK: - XOX

/// A game of XOX: nine cells, X and O in turn, three in a row wins.
struct TicTacToe: Equatable {
    enum Mark: String, Equatable {
        case x = "X"
        case o = "O"

        var other: Mark { self == .x ? .o : .x }
    }

    enum Outcome: Equatable {
        case won(Mark, line: [Int])
        case draw
    }

    static let lines: [[Int]] = [[0, 1, 2], [3, 4, 5], [6, 7, 8], [0, 3, 6], [1, 4, 7], [2, 5, 8], [0, 4, 8], [2, 4, 6]]
    static let centre = 4
    static let corners = [0, 2, 6, 8]
    static let edges = [1, 3, 5, 7]

    private(set) var cells: [Mark?] = Array(repeating: nil, count: 9)
    private(set) var turn: Mark

    init(first: Mark = .x) {
        turn = first
    }

    var free: [Int] { cells.indices.filter { cells[$0] == nil } }

    var outcome: Outcome? {
        for line in Self.lines {
            if let mark = cells[line[0]], cells[line[1]] == mark, cells[line[2]] == mark {
                return .won(mark, line: line)
            }
        }
        return free.isEmpty ? .draw : nil
    }

    var isOver: Bool { outcome != nil }

    /// Puts the turn's mark in `cell`; false when the cell is taken, out of the board or the game is over.
    @discardableResult
    mutating func play(_ cell: Int) -> Bool {
        guard !isOver, cells.indices.contains(cell), cells[cell] == nil else { return false }
        cells[cell] = turn
        turn = turn.other
        return true
    }

    /// A free cell that completes a line for `mark`, if there is one.
    func winningCell(for mark: Mark) -> Int? {
        for line in Self.lines {
            let marks = line.map { cells[$0] }
            if marks.filter({ $0 == mark }).count == 2, let gap = line.first(where: { cells[$0] == nil }) {
                return gap
            }
        }
        return nil
    }

    /// The iPad's answer for `mark`: a win if there is one, else a block, else the centre, else a
    /// corner, else an edge. `whim` (0…1) is how often it plays any free cell instead of the centre
    /// or corner, so no two games are alike; a win or a block is never missed. It sees no forks, so
    /// a patient player beats it.
    func bestMove<R: RandomNumberGenerator>(for mark: Mark, rng: inout R, whim: Double = 0.2) -> Int? {
        guard !isOver, !free.isEmpty else { return nil }
        if let win = winningCell(for: mark) { return win }
        if let block = winningCell(for: mark.other) { return block }
        if Double.random(in: 0..<1, using: &rng) < whim {
            return free.randomElement(using: &rng)
        }
        if cells[Self.centre] == nil { return Self.centre }
        let corners = Self.corners.filter { cells[$0] == nil }
        if let corner = corners.randomElement(using: &rng) { return corner }
        return Self.edges.filter { cells[$0] == nil }.randomElement(using: &rng) ?? free.first
    }

    /// The iPad's answer at each difficulty: Kolay plays any free cell two times in three and only
    /// then looks for a win or a block; Orta is `bestMove`; Zor plays perfectly (minimax), so it
    /// never loses, but picks among its equally good moves at random.
    func move<R: RandomNumberGenerator>(for mark: Mark, difficulty: GameDifficulty, rng: inout R) -> Int? {
        guard !isOver, !free.isEmpty else { return nil }
        switch difficulty {
        case .easy:
            if Double.random(in: 0..<1, using: &rng) < 0.65 { return free.randomElement(using: &rng) }
            if let win = winningCell(for: mark) { return win }
            if let block = winningCell(for: mark.other) { return block }
            return free.randomElement(using: &rng)
        case .medium:
            return bestMove(for: mark, rng: &rng)
        case .hard:
            return perfectMoves(for: mark).randomElement(using: &rng)
        }
    }

    /// The moves with the best outcome `mark` can force: a win over a draw over a loss, the sooner
    /// the better. On an empty board every move draws, so all nine come back without a search.
    func perfectMoves(for mark: Mark) -> [Int] {
        guard !isOver else { return [] }
        let open = free
        if open.count == 9 { return open }
        var best = Int.min
        var moves: [Int] = []
        for cell in open {
            var next = self
            next.cells[cell] = mark
            next.turn = mark.other
            let value = -next.negamax(for: mark.other, depth: 1)
            if value > best {
                best = value
                moves = [cell]
            } else if value == best {
                moves.append(cell)
            }
        }
        return moves
    }

    /// The value of the board for `mark`, who is to move: 10 − depth for a win, depth − 10 for a loss, 0 for a draw.
    private func negamax(for mark: Mark, depth: Int) -> Int {
        switch outcome {
        case .won(let winner, _)?: return winner == mark ? 10 - depth : depth - 10
        case .draw?: return 0
        case nil: break
        }
        var best = Int.min
        for cell in free {
            var next = self
            next.cells[cell] = mark
            next.turn = mark.other
            best = max(best, -next.negamax(for: mark.other, depth: depth + 1))
        }
        return best
    }
}
