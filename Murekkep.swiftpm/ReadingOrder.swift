import Foundation

/// The lines of a scanned page in reading order, from the boxes text recognition found (pixels,
/// top-left origin) (twin of tests/ports/reading_order.py). Vision returns a two-column textbook page
/// row by row across both columns; read that way, the grammar box on the left lands in the middle of
/// the exercise on the right.
///
/// Columns are found where few boxes cross a vertical band that has at least a fifth of the boxes on
/// each side; boxes that cross it (a title, a full-width letter) break the page into sections, and each
/// section is read column by column. Boxes of one row inside a column are joined left to right; a
/// blank (a printed answer line) between them, or between words, becomes "___".
enum ReadingOrder {
    struct Piece {
        var text: String
        var box: CGRect
        var words: [(text: String, box: CGRect)] = []
    }

    /// Pieces or words farther apart than this many line heights have a blank between them.
    private static let gap: CGFloat = 1.2
    /// A column gap is at least this many line heights wide.
    private static let gutterMin: CGFloat = 0.6
    /// Each side of a column gap holds at least this share of the boxes.
    private static let sideShare: CGFloat = 0.2
    /// At most this share of the boxes cross a column gap.
    private static let crossShare: CGFloat = 0.2
    /// A column's typical box is at least this many line heights wide.
    private static let columnWidth: CGFloat = 4
    /// Boxes of one row overlap vertically by half the smaller height.
    private static let rowOverlap: CGFloat = 0.5
    /// Up to four columns.
    private static let maxDepth = 2

