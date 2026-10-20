import CoreGraphics
import Foundation

/// What a handle drag did: the text for the bubble next to the pencil, and whether the handle
/// settled on something (a right angle, a level or upright side, a circle) for a click.
struct ShapeHandleFeedback {
    var label: String?
    var snapped: Bool
}

/// A recognized shape that stays adjustable after the pencil lifts. Polygons and broken lines get a
/// handle on every corner, circles and ellipses on the ends of their axes, and every shape one in
/// its middle that moves it whole. The handles stay until the next touch somewhere else.
struct EditableShape: Equatable {
    enum Kind: Equatable {
        /// Closed outline through `points` (triangles, rectangles, squares, other polygons).
        case polygon
        /// Open line through `points` (a straight line has two).
        case polyline
        case oval(center: CGPoint, rx: CGFloat, ry: CGFloat, angle: CGFloat)
        /// A bend between two ends; its handle sits on the curve halfway.
        case curve(ShapeMatch.Curve)
    }

    var kind: Kind
    /// Corners in page space (empty for an oval).
    var points: [CGPoint]
    var title: String

    init(kind: Kind, points: [CGPoint], title: String) {
        self.kind = kind
        self.points = points
        self.title = title
    }

    init?(match: ShapeMatch) {
        switch match.kind {
        case .line, .polyline:
            let corners = match.corners.count >= 2 ? match.corners : [match.path.first, match.path.last].compactMap { $0 }
            guard corners.count >= 2 else { return nil }
            self.init(kind: .polyline, points: corners, title: match.title)
        case .polygon, .rectangle:
            guard match.corners.count >= 3 else { return nil }
            self.init(kind: .polygon, points: match.corners, title: match.title)
        case .circle, .ellipse:
            guard let o = match.oval else { return nil }
            self.init(kind: .oval(center: o.center, rx: o.rx, ry: o.ry, angle: o.angle), points: [], title: match.title)
        case .curve:
            guard let c = match.curve else { return nil }
            self.init(kind: .curve(c), points: [], title: match.title)
        }
    }

    /// Average of the corners (the middle of an oval; for a curve, between its ends and its bend).
    var middle: CGPoint {
        if case let .oval(center, _, _, _) = kind { return center }
        if case let .curve(c) = kind {
            let m = c.middle
            return CGPoint(x: (c.start.x + m.x + c.end.x) / 3, y: (c.start.y + m.y + c.end.y) / 3)
        }
        guard !points.isEmpty else { return .zero }
        let n = CGFloat(points.count)
        return CGPoint(x: points.reduce(CGFloat(0)) { $0 + $1.x } / n, y: points.reduce(CGFloat(0)) { $0 + $1.y } / n)
    }

    /// Handle positions in page space. The last one is always the middle, which moves everything.
    var handles: [CGPoint] {
        switch kind {
        case .polygon, .polyline:
            return points + [middle]
        case let .oval(center, rx, ry, angle):
            let u = CGPoint(x: cos(angle), y: sin(angle))
            let v = CGPoint(x: -sin(angle), y: cos(angle))
            return [CGPoint(x: center.x + u.x * rx, y: center.y + u.y * rx),
                    CGPoint(x: center.x + v.x * ry, y: center.y + v.y * ry),
                    CGPoint(x: center.x - u.x * rx, y: center.y - u.y * rx),
                    CGPoint(x: center.x - v.x * ry, y: center.y - v.y * ry),
                    center]
        case let .curve(c):
            return [c.start, c.middle, c.end, middle]
        }
    }

    /// The outline to ink.
    func path() -> [CGPoint] {
        switch kind {
        case .polygon:
            guard let first = points.first else { return [] }
            return points + [first]
        case .polyline:
            return points
        case let .oval(center, rx, ry, angle):
            let n = max(48, min(720, Int((CGFloat.pi * (rx + ry) / 3).rounded(.up))))
            let c = cos(angle)
            let s = sin(angle)
            return (0...n).map { i -> CGPoint in
                let t = 2 * CGFloat.pi * CGFloat(i) / CGFloat(n) - CGFloat.pi / 2
                let x = cos(t) * rx
                let y = sin(t) * ry
                return CGPoint(x: center.x + x * c - y * s, y: center.y + x * s + y * c)
            }
        case let .curve(c):
            return c.path()
        }
    }

