import Foundation

// Ebru, the Turkish art of marbling on water, without its screen (checked in tools/gamescheck).
// Foundation only. Every colour on the tray is a closed outline, and the moves are the closed-form
// marbling maps (Lu, Jaffer et al., "Mathematical Marbling", IEEE CG&A 2012): paint is pushed and
// pulled but never squeezed, so a drop keeps its area however it is combed.

/// One move on the water. A `shift` may be negative: the tine is drawn the other way.
enum EbruMove: Equatable {
    /// A drop lands at `centre`: the paint already there is pushed out in rings,
    /// p' = c + (p − c)·√(1 + r²/|p − c|²), and the drop is a circle of `radius`.
    case drop(centre: CGPoint, radius: Double, pigment: Int)
    /// A drop on the water spreads: everything is pushed as by a ring of `radius` more, so a circle
    /// of radius r around `centre` becomes one of √(r² + radius²).
    case spread(centre: CGPoint, radius: Double)
    /// A straight tine through `through`, drawn along the unit vector `direction`: each point moves
    /// along it by `shift`·λ/(d + λ), d its distance from the tine and λ the `sharpness`.
    case line(through: CGPoint, direction: CGPoint, shift: Double, sharpness: Double)
    /// A comb: tines `spacing` apart, one through `through`, all drawn along `direction`; d is the
    /// distance to the nearest tine.
    case comb(through: CGPoint, direction: CGPoint, spacing: Double, shift: Double, sharpness: Double)
    /// A wavy tine along `direction` through `through`, swinging `amplitude` to either side every
    /// `period` points.
    case wave(through: CGPoint, direction: CGPoint, amplitude: Double, period: Double, shift: Double, sharpness: Double)
    /// A swirl: points turn around `centre` by `angle`·e^(−r²/reach²).
    case swirl(centre: CGPoint, angle: Double, reach: Double)
    /// One step of the needle (biz) to `tip`: paint near it moves by `step`·κ·e^(−d²/reach²).
    case needle(tip: CGPoint, step: CGPoint, reach: Double)
    /// One step of the comb (tarak): its tines stand `spacing` apart on the line through `tip`
    /// across `step`, and paint near a tine moves like paint near the needle.
    case combStep(tip: CGPoint, step: CGPoint, spacing: Double, reach: Double)
}

/// What the pencil does on the water.
enum EbruTool: String, CaseIterable, Identifiable {
    /// Drops paint; held still, the drop keeps spreading; moved, it leaves a trail of drops.
    case drop
    /// The needle (biz): drags the paint along its path.
    case needle
    /// The comb (tarak): tines across the whole tray, pulled along the first movement's axis.
    case comb

    var id: String { rawValue }
}

/// The traditional patterns, played over the paint already on the tray.
enum EbruPattern: String, CaseIterable, Identifiable {
    /// Gel-git: the needle back and forth across the tray in parallel lines.
    case gelgit
    /// A fine comb drawn down the tray.
    case tarakli
    /// Şal: wavy lines down and up the tray.
    case sal
    /// Bülbül yuvası (nightingale's nest): small spirals in staggered rows.
    case bulbul

    var id: String { rawValue }
}

/// The ebru tray: the paint on the water, the moves still to play, and what the pencil is doing.
struct EbruTray: Equatable {
    /// One colour on the water: a closed outline and its place in the palette.
    struct Paint: Equatable {
        let pigment: Int
        var outline: [CGPoint]
    }

    /// Outlines are refined to edges this long while the tray holds fewer than `budget` points,
    /// to edges twice as long below 1.5 × `budget`, and not at all above that.
    static let edge = 3.0
    static let budget = 60_000
    /// A touch's drop, a trail's drops, and the largest a held drop grows.
    static let dropStart = 9.0
    static let trailDrop = 6.0
    static let trailGap = 16.0
    static let dropLimit = 60.0
    /// How fast a held drop spreads (its radius² grows by this many points² a second).
    static let spreadRate = 900.0
    /// The needle's and the comb's reach, the comb's tine spacing, and how much of a step the
    /// paint right at a tip follows (the rest slips behind, so a stroke leaves a tapering tongue).
    static let needleReach = 9.0
    static let combReach = 6.0
    static let combSpacing = 20.0
    static let follow = 0.85
    /// The longest step a dragged tool takes at once.
    static let step = 3.0
    /// How many undo steps are kept.
    static let historyLimit = 10

