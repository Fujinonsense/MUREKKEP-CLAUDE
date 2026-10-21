import Foundation

// Stand-ins for the Apple-only pieces the text pen's files use, so the real InkLine.swift,
// HandwritingModel.swift and InkDeskew.swift compile on Windows: Accelerate's vDSP_mmul, NSDataAsset,
// and the part of CoreGraphics that InkLine.render draws with (a bitmap context that strokes round-
// capped polylines and fills ellipses, antialiased by 4 × 4 supersampling, rows top first as in a
// CGBitmapContext seen through the app's flip).

// MARK: Accelerate

typealias vDSP_Length = UInt
typealias vDSP_Stride = Int

/// C[m × n] = A[m × p] · B[p × n], row-major, unit strides (all the app uses).
func vDSP_mmul(_ a: UnsafePointer<Float>, _ ia: vDSP_Stride, _ b: UnsafePointer<Float>, _ ib: vDSP_Stride,
               _ c: UnsafeMutablePointer<Float>, _ ic: vDSP_Stride, _ m: vDSP_Length, _ n: vDSP_Length, _ p: vDSP_Length) {
    precondition(ia == 1 && ib == 1 && ic == 1)
    let m = Int(m), n = Int(n), p = Int(p)
    for i in 0..<m {
        let row = c + i * n
        for j in 0..<n { row[j] = 0 }
        for k in 0..<p {
            let aik = a[i * p + k]
            if aik == 0 { continue }
            let bk = b + k * n
            for j in 0..<n { row[j] += aik * bk[j] }
        }
    }
}

// MARK: UIKit

final class NSDataAsset {
    let data: Data

    /// Reads the file named by the MRK_ASSET_<name> environment variable.
    init?(name: String) {
        guard let path = ProcessInfo.processInfo.environment["MRK_ASSET_\(name)"],
              let data = FileManager.default.contents(atPath: path) else { return nil }
        self.data = data
    }
}

// MARK: The stroke model (InkModel.swift, reduced to what InkLine reads)

struct InkPoint: Equatable {
    var x: Float
    var y: Float
    var r: Float = 0
    var ink: Float = 0
}

struct InkRect: Equatable {
    var minX: Float
    var minY: Float
    var maxX: Float
    var maxY: Float
}

struct Stroke {
    let id: Int
    var points: [InkPoint]
    /// Includes the pen's radius, as in the app.
    var bounds: InkRect {
        var b = InkRect(minX: .infinity, minY: .infinity, maxX: -.infinity, maxY: -.infinity)
        for p in points {
            b.minX = min(b.minX, p.x - p.r)
            b.minY = min(b.minY, p.y - p.r)
            b.maxX = max(b.maxX, p.x + p.r)
            b.maxY = max(b.maxY, p.y + p.r)
        }
        return b
    }
}

// MARK: CoreGraphics

final class CGColorSpace {}

func CGColorSpaceCreateDeviceGray() -> CGColorSpace { CGColorSpace() }

enum CGImageAlphaInfo: UInt32 {
    case none = 0
}

enum CGLineCap { case butt, round, square }
enum CGLineJoin { case miter, round, bevel }

final class CGContext {
    let width: Int
    let height: Int
    private let k = 4
    private var gray: [Float]
    private var bytes: [UInt8]
    // User space → device space: device = (a·x + c·y + tx, b·x + d·y + ty).
    private var a: CGFloat = 1, b: CGFloat = 0, c: CGFloat = 0, d: CGFloat = 1, tx: CGFloat = 0, ty: CGFloat = 0
    private var fill: Float = 0
    private var stroke: Float = 0
    private var lineWidth: CGFloat = 1
    private var path: [[CGPoint]] = []

    init?(data: UnsafeMutableRawPointer?, width: Int, height: Int, bitsPerComponent: Int, bytesPerRow: Int,
          space: CGColorSpace, bitmapInfo: UInt32) {
        guard data == nil, bitsPerComponent == 8, bytesPerRow == width, width > 0, height > 0 else { return nil }
        self.width = width
        self.height = height
        gray = [Float](repeating: 0, count: width * height)
        bytes = [UInt8](repeating: 0, count: width * height)
    }

    /// The pixels, row 0 at the top (memory order of a CGBitmapContext).
    var data: UnsafeMutableRawPointer? {
        for i in 0..<gray.count {
            bytes[i] = UInt8(max(0, min(255, (gray[i] * 255).rounded())))
        }
        return bytes.withUnsafeMutableBytes { $0.baseAddress }
    }

