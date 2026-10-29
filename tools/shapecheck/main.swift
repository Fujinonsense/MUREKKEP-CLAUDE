import Foundation

// Runs the iPad's real shape code on Windows over deterministic hand-drawn strokes and writes what it
// answers into a plain-text fixture that the Android edition's JUnit tests (ShapeRecognizerTest,
// ShapeEditingTest, ShapeToolTest, StrokeBuilderTest) hold the Kotlin port to: the same kinds, names,
// labels and points. The strokes are shaken like a hand from a seeded generator, so the fixture is the
// same on every run and every case is a drawing the recognizer really sees.
// usage: shapecheck.exe <path of shapes.txt>   (tools/shapecheck/run.ps1 builds and runs it)
//
// The fixture is lines of "key value…" grouped in "case <type> <name>" … "end". Inputs (strokes, pen
// samples, handle targets) are rounded to thousandths first, so their decimal form reads back exactly;
// Float values are written in their shortest round-trip form, also exact; the iPad's other answers
// get ten significant digits, plenty for the tests' tolerance of 1e-6.

// MARK: - Writing

var out: [String] = []
var failures = 0

func emit(_ line: String) { out.append(line) }
func f(_ v: CGFloat) -> String { String(format: "%.10g", Double(v)) }
func f(_ v: Float) -> String { "\(v)" }
func f(_ v: Int) -> String { "\(v)" }
func join(_ p: [CGPoint]) -> String { p.map { "\(f($0.x)) \(f($0.y))" }.joined(separator: " ") }
func emitPoints(_ key: String, _ p: [CGPoint]) { emit(p.isEmpty ? key : "\(key) \(join(p))") }
func emitInk(_ key: String, _ p: [InkPoint]) {
    emit(p.isEmpty ? key : key + " " + p.map { "\(f($0.x)) \(f($0.y)) \(f($0.r)) \(f($0.ink))" }.joined(separator: " "))
}
func emitVec(_ key: String, _ p: [SIMD2<Float>]) {
    emit(p.isEmpty ? key : key + " " + p.map { "\(f($0.x)) \(f($0.y))" }.joined(separator: " "))
}

/// Inputs are rounded to thousandths so they read back exactly from their decimal form.
func r3(_ v: CGFloat) -> CGFloat { (v * 1000).rounded() / 1000 }
func r3(_ p: CGPoint) -> CGPoint { CGPoint(x: r3(p.x), y: r3(p.y)) }

func check(_ ok: Bool, _ what: String) {
    print(ok ? "ok   \(what)" : "FAIL \(what)")
    if !ok { failures += 1 }
}

// MARK: - A hand

/// A 64-bit linear congruential generator: the same strokes on every machine.
struct Rand {
    var state: UInt64

    init(_ seed: UInt64) {
        state = seed &* 2862933555777941757 &+ 3037000493
    }

    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 11) * (1.0 / 9007199254740992.0)
    }

    mutating func between(_ lo: Double, _ hi: Double) -> Double { lo + (hi - lo) * next() }
}

/// Points about `spacing` apart along the straight pieces between `corners` (back to the first one
/// when closed, then `overshoot` points further along the first side), shaken like a hand: a slow
/// sway across the line and a fine tremor. The corners themselves stay where they are.
func hand(_ corners: [CGPoint], closed: Bool, rng: inout Rand, sway: Double = 1.2, tremor: Double = 0.5,
          spacing: Double = 2.5, overshoot: Double = 0) -> [CGPoint] {
    var stops = corners
    if closed {
        stops.append(corners[0])
        if overshoot > 0 {
            let a = corners[0]
            let b = corners[1]
            let l = hypot(b.x - a.x, b.y - a.y)
            stops.append(CGPoint(x: a.x + (b.x - a.x) / l * overshoot, y: a.y + (b.y - a.y) / l * overshoot))
        }
    }
    let phase = rng.between(0, 2 * .pi)
    let wave = rng.between(0.03, 0.06)
    var points: [CGPoint] = []
    var travelled = 0.0
    for i in 0..<(stops.count - 1) {
        let a = stops[i]
        let b = stops[i + 1]
        let l = hypot(b.x - a.x, b.y - a.y)
        let n = max(1, Int(l / spacing))
        let ux = (b.x - a.x) / l
        let uy = (b.y - a.y) / l
        for k in 0..<n {
            let t = Double(k) / Double(n)
            let d = travelled + l * t
            let side = (k == 0 ? 0 : sway * sin(phase + d * wave)) + rng.between(-tremor, tremor)
            points.append(r3(CGPoint(x: a.x + ux * l * t - uy * side, y: a.y + uy * l * t + ux * side)))
        }
        travelled += l
    }
    points.append(r3(stops[stops.count - 1]))
    return points
}

/// An oval drawn by hand (after tests/ports/badcircles.py): a slow wobble of the radius, a landing
/// hook at the start, a tremor, and `overshoot` degrees past the start.
func oval(center: CGPoint, rx: Double, ry: Double, angle: Double, rng: inout Rand, wobble: Double = 0.03,
          overshoot: Double = 20, hook: Double = 0.06, start: Double? = nil, clockwise: Bool = true,
          tremor: Double = 0.4) -> [CGPoint] {
    let amp = (0..<4).map { _ in rng.between(0, wobble) }
    let ph = (0..<4).map { _ in rng.between(0, 2 * .pi) }
    let t0 = start ?? rng.between(0, 2 * .pi)
    let total = 2 * .pi + overshoot * .pi / 180
    let n = max(24, Int(.pi * (rx + ry) * total / (2 * .pi) / 2.5))
    let dir = clockwise ? 1.0 : -1.0
    var points: [CGPoint] = []
    for i in 0...n {
        let t = total * Double(i) / Double(n)
        var k = 1.0
        for j in 0..<4 { k += amp[j] * sin(Double(j + 2) * t + ph[j]) }
        let landing = 25 * Double.pi / 180
        if t < landing { k *= 1 - hook * (1 - t / landing) }
        let a = t0 + dir * t
        let x = rx * k * cos(a)
        let y = ry * k * sin(a)
        let jx = rng.between(-tremor, tremor)
        let jy = rng.between(-tremor, tremor)
        points.append(r3(CGPoint(x: center.x + x * cos(angle) - y * sin(angle) + jx,
                                 y: center.y + x * sin(angle) + y * cos(angle) + jy)))
    }
    return points
}

