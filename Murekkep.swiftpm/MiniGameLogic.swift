import Foundation

// The break corner's games without their screens (checked in tools/gamescheck): the mandala's
// mirror, the bubbles' rise and score, the XOX board and the iPad's moves. Foundation only.

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

/// A bubble of ink on its way up.
struct Bubble: Equatable {
    let id: Int
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

    /// Small bubbles are worth more.
    var worth: Int { radius < BubbleField.smallRadius ? 2 : 1 }
}

/// The splash a popped bubble leaves, for a moment.
struct Splash: Equatable {
    let x: Double
    let y: Double
    let radius: Double
    let hue: Double
    var age: TimeInterval = 0

    static let life: TimeInterval = 0.45
    var done: Bool { age >= Self.life }
}

/// Sixty seconds of bubbles rising through a field `size` big; each tap pops the bubble under it.
/// The field is stepped by `advance(by:)`; nothing in it knows about the screen.
struct BubbleField: Equatable {
    static let round: TimeInterval = 60
    static let bestKey = "breakBubblesBest"
    /// Bubbles narrower than this are the two-point ones.
    static let smallRadius = 20.0
    /// How far beside a bubble's edge a touch still pops it (a fingertip is wide).
    static let reach = 12.0
    /// Seconds between bubbles at the start and at the end of a round.
    static let spawnEasy: TimeInterval = 1.1
    static let spawnHard: TimeInterval = 0.45
    /// One step never jumps further than this, whatever the clock says (a pause, a slow frame).
    static let maxStep: TimeInterval = 0.1

    var size: CGSize
    private(set) var bubbles: [Bubble] = []
    private(set) var splashes: [Splash] = []
    private(set) var score = 0
    private(set) var popped = 0
    private(set) var elapsed: TimeInterval = 0
    private var untilSpawn: TimeInterval = 0.5
    private var nextID = 1
    private var rng: GameRandom

    init(size: CGSize, seed: UInt64) {
        self.size = size
        rng = GameRandom(seed: seed)
    }

    var timeLeft: TimeInterval { max(0, Self.round - elapsed) }
    var isOver: Bool { elapsed >= Self.round }
    /// 0 at the start, 1 at the end: the bubbles come faster and rise faster.
    var difficulty: Double { min(1, max(0, elapsed / Self.round)) }
    var spawnInterval: TimeInterval { Self.spawnEasy - (Self.spawnEasy - Self.spawnHard) * difficulty }
    /// Points per second a new bubble rises at, before its own variation.
    var riseSpeed: Double { 38 + 42 * difficulty }

    /// Moves everything on by `dt` seconds (at most `maxStep`); nothing moves once the round is over.
    mutating func advance(by dt: TimeInterval) {
        guard !isOver, dt > 0 else { return }
        let step = min(dt, Self.maxStep, Self.round - elapsed)
        elapsed += step
        for i in bubbles.indices {
            bubbles[i].age += step
            bubbles[i].y -= bubbles[i].speed * step
            bubbles[i].x = bubbles[i].home + bubbles[i].sway * sin(bubbles[i].phase + bubbles[i].age * 1.7)
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

    /// A touch at `point`: the nearest bubble under it pops and its points are scored; `nil` when
    /// nothing was there.
    @discardableResult
    mutating func pop(at point: CGPoint) -> Int? {
        guard !isOver else { return nil }
        func distance(_ b: Bubble) -> Double {
            let dx = b.x - Double(point.x)
            let dy = b.y - Double(point.y)
            return (dx * dx + dy * dy).squareRoot()
        }
        let hit = bubbles.indices.filter { distance(bubbles[$0]) <= bubbles[$0].radius + Self.reach }
        guard let i = hit.min(by: { distance(bubbles[$0]) < distance(bubbles[$1]) }) else { return nil }
        let bubble = bubbles.remove(at: i)
        score += bubble.worth
        popped += 1
        splashes.append(Splash(x: bubble.x, y: bubble.y, radius: bubble.radius, hue: bubble.hue))
        return bubble.worth
    }

    private mutating func spawn() {
        let radius = Double.random(in: 13...30, using: &rng)
        let margin = radius + 6
        let width = Double(size.width)
        let home = width > 2 * margin ? Double.random(in: margin...(width - margin), using: &rng) : width / 2
        let speed = riseSpeed * Double.random(in: 0.8...1.25, using: &rng) * (28 / radius).squareRoot()
        let hue = Double.random(in: 0.52...0.72, using: &rng)
        bubbles.append(Bubble(id: nextID, home: home, x: home, y: Double(size.height) + radius, radius: radius, speed: speed,
                              sway: Double.random(in: 4...12, using: &rng), phase: Double.random(in: 0...(2 * .pi), using: &rng), hue: hue))
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
}
