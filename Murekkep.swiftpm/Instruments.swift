import CoreGraphics
import Foundation

/// Points per millimetre on the page (pages are laid out in PostScript points: A4 = 595 × 842).
let pointsPerMillimetre: CGFloat = 72 / 25.4

// MARK: - Drafting instruments

enum InstrumentKind: String, CaseIterable, Identifiable {
    case ruler
    case setSquare45
    case setSquare3060
    case protractor

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ruler: return Loc.t("Cetvel")
        case .setSquare45: return Loc.t("Gönye 45°")
        case .setSquare3060: return Loc.t("Gönye 30°/60°")
        case .protractor: return Loc.t("İletki (açıölçer)")
        }
    }

    var symbol: String {
        switch self {
        case .ruler: return "ruler"
        case .setSquare45: return "triangle"
        case .setSquare3060: return "triangle.righthalf.filled"
        case .protractor: return "angle"
        }
    }
}

/// A ruler, set square or protractor lying on the document. The pencil slides along its edges.
struct Instrument: Equatable {
    var kind: InstrumentKind
    /// Document-space position: the ruler's middle, the set square's centroid, the protractor's center.
    var center: CGPoint
    /// Rotation in radians (0 = the long edge runs left to right).
    var angle: CGFloat

    static let rulerLength: CGFloat = 170 * pointsPerMillimetre
    static let rulerWidth: CGFloat = 20 * pointsPerMillimetre
    static let squareLeg: CGFloat = 95 * pointsPerMillimetre
    static let protractorRadius: CGFloat = 55 * pointsPerMillimetre

    /// Corners in the instrument's own frame (before rotation, y down).
    var localOutline: [CGPoint] {
        switch kind {
        case .ruler:
            let w = Self.rulerLength / 2
            let h = Self.rulerWidth / 2
            return [CGPoint(x: -w, y: -h), CGPoint(x: w, y: -h), CGPoint(x: w, y: h), CGPoint(x: -w, y: h)]
        case .setSquare45, .setSquare3060:
            let a = Self.squareLeg
            let b = kind == .setSquare45 ? a : a * tan(.pi / 6)
            // Right angle at bottom-left; centroid at the origin.
            let pts = [CGPoint(x: 0, y: 0), CGPoint(x: a, y: 0), CGPoint(x: 0, y: -b)]
            let cx = (a) / 3
            let cy = (-b) / 3
            return pts.map { CGPoint(x: $0.x - cx, y: $0.y - cy) }
        case .protractor:
            let r = Self.protractorRadius
            var pts: [CGPoint] = [CGPoint(x: -r, y: 0)]
            for i in 0...36 {
                let a = CGFloat.pi * CGFloat(i) / 36
                pts.append(CGPoint(x: -r * cos(a), y: -r * sin(a)))
            }
            return pts
        }
    }

    func toDocument(_ p: CGPoint) -> CGPoint {
        let c = cos(angle)
        let s = sin(angle)
        return CGPoint(x: center.x + p.x * c - p.y * s, y: center.y + p.x * s + p.y * c)
    }

    func toLocal(_ p: CGPoint) -> CGPoint {
        let dx = p.x - center.x
        let dy = p.y - center.y
        let c = cos(angle)
        let s = sin(angle)
        return CGPoint(x: dx * c + dy * s, y: -dx * s + dy * c)
    }

    var outline: [CGPoint] { localOutline.map(toDocument) }

    /// Straight edges the pencil can slide along (document space).
    var edges: [(CGPoint, CGPoint)] {
        let o = outline
        switch kind {
        case .ruler:
            return [(o[0], o[1]), (o[3], o[2])]
        case .setSquare45, .setSquare3060:
            return [(o[0], o[1]), (o[1], o[2]), (o[2], o[0])]
        case .protractor:
            return [(o[0], o[o.count - 1])]
        }
    }

    func contains(_ p: CGPoint) -> Bool {
        let q = toLocal(p)
        switch kind {
        case .ruler:
            return abs(q.x) <= Self.rulerLength / 2 && abs(q.y) <= Self.rulerWidth / 2
        case .protractor:
            return q.y <= 0 && hypot(q.x, q.y) <= Self.protractorRadius
        case .setSquare45, .setSquare3060:
            let o = localOutline
            return Self.pointInTriangle(q, o[0], o[1], o[2])
        }
    }