/// A quadratic bend from `s` to `e` pulled towards `c`, with a tremor.
func bend(_ s: CGPoint, _ c: CGPoint, _ e: CGPoint, rng: inout Rand, tremor: Double = 0.5) -> [CGPoint] {
    let len = hypot(c.x - s.x, c.y - s.y) + hypot(e.x - c.x, e.y - c.y)
    let n = max(12, Int(len / 2.5))
    return (0...n).map { i in
        let t = Double(i) / Double(n)
        let u = 1 - t
        let x = u * u * s.x + 2 * u * t * c.x + t * t * e.x
        let y = u * u * s.y + 2 * u * t * c.y + t * t * e.y
        return r3(CGPoint(x: x + rng.between(-tremor, tremor), y: y + rng.between(-tremor, tremor)))
    }
}

/// The corners of a regular polygon.
func regular(_ n: Int, center: CGPoint, r: Double, turn: Double) -> [CGPoint] {
    (0..<n).map { i in
        let a = turn + 2 * .pi * Double(i) / Double(n)
        return CGPoint(x: center.x + r * cos(a), y: center.y + r * sin(a))
    }
}

/// A square with rounded corners (a superellipse), closed with an overshoot.
func roundedSquare(center: CGPoint, half: Double, power: Double, rng: inout Rand) -> [CGPoint] {
    let n = Int(8 * half / 2.5)
    var points: [CGPoint] = []
    for i in 0...(n + n / 12) {
        let a = 2 * .pi * Double(i) / Double(n) - .pi / 4
        let c = cos(a)
        let s = sin(a)
        let x = (c < 0 ? -1.0 : 1.0) * pow(abs(c), 2 / power) * half
        let y = (s < 0 ? -1.0 : 1.0) * pow(abs(s), 2 / power) * half
        points.append(r3(CGPoint(x: center.x + x + rng.between(-0.4, 0.4), y: center.y + y + rng.between(-0.4, 0.4))))
    }
    return points
}

/// A random walk: a scribble.
func walk(start: CGPoint, steps: Int, step: Double, rng: inout Rand) -> [CGPoint] {
    var points = [start]
    var heading = rng.between(0, 2 * .pi)
    var p = start
    for _ in 0..<steps {
        heading += rng.between(-1.4, 1.4)
        p = CGPoint(x: p.x + cos(heading) * step, y: p.y + sin(heading) * step)
        points.append(r3(p))
    }
    return points
}

func rot(_ x: Double, _ y: Double, _ a: Double) -> CGPoint { CGPoint(x: x * cos(a) - y * sin(a), y: x * sin(a) + y * cos(a)) }
func add(_ p: CGPoint, _ dx: Double, _ dy: Double) -> CGPoint { CGPoint(x: p.x + dx, y: p.y + dy) }

// MARK: - The iPad code that lives in UIKit files

/// `EditorModel.restroke(_:along:)` of the iPad on the points alone (EditorModel.swift needs SwiftUI,
/// which Windows has not): the same lines, with the stroke's brush, color, width, birth, seed and
/// duration left out.
func restroke(_ points: [InkPoint], along path: [CGPoint]) -> [InkPoint] {
    let n = Float(max(points.count, 1))
    let r = points.reduce(Float(0)) { $0 + $1.r } / n
    let ink = points.reduce(Float(0)) { $0 + $1.ink } / n
    let dense = path.count >= 2 ? Geo.densify(path, spacing: CGFloat(max(1.5, r * 0.7))) : path
    return dense.map { InkPoint(x: Float($0.x), y: Float($0.y), r: r, ink: ink) }
}

/// `CanvasView.snappedShapeEnd(_:from:)` of the iPad (CanvasView.swift needs UIKit), with the view's
/// current shape kind as a parameter: lines, arrows and dimensions click to 15° steps; boxes to
/// squares when nearly square.
func snappedShapeEnd(_ kind: ShapeKind, _ p: CGPoint, from a: CGPoint) -> CGPoint {
    let dx = p.x - a.x
    let dy = p.y - a.y
    switch kind {
    case .line, .arrow, .doubleArrow, .dimension:
        let len = hypot(dx, dy)
        let angle = atan2(dy, dx)
        let step = CGFloat.pi / 12
        let nearest = (angle / step).rounded() * step
        if abs(angle - nearest) < 0.05 {
            return CGPoint(x: a.x + cos(nearest) * len, y: a.y + sin(nearest) * len)
        }
        return p
    case .rectangle, .ellipse:
        if abs(abs(dx) - abs(dy)) < max(abs(dx), abs(dy)) * 0.06 {
            let s = max(abs(dx), abs(dy))
            return CGPoint(x: a.x + (dx < 0 ? -s : s), y: a.y + (dy < 0 ? -s : s))
        }
        return p
    default:
        return p
    }
}

// MARK: - Shapes and their handles

func kindName(_ k: ShapeMatch.Kind) -> String {
    switch k {
    case .line: return "line"
    case .polyline: return "polyline"
    case .polygon: return "polygon"
    case .rectangle: return "rectangle"
    case .circle: return "circle"
    case .ellipse: return "ellipse"
    case .curve: return "curve"
    }
}

func emitMatch(_ m: ShapeMatch?) {
    guard let m else {
        emit("match -")
        return
    }
    emit("match \(kindName(m.kind)) \(m.title)")
    emit("closed \(m.isClosed ? 1 : 0)")
    emitPoints("path", m.path)
    emitPoints("corners", m.corners)
    if let o = m.oval { emit("oval \(f(o.center.x)) \(f(o.center.y)) \(f(o.rx)) \(f(o.ry)) \(f(o.angle))") }
    if let c = m.curve {
        emit("curve \(f(c.start.x)) \(f(c.start.y)) \(f(c.control.x)) \(f(c.control.y)) \(f(c.end.x)) \(f(c.end.y))")
    }
}

/// The shape's kind, title, corners (or oval, or curve), handles and middle; its outline too when
/// `path` (once per shape and after the transform: it is long for an oval).
func emitShape(_ s: EditableShape, path: Bool = true) {
    let kind: String
    switch s.kind {
    case .polygon: kind = "polygon"
    case .polyline: kind = "polyline"
    case .oval: kind = "oval"
    case .curve: kind = "curve"
    }
    emit("shape \(kind) \(s.title)")
    emitPoints("spoints", s.points)
    if case let .oval(center, rx, ry, angle) = s.kind {
        emit("soval \(f(center.x)) \(f(center.y)) \(f(rx)) \(f(ry)) \(f(angle))")
    }
    if case let .curve(c) = s.kind {
        emit("scurve \(f(c.start.x)) \(f(c.start.y)) \(f(c.control.x)) \(f(c.control.y)) \(f(c.end.x)) \(f(c.end.y))")
    }
    emitPoints("handles", s.handles)
    emit("middle \(f(s.middle.x)) \(f(s.middle.y))")
    if path { emitPoints("spath", s.path()) }
}

