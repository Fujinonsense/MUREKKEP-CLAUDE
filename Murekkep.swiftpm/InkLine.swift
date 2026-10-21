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
/// strokes are exponents (twin of tests/ports/inkline.py). Boxes are the strokes' own points, without
/// the pen's radius, so a thick 3D ink splits lines exactly like a ballpoint. Letter-size strokes (at
/// least 0.6 × the median stroke height) build the lines, each joining the line whose band it overlaps
/// by 40 % of the smaller height; the band follows the line's slope once it has six letters. A
/// letter-size stroke wholly above or below the band (a y's tail or an ascender drawn on its own) joins
/// a line it stands beside when 75 % of it lies within 1.2 band heights of the band, the line whose
/// band is nearest when two qualify. Lines split while the writing was read left to right are joined
/// again: a smaller line whose middle lies within 0.75 band heights of a bigger one's, or whose letters
/// lie in its reach (a few strokes narrower than 2.5 band heights: in its reach widened to 1.6, for long
/// tails, or within the line's own ascenders and descenders). Every smaller stroke (dots, accents,
/// commas, exponents) then joins the nearest line, preferring lines it lies beside.
extension InkLine {
    private static let primaryShare: CGFloat = 0.6
    private static let joinShare: CGFloat = 0.4
    private static let raisedBottom: CGFloat = 0.3
    private static let raisedMin: CGFloat = 0.25
    private static let overLetter: CGFloat = 0.1
    private static let groupGap: CGFloat = 0.5
    /// An exponent has a stroke at least this many letter heights long; dots, ticks, apostrophes
    /// and breves (written beside their letter) are shorter.
    private static let raisedPath: CGFloat = 1.1
    /// Ascenders and descenders reach this many band heights above and below the band.
    private static let reach: CGFloat = 1.2
    /// Share of a stroke's height inside that reach for it to belong to the line.
    private static let insideShare: CGFloat = 0.75
    /// Lines whose middles are closer than this many band heights are one line.
    private static let mergeShare: CGFloat = 0.75
    /// A "line" of at most this many strokes, narrower than `fragmentWidth` band heights, is a part of
    /// a letter when it lies within `fragmentReach` band heights.
    private static let fragmentCount = 3
    private static let fragmentWidth: CGFloat = 2.5
    private static let fragmentReach: CGFloat = 1.6
    /// Lines whose letters' middles are closer than this many letters are one line.
    private static let sameMiddle: CGFloat = 0.5
    /// A "line" of at most this many strokes may be a letter of another with its accents.
    private static let accented = 6

    private struct Box {
        let minX: CGFloat
        let maxX: CGFloat
        let minY: CGFloat
        let maxY: CGFloat
        var h: CGFloat { maxY - minY }
        var cx: CGFloat { (minX + maxX) / 2 }
        var cy: CGFloat { (minY + maxY) / 2 }

