import CoreGraphics
import Foundation

/// A clean shape found in a hand-drawn stroke. `path` is page-local and ready to become ink.
struct ShapeMatch {
    enum Kind {
        case line
        case polyline
        case polygon
        case rectangle
        case circle
        case ellipse
        /// A smooth bend between two ends (a quadratic Bézier, so a piece of a parabola); no arrowhead.
        case curve
    }

    /// Center, radii and turn of a circle or an ellipse.
    struct Oval: Equatable {
        var center: CGPoint
        var rx: CGFloat
        var ry: CGFloat
        var angle: CGFloat
    }

    /// The two ends of a curve and the control point between them.
    struct Curve: Equatable {
        var start: CGPoint
        var control: CGPoint
        var end: CGPoint

        func point(at t: CGFloat) -> CGPoint {
            let u = 1 - t
            let x: CGFloat = u * u * start.x + 2 * u * t * control.x + t * t * end.x
            let y: CGFloat = u * u * start.y + 2 * u * t * control.y + t * t * end.y
            return CGPoint(x: x, y: y)
        }

        /// The point the curve passes through halfway, where its bend handle sits.
        var middle: CGPoint { point(at: 0.5) }

        /// The control point that makes the curve pass through `m` halfway.
        static func control(start: CGPoint, through m: CGPoint, end: CGPoint) -> CGPoint {
            CGPoint(x: 2 * m.x - (start.x + end.x) / 2, y: 2 * m.y - (start.y + end.y) / 2)
        }

        func path() -> [CGPoint] {
            let length = Geo.dist(start, control) + Geo.dist(control, end)
            let n = max(24, min(240, Int((length / 2).rounded(.up))))
            return (0...n).map { i in point(at: CGFloat(i) / CGFloat(n)) }
        }
    }

    let kind: Kind
    let title: String
    let path: [CGPoint]
    /// Corners the user can drag after the pencil lifts (polygons, rectangles, broken lines, lines).
    var corners: [CGPoint] = []
    /// Set for circles and ellipses: their axes get handles instead of corners.
    var oval: Oval? = nil
    /// Set for curves: the ends and the bend get handles.
    var curve: Curve? = nil

    /// Closed shapes turn and scale around their middle, open ones around where they started.
    var isClosed: Bool {
        switch kind {
        case .polygon, .rectangle, .circle, .ellipse: return true
        default: return false
        }
    }
}

/// Hold-to-shape: lines, broken lines, triangles, rectangles and other polygons, circles, ellipses
/// and curves. Real handwriting shakes, so the stroke is smoothed first and every possible
/// shape is fitted; the one with the smallest error wins, and only when it really follows the
/// drawing. Every test is relative to the drawing's size.
///
/// Holding the pencil still is a request for a shape, so the tests are forgiving: a crooked square
/// still becomes a square, a lopsided triangle with a near right angle becomes a right triangle.
/// What is not perfect afterwards can be fixed by dragging the corners.
enum ShapeRecognizer {
    static func recognize(_ raw: [CGPoint]) -> ShapeMatch? {
        guard raw.count >= 3 else { return nil }
        let length = Geo.length(raw)
        let box = Geo.bounds(raw)
        let diag = hypot(box.width, box.height)
        let maxDim = max(box.width, box.height)
        guard length >= 14, maxDim >= 8 else { return nil }
        // Closed when the end comes back near the first stretch of the stroke: overshooting the
        // start is normal when a shape is closed by hand, and so is stopping a little short of it.
        let last = raw[raw.count - 1]
        var gap = CGFloat.infinity
        var run: CGFloat = 0
        for i in raw.indices {
            if i > 0 { run += Geo.dist(raw[i - 1], raw[i]) }
            if run > 0.3 * length { break }
            gap = min(gap, Geo.dist(raw[i], last))
        }
        let closed = gap < max(0.28 * maxDim, 10) && length > 2.1 * maxDim
        return closed ? closedShape(raw, diag: diag) : openShape(raw, length: length, diag: diag)
    }

    private struct Candidate {
        let match: ShapeMatch
        /// RMS distance of the drawing from the shape, in points.
        let rms: CGFloat
        /// Above 1 for shapes that should only win clearly (many corners).
        let penalty: CGFloat
    }

    private static func pick(_ candidates: [Candidate], limit: CGFloat) -> ShapeMatch? {
        guard let best = candidates.min(by: { $0.rms * $0.penalty < $1.rms * $1.penalty }), best.rms <= limit else {
            return nil
        }
        return best.match
    }

    // MARK: Open strokes

