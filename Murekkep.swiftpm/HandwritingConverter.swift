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
    /// `obstacles`: bounds of the page's other ink, which the typed words keep clear of.
    static func convert(strokes: [Stroke], paper: PaperStyle, pageSize: CGSize, flowerLevel: Int,
                        keepPosition: Bool = false, ai: HandwritingAI.Access? = nil,
                        continueFrom: TextEnd? = nil, obstacles: [CGRect] = [],
                        textScale: Double = 1) async -> ConversionResult? {
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

        if lines.isEmpty, let model = HandwritingModel.shared {
            (lines, members) = await readWithModel(source, model: model)
            guard !lines.isEmpty else { return nil }
        }

        if lines.isEmpty {
            guard let raster = InkRaster.render(source) else { return nil }
            var raw = await PageOCR.lines(in: raster)
            if raw.isEmpty, let thick = InkRaster.render(source, lineScale: 1.7) {
                // Thin or faint writing: a second look with heavier lines.
                raw = await PageOCR.lines(in: thick)
            }
            // Real Turkish and English words decide between Vision's readings and bring back ş, ğ, ı…
            // One line per trip to the main thread: Pencil taps and touches are handled in between.
            var polished: [OCRLine] = []
            for line in raw {
                polished += await MainActor.run { Spelling.polish([line]) }
            }
            lines = polished.filter {
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
        let printed = paper.ruling(pageSize: pageSize)
        var ruling = printed ?? estimatedRuling(lines, pageSize: pageSize)
        ruling.capHeight = capHeight(ruling: ruling, scale: textScale)
        // On a page without printed lines the text pen keeps to the line its last words sat on.
        if printed == nil, keepPosition, let previous = continueFrom, let first = lines.first {
            let handBaseline = first.box.maxY - first.box.height * 0.15
            if abs(handBaseline - previous.baseline) < max(ruling.spacing * 0.6, ruling.capHeight * 1.2) {
                ruling.top = previous.baseline.truncatingRemainder(dividingBy: ruling.spacing)
            }
        }

        let birth = Date().timeIntervalSinceReferenceDate
        var added: [Stroke] = []
        var removed = Set<Int>()
        var texts: [String] = []
        var nextLine = 0
        var end: TextEnd?
        let unit = ruling.capHeight / 10
        let space = CGFloat(StrokeFont.spaceAdvance) * unit
        let hairline = CGFloat(StrokeFont.tracking) * unit
        var blocking = TextPlacement.obstacles(obstacles, ruling: ruling)
        if keepPosition, let previous = continueFrom {
            // Where the text pen's last words ended, so the next ones follow them.
            blocking.append(CGRect(x: previous.x - 1, y: previous.baseline - ruling.capHeight, width: 1, height: ruling.capHeight))
        }
        for (i, line) in lines.enumerated() where !members[i].isEmpty {
            // The handwriting box includes some of the descenders; the baseline sits a bit above its bottom.
            let handBaseline = line.box.maxY - line.box.height * 0.15
            let k = max(ruling.index(nearBaseline: handBaseline), nextLine)
            let indented = line.box.minX > ruling.left + ruling.spacing * 2
            let startX = indented || keepPosition ? line.box.minX : ruling.left
            let words = line.words.isEmpty ? [OCRWord(text: line.text, box: line.box)] : line.words
            let fallback = dominantStyle(members[i], capHeight: ruling.capHeight)
            var styles: [StrokeText.Style] = []
            var trackings: [Float] = []
            var widths: [CGFloat] = []
            for word in words {
                let nearby = members[i].filter { CGRect(ink: $0.bounds).insetBy(dx: -2, dy: -2).intersects(word.box) }
                let style = nearby.isEmpty ? fallback : dominantStyle(nearby, capHeight: ruling.capHeight)
                let tracking = letterTracking(style.width, unit: unit)
                styles.append(style)
                trackings.append(tracking)
                widths.append(CGFloat(StrokeFont.width(word.text, tracking: tracking)) * unit)
            }
            let joins = line.text.first.map { ".,;:!?)]}%".contains($0) } ?? false
            let spots = TextPlacement.place(widths: widths, startX: startX, startLine: k, ruling: ruling, space: space,
                                            joinGap: joins ? hairline : space, obstacles: blocking)
            var lastLine = k
            for (j, word) in words.enumerated() {
                let baseline = ruling.baseline(spots[j].line)
                let x = spots[j].x
                let origin = SIMD2<Float>(Float(x), Float(baseline))
                let paths = StrokeFont.paths(word.text, origin: origin, capHeight: Float(ruling.capHeight), tracking: trackings[j])
                added += StrokeText.strokes(paths, style: styles[j], flowerLevel: flowerLevel, birth: birth)
                end = TextEnd(baseline: baseline, x: x + widths[j])
                // Later lines of this batch keep clear of the words just placed.
                blocking.append(CGRect(x: x, y: baseline - ruling.capHeight * 1.1, width: widths[j], height: ruling.capHeight * 1.3))
                lastLine = spots[j].line
            }
            nextLine = lastLine + 1
            for s in members[i] { removed.insert(s.id) }
            texts.append(line.text)
        }
        guard !added.isEmpty else { return nil }
        return ConversionResult(removed: removed, added: added, lineCount: texts.count, text: texts.joined(separator: "\n"), end: end)
    }

    /// The batch read line by line with Mürekkep's own model. Vision's readings of the same line
    /// compete, scored by the model, and the dictionary settles near-ties; exponents are read on
    /// their own and put back raised.
    private static func readWithModel(_ ink: [Stroke], model: HandwritingModel) async -> ([OCRLine], [[Stroke]]) {
        // A turned page (or a slanted hand) leaves the writing at an angle to the page; it is read
        // levelled (the line splitter and the model need level lines), and the boxes go back.
        let paths = ink.map { s in s.points.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) } }
        let degrees = InkDeskew.angle(paths)
        let pivot = InkDeskew.centre(paths)
        var original: [Int: Stroke] = [:]
        var source = ink
        if degrees != 0 {
            source = ink.map { s in
                let turned = s.withPoints(s.points.map { p in
                    let q = InkDeskew.level(CGPoint(x: CGFloat(p.x), y: CGFloat(p.y)), degrees: degrees, centre: pivot)
                    var r = p
                    r.x = Float(q.x)
                    r.y = Float(q.y)
                    return r
                })
                original[turned.id] = s
                return turned
            }
        }
        /// A levelled box placed back on the page, anchored where the writing starts (its lower left).
        func onPage(_ box: CGRect) -> CGRect {
            guard degrees != 0 else { return box }
            let start = InkDeskew.unlevel(CGPoint(x: box.minX, y: box.maxY), degrees: degrees, centre: pivot)
            return CGRect(x: start.x, y: start.y - box.height, width: box.width, height: box.height)
        }
        var vision: [OCRLine] = []
        if let raster = InkRaster.render(source) {
            vision = await PageOCR.lines(in: raster)
        }
        let tr = Locale(identifier: "tr_TR")
        var lines: [OCRLine] = []
        var members: [[Stroke]] = []
        for line in InkLine.lines(source) {
            let (base, raised) = InkLine.splitRaised(line)
            guard let image = InkLine.render(base) else { continue }
            let lp = model.logProbs(image)
            let beam = CTC.beam(lp, charset: model.charset)
            guard let first = beam.first else { continue }
            let box = inkBounds(line)
            var seen = Set(beam.map(\.text))
            var visionTexts: [String] = []
            for v in vision where verticalOverlap(v.box, box) >= 0.5 {
                for text in [v.text] + v.alternatives.map(\.text) where seen.insert(text).inserted {
                    visionTexts.append(text)
                }
            }
            // Vision drops Turkish letters (ş → s); the dictionary repair brings them back.
            let read = visionTexts
            let repaired = await MainActor.run { read.map { Spelling.repair($0) } }
            for text in repaired where seen.insert(text).inserted {
                visionTexts.append(text)
            }
            let candidates = beam.map(\.text) + visionTexts
            let known = await MainActor.run {
                Dictionary(candidates.map { ($0, Spelling.score($0.lowercased(with: tr))) }, uniquingKeysWith: { a, _ in a })
            }
            let isMath = PageOCR.mathScore(first.text) >= 2 || first.text.contains("=")
            var text = Reading.choose(model: beam,
                                      vision: visionTexts.map { (text: $0, score: CTC.score($0, lp, charset: model.charset)) },
                                      length: first.text.count, isMath: isMath, dictionary: known)
            var xs = characterPositions(text, lp: lp, image: image, charset: model.charset, box: box)
            var groups: [(text: String, x: CGFloat)] = []
            for group in raised {
                if let img = InkLine.render(group.strokes),
                   let best = CTC.beam(model.logProbs(img), charset: model.charset, width: 4).first {
                    groups.append((text: best.text.trimmingCharacters(in: .whitespaces), x: group.x))
                }
            }
            if !groups.isEmpty {
                text = Reading.insertSuperscripts(text, charX: xs, raised: groups)
                xs = characterPositions(text, lp: nil, image: image, charset: model.charset, box: box)
            }
            let placed = words(of: text, at: xs, box: box).map { OCRWord(text: $0.text, box: onPage($0.box)) }
            lines.append(OCRLine(text: text, box: onPage(box), words: placed))
            members.append(line.map { original[$0.id] ?? $0 })
        }
        return (lines, members)
    }

    private static func inkBounds(_ strokes: [Stroke]) -> CGRect {
        strokes.map { CGRect(ink: $0.bounds) }.reduce(CGRect.null) { $0.union($1) }
    }

    private static func verticalOverlap(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let overlap = min(a.maxY, b.maxY) - max(a.minY, b.minY)
        return max(0, overlap) / max(min(a.height, b.height), 1)
    }

    /// Page x of each character: where the model's best path writes it when that path spells the
    /// text, otherwise spread evenly over the line.
    private static func characterPositions(_ text: String, lp: [[Float]]?, image: InkLineImage,
                                           charset: [Character], box: CGRect) -> [CGFloat] {
        let chars = Array(text)
        if let lp {
            let frames = CTC.alignment(lp)
            let greedy = frames.map { t -> Character in
                let k = lp[t].indices.max { lp[t][$0] < lp[t][$1] } ?? 1
                return charset[max(k, 1) - 1]
            }
            if greedy == chars {
                return frames.map { (CGFloat($0 * 4 + 2) - image.origin.x) / image.scale }
            }
        }
        guard chars.count > 1 else { return chars.isEmpty ? [] : [box.midX] }
        return chars.indices.map { box.minX + box.width * (CGFloat($0) + 0.5) / CGFloat(chars.count) }
    }

    /// Word boxes from the characters' positions (for the style each typed word takes).
    private static func words(of text: String, at xs: [CGFloat], box: CGRect) -> [OCRWord] {
        let chars = Array(text)
        guard chars.count == xs.count, !chars.isEmpty else { return [OCRWord(text: text, box: box)] }
        let step = chars.count > 1 ? (xs[xs.count - 1] - xs[0]) / CGFloat(chars.count - 1) : box.width
        var out: [OCRWord] = []
        var start: Int?
        for i in 0...chars.count {
            let isSpace = i == chars.count || chars[i] == " "
            if !isSpace && start == nil { start = i }
            if isSpace, let s = start {
                let minX = xs[s] - step / 2
                let maxX = xs[i - 1] + step / 2
                out.append(OCRWord(text: String(chars[s..<i]), box: CGRect(x: minX, y: box.minY, width: max(maxX - minX, 1), height: box.height)))
                start = nil
            }
        }
        return out.isEmpty ? [OCRWord(text: text, box: box)] : out
    }

    /// Typed text placed at `point`: on the next writing line when the page has them.
    static func typed(_ text: String, at point: CGPoint, paper: PaperStyle, pageSize: CGSize, style: StrokeText.Style,
                      flowerLevel: Int, scale: Double = 1) -> [Stroke] {
        let lines = typedLayout(at: point, paper: paper, pageSize: pageSize, scale: scale)
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

    /// Capital height of typed text at the chosen size: never taller than 72 % of the space between
    /// ruled lines.
    static func capHeight(ruling: Ruling, scale: Double) -> CGFloat {
        min(ruling.capHeight * CGFloat(scale), ruling.spacing * 0.72)
    }

    static func typedLayout(at point: CGPoint, paper: PaperStyle, pageSize: CGSize, scale: Double = 1) -> TypedLayout {
        let ruling = paper.ruling(pageSize: pageSize)
        let cap = ruling.map { capHeight(ruling: $0, scale: scale) } ?? 15 * CGFloat(scale)
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