    static func pointInTriangle(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> Bool {
        func side(_ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint) -> CGFloat {
            (p1.x - p3.x) * (p2.y - p3.y) - (p2.x - p3.x) * (p1.y - p3.y)
        }
        let d1 = side(p, a, b)
        let d2 = side(p, b, c)
        let d3 = side(p, c, a)
        let neg = d1 < 0 || d2 < 0 || d3 < 0
        let pos = d1 > 0 || d2 > 0 || d3 > 0
        return !(neg && pos)
    }

    /// Angle shown to the user, 0…180°, counterclockwise as on paper (the view's y axis points down).
    var degrees: Int {
        var d = Int((-angle * 180 / .pi).rounded()) % 180
        if d < 0 { d += 180 }
        return d
    }
}

/// Locks a stroke onto an instrument edge (or a protractor ray) once it starts close to it.
struct EdgeSnap {
    let a: CGPoint
    let b: CGPoint
    /// Protractor rays: the stroke runs from the center outwards at a whole-degree angle.
    let isRay: Bool

    func project(_ p: CGPoint) -> CGPoint {
        if isRay {
            let dx = p.x - a.x
            let dy = p.y - a.y
            let len = hypot(dx, dy)
            guard len > 0.01 else { return a }
            let raw = atan2(dy, dx)
            let base = atan2(b.y - a.y, b.x - a.x)
            let step = CGFloat.pi / 180
            let snapped = base + ((raw - base) / step).rounded() * step
            return CGPoint(x: a.x + cos(snapped) * len, y: a.y + sin(snapped) * len)
        }
        let ab = CGPoint(x: b.x - a.x, y: b.y - a.y)
        let l2 = ab.x * ab.x + ab.y * ab.y
        guard l2 > 0 else { return a }
        let t = min(max(((p.x - a.x) * ab.x + (p.y - a.y) * ab.y) / l2, -0.05), 1.05)
        return CGPoint(x: a.x + ab.x * t, y: a.y + ab.y * t)
    }

    static func distance(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let ab = CGPoint(x: b.x - a.x, y: b.y - a.y)
        let l2 = ab.x * ab.x + ab.y * ab.y
        guard l2 > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = min(max(((p.x - a.x) * ab.x + (p.y - a.y) * ab.y) / l2, 0), 1)
        return hypot(p.x - (a.x + ab.x * t), p.y - (a.y + ab.y * t))
    }

    /// The edge (or protractor ray) a stroke starting at `p` should follow, if it starts close enough.
    static func find(for instrument: Instrument, at p: CGPoint, tolerance: CGFloat) -> EdgeSnap? {
        if instrument.kind == .protractor {
            let c = instrument.center
            if hypot(p.x - c.x, p.y - c.y) <= tolerance * 1.4 {
                let base = instrument.toDocument(CGPoint(x: Instrument.protractorRadius, y: 0))
                return EdgeSnap(a: c, b: base, isRay: true)
            }
        }
        var best: EdgeSnap?
        var bestDistance = tolerance
        for (a, b) in instrument.edges {
            let d = distance(p, a, b)
            if d <= bestDistance {
                bestDistance = d
                best = EdgeSnap(a: a, b: b, isRay: false)
            }
        }
        return best
    }
}

// MARK: - Shapes

enum ShapeKind: String, CaseIterable, Identifiable {
    case line
    case arrow
    case doubleArrow
    case rectangle
    case ellipse
    case circle
    case triangle
    case rightTriangle
    case polygon
    case axes
    case dimension

    var id: String { rawValue }

    var title: String {
        switch self {
        case .line: return Loc.t("Doğru")
        case .arrow: return Loc.t("Ok")
        case .doubleArrow: return Loc.t("Çift ok")
        case .rectangle: return Loc.t("Dikdörtgen")
        case .ellipse: return Loc.t("Elips")
        case .circle: return Loc.t("Çember (merkezden)")
        case .triangle: return Loc.t("Üçgen")
        case .rightTriangle: return Loc.t("Dik üçgen")
        case .polygon: return Loc.t("Düzgün çokgen")
        case .axes: return Loc.t("Koordinat ekseni")
        case .dimension: return Loc.t("Ölçü çizgisi")
        }
    }