    func setFillColor(gray g: CGFloat, alpha: CGFloat) { fill = Float(g) }
    func setStrokeColor(gray g: CGFloat, alpha: CGFloat) { stroke = Float(g) }
    func setLineWidth(_ w: CGFloat) { lineWidth = w }
    func setLineCap(_ cap: CGLineCap) { precondition(cap == .round) }
    func setLineJoin(_ join: CGLineJoin) { precondition(join == .round) }

    func translateBy(x: CGFloat, y: CGFloat) {
        tx += a * x + c * y
        ty += b * x + d * y
    }

    func scaleBy(x: CGFloat, y: CGFloat) {
        a *= x
        b *= x
        c *= y
        d *= y
    }

    private func device(_ p: CGPoint) -> CGPoint {
        CGPoint(x: a * p.x + c * p.y + tx, y: b * p.x + d * p.y + ty)
    }

    func fill(_ rect: CGRect) {
        for i in 0..<gray.count { gray[i] = fill }  // the app fills the whole context
    }

    func move(to p: CGPoint) { path.append([device(p)]) }

    func addLine(to p: CGPoint) {
        if path.isEmpty { path.append([]) }
        path[path.count - 1].append(device(p))
    }

    /// Paints `colour` over every pixel by the share of its 4 × 4 samples that `inside` covers. A
    /// device pixel (column x, memory row r) spans device y from height − 1 − r to height − r.
    private func paint(_ colour: Float, minX: CGFloat, maxX: CGFloat, minY: CGFloat, maxY: CGFloat,
                       _ inside: (CGFloat, CGFloat) -> Bool) {
        let x0 = max(0, Int(minX.rounded(.down)))
        let x1 = min(width - 1, Int(maxX.rounded(.up)))
        let r0 = max(0, height - 1 - Int(maxY.rounded(.up)))
        let r1 = min(height - 1, height - Int(minY.rounded(.down)))
        guard x0 <= x1, r0 <= r1 else { return }
        for r in r0...r1 {
            for x in x0...x1 {
                var hit = 0
                for j in 0..<k {
                    let dy = CGFloat(height - 1 - r) + (CGFloat(j) + 0.5) / CGFloat(k)
                    for i in 0..<k where inside(CGFloat(x) + (CGFloat(i) + 0.5) / CGFloat(k), dy) {
                        hit += 1
                    }
                }
                guard hit > 0 else { continue }
                let cover = Float(hit) / Float(k * k)
                let o = r * width + x
                gray[o] = gray[o] * (1 - cover) + colour * cover
            }
        }
    }

    func strokePath() {
        let radius = lineWidth / 2 * abs(a)
        for poly in path where !poly.isEmpty {
            let xs = poly.map(\.x), ys = poly.map(\.y)
            paint(stroke, minX: xs.min()! - radius, maxX: xs.max()! + radius,
                  minY: ys.min()! - radius, maxY: ys.max()! + radius) { px, py in
                // Inside the union of the round-capped segments (one path: covered once).
                if poly.count == 1 {
                    return hypot(px - poly[0].x, py - poly[0].y) <= radius
                }
                for s in 1..<poly.count {
                    let p = poly[s - 1], q = poly[s]
                    let vx = q.x - p.x, vy = q.y - p.y
                    let len2 = vx * vx + vy * vy
                    var t: CGFloat = 0
                    if len2 > 0 { t = max(0, min(1, ((px - p.x) * vx + (py - p.y) * vy) / len2)) }
                    if hypot(px - (p.x + t * vx), py - (p.y + t * vy)) <= radius { return true }
                }
                return false
            }
        }
        path = []
    }

    func fillEllipse(in rect: CGRect) {
        let p0 = device(CGPoint(x: rect.minX, y: rect.minY))
        let p1 = device(CGPoint(x: rect.maxX, y: rect.maxY))
        let cx = (p0.x + p1.x) / 2, cy = (p0.y + p1.y) / 2
        let rx = abs(p1.x - p0.x) / 2, ry = abs(p1.y - p0.y) / 2
        guard rx > 0, ry > 0 else { return }
        paint(fill, minX: cx - rx, maxX: cx + rx, minY: cy - ry, maxY: cy + ry) { px, py in
            let u = (px - cx) / rx, v = (py - cy) / ry
            return u * u + v * v <= 1
        }
    }
}
