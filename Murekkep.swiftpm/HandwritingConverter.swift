import CoreGraphics
import Foundation

/// The writing lines of a page: where text sits and how big it is.
struct Ruling {
    /// Baseline of the first writing line.
    var top: CGFloat
    var spacing: CGFloat
    /// Text starts at `left` and wraps before `right`.
    var left: CGFloat
    var right: CGFloat
    var bottom: CGFloat
    /// Height of capital letters on these lines.
    var capHeight: CGFloat

    func baseline(_ k: Int) -> CGFloat {
        top + CGFloat(k) * spacing
    }

    /// The writing line whose baseline is nearest to `y` (never above the first one).
    func index(nearBaseline y: CGFloat) -> Int {
        max(0, Int(((y - top) / spacing).rounded()))
    }

    /// The first writing line at or below `y`.
    func index(atOrBelow y: CGFloat) -> Int {
        max(0, Int(((y - top) / spacing).rounded(.up)))
    }
}

extension PaperStyle {
    /// Writing lines printed on the template, when it has a regular set of them.
    func ruling(pageSize: CGSize) -> Ruling? {
        let w = pageSize.width
        let h = pageSize.height
        switch self {
        case .lined:
            return Ruling(top: 84, spacing: 28, left: 80, right: w - 30, bottom: h - 10, capHeight: 15.4)
        case .narrowLined:
            return Ruling(top: 72, spacing: 21, left: 67, right: w - 26, bottom: h - 10, capHeight: 11.6)
        case .grid, .dotted:
            return Ruling(top: 40, spacing: 20, left: 24, right: w - 24, bottom: h - 10, capHeight: 12)
        case .smallGrid, .engineering:
            return Ruling(top: 42.51, spacing: 28.34, left: 28.34, right: w - 28, bottom: h - 10, capHeight: 15.6)
        case .handwriting:
            return Ruling(top: 100, spacing: 56, left: 46, right: w - 46, bottom: h - 30, capHeight: 21.4)
        case .todo:
            return Ruling(top: 126, spacing: 34, left: 70, right: w - 40, bottom: h - 30, capHeight: 15)
        case .letter:
            return Ruling(top: 410, spacing: 26, left: 44, right: w - 40, bottom: h - 150, capHeight: 14.5)
        default:
            return nil
        }
    }
}

/// Where typeset text ended: the baseline it sat on and the end of its last word (page space).
struct TextEnd: Equatable {
    var baseline: CGFloat
    var x: CGFloat
}

struct ConversionResult {
    var removed: Set<Int>
    var added: [Stroke]
    var lineCount: Int
    var text: String
    /// End of the last word written, so the text pen's next words can follow it.
    var end: TextEnd? = nil
}

