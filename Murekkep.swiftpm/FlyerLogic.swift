import Foundation

// Uçan damla, without its screen (checked in tools/gamescheck): an ink drop kept aloft with taps
// glides past standing pencils and hanging rulers; a level is a stretch of them with a flag at its
// end. Three drops a level; the stars at the flag are the drops left. From level 5 some gaps drift
// up and down. The endless flight has no flag: it speeds up and narrows as it goes, and its score
// is the pencils passed. Foundation only.

/// How a level flies: set by the difficulty, tightened a little with every level.
struct FlyerSettings: Equatable {
    /// Points per second the pencils come at.
    var speed: Double
    /// Points between a pencil's tip and the ruler's end.
    var gap: Double
    /// Points per second squared.
    var gravity: Double
    /// Points per second upwards on a tap.
    var flap: Double
    /// Points between one obstacle and the next.
    var spacing: Double

    static func settings(difficulty: GameDifficulty, level: Int) -> FlyerSettings {
        let step = Double(max(0, level - 1))
        switch difficulty {
        case .easy: return FlyerSettings(speed: 105 + 3 * step, gap: max(122, 150 - 2 * step), gravity: 880, flap: 300, spacing: 230)
        case .medium: return FlyerSettings(speed: 135 + 4 * step, gap: max(106, 128 - 2 * step), gravity: 1080, flap: 330, spacing: 215)
        case .hard: return FlyerSettings(speed: 160 + 5 * step, gap: max(100, 116 - 2 * step), gravity: 1200, flap: 340, spacing: 200)
        }
    }
}

/// A standing pencil with a ruler hanging over it (or the other way round), and the gap between.
struct FlyerObstacle: Equatable {
    enum Kind: Equatable {
        /// The pencil stands from the floor, the ruler hangs from the top.
        case pencilBelow
        /// The pencil hangs tip down, the ruler stands.
        case pencilAbove
    }

    static let width = 26.0

    let id: Int
    /// Its centre, points from the left.
    var x: Double
    /// The centre of the gap, points from the top.
    var gapY: Double
    let gap: Double
    let kind: Kind
    var passed = false
    /// A drifting gap swings `drift` points either side of `home`, `pace` radians a second.
    var drift = 0.0
    var home = 0.0
    var pace = 0.0

    var top: Double { gapY - gap / 2 }
    var bottom: Double { gapY + gap / 2 }

    /// Where a drifting gap stands after `time` seconds of flight (each starts at its own point of the swing).
    func driftedY(at time: TimeInterval) -> Double {
        home + drift * sin(pace * time + Double(id))
    }
}

/// One level of the flyer in a field `size` big, or the endless flight, stepped by `advance(by:)`.
struct FlyerWorld: Equatable {
    enum Phase: Equatable {
        case ready, flying, complete, failed
    }

    static let levels = 12
    static let lives = 3
    static let dropRadius = 9.0
    /// The drop flies a third of the way in from the left.
    static let dropXFraction = 0.3
    /// After a hit the drop is safe for a moment, to find the gap again.
    static let grace: TimeInterval = 1.2
    static let maxStep: TimeInterval = 0.1
    static let terminalFall = 520.0
    /// The room a gap keeps from the top and the bottom of the page.
    static let margin = 30.0

    let size: CGSize
    let level: Int
    let settings: FlyerSettings
    /// The endless flight: no flag, faster and narrower with every pencil passed.
    let endless: Bool
    /// Obstacles in the level (none counted in the endless flight).
    let goal: Int
    private(set) var phase: Phase = .ready
    private(set) var dropY: Double
    private(set) var velocity = 0.0
    private(set) var obstacles: [FlyerObstacle]
    private(set) var flagX: Double
    private(set) var passed = 0
    private(set) var lives = FlyerWorld.lives
    private(set) var graceLeft: TimeInterval = 0
    private(set) var elapsed: TimeInterval = 0
    /// How far the page has scrolled by (for the clouds behind).
    private(set) var distance = 0.0
    /// How far the drifting gaps swing at this difficulty.
    private let driftScale: Double
    private var rng: GameRandom
    private var lastGapY: Double
    private var made = 0

    static func goal(level: Int) -> Int { 6 + 2 * max(0, level - 1) }

    var dropX: Double { Double(size.width) * Self.dropXFraction }
    var stars: Int { phase == .complete ? lives : 0 }
    var isOver: Bool { phase == .complete || phase == .failed }
    /// The way to the flag, 0…1 (always 0 in the endless flight).
    var progress: Double { goal > 0 ? min(1, Double(passed) / Double(goal)) : 0 }
    /// Points per second the page goes by: the endless flight gains 1.5 for every pencil passed, 70 at most.
    var speed: Double { endless ? settings.speed + min(70, 1.5 * Double(passed)) : settings.speed }

