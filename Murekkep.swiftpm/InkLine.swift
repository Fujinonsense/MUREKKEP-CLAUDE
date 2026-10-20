import CoreGraphics
import Foundation

/// One line of handwriting as the handwriting model sees it: 48 pixels high, ink 1 on 0.
struct InkLineImage {
    let width: Int
    /// Row-major, `InkLine.height` rows of `width` pixels.
    let pixels: [Float]
    /// Image point = page point × scale + origin.
    let scale: CGFloat
    let origin: CGPoint
}

/// Draws a line of strokes for the handwriting model (twin of ml/handwriting/ink_render.py; both
/// use the same constants). The middle 90 % of the line's points is scaled to `core` pixels, and
/// every stroke is drawn as the same thin line whatever pen wrote it, so lava, grass or a 3D gel pen
/// read exactly like a ballpoint.
enum InkLine {
    static let height = 48
    static let core: CGFloat = 30
    static let top: CGFloat = 9
    static let left: CGFloat = 4
    static let margin = 8
    static let minWidth = 16
    static let maxWidth = 1600
    static let linePx: CGFloat = 2.4

    /// numpy's percentile (linear interpolation) of sorted values; `q` in 0…100.
    static func percentile(_ sorted: [CGFloat], _ q: CGFloat) -> CGFloat {
        guard !sorted.isEmpty else { return 0 }
        let pos = q / 100 * CGFloat(sorted.count - 1)
        let i = Int(pos.rounded(.down))
        guard i + 1 < sorted.count else { return sorted[sorted.count - 1] }
        return sorted[i] + (sorted[i + 1] - sorted[i]) * (pos - CGFloat(i))
    }

    static func render(_ strokes: [Stroke]) -> InkLineImage? {
        let ink = strokes.filter { !$0.points.isEmpty }
        guard !ink.isEmpty else { return nil }
        var ys: [CGFloat] = []
        var minX = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude
        for s in ink {
            for p in s.points {
                ys.append(CGFloat(p.y))
                minX = min(minX, CGFloat(p.x))
                maxX = max(maxX, CGFloat(p.x))
            }
        }
        ys.sort()
        let p5 = percentile(ys, 5)
        let p95 = percentile(ys, 95)
        var scale = core / max(p95 - p5, 1)
        let inkWidth = (maxX - minX) * scale
        if Int(inkWidth.rounded(.up)) + margin > maxWidth {
            // A very long line is shrunk to fit rather than cut.
            scale *= CGFloat(maxWidth - margin) / max(inkWidth, 1e-6)
        }
        let dx = left - minX * scale
        let dy = top - p5 * scale
        var w = Int(((maxX - minX) * scale).rounded(.up)) + margin
        w = (w + 3) / 4 * 4
        w = min(max(w, minWidth), maxWidth)

        guard let ctx = CGContext(data: nil, width: w, height: height, bitsPerComponent: 8, bytesPerRow: w,
                                  space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        ctx.setFillColor(gray: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: height))
        // Rows go down like the image's: memory row 0 is the top.
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)
        ctx.setStrokeColor(gray: 1, alpha: 1)
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.setLineWidth(linePx)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        for s in ink {
            let pts = s.points.map { CGPoint(x: CGFloat($0.x) * scale + dx, y: CGFloat($0.y) * scale + dy) }
            if pts.count == 1 {
                let r = linePx * 0.6
                ctx.fillEllipse(in: CGRect(x: pts[0].x - r, y: pts[0].y - r, width: r * 2, height: r * 2))
                continue
            }
            ctx.move(to: pts[0])
            for p in pts.dropFirst() {
                ctx.addLine(to: p)
            }
            ctx.strokePath()
        }
        guard let data = ctx.data else { return nil }
        let bytes = data.bindMemory(to: UInt8.self, capacity: w * height)
        var pixels = [Float](repeating: 0, count: w * height)
        for i in 0..<(w * height) {
            pixels[i] = Float(bytes[i]) / 255
        }
        return InkLineImage(width: w, pixels: pixels, scale: scale, origin: CGPoint(x: dx, y: dy))
    }
}
