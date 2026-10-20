import Accelerate
import Foundation
import UIKit

/// Mürekkep's own handwriting reader, trained on ugly Turkish and English handwriting (see
/// ml/handwriting). It runs on the device with Accelerate, as a step-by-step transcription of
/// ml/handwriting/infer_np.py, which is checked against PyTorch.
final class HandwritingModel {
    /// nil when the model asset is missing or unreadable; the text pen then reads with Vision only.
    static let shared: HandwritingModel? = {
        guard let asset = NSDataAsset(name: "hwmodel"), let model = HandwritingModel(data: asset.data) else {
            print("Mürekkep: handwriting model not available, reading with Vision")
            return nil
        }
        return model
    }()

    let charset: [Character]
    var classes: Int { charset.count + 1 }

    private struct Conv {
        let w: [Float]  // [out, in × 9]
        let b: [Float]
        let cin: Int
        let cout: Int
    }

    private struct LSTM {
        let wihT: [Float]  // [inputs, 640]
        let whh: [Float]   // [640, 160]
        let b: [Float]     // [640]
        let inputs: Int
    }

    private let convs: [Conv]
    private let lstms: [LSTM]  // layer 1 forward, layer 1 backward, layer 2 forward, layer 2 backward
    private let fcT: [Float]   // [320, classes]
    private let fcB: [Float]
    private static let hidden = 160
    private static let pools: [Int: (Int, Int)] = [0: (2, 2), 1: (2, 2), 3: (2, 1), 5: (2, 1)]

    // MARK: Loading hwmodel.bin

    private struct Reader {
        let bytes: [UInt8]
        var pos = 0

        mutating func u32() -> Int? {
            guard pos + 4 <= bytes.count else { return nil }
            let v = UInt32(bytes[pos]) | UInt32(bytes[pos + 1]) << 8 | UInt32(bytes[pos + 2]) << 16 | UInt32(bytes[pos + 3]) << 24
            pos += 4
            return Int(v)
        }

        mutating func halves(_ n: Int) -> [Float]? {
            guard n >= 0, pos + 2 * n <= bytes.count else { return nil }
            var out = [Float](repeating: 0, count: n)
            for i in 0..<n {
                out[i] = HandwritingModel.float(half: UInt16(bytes[pos + 2 * i]) | UInt16(bytes[pos + 2 * i + 1]) << 8)
            }
            pos += 2 * n
            return out
        }
    }

    /// IEEE half to float, without relying on Float16 (not available on every build target).
    static func float(half h: UInt16) -> Float {
        let sign: UInt32 = UInt32(h >> 15) << 31
        let exponent = Int((h >> 10) & 0x1F)
        let fraction = UInt32(h & 0x3FF)
        if exponent == 0 {
            let v = Float(fraction) / 1024 * Float(pow(2.0, -14.0))
            return sign != 0 ? -v : v
        }
        if exponent == 31 {
            return Float(bitPattern: sign | 0x7F80_0000 | fraction << 13)
        }
        return Float(bitPattern: sign | UInt32(exponent - 15 + 127) << 23 | fraction << 13)
    }

    init?(data: Data) {
        var r = Reader(bytes: [UInt8](data))
        guard r.bytes.count > 16, Array(r.bytes[0..<8]) == Array("MRKHW1".utf8) + [0, 0] else { return nil }
        r.pos = 8
        guard r.u32() == 1, let nChars = r.u32(), r.pos + nChars <= r.bytes.count,
              let text = String(bytes: r.bytes[r.pos..<(r.pos + nChars)], encoding: .utf8) else { return nil }
        r.pos += nChars
        charset = Array(text)
        guard let count = r.u32(), count == 26 else { return nil }
        var tensors: [(dims: [Int], values: [Float])] = []
        for _ in 0..<count {
            guard let rank = r.u32(), rank >= 1, rank <= 4 else { return nil }
            var dims: [Int] = []
            for _ in 0..<rank {
                guard let d = r.u32() else { return nil }
                dims.append(d)
            }
            guard let values = r.halves(dims.reduce(1, *)) else { return nil }
            tensors.append((dims, values))
        }
        var convs: [Conv] = []
        var cin = 1
        for i in 0..<6 {
            let w = tensors[2 * i]
            guard w.dims.count == 4, w.dims[1] == cin, w.dims[2] == 3, w.dims[3] == 3 else { return nil }
            convs.append(Conv(w: w.values, b: tensors[2 * i + 1].values, cin: cin, cout: w.dims[0]))
            cin = w.dims[0]
        }
        var lstms: [LSTM] = []
        var inputs = cin * 3
        for k in 0..<4 {
            let wih = tensors[12 + 3 * k]
            guard wih.dims == [4 * Self.hidden, inputs] else { return nil }
            lstms.append(LSTM(wihT: Self.transpose(wih.values, rows: 4 * Self.hidden, cols: inputs),
                              whh: tensors[13 + 3 * k].values, b: tensors[14 + 3 * k].values, inputs: inputs))
            if k == 1 { inputs = 2 * Self.hidden }
        }
        let fc = tensors[24]
        guard fc.dims == [charset.count + 1, 2 * Self.hidden] else { return nil }
        self.convs = convs
        self.lstms = lstms
        fcT = Self.transpose(fc.values, rows: fc.dims[0], cols: fc.dims[1])
        fcB = tensors[25].values
    }