    /// The same shape grown by `scale` and turned by `angle` around `anchor` (while the pencil that
    /// drew it still holds it).
    func transformed(anchor: CGPoint, scale: CGFloat, angle: CGFloat) -> EditableShape {
        let c = cos(angle)
        let s = sin(angle)
        func place(_ p: CGPoint) -> CGPoint {
            let x = (p.x - anchor.x) * scale
            let y = (p.y - anchor.y) * scale
            return CGPoint(x: anchor.x + x * c - y * s, y: anchor.y + x * s + y * c)
        }
        var copy = self
        copy.points = points.map { place($0) }
        if case let .oval(center, rx, ry, a) = kind {
            copy.kind = .oval(center: place(center), rx: rx * scale, ry: ry * scale, angle: a + angle)
        }
        if case let .curve(c) = kind {
            copy.kind = .curve(ShapeMatch.Curve(start: place(c.start), control: place(c.control), end: place(c.end)))
        }
        return copy
    }

    /// Moves handle `index` to `target` (page space). `snap` is how close, in points, a corner has
    /// to come to a level or upright line through its neighbour before it settles there.
    mutating func move(handle index: Int, to target: CGPoint, snap: CGFloat) -> ShapeHandleFeedback {
        let all = handles
        guard all.indices.contains(index) else { return ShapeHandleFeedback(label: nil, snapped: false) }
        if index == all.count - 1 {
            translate(by: CGPoint(x: target.x - all[index].x, y: target.y - all[index].y))
            return ShapeHandleFeedback(label: nil, snapped: false)
        }
        switch kind {
        case .polygon, .polyline:
            return moveCorner(index, to: target, snap: snap)
        case let .oval(center, rx, ry, angle):
            return moveAxis(index, to: target, center: center, rx: rx, ry: ry, angle: angle)
        case let .curve(c):
            return moveCurveHandle(index, to: target, curve: c, snap: snap)
        }
    }