/// The shape's handles, a few drags of them (one that settles level with a neighbour, one onto a
/// right angle, one free, the middle), the pen's resize-and-turn, and the stroke redrawn along it.
func edit(_ match: ShapeMatch) {
    guard var shape = EditableShape(match: match) else {
        emit("editable -")
        return
    }
    emitShape(shape)
    if caseCount % 3 == 0 {
        // A stroke of varying width and ink redrawn along the shape (every third case: it is long).
        let path = shape.path()
        let ink = path.enumerated().map { i, p in
            InkPoint(x: Float(p.x), y: Float(p.y), r: Float(2.2 + 0.6 * sin(Double(i))), ink: Float(0.5 + 0.3 * cos(Double(i))))
        }
        emitInk("restroke_in", ink)
        emitInk("restroke_out", restroke(ink, along: path))
    }

    func move(_ index: Int, _ target: CGPoint, snap: CGFloat = 9) {
        let t = r3(target)
        let feedback = shape.move(handle: index, to: t, snap: snap)
        emit("move \(index) \(f(t.x)) \(f(t.y)) \(f(snap))")
        emit("label \(feedback.label ?? "-")")
        emit("snapped \(feedback.snapped ? 1 : 0)")
        emitShape(shape, path: false)
    }

    switch shape.kind {
    case .polygon, .polyline:
        let n = shape.points.count
        // Level with the next corner.
        move(0, CGPoint(x: shape.points[0].x + 14, y: shape.points[1 % n].y + 3))
        if n >= 3 {
            // A right angle at corner 1: just outside the circle over its neighbours.
            let a = shape.points[0]
            let c = shape.points[2 % n]
            let p = shape.points[1]
            let mid = CGPoint(x: (a.x + c.x) / 2, y: (a.y + c.y) / 2)
            let r = hypot(c.x - a.x, c.y - a.y) / 2
            let l = max(hypot(c.x - a.x, c.y - a.y), 1)
            var nx = -(c.y - a.y) / l
            var ny = (c.x - a.x) / l
            if (p.x - mid.x) * nx + (p.y - mid.y) * ny < 0 {
                nx = -nx
                ny = -ny
            }
            move(1, CGPoint(x: mid.x + nx * r * 1.03, y: mid.y + ny * r * 1.03))
        }
        // The last corner, freely.
        move(n - 1, add(shape.points[n - 1], 11, -17))
        // Everything.
        move(n, add(shape.handles[n], 10, -5))
    case let .oval(center, rx, ry, angle):
        // The first axis, longer and 2° off: it settles level (or upright) again.
        let u = rot(rx * 1.3, 0, angle + 2 * .pi / 180)
        move(0, add(center, u.x, u.y))
        // The second axis, shorter.
        if case let .oval(c2, _, ry2, a2) = shape.kind {
            let v = rot(0, ry2 * 0.8, a2)
            move(1, add(c2, v.x, v.y))
        }
        // The second axis as long as the first: a circle.
        if case let .oval(c3, rx3, _, a3) = shape.kind {
            let v = rot(0, rx3 * 1.02, a3)
            move(3, add(c3, -v.x, -v.y))
        }
        // The first axis turned by 30°.
        if case let .oval(c4, rx4, _, a4) = shape.kind {
            let u = rot(rx4, 0, a4 + 30 * .pi / 180)
            move(2, add(c4, -u.x, -u.y))
        }
        move(4, add(shape.handles[4], 10, -5))
        _ = ry
    case let .curve(c):
        move(1, add(c.middle, 5, 15))
        if case let .curve(c2) = shape.kind {
            // The start upright with the end: its x settles on the end's.
            move(0, CGPoint(x: c2.end.x + 3, y: c2.start.y - 20))
        }
        if case let .curve(c3) = shape.kind {
            move(2, add(c3.end, 12, 9))
        }
        move(3, add(shape.handles[3], 10, -5))
    }
    let anchor = r3(shape.middle)
    shape = shape.transformed(anchor: anchor, scale: 1.5, angle: 0.3)
    emit("transform \(f(anchor.x)) \(f(anchor.y)) 1.5 0.3")
    emitShape(shape)
}

var titles: [String: Int] = [:]
var kinds: [String: Int] = [:]
var nilCount = 0
var caseCount = 0

@discardableResult
func recognizeCase(_ name: String, _ stroke: [CGPoint]) -> ShapeMatch? {
    caseCount += 1
    emit("case recognize \(name)")
    emitPoints("in", stroke)
    let m = ShapeRecognizer.recognize(stroke)
    emitMatch(m)
    if let m {
        edit(m)
        titles[m.title, default: 0] += 1
        kinds[kindName(m.kind), default: 0] += 1
        print("  \(name): \(kindName(m.kind)) \(m.title)")
    } else {
        nilCount += 1
        print("  \(name): -")
    }
    emit("end")
    return m
}

var rng = Rand(20261029)
let pi = Double.pi

// Lines.
recognizeCase("line_level", hand([CGPoint(x: 40, y: 100), CGPoint(x: 180, y: 102)], closed: false, rng: &rng))
recognizeCase("line_diagonal", hand([CGPoint(x: 30, y: 30), CGPoint(x: 150, y: 140)], closed: false, rng: &rng, sway: 2))
recognizeCase("line_upright", hand([CGPoint(x: 90, y: 20), CGPoint(x: 92, y: 160)], closed: false, rng: &rng))
recognizeCase("line_short", hand([CGPoint(x: 50, y: 50), CGPoint(x: 70, y: 56)], closed: false, rng: &rng, sway: 0.3, tremor: 0.2, spacing: 1.5))
recognizeCase("line_back_left", hand([CGPoint(x: 200, y: 80), CGPoint(x: 60, y: 60)], closed: false, rng: &rng))

// Broken lines.
recognizeCase("angle_l", hand([CGPoint(x: 40, y: 40), CGPoint(x: 40, y: 140), CGPoint(x: 150, y: 140)], closed: false, rng: &rng))
recognizeCase("angle_v", hand([CGPoint(x: 40, y: 40), CGPoint(x: 90, y: 140), CGPoint(x: 150, y: 50)], closed: false, rng: &rng))
recognizeCase("zigzag_3", hand([CGPoint(x: 20, y: 100), CGPoint(x: 60, y: 30), CGPoint(x: 100, y: 100), CGPoint(x: 140, y: 30)], closed: false, rng: &rng))
recognizeCase("zigzag_4", hand([CGPoint(x: 20, y: 100), CGPoint(x: 55, y: 30), CGPoint(x: 90, y: 100), CGPoint(x: 125, y: 30), CGPoint(x: 160, y: 100)],
                               closed: false, rng: &rng))
recognizeCase("stairs", hand([CGPoint(x: 20, y: 140), CGPoint(x: 60, y: 140), CGPoint(x: 60, y: 100), CGPoint(x: 100, y: 100), CGPoint(x: 100, y: 60),
                              CGPoint(x: 140, y: 60), CGPoint(x: 140, y: 20)], closed: false, rng: &rng))