    private static func openShape(_ raw: [CGPoint], length: CGFloat, diag: CGFloat) -> ShapeMatch? {
        let pts = Geo.smooth(Geo.resample(raw, count: 96), closed: false, radius: 2)
        let first = raw[0]
        let last = raw[raw.count - 1]
        var deviation: CGFloat = 0
        for p in pts {
            deviation = max(deviation, Geo.segmentDistance(p, first, last))
        }
        let chord = Geo.dist(first, last)
        if deviation < max(0.07 * chord, 3), chord > 0.8 * length {
            return ShapeMatch(kind: .line, title: Loc.t("Doğru"), path: [first, last], corners: [first, last])
        }

        var candidates: [Candidate] = []
        // Straight pieces joined at real corners (an angle, a zigzag, axes).
        var v = Geo.simplify(pts, tolerance: 0.05 * diag).map { pts[$0] }
        v = Geo.dropCollinear(v, closed: false, minTurn: 25 * .pi / 180)
        v = Geo.mergeClose(v, closed: false, minLength: 0.1 * length)
        if v.count >= 3, v.count <= 8, Geo.cornersAreSharp(pts, v, closed: false) {
            candidates.append(Candidate(match: ShapeMatch(kind: .polyline, title: Loc.t("Kırık çizgi"), path: v, corners: v),
                                        rms: Geo.polylineRMS(pts, v, closed: false),
                                        penalty: 1 + 0.08 * CGFloat(v.count - 3)))
        }
        // Any smooth bend becomes a curve with a handle on its bend: no arcs, no arrowheads.
        if let first = pts.first, let last = pts.last, let fit = Fit.quadraticBezier(pts) {
            let curve = ShapeMatch.Curve(start: first, control: fit.control, end: last)
            candidates.append(Candidate(match: ShapeMatch(kind: .curve, title: Loc.t("Eğri"), path: curve.path(), curve: curve),
                                        rms: fit.rms, penalty: 1.05))
        }
        return pick(candidates, limit: 0.06 * diag)
    }

    // MARK: Closed strokes

    private static func closedShape(_ raw: [CGPoint], diag: CGFloat) -> ShapeMatch? {
        // Cut the overshoot past the starting point.
        var bestIndex = raw.count - 1
        var bestDistance = CGFloat.infinity
        for i in Int(Double(raw.count) * 0.65)..<raw.count {
            let d = Geo.dist(raw[i], raw[0])
            if d < bestDistance {
                bestDistance = d
                bestIndex = i
            }
        }
        let loop = Array(raw[0...bestIndex])
        let pts = Geo.smooth(Geo.resample(loop, count: 120), closed: true, radius: 2)
        // About once around: a spiral or a scribble is not a shape (a small overshoot is fine).
        guard abs(abs(Geo.winding(pts)) - 2 * .pi) < 0.75 * .pi else { return nil }

        var candidates: [Candidate] = []
        if let e = Fit.ellipse(pts) {
            if e.ry / e.rx > 0.82 {
                let r = (e.rx + e.ry) / 2
                candidates.append(Candidate(match: ShapeMatch(kind: .circle, title: Loc.t("Daire"),
                                                              path: ellipsePath(center: e.center, rx: r, ry: r, angle: 0, following: pts),
                                                              oval: ShapeMatch.Oval(center: e.center, rx: r, ry: r, angle: 0)),
                                            rms: Fit.circle(pts)?.rms ?? e.rms, penalty: 1))
            } else {
                var angle: CGFloat = e.angle
                let quarter: CGFloat = CGFloat.pi / 2
                let k: CGFloat = (angle / quarter).rounded()
                if abs(angle - k * quarter) < 8 * CGFloat.pi / 180 { angle = k * quarter }
                candidates.append(Candidate(match: ShapeMatch(kind: .ellipse, title: Loc.t("Elips"),
                                                              path: ellipsePath(center: e.center, rx: e.rx, ry: e.ry, angle: angle, following: pts),
                                                              oval: ShapeMatch.Oval(center: e.center, rx: e.rx, ry: e.ry, angle: angle)),
                                            rms: e.rms, penalty: 1))
            }
        }

        // A loop that fills almost all of the smallest rectangle around it is a rectangle, however
        // crooked its sides or round its corners (an ellipse fills 79 %, a hexagon 75 %).
        let box = boundingRectangle(pts)
        if let box, box.fill > 0.88 {
            let rect = snapRectangle(box.corners)
            candidates.append(Candidate(match: ShapeMatch(kind: .rectangle, title: isSquare(rect) ? Loc.t("Kare") : Loc.t("Dikdörtgen"),
                                                          path: rect + [rect[0]], corners: rect),
                                        rms: Geo.polylineRMS(pts, rect, closed: true), penalty: 0.7))
        }

        // Polygon: simplify the loop starting from its sharpest point (a corner).
        let n = pts.count
        var sharpest = 0
        var sharpestTurn: CGFloat = -1
        for i in 0..<n {
            let t = Geo.turn(pts[(i - 6 + n) % n], pts[i], pts[(i + 6) % n])
            if t > sharpestTurn {
                sharpestTurn = t
                sharpest = i
            }
        }
        var rotated = Array(pts[sharpest...]) + Array(pts[..<sharpest])
        rotated.append(rotated[0])
        var v = Geo.simplify(rotated, tolerance: 0.045 * diag).dropLast().map { rotated[$0] }
        v = Geo.dropCollinear(v, closed: true, minTurn: 28 * .pi / 180)
        v = Geo.mergeClose(v, closed: true, minLength: 0.12 * diag)
        if v.count >= 3, v.count <= 8, Geo.cornersAreSharp(pts, v, closed: true) {
            var path = v
            var kind = ShapeMatch.Kind.polygon
            let names = [3: Loc.t("Üçgen"), 4: Loc.t("Dörtgen"), 5: Loc.t("Beşgen"), 6: Loc.t("Altıgen"), 7: Loc.t("Yedigen"), 8: Loc.t("Sekizgen")]
            var title = names[v.count] ?? Loc.t("Çokgen")
            let nearlyRight = v.count == 4 && (0..<4).allSatisfy { i in
                abs(Geo.interiorAngle(v[(i + 3) % 4], v[i], v[(i + 1) % 4]) - .pi / 2) < 30 * .pi / 180
            }
            if v.count == 4, nearlyRight || (box?.fill ?? 0) > 0.9 {
                path = snapRectangle(v)
                kind = .rectangle
                title = isSquare(path) ? Loc.t("Kare") : Loc.t("Dikdörtgen")
            } else if v.count == 3 {
                let tri = beautifyTriangle(v)
                path = tri.points
                title = tri.title
            }
            let penalties: [CGFloat] = [0, 0, 0, 0.8, 0.8, 0.85, 1.0, 1.15, 1.3]
            candidates.append(Candidate(match: ShapeMatch(kind: kind, title: title, path: path + [path[0]], corners: path),
                                        rms: Geo.polylineRMS(pts, v, closed: true), penalty: penalties[v.count]))
        }
        return pick(candidates, limit: 0.075 * diag)
    }

