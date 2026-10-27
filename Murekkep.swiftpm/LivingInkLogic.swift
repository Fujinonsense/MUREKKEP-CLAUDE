import Foundation

// Canlı mürekkep without its screen (checked in tools/gamescheck): a drawing on the pond wakes up
// where it was drawn and swims off. Foundation only.

/// One creature: the drawing in its own frame (the head toward +x, the middle of the drawing at the
/// origin) and how it is swimming.
struct InkCreature: Equatable {
    let id: Int
    /// The game ink it was drawn in (`GameCorner.inkHues`).
    let ink: Int
    let strokes: [[CGPoint]]
    /// The drawing's width along the body and its height.
    let length: Double
    let height: Double
    var position: CGPoint
    /// +1 swimming right, −1 swimming left.
    var facing: Double
    /// The nose down (positive, the screen's y runs down) or up, in radians, and where it is heading.
    var tilt = 0.0
    var aim = 0.0
    var speed = 0.0
    /// The body wave's phase.
    var phase = 0.0
    /// Seconds since it woke.
    var age = 0.0
    /// A turn round, 0 → 1: the drawing flattens to nothing half way and comes back the other way.
    var turn: Double?
    /// Seconds until it picks a new course, of a dash left after a poke, of joy after a meal.
    var wander = 1.0
    var dash = 0.0
    var joy = 0.0
    /// Fading out, 1 → 0, to make room for a ninth.
    var fade: Double?

    /// The drawing's x scale on screen: the facing, passing through 0 during a turn.
    var flip: Double { facing * cos(.pi * (turn ?? 0)) }

    /// Where its head is, on the pond.
    var head: CGPoint {
        let angle = flip >= 0 ? tilt : -tilt
        let reach = flip * length / 2
        return CGPoint(x: Double(position.x) + reach * cos(angle), y: Double(position.y) + reach * sin(angle))
    }
}

/// The pond: the creatures, the food sinking in it, the bubbles they breathe out.
struct InkPond: Equatable {
    struct Crumb: Equatable {
        let id: Int
        let home: Double
        var position: CGPoint
        var age = 0.0
    }

    struct Bubble: Equatable {
        let home: Double
        var position: CGPoint
        let radius: Double
        var age = 0.0
    }

    static let maxCreatures = 8
    /// How long the pencil must stay off the pond before a drawing wakes.
    static let wakeDelay = 0.8
    static let turnTime = 0.45
    static let fadeTime = 0.6
    static let sinkSpeed = 16.0
    static let riseSpeed = 22.0
    static let maxCrumbs = 12
    /// A creature keeps at most this many points; a busier drawing is thinned evenly.
    static let pointBudget = 600

    let size: CGSize
    private(set) var creatures: [InkCreature] = []
    private(set) var crumbs: [Crumb] = []
    private(set) var bubbles: [Bubble] = []
    /// Crumbs eaten so far.
    private(set) var meals = 0
    private var nextID = 1
    private var random: GameRandom

    init(size: CGSize, seed: UInt64) {
        self.size = size
        random = GameRandom(seed: seed)
    }

    var isStill: Bool { creatures.isEmpty && crumbs.isEmpty && bubbles.isEmpty }
    var awake: Int { creatures.filter { $0.fade == nil }.count }

    /// Wakes a drawing (strokes in pond points) as a creature in `ink`, exactly where it was drawn and
    /// facing the way it was drawn; with eight about already, the oldest fades out. Nil for a
    /// drawing of fewer than two points.
    @discardableResult
    mutating func wake(_ drawing: [[CGPoint]], ink: Int) -> Int? {
        let points = drawing.flatMap { $0 }
        guard points.count >= 2 else { return nil }
        let xs = points.map { Double($0.x) }
        let ys = points.map { Double($0.y) }
        let minX = xs.min() ?? 0
        let maxX = xs.max() ?? 0
        let minY = ys.min() ?? 0
        let maxY = ys.max() ?? 0
        let cx = (minX + maxX) / 2
        let cy = (minY + maxY) / 2
        let facing: Double = Self.facesRight(drawing) ? 1 : -1
        let strokes = Self.thinned(drawing.filter { !$0.isEmpty }, budget: Self.pointBudget).map { stroke in
            stroke.map { CGPoint(x: (Double($0.x) - cx) * facing, y: Double($0.y) - cy) }
        }
        if awake >= Self.maxCreatures, let oldest = creatures.firstIndex(where: { $0.fade == nil }) {
            creatures[oldest].fade = 1
        }
        let creature = InkCreature(id: nextID, ink: ink, strokes: strokes, length: max(maxX - minX, 1), height: max(maxY - minY, 1),
                                   position: CGPoint(x: cx, y: cy), facing: facing, wander: Double.random(in: 0.8...2, using: &random))
        nextID += 1
        creatures.append(creature)
        return creature.id
    }

