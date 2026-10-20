import Foundation

/// The angle of the writing on the page (twin of tests/ports/deskew.py), so the text pen can level it
/// before reading: on a page turned by -19° with the writing level on the screen, the ink lies 19° off
/// the page's lines, and both the line splitter and the handwriting model read it badly.
///
/// The ink's points are turned through every angle from -35° to 35° (1° steps, then ±1° in 0.25°
/// steps around the best); the angle at which the points pile up in the fewest, fullest horizontal
/// bands (bins a quarter of a letter high; score = sum of squared bin counts) is the writing's
/// direction. An angle that scores less than 3 % better than level counts as level. Degrees, y down:
/// a positive angle is writing that goes down to the right.
enum InkDeskew {
    static let maxDegrees = 35.0
    static let minGain = 1.03
    static let maxPoints = 3000

    private static func sample(_ strokes: [[CGPoint]]) -> [CGPoint] {
        let all = strokes.flatMap { $0 }
        guard all.count > maxPoints else { return all }
        let step = Double(all.count) / Double(maxPoints)
        return (0..<maxPoints).map { all[Int(Double($0) * step)] }
    }

    private static func letterHeight(_ strokes: [[CGPoint]]) -> Double {
        let heights = strokes.filter { !$0.isEmpty }.map { s -> Double in
            let ys = s.map { Double($0.y) }
            return ys.max()! - ys.min()!
        }
        let big = heights.filter { $0 >= 3 }.sorted()
        guard !big.isEmpty else { return max(heights.max() ?? 1, 1) }
        let m = big.count / 2
        return big.count % 2 == 1 ? big[m] : (big[m - 1] + big[m]) / 2
    }

    private static func score(_ points: [CGPoint], degrees: Double, bin: Double) -> Double {
        let a = degrees * .pi / 180
        let s = sin(a)
        let c = cos(a)
        let ys = points.map { -Double($0.x) * s + Double($0.y) * c }
        let lo = ys.min() ?? 0
        var counts: [Int: Double] = [:]
        for y in ys {
            counts[Int((y - lo) / bin), default: 0] += 1
        }
        return counts.values.reduce(0) { $0 + $1 * $1 }
    }

    /// Degrees the writing is turned (0 when level, or too little ink to tell).
    static func angle(_ strokes: [[CGPoint]]) -> Double {
        let points = sample(strokes)
        guard points.count >= 8 else { return 0 }
        let xs = points.map { Double($0.x) }
        guard (xs.max() ?? 0) - (xs.min() ?? 0) > 1e-6 else { return 0 }
        let bin = max(letterHeight(strokes) / 4, 0.5)
        let levelScore = score(points, degrees: 0, bin: bin)
        var bestDegrees = 0.0
        var best = levelScore
        var d = -maxDegrees
        while d <= maxDegrees + 1e-9 {
            let s = score(points, degrees: d, bin: bin)
            if s > best {
                bestDegrees = d
                best = s
            }
            d += 1
        }
        let centre = bestDegrees
        for k in -4...4 {
            let candidate = centre + Double(k) * 0.25
            let s = score(points, degrees: candidate, bin: bin)
            if s > best {
                bestDegrees = candidate
                best = s
            }
        }
        return best < levelScore * minGain ? 0 : bestDegrees
    }

    /// The centre the strokes are turned around.
    static func centre(_ strokes: [[CGPoint]]) -> CGPoint {
        let all = strokes.flatMap { $0 }
        guard !all.isEmpty else { return .zero }
        let x = all.reduce(0.0) { $0 + Double($1.x) } / Double(all.count)
        let y = all.reduce(0.0) { $0 + Double($1.y) } / Double(all.count)
        return CGPoint(x: x, y: y)
    }

    /// `p` turned by -degrees around `centre` (the writing made level).
    static func level(_ p: CGPoint, degrees: Double, centre: CGPoint) -> CGPoint {
        let a = degrees * .pi / 180
        let c = cos(a)
        let s = sin(a)
        let dx = Double(p.x - centre.x)
        let dy = Double(p.y - centre.y)
        return CGPoint(x: Double(centre.x) + dx * c + dy * s, y: Double(centre.y) - dx * s + dy * c)
    }

    /// `p` from levelled coordinates back to the page (turned by +degrees around `centre`).
    static func unlevel(_ p: CGPoint, degrees: Double, centre: CGPoint) -> CGPoint {
        level(p, degrees: -degrees, centre: centre)
    }
}