    /// The smallest rectangle (at any turn) around the loop, and how much of it the loop fills.
    private static func boundingRectangle(_ pts: [CGPoint]) -> (corners: [CGPoint], fill: CGFloat)? {
        let area = abs(Geo.signedArea(pts))
        guard area > 1 else { return nil }
        var bestArea = CGFloat.infinity
        var bestCorners: [CGPoint] = []
        for step in 0..<90 {
            let a = CGFloat(step) * .pi / 180
            let c = cos(a)
            let s = sin(a)
            var u0 = CGFloat.infinity
            var u1 = -CGFloat.infinity
            var w0 = CGFloat.infinity
            var w1 = -CGFloat.infinity
            for p in pts {
                let u = p.x * c + p.y * s
                let w = -p.x * s + p.y * c
                u0 = min(u0, u)
                u1 = max(u1, u)
                w0 = min(w0, w)
                w1 = max(w1, w)
            }
            let boxArea = (u1 - u0) * (w1 - w0)
            if boxArea < bestArea {
                bestArea = boxArea
                bestCorners = [CGPoint(x: u0 * c - w0 * s, y: u0 * s + w0 * c), CGPoint(x: u1 * c - w0 * s, y: u1 * s + w0 * c),
                               CGPoint(x: u1 * c - w1 * s, y: u1 * s + w1 * c), CGPoint(x: u0 * c - w1 * s, y: u0 * s + w1 * c)]
            }
        }
        guard bestArea > 1, bestCorners.count == 4 else { return nil }
        return (bestCorners, area / bestArea)
    }