    /// A poke at `point`: the creature there dashes off, turning away if the poke came from ahead.
    /// False when no creature is there.
    mutating func poke(at point: CGPoint) -> Bool {
        guard let i = creatures.indices.last(where: { i in
            let c = creatures[i]
            return c.fade == nil && Self.distance(c.position, point) < max(c.length, c.height) / 2 + 8
        }) else { return false }
        creatures[i].dash = 0.7
        let ahead = (Double(point.x) - Double(creatures[i].position.x)) * creatures[i].facing > 0
        if ahead, creatures[i].turn == nil { creatures[i].turn = 0 }
        creatures[i].aim = Double.random(in: -0.6...0.6, using: &random)
        return true
    }

    /// Four crumbs scattered along the top, sinking slowly (twelve in the water at most).
    mutating func feed() {
        let width = Double(size.width)
        for _ in 0..<min(4, Self.maxCrumbs - crumbs.count) {
            let x = Double.random(in: (width * 0.15)...(width * 0.85), using: &random)
            crumbs.append(Crumb(id: nextID, home: x, position: CGPoint(x: x, y: -4)))
            nextID += 1
        }
    }

    /// Moves the pond on by `dt` seconds (a gap longer than a tenth of a second counts as a tenth).
    mutating func advance(by dt: Double) {
        guard dt > 0 else { return }
        let step = min(dt, 0.1)
        let width = Double(size.width)
        let height = Double(size.height)
        for i in crumbs.indices {
            crumbs[i].age += step
            let y = min(height - 6, Double(crumbs[i].position.y) + Self.sinkSpeed * step)
            let sway = y < height - 6 ? 3 * sin(crumbs[i].age * 2.1 + crumbs[i].home) : 0
            crumbs[i].position = CGPoint(x: crumbs[i].home + sway, y: y)
        }
        var eaten: Set<Int> = []
        for i in creatures.indices {
            var c = creatures[i]
            c.age += step
            c.wander -= step
            c.dash = max(0, c.dash - step)
            c.joy = max(0, c.joy - step)
            if let t = c.turn {
                if t + step / Self.turnTime >= 1 {
                    c.facing = -c.facing
                    c.turn = nil
                } else {
                    c.turn = t + step / Self.turnTime
                }
            }
            var hurry = 1.0
            var chasing = false
            let head = c.head
            if c.fade == nil, let food = crumbs.filter({ !eaten.contains($0.id) }).min(by: { Self.distance($0.position, head) < Self.distance($1.position, head) }) {
                let dx = Double(food.position.x) - Double(head.x)
                let dy = Double(food.position.y) - Double(head.y)
                if dx * c.facing < -c.length * 0.25 {
                    if c.turn == nil { c.turn = 0 }
                } else {
                    chasing = true
                }
                c.aim = max(-0.8, min(0.8, atan2(dy, abs(dx) + 1)))
                hurry = 1.7
                if (dx * dx + dy * dy).squareRoot() < max(10, c.height * 0.4) {
                    eaten.insert(food.id)
                    c.joy = 1.2
                    meals += 1
                }
            } else if c.wander <= 0 {
                c.aim = Double.random(in: -0.45...0.45, using: &random)
                c.wander = Double.random(in: 1.5...4, using: &random)
                if c.turn == nil, Double.random(in: 0..<1, using: &random) < 0.12 { c.turn = 0 }
            }
            // Turn round before a wall and level off near the top and the bottom, unless food lies
            // ahead (the pond's edge stops it anyway); a creature as big as the pond keeps a middle third.
            let x = Double(c.position.x)
            let y = Double(c.position.y)
            if !chasing {
                let side = min(max(24, c.length / 2 + 6), width * 0.35)
                let edge = min(max(18, c.height / 2 + 6), height * 0.35)
                if c.turn == nil, (c.facing > 0 && x > width - side) || (c.facing < 0 && x < side) { c.turn = 0 }
                if y < edge { c.aim = max(c.aim, 0.35) }
                if y > height - edge { c.aim = min(c.aim, -0.35) }
            }
            c.tilt += (c.aim - c.tilt) * min(1, step * 1.8)
            let cruise = 18 + 700 / (c.length + 30)
            let goal = cruise * hurry * (c.dash > 0 ? 2.6 : 1) * min(1, c.age / 0.8)
            c.speed += (goal - c.speed) * min(1, step * 2.5)
            let ahead = cos(.pi * (c.turn ?? 0))
            c.position = CGPoint(x: min(width, max(0, x + c.facing * c.speed * ahead * cos(c.tilt) * step)),
                                 y: min(height, max(0, y + c.speed * abs(ahead) * sin(c.tilt) * step)))
            c.phase = (c.phase + 2 * .pi * (0.9 + c.speed / 35) * (1 + 0.5 * c.joy) * step).truncatingRemainder(dividingBy: 2 * .pi)
            if let f = c.fade { c.fade = f - step / Self.fadeTime }
            // Now and then a bubble from the mouth.
            if c.fade == nil, Double.random(in: 0..<1, using: &random) < 0.25 * step {
                let mouth = c.head
                bubbles.append(Bubble(home: Double(mouth.x), position: mouth, radius: Double.random(in: 1.5...3, using: &random)))
            }
            creatures[i] = c
        }
        creatures.removeAll { ($0.fade ?? 1) <= 0 }
        crumbs.removeAll { eaten.contains($0.id) }
        for i in bubbles.indices {
            bubbles[i].age += step
            let y = Double(bubbles[i].position.y) - Self.riseSpeed * step
            bubbles[i].position = CGPoint(x: bubbles[i].home + 2 * sin(bubbles[i].age * 5), y: y)
        }
        bubbles.removeAll { $0.age > 3 || Double($0.position.y) < -5 }
    }

