import CoreGraphics
import Foundation

/// Drawings that are better as a picture: a heart, a kidney, a spleen, a pair of lungs, a smiling or
/// sad face. Each drawing is compared with outlines taken from the app's own vector pictures (in
/// every orientation) and checked against its shape: whether it is closed, how deep its notches go,
/// how many lobes it has.
enum SketchRecognizer {
    enum Mood {
        case happy
        case sad
        case neutral
    }

    struct Match {
        let kind: SketchSuggestion.Kind
        /// The next most likely reading, offered beside the first one.
        let alternate: SketchSuggestion.Kind?
        /// Indices (in the strokes passed in) that make up the drawing.
        let members: [Int]
    }

    /// `strokes` are page-local, oldest first; the last one is the stroke the pencil is holding.
    static func recognize(_ strokes: [[CGPoint]]) -> Match? {
        guard let current = strokes.last, current.count >= 8 else { return nil }
        let currentIndex = strokes.count - 1
        if let pair = Self.lungs(strokes) {
            return pair
        }
        if let face = Self.face(strokes), face.members.contains(currentIndex), face.mood != .neutral {
            return Match(kind: .face(happy: face.mood == .happy), alternate: nil, members: face.members)
        }
        guard let loop = closedLoop(current) else { return nil }
        let t = Templates.shared
        let pts = Geo.resample(loop, count: 64)
        let shape = Geo.normalized(pts)
        let toEllipse = Geo.chamfer(shape, t.ellipse)
        let toHeart = Geo.chamfer(shape, t.heart)
        let toKidney = t.kidney.map { Geo.chamfer(shape, $0) }.min() ?? .infinity
        let toSpleen = t.spleen.map { Geo.chamfer(shape, $0) }.min() ?? .infinity
        let outline = Geo.smooth(Geo.resample(loop, count: 96), closed: true, radius: 2)
        let notches = concavities(outline).filter { $0 > 0.07 }
        // An organ's notch (the hilum) is part of the drawing, not the dent a quick hand leaves
        // where it closes a circle: dents next to the stroke's two ends do not count, and a real
        // hilum is at least a tenth of the drawing deep.
        let organNotches = concavities(outline, ignoringJunction: true).filter { $0 > 0.07 }
        // A heart is told apart by its build (two lobes, a notch on top, a point at the bottom, the
        // halves alike), not by how closely it follows the textbook curve: a quick, lopsided heart
        // is still a heart, while a kidney or a spleen never has the bottom point.
        let heartLike = looksLikeHeart(loop)

        var candidates: [(kind: SketchSuggestion.Kind, distance: CGFloat)] = []
        if heartLike, toHeart < 0.14 {
            candidates.append((.heart, toHeart * 0.5))
        } else if toHeart < 0.065, toHeart < 0.65 * toEllipse, !notches.isEmpty {
            candidates.append((.heart, toHeart))
        }
        // A kidney and a spleen both have one clear notch (the hilum); an ellipse or a rectangle has none.
        let notched = (1...2).contains(organNotches.count) && organNotches[0] >= 0.10 && organNotches[0] < 0.4
        if notched, toKidney < 0.06 {
            candidates.append((.kidney, toKidney))
        }
        if notched, toSpleen < 0.06 {
            candidates.append((.spleen, toSpleen))
        }
        candidates.sort { $0.distance < $1.distance }
        // A drawing built like a heart is offered as a heart first; an organ reading stays beside it.
        if heartLike, let i = candidates.firstIndex(where: { $0.kind == .heart }), i > 0 {
            let heart = candidates.remove(at: i)
            candidates.insert(heart, at: 0)
        }
        guard let best = candidates.first else { return nil }
        let alternate: SketchSuggestion.Kind?
        if candidates.count > 1 {
            alternate = candidates[1].kind
        } else if best.kind == .kidney {
            alternate = .spleen
        } else if best.kind == .spleen {
            alternate = .kidney
        } else {
            alternate = nil
        }
        return Match(kind: best.kind, alternate: alternate, members: [currentIndex])
    }