recognizeCase("zigzag_7", hand((0...7).map { i in CGPoint(x: 20 + 25 * Double(i), y: i % 2 == 0 ? 110 : 30) }, closed: false, rng: &rng))
recognizeCase("narrow_v", hand([CGPoint(x: 72, y: 40), CGPoint(x: 80, y: 100), CGPoint(x: 88, y: 40)], closed: false, rng: &rng, sway: 0.4))
recognizeCase("axes_cross", hand([CGPoint(x: 40, y: 140), CGPoint(x: 40, y: 20), CGPoint(x: 40, y: 140), CGPoint(x: 170, y: 140)], closed: false, rng: &rng, sway: 0.5))

// Curves.
recognizeCase("bend_deep", bend(CGPoint(x: 30, y: 120), CGPoint(x: 100, y: -20), CGPoint(x: 180, y: 120), rng: &rng))
recognizeCase("bend_shallow", bend(CGPoint(x: 30, y: 100), CGPoint(x: 110, y: 60), CGPoint(x: 190, y: 100), rng: &rng))
recognizeCase("bend_tilted", bend(CGPoint(x: 40, y: 40), CGPoint(x: 160, y: 60), CGPoint(x: 120, y: 170), rng: &rng))
recognizeCase("arc_120", (0...60).map { i in
    let a = pi * (0.5 + 2.0 / 3 * Double(i) / 60)
    return r3(CGPoint(x: 100 + 70 * cos(a) + rng.between(-0.5, 0.5), y: 100 + 70 * sin(a) + rng.between(-0.5, 0.5)))
})
recognizeCase("hook", bend(CGPoint(x: 40, y: 150), CGPoint(x: 60, y: 10), CGPoint(x: 150, y: 60), rng: &rng))

// Triangles.
recognizeCase("tri_equilateral", hand(regular(3, center: CGPoint(x: 100, y: 100), r: 55, turn: -pi / 2), closed: true, rng: &rng, overshoot: 8))
recognizeCase("tri_equilateral_turned", hand(regular(3, center: CGPoint(x: 100, y: 100), r: 60, turn: 0.4), closed: true, rng: &rng, overshoot: 5))
recognizeCase("tri_right_345", hand([CGPoint(x: 40, y: 140), CGPoint(x: 120, y: 140), CGPoint(x: 40, y: 80)], closed: true, rng: &rng, overshoot: 10))
recognizeCase("tri_right_turned", hand([CGPoint(x: 50, y: 50), CGPoint(x: 150, y: 90), CGPoint(x: 120, y: 165)], closed: true, rng: &rng, overshoot: 6))
recognizeCase("tri_isosceles", hand([CGPoint(x: 100, y: 30), CGPoint(x: 128, y: 105), CGPoint(x: 72, y: 105)], closed: true, rng: &rng, overshoot: 6))
// A wide isosceles whose apex is within 10° of a right angle: the right angle wins (it is tested first).
recognizeCase("tri_isosceles_wide_is_right", hand([CGPoint(x: 40, y: 120), CGPoint(x: 160, y: 122), CGPoint(x: 101, y: 50)], closed: true, rng: &rng, overshoot: 8))
recognizeCase("tri_scalene", hand([CGPoint(x: 30, y: 130), CGPoint(x: 140, y: 118), CGPoint(x: 60, y: 60)], closed: true, rng: &rng, overshoot: 6))
// Sides 50, 75 and 110 (angles 23°, 35° and 122°), turned 20°: no special triangle at all.
recognizeCase("tri_scalene_obtuse", hand([CGPoint(x: 30, y: 130), CGPoint(x: 140, y: 130), CGPoint(x: 70.8, y: 101.1)].map { p in
    add(rot(p.x - 80, p.y - 120, 20 * pi / 180), 80, 120)
}, closed: true, rng: &rng, overshoot: 6))
// Two sides within 8 % of each other: isosceles, though it was not drawn as one.
recognizeCase("tri_near_isosceles", hand([CGPoint(x: 30, y: 100), CGPoint(x: 130, y: 150), CGPoint(x: 90, y: 40)], closed: true, rng: &rng, overshoot: 6))
// The base 5° off level is straightened.
recognizeCase("tri_isosceles_level_side_5deg", hand([CGPoint(x: 40, y: 140), CGPoint(x: 140, y: 131), CGPoint(x: 95, y: 60)], closed: true, rng: &rng, overshoot: 6))
recognizeCase("tri_tiny", hand(regular(3, center: CGPoint(x: 50, y: 50), r: 9, turn: 0), closed: true, rng: &rng, sway: 0.2, tremor: 0.15, spacing: 1, overshoot: 2))

// Rectangles and squares.
recognizeCase("rect_level", hand([CGPoint(x: 40, y: 40), CGPoint(x: 160, y: 42), CGPoint(x: 161, y: 110), CGPoint(x: 41, y: 109)], closed: true, rng: &rng, overshoot: 12))
recognizeCase("rect_tilted_25", hand((0..<4).map { i in
    let c = [CGPoint(x: -60, y: -35), CGPoint(x: 60, y: -35), CGPoint(x: 60, y: 35), CGPoint(x: -60, y: 35)][i]
    let p = rot(c.x, c.y, 25 * pi / 180)
    return add(p, 100, 100)
}, closed: true, rng: &rng, overshoot: 10))
recognizeCase("rect_tilted_5", hand((0..<4).map { i in
    let c = [CGPoint(x: -60, y: -35), CGPoint(x: 60, y: -35), CGPoint(x: 60, y: 35), CGPoint(x: -60, y: 35)][i]
    let p = rot(c.x, c.y, 5 * pi / 180)
    return add(p, 100, 100)
}, closed: true, rng: &rng, overshoot: 10))
recognizeCase("square_level", hand([CGPoint(x: 50, y: 50), CGPoint(x: 130, y: 52), CGPoint(x: 129, y: 131), CGPoint(x: 49, y: 130)], closed: true, rng: &rng, overshoot: 10))
recognizeCase("square_tilted_12", hand((0..<4).map { i in
    let c = [CGPoint(x: -45, y: -45), CGPoint(x: 45, y: -45), CGPoint(x: 45, y: 45), CGPoint(x: -45, y: 45)][i]
    let p = rot(c.x, c.y, 12 * pi / 180)
    return add(p, 100, 100)
}, closed: true, rng: &rng, overshoot: 8))
recognizeCase("rect_nearly_square", hand([CGPoint(x: 40, y: 40), CGPoint(x: 140, y: 40), CGPoint(x: 140, y: 132), CGPoint(x: 40, y: 132)], closed: true, rng: &rng, overshoot: 8))
recognizeCase("rect_tall", hand([CGPoint(x: 80, y: 20), CGPoint(x: 110, y: 20), CGPoint(x: 110, y: 160), CGPoint(x: 80, y: 160)], closed: true, rng: &rng, overshoot: 6))
recognizeCase("rect_rounded", roundedSquare(center: CGPoint(x: 100, y: 100), half: 50, power: 5, rng: &rng))
recognizeCase("rect_counterclockwise", hand([CGPoint(x: 40, y: 40), CGPoint(x: 40, y: 110), CGPoint(x: 160, y: 110), CGPoint(x: 160, y: 40)], closed: true, rng: &rng, overshoot: 10))
recognizeCase("square_crooked", hand([CGPoint(x: 50, y: 50), CGPoint(x: 135, y: 46), CGPoint(x: 140, y: 128), CGPoint(x: 48, y: 134)], closed: true, rng: &rng, sway: 2, overshoot: 12))