    private static func transpose(_ a: [Float], rows: Int, cols: Int) -> [Float] {
        var out = [Float](repeating: 0, count: rows * cols)
        for r in 0..<rows {
            for c in 0..<cols {
                out[c * rows + r] = a[r * cols + c]
            }
        }
        return out
    }

    // MARK: The network

    /// C[m × n] = A[m × p] · B[p × n], row-major.
    private static func matmul(_ a: [Float], _ b: [Float], m: Int, n: Int, p: Int) -> [Float] {
        var c = [Float](repeating: 0, count: m * n)
        a.withUnsafeBufferPointer { pa in
            b.withUnsafeBufferPointer { pb in
                c.withUnsafeMutableBufferPointer { pc in
                    vDSP_mmul(pa.baseAddress!, 1, pb.baseAddress!, 1, pc.baseAddress!, 1,
                              vDSP_Length(m), vDSP_Length(n), vDSP_Length(p))
                }
            }
        }
        return c
    }

    /// 3×3 convolution (zero padding) + bias + ReLU of a [c, h, w] tensor, as one matrix product
    /// over the shifted image (row index channel × 9 + dy × 3 + dx).
    private static func conv(_ x: [Float], h: Int, w: Int, _ layer: Conv) -> [Float] {
        let hw = h * w
        var cols = [Float](repeating: 0, count: layer.cin * 9 * hw)
        x.withUnsafeBufferPointer { px in
            cols.withUnsafeMutableBufferPointer { pc in
                for ci in 0..<layer.cin {
                    for dy in 0..<3 {
                        for dx in 0..<3 {
                            let row = (ci * 9 + dy * 3 + dx) * hw
                            for y in 0..<h {
                                let sy = y + dy - 1
                                guard sy >= 0, sy < h else { continue }
                                for xx in 0..<w {
                                    let sx = xx + dx - 1
                                    guard sx >= 0, sx < w else { continue }
                                    pc[row + y * w + xx] = px[ci * hw + sy * w + sx]
                                }
                            }
                        }
                    }
                }
            }
        }
        var out = matmul(layer.w, cols, m: layer.cout, n: hw, p: layer.cin * 9)
        out.withUnsafeMutableBufferPointer { po in
            for o in 0..<layer.cout {
                let b = layer.b[o]
                for i in 0..<hw {
                    let v = po[o * hw + i] + b
                    po[o * hw + i] = v > 0 ? v : 0
                }
            }
        }
        return out
    }

    private static func maxPool(_ x: [Float], c: Int, h: Int, w: Int, ph: Int, pw: Int) -> [Float] {
        let oh = h / ph
        let ow = w / pw
        var out = [Float](repeating: -.infinity, count: c * oh * ow)
        for ch in 0..<c {
            for y in 0..<(oh * ph) {
                for xx in 0..<(ow * pw) {
                    let o = ch * oh * ow + (y / ph) * ow + xx / pw
                    out[o] = max(out[o], x[ch * h * w + y * w + xx])
                }
            }
        }
        return out
    }

    private static func sigmoid(_ v: Float) -> Float { 1 / (1 + exp(-v)) }

    private static func run(_ xs: [Float], steps: Int, _ layer: LSTM, reverse: Bool) -> [Float] {
        let hidden = Self.hidden
        let gates = 4 * hidden
        let pre = matmul(xs, layer.wihT, m: steps, n: gates, p: layer.inputs)
        var h = [Float](repeating: 0, count: hidden)
        var c = [Float](repeating: 0, count: hidden)
        var out = [Float](repeating: 0, count: steps * hidden)
        for step in 0..<steps {
            let t = reverse ? steps - 1 - step : step
            var g = matmul(layer.whh, h, m: gates, n: 1, p: hidden)
            for k in 0..<gates {
                g[k] += pre[t * gates + k] + layer.b[k]
            }
            for j in 0..<hidden {
                let i = sigmoid(g[j])
                let f = sigmoid(g[hidden + j])
                let gg = tanh(g[2 * hidden + j])
                let o = sigmoid(g[3 * hidden + j])
                c[j] = f * c[j] + i * gg
                h[j] = o * tanh(c[j])
                out[t * hidden + j] = h[j]
            }
        }
        return out
    }