    /// Two closed lobes side by side, similar in height and taller than wide.
    private static func lungs(_ strokes: [[CGPoint]]) -> Match? {
        guard strokes.count >= 2, let current = closedLoop(strokes[strokes.count - 1]) else { return nil }
        let t = Templates.shared
        let bc = Geo.bounds(current)
        guard bc.height > 1.05 * bc.width else { return nil }
        for k in stride(from: strokes.count - 2, through: 0, by: -1) {
            guard let other = closedLoop(strokes[k]) else { continue }
            let bo = Geo.bounds(other)
            let heightRatio = bc.height / max(bo.height, 1e-6)
            let overlap = min(bc.maxY, bo.maxY) - max(bc.minY, bo.minY)
            let gapX = max(bc.minX, bo.minX) - min(bc.maxX, bo.maxX)
            guard heightRatio > 0.6, heightRatio < 1.6, overlap > 0.6 * min(bc.height, bo.height),
                  gapX < 0.6 * max(bc.width, bo.width), gapX > -0.35 * min(bc.width, bo.width),
                  bo.height > 1.05 * bo.width else { continue }
            let leftFirst = bc.minX < bo.minX
            let left = leftFirst ? current : other
            let right = leftFirst ? other : current
            let dl = Geo.chamfer(Geo.normalized(Geo.resample(left, count: 64)), t.lungLeft)
            let dr = Geo.chamfer(Geo.normalized(Geo.resample(right, count: 64)), t.lungRight)
            if dl < 0.09, dr < 0.09 {
                return Match(kind: .lungs, alternate: nil, members: [k, strokes.count - 1])
            }
        }
        return nil
    }

    /// The stroke without its overshoot when it comes back to where it started; nil when open.
    static func closedLoop(_ s: [CGPoint]) -> [CGPoint]? {
        guard s.count >= 8 else { return nil }
        let length = Geo.length(s)
        let box = Geo.bounds(s)
        let maxDim = max(box.width, box.height)
        guard maxDim >= 12 else { return nil }
        let last = s[s.count - 1]
        var gap = CGFloat.infinity
        var run: CGFloat = 0
        for i in s.indices {
            if i > 0 { run += Geo.dist(s[i - 1], s[i]) }
            if run > 0.3 * length { break }
            gap = min(gap, Geo.dist(s[i], last))
        }
        guard gap < max(0.25 * maxDim, 8), length > 2.2 * maxDim else { return nil }
        var bestIndex = s.count - 1
        var bestDistance = CGFloat.infinity
        for i in Int(Double(s.count) * 0.65)..<s.count {
            let d = Geo.dist(s[i], s[0])
            if d < bestDistance {
                bestDistance = d
                bestIndex = i
            }
        }
        return Array(s[0...bestIndex])
    }

    /// How deep the outline dips inside its convex hull, relative to the drawing's size (deepest first).
    /// `ignoringJunction` leaves out dents whose deepest point lies within 12 % of the loop from
    /// where the stroke started and ended.
    static func concavities(_ pts: [CGPoint], ignoringJunction: Bool = false) -> [CGFloat] {
        let n = pts.count
        guard n >= 5 else { return [] }
        let box = Geo.bounds(pts)
        let size = max(box.width, box.height, 1e-6)
        let hull = convexHull(pts).sorted()
        guard hull.count >= 3 else { return [] }
        let junction = Double(n) * 0.12
        var out: [CGFloat] = []
        for k in hull.indices {
            let a = hull[k]
            let c = hull[(k + 1) % hull.count]
            var depth: CGFloat = 0
            var deepest = a
            var i = (a + 1) % n
            while i != c {
                let d = Geo.segmentDistance(pts[i], pts[a], pts[c])
                if d > depth {
                    depth = d
                    deepest = i
                }
                i = (i + 1) % n
            }
            guard depth > 0 else { continue }
            if ignoringJunction && Double(min(deepest, n - deepest)) < junction { continue }
            out.append(depth / size)
        }
        return out.sorted(by: >)
    }

    /// A hand-drawn heart: two lobes on top with a notch between them, a point at the bottom and two
    /// halves that mirror each other. Accepted turned up to 30° either way.
    static func looksLikeHeart(_ loop: [CGPoint]) -> Bool {
        let pts = Geo.smooth(Geo.resample(loop, count: 96), closed: true, radius: 2)
        let box = Geo.bounds(pts)
        let center = CGPoint(x: box.midX, y: box.midY)
        for degrees in stride(from: -30, through: 30, by: 6) {
            let a = CGFloat(degrees) * .pi / 180
            let c = cos(a)
            let s = sin(a)
            let turned = pts.map { p -> CGPoint in
                let x = p.x - center.x
                let y = p.y - center.y
                return CGPoint(x: x * c - y * s, y: x * s + y * c)
            }
            if heartBuild(Geo.normalized(turned)) { return true }
        }
        return false
    }