// Other polygons.
recognizeCase("quad_parallelogram", hand([CGPoint(x: 40, y: 130), CGPoint(x: 130, y: 130), CGPoint(x: 180, y: 50), CGPoint(x: 90, y: 50)], closed: true, rng: &rng, overshoot: 8))
recognizeCase("quad_kite", hand([CGPoint(x: 100, y: 20), CGPoint(x: 150, y: 70), CGPoint(x: 100, y: 180), CGPoint(x: 50, y: 70)], closed: true, rng: &rng, overshoot: 8))
recognizeCase("pentagon", hand(regular(5, center: CGPoint(x: 100, y: 100), r: 60, turn: -pi / 2), closed: true, rng: &rng, overshoot: 8))
recognizeCase("pentagon_turned", hand(regular(5, center: CGPoint(x: 110, y: 90), r: 55, turn: 0.3), closed: true, rng: &rng, overshoot: 6))
// A regular hexagon is nearly as round as a circle (the smoothing rounds its corners): on the iPad it
// is a toss-up between the two, and this steady one went to the circle.
recognizeCase("hexagon_regular_is_circle", hand(regular(6, center: CGPoint(x: 100, y: 100), r: 60, turn: 0), closed: true, rng: &rng, sway: 0.3, tremor: 0.15, overshoot: 8))
// An L: six corners no oval comes near.
recognizeCase("hexagon_l_shape", hand([CGPoint(x: 40, y: 40), CGPoint(x: 100, y: 40), CGPoint(x: 100, y: 100), CGPoint(x: 160, y: 100), CGPoint(x: 160, y: 160),
                                        CGPoint(x: 40, y: 160)], closed: true, rng: &rng, overshoot: 8))
// A box with two cut corners, drawn the other way round.
recognizeCase("hexagon_cut_corners_counterclockwise", hand([CGPoint(x: 40, y: 40), CGPoint(x: 40, y: 130), CGPoint(x: 160, y: 130), CGPoint(x: 190, y: 100),
                                                            CGPoint(x: 190, y: 70), CGPoint(x: 160, y: 40)], closed: true, rng: &rng, overshoot: 8))
// Seven and eight corners carry penalties of 1.15 and 1.3, and the smoothing rounds the corners of a
// regular heptagon or octagon enough for the circle to win: those stay circles (the two "regular"
// cases show it). Boxes with cut corners have flat sides no oval follows, and are seen.
recognizeCase("heptagon", hand([CGPoint(x: 70, y: 40), CGPoint(x: 160, y: 40), CGPoint(x: 190, y: 70), CGPoint(x: 190, y: 100), CGPoint(x: 160, y: 130),
                                CGPoint(x: 40, y: 130), CGPoint(x: 40, y: 70)], closed: true, rng: &rng, overshoot: 8))
recognizeCase("heptagon_turned", hand([CGPoint(x: 70, y: 40), CGPoint(x: 160, y: 40), CGPoint(x: 190, y: 70), CGPoint(x: 190, y: 100), CGPoint(x: 160, y: 130),
                                       CGPoint(x: 40, y: 130), CGPoint(x: 40, y: 70)].map { p in add(rot(p.x - 115, p.y - 85, 0.5), 115, 85) },
                                      closed: true, rng: &rng, overshoot: 8))
recognizeCase("heptagon_regular_is_circle", hand(regular(7, center: CGPoint(x: 100, y: 100), r: 65, turn: -pi / 2), closed: true, rng: &rng, sway: 0.5,
                                                 tremor: 0.25, overshoot: 8))
recognizeCase("octagon", hand([CGPoint(x: 70, y: 40), CGPoint(x: 170, y: 40), CGPoint(x: 200, y: 70), CGPoint(x: 200, y: 110), CGPoint(x: 170, y: 140),
                               CGPoint(x: 70, y: 140), CGPoint(x: 40, y: 110), CGPoint(x: 40, y: 70)], closed: true, rng: &rng, overshoot: 8))
recognizeCase("octagon_counterclockwise", hand([CGPoint(x: 70, y: 40), CGPoint(x: 40, y: 70), CGPoint(x: 40, y: 110), CGPoint(x: 70, y: 140), CGPoint(x: 170, y: 140),
                                                CGPoint(x: 200, y: 110), CGPoint(x: 200, y: 70), CGPoint(x: 170, y: 40)].map { p in add(rot(p.x - 120, p.y - 90, -0.3), 120, 90) },
                                               closed: true, rng: &rng, overshoot: 8))
recognizeCase("octagon_regular_is_circle", hand(regular(8, center: CGPoint(x: 100, y: 100), r: 70, turn: pi / 8), closed: true, rng: &rng, sway: 0.4,
                                                tremor: 0.2, overshoot: 8))

// Circles and ellipses.
recognizeCase("circle", oval(center: CGPoint(x: 100, y: 100), rx: 50, ry: 50, angle: 0, rng: &rng))
recognizeCase("circle_overshoot", oval(center: CGPoint(x: 100, y: 100), rx: 40, ry: 40, angle: 0, rng: &rng, overshoot: 40, hook: 0.12))
recognizeCase("circle_counterclockwise", oval(center: CGPoint(x: 100, y: 100), rx: 45, ry: 45, angle: 0, rng: &rng, clockwise: false))
recognizeCase("circle_small", oval(center: CGPoint(x: 60, y: 60), rx: 15, ry: 15, angle: 0, rng: &rng, tremor: 0.2))
recognizeCase("circle_from_fat_ellipse", oval(center: CGPoint(x: 100, y: 100), rx: 50, ry: 44, angle: 0.5, rng: &rng))
recognizeCase("ellipse_level", oval(center: CGPoint(x: 100, y: 100), rx: 80, ry: 45, angle: 0, rng: &rng))
recognizeCase("ellipse_upright", oval(center: CGPoint(x: 100, y: 100), rx: 40, ry: 75, angle: 0, rng: &rng))
recognizeCase("ellipse_tilted_30", oval(center: CGPoint(x: 100, y: 100), rx: 80, ry: 45, angle: 30 * pi / 180, rng: &rng))
recognizeCase("ellipse_tilted_5", oval(center: CGPoint(x: 100, y: 100), rx: 80, ry: 45, angle: 5 * pi / 180, rng: &rng))
recognizeCase("ellipse_thin", oval(center: CGPoint(x: 100, y: 100), rx: 90, ry: 25, angle: -0.6, rng: &rng))