    let size: CGSize
    private(set) var paints: [Paint] = []
    /// Moves still to play: a sprinkle or a pattern, one at every frame.
    private(set) var pending: [EbruMove] = []
    private var history: [[Paint]] = []
    private var touch: Touch?
    private var random: GameRandom

    private struct Touch: Equatable {
        let tool: EbruTool
        let pigment: Int
        let start: CGPoint
        var last: CGPoint
        /// The comb's axis, once the pencil has moved far enough to tell: true along x.
        var combAlongX: Bool?
        /// The drop under the pencil and how far it has spread.
        var drop: CGPoint?
        var radius = 0.0
    }

    init(size: CGSize, seed: UInt64) {
        self.size = size
        random = GameRandom(seed: seed)
    }

    var pointCount: Int { paints.reduce(0) { $0 + $1.outline.count } }
    var isPlaying: Bool { !pending.isEmpty }
    var canUndo: Bool { !history.isEmpty }
    /// True while a drop is under the pencil.
    var isHoldingDrop: Bool { touch?.drop != nil }
    /// True while the drop under the pencil can still spread (it stops at `dropLimit`).
    var isSpreading: Bool {
        guard let t = touch, t.drop != nil else { return false }
        return t.radius < Self.dropLimit
    }

    // MARK: The pencil

    /// The pencil touches the water. Moves still playing finish first, and the tray is kept for undo.
    mutating func touchBegan(at point: CGPoint, tool: EbruTool, pigment: Int) {
        finish()
        remember()
        touch = Touch(tool: tool, pigment: pigment, start: point, last: point)
        if tool == .drop {
            apply(.drop(centre: point, radius: Self.dropStart, pigment: pigment))
            touch?.drop = point
            touch?.radius = Self.dropStart
        }
    }

    mutating func touchMoved(to point: CGPoint) {
        guard var t = touch else { return }
        switch t.tool {
        case .drop:
            guard let centre = t.drop, Self.distance(centre, point) > Self.trailGap else { return }
            apply(.drop(centre: point, radius: Self.trailDrop, pigment: t.pigment))
            t.drop = point
            t.radius = Self.trailDrop
        case .needle:
            for (tip, step) in Self.steps(from: t.last, to: point) {
                apply(.needle(tip: tip, step: step, reach: Self.needleReach))
            }
        case .comb:
            if t.combAlongX == nil {
                let dx = Double(point.x) - Double(t.start.x)
                let dy = Double(point.y) - Double(t.start.y)
                guard dx * dx + dy * dy >= 36 else { return }
                t.combAlongX = abs(dx) >= abs(dy)
            }
            // The comb runs on a rail: only the movement along its axis counts, and its tines stay on
            // the line through where the pencil came down.
            let alongX = t.combAlongX == true
            let from = alongX ? CGPoint(x: t.last.x, y: t.start.y) : CGPoint(x: t.start.x, y: t.last.y)
            let to = alongX ? CGPoint(x: point.x, y: t.start.y) : CGPoint(x: t.start.x, y: point.y)
            for (tip, step) in Self.steps(from: from, to: to) {
                apply(.combStep(tip: tip, step: step, spacing: Self.combSpacing, reach: Self.combReach))
            }
        }
        t.last = point
        touch = t
    }

    /// Time passes with the pencil down: the drop under it keeps spreading, up to `dropLimit`
    /// (a gap longer than a tenth of a second counts as a tenth). False when nothing changed.
    @discardableResult
    mutating func hold(for seconds: Double) -> Bool {
        guard var t = touch, let centre = t.drop, seconds > 0 else { return false }
        let grown = min(Self.dropLimit, (t.radius * t.radius + Self.spreadRate * min(seconds, 0.1)).squareRoot())
        guard grown > t.radius else { return false }
        apply(.spread(centre: centre, radius: (grown * grown - t.radius * t.radius).squareRoot()))
        t.radius = grown
        touch = t
        return true
    }

    mutating func touchEnded() {
        touch = nil
    }

    // MARK: Sprinkles, patterns, undo