    var symbol: String {
        switch self {
        case .line: return "line.diagonal"
        case .arrow: return "arrow.up.right"
        case .doubleArrow: return "arrow.left.and.right"
        case .rectangle: return "rectangle"
        case .ellipse: return "oval"
        case .circle: return "circle"
        case .triangle: return "triangle"
        case .rightTriangle: return "righttriangle"
        case .polygon: return "hexagon"
        case .axes: return "chart.xyaxis.line"
        case .dimension: return "ruler"
        }
    }
}

struct CompassState: Equatable {
    var page: Int
    /// Page-local center.
    var center: CGPoint
    var radius: CGFloat
}

struct InkSelection: Equatable {
    var page: Int
    var ids: Set<Int>
    /// Page-local bounds of the selected strokes and stickers.
    var bounds: CGRect
    var stickers: Set<UUID> = []
}

struct TextRequest: Identifiable, Equatable {
    let id = UUID()
    var page: Int
    /// Page-local point where the text goes.
    var point: CGPoint
}

/// Geometry of shapes, measurement labels and function plots as pen paths (page-local, y down).
enum ShapeBuilder {
    typealias Path = [SIMD2<Float>]

    static func paths(_ kind: ShapeKind, from a: CGPoint, to b: CGPoint, sides: Int, labelHeight: CGFloat) -> [Path] {
        let p = SIMD2<Float>(Float(a.x), Float(a.y))
        let q = SIMD2<Float>(Float(b.x), Float(b.y))
        switch kind {
        case .line:
            return [[p, q]]
        case .arrow:
            return [arrowPath(from: p, to: q)]
        case .doubleArrow:
            return [arrowPath(from: p, to: q), head(at: p, from: q)]
        case .rectangle:
            return [[p, SIMD2(q.x, p.y), q, SIMD2(p.x, q.y), p]]
        case .ellipse:
            let c = (p + q) / 2
            let r = SIMD2<Float>(abs(q.x - p.x), abs(q.y - p.y)) / 2
            return [ellipse(center: c, rx: r.x, ry: r.y)]
        case .circle:
            let r = vlength(q - p)
            return [ellipse(center: p, rx: r, ry: r)]
        case .triangle:
            return [[SIMD2(p.x, q.y), SIMD2((p.x + q.x) / 2, p.y), q, SIMD2(p.x, q.y)]]
        case .rightTriangle:
            return [[p, SIMD2(p.x, q.y), q, p]]
        case .polygon:
            let r = vlength(q - p)
            let start = atan2(q.y - p.y, q.x - p.x)
            let n = max(3, min(sides, 24))
            let pts = (0...n).map { i -> SIMD2<Float> in
                let ang = start + Float(i) * 2 * .pi / Float(n)
                return p + SIMD2(cos(ang), sin(ang)) * r
            }
            return [pts]
        case .axes:
            return axes(origin: p, extent: SIMD2<Float>(abs(q.x - p.x), abs(q.y - p.y)), labelHeight: Float(labelHeight))
        case .dimension:
            return dimension(from: p, to: q, labelHeight: Float(labelHeight))
        }
    }

    /// Length of a shape for the live label ("42,3 mm", "r = 18 mm").
    static func measurement(_ kind: ShapeKind, from a: CGPoint, to b: CGPoint) -> String {
        let dx = (b.x - a.x) / pointsPerMillimetre
        let dy = (b.y - a.y) / pointsPerMillimetre
        let len = hypot(dx, dy)
        var angle = atan2(-dy, dx) * 180 / .pi
        if angle < 0 { angle += 360 }
        switch kind {
        case .rectangle, .ellipse, .triangle, .rightTriangle, .axes:
            return "\(mm(abs(dx))) × \(mm(abs(dy)))"
        case .circle, .polygon:
            return "r = \(mm(len))"
        default:
            return "\(mm(len)) · \(Int(angle.rounded()))°"
        }
    }

    static func mm(_ v: CGFloat) -> String {
        if v >= 100 {
            return MathFormat.decimal(Double((v / 10 * 10).rounded() / 10)) + " cm"
        }
        return MathFormat.decimal(Double((v * 10).rounded() / 10)) + " mm"
    }