    /// A hand-drawn triangle made exact when it is close to a special one: equilateral, right
    /// angled or isosceles; a side that is almost level (or upright) is straightened.
    private static func beautifyTriangle(_ v: [CGPoint]) -> (points: [CGPoint], title: String) {
        var p = v
        var title = Loc.t("Üçgen")
        // Side i runs from v[i] to v[i+1].
        let s: [CGFloat] = (0..<3).map { Geo.dist(v[$0], v[($0 + 1) % 3]) }
        let longest = s.max() ?? 1
        let shortest = s.min() ?? 1
        let center = CGPoint(x: (p[0].x + p[1].x + p[2].x) / 3, y: (p[0].y + p[1].y + p[2].y) / 3)
        var rightAt: Int?
        for i in 0..<3 {
            let angle = Geo.interiorAngle(p[(i + 2) % 3], p[i], p[(i + 1) % 3])
            if abs(angle - .pi / 2) < 10 * .pi / 180 { rightAt = i }
        }
        if longest - shortest < 0.12 * longest {
            // Equilateral around the same middle, keeping the most level side's direction.
            var levelSide = 0
            var levelness = CGFloat.infinity
            for i in 0..<3 {
                let d = abs(sin(atan2(p[(i + 1) % 3].y - p[i].y, p[(i + 1) % 3].x - p[i].x)))
                if d < levelness {
                    levelness = d
                    levelSide = i
                }
            }
            let a = p[levelSide]
            let b = p[(levelSide + 1) % 3]
            let apex = p[(levelSide + 2) % 3]
            let length = max(Geo.dist(a, b), 1)
            let u = CGPoint(x: (b.x - a.x) / length, y: (b.y - a.y) / length)
            var n = CGPoint(x: -u.y, y: u.x)
            let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
            if (apex.x - mid.x) * n.x + (apex.y - mid.y) * n.y < 0 { n = CGPoint(x: -n.x, y: -n.y) }
            let radius = (Geo.dist(p[0], center) + Geo.dist(p[1], center) + Geo.dist(p[2], center)) / 3
            let side = radius * CGFloat(3).squareRoot()
            let baseMid = CGPoint(x: center.x - n.x * radius / 2, y: center.y - n.y * radius / 2)
            p[levelSide] = CGPoint(x: baseMid.x - u.x * side / 2, y: baseMid.y - u.y * side / 2)
            p[(levelSide + 1) % 3] = CGPoint(x: baseMid.x + u.x * side / 2, y: baseMid.y + u.y * side / 2)
            p[(levelSide + 2) % 3] = CGPoint(x: center.x + n.x * radius, y: center.y + n.y * radius)
            title = Loc.t("Eşkenar üçgen")
        } else if let i = rightAt {
            // The right-angle corner moves onto the circle over the other two (Thales).
            let a = p[(i + 2) % 3]
            let c = p[(i + 1) % 3]
            let mid = CGPoint(x: (a.x + c.x) / 2, y: (a.y + c.y) / 2)
            let r = Geo.dist(a, c) / 2
            let d = Geo.dist(p[i], mid)
            if d > 1e-3 {
                p[i] = CGPoint(x: mid.x + (p[i].x - mid.x) * r / d, y: mid.y + (p[i].y - mid.y) * r / d)
            }
            title = Loc.t("Dik üçgen")
        } else {
            // Two equal sides meeting at p[i]: the apex moves onto the middle of the base.
            for i in 0..<3 {
                let one = s[i]
                let other = s[(i + 2) % 3]
                guard abs(one - other) < 0.08 * max(one, other) else { continue }
                let b = p[(i + 1) % 3]
                let c = p[(i + 2) % 3]
                let length = max(Geo.dist(b, c), 1)
                let u = CGPoint(x: (c.x - b.x) / length, y: (c.y - b.y) / length)
                let mid = CGPoint(x: (b.x + c.x) / 2, y: (b.y + c.y) / 2)
                let along = (p[i].x - mid.x) * u.x + (p[i].y - mid.y) * u.y
                p[i] = CGPoint(x: p[i].x - u.x * along, y: p[i].y - u.y * along)
                title = Loc.t("İkizkenar üçgen")
                break
            }
        }
        // Straighten a side that is almost level or upright by turning the whole triangle.
        var smallest = CGFloat.infinity
        var correction: CGFloat = 0
        for i in 0..<3 {
            let a = atan2(p[(i + 1) % 3].y - p[i].y, p[(i + 1) % 3].x - p[i].x)
            let quarter = CGFloat.pi / 2
            let off = a - (a / quarter).rounded() * quarter
            if abs(off) < smallest {
                smallest = abs(off)
                correction = -off
            }
        }
        if smallest > 0.001, smallest < 7 * .pi / 180 {
            let c = CGPoint(x: (p[0].x + p[1].x + p[2].x) / 3, y: (p[0].y + p[1].y + p[2].y) / 3)
            let cs = cos(correction)
            let sn = sin(correction)
            p = p.map { q in
                let x = q.x - c.x
                let y = q.y - c.y
                return CGPoint(x: c.x + x * cs - y * sn, y: c.y + x * sn + y * cs)
            }
        }
        return (p, title)
    }

    /// Right angles become a true rectangle (a square when the sides are nearly equal); a rectangle
    /// that is almost level is leveled.
    private static func snapRectangle(_ v: [CGPoint]) -> [CGPoint] {
        var longest: CGFloat = 0
        var angle: CGFloat = 0
        for i in 0..<4 {
            let a = v[i]
            let b = v[(i + 1) % 4]
            let l = Geo.dist(a, b)
            if l > longest {
                longest = l
                angle = atan2(b.y - a.y, b.x - a.x)
            }
        }
        let quarter = CGFloat.pi / 2
        angle = (angle.truncatingRemainder(dividingBy: quarter) + quarter).truncatingRemainder(dividingBy: quarter)
        if angle > quarter / 2 { angle -= quarter }
        if abs(angle) < 8 * .pi / 180 { angle = 0 }
        let c = cos(angle)
        let s = sin(angle)
        let us = v.map { $0.x * c + $0.y * s }.sorted()
        let ws = v.map { -$0.x * s + $0.y * c }.sorted()
        var u0 = (us[0] + us[1]) / 2
        var u1 = (us[2] + us[3]) / 2
        var w0 = (ws[0] + ws[1]) / 2
        var w1 = (ws[2] + ws[3]) / 2
        let width = u1 - u0
        let height = w1 - w0
        if abs(width - height) < 0.15 * max(width, height) {
            let m = (width + height) / 2
            let cu = (u0 + u1) / 2
            let cw = (w0 + w1) / 2
            u0 = cu - m / 2
            u1 = cu + m / 2
            w0 = cw - m / 2
            w1 = cw + m / 2
        }
        func back(_ u: CGFloat, _ w: CGFloat) -> CGPoint { CGPoint(x: u * c - w * s, y: u * s + w * c) }
        return [back(u0, w0), back(u1, w0), back(u1, w1), back(u0, w1)]
    }