    /// Battal: about thirty drops of `pigment` over the whole tray (more on a larger one), each a
    /// move of its own so they fall one by one.
    mutating func sprinkle(pigment: Int) {
        finish()
        remember()
        let area = Double(size.width) * Double(size.height)
        let count = max(20, min(60, Int((34 * area / (316 * 260)).rounded())))
        for _ in 0..<count {
            let x = Double.random(in: -10...(Double(size.width) + 10), using: &random)
            let y = Double.random(in: -10...(Double(size.height) + 10), using: &random)
            let radius = Double.random(in: 10...22, using: &random)
            pending.append(.drop(centre: CGPoint(x: x, y: y), radius: radius, pigment: pigment))
        }
    }

    /// Queues a traditional pattern over the paint on the tray.
    mutating func play(_ pattern: EbruPattern) {
        finish()
        remember()
        pending += Self.moves(for: pattern, size: size)
    }

    /// Plays up to `count` waiting moves; false when there were none.
    @discardableResult
    mutating func advance(moves count: Int = 1) -> Bool {
        guard !pending.isEmpty else { return false }
        let n = min(max(1, count), pending.count)
        for move in pending.prefix(n) {
            apply(move)
        }
        pending.removeFirst(n)
        return true
    }

    /// Plays every waiting move now.
    mutating func finish() {
        let moves = pending
        pending = []
        for move in moves {
            apply(move)
        }
    }

    /// Back to the tray before the last touch, sprinkle or pattern (a pattern still playing stops).
    mutating func undo() {
        guard let last = history.popLast() else { return }
        pending = []
        touch = nil
        paints = last
    }

    private mutating func remember() {
        history.append(paints)
        if history.count > Self.historyLimit {
            history.removeFirst(history.count - Self.historyLimit)
        }
    }

    // MARK: Moves

    /// Moves every outline by `move`, refines the stretched edges, lets go of paint pushed wholly off
    /// the tray, and adds the drop's circle for a drop.
    mutating func apply(_ move: EbruMove) {
        let map = Self.map(move)
        let edge = refineEdge
        var kept: [Paint] = []
        kept.reserveCapacity(paints.count + 1)
        for paint in paints {
            let outline = Self.moved(paint.outline, by: map, edge: edge)
            if Self.overlapsTray(outline, size: size) {
                kept.append(Paint(pigment: paint.pigment, outline: outline))
            }
        }
        if case let .drop(centre, radius, pigment) = move {
            kept.append(Paint(pigment: pigment, outline: Self.circle(around: centre, radius: radius)))
        }
        paints = kept
    }

    private var refineEdge: Double? {
        let count = pointCount
        if count < Self.budget { return Self.edge }
        if count < Self.budget * 3 / 2 { return Self.edge * 2 }
        return nil
    }

