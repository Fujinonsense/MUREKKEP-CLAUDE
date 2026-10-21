import Foundation
import UIKit

/// The text pen's second reader: it reads how the pen moved, not a picture of the ink, so a
/// hurried 'e' that looks like an 'a' is still an 'e' by where the pen started and which way it
/// went. Step-by-step transcription of ml/handwriting/online.py (features, three 1-D convolutions,
/// two bidirectional LSTM layers, CTC), trained on the Kinematic Stroke Generator (kinematic.py).
final class OnlineReader {
    /// nil when hwonline is missing or unreadable; the text pen then reads with the picture alone.
    static let shared: OnlineReader? = {
        guard let asset = NSDataAsset(name: "hwonline"), let reader = OnlineReader(data: asset.data) else {
            print("Mürekkep: pen-motion reader not available")
            return nil
        }
        return reader
    }()

    /// Points along each stroke, every `step` line heights.
    static let step = 0.1
    static let maxPoints = 2400
    static let features = 5

    let charset: [Character]
    var classes: Int { charset.count + 1 }

    private struct Conv {
        let w: [Float]  // [out, in × 5]
        let b: [Float]
        let cin: Int
        let cout: Int
        let stride: Int
    }

    private let convs: [Conv]
    private let lstms: [HandwritingModel.LSTM]  // layer 1 forward, backward, layer 2 forward, backward
    private let fcT: [Float]
    private let fcB: [Float]

    // MARK: Loading hwonline.bin

    init?(data: Data) {
        var r = HandwritingModel.Reader(bytes: [UInt8](data))
        guard r.bytes.count > 16, Array(r.bytes[0..<8]) == Array("MRKON1".utf8) + [0, 0] else { return nil }
        r.pos = 8
        guard r.u32() == 1, let nChars = r.u32(), r.pos + nChars <= r.bytes.count,
              let text = String(bytes: r.bytes[r.pos..<(r.pos + nChars)], encoding: .utf8) else { return nil }
        r.pos += nChars
        let chars = Array(text)
        guard let count = r.u32(), count == 20 else { return nil }
        var tensors: [(dims: [Int], values: [Float])] = []
        for _ in 0..<count {
            guard let rank = r.u32(), rank >= 1, rank <= 3 else { return nil }
            var dims: [Int] = []
            for _ in 0..<rank {
                guard let d = r.u32() else { return nil }
                dims.append(d)
            }
            guard let values = r.halves(dims.reduce(1, *)) else { return nil }
            tensors.append((dims, values))
        }
        var convs: [Conv] = []
        var cin = Self.features
        for (i, stride) in [1, 2, 2].enumerated() {
            let w = tensors[2 * i]
            guard w.dims.count == 3, w.dims[1] == cin, w.dims[2] == 5 else { return nil }
            convs.append(Conv(w: w.values, b: tensors[2 * i + 1].values, cin: cin, cout: w.dims[0], stride: stride))
            cin = w.dims[0]
        }
        let hidden = HandwritingModel.hidden
        var lstms: [HandwritingModel.LSTM] = []
        var inputs = cin
        for k in 0..<4 {
            let wih = tensors[6 + 3 * k]
            guard wih.dims == [4 * hidden, inputs] else { return nil }
            lstms.append(HandwritingModel.LSTM(wihT: HandwritingModel.transpose(wih.values, rows: 4 * hidden, cols: inputs),
                                               whh: tensors[7 + 3 * k].values, b: tensors[8 + 3 * k].values, inputs: inputs))
            if k == 1 { inputs = 2 * hidden }
        }
        let fc = tensors[18]
        guard fc.dims == [chars.count + 1, 2 * hidden] else { return nil }
        charset = chars
        self.convs = convs
        self.lstms = lstms
        fcT = HandwritingModel.transpose(fc.values, rows: fc.dims[0], cols: fc.dims[1])
        fcB = tensors[19].values
    }

    // MARK: Pen-motion features

    /// Points every `step` along the stroke (repeated points dropped first), ends included.
    static func resample(_ stroke: [CGPoint], step: Double) -> [(x: Double, y: Double)] {
        var p: [(x: Double, y: Double)] = []
        for q in stroke {
            let x = Double(q.x), y = Double(q.y)
            if let last = p.last, hypot(x - last.x, y - last.y) <= 1e-9 { continue }
            p.append((x, y))
        }
        guard p.count >= 2 else { return p }
        var cum = [0.0]
        for i in 1..<p.count {
            cum.append(cum[i - 1] + hypot(p[i].x - p[i - 1].x, p[i].y - p[i - 1].y))
        }
        let total = cum[cum.count - 1]
        let n = max(2, Int((total / step).rounded(.up)) + 1)
        let delta = total / Double(n - 1)
        var out: [(x: Double, y: Double)] = []
        out.reserveCapacity(n)
        var j = 0
        for i in 0..<n {
            let at = i == n - 1 ? total : Double(i) * delta
            while j < cum.count - 2, cum[j + 1] <= at { j += 1 }
            if at >= total {
                out.append(p[p.count - 1])
                continue
            }
            let t = (at - cum[j]) / (cum[j + 1] - cum[j])
            out.append((p[j].x + (p[j + 1].x - p[j].x) * t, p[j].y + (p[j + 1].y - p[j].y) * t))
        }
        return out
    }

    /// numpy's default (linear) percentile of sorted values.
    private static func percentile(_ sorted: [Double], _ q: Double) -> Double {
        let at = q / 100 * Double(sorted.count - 1)
        let lo = Int(at.rounded(.down))
        let hi = min(lo + 1, sorted.count - 1)
        return sorted[lo] + (sorted[hi] - sorted[lo]) * (at - Double(lo))
    }