    private static func isSquare(_ r: [CGPoint]) -> Bool {
        abs(Geo.dist(r[0], r[1]) - Geo.dist(r[1], r[2])) < 0.01 * Geo.dist(r[0], r[2])
    }

    /// Starts where the user started and runs the same way round.
    private static func ellipsePath(center: CGPoint, rx: CGFloat, ry: CGFloat, angle: CGFloat, following pts: [CGPoint]) -> [CGPoint] {
        var area: CGFloat = 0
        for i in 1..<pts.count {
            area += pts[i - 1].x * pts[i].y - pts[i].x * pts[i - 1].y
        }
        let direction: CGFloat = area >= 0 ? 1 : -1
        let c = cos(angle)
        let s = sin(angle)
        let x = pts[0].x - center.x
        let y = pts[0].y - center.y
        let t0 = atan2((-x * s + y * c) / ry, (x * c + y * s) / rx)
        let n = max(48, Int((CGFloat.pi * (rx + ry) / 3).rounded(.up)))
        return (0...n).map { i in
            let t = t0 + direction * 2 * .pi * CGFloat(i) / CGFloat(n)
            let u = cos(t) * rx
            let w = sin(t) * ry
            return CGPoint(x: center.x + u * c - w * s, y: center.y + u * s + w * c)
        }
    }
}

// MARK: - Geometry

enum Geo {
    static func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    static func length(_ p: [CGPoint]) -> CGFloat {
        var l: CGFloat = 0
        for i in p.indices.dropFirst() {
            l += dist(p[i - 1], p[i])
        }
        return l
    }