    /// Where a move takes a point of the water.
    static func map(_ move: EbruMove) -> (CGPoint) -> CGPoint {
        switch move {
        case let .drop(centre, radius, _), let .spread(centre, radius):
            let cx = Double(centre.x)
            let cy = Double(centre.y)
            let r2 = radius * radius
            return { p in
                let dx = Double(p.x) - cx
                let dy = Double(p.y) - cy
                let d2 = dx * dx + dy * dy
                guard d2 > 1e-12 else { return CGPoint(x: cx + radius, y: cy) }
                let k = (1 + r2 / d2).squareRoot()
                return CGPoint(x: cx + dx * k, y: cy + dy * k)
            }
        case let .line(through, direction, shift, sharpness):
            let qx = Double(through.x)
            let qy = Double(through.y)
            let mx = Double(direction.x)
            let my = Double(direction.y)
            return { p in
                let px = Double(p.x)
                let py = Double(p.y)
                let d = abs((px - qx) * -my + (py - qy) * mx)
                let z = shift * sharpness / (d + sharpness)
                return CGPoint(x: px + z * mx, y: py + z * my)
            }
        case let .comb(through, direction, spacing, shift, sharpness):
            let qx = Double(through.x)
            let qy = Double(through.y)
            let mx = Double(direction.x)
            let my = Double(direction.y)
            return { p in
                let px = Double(p.x)
                let py = Double(p.y)
                let d = nearestTine((px - qx) * -my + (py - qy) * mx, spacing: spacing)
                let z = shift * sharpness / (d + sharpness)
                return CGPoint(x: px + z * mx, y: py + z * my)
            }
        case let .wave(through, direction, amplitude, period, shift, sharpness):
            let qx = Double(through.x)
            let qy = Double(through.y)
            let mx = Double(direction.x)
            let my = Double(direction.y)
            // The water is sheared so the wave lies straight, combed by a straight tine and sheared
            // back: three area-keeping maps, so the paint keeps its area here too.
            return { p in
                let px = Double(p.x) - qx
                let py = Double(p.y) - qy
                let along = px * mx + py * my
                let straight = px * -my + py * mx - amplitude * sin(2 * .pi * along / period)
                let moved = along + shift * sharpness / (abs(straight) + sharpness)
                let across = straight + amplitude * sin(2 * .pi * moved / period)
                return CGPoint(x: qx + moved * mx - across * my, y: qy + moved * my + across * mx)
            }
        case let .swirl(centre, angle, reach):
            let cx = Double(centre.x)
            let cy = Double(centre.y)
            let r2 = reach * reach
            return { p in
                let dx = Double(p.x) - cx
                let dy = Double(p.y) - cy
                let d2 = dx * dx + dy * dy
                guard d2 < 9 * r2 else { return p }
                let a = angle * exp(-d2 / r2)
                let c = cos(a)
                let s = sin(a)
                return CGPoint(x: cx + dx * c - dy * s, y: cy + dx * s + dy * c)
            }
        case let .needle(tip, step, reach):
            let tx = Double(tip.x)
            let ty = Double(tip.y)
            let sx = Double(step.x)
            let sy = Double(step.y)
            let r2 = reach * reach
            return { p in
                let px = Double(p.x)
                let py = Double(p.y)
                let d2 = (px - tx) * (px - tx) + (py - ty) * (py - ty)
                guard d2 < 9 * r2 else { return p }
                let k = follow * exp(-d2 / r2)
                return CGPoint(x: px + sx * k, y: py + sy * k)
            }
        case let .combStep(tip, step, spacing, reach):
            let tx = Double(tip.x)
            let ty = Double(tip.y)
            let sx = Double(step.x)
            let sy = Double(step.y)
            let length = (sx * sx + sy * sy).squareRoot()
            guard length > 0 else { return { $0 } }
            let mx = sx / length
            let my = sy / length
            let r2 = reach * reach
            return { p in
                let px = Double(p.x)
                let py = Double(p.y)
                let along = (px - tx) * mx + (py - ty) * my
                guard abs(along) < 3 * reach else { return p }
                let across = nearestTine((px - tx) * -my + (py - ty) * mx, spacing: spacing)
                let k = follow * exp(-(along * along + across * across) / r2)
                return CGPoint(x: px + sx * k, y: py + sy * k)
            }
        }
    }

    /// The moves of a pattern for a tray of `size`: each tine or swirl in a few parts, so the pattern
    /// can be watched as it is drawn (a tine's or a swirl's parts add up exactly to the whole).
    static func moves(for pattern: EbruPattern, size: CGSize) -> [EbruMove] {
        let width = Double(size.width)
        let height = Double(size.height)
        var moves: [EbruMove] = []
        switch pattern {
        case .gelgit:
            var y = 11.0
            var sign = 1.0
            while y < height {
                for _ in 0..<4 {
                    moves.append(.line(through: CGPoint(x: 0, y: y), direction: CGPoint(x: 1, y: 0), shift: sign * 9, sharpness: 10))
                }
                sign = -sign
                y += 22
            }
        case .tarakli:
            for _ in 0..<6 {
                moves.append(.comb(through: .zero, direction: CGPoint(x: 0, y: 1), spacing: 12, shift: 5, sharpness: 6))
            }
        case .sal:
            var x = 11.0
            var sign = 1.0
            while x < width {
                for _ in 0..<3 {
                    moves.append(.wave(through: CGPoint(x: x, y: 0), direction: CGPoint(x: 0, y: 1), amplitude: 7, period: 60,
                                       shift: sign * 26 / 3, sharpness: 8))
                }
                sign = -sign
                x += 22
            }
        case .bulbul:
            var y = 30.0
            var row = 0
            while y < height + 10 {
                var x = row % 2 == 0 ? 30.0 : 57.5
                while x < width + 10 {
                    for _ in 0..<3 {
                        moves.append(.swirl(centre: CGPoint(x: x, y: y), angle: 2.6 * .pi / 3, reach: 20))
                    }
                    x += 55
                }
                y += 55
                row += 1
            }
        }
        return moves
    }