    // MARK: Drawing

    /// A creature's strokes as they are drawn now, in pond points: bent by the wave that runs from
    /// its head to its tail, turned by its tilt and flipped by its facing. Just woken it is exactly
    /// the drawing; over its first second it shakes itself awake.
    static func pose(_ c: InkCreature) -> [[CGPoint]] {
        let flip = c.flip
        let angle = flip >= 0 ? c.tilt : -c.tilt
        let cosA = cos(angle)
        let sinA = sin(angle)
        let waking = min(1, c.age / 0.2)
        let shake = 1 + 1.6 * exp(-2.5 * c.age)
        let amplitude = (0.05 * c.length + 1.2) * waking * shake * (1 + 0.6 * min(1, c.joy))
        let px = Double(c.position.x)
        let py = Double(c.position.y)
        let half = c.length / 2
        return c.strokes.map { stroke in
            stroke.map { p in
                let x = Double(p.x)
                let u = min(1, max(0, (half - x) / c.length))
                let bend = amplitude * (0.15 + 0.85 * u * u) * sin(c.phase - 2 * .pi * 0.9 * u)
                let sx = x * flip
                let sy = Double(p.y) + bend
                return CGPoint(x: px + sx * cosA - sy * sinA, y: py + sx * sinA + sy * cosA)
            }
        }
    }

    /// Which way a drawing faces. A fish's tail fin stands taller than its snout, so the end whose
    /// outer eighth is taller is the tail; when the ends are alike, the drawing began at its head
    /// (a mouth is usually drawn first).
    static func facesRight(_ strokes: [[CGPoint]]) -> Bool {
        let points = strokes.flatMap { $0 }
        guard let first = points.first else { return true }
        let xs = points.map { Double($0.x) }
        let minX = xs.min() ?? 0
        let maxX = xs.max() ?? 0
        let width = maxX - minX
        guard width > 1 else { return true }
        func tallness(from lo: Double, to hi: Double) -> Double {
            let ys = points.filter { Double($0.x) >= lo && Double($0.x) <= hi }.map { Double($0.y) }
            guard let top = ys.min(), let bottom = ys.max() else { return 0 }
            return bottom - top
        }
        let left = tallness(from: minX, to: minX + width / 8)
        let right = tallness(from: maxX - width / 8, to: maxX)
        if right > left * 1.3 + 1 { return false }
        if left > right * 1.3 + 1 { return true }
        return Double(first.x) > minX + width / 2
    }

    /// The strokes with points at least `gap` apart (the ends kept), the gap doubling until the
    /// drawing fits in `budget` points.
    static func thinned(_ strokes: [[CGPoint]], budget: Int) -> [[CGPoint]] {
        var gap = 1.5
        var out = strokes
        while out.reduce(0, { $0 + $1.count }) > budget, gap < 1000 {
            out = strokes.map { stroke in
                guard let first = stroke.first, stroke.count > 2 else { return stroke }
                var kept = [first]
                for p in stroke.dropFirst().dropLast() where distance(p, kept[kept.count - 1]) >= gap {
                    kept.append(p)
                }
                kept.append(stroke[stroke.count - 1])
                return kept
            }
            gap *= 2
        }
        return out
    }

    static func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
        let dx = Double(a.x) - Double(b.x)
        let dy = Double(a.y) - Double(b.y)
        return (dx * dx + dy * dy).squareRoot()
    }
}