    /// The 5th to 95th percentile of y along the ink, taken every 1/50 of its height, so it does
    /// not depend on how densely the pen was sampled.
    static func lineHeight(_ strokes: [[CGPoint]]) -> Double {
        let every = strokes.joined()
        guard let first = every.first else { return 1 }
        var lo = first, hi = first
        for p in every {
            lo = CGPoint(x: min(lo.x, p.x), y: min(lo.y, p.y))
            hi = CGPoint(x: max(hi.x, p.x), y: max(hi.y, p.y))
        }
        let span = max(Double(hi.y - lo.y), Double(hi.x - lo.x) / 10, 1)
        let ys = strokes.flatMap { resample($0, step: span / 50).map(\.y) }.sorted()
        return max(percentile(ys, 95) - percentile(ys, 5), 1)
    }

    /// (dx, dy, sin θ, cos θ, pen) for each point, row after row; pen is 1 where a stroke begins.
    static func features(_ strokes: [[CGPoint]]) -> [Float] {
        let strokes = strokes.filter { !$0.isEmpty }
        guard !strokes.isEmpty else { return [] }
        let h = lineHeight(strokes)
        var rows: [Double] = []
        var prev: (x: Double, y: Double)?
        for s in strokes {
            for (j, p) in resample(s, step: step * h).enumerated() {
                var dx = 0.0, dy = 0.0
                if let q = prev {
                    dx = (p.x - q.x) / h
                    dy = (p.y - q.y) / h
                }
                let n = hypot(dx, dy)
                rows += [min(4, max(-4, dx)), min(4, max(-4, dy)), n > 1e-9 ? dy / n : 0, n > 1e-9 ? dx / n : 1,
                         j == 0 ? 1 : 0]
                prev = p
            }
        }
        let count = rows.count / features
        guard count > maxPoints else { return rows.map { Float($0) } }
        // A very long line: every k-th point (moves summed so the path still adds up).
        let k = (count + maxPoints - 1) / maxPoints
        var thin: [Float] = []
        var i = 0
        while i < count {
            let end = min(i + k, count)
            // Summed in float32, as numpy sums the float32 rows.
            var dx: Float = 0, dy: Float = 0, pen: Float = 0
            for r in i..<end {
                dx += Float(rows[r * features])
                dy += Float(rows[r * features + 1])
                pen = max(pen, Float(rows[r * features + 4]))
            }
            let n = (dx * dx + dy * dy).squareRoot()
            thin += [min(4, max(-4, dx)), min(4, max(-4, dy)), n > 1e-9 ? dy / n : 0, n > 1e-9 ? dx / n : 1, pen]
            i = end
        }
        return thin
    }

    // MARK: The network

    /// Kernel-5 convolution (padding 2) + bias + ReLU of a [c, n] sequence, as one matrix product.
    private static func conv(_ x: [Float], n: Int, _ layer: Conv) -> (values: [Float], count: Int) {
        let m = (n - 1) / layer.stride + 1
        var cols = [Float](repeating: 0, count: layer.cin * 5 * m)
        for ci in 0..<layer.cin {
            for k in 0..<5 {
                let row = (ci * 5 + k) * m
                for t in 0..<m {
                    let src = t * layer.stride + k - 2
                    if src >= 0, src < n { cols[row + t] = x[ci * n + src] }
                }
            }
        }
        var out = HandwritingModel.matmul(layer.w, cols, m: layer.cout, n: m, p: layer.cin * 5)
        for o in 0..<layer.cout {
            let b = layer.b[o]
            for t in 0..<m {
                let v = out[o * m + t] + b
                out[o * m + t] = v > 0 ? v : 0
            }
        }
        return (out, m)
    }

    /// Log-probabilities of every class for each output column (one per four points), of a line's
    /// strokes in the order they were drawn (levelled page points); nil without ink.
    func logProbs(_ strokes: [[CGPoint]]) -> [[Float]]? {
        let f = Self.features(strokes)
        let n = f.count / Self.features
        guard n > 0 else { return nil }
        var x = [Float](repeating: 0, count: f.count)
        for t in 0..<n {
            for c in 0..<Self.features { x[c * n + t] = f[t * Self.features + c] }
        }
        var steps = n
        var c = Self.features
        for layer in convs {
            (x, steps) = Self.conv(x, n: steps, layer)
            c = layer.cout
        }
        var seq = [Float](repeating: 0, count: steps * c)
        for t in 0..<steps {
            for ch in 0..<c { seq[t * c + ch] = x[ch * steps + t] }
        }
        let hidden = HandwritingModel.hidden
        for layer in 0..<2 {
            let fwd = HandwritingModel.run(seq, steps: steps, lstms[2 * layer], reverse: false)
            let bwd = HandwritingModel.run(seq, steps: steps, lstms[2 * layer + 1], reverse: true)
            var joined = [Float](repeating: 0, count: steps * 2 * hidden)
            for t in 0..<steps {
                for j in 0..<hidden {
                    joined[t * 2 * hidden + j] = fwd[t * hidden + j]
                    joined[t * 2 * hidden + hidden + j] = bwd[t * hidden + j]
                }
            }
            seq = joined
        }
        let logits = HandwritingModel.matmul(seq, fcT, m: steps, n: classes, p: 2 * hidden)
        return (0..<steps).map { t in
            var row = Array(logits[(t * classes)..<((t + 1) * classes)])
            for k in 0..<classes { row[k] += fcB[k] }
            let m = row.max() ?? 0
            let sum = row.reduce(Float(0)) { $0 + exp($1 - m) }
            let lse = m + log(sum)
            return row.map { $0 - lse }
        }
    }
}
