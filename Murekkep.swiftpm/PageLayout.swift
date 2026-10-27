import Foundation

/// A page of math read from where its glyphs stand rather than from PDFKit's reading order, which
/// scatters a typeset fraction ("3x⏎1⏎x2 + 2 ≥⏎x−1"), drops a power's height ("x2") and moves pieces
/// to the end of the page. Each glyph's own box (characterBounds, see PageGlyphs) gives it back:
/// a small digit raised beside the glyph before it is a power ("x²"), a piece standing above another
/// in a gap of a line is a fraction ("(3x)/(x² + 2)"), and every piece lands on its own line again.
/// Pure geometry, so tools/mathcheck runs it on the boxes PDFKit gave for CALCULUS p.14.
enum PageLayout {
    /// One glyph and its box in page points, origin bottom-left (y grows upwards).
    struct Glyph: Equatable {
        var char: Character
        var x: Double
        var y: Double
        var w: Double
        var h: Double

        var maxX: Double { x + w }
        var maxY: Double { y + h }
        var midY: Double { y + h / 2 }
        /// Where the glyph stands in its row: its middle, but a full stop's or a comma's (which sit on
        /// or under the baseline) a little above its top, where a small letter's middle is.
        var rowY: Double { ".,".contains(char) && h < 4 ? maxY + 1.2 : midY }
    }

    /// A run of glyphs on one row with no wide gap inside, as text.
    private struct Piece {
        var glyphs: [Glyph]
        var minX: Double { glyphs.first!.x }
        var maxX: Double { glyphs.map(\.maxX).max()! }
        var text: String { PageLayout.spaced(glyphs) }
    }

    private struct Row {
        var midY: Double
        var pieces: [Piece]
    }

    private static let superscripts: [Character: Character] = [
        "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹", "0": "⁰",
    ]

    /// The page as lines of text, top to bottom; nil when there is too little to read.
    static func text(_ glyphs: [Glyph]) -> String? {
        let marks = glyphs.filter { !$0.char.isWhitespace && $0.w > 0 && $0.h > 0 }
        guard marks.count >= 20 else { return nil }
        let rows = self.rows(raised(marks))
        var used = Set<Int>()
        var fractions: [Int: [(x: Double, text: String)]] = [:]
        // A piece of math just above and one just below a row's gap, overlapping each other: a fraction
        // of that row. Words are never a numerator, so two lines of text are never read as one.
        for (m, main) in rows.enumerated() {
            guard let above = rows.indices.last(where: { $0 < m && rows[$0].midY - main.midY < 9.5 && rows[$0].midY - main.midY > 3.5 }),
                  let below = rows.indices.first(where: { $0 > m && main.midY - rows[$0].midY < 9.5 && main.midY - rows[$0].midY > 3.5 })
            else { continue }
            for (i, top) in rows[above].pieces.enumerated() where !hasWord(top.text) {
                for (j, bottom) in rows[below].pieces.enumerated() where !hasWord(bottom.text) {
                    let overlap = min(top.maxX, bottom.maxX) - max(top.minX, bottom.minX)
                    guard overlap > 0.4 * min(top.maxX - top.minX, bottom.maxX - bottom.minX),
                          !main.pieces.contains(where: { $0.minX < max(top.maxX, bottom.maxX) - 1 && $0.maxX > min(top.minX, bottom.minX) + 1 })
                    else { continue }
                    let key = above * 10_000 + i, keyBelow = below * 10_000 + j
                    guard !used.contains(key), !used.contains(keyBelow) else { continue }
                    used.insert(key)
                    used.insert(keyBelow)
                    fractions[m, default: []].append((x: min(top.minX, bottom.minX), text: "(\(top.text))/(\(bottom.text))"))
                }
            }
        }
        var lines: [String] = []
        for (r, row) in rows.enumerated() {
            var parts: [(x: Double, text: String)] = []
            for (i, piece) in row.pieces.enumerated() where !used.contains(r * 10_000 + i) {
                parts.append((x: piece.minX, text: piece.text))
            }
            parts += fractions[r] ?? []
            guard !parts.isEmpty else { continue }
            parts.sort { $0.x < $1.x }
            var line = ""
            for part in parts {
                if line.isEmpty || part.text.first.map({ ".,;:)".contains($0) }) == true {
                    line += part.text
                } else {
                    line += " " + part.text
                }
            }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }

    /// A run of four letters: a word, which no fraction holds.
    private static func hasWord(_ s: String) -> Bool {
        var run = 0
        for c in s {
            run = c.isLetter ? run + 1 : 0
            if run >= 4 { return true }
        }
        return false
    }

    /// Small digits raised beside the glyph before them turned into powers, standing on that glyph's
    /// row. Raised means standing on the base's upper half, so the 4 of "|4x" (a bar reaches below
    /// the line) stays a 4.
    private static func raised(_ glyphs: [Glyph]) -> [Glyph] {
        var out = glyphs
        for (i, g) in glyphs.enumerated() {
            guard let power = superscripts[g.char] else { continue }
            let base = glyphs.firstIndex { b in
                b.maxX >= g.x - 1.2 && b.maxX <= g.x + 0.8 && b.char != g.char && !b.char.isWhitespace
                    && g.y >= b.midY - 0.5 && g.y < b.maxY + 1 && (b.char.isLetter || ")|".contains(b.char))
            }
            guard let b = base else { continue }
            out[i].char = power
            out[i].y = glyphs[b].y
            out[i].h = glyphs[b].h
        }
        return out
    }

    /// Glyphs grouped by height on the page (rows top to bottom), each row cut into pieces at wide gaps.
    private static func rows(_ glyphs: [Glyph]) -> [Row] {
        let sorted = glyphs.sorted { $0.rowY > $1.rowY }
        var groups: [[Glyph]] = []
        for g in sorted {
            if let last = groups.last, let top = last.first, top.rowY - g.rowY <= 3.0, last.last!.rowY - g.rowY <= 1.6 {
                groups[groups.count - 1].append(g)
            } else {
                groups.append([g])
            }
        }
        return groups.map { group in
            let byX = group.sorted { $0.x < $1.x }
            var pieces: [Piece] = []
            for g in byX {
                if let last = pieces.last, g.x - last.maxX <= 6 {
                    pieces[pieces.count - 1].glyphs.append(g)
                } else {
                    pieces.append(Piece(glyphs: [g]))
                }
            }
            return Row(midY: group.map(\.rowY).reduce(0, +) / Double(group.count), pieces: pieces)
        }
    }

    /// A run's glyphs with a space wherever the ink leaves a word's gap.
    private static func spaced(_ glyphs: [Glyph]) -> String {
        var s = ""
        var lastMax: Double?
        for g in glyphs {
            if let m = lastMax, g.x - m > 2.0 { s += " " }
            s.append(g.char)
            lastMax = max(lastMax ?? g.maxX, g.maxX)
        }
        return s
    }
}