    init(size: CGSize, level: Int, difficulty: GameDifficulty, seed: UInt64, endless: Bool = false) {
        self.size = size
        self.level = level
        self.endless = endless
        settings = FlyerSettings.settings(difficulty: difficulty, level: endless ? 1 : level)
        goal = endless ? 0 : Self.goal(level: level)
        dropY = Double(size.height) / 2
        switch difficulty {
        case .easy: driftScale = 0.7
        case .medium: driftScale = 1
        case .hard: driftScale = 1.15
        }
        rng = GameRandom(seed: seed)
        lastGapY = Double(size.height) / 2
        obstacles = []
        flagX = .infinity
        let start = Double(size.width) + 140
        for i in 0..<(endless ? 4 : goal) {
            obstacles.append(makeObstacle(at: start + Double(i) * settings.spacing))
        }
        if !endless {
            flagX = start + Double(goal) * settings.spacing
        }
    }

    /// The next pencil, at `x`, its gap within reach of the last one. From level 5 every third gap
    /// drifts and from level 9 every other (in the endless flight after 12 and after 30 pencils),
    /// swinging further level by level but never off the page.
    private mutating func makeObstacle(at x: Double) -> FlyerObstacle {
        let height = Double(size.height)
        let i = made
        made += 1
        let gap = endless ? max(settings.gap - 18, settings.gap - 0.6 * Double(i)) : settings.gap
        let low = Self.margin + gap / 2
        let high = max(low, height - Self.margin - gap / 2)
        let reach = 0.38 * height
        let lower = max(low, lastGapY - reach)
        let upper = max(lower, min(high, lastGapY + reach))
        let y = Double.random(in: lower...upper, using: &rng)
        lastGapY = y
        var obstacle = FlyerObstacle(id: i, x: x, gapY: y, gap: gap, kind: i % 2 == 0 ? .pencilBelow : .pencilAbove)
        let stage = endless ? (i >= 30 ? 2 : i >= 12 ? 1 : 0) : (level >= 9 ? 2 : level >= 5 ? 1 : 0)
        let drifts = stage == 2 ? i % 2 == 1 : stage == 1 && i % 3 == 2
        if drifts {
            let steps = Double(max(0, (endless ? i / 4 : level) - 5))
            obstacle.drift = min(0.16 * height, (14 + 4 * steps) * driftScale, y - low, high - y)
            obstacle.home = y
            obstacle.pace = 0.9 + 0.05 * steps
            obstacle.gapY = obstacle.driftedY(at: elapsed)
        }
        return obstacle
    }

    /// A tap: the drop rises; the first one starts the flight.
    mutating func flap() {
        guard phase == .ready || phase == .flying else { return }
        phase = .flying
        velocity = -settings.flap
    }

    mutating func advance(by dt: TimeInterval) {
        guard phase == .flying, dt > 0 else { return }
        let step = min(dt, Self.maxStep)
        elapsed += step
        graceLeft = max(0, graceLeft - step)
        velocity = min(velocity + settings.gravity * step, Self.terminalFall)
        dropY += velocity * step
        if dropY < Self.dropRadius {
            dropY = Self.dropRadius
            velocity = 0
        }
        let shift = speed * step
        distance += shift
        for i in obstacles.indices {
            obstacles[i].x -= shift
            if obstacles[i].drift > 0 {
                obstacles[i].gapY = obstacles[i].driftedY(at: elapsed)
            }
            if !obstacles[i].passed, obstacles[i].x + FlyerObstacle.width / 2 < dropX - Self.dropRadius {
                obstacles[i].passed = true
                passed += 1
            }
        }
        if endless {
            // Pencils behind the drop go; new ones come in at the right, one spacing apart.
            obstacles.removeAll { $0.x < -60 }
            var edge = obstacles.last?.x ?? Double(size.width) + 140 - settings.spacing
            while edge < Double(size.width) + settings.spacing {
                edge += settings.spacing
                obstacles.append(makeObstacle(at: edge))
            }
        }
        flagX -= shift
        if flagX <= dropX {
            phase = .complete
            return
        }
        let floor = Double(size.height) - Self.dropRadius
        if dropY >= floor {
            dropY = floor
            // The floor costs a drop, but not again while the drop is still finding its way.
            if graceLeft > 0 {
                velocity = -settings.flap * 0.9
            } else {
                hit()
            }
            return
        }
        if graceLeft == 0, obstacles.contains(where: collides) {
            hit()
        }
    }

    /// The drop against the pencil or the ruler of `obstacle`; a little forgiving at the edges.
    func collides(_ obstacle: FlyerObstacle) -> Bool {
        let r = Self.dropRadius - 1.5
        let half = FlyerObstacle.width / 2
        guard abs(obstacle.x - dropX) < half + r else { return false }
        // The nearest point of each bar to the drop's centre.
        func touches(top: Double, bottom: Double) -> Bool {
            let cx = min(max(dropX, obstacle.x - half), obstacle.x + half)
            let cy = min(max(dropY, top), bottom)
            let dx = dropX - cx
            let dy = dropY - cy
            return dx * dx + dy * dy < r * r
        }
        return touches(top: 0, bottom: obstacle.top) || touches(top: obstacle.bottom, bottom: Double(size.height))
    }

    private mutating func hit() {
        lives -= 1
        if lives <= 0 {
            phase = .failed
            return
        }
        graceLeft = Self.grace
        velocity = -settings.flap * 0.9
    }
}