    private static let underscores = try! NSRegularExpression(pattern: #"_+"#)
    private static let leaders = try! NSRegularExpression(pattern: #"\.{5,}|…{2,}"#)
    private static let spaces = try! NSRegularExpression(pattern: #"\s+"#)
    private static let repeated = try! NSRegularExpression(pattern: #"___(?: ___)+"#)

    private static func replace(_ rx: NSRegularExpression, in s: String, with t: String) -> String {
        rx.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length), withTemplate: t)
    }

    /// Printed blanks (underscores, dot leaders) as one "___".
    static func normalizeBlanks(_ s: String) -> String {
        var t = replace(underscores, in: s, with: " ___ ")
        t = replace(leaders, in: t, with: " ___ ")
        t = replace(spaces, in: t, with: " ").trimmingCharacters(in: .whitespaces)
        return replace(repeated, in: t, with: "___")
    }

    /// Python's statistics.median.
    private static func median(_ values: [CGFloat]) -> CGFloat {
        let v = values.sorted()
        guard !v.isEmpty else { return 0 }
        let m = v.count / 2
        return v.count % 2 == 1 ? v[m] : (v[m - 1] + v[m]) / 2
    }

    private static func crosses(_ p: Piece, _ g: (CGFloat, CGFloat)) -> Bool {
        min(p.box.maxX, g.1) - max(p.box.minX, g.0) >= (g.1 - g.0) / 2
    }

    /// The widest band few boxes cross, with enough boxes on both sides.
    private static func gutter(_ pieces: [Piece], _ h: CGFloat) -> (CGFloat, CGFloat)? {
        let n = CGFloat(pieces.count)
        guard pieces.count >= 6 else { return nil }
        let lo = pieces.map(\.box.minX).min()!
        let hi = pieces.map(\.box.maxX).max()!
        let step = max(h / 8, 1)
        var xs: [CGFloat] = []
        var x = lo + step
        while x < hi {
            xs.append(x)
            x += step
        }
        var cross: [Int] = []
        var inner: [Bool] = []
        for x in xs {
            cross.append(pieces.filter { $0.box.minX < x && x < $0.box.maxX }.count)
            let left = CGFloat(pieces.filter { $0.box.maxX <= x }.count)
            let right = CGFloat(pieces.filter { $0.box.minX >= x }.count)
            inner.append(left >= sideShare * n && right >= sideShare * n)
        }
        let candidates = xs.indices.filter { inner[$0] }.map { cross[$0] }
        guard let least = candidates.min(), CGFloat(least) <= crossShare * n else { return nil }
        let limit = least + max(1, Int((0.03 * n).rounded(.toNearestOrEven)))
        var best: (Int, Int)?
        var start: Int?
        for i in 0...xs.count {
            let ok = i < xs.count && inner[i] && cross[i] <= limit
            if ok && start == nil {
                start = i
            } else if !ok, let s = start {
                if best == nil || i - s > best!.1 - best!.0 { best = (s, i) }
                start = nil
            }
        }
        guard let run = best else { return nil }
        let g = (xs[run.0], xs[run.1 - 1])
        guard g.1 - g.0 >= gutterMin * h else { return nil }
        let mid = (g.0 + g.1) / 2
        let rest = pieces.filter { !crosses($0, g) }
        for side in [rest.filter { $0.box.midX < mid }, rest.filter { $0.box.midX >= mid }] {
            if side.isEmpty || median(side.map(\.box.width)) < columnWidth * h { return nil }
        }
        return g
    }

    private static func gutters(_ pieces: [Piece], _ h: CGFloat, depth: Int = 0) -> [(CGFloat, CGFloat)] {
        guard let g = gutter(pieces, h) else { return [] }
        if depth + 1 >= maxDepth { return [g] }
        let mid = (g.0 + g.1) / 2
        let rest = pieces.filter { !crosses($0, g) }
        return gutters(rest.filter { $0.box.midX < mid }, h, depth: depth + 1) + [g]
            + gutters(rest.filter { $0.box.midX >= mid }, h, depth: depth + 1)
    }

    /// Pieces of one row together, rows top to bottom, each row left to right.
    private static func rows(_ pieces: [Piece]) -> [[Piece]] {
        let sorted = pieces.sorted { a, b in
            if a.box.midY != b.box.midY { return a.box.midY < b.box.midY }
            if a.box.minX != b.box.minX { return a.box.minX < b.box.minX }
            return a.text < b.text
        }
        var rows: [[Piece]] = []
        for p in sorted {
            var placed = false
            for k in stride(from: rows.count - 1, through: max(rows.count - 3, 0), by: -1) {
                let anchor = rows[k][0]
                let overlap = min(anchor.box.maxY, p.box.maxY) - max(anchor.box.minY, p.box.minY)
                if overlap < rowOverlap * min(anchor.box.height, p.box.height) { continue }
                let clash = rows[k].contains { q in
                    min(q.box.maxX, p.box.maxX) - max(q.box.minX, p.box.minX) > 0.5 * min(q.box.width, p.box.width)
                }
                if clash { continue }
                rows[k].append(p)
                placed = true
                break
            }
            if !placed { rows.append([p]) }
        }
        let ordered = rows.map { r in
            r.sorted { a, b in a.box.minX != b.box.minX ? a.box.minX < b.box.minX : a.text < b.text }
        }
        func centre(_ r: [Piece]) -> CGFloat { r.reduce(0) { $0 + $1.box.midY } / CGFloat(r.count) }
        return ordered.sorted { a, b in
            let ca = centre(a)
            let cb = centre(b)
            return ca != cb ? ca < cb : a[0].box.minX < b[0].box.minX
        }
    }

    private static func text(_ p: Piece) -> String {
        guard p.words.count >= 2 else { return p.text.trimmingCharacters(in: .whitespaces) }
        var out = p.words[0].text
        for (a, b) in zip(p.words, p.words.dropFirst()) {
            out += (b.box.minX - a.box.maxX > gap * p.box.height ? " ___ " : " ") + b.text
        }
        return out
    }

    private static func join(_ row: [Piece], _ h: CGFloat) -> String {
        var out = ""
        var right: CGFloat?
        for p in row {
            if let r = right {
                out += p.box.minX - r > gap * h ? " ___ " : " "
            }
            out += text(p)
            right = p.box.maxX
        }
        return normalizeBlanks(out)
    }

    static func lines(_ pieces: [Piece]) -> [String] {
        let pieces = pieces.filter {
            !$0.text.trimmingCharacters(in: .whitespaces).isEmpty && $0.box.width > 0 && $0.box.height > 0
        }
        guard !pieces.isEmpty else { return [] }
        let h = median(pieces.map(\.box.height))
        let gs = gutters(pieces, h)
        let spanning = pieces.filter { p in gs.contains { crosses(p, $0) } }
        let columns = pieces.filter { p in !gs.contains { crosses(p, $0) } }
        let spanRows = rows(spanning)
        let edges = spanRows.map { r in r.reduce(0) { $0 + $1.box.midY } / CGFloat(r.count) }
        let mids = gs.map { ($0.0 + $0.1) / 2 }
        var out: [String] = []
        for k in 0...spanRows.count {
            let section = columns.filter { p in edges.filter { $0 < p.box.midY }.count == k }
            for c in 0...gs.count {
                let mine = section.filter { p in mids.filter { p.box.midX >= $0 }.count == c }
                out += rows(mine).map { join($0, h) }
            }
            if k < spanRows.count {
                out.append(join(spanRows[k], h))
            }
        }
        return out.filter { !$0.isEmpty }
    }
}
