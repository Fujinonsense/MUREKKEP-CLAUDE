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

// MARK: - Lines, marks and exponents

/// Which strokes form a line of writing, where dots and accents belong, and which small raised
/// strokes are exponents (twin of tests/ports/inkline.py). Letter-size strokes (at least 0.6 × the
/// median stroke height) build the lines, each joining the line whose band it overlaps by 40 % of the
/// smaller height; the band follows the line's slope once it has three letters. Every smaller stroke
/// (dots, accents, commas, exponents) then joins the nearest line, preferring lines it lies beside.
extension InkLine {
    private static let primaryShare: CGFloat = 0.6
    private static let joinShare: CGFloat = 0.4
    private static let raisedBottom: CGFloat = 0.3
    private static let raisedMin: CGFloat = 0.25
    private static let overLetter: CGFloat = 0.1
    private static let groupGap: CGFloat = 0.5

    private struct Box {
        let minX: CGFloat
        let maxX: CGFloat
        let minY: CGFloat
        let maxY: CGFloat
        var h: CGFloat { maxY - minY }
        var cx: CGFloat { (minX + maxX) / 2 }
        var cy: CGFloat { (minY + maxY) / 2 }

        init(_ r: InkRect) {
            minX = CGFloat(r.minX)
            maxX = CGFloat(r.maxX)
            minY = CGFloat(r.minY)
            maxY = CGFloat(r.maxY)
        }
    }

    /// Python's statistics.median.
    private static func median(_ values: [CGFloat]) -> CGFloat {
        let v = values.sorted()
        guard !v.isEmpty else { return 0 }
        let m = v.count / 2
        return v.count % 2 == 1 ? v[m] : (v[m - 1] + v[m]) / 2
    }

    private static func letterHeight(_ boxes: [Box]) -> CGFloat {
        let hs = boxes.map(\.h).filter { $0 >= 3 }
        return hs.isEmpty ? max(boxes.map(\.h).max() ?? 1, 1) : median(hs)
    }

    /// Top and bottom of a line's letters at `x`.
    private static func band(_ members: [Int], _ boxes: [Box], at x: CGFloat) -> (top: CGFloat, bottom: CGFloat) {
        let ms = members.map { boxes[$0] }
        guard ms.count >= 3 else {
            return (ms.map(\.minY).min() ?? 0, ms.map(\.maxY).max() ?? 0)
        }
        let core = median(ms.map(\.h))
        let n = CGFloat(ms.count)
        let mx = ms.reduce(0) { $0 + $1.cx } / n
        let my = ms.reduce(0) { $0 + $1.cy } / n
        let sxx = ms.reduce(0) { $0 + ($1.cx - mx) * ($1.cx - mx) }
        let sxy = ms.reduce(0) { $0 + ($1.cx - mx) * ($1.cy - my) }
        let a = sxx > 1e-9 ? sxy / sxx : 0
        let yc = my + a * (x - mx)
        return (yc - core / 2, yc + core / 2)
    }

    /// The lines of a batch of strokes, top to bottom; each keeps the strokes' original order.
    static func lines(_ strokes: [Stroke]) -> [[Stroke]] {
        guard !strokes.isEmpty else { return [] }
        let boxes = strokes.map { Box($0.bounds) }
        let letter = letterHeight(boxes)
        let primary = boxes.indices.filter { boxes[$0].h >= primaryShare * letter }
            .sorted { (boxes[$0].minX, $0) < (boxes[$1].minX, $1) }
        guard !primary.isEmpty else { return [strokes] }
        var found: [[Int]] = []
        for i in primary {
            let b = boxes[i]
            var best: Int?
            var bestRatio: CGFloat = 0
            for (k, members) in found.enumerated() {
                let (top, bottom) = band(members, boxes, at: b.cx)
                let overlap = max(0, min(b.maxY, bottom) - max(b.minY, top))
                let ratio = overlap / max(min(b.h, bottom - top), 1e-6)
                if ratio > bestRatio {
                    best = k
                    bestRatio = ratio
                }
            }
            if let k = best, bestRatio >= joinShare {
                found[k].append(i)
            } else {
                found.append([i])
            }
        }
        let taken = Set(primary)
        for (i, b) in boxes.enumerated() where !taken.contains(i) {
            var best = 0
            var bestKey: (Int, CGFloat)?
            for (k, members) in found.enumerated() {
                let (top, bottom) = band(members, boxes, at: b.cx)
                let gap: CGFloat = b.cy >= top && b.cy <= bottom ? 0 : min(abs(b.cy - top), abs(b.cy - bottom))
                let reach = 2 * (bottom - top)
                let left = members.map { boxes[$0].minX }.min() ?? 0
                let right = members.map { boxes[$0].maxX }.max() ?? 0
                let beside = b.cx >= left - reach && b.cx <= right + reach
                let key = (beside ? 0 : 1, gap)
                if bestKey == nil || key < bestKey! {
                    best = k
                    bestKey = key
                }
            }
            found[best].append(i)
        }
        let ordered = found.map { $0.sorted() }.sorted { a, b in
            let ma = a.reduce(0) { $0 + boxes[$1].cy } / CGFloat(a.count)
            let mb = b.reduce(0) { $0 + boxes[$1].cy } / CGFloat(b.count)
            return (ma, a[0]) < (mb, b[0])
        }
        return ordered.map { $0.map { strokes[$0] } }
    }

    /// A line without its exponents, and the exponents (small, high, after a letter, not a dot or
    /// accent over one) grouped left to right with where each group starts.
    static func splitRaised(_ line: [Stroke]) -> (base: [Stroke], raised: [(strokes: [Stroke], x: CGFloat)]) {
        let boxes = line.map { Box($0.bounds) }
        let letter = letterHeight(boxes)
        let primary = boxes.indices.filter { boxes[$0].h >= primaryShare * letter }
        guard !primary.isEmpty else { return (line, []) }
        let core = median(primary.map { boxes[$0].h })
        let firstX = primary.map { boxes[$0].minX }.min() ?? 0
        let primarySet = Set(primary)
        var raised: [Int] = []
        for (i, b) in boxes.enumerated() where !primarySet.contains(i) {
            let top = band(primary, boxes, at: b.cx).top
            let overALetter = primary.contains { j in
                b.cx >= boxes[j].minX - overLetter * core && b.cx <= boxes[j].maxX + overLetter * core
            }
            if b.maxY < top + raisedBottom * core, b.h >= raisedMin * core, !overALetter, b.minX > firstX {
                raised.append(i)
            }
        }
        raised.sort { (boxes[$0].minX, $0) < (boxes[$1].minX, $1) }
        var groups: [[Int]] = []
        for i in raised {
            if let last = groups.last, let right = last.map({ boxes[$0].maxX }).max(),
               boxes[i].minX - right < groupGap * core {
                groups[groups.count - 1].append(i)
            } else {
                groups.append([i])
            }
        }
        let raisedSet = Set(raised)
        let base = line.indices.filter { !raisedSet.contains($0) }.map { line[$0] }
        let exponents = groups.map { g -> (strokes: [Stroke], x: CGFloat) in
            (strokes: g.map { line[$0] }, x: g.map { boxes[$0].minX }.min() ?? 0)
        }
        return (base, exponents)
    }
}
