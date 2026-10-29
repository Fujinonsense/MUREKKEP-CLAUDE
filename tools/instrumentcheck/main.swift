import Foundation

// Runs the iPad's real drafting instruments (Instruments.swift: Instrument, EdgeSnap) on Windows and
// writes what they answer into a plain-text fixture that the Android edition's InstrumentsTest holds
// ink/Instruments.kt to: each instrument's outline and edges, its angle in degrees, and for points
// round it whether it covers them, where they lie in its own frame, how far they are from each edge,
// which edge (or protractor ray) a pen coming down there follows, and where the pen's later points
// land on it. The points come from a seeded generator, so the fixture is the same on every run.
// usage: instrumentcheck.exe <path of instruments.txt>   (tools/instrumentcheck/run.ps1 builds and runs it)
//
// The fixture is lines of "key value…" grouped in "case <type> <name>" … "end", as shapes.txt.
// Inputs are rounded to thousandths first, so their decimal form reads back exactly; the iPad's
// answers get ten significant digits, plenty for the tests' tolerance of 1e-6.

// MARK: - Writing

var out: [String] = []
var failures = 0

func emit(_ line: String) { out.append(line) }
func f(_ v: CGFloat) -> String { String(format: "%.10g", Double(v)) }
func join(_ p: [CGPoint]) -> String { p.map { "\(f($0.x)) \(f($0.y))" }.joined(separator: " ") }
func emitPoints(_ key: String, _ p: [CGPoint]) { emit(p.isEmpty ? key : "\(key) \(join(p))") }

/// Inputs are rounded to thousandths so they read back exactly from their decimal form.
func r3(_ v: CGFloat) -> CGFloat { (v * 1000).rounded() / 1000 }
func r3(_ p: CGPoint) -> CGPoint { CGPoint(x: r3(p.x), y: r3(p.y)) }

func check(_ ok: Bool, _ what: String) {
    print(ok ? "ok   \(what)" : "FAIL \(what)")
    if !ok { failures += 1 }
}

/// A 64-bit linear congruential generator (tools/shapecheck's): the same points on every machine.
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

var rng = Rand(20261030)

// MARK: - Points round an instrument

/// Points round the instrument: some anywhere near it, some just inside and just outside the snap's
/// reach of every edge (and past the edges' ends), and for the protractor some round its center.
func probes(_ ins: Instrument, tolerance: CGFloat) -> [CGPoint] {
    var points: [CGPoint] = []
    let reach: CGFloat
    switch ins.kind {
    case .ruler: reach = Instrument.rulerLength / 2 + 30
    case .setSquare45, .setSquare3060: reach = Instrument.squareLeg + 20
    case .protractor: reach = Instrument.protractorRadius + 30
    }
    for _ in 0..<10 {
        points.append(r3(CGPoint(x: ins.center.x + rng.between(-reach, reach), y: ins.center.y + rng.between(-reach, reach))))
    }
    for (a, b) in ins.edges {
        let length = hypot(b.x - a.x, b.y - a.y)
        let ux = (b.x - a.x) / length
        let uy = (b.y - a.y) / length
        for t in [-0.06, 0.3, 0.75, 1.04] {
            for k in [-1.3, -0.5, 0.4, 1.2] {
                let side = k * tolerance
                points.append(r3(CGPoint(x: a.x + (b.x - a.x) * t - uy * side, y: a.y + (b.y - a.y) * t + ux * side)))
            }
        }
    }
    if ins.kind == .protractor {
        for k in [0.2, 0.7, 1.2, 1.35, 1.5, 2.2] {
            let angle = rng.between(0, 2 * .pi)
            let d = k * tolerance
            points.append(r3(CGPoint(x: ins.center.x + cos(angle) * d, y: ins.center.y + sin(angle) * d)))
        }
    }
    return points
}

/// Where the pen goes after coming down at `p` on `snap`: along an edge both ways (past its ends
/// too) with a wobble across it; out along a protractor's ray at any angle and length.
func follow(_ snap: EdgeSnap, from p: CGPoint) -> [CGPoint] {
    var points: [CGPoint] = []
    if snap.isRay {
        for _ in 0..<4 {
            let angle = rng.between(-.pi, .pi)
            let d = rng.between(5, 220)
            points.append(r3(CGPoint(x: snap.a.x + cos(angle) * d, y: snap.a.y + sin(angle) * d)))
        }
        // Right on the center: the ray's start.
        points.append(r3(CGPoint(x: snap.a.x + 0.004, y: snap.a.y - 0.003)))
        return points
    }
    let length = hypot(snap.b.x - snap.a.x, snap.b.y - snap.a.y)
    let ux = (snap.b.x - snap.a.x) / length
    let uy = (snap.b.y - snap.a.y) / length
    for along in [-0.4 * length, -25, 60, 1.3 * length] {
        let side = rng.between(-4, 4)
        points.append(r3(CGPoint(x: p.x + ux * along - uy * side, y: p.y + uy * along + ux * side)))
    }
    return points
}

// MARK: - Cases

var instrumentCount = 0
var snaps = [String: Int]()