    /// `shape` is normalized to the unit square, y down.
    private static func heartBuild(_ shape: [CGPoint]) -> Bool {
        let n = shape.count
        guard n >= 24, let tipIndex = shape.indices.max(by: { shape[$0].y < shape[$1].y }) else { return false }
        // The point at the bottom: near the middle and clearly sharper than a rounded end.
        let tip = shape[tipIndex]
        guard tip.x > 0.2, tip.x < 0.8 else { return false }
        let k = max(3, n / 12)
        let tipAngle = Geo.interiorAngle(shape[(tipIndex - k + n) % n], tip, shape[(tipIndex + k) % n])
        guard tipAngle < 128 * .pi / 180 else { return false }
        // The notch between the lobes: the deepest dent of the outline, in the upper half and near the middle.
        guard let notch = deepestDent(shape), notch.depth > 0.045,
              notch.point.x > 0.22, notch.point.x < 0.78, notch.point.y < 0.55 else { return false }
        // Both lobes rise above the notch.
        let leftTop = shape.filter { $0.x < notch.point.x - 0.08 }.map(\.y).min() ?? 1
        let rightTop = shape.filter { $0.x > notch.point.x + 0.08 }.map(\.y).min() ?? 1
        guard leftTop < notch.point.y - 0.035, rightTop < notch.point.y - 0.035 else { return false }
        // The halves mirror each other about the line through the notch and the point.
        let axis = (notch.point.x + tip.x) / 2
        let mirrored = shape.map { CGPoint(x: 2 * axis - $0.x, y: $0.y) }
        return Geo.chamfer(Geo.resample(shape, count: 48), Geo.resample(mirrored, count: 48)) < 0.08
    }

    /// The point of the outline that lies deepest inside its convex hull, and how deep.
    private static func deepestDent(_ pts: [CGPoint]) -> (point: CGPoint, depth: CGFloat)? {
        let n = pts.count
        let hull = convexHull(pts).sorted()
        guard hull.count >= 3 else { return nil }
        var bestPoint = CGPoint.zero
        var bestDepth: CGFloat = 0
        for k in hull.indices {
            let a = hull[k]
            let c = hull[(k + 1) % hull.count]
            var i = (a + 1) % n
            while i != c {
                let d = Geo.segmentDistance(pts[i], pts[a], pts[c])
                if d > bestDepth {
                    bestDepth = d
                    bestPoint = pts[i]
                }
                i = (i + 1) % n
            }
        }
        return bestDepth > 0 ? (bestPoint, bestDepth) : nil
    }

    /// Indices of the convex hull (monotone chain).
    private static func convexHull(_ pts: [CGPoint]) -> [Int] {
        let order = pts.indices.sorted { pts[$0].x != pts[$1].x ? pts[$0].x < pts[$1].x : pts[$0].y < pts[$1].y }
        func cross(_ o: Int, _ a: Int, _ b: Int) -> CGFloat {
            (pts[a].x - pts[o].x) * (pts[b].y - pts[o].y) - (pts[a].y - pts[o].y) * (pts[b].x - pts[o].x)
        }
        var lower: [Int] = []
        for i in order {
            while lower.count >= 2, cross(lower[lower.count - 2], lower[lower.count - 1], i) <= 0 { lower.removeLast() }
            lower.append(i)
        }
        var upper: [Int] = []
        for i in order.reversed() {
            while upper.count >= 2, cross(upper[upper.count - 2], upper[upper.count - 1], i) <= 0 { upper.removeLast() }
            upper.append(i)
        }
        return Array(lower.dropLast()) + Array(upper.dropLast())
    }

