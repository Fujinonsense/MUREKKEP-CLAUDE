import CoreGraphics
import Foundation
import Vision

/// The ink of a page drawn for text recognition only: black, even lines on white, without the paper
/// pattern and without any 3D effect. Sea foam, pearl beads, grass blades or a lightning glow would
/// otherwise look like extra letters, so every brush is read exactly like a plain pen.
struct InkRaster: @unchecked Sendable {
    let image: CGImage
    /// Page point at the image's top-left corner.
    let origin: CGPoint
    /// Pixels per page point.
    let scale: CGFloat

    /// Page rectangle of a Vision bounding box (normalized, bottom-left origin).
    func pageRect(fromVision box: CGRect) -> CGRect {
        let w = CGFloat(image.width) / scale
        let h = CGFloat(image.height) / scale
        return CGRect(x: origin.x + box.minX * w, y: origin.y + (1 - box.maxY) * h,
                      width: box.width * w, height: box.height * h)
    }

    /// nil when there is no ink to read. `lineScale` thickens the lines for a second attempt.
    static func render(_ strokes: [Stroke], lineScale: CGFloat = 1, maxPixels: CGFloat = 2800) -> InkRaster? {
        let ink = strokes.filter { $0.brush != .highlighter && !$0.points.isEmpty }
        guard !ink.isEmpty else { return nil }
        var minX = CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude
        for s in ink where !s.bounds.isEmpty {
            minX = min(minX, CGFloat(s.bounds.minX))
            minY = min(minY, CGFloat(s.bounds.minY))
            maxX = max(maxX, CGFloat(s.bounds.maxX))
            maxY = max(maxY, CGFloat(s.bounds.maxY))
        }
        guard minX < maxX || minY < maxY else { return nil }
        // Vision reads handwriting best when letters are about 50 px tall, so the scale follows the
        // size of the writing: small notes are enlarged, big letters are not blown up.
        let letter = letterHeight(ink)
        var scale = min(max(52 / letter, 2.2), 6)
        let contentLongest = max(maxX - minX, maxY - minY, 1) + 36
        if contentLongest * scale > maxPixels {
            scale = max(0.8, maxPixels / contentLongest)
        }
        // At least 32 white pixels around the writing: Vision misses letters that touch the edge.
        let margin = max(18, 32 / scale)
        let rect = CGRect(x: minX - margin, y: minY - margin,
                          width: max(maxX - minX, 1) + margin * 2, height: max(maxY - minY, 1) + margin * 2)
        let w = max(8, Int((rect.width * scale).rounded(.up)))
        let h = max(8, Int((rect.height * scale).rounded(.up)))
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        // Page space is y-down.
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: scale, y: -scale)
        ctx.translateBy(x: -rect.minX, y: -rect.minY)
        ctx.setStrokeColor(gray: 0, alpha: 1)
        ctx.setFillColor(gray: 0, alpha: 1)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        // Lines like a fine pen at this letter size: too thin and letters break apart, too thick and
        // the holes of a, e, o close up.
        let thinnest = max(1.0, letter * 0.06)
        let thickest = max(thinnest, min(3.0, letter * 0.15))
        for s in ink {
            let lineWidth = min(max(CGFloat(s.width) * 0.55, thinnest), thickest) * lineScale
            let pts = s.points
            if pts.count == 1 {
                let r = lineWidth * 0.6
                ctx.fillEllipse(in: CGRect(x: CGFloat(pts[0].x) - r, y: CGFloat(pts[0].y) - r, width: r * 2, height: r * 2))
                continue
            }
            ctx.setLineWidth(lineWidth)
            ctx.move(to: CGPoint(x: CGFloat(pts[0].x), y: CGFloat(pts[0].y)))
            for p in pts.dropFirst() {
                ctx.addLine(to: CGPoint(x: CGFloat(p.x), y: CGFloat(p.y)))
            }
            ctx.strokePath()
        }
        guard let image = ctx.makeImage() else { return nil }
        return InkRaster(image: image, origin: rect.origin, scale: scale)
    }

    /// Typical height of the writing in points: the median height of strokes that look like letters
    /// (not dots, not long lines or drawings).
    private static func letterHeight(_ ink: [Stroke]) -> CGFloat {
        let heights = ink.compactMap { s -> CGFloat? in
            let h = CGFloat(s.bounds.maxY - s.bounds.minY)
            let w = CGFloat(s.bounds.maxX - s.bounds.minX)
            guard h >= 3, h < 120, w < 600 else { return nil }
            return h
        }.sorted()
        guard !heights.isEmpty else { return 16 }
        return min(max(heights[heights.count / 2], 6), 60)
    }
}

struct OCRWord: Sendable {
    var text: String
    var box: CGRect
}

/// One recognized line. Boxes are in page points when the image was an `InkRaster`, otherwise
/// normalized with a top-left origin.
struct OCRLine: Sendable {
    var text: String
    var box: CGRect
    var words: [OCRWord]
    /// Other readings Vision considered for the same line (from both passes).
    var alternatives: [OCRVariant] = []
}

struct OCRVariant: Sendable {
    var text: String
    var words: [OCRWord]
}

/// On-device text recognition (printed text and handwriting) with Vision. No network.
enum PageOCR {
    /// Plain text of a page image in reading order: column by column, with printed answer blanks as
    /// "___".
    static func recognize(_ image: CGImage) async -> String {
        let found = await lines(in: image)
        let w = CGFloat(image.width)
        let h = CGFloat(image.height)
        func pixels(_ r: CGRect) -> CGRect {
            CGRect(x: r.minX * w, y: r.minY * h, width: r.width * w, height: r.height * h)
        }
        let pieces = found.map { line in
            ReadingOrder.Piece(text: line.text, box: pixels(line.box),
                               words: line.words.map { (text: $0.text, box: pixels($0.box)) })
        }
        return ReadingOrder.lines(pieces).joined(separator: "\n")
    }