/// Turns handwriting into neat text on the page's lines. Each word keeps the brush and color it was
/// written with, so 3D inks stay 3D. The letters come from `StrokeFont`.
enum HandwritingConverter {
    /// `keepPosition`: words start where they were written (the text pen) instead of at the margin.
    /// `ai`: read with Claude first (falls back to the device). `continueFrom`: where the text pen's
    /// previous words ended; writing that goes on along the same line follows them with one space.
    static func convert(strokes: [Stroke], paper: PaperStyle, pageSize: CGSize, flowerLevel: Int,
                        keepPosition: Bool = false, ai: HandwritingAI.Access? = nil,
                        continueFrom: TextEnd? = nil) async -> ConversionResult? {
        let source = strokes.filter { $0.brush != .highlighter && !$0.points.isEmpty }
        guard !source.isEmpty else { return nil }
        var lines: [OCRLine] = []
        var members: [[Stroke]] = []

        if let ai {
            let groups = HandwritingAI.groups(source)
            if let texts = await HandwritingAI.read(groups, access: ai) {
                for (group, text) in zip(groups, texts) where !text.isEmpty {
                    let words = text.split(separator: " ").map { OCRWord(text: String($0), box: group.box) }
                    lines.append(OCRLine(text: text, box: group.box, words: words))
                    members.append(group.strokes)
                }
                // Claude saw only drawings or scribbles: the ink stays as it is.
                if lines.isEmpty { return nil }
            }
        }

        if lines.isEmpty {
            guard let raster = InkRaster.render(source) else { return nil }
            var raw = await PageOCR.lines(in: raster)
            if raw.isEmpty, let thick = InkRaster.render(source, lineScale: 1.7) {
                // Thin or faint writing: a second look with heavier lines.
                raw = await PageOCR.lines(in: thick)
            }
            // Real Turkish and English words decide between Vision's readings and bring back ş, ğ, ı…
            let found = raw
            lines = await MainActor.run { Spelling.polish(found) }.filter {
                !$0.text.trimmingCharacters(in: .whitespaces).isEmpty
            }
            guard !lines.isEmpty else { return nil }
            // Strokes of each line: their center lies in the line's box and they are not a big drawing.
            var taken = Set<Int>()
            for line in lines {
                let zone = line.box.insetBy(dx: -4, dy: -max(4, line.box.height * 0.25))
                let maxHeight = line.box.height * 2.4 + 10
                let mine = source.filter { s in
                    guard !taken.contains(s.id) else { return false }
                    let height = CGFloat(s.bounds.maxY - s.bounds.minY)
                    return height <= maxHeight && zone.contains(center(of: s))
                }
                for s in mine { taken.insert(s.id) }
                members.append(mine)
            }
        }
        let ruling = paper.ruling(pageSize: pageSize) ?? estimatedRuling(lines, pageSize: pageSize)

        let birth = Date().timeIntervalSinceReferenceDate
        var added: [Stroke] = []
        var removed = Set<Int>()
        var texts: [String] = []
        var nextLine = 0
        var end: TextEnd?
        let unit = ruling.capHeight / 10
        let space = CGFloat(StrokeFont.spaceAdvance) * unit
        for (i, line) in lines.enumerated() where !members[i].isEmpty {
            // The handwriting box includes some of the descenders; the baseline sits a bit above its bottom.
            let handBaseline = line.box.maxY - line.box.height * 0.15
            var k = max(ruling.index(nearBaseline: handBaseline), nextLine)
            var baseline = ruling.baseline(k)
            let indented = line.box.minX > ruling.left + ruling.spacing * 2
            var x = indented || keepPosition ? max(ruling.left, min(line.box.minX, ruling.right - 20)) : ruling.left
            // The text pen goes on along the line it wrote last: the next words follow the earlier
            // ones on the same baseline with exactly one space, however close or far the hand put them.
            if i == 0, keepPosition, let previous = continueFrom,
               abs(handBaseline - previous.baseline) < max(ruling.spacing * 0.6, ruling.capHeight * 1.2),
               line.box.minX > previous.x - ruling.capHeight * 2.5,
               line.box.minX < previous.x + ruling.capHeight * 9 {
                baseline = previous.baseline
                k = ruling.index(nearBaseline: previous.baseline)
                let joins = line.text.first.map { ".,;:!?)]}%".contains($0) } ?? false
                x = previous.x + (joins ? CGFloat(StrokeFont.tracking) * unit : space)
            }
            let words = line.words.isEmpty ? [OCRWord(text: line.text, box: line.box)] : line.words
            let fallback = dominantStyle(members[i], capHeight: ruling.capHeight)
            for word in words {
                let nearby = members[i].filter { CGRect(ink: $0.bounds).insetBy(dx: -2, dy: -2).intersects(word.box) }
                let style = nearby.isEmpty ? fallback : dominantStyle(nearby, capHeight: ruling.capHeight)
                let tracking = letterTracking(style.width, unit: unit)
                let width = CGFloat(StrokeFont.width(word.text, tracking: tracking)) * unit
                if x + width > ruling.right && x > ruling.left + 1 {
                    k += 1
                    baseline += ruling.spacing
                    x = ruling.left
                }
                let origin = SIMD2<Float>(Float(x), Float(baseline))
                let paths = StrokeFont.paths(word.text, origin: origin, capHeight: Float(ruling.capHeight), tracking: tracking)
                added += StrokeText.strokes(paths, style: style, flowerLevel: flowerLevel, birth: birth)
                end = TextEnd(baseline: baseline, x: x + width)
                x += width + space
            }
            nextLine = k + 1
            for s in members[i] { removed.insert(s.id) }
            texts.append(line.text)
        }
        guard !added.isEmpty else { return nil }
        return ConversionResult(removed: removed, added: added, lineCount: texts.count, text: texts.joined(separator: "\n"), end: end)
    }

    /// Typed text placed at `point`: on the next writing line when the page has them.
    static func typed(_ text: String, at point: CGPoint, paper: PaperStyle, pageSize: CGSize, style: StrokeText.Style,
                      flowerLevel: Int) -> [Stroke] {
        let lines = typedLayout(at: point, paper: paper, pageSize: pageSize)
        let cap = lines.cap
        let unit = cap / 10
        let left = lines.left
        let right = lines.right
        let spacing = lines.spacing
        var baseline = lines.baseline
        let birth = Date().timeIntervalSinceReferenceDate
        var out: [Stroke] = []
        let thin = StrokeText.Style(brush: style.brush, color: style.color, width: textWidth(style.width, brush: style.brush, capHeight: cap))
        let tracking = letterTracking(thin.width, unit: unit)
        for paragraph in text.components(separatedBy: .newlines) {
            var x = left
            for word in paragraph.split(separator: " ", omittingEmptySubsequences: false) {
                let w = String(word)
                let width = CGFloat(StrokeFont.width(w, tracking: tracking)) * unit
                if x + width > right && x > left + 1 {
                    baseline += spacing
                    x = left
                }
                if !w.isEmpty {
                    let paths = StrokeFont.paths(w, origin: SIMD2<Float>(Float(x), Float(baseline)), capHeight: Float(cap), tracking: tracking)
                    out += StrokeText.strokes(paths, style: thin, flowerLevel: flowerLevel, birth: birth)
                }
                x += width + CGFloat(StrokeFont.spaceAdvance) * unit
            }
            baseline += spacing
        }
        return out
    }