// Near misses and scribbles: nothing.
recognizeCase("nil_tiny", [CGPoint(x: 50, y: 50), CGPoint(x: 52, y: 51), CGPoint(x: 53, y: 53), CGPoint(x: 51, y: 54)])
recognizeCase("nil_two_points", [CGPoint(x: 0, y: 0), CGPoint(x: 50, y: 30)])
recognizeCase("nil_scribble", walk(start: CGPoint(x: 100, y: 100), steps: 80, step: 3, rng: &rng))
recognizeCase("nil_spiral", (0...300).map { i in
    let a = 4.2 * pi * Double(i) / 300
    let r = 4 + 9 * a / (2 * pi)
    return r3(CGPoint(x: 100 + r * cos(a), y: 100 + r * sin(a)))
})
recognizeCase("nil_wave", (0...150).map { i in
    let x = Double(i)
    return r3(CGPoint(x: 20 + x, y: 100 + 20 * sin(2 * pi * 3 * x / 150) + rng.between(-0.3, 0.3)))
})
recognizeCase("nil_zigzag_9", hand((0...9).map { i in CGPoint(x: 20 + 18 * Double(i), y: i % 2 == 0 ? 110 : 30) }, closed: false, rng: &rng))
// An S is no parabola; its two bends read as a broken line.
recognizeCase("s_curve_polyline", (0...80).map { i in
    let t = Double(i) / 80
    return r3(CGPoint(x: 20 + 160 * t, y: 100 + 50 * sin(2 * pi * t) + rng.between(-0.3, 0.3)))
})
recognizeCase("nil_blob", (0...100).map { i in
    let a = 2.2 * pi * Double(i) / 100
    let r = 40 + 18 * sin(3 * a) + 10 * sin(5 * a + 1)
    return r3(CGPoint(x: 100 + r * cos(a), y: 100 + r * sin(a)))
})
recognizeCase("nil_dot_cluster", (0...30).map { _ in r3(CGPoint(x: 100 + rng.between(-6, 6), y: 100 + rng.between(-6, 6))) })

// MARK: - The shape tool

func toolCase(_ name: String, _ kind: ShapeKind, _ a: CGPoint, _ b: CGPoint, sides: Int = 6, dashes: Bool = false) {
    caseCount += 1
    emit("case tool \(name)")
    emit("kind \(kind.rawValue)")
    emit("from \(f(a.x)) \(f(a.y))")
    emit("to \(f(b.x)) \(f(b.y))")
    emit("sides \(sides)")
    emit("measurement \(ShapeBuilder.measurement(kind, from: a, to: b))")
    let e = snappedShapeEnd(kind, b, from: a)
    emit("snapped \(f(e.x)) \(f(e.y))")
    let paths = ShapeBuilder.paths(kind, from: a, to: b, sides: sides, labelHeight: 9)
    for path in paths { emitVec("path", path) }
    if dashes {
        for path in ShapeBuilder.dashed(paths) { emitVec("dash", path) }
    }
    emit("end")
}

toolCase("line_29deg", .line, CGPoint(x: 40, y: 100), CGPoint(x: 40 + 100 * cos(29 * pi / 180), y: 100 - 100 * sin(29 * pi / 180)))
toolCase("line_26deg", .line, CGPoint(x: 40, y: 100), CGPoint(x: 40 + 100 * cos(26 * pi / 180), y: 100 - 100 * sin(26 * pi / 180)))
toolCase("line_level", .line, CGPoint(x: 10.5, y: 20.25), CGPoint(x: 210.5, y: 20.25), dashes: true)
toolCase("line_long", .line, CGPoint(x: 0, y: 0), CGPoint(x: 400, y: 300))
toolCase("line_back", .line, CGPoint(x: 200, y: 50), CGPoint(x: 50, y: 160))
toolCase("arrow", .arrow, CGPoint(x: 30, y: 30), CGPoint(x: 150, y: 90), dashes: true)
toolCase("arrow_short", .arrow, CGPoint(x: 30, y: 30), CGPoint(x: 45, y: 35))
toolCase("arrow_tiny", .arrow, CGPoint(x: 30, y: 30), CGPoint(x: 30.2, y: 30.3))
toolCase("arrow_near_15", .arrow, CGPoint(x: 100, y: 100), CGPoint(x: 100 + 80 * cos(-44 * pi / 180), y: 100 + 80 * sin(-44 * pi / 180)))
toolCase("double_arrow", .doubleArrow, CGPoint(x: 20, y: 120), CGPoint(x: 200, y: 40), dashes: true)
toolCase("double_arrow_tiny", .doubleArrow, CGPoint(x: 20, y: 120), CGPoint(x: 20.1, y: 120.2))
toolCase("rectangle", .rectangle, CGPoint(x: 40, y: 40), CGPoint(x: 180, y: 110), dashes: true)
toolCase("rectangle_nearly_square", .rectangle, CGPoint(x: 40, y: 40), CGPoint(x: 140, y: 144))
toolCase("rectangle_square_up_left", .rectangle, CGPoint(x: 140, y: 150), CGPoint(x: 38, y: 50))
toolCase("ellipse", .ellipse, CGPoint(x: 40, y: 40), CGPoint(x: 180, y: 110), dashes: true)
toolCase("ellipse_nearly_square", .ellipse, CGPoint(x: 100, y: 100), CGPoint(x: 10, y: 190))
toolCase("ellipse_big", .ellipse, CGPoint(x: 0, y: 0), CGPoint(x: 500, y: 200))
toolCase("circle", .circle, CGPoint(x: 100, y: 100), CGPoint(x: 160, y: 130), dashes: true)
toolCase("circle_small", .circle, CGPoint(x: 100, y: 100), CGPoint(x: 108, y: 94))
toolCase("triangle", .triangle, CGPoint(x: 40, y: 40), CGPoint(x: 180, y: 150))
toolCase("triangle_up", .triangle, CGPoint(x: 180, y: 150), CGPoint(x: 40, y: 40))
toolCase("right_triangle", .rightTriangle, CGPoint(x: 40, y: 40), CGPoint(x: 180, y: 150), dashes: true)
toolCase("polygon_6", .polygon, CGPoint(x: 100, y: 100), CGPoint(x: 160, y: 100), sides: 6, dashes: true)
toolCase("polygon_3", .polygon, CGPoint(x: 100, y: 100), CGPoint(x: 140, y: 150), sides: 3)
toolCase("polygon_5", .polygon, CGPoint(x: 100, y: 100), CGPoint(x: 60, y: 60), sides: 5)
toolCase("polygon_8", .polygon, CGPoint(x: 100, y: 100), CGPoint(x: 100, y: 30), sides: 8)
toolCase("polygon_24", .polygon, CGPoint(x: 100, y: 100), CGPoint(x: 150, y: 100), sides: 24)
toolCase("polygon_30_clamped", .polygon, CGPoint(x: 100, y: 100), CGPoint(x: 150, y: 100), sides: 30)
toolCase("polygon_2_clamped", .polygon, CGPoint(x: 100, y: 100), CGPoint(x: 150, y: 100), sides: 2)
toolCase("measure_cm", .line, CGPoint(x: 0, y: 0), CGPoint(x: 400, y: 0))
toolCase("measure_box_cm", .rectangle, CGPoint(x: 0, y: 0), CGPoint(x: 350, y: 299.9))