    /// Log-probabilities of every class for each of the image's width / 4 columns.
    func logProbs(_ image: InkLineImage) -> [[Float]] {
        var x = image.pixels
        var c = 1
        var h = InkLine.height
        var w = image.width
        for (i, layer) in convs.enumerated() {
            x = Self.conv(x, h: h, w: w, layer)
            c = layer.cout
            if let pool = Self.pools[i] {
                x = Self.maxPool(x, c: c, h: h, w: w, ph: pool.0, pw: pool.1)
                h /= pool.0
                w /= pool.1
            }
        }
        let steps = w
        let features = c * h
        var seq = [Float](repeating: 0, count: steps * features)
        for t in 0..<steps {
            for ch in 0..<c {
                for r in 0..<h {
                    seq[t * features + ch * h + r] = x[ch * h * w + r * w + t]
                }
            }
        }
        for layer in 0..<2 {
            let fwd = Self.run(seq, steps: steps, lstms[2 * layer], reverse: false)
            let bwd = Self.run(seq, steps: steps, lstms[2 * layer + 1], reverse: true)
            var joined = [Float](repeating: 0, count: steps * 2 * Self.hidden)
            for t in 0..<steps {
                for j in 0..<Self.hidden {
                    joined[t * 2 * Self.hidden + j] = fwd[t * Self.hidden + j]
                    joined[t * 2 * Self.hidden + Self.hidden + j] = bwd[t * Self.hidden + j]
                }
            }
            seq = joined
        }
        let logits = Self.matmul(seq, fcT, m: steps, n: classes, p: 2 * Self.hidden)
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

// MARK: - CTC

/// Reading the model's columns (twin of tests/ports/ctc.py). Class 0 is the blank; class i is
/// charset[i - 1].
enum CTC {
    private static let top = 12  // characters tried per column

    private static func lse(_ xs: Float...) -> Float {
        let m = xs.max() ?? -.infinity
        guard m > -.infinity else { return -.infinity }
        return m + log(xs.reduce(Float(0)) { $0 + exp($1 - m) })
    }

    /// The most likely texts with their log probabilities, best first (prefix beam search).
    static func beam(_ lp: [[Float]], charset: [Character], width: Int = 8) -> [(text: String, score: Float)] {
        var beams: [[Int]: (b: Float, nb: Float)] = [[]: (0, -.infinity)]
        for row in lp {
            let tops = (1..<row.count).sorted { (row[$0], -$0) > (row[$1], -$1) }.prefix(top)
            var next: [[Int]: (b: Float, nb: Float)] = [:]
            func add(_ prefix: [Int], b: Float = -.infinity, nb: Float = -.infinity) {
                let old = next[prefix] ?? (-.infinity, -.infinity)
                next[prefix] = (lse(old.b, b), lse(old.nb, nb))
            }
            for (prefix, p) in beams {
                add(prefix, b: lse(p.b, p.nb) + row[0])
                for k in tops {
                    if prefix.last == k {
                        add(prefix + [k], nb: p.b + row[k])  // a repeat needs a blank in between
                        add(prefix, nb: p.nb + row[k])        // the same character held longer
                    } else {
                        add(prefix + [k], nb: lse(p.b, p.nb) + row[k])
                    }
                }
            }
            beams = Dictionary(uniqueKeysWithValues: next.sorted { lse($0.value.b, $0.value.nb) > lse($1.value.b, $1.value.nb) }
                .prefix(width).map { ($0.key, $0.value) })
        }
        return beams.map { (String($0.key.map { charset[$0 - 1] }), lse($0.value.b, $0.value.nb)) }
            .sorted { $0.1 > $1.1 }
            .map { (text: $0.0, score: $0.1) }
    }

    /// log P(text) over all paths (forward algorithm); nil when a character is not in the charset.
    static func score(_ text: String, _ lp: [[Float]], charset: [Character]) -> Float? {
        guard !lp.isEmpty else { return nil }
        var labels = [0]
        for ch in text {
            guard let k = charset.firstIndex(of: ch) else { return nil }
            labels += [k + 1, 0]
        }
        let n = labels.count
        var alpha = [Float](repeating: -.infinity, count: n)
        alpha[0] = lp[0][labels[0]]
        if n > 1 { alpha[1] = lp[0][labels[1]] }
        for t in 1..<lp.count {
            var next = [Float](repeating: -.infinity, count: n)
            for s in 0..<n {
                var v = alpha[s]
                if s >= 1 { v = lse(v, alpha[s - 1]) }
                if s >= 2, labels[s] != 0, labels[s] != labels[s - 2] { v = lse(v, alpha[s - 2]) }
                next[s] = v + lp[t][labels[s]]
            }
            alpha = next
        }
        return n > 1 ? lse(alpha[n - 1], alpha[n - 2]) : alpha[n - 1]
    }

    /// Column of each character the best single path writes.
    static func alignment(_ lp: [[Float]]) -> [Int] {
        var frames: [Int] = []
        var prev = 0
        for (t, row) in lp.enumerated() {
            let k = row.indices.max { row[$0] < row[$1] } ?? 0
            if k != prev && k != 0 { frames.append(t) }
            prev = k
        }
        return frames
    }
}