    /// A face: one round closed stroke with at least two strokes inside it, eyes above the middle
    /// and a mouth below. Returns the mood and the indices of the strokes that make up the face.
    static func face(_ strokes: [[CGPoint]]) -> (mood: Mood, members: [Int])? {
        var faceIndex = -1
        var biggest: Fit.Ellipse?
        for (i, s) in strokes.enumerated() where s.count >= 8 {
            let box = Geo.bounds(s)
            let md = max(box.width, box.height)
            guard md >= 20, Geo.dist(s[0], s[s.count - 1]) < 0.25 * md, Geo.length(s) > 2.4 * md else { continue }
            if let e = Fit.ellipse(Geo.resample(s, count: 64)), e.residual < 0.14, e.ry / e.rx > 0.6,
               biggest == nil || e.rx > biggest!.rx {
                faceIndex = i
                biggest = e
            }
        }
        guard let outline = biggest else { return nil }
        let radius = (outline.rx + outline.ry) / 2
        var inside: [(index: Int, box: CGRect, points: [CGPoint])] = []
        for (i, s) in strokes.enumerated() where i != faceIndex && !s.isEmpty {
            let box = Geo.bounds(s)
            let c = CGPoint(x: box.midX, y: box.midY)
            if Geo.dist(c, outline.center) < 0.8 * radius, max(box.width, box.height) < 1.3 * radius {
                inside.append((i, box, s))
            }
        }
        guard inside.count >= 2 else { return nil }
        let upper = inside.filter { $0.box.midY < outline.center.y - 0.05 * radius }
        let lower = inside.filter { $0.box.midY > outline.center.y + 0.05 * radius }
        guard !upper.isEmpty, let mouth = lower.max(by: { $0.box.width < $1.box.width }) else { return nil }
        let m = mouth.points
        let mid = Geo.resample(m, count: 21)[10]
        let ends = (m[0].y + m[m.count - 1].y) / 2
        let curve = (mid.y - ends) / max(mouth.box.width, 1)
        let mood: Mood = curve > 0.08 ? .happy : (curve < -0.08 ? .sad : .neutral)
        return (mood, [faceIndex] + inside.map { $0.index })
    }

    /// The classic heart curve at parameter `t` (y down). One term per line keeps the type checker fast.
    fileprivate static func heartPoint(_ t: CGFloat) -> CGPoint {
        let s: CGFloat = sin(t)
        let x: CGFloat = 16 * s * s * s
        let c1: CGFloat = 13 * cos(t)
        let c2: CGFloat = 5 * cos(2 * t)
        let c3: CGFloat = 2 * cos(3 * t)
        let c4: CGFloat = cos(4 * t)
        return CGPoint(x: x, y: -(c1 - c2 - c3 - c4))
    }

    /// A neat heart filling `rect`, starting at the top notch.
    static func heartPath(in rect: CGRect) -> [CGPoint] {
        let raw: [CGPoint] = (0...96).map { (i: Int) -> CGPoint in
            heartPoint(CGFloat.pi + CGFloat(i) / 96 * 2 * CGFloat.pi)
        }
        let box = Geo.bounds(raw)
        return raw.map { p in
            CGPoint(x: rect.minX + (p.x - box.minX) / box.width * rect.width,
                    y: rect.minY + (p.y - box.minY) / box.height * rect.height)
        }
    }

    /// Outlines to compare drawings with, normalized to the unit square.
    private final class Templates: @unchecked Sendable {
        static let shared = Templates()

        let heart: [CGPoint]
        let ellipse: [CGPoint]
        let kidney: [[CGPoint]]
        let spleen: [[CGPoint]]
        let lungLeft: [CGPoint]
        let lungRight: [CGPoint]

        private init() {
            heart = Geo.normalized((0..<64).map { (i: Int) -> CGPoint in
                SketchRecognizer.heartPoint(CGFloat(i) / 64 * 2 * CGFloat.pi)
            })
            ellipse = Geo.normalized((0..<64).map { i in
                let t = CGFloat(i) / 64 * 2 * .pi
                return CGPoint(x: cos(t), y: sin(t))
            })
            func outline(_ name: String, _ which: Int = 0) -> [CGPoint] {
                StickerArt.bodyOutline(name, which: which)
            }
            func template(_ p: [CGPoint]) -> [CGPoint] {
                Geo.normalized(Geo.resample(p, count: 64))
            }
            /// The outline in all eight orientations (four turns, mirrored or not).
            func orientations(_ p: [CGPoint]) -> [[CGPoint]] {
                guard !p.isEmpty else { return [] }
                var out: [[CGPoint]] = []
                for turns in 0..<4 {
                    for mirror in [CGFloat(1), -1] {
                        out.append(template(p.map { q in
                            var x = (q.x - 50) * mirror
                            var y = q.y - 50
                            for _ in 0..<turns {
                                let t = x
                                x = -y
                                y = t
                            }
                            return CGPoint(x: x, y: y)
                        }))
                    }
                }
                return out
            }
            kidney = orientations(outline("kidney"))
            spleen = orientations(outline("spleen"))
            lungLeft = template(outline("lungs", 0))
            lungRight = template(outline("lungs", 1))
        }
    }
}