    static func arrowPath(from p: SIMD2<Float>, to q: SIMD2<Float>) -> Path {
        let d = q - p
        let len = vlength(d)
        guard len > 0.5 else { return [p, q] }
        let u = d / len
        let n = SIMD2<Float>(-u.y, u.x)
        let size = min(max(len * 0.18, 6), 16)
        let left = q - u * size + n * size * 0.45
        let right = q - u * size - n * size * 0.45
        return [p, q, left, q, right]
    }

    static func head(at p: SIMD2<Float>, from q: SIMD2<Float>) -> Path {
        let d = p - q
        let len = vlength(d)
        guard len > 0.5 else { return [p] }
        let u = d / len
        let n = SIMD2<Float>(-u.y, u.x)
        let size = min(max(len * 0.18, 6), 16)
        return [p - u * size + n * size * 0.45, p, p - u * size - n * size * 0.45]
    }

    static func ellipse(center c: SIMD2<Float>, rx: Float, ry: Float) -> Path {
        let n = max(24, min(160, Int((rx + ry) * 0.6)))
        return (0...n).map { i in
            let a = Float(i) / Float(n) * 2 * .pi
            return c + SIMD2(cos(a) * rx, sin(a) * ry)
        }
    }

    /// x and y axes through `origin`, ticks every 10 mm, arrow heads and labels.
    static func axes(origin o: SIMD2<Float>, extent: SIMD2<Float>, labelHeight: Float) -> [Path] {
        let ex = max(extent.x, 20)
        let ey = max(extent.y, 20)
        var out: [Path] = []
        out.append(arrowPath(from: SIMD2(o.x - ex, o.y), to: SIMD2(o.x + ex, o.y)))
        out.append(arrowPath(from: SIMD2(o.x, o.y + ey), to: SIMD2(o.x, o.y - ey)))
        let tick = Float(pointsPerMillimetre) * 10
        let t: Float = 3
        var x = tick
        while x < ex - 8 {
            out.append([SIMD2(o.x + x, o.y - t), SIMD2(o.x + x, o.y + t)])
            out.append([SIMD2(o.x - x, o.y - t), SIMD2(o.x - x, o.y + t)])
            x += tick
        }
        var y = tick
        while y < ey - 8 {
            out.append([SIMD2(o.x - t, o.y - y), SIMD2(o.x + t, o.y - y)])
            out.append([SIMD2(o.x - t, o.y + y), SIMD2(o.x + t, o.y + y)])
            y += tick
        }
        let h = labelHeight
        out += StrokeFont.paths("x", origin: SIMD2(o.x + ex - h * 0.3, o.y + h * 1.4), capHeight: h)
        out += StrokeFont.paths("y", origin: SIMD2(o.x + h * 0.6, o.y - ey + h * 0.6), capHeight: h)
        out += StrokeFont.paths("0", origin: SIMD2(o.x - h * 0.9, o.y + h * 1.3), capHeight: h * 0.8)
        return out
    }

    /// Engineering dimension: extension ticks, arrows both ways and the length written above the line.
    static func dimension(from p: SIMD2<Float>, to q: SIMD2<Float>, labelHeight: Float) -> [Path] {
        let d = q - p
        let len = vlength(d)
        guard len > 2 else { return [[p, q]] }
        let u = d / len
        let n = SIMD2<Float>(-u.y, u.x)
        let ext: Float = 6
        var out: [Path] = [
            [p + n * ext, p - n * ext],
            [q + n * ext, q - n * ext],
            arrowPath(from: p, to: q),
            head(at: p, from: q),
        ]
        let text = mm(CGFloat(len) / pointsPerMillimetre)
        let width = StrokeFont.width(text) * labelHeight / 10
        // Keep the text upright: write along the line in the direction that reads left to right.
        let along = u.x < 0 ? -u : u
        let up = SIMD2<Float>(along.y, -along.x)
        let mid = (p + q) / 2
        let origin = mid - along * (width / 2) + up * (labelHeight * 0.35)
        let flat = StrokeFont.paths(text, origin: SIMD2(0, 0), capHeight: labelHeight)
        for path in flat {
            out.append(path.map { v in origin + along * v.x - up * v.y })
        }
        return out
    }