    static func bounds(_ p: [CGPoint]) -> CGRect {
        guard let f = p.first else { return .zero }
        var x0 = f.x, y0 = f.y, x1 = f.x, y1 = f.y
        for q in p {
            x0 = min(x0, q.x)
            y0 = min(y0, q.y)
            x1 = max(x1, q.x)
            y1 = max(y1, q.y)
        }
        return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    static func wrap(_ a: CGFloat) -> CGFloat {
        var d = a
        while d > .pi { d -= 2 * .pi }
        while d < -.pi { d += 2 * .pi }
        return d
    }

    /// `count` points evenly spaced along the path.
    static func resample(_ p: [CGPoint], count n: Int) -> [CGPoint] {
        let total = length(p)
        guard total > 0, p.count >= 2, n >= 2 else { return p }
        let step = total / CGFloat(n - 1)
        var out = [p[0]]
        out.reserveCapacity(n)
        var acc: CGFloat = 0
        for i in 1..<p.count {
            var a = p[i - 1]
            let b = p[i]
            var d = dist(a, b)
            while acc + d >= step, d > 0, out.count < n {
                let t = (step - acc) / d
                let q = CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
                out.append(q)
                a = q
                d = dist(a, b)
                acc = 0
            }
            acc += d
        }
        while out.count < n { out.append(p[p.count - 1]) }
        return out
    }

    /// Points no more than `spacing` apart along `p`, keeping every point of `p` (corners stay sharp,
    /// unlike `resample`, which can step over a corner).
    static func densify(_ p: [CGPoint], spacing: CGFloat) -> [CGPoint] {
        guard p.count >= 2 else { return p }
        let step = max(spacing, 0.5)
        var out: [CGPoint] = []
        out.reserveCapacity(Int(length(p) / step) + p.count)
        for i in 0..<(p.count - 1) {
            let a = p[i]
            let b = p[i + 1]
            out.append(a)
            let n = min(Int(dist(a, b) / step), 4000)
            if n > 1 {
                for k in 1..<n {
                    let t = CGFloat(k) / CGFloat(n)
                    out.append(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
                }
            }
        }
        out.append(p[p.count - 1])
        return out
    }

    static func resample(_ p: [CGPoint], spacing: CGFloat) -> [CGPoint] {
        let n = max(2, Int((length(p) / max(spacing, 0.5)).rounded()) + 1)
        return resample(p, count: min(n, 2000))
    }

    /// Moving average over `radius` neighbours on each side: takes the tremor out of a hand stroke.
    static func smooth(_ p: [CGPoint], closed: Bool, radius k: Int) -> [CGPoint] {
        let n = p.count
        guard n > 2 * k + 1 else { return p }
        var out: [CGPoint] = []
        out.reserveCapacity(n)
        for i in 0..<n {
            var sx: CGFloat = 0
            var sy: CGFloat = 0
            for j in -k...k {
                let idx = closed ? ((i + j) % n + n) % n : min(max(i + j, 0), n - 1)
                sx += p[idx].x
                sy += p[idx].y
            }
            let c = CGFloat(2 * k + 1)
            out.append(CGPoint(x: sx / c, y: sy / c))
        }
        if !closed {
            out[0] = p[0]
            out[n - 1] = p[n - 1]
        }
        return out
    }

    static func segmentDistance(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let l2 = dx * dx + dy * dy
        guard l2 > 1e-9 else { return dist(p, a) }
        let t = min(max(((p.x - a.x) * dx + (p.y - a.y) * dy) / l2, 0), 1)
        return hypot(p.x - a.x - t * dx, p.y - a.y - t * dy)
    }

    /// Douglas–Peucker: indices of the points that keep the path within `tolerance`.
    static func simplify(_ p: [CGPoint], tolerance: CGFloat) -> [Int] {
        guard p.count >= 3 else { return Array(p.indices) }
        var keep = Array(repeating: false, count: p.count)
        keep[0] = true
        keep[p.count - 1] = true
        var stack = [(0, p.count - 1)]
        while let span = stack.popLast() {
            let (a, b) = span
            var farthest: CGFloat = -1
            var index = -1
            if b - a >= 2 {
                for i in (a + 1)..<b {
                    let d = segmentDistance(p[i], p[a], p[b])
                    if d > farthest {
                        farthest = d
                        index = i
                    }
                }
            }
            if farthest > tolerance, index > 0 {
                keep[index] = true
                stack.append((a, index))
                stack.append((index, b))
            }
        }
        return keep.indices.filter { keep[$0] }
    }

    static func turn(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> CGFloat {
        abs(wrap(atan2(c.y - b.y, c.x - b.x) - atan2(b.y - a.y, b.x - a.x)))
    }

    /// Total signed turning of a closed path (±2π for one time around).
    static func winding(_ p: [CGPoint]) -> CGFloat {
        let n = p.count
        guard n >= 3 else { return 0 }
        var total: CGFloat = 0
        for i in 0..<n {
            let a = p[(i - 1 + n) % n]
            let b = p[i]
            let c = p[(i + 1) % n]
            total += wrap(atan2(c.y - b.y, c.x - b.x) - atan2(b.y - a.y, b.x - a.x))
        }
        return total
    }

    /// Shoelace area of a closed outline (sign follows the direction it runs).
    static func signedArea(_ p: [CGPoint]) -> CGFloat {
        guard p.count >= 3 else { return 0 }
        var a: CGFloat = 0
        for i in p.indices {
            let q = p[(i + 1) % p.count]
            a += p[i].x * q.y - q.x * p[i].y
        }
        return a / 2
    }

    static func interiorAngle(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> CGFloat {
        let v1 = CGPoint(x: a.x - b.x, y: a.y - b.y)
        let v2 = CGPoint(x: c.x - b.x, y: c.y - b.y)
        let d = (v1.x * v2.x + v1.y * v2.y) / max(hypot(v1.x, v1.y) * hypot(v2.x, v2.y), 1e-9)
        return acos(min(max(d, -1), 1))
    }

    /// Removes corners that barely turn (the straightest first).
    static func dropCollinear(_ v: [CGPoint], closed: Bool, minTurn: CGFloat) -> [CGPoint] {
        var out = v
        for _ in 0..<30 where out.count > (closed ? 3 : 2) {
            let lo = closed ? 0 : 1
            let hi = closed ? out.count : out.count - 1
            guard lo < hi else { break }
            var worst = -1
            var smallest = CGFloat.infinity
            for i in lo..<hi {
                let t = turn(out[(i - 1 + out.count) % out.count], out[i], out[(i + 1) % out.count])
                if t < smallest {
                    smallest = t
                    worst = i
                }
            }
            guard smallest < minTurn, worst >= 0 else { break }
            out.remove(at: worst)
        }
        return out
    }

    /// Joins corners closer than `minLength` (a wobble that looked like two corners).
    static func mergeClose(_ v: [CGPoint], closed: Bool, minLength: CGFloat) -> [CGPoint] {
        var out = v
        var changed = true
        while changed && out.count > (closed ? 3 : 2) {
            changed = false
            let m = closed ? out.count : out.count - 1
            for i in 0..<m {
                let j = (i + 1) % out.count
                guard dist(out[i], out[j]) < minLength else { continue }
                if !closed && i == 0 {
                    out.remove(at: 1)
                } else if !closed && j == out.count - 1 {
                    out.remove(at: i)
                } else {
                    out[i] = CGPoint(x: (out[i].x + out[j].x) / 2, y: (out[i].y + out[j].y) / 2)
                    out.remove(at: j)
                }
                changed = true
                break
            }
        }
        return out
    }

    /// RMS distance of the points from the polyline (or polygon).
    static func polylineRMS(_ pts: [CGPoint], _ v: [CGPoint], closed: Bool) -> CGFloat {
        guard v.count >= 2, !pts.isEmpty else { return .infinity }
        let m = closed ? v.count : v.count - 1
        var e: CGFloat = 0
        for q in pts {
            var best = CGFloat.infinity
            for i in 0..<m {
                best = min(best, segmentDistance(q, v[i], v[(i + 1) % v.count]))
            }
            e += best * best
        }
        return (e / CGFloat(pts.count)).squareRoot()
    }

    static func nearestIndex(_ pts: [CGPoint], to q: CGPoint) -> Int {
        var best = 0
        var bestDistance = CGFloat.infinity
        for (i, p) in pts.enumerated() {
            let d = dist(p, q)
            if d < bestDistance {
                bestDistance = d
                best = i
            }
        }
        return best
    }

    /// Every corner turns within a short stretch of the path (a real corner), not gradually (a curve).
    static func cornersAreSharp(_ pts: [CGPoint], _ v: [CGPoint], closed: Bool) -> Bool {
        let n = pts.count
        guard n >= 5, v.count >= 3 else { return false }
        let w = max(2, Int((CGFloat(n) * 0.05).rounded()))
        // Hand-drawn corners are often a little round, so a corner may take some room to turn.
        let ratio: CGFloat = v.count >= 6 ? 0.42 : 0.27
        let lo = closed ? 0 : 1
        let hi = closed ? v.count : v.count - 1
        for k in lo..<hi {
            let i = nearestIndex(pts, to: v[k])
            let a = closed ? pts[(i - w + n) % n] : pts[max(0, i - w)]
            let c = closed ? pts[(i + w) % n] : pts[min(n - 1, i + w)]
            let shortTurn = turn(a, pts[i], c)
            let cornerTurn = turn(v[(k - 1 + v.count) % v.count], v[k], v[(k + 1) % v.count])
            if shortTurn < ratio * cornerTurn { return false }
        }
        return true
    }

    /// Scales into the unit square (each axis on its own, so wide and tall drawings compare alike).
    static func normalized(_ p: [CGPoint]) -> [CGPoint] {
        let b = bounds(p)
        let sx = max(b.width, 1e-6)
        let sy = max(b.height, 1e-6)
        return p.map { CGPoint(x: ($0.x - b.minX) / sx, y: ($0.y - b.minY) / sy) }
    }

    /// Symmetric average nearest-point distance; independent of where and which way a shape was drawn.
    static func chamfer(_ a: [CGPoint], _ b: [CGPoint]) -> CGFloat {
        func one(_ x: [CGPoint], _ y: [CGPoint]) -> CGFloat {
            var s: CGFloat = 0
            for p in x {
                var m = CGFloat.infinity
                for q in y {
                    m = min(m, (p.x - q.x) * (p.x - q.x) + (p.y - q.y) * (p.y - q.y))
                }
                s += m.squareRoot()
            }
            return s / CGFloat(max(x.count, 1))
        }
        return (one(a, b) + one(b, a)) / 2
    }
}

// MARK: - Fitting

enum Fit {
    struct Circle {
        let center: CGPoint
        let radius: CGFloat
        /// Root-mean-square distance from the circle, in points.
        let rms: CGFloat
        var relative: CGFloat { rms / radius }
    }

    struct Ellipse {
        let center: CGPoint
        let rx: CGFloat
        let ry: CGFloat
        let angle: CGFloat
        /// RMS of (normalized radius − 1).
        let residual: CGFloat
        /// Approximate RMS distance from the ellipse, in points.
        let rms: CGFloat
    }

    private static func solve3(_ m: [[CGFloat]], _ v: [CGFloat]) -> [CGFloat]? {
        func det(_ a: [[CGFloat]]) -> CGFloat {
            a[0][0] * (a[1][1] * a[2][2] - a[1][2] * a[2][1])
                - a[0][1] * (a[1][0] * a[2][2] - a[1][2] * a[2][0])
                + a[0][2] * (a[1][0] * a[2][1] - a[1][1] * a[2][0])
        }
        let d = det(m)
        guard abs(d) > 1e-12 else { return nil }
        return (0..<3).map { k in
            var a = m
            for i in 0..<3 { a[i][k] = v[i] }
            return det(a) / d
        }
    }

    /// Algebraic least-squares circle (Kåsa), centered on the mean for stability.
    static func circle(_ p: [CGPoint]) -> Circle? {
        guard p.count >= 3 else { return nil }
        let n = CGFloat(p.count)
        let mx = p.reduce(0) { $0 + $1.x } / n
        let my = p.reduce(0) { $0 + $1.y } / n
        var sxx: CGFloat = 0, sxy: CGFloat = 0, syy: CGFloat = 0, sx: CGFloat = 0, sy: CGFloat = 0
        var sxz: CGFloat = 0, syz: CGFloat = 0, sz: CGFloat = 0
        for q in p {
            let x = q.x - mx
            let y = q.y - my
            let z = x * x + y * y
            sxx += x * x
            sxy += x * y
            syy += y * y
            sx += x
            sy += y
            sxz += x * z
            syz += y * z
            sz += z
        }
        guard let s = solve3([[sxx, sxy, sx], [sxy, syy, sy], [sx, sy, n]], [-sxz, -syz, -sz]) else { return nil }
        let cx = -s[0] / 2
        let cy = -s[1] / 2
        let r2 = cx * cx + cy * cy - s[2]
        guard r2 > 0 else { return nil }
        let r = r2.squareRoot()
        var e: CGFloat = 0
        for q in p {
            let d = hypot(q.x - mx - cx, q.y - my - cy) - r
            e += d * d
        }
        return Circle(center: CGPoint(x: cx + mx, y: cy + my), radius: r, rms: (e / n).squareRoot())
    }

    /// Axes from the point covariance; radii from the spread along each axis.
    static func ellipse(_ p: [CGPoint]) -> Ellipse? {
        guard p.count >= 5 else { return nil }
        let n = CGFloat(p.count)
        let mx = p.reduce(0) { $0 + $1.x } / n
        let my = p.reduce(0) { $0 + $1.y } / n
        var cxx: CGFloat = 0, cxy: CGFloat = 0, cyy: CGFloat = 0
        for q in p {
            let x = q.x - mx
            let y = q.y - my
            cxx += x * x
            cxy += x * y
            cyy += y * y
        }
        let angle = 0.5 * atan2(2 * cxy, cxx - cyy)
        let c = cos(angle)
        let s = sin(angle)
        var v1: CGFloat = 0, v2: CGFloat = 0
        for q in p {
            let x = q.x - mx
            let y = q.y - my
            let u = x * c + y * s
            let w = -x * s + y * c
            v1 += u * u
            v2 += w * w
        }
        let rx = (2 * v1 / n).squareRoot()
        let ry = (2 * v2 / n).squareRoot()
        guard rx > 1e-3, ry > 1e-3 else { return nil }
        var e: CGFloat = 0
        var ed: CGFloat = 0
        for q in p {
            let x = q.x - mx
            let y = q.y - my
            let u = x * c + y * s
            let w = -x * s + y * c
            let rho = hypot(u / rx, w / ry)
            let d = rho - 1
            e += d * d
            let distance = d * hypot(u, w) / max(rho, 1e-6)
            ed += distance * distance
        }
        return Ellipse(center: CGPoint(x: mx, y: my), rx: rx, ry: ry, angle: angle,
                       residual: (e / n).squareRoot(), rms: (ed / n).squareRoot())
    }

    /// Quadratic Bézier through the first and last point that follows `p` best (least squares). The
    /// control point is solved for the points' curve parameters, which then move to the nearest
    /// point of the curve (two Newton steps), 24 rounds. Returns the control point and the RMS
    /// distance in points.
    static func quadraticBezier(_ p: [CGPoint]) -> (control: CGPoint, rms: CGFloat)? {
        let n = p.count
        guard n >= 3, let p0 = p.first, let p2 = p.last else { return nil }
        var ts = [CGFloat](repeating: 0, count: n)
        var run: CGFloat = 0
        for i in 1..<n {
            run += Geo.dist(p[i - 1], p[i])
            ts[i] = run
        }
        guard run > 1e-6 else { return nil }
        for i in 0..<n { ts[i] /= run }
        var c = CGPoint.zero
        for _ in 0..<24 {
            var nx: CGFloat = 0
            var ny: CGFloat = 0
            var den: CGFloat = 0
            for i in 0..<n {
                let t = ts[i]
                let u = 1 - t
                let w: CGFloat = 2 * t * u
                let rx: CGFloat = p[i].x - u * u * p0.x - t * t * p2.x
                let ry: CGFloat = p[i].y - u * u * p0.y - t * t * p2.y
                nx += w * rx
                ny += w * ry
                den += w * w
            }
            guard den > 1e-9 else { return nil }
            c = CGPoint(x: nx / den, y: ny / den)
            let d2 = CGPoint(x: 2 * (p2.x - 2 * c.x + p0.x), y: 2 * (p2.y - 2 * c.y + p0.y))
            for i in 1..<(n - 1) {
                var t = ts[i]
                for _ in 0..<2 {
                    let u = 1 - t
                    let bx: CGFloat = u * u * p0.x + 2 * u * t * c.x + t * t * p2.x
                    let by: CGFloat = u * u * p0.y + 2 * u * t * c.y + t * t * p2.y
                    let d1x: CGFloat = 2 * u * (c.x - p0.x) + 2 * t * (p2.x - c.x)
                    let d1y: CGFloat = 2 * u * (c.y - p0.y) + 2 * t * (p2.y - c.y)
                    let ex = bx - p[i].x
                    let ey = by - p[i].y
                    let f1: CGFloat = ex * d1x + ey * d1y
                    let f2: CGFloat = d1x * d1x + d1y * d1y + ex * d2.x + ey * d2.y
                    if f2 > 1e-9 { t = min(max(t - f1 / f2, 0), 1) }
                }
                ts[i] = t
            }
        }
        var e: CGFloat = 0
        for i in 0..<n {
            let t = ts[i]
            let u = 1 - t
            let dx: CGFloat = u * u * p0.x + 2 * u * t * c.x + t * t * p2.x - p[i].x
            let dy: CGFloat = u * u * p0.y + 2 * u * t * c.y + t * t * p2.y - p[i].y
            e += dx * dx + dy * dy
        }
        return (c, (e / CGFloat(n)).squareRoot())
    }
}