func instrumentCase(_ name: String, _ ins: Instrument, tolerance: CGFloat) {
    instrumentCount += 1
    emit("case instrument \(name)")
    emit("in \(ins.kind.rawValue) \(f(ins.center.x)) \(f(ins.center.y)) \(f(ins.angle))")
    emit("tolerance \(f(tolerance))")
    emitPoints("local", ins.localOutline)
    emitPoints("outline", ins.outline)
    emit("edges " + ins.edges.map { "\(f($0.0.x)) \(f($0.0.y)) \(f($0.1.x)) \(f($0.1.y))" }.joined(separator: " "))
    emit("degrees \(ins.degrees)")
    for p in probes(ins, tolerance: tolerance) {
        emit("probe \(f(p.x)) \(f(p.y))")
        emit("contains \(ins.contains(p) ? 1 : 0)")
        emitPoints("tolocal", [ins.toLocal(p)])
        // The probe read as a point of the instrument's own frame.
        emitPoints("todoc", [ins.toDocument(p)])
        emit("dist " + ins.edges.map { f(EdgeSnap.distance(p, $0.0, $0.1)) }.joined(separator: " "))
        guard let snap = EdgeSnap.find(for: ins, at: p, tolerance: tolerance) else {
            emit("snap")
            snaps["none", default: 0] += 1
            continue
        }
        snaps[snap.isRay ? "ray" : "edge", default: 0] += 1
        emit("snap \(f(snap.a.x)) \(f(snap.a.y)) \(f(snap.b.x)) \(f(snap.b.y)) \(snap.isRay ? 1 : 0)")
        emitPoints("start", [snap.project(p)])
        for q in follow(snap, from: p) {
            emitPoints("follow", [q, snap.project(q)])
        }
    }
    emit("end")
}

let instruments: [(String, Instrument, CGFloat)] = [
    ("ruler_level", Instrument(kind: .ruler, center: CGPoint(x: 300, y: 400), angle: 0), 18),
    ("ruler_turned_zoomed", Instrument(kind: .ruler, center: CGPoint(x: 250.5, y: 610.25), angle: -0.523), 18 / 1.7),
    ("ruler_upside_down", Instrument(kind: .ruler, center: CGPoint(x: 297.125, y: 120.5), angle: 3.0), 18 / 0.8),
    ("square45_level", Instrument(kind: .setSquare45, center: CGPoint(x: 320, y: 300), angle: 0), 18),
    ("square45_turned", Instrument(kind: .setSquare45, center: CGPoint(x: 280.25, y: 500.75), angle: -2.1), 18 / 0.8),
    ("square3060_level", Instrument(kind: .setSquare3060, center: CGPoint(x: 300, y: 420), angle: 0), 18),
    ("square3060_turned", Instrument(kind: .setSquare3060, center: CGPoint(x: 310.5, y: 380.25), angle: 1.2), 18 / 2.3),
    ("protractor_level", Instrument(kind: .protractor, center: CGPoint(x: 297, y: 420), angle: 0), 18),
    ("protractor_turned", Instrument(kind: .protractor, center: CGPoint(x: 200.75, y: 300.5), angle: -0.785), 18 / 1.3),
    ("protractor_over", Instrument(kind: .protractor, center: CGPoint(x: 150, y: 700), angle: 2.6), 18 / 0.6),
]

for (name, ins, tolerance) in instruments {
    instrumentCase(name, ins, tolerance: tolerance)
}

// The angle shown while an instrument turns, for turns all the way round and past it.
emit("case degrees turns")
var angles: [CGFloat] = [0, -0.0001, 0.0001, .pi, -.pi, .pi / 2, -.pi / 2, 2 * .pi]
for _ in 0..<40 { angles.append(r3(rng.between(-12, 12))) }
emit("angles " + angles.map { f($0) }.joined(separator: " "))
emit("values " + angles.map { "\(Instrument(kind: .ruler, center: .zero, angle: $0).degrees)" }.joined(separator: " "))
emit("end")

// MARK: - Coverage and the file

print("\(instrumentCount) instruments; snaps: \(snaps.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", "))")
check(instrumentCount == instruments.count, "every instrument written")
check((snaps["edge"] ?? 0) >= 100, "at least a hundred pens along an edge (\(snaps["edge"] ?? 0))")
check((snaps["ray"] ?? 0) >= 6, "at least six pens on a protractor's ray (\(snaps["ray"] ?? 0))")
check((snaps["none"] ?? 0) >= 100, "at least a hundred pens that follow nothing (\(snaps["none"] ?? 0))")

let path = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "instruments.txt"
let url = URL(fileURLWithPath: path)
try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
let header = "# Written by tools/instrumentcheck from the iPad's Swift instrument code; do not edit. \(instrumentCount) instruments.\n"
// Bytes, not text: Foundation's text writing on Windows turns the newlines into CRLF, and the repo is LF.
try! Data((header + out.joined(separator: "\n") + "\n").utf8).write(to: url)
print("wrote \(path): \(out.count) lines")
exit(failures == 0 ? 0 : 1)