        /// The stroke's points, without the pen's radius.
        init(_ stroke: Stroke) {
            var x0 = Float.infinity
            var x1 = -Float.infinity
            var y0 = Float.infinity
            var y1 = -Float.infinity
            for p in stroke.points {
                x0 = min(x0, p.x)
                x1 = max(x1, p.x)
                y0 = min(y0, p.y)
                y1 = max(y1, p.y)
            }
            if stroke.points.isEmpty {
                x0 = 0
                x1 = 0
                y0 = 0
                y1 = 0
            }
            minX = CGFloat(x0)
            maxX = CGFloat(x1)
            minY = CGFloat(y0)
            maxY = CGFloat(y1)
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

    /// The slope comes from the line's last 12 letters, at most 5° (tan 5° ≈ 0.0875: the text pen levels
    /// the ink before it looks for lines), and only once the line has 6 letters.
    private static let recentLetters = 12
    private static let fitLetters = 6
    private static let maxSlope: CGFloat = 0.0875

    /// Top and bottom of a line's letters at `x`. The slope is the median of the slopes between the
    /// last letters, so a capital or a descender among them cannot tilt the band; a shorter line is
    /// level ("Bug" alone would point the band below the next letter).
    private static func band(_ members: [Int], _ boxes: [Box], at x: CGFloat) -> (top: CGFloat, bottom: CGFloat) {
        let ms = members.map { boxes[$0] }
        guard ms.count >= 3 else {
            return (ms.map(\.minY).min() ?? 0, ms.map(\.maxY).max() ?? 0)
        }
        let core = median(ms.map(\.h))
        let recent = Array(ms.suffix(recentLetters))
        var slopes: [CGFloat] = []
        if recent.count >= fitLetters {
            for i in recent.indices {
                for j in (i + 1)..<recent.count where abs(recent[j].cx - recent[i].cx) > 1e-6 {
                    slopes.append((recent[j].cy - recent[i].cy) / (recent[j].cx - recent[i].cx))
                }
            }
        }
        let a = min(max(slopes.isEmpty ? 0 : median(slopes), -maxSlope), maxSlope)
        // The slope is not carried past the recent letters by more than a letter: across a wide word
        // gap a slope fitted from pieces of letters walked the band off the line.
        let lo = (recent.map(\.cx).min() ?? x) - core
        let hi = (recent.map(\.cx).max() ?? x) + core
        let yc = median(recent.map { $0.cy - a * $0.cx }) + a * min(max(x, lo), hi)
        return (yc - core / 2, yc + core / 2)
    }

    private static func overlap(_ lo1: CGFloat, _ hi1: CGFloat, _ lo2: CGFloat, _ hi2: CGFloat) -> CGFloat {
        max(0, min(hi1, hi2) - max(lo1, lo2))
    }

    /// The line a stroke above or below every band belongs to: one it stands beside (not past the line's
    /// right end by more than two band heights) with 75 % of the stroke within the ascender and
    /// descender reach of its band; the line whose band is nearest wins.
    private static func reachingLine(_ found: [[Int]], _ boxes: [Box], _ b: Box) -> Int? {
        var best: Int?
        var bestGap: CGFloat = 0
        for (k, members) in found.enumerated() {
            let (top, bottom) = band(members, boxes, at: b.cx)
            var core = bottom - top
            if members.count < 3 {
                // A line of one or two strokes has their whole height as its band already.
                core = median(members.map { boxes[$0].h }) * 0.5
            }
            let share = overlap(b.minY, b.maxY, top - reach * core, bottom + reach * core) / max(b.h, 1e-6)
            let right = members.map { boxes[$0].maxX }.max() ?? 0
            if share < insideShare || b.minX > right + 2 * (bottom - top) { continue }
            let gap: CGFloat = b.maxY >= top && b.minY <= bottom ? 0 : min(abs(b.minY - bottom), abs(top - b.maxY))
            if best == nil || gap < bestGap {
                best = k
                bestGap = gap
            }
        }
        return best
    }

    /// Whether the line `small` is part of the line `big` (see the type's description).
    private static func sameLine(_ small: [Int], _ big: [Int], _ boxes: [Box]) -> Bool {
        let ms = small.map { boxes[$0] }
        // Letters whose middles are within half a letter of the line's are on it, whatever slope was
        // fitted from pieces of letters (a wide word gap then started a "line" beside the first).
        let letter = median(ms.map(\.h) + big.map { boxes[$0].h })
        if abs(median(ms.map(\.cy)) - median(big.map { boxes[$0].cy })) < sameMiddle * letter { return true }
        // A letter of the line with its accents ("Ö" and its dots, a "!" whose dot came apart,
        // apostrophes written high): the tallest stroke ends in the line's band, and the rest lie at
        // most 1.5 band heights above it and one band height below the band.
        if ms.count <= accented, let tall = ms.max(by: { $0.h < $1.h }) {
            let (t, b) = band(big, boxes, at: tall.cx)
            let core = b - t
            if tall.maxY >= t - 0.25 * core, tall.maxY <= b + 0.5 * core,
               ms.allSatisfy({ $0.minY >= tall.minY - 1.5 * core && $0.maxY <= b + core }) {
                return true
            }
        }
        let cx = median(ms.map(\.cx))
        let (top, bottom) = band(big, boxes, at: cx)
        var core = bottom - top
        if big.count < 3 {
            core = median(big.map { boxes[$0].h }) * 0.5
        }
        let height = max(bottom - top, median(ms.map(\.h)))
        if abs(median(ms.map(\.cy)) - (top + bottom) / 2) < mergeShare * height { return true }
        let left = (big.map { boxes[$0].minX }.min() ?? 0) - 2 * (bottom - top)
        let right = (big.map { boxes[$0].maxX }.max() ?? 0) + 2 * (bottom - top)
        let width = (ms.map(\.maxX).max() ?? 0) - (ms.map(\.minX).min() ?? 0)
        let fragment = ms.count <= fragmentCount && width < fragmentWidth * (bottom - top)
        let r = fragment ? fragmentReach : reach
        // A fragment may also lie anywhere within the line's own ascenders and descenders (letters that
        // come in pieces make the band lower than the letters).
        let high = (big.map { boxes[$0].minY }.min() ?? 0) - 0.3 * (bottom - top)
        let low = (big.map { boxes[$0].maxY }.max() ?? 0) + 0.3 * (bottom - top)
        var inside = 0
        for m in ms {
            let (t, b) = band(big, boxes, at: m.cx)
            var share = overlap(m.minY, m.maxY, t - r * core, b + r * core) / max(m.h, 1e-6)
            if fragment {
                share = max(share, overlap(m.minY, m.maxY, high, low) / max(m.h, 1e-6))
            }
            if share >= insideShare && m.cx >= left && m.cx <= right {
                inside += 1
            }
        }
        return CGFloat(inside) >= insideShare * CGFloat(ms.count)
    }

    /// The lines with every split line joined to the line it is part of, smallest first.
    private static func merged(_ lines: [[Int]], _ boxes: [Box]) -> [[Int]] {
        var found = lines
        while found.count > 1 {
            let smallFirst = found.indices.sorted { (found[$0].count, $0) < (found[$1].count, $1) }
            let bigFirst = found.indices.sorted { (-found[$0].count, $0) < (-found[$1].count, $1) }
            var pair: (small: Int, big: Int)?
            search: for s in smallFirst {
                for b in bigFirst where b != s && found[b].count >= found[s].count && sameLine(found[s], found[b], boxes) {
                    pair = (s, b)
                    break search
                }
            }
            guard let chosen = pair else { break }
            let s = chosen.small
            let b = chosen.big
            found[b] = (found[b] + found[s]).sorted { (boxes[$0].minX, $0) < (boxes[$1].minX, $1) }
            found.remove(at: s)
        }
        return found
    }

    /// The lines of a batch of strokes, top to bottom; each keeps the strokes' original order.
    static func lines(_ strokes: [Stroke]) -> [[Stroke]] {
        guard !strokes.isEmpty else { return [] }
        let boxes = strokes.map { Box($0) }
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
            } else if let k = reachingLine(found, boxes, b) {
                found[k].append(i)
            } else {
                found.append([i])
            }
        }
        found = merged(found, boxes)
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

    /// The length of a stroke's pen path.
    private static func path(_ s: Stroke) -> CGFloat {
        zip(s.points, s.points.dropFirst()).reduce(CGFloat(0)) { sum, pair in
            sum + CGFloat(hypot(pair.1.x - pair.0.x, pair.1.y - pair.0.y))
        }
    }

    /// A line without its exponents, and the exponents (small, high, after a letter, not a dot or
    /// accent over one, drawn with a character's length of pen) grouped left to right with where
    /// each group starts.
    static func splitRaised(_ line: [Stroke]) -> (base: [Stroke], raised: [(strokes: [Stroke], x: CGFloat)]) {
        let boxes = line.map { Box($0) }
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
        // A group without one stroke as long as a character's stays in the line.
        groups = groups.filter { g in g.map { path(line[$0]) }.max() ?? 0 >= raisedPath * core }
        let raisedSet = Set(groups.joined())
        let base = line.indices.filter { !raisedSet.contains($0) }.map { line[$0] }
        let exponents = groups.map { g -> (strokes: [Stroke], x: CGFloat) in
            (strokes: g.map { line[$0] }, x: g.map { boxes[$0].minX }.min() ?? 0)
        }
        return (base, exponents)
    }
}