    /// Breaks paths into dashes (lengths in points).
    static func dashed(_ paths: [Path], dash: Float = 6, gap: Float = 4) -> [Path] {
        var out: [Path] = []
        for path in paths where path.count >= 2 {
            var current: Path = [path[0]]
            var drawing = true
            var left = dash
            for i in 1..<path.count {
                var a = path[i - 1]
                let b = path[i]
                var segment = vlength(b - a)
                while segment > 0 {
                    let step = min(left, segment)
                    let point = a + (b - a) * (step / max(vlength(b - a), 1e-6))
                    if drawing { current.append(point) }
                    segment -= step
                    left -= step
                    a = point
                    if left <= 1e-4 {
                        if drawing {
                            if current.count >= 2 { out.append(current) }
                            current = []
                        } else {
                            current = [a]
                        }
                        drawing.toggle()
                        left = drawing ? dash : gap
                    }
                }
            }
            if drawing && current.count >= 2 { out.append(current) }
        }
        return out
    }

    /// y = f(x) on axes centred at `center`, `size` points wide, for x in [xMin, xMax].
    static func plot(_ expression: MathExpr, variable: String, xMin: Double, xMax: Double, center: CGPoint,
                     size: CGFloat, labelHeight: CGFloat) -> [Path]? {
        guard xMax > xMin else { return nil }
        let samples = 600
        var values: [(Double, Double)] = []
        for i in 0...samples {
            let x = xMin + (xMax - xMin) * Double(i) / Double(samples)
            if let y = expression.evaluate([variable: x]), y.isFinite {
                values.append((x, y))
            }
        }
        guard values.count > 2 else { return nil }
        let ys = values.map(\.1).sorted()
        // Ignore extreme outliers near poles so the interesting part fills the frame.
        let lo = ys[Int(Double(ys.count - 1) * 0.02)]
        let hi = ys[Int(Double(ys.count - 1) * 0.98)]
        var yMin = min(lo, 0)
        var yMax = max(hi, 0)
        if yMax - yMin < 1e-9 {
            yMin -= 1
            yMax += 1
        }
        let half = Double(size) / 2
        let sx = Double(size) / (xMax - xMin)
        let sy = Double(size) * 0.8 / (yMax - yMin)
        let cx = Double(center.x)
        let cy = Double(center.y)
        let xMid = (xMin + xMax) / 2
        let yMid = (yMin + yMax) / 2
        func page(_ x: Double, _ y: Double) -> SIMD2<Float> {
            SIMD2(Float(cx + (x - xMid) * sx), Float(cy - (y - yMid) * sy))
        }
        var out: [Path] = []
        // Axes where zero is in range, otherwise along the frame edge.
        let axisY = page(0, min(max(0, yMin), yMax)).y
        let axisX = page(min(max(0, xMin), xMax), 0).x
        out.append(arrowPath(from: SIMD2(Float(cx - half) - 6, axisY), to: SIMD2(Float(cx + half) + 10, axisY)))
        out.append(arrowPath(from: SIMD2(axisX, Float(cy + Double(size) * 0.45) + 6), to: SIMD2(axisX, Float(cy - Double(size) * 0.45) - 10)))
        // Curve, split where it jumps (poles) or is undefined.
        var current: Path = []
        var last: (Double, Double)?
        for (x, y) in values {
            let inRange = y >= yMin - (yMax - yMin) * 0.6 && y <= yMax + (yMax - yMin) * 0.6
            if let l = last, abs(y - l.1) > (yMax - yMin) * 0.8 || !inRange {
                if current.count >= 2 { out.append(current) }
                current = []
            }
            if inRange { current.append(page(x, y)) }
            last = (x, y)
        }
        if current.count >= 2 { out.append(current) }
        let h = Float(labelHeight)
        out += StrokeFont.paths(MathFormat.decimal(xMax), origin: SIMD2(Float(cx + half) - h * 2, axisY + h * 1.5), capHeight: h * 0.8)
        out += StrokeFont.paths(MathFormat.decimal(yMax), origin: SIMD2(axisX + h * 0.5, Float(cy - Double(size) * 0.4)), capHeight: h * 0.8)
        return out
    }
}