// MARK: - The stroke builder

func samples(_ pts: [CGPoint], startTime: Double = 0, dt: Double = 1.0 / 240, forces: [CGFloat] = [1],
             altitude: CGFloat = .pi / 2, pencil: Bool = true, roll: CGFloat = 0) -> [InputSample] {
    pts.enumerated().map { i, p in
        // Whole Float values, so the sample reads back exactly on the Float side.
        let x = CGFloat(Float(p.x))
        let y = CGFloat(Float(p.y))
        return InputSample(location: CGPoint(x: x, y: y), force: forces[i % forces.count], timestamp: startTime + Double(i) * dt,
                           altitude: altitude, azimuth: 0, roll: roll, isPencil: pencil, estimationIndex: nil)
    }
}

func feed(_ b: inout StrokeBuilder, _ s: [InputSample]) {
    for sample in s {
        b.add(sample)
        // The Float values the builder reads; the timestamp in its exact Double form.
        emit("sample \(f(Float(sample.location.x))) \(f(Float(sample.location.y))) \(f(Float(sample.force))) \(sample.timestamp) "
             + "\(f(Float(sample.altitude))) \(sample.isPencil ? 1 : 0) \(f(Float(sample.roll)))")
    }
}

func emitBuilder(_ b: StrokeBuilder) {
    emitInk("points", b.points)
    emit("straight \(b.isStraight ? 1 : 0)")
    if let a = b.shapeAdjustment { emit("adjust \(f(a.scale)) \(a.degrees)") } else { emit("adjust -") }
    if let e = b.editable { emitShape(e) } else { emit("editable -") }
    emitPoints("drawn", b.drawnPath)
    if let t = b.tip { emit("tip \(f(t.x)) \(f(t.y))") } else { emit("tip -") }
    emitInk("preview", b.preview(predicted: []))
}

func builderCase(_ name: String, brush: Brush, nib: Float = 0.66, useRoll: Bool = true, _ run: (inout StrokeBuilder) -> Void) {
    caseCount += 1
    emit("case builder \(name)")
    var b = StrokeBuilder(brush: brush, color: InkColor(hex: 0), width: brush.defaultWidth, seed: 0.5)
    b.nibAngle = nib
    b.useRoll = useRoll
    emit("brush \(brush.rawValue) \(f(b.width)) \(f(nib)) \(useRoll ? 1 : 0)")
    run(&b)
    emit("finish")
    emitInk("points", b.finish())
    emit("end")
}

func snapLine(_ b: inout StrokeBuilder) {
    let ok = b.snapToLine()
    emit("snapline")
    emit("result \(ok ? 1 : 0)")
    emitBuilder(b)
}

@discardableResult
func snapShape(_ b: inout StrokeBuilder) -> String? {
    let title = b.snapToShape()
    emit("snapshape")
    emit("result \(title ?? "-")")
    emitBuilder(b)
    print("  builder: \(title ?? "-")")
    return title
}