    private mutating func translate(by d: CGPoint) {
        func shift(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x + d.x, y: p.y + d.y) }
        points = points.map { shift($0) }
        if case let .oval(center, rx, ry, angle) = kind {
            kind = .oval(center: shift(center), rx: rx, ry: ry, angle: angle)
        }
        if case let .curve(c) = kind {
            kind = .curve(ShapeMatch.Curve(start: shift(c.start), control: shift(c.control), end: shift(c.end)))
        }
    }

    /// Curve handles: 0 and 2 are the ends, 1 the bend. Moving an end keeps the bend where it is;
    /// the ends settle level or upright with each other.
    private mutating func moveCurveHandle(_ i: Int, to target: CGPoint, curve c: ShapeMatch.Curve,
                                          snap: CGFloat) -> ShapeHandleFeedback {
        var next = c
        if i == 1 {
            next.control = ShapeMatch.Curve.control(start: c.start, through: target, end: c.end)
            kind = .curve(next)
            return ShapeHandleFeedback(label: title, snapped: false)
        }
        var p = target
        var snapped = false
        let other = i == 0 ? c.end : c.start
        if abs(p.x - other.x) < snap {
            p.x = other.x
            snapped = true
        }
        if abs(p.y - other.y) < snap {
            p.y = other.y
            snapped = true
        }
        let bend = c.middle
        if i == 0 { next.start = p } else { next.end = p }
        next.control = ShapeMatch.Curve.control(start: next.start, through: bend, end: next.end)
        kind = .curve(next)
        return ShapeHandleFeedback(label: ShapeBuilder.mm(Geo.dist(next.start, next.end) / pointsPerMillimetre), snapped: snapped)
    }

    private mutating func moveCorner(_ i: Int, to target: CGPoint, snap: CGFloat) -> ShapeHandleFeedback {
        let n = points.count
        guard points.indices.contains(i), n >= 2 else { return ShapeHandleFeedback(label: nil, snapped: false) }
        let closed = kind == .polygon
        let prev: CGPoint? = (closed || i > 0) ? points[(i - 1 + n) % n] : nil
        let next: CGPoint? = (closed || i < n - 1) ? points[(i + 1) % n] : nil
        var p = target
        var snapped = false
        // Level or upright with a neighbour.
        for q in [prev, next].compactMap({ $0 }) {
            if abs(p.x - q.x) < snap {
                p.x = q.x
                snapped = true
            }
            if abs(p.y - q.y) < snap {
                p.y = q.y
                snapped = true
            }
        }
        // A right angle at this corner: it sits on the circle over its two neighbours (Thales).
        if !snapped, let a = prev, let c = next {
            let angle = Geo.interiorAngle(a, p, c)
            if abs(angle - .pi / 2) < 5 * .pi / 180 {
                let mid = CGPoint(x: (a.x + c.x) / 2, y: (a.y + c.y) / 2)
                let r = Geo.dist(a, c) / 2
                let d = Geo.dist(p, mid)
                if d > 1e-3 {
                    p = CGPoint(x: mid.x + (p.x - mid.x) * r / d, y: mid.y + (p.y - mid.y) * r / d)
                    snapped = true
                }
            }
        }
        points[i] = p
        if let a = prev, let c = next {
            let degrees = Int((Geo.interiorAngle(a, p, c) * 180 / .pi).rounded())
            return ShapeHandleFeedback(label: "\(degrees)°", snapped: snapped)
        }
        if let q = prev ?? next {
            return ShapeHandleFeedback(label: ShapeBuilder.mm(Geo.dist(p, q) / pointsPerMillimetre), snapped: snapped)
        }
        return ShapeHandleFeedback(label: nil, snapped: snapped)
    }

    /// Axis handles: 0 and 2 on the first axis, 1 and 3 on the second. Dragging one sets that radius
    /// and turns the oval; radii that come close become a circle.
    private mutating func moveAxis(_ i: Int, to target: CGPoint, center: CGPoint, rx: CGFloat, ry: CGFloat,
                                   angle: CGFloat) -> ShapeHandleFeedback {
        let dx = target.x - center.x
        let dy = target.y - center.y
        let r = max(hypot(dx, dy), 4)
        let along = atan2(dy, dx)
        var newRx = rx
        var newRy = ry
        var newAngle = angle
        switch i {
        case 0:
            newRx = r
            newAngle = along
        case 2:
            newRx = r
            newAngle = along + .pi
        case 1:
            newRy = r
            newAngle = along - .pi / 2
        default:
            newRy = r
            newAngle = along + .pi / 2
        }
        var snapped = false
        // The turn settles on level and upright.
        let quarter = CGFloat.pi / 2
        let nearest = (newAngle / quarter).rounded() * quarter
        if abs(newAngle - nearest) < 4 * .pi / 180 {
            newAngle = nearest
        }
        let circle = abs(newRx - newRy) < 0.05 * max(newRx, newRy)
        if circle {
            if i % 2 == 0 { newRy = newRx } else { newRx = newRy }
            snapped = true
        }
        kind = .oval(center: center, rx: newRx, ry: newRy, angle: newAngle)
        title = circle ? Loc.t("Daire") : Loc.t("Elips")
        let size = circle ? ShapeBuilder.mm(2 * newRx / pointsPerMillimetre)
                          : ShapeBuilder.mm(2 * newRx / pointsPerMillimetre) + " × " + ShapeBuilder.mm(2 * newRy / pointsPerMillimetre)
        return ShapeHandleFeedback(label: "\(title) · \(size)", snapped: snapped)
    }
}

/// The shape on a page whose handles are showing.
struct ShapeEditState: Equatable {
    var page: Int
    /// The stroke that draws the shape (it gets a new id every time the shape is redrawn).
    var strokeID: Int
    var shape: EditableShape
}