    // MARK: Geometry

    /// The distance from a point at `across` (measured across the tines from one of them) to the
    /// nearest tine `spacing` apart.
    static func nearestTine(_ across: Double, spacing: Double) -> Double {
        var r = across.truncatingRemainder(dividingBy: spacing)
        if r < 0 { r += spacing }
        return min(r, spacing - r)
    }

    /// An outline moved point by point; an edge stretched past `edge` gets the moved images of
    /// points along its original, so curves stay curves (at most 32 to an edge).
    static func moved(_ outline: [CGPoint], by map: (CGPoint) -> CGPoint, edge: Double?) -> [CGPoint] {
        let images = outline.map(map)
        guard let edge, images.count > 1 else { return images }
        var out: [CGPoint] = []
        out.reserveCapacity(images.count + images.count / 4)
        for i in images.indices {
            let j = i + 1 == images.count ? 0 : i + 1
            let a = images[i]
            out.append(a)
            let length = distance(a, images[j])
            guard length > edge else { continue }
            let parts = min(32, Int((length / edge).rounded(.up)))
            let s = outline[i]
            let e = outline[j]
            for k in 1..<parts {
                let t = Double(k) / Double(parts)
                out.append(map(CGPoint(x: Double(s.x) + (Double(e.x) - Double(s.x)) * t,
                                       y: Double(s.y) + (Double(e.y) - Double(s.y)) * t)))
            }
        }
        return out
    }

    /// A drop's circle: points about `edge` apart, never fewer than 24.
    static func circle(around centre: CGPoint, radius: Double) -> [CGPoint] {
        let n = max(24, Int((2 * .pi * radius / edge).rounded(.up)))
        return (0..<n).map { i in
            let a = 2 * .pi * Double(i) / Double(n)
            return CGPoint(x: Double(centre.x) + radius * cos(a), y: Double(centre.y) + radius * sin(a))
        }
    }

    /// The steps of at most `step` points from `a` to `b`: each step's end and its movement.
    static func steps(from a: CGPoint, to b: CGPoint) -> [(tip: CGPoint, step: CGPoint)] {
        let dx = Double(b.x) - Double(a.x)
        let dy = Double(b.y) - Double(a.y)
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 0 else { return [] }
        let n = max(1, Int((length / step).rounded(.up)))
        let sx = dx / Double(n)
        let sy = dy / Double(n)
        return (1...n).map { i in
            (tip: CGPoint(x: Double(a.x) + sx * Double(i), y: Double(a.y) + sy * Double(i)), step: CGPoint(x: sx, y: sy))
        }
    }

    /// The area inside a closed outline (shoelace).
    static func area(of outline: [CGPoint]) -> Double {
        guard outline.count > 2 else { return 0 }
        var sum = 0.0
        for i in outline.indices {
            let a = outline[i]
            let b = outline[i + 1 == outline.count ? 0 : i + 1]
            sum += Double(a.x) * Double(b.y) - Double(b.x) * Double(a.y)
        }
        return abs(sum) / 2
    }

    static func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
        let dx = Double(a.x) - Double(b.x)
        let dy = Double(a.y) - Double(b.y)
        return (dx * dx + dy * dy).squareRoot()
    }

    private static func overlapsTray(_ outline: [CGPoint], size: CGSize) -> Bool {
        guard let first = outline.first else { return false }
        var minX = Double(first.x)
        var maxX = minX
        var minY = Double(first.y)
        var maxY = minY
        for p in outline {
            minX = min(minX, Double(p.x))
            maxX = max(maxX, Double(p.x))
            minY = min(minY, Double(p.y))
            maxY = max(maxY, Double(p.y))
        }
        return maxX >= 0 && minX <= Double(size.width) && maxY >= 0 && minY <= Double(size.height)
    }
}