/// Points of the pen moving from `a` to `b` in `n` steps (the tip only; no tremor).
func glide(_ a: CGPoint, _ b: CGPoint, _ n: Int) -> [CGPoint] {
    (1...n).map { i in
        let t = Double(i) / Double(n)
        return r3(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
    }
}

let presses: [CGFloat] = [1, 1.25, 1.5, 1.25, 1, 0.75, 0.5, 0.75]

builderCase("line_snap", brush: .pen) { b in
    let stroke = hand([CGPoint(x: 10, y: 10), CGPoint(x: 90, y: 60)], closed: false, rng: &rng, spacing: 1.5)
    feed(&b, samples(stroke, forces: presses))
    snapLine(&b)
    // The end keeps following the pen.
    feed(&b, samples(glide(CGPoint(x: 90, y: 60), CGPoint(x: 120, y: 40), 8), startTime: 1, forces: presses))
    emitBuilder(b)
}

builderCase("line_by_shape", brush: .pen) { b in
    let stroke = hand([CGPoint(x: 20, y: 120), CGPoint(x: 150, y: 30)], closed: false, rng: &rng, sway: 1.5, spacing: 1.5)
    feed(&b, samples(stroke, forces: presses))
    snapShape(&b)
    feed(&b, samples(glide(CGPoint(x: 150, y: 30), CGPoint(x: 160, y: 20), 4), startTime: 1))
    emitBuilder(b)
}

builderCase("line_too_short", brush: .pen) { b in
    feed(&b, samples([CGPoint(x: 10, y: 10), CGPoint(x: 11, y: 11), CGPoint(x: 13, y: 12), CGPoint(x: 14, y: 13)]))
    snapLine(&b)
    emitBuilder(b)
}

builderCase("square_wet", brush: .wet) { b in
    let stroke = hand([CGPoint(x: 50, y: 50), CGPoint(x: 130, y: 52), CGPoint(x: 129, y: 131), CGPoint(x: 49, y: 130)], closed: true, rng: &rng,
                      spacing: 1.5, overshoot: 10)
    feed(&b, samples(stroke, forces: presses))
    snapShape(&b)
    let grab = stroke[stroke.count - 1]
    let anchor = CGPoint(x: 90, y: 90)
    // Away from the middle: bigger.
    let far = CGPoint(x: anchor.x + (grab.x - anchor.x) * 1.4, y: anchor.y + (grab.y - anchor.y) * 1.4)
    feed(&b, samples(glide(grab, far, 6), startTime: 1))
    emitBuilder(b)
    // Round the middle by 14°: the turn clicks to 15°.
    let turned = add(rot(far.x - anchor.x, far.y - anchor.y, 14 * pi / 180), anchor.x, anchor.y)
    feed(&b, samples(glide(far, turned, 6), startTime: 2))
    emitBuilder(b)
    // By 7° only: no click.
    let seven = add(rot(far.x - anchor.x, far.y - anchor.y, 7 * pi / 180), anchor.x, anchor.y)
    feed(&b, samples(glide(turned, seven, 4), startTime: 3))
    emitBuilder(b)
    // Back near the middle: as small as it gets.
    feed(&b, samples(glide(seven, add(anchor, 2, 1), 5), startTime: 4))
    emitBuilder(b)
}

builderCase("square_wobble", brush: .pen) { b in
    // A wobble under 6 points while lifting the pen changes nothing.
    let stroke = hand([CGPoint(x: 50, y: 50), CGPoint(x: 130, y: 50), CGPoint(x: 130, y: 130), CGPoint(x: 50, y: 130)], closed: true, rng: &rng,
                      spacing: 1.5, overshoot: 10)
    feed(&b, samples(stroke))
    snapShape(&b)
    let grab = stroke[stroke.count - 1]
    feed(&b, samples(glide(grab, add(grab, 3, -2), 3), startTime: 1))
    emitBuilder(b)
}

builderCase("circle_turn", brush: .pen) { b in
    let stroke = oval(center: CGPoint(x: 100, y: 100), rx: 50, ry: 50, angle: 0, rng: &rng, start: 0.2)
    feed(&b, samples(stroke, forces: presses))
    snapShape(&b)
    let grab = stroke[stroke.count - 1]
    if let e = b.editable, case let .oval(center, _, _, _) = e.kind {
        // Round the middle by 44°, half as far out: the turn clicks to 45°.
        let v = rot((grab.x - center.x) * 0.5, (grab.y - center.y) * 0.5, 44 * pi / 180)
        feed(&b, samples(glide(grab, add(center, v.x, v.y), 10), startTime: 1))
        emitBuilder(b)
        // Across to the other side: a half turn.
        let w = rot((grab.x - center.x), (grab.y - center.y), 181 * pi / 180)
        feed(&b, samples(glide(add(center, v.x, v.y), add(center, w.x, w.y), 10), startTime: 2))
        emitBuilder(b)
    }
}

builderCase("triangle_pencil", brush: .pencil) { b in
    let stroke = hand([CGPoint(x: 40, y: 140), CGPoint(x: 120, y: 140), CGPoint(x: 40, y: 80)], closed: true, rng: &rng, spacing: 1.5, overshoot: 10)
    feed(&b, samples(stroke, forces: presses, altitude: 1))
    snapShape(&b)
    let grab = stroke[stroke.count - 1]
    feed(&b, samples(glide(grab, add(grab, 20, 15), 5), startTime: 1, altitude: 1))
    emitBuilder(b)
}

builderCase("curve_open_anchor", brush: .pen) { b in
    let stroke = bend(CGPoint(x: 30, y: 120), CGPoint(x: 100, y: -20), CGPoint(x: 180, y: 120), rng: &rng)
    feed(&b, samples(stroke, forces: presses))
    snapShape(&b)
    // An open shape turns and grows around its start.
    let grab = stroke[stroke.count - 1]
    let start = stroke[0]
    let v = rot((grab.x - start.x) * 1.2, (grab.y - start.y) * 1.2, -16 * pi / 180)
    feed(&b, samples(glide(grab, add(start, v.x, v.y), 8), startTime: 1))
    emitBuilder(b)
}

builderCase("scribble_stays", brush: .pen) { b in
    let stroke = walk(start: CGPoint(x: 100, y: 100), steps: 60, step: 3, rng: &rng)
    feed(&b, samples(stroke, forces: presses))
    snapShape(&b)
    feed(&b, samples(glide(stroke[stroke.count - 1], add(stroke[stroke.count - 1], 5, 5), 3), startTime: 1))
    emitBuilder(b)
}

builderCase("calligraphy_line", brush: .calligraphy, nib: 0.66, useRoll: true) { b in
    let stroke = hand([CGPoint(x: 20, y: 100), CGPoint(x: 120, y: 100)], closed: false, rng: &rng, spacing: 1.5)
    feed(&b, samples(stroke, roll: 0.25))
    snapLine(&b)
    // Upright now: the nib crosses the line, the width grows.
    feed(&b, samples(glide(CGPoint(x: 120, y: 100), CGPoint(x: 70, y: 20), 6), startTime: 1, roll: 0.25))
    emitBuilder(b)
}

builderCase("calligraphy_square", brush: .calligraphy, nib: 0.5, useRoll: false) { b in
    let stroke = hand([CGPoint(x: 50, y: 50), CGPoint(x: 130, y: 50), CGPoint(x: 130, y: 130), CGPoint(x: 50, y: 130)], closed: true, rng: &rng,
                      spacing: 1.5, overshoot: 10)
    feed(&b, samples(stroke))
    snapShape(&b)
}

builderCase("fountain_rectangle", brush: .fountain) { b in
    let stroke = hand([CGPoint(x: 40, y: 40), CGPoint(x: 160, y: 42), CGPoint(x: 161, y: 110), CGPoint(x: 41, y: 109)], closed: true, rng: &rng,
                      spacing: 1.5, overshoot: 12)
    feed(&b, samples(stroke, forces: presses))
    snapShape(&b)
    let grab = stroke[stroke.count - 1]
    feed(&b, samples(glide(grab, add(grab, -30, 10), 6), startTime: 1, forces: presses))
    emitBuilder(b)
}

// MARK: - Coverage and the file

print("\(caseCount) cases; recognized \(titles.values.reduce(0, +)), nothing \(nilCount)")
print("kinds: \(kinds.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", "))")
print("titles: \(titles.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", "))")
for title in ["Doğru", "Kırık çizgi", "Eğri", "Daire", "Elips", "Kare", "Dikdörtgen", "Üçgen", "Dik üçgen", "Eşkenar üçgen", "İkizkenar üçgen",
              "Dörtgen", "Beşgen", "Altıgen", "Yedigen", "Sekizgen"] {
    check((titles[title] ?? 0) > 0, "a \(title) in the fixture")
}
for kind in ["line", "polyline", "curve", "polygon", "rectangle", "circle", "ellipse"] {
    check((kinds[kind] ?? 0) > 0, "a \(kind) in the fixture")
}
check(nilCount >= 6, "at least six strokes that are nothing (\(nilCount))")
check(caseCount >= 60, "at least sixty cases (\(caseCount))")

let path = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "shapes.txt"
let url = URL(fileURLWithPath: path)
try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
let header = "# Written by tools/shapecheck from the iPad's Swift shape code; do not edit. \(caseCount) cases.\n"
// Bytes, not text: Foundation's text writing on Windows turns the newlines into CRLF, and the repo is LF.
try! Data((header + out.joined(separator: "\n") + "\n").utf8).write(to: url)
print("wrote \(path): \(out.count) lines")
exit(failures == 0 ? 0 : 1)