    /// Where typed text goes on a page (page-local): its left and right edges, the first baseline,
    /// the letter height and the line spacing, on the template's lines when it has them.
    struct TypedLayout {
        var left: CGFloat
        var right: CGFloat
        var baseline: CGFloat
        var cap: CGFloat
        var spacing: CGFloat
    }

    static func typedLayout(at point: CGPoint, paper: PaperStyle, pageSize: CGSize) -> TypedLayout {
        let ruling = paper.ruling(pageSize: pageSize)
        let cap = ruling?.capHeight ?? 15
        let left = ruling.map { max($0.left, min(point.x, $0.right - 40)) } ?? point.x
        let right = ruling?.right ?? (pageSize.width - 24)
        let spacing = ruling?.spacing ?? cap * 1.8
        let baseline: CGFloat
        if let r = ruling {
            baseline = r.baseline(r.index(atOrBelow: point.y + cap * 0.3))
        } else {
            baseline = point.y + cap
        }
        return TypedLayout(left: left, right: right, baseline: baseline, cap: cap, spacing: spacing)
    }

    /// Letter spacing in font units: the font's own, plus room for the line width of thick inks.
    static func letterTracking(_ lineWidth: Float, unit: CGFloat) -> Float {
        StrokeFont.tracking + lineWidth / Float(max(unit, 0.1)) * 0.6
    }

    /// Thick 3D inks keep their look but get a line weight letters can carry.
    static func textWidth(_ width: Float, brush: Brush, capHeight: CGFloat) -> Float {
        let cap = Float(capHeight)
        let limit = brush.castsShadow ? cap * 0.2 : cap * 0.13
        return max(0.9, min(width, limit))
    }

    private static func dominantStyle(_ strokes: [Stroke], capHeight: CGFloat) -> StrokeText.Style {
        var weights: [String: (style: StrokeText.Style, weight: Float, widthSum: Float)] = [:]
        for s in strokes {
            let key = "\(s.brush.rawValue)-\(s.color.r)-\(s.color.g)-\(s.color.b)-\(s.color.a)"
            let length = Float(max(s.points.count, 1))
            let base = StrokeText.Style(brush: s.brush, color: s.color, width: s.width)
            let current = weights[key] ?? (style: base, weight: 0, widthSum: 0)
            weights[key] = (style: base, weight: current.weight + length, widthSum: current.widthSum + s.width * length)
        }
        guard let best = weights.values.max(by: { $0.weight < $1.weight }) else {
            return StrokeText.Style(brush: .pen, color: InkColor(hex: 0x1C1C1E), width: 2)
        }
        let averageWidth = best.widthSum / max(best.weight, 1)
        return StrokeText.Style(brush: best.style.brush, color: best.style.color,
                                width: textWidth(averageWidth, brush: best.style.brush, capHeight: capHeight))
    }

    /// For templates without ruled lines: lines as far apart as the writing suggests.
    private static func estimatedRuling(_ lines: [OCRLine], pageSize: CGSize) -> Ruling {
        let heights = lines.map(\.box.height).sorted()
        let median = heights[heights.count / 2]
        let spacing = min(max(median * 1.5, 22), 60)
        let first = lines[0].box.maxY - lines[0].box.height * 0.15
        let left = max(16, lines.map(\.box.minX).min() ?? 40)
        return Ruling(top: first, spacing: spacing, left: left, right: pageSize.width - 30,
                      bottom: pageSize.height - 10, capHeight: spacing * 0.55)
    }

    private static func center(of s: Stroke) -> CGPoint {
        CGPoint(x: CGFloat(s.bounds.minX + s.bounds.maxX) / 2, y: CGFloat(s.bounds.minY + s.bounds.maxY) / 2)
    }
}

extension CGRect {
    init(ink r: InkRect) {
        self.init(x: CGFloat(r.minX), y: CGFloat(r.minY), width: CGFloat(r.maxX - r.minX), height: CGFloat(r.maxY - r.minY))
    }
}