    /// Lines of an arbitrary image (boxes normalized, top-left origin).
    static func lines(in image: CGImage) async -> [OCRLine] {
        await withCheckedContinuation { (cont: CheckedContinuation<[OCRLine], Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                cont.resume(returning: recognizeNow(image) { box in
                    CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height)
                })
            }
        }
    }

    /// Lines of the page ink (boxes in page points).
    static func lines(in raster: InkRaster) async -> [OCRLine] {
        await withCheckedContinuation { (cont: CheckedContinuation<[OCRLine], Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                cont.resume(returning: recognizeNow(raster.image) { raster.pageRect(fromVision: $0) })
            }
        }
    }

    private static func makeRequest(correction: Bool, imageHeight: Int) -> VNRecognizeTextRequest {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = correction
        // The default ignores text under 1/32 of the image height, which drops ordinary lines of a
        // full page. Anything at least ~12 px tall counts.
        request.minimumTextHeight = Float(min(1.0 / 32, 12 / Double(max(imageHeight, 1))))
        if let supported = try? request.supportedRecognitionLanguages() {
            // The app's language is tried first.
            let order = Loc.isEnglish ? ["en-US", "tr-TR"] : ["tr-TR", "en-US"]
            let wanted = order.filter { supported.contains($0) }
            if !wanted.isEmpty {
                request.recognitionLanguages = wanted
            }
        }
        return request
    }

    /// Two passes over the same image: with language correction (good for words) and without it
    /// (good for math, which correction would "fix" into words). Each line takes the better reading.
    private static func recognizeNow(_ image: CGImage, map: (CGRect) -> CGRect) -> [OCRLine] {
        let corrected = makeRequest(correction: true, imageHeight: image.height)
        let literal = makeRequest(correction: false, imageHeight: image.height)
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([corrected, literal])
        } catch {
            return []
        }
        let a = corrected.results ?? []
        let b = literal.results ?? []
        var used = Set<Int>()
        // The chosen reading of each line, plus the other readings both passes considered.
        var picked: [(VNRecognizedTextObservation, VNRecognizedText, [VNRecognizedText])] = []
        for obs in a {
            let mine = obs.topCandidates(3)
            guard let ca = mine.first else { continue }
            var best = -1
            var bestOverlap: CGFloat = 0.4
            for (j, o) in b.enumerated() where !used.contains(j) {
                let v = overlap(obs.boundingBox, o.boundingBox)
                if v > bestOverlap {
                    bestOverlap = v
                    best = j
                }
            }
            if best >= 0 {
                used.insert(best)
                let literal = b[best].topCandidates(3)
                if let cb = literal.first, prefersLiteral(cb.string, over: ca.string) {
                    picked.append((b[best], cb, mine + literal))
                    continue
                }
                picked.append((obs, ca, mine + literal))
                continue
            }
            picked.append((obs, ca, mine))
        }
        // Lines only the literal pass found (often pure math such as "2+2=5").
        for (j, o) in b.enumerated() where !used.contains(j) {
            let mine = o.topCandidates(3)
            if let c = mine.first, mathScore(c.string) > 0 {
                picked.append((o, c, mine))
            }
        }
        var out: [OCRLine] = []
        for (obs, cand, readings) in picked {
            let text = cand.string.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }
            var seen: Set<String> = [text]
            var alternatives: [OCRVariant] = []
            for r in readings {
                let t = r.string.trimmingCharacters(in: .whitespaces)
                guard !t.isEmpty, seen.insert(t).inserted else { continue }
                alternatives.append(OCRVariant(text: t, words: words(of: r, map: map)))
            }
            out.append(OCRLine(text: text, box: map(obs.boundingBox), words: words(of: cand, map: map), alternatives: alternatives))
        }
        // Top to bottom, then left to right (boxes are top-left based now).
        return out.sorted { l, r in
            let tolerance = min(l.box.height, r.box.height) * 0.5
            if abs(l.box.midY - r.box.midY) > tolerance { return l.box.midY < r.box.midY }
            return l.box.minX < r.box.minX
        }
    }

    private static func words(of cand: VNRecognizedText, map: (CGRect) -> CGRect) -> [OCRWord] {
        let s = cand.string
        var out: [OCRWord] = []
        var i = s.startIndex
        while i < s.endIndex {
            while i < s.endIndex, s[i].isWhitespace {
                i = s.index(after: i)
            }
            guard i < s.endIndex else { break }
            var end = i
            while end < s.endIndex, !s[end].isWhitespace {
                end = s.index(after: end)
            }
            if let rect = try? cand.boundingBox(for: i..<end) {
                out.append(OCRWord(text: String(s[i..<end]), box: map(rect.boundingBox)))
            }
            i = end
        }
        return out
    }

    /// Intersection over the smaller box.
    private static func overlap(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let i = a.intersection(b)
        guard !i.isNull, !i.isEmpty else { return 0 }
        let smaller = min(a.width * a.height, b.width * b.height)
        return smaller > 0 ? (i.width * i.height) / smaller : 0
    }

    static func mathScore(_ s: String) -> Int {
        s.filter { "0123456789+-−=×÷*/^√()%<>±".contains($0) }.count
    }

    private static func prefersLiteral(_ literal: String, over corrected: String) -> Bool {
        let ml = mathScore(literal)
        guard ml > 0 else { return false }
        let mc = mathScore(corrected)
        if ml > mc { return true }
        return literal.contains("=") && !corrected.contains("=")
    }
}
