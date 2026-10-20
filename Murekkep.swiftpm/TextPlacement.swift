import CoreGraphics

/// Where the typed words of a converted line go (twin of tests/ports/placement.py).
///
/// The words start on their line where the hand started, unless ink on that line begins left of there
/// and ends at most 3 capital heights before it: then the hand meant to go on, and the words follow it
/// after one space (punctuation: a hairline). A word that would overlap ink moves past it; past the
/// right margin it wraps to the next line's left margin and is checked again. Words never go above the
/// line they were written on.
enum TextPlacement {
    static let joinReach: CGFloat = 3
    static let bandUp: CGFloat = 1.25
    static let bandDown: CGFloat = 0.35

    /// The page's ink that typed words keep clear of: not long flat lines (underlines, rules) and not
    /// drawings taller than two lines (a frame around the writing).
    static func obstacles(_ rects: [CGRect], ruling: Ruling) -> [CGRect] {
        rects.filter { o in
            !(o.width > 4 * ruling.capHeight && o.height < 0.4 * ruling.capHeight) && o.height <= 2 * ruling.spacing
        }
    }

    private static func onLine(_ o: CGRect, _ k: Int, _ ruling: Ruling) -> Bool {
        let b = ruling.baseline(k)
        return min(o.maxY, b + bandDown * ruling.capHeight) > max(o.minY, b - bandUp * ruling.capHeight)
    }

    static func place(widths: [CGFloat], startX: CGFloat, startLine: Int, ruling: Ruling, space: CGFloat,
                      joinGap: CGFloat, obstacles: [CGRect]) -> [(x: CGFloat, line: Int)] {
        var k = startLine
        var x = min(max(startX, ruling.left), ruling.right - 20)
        let before = obstacles.filter {
            onLine($0, k, ruling) && $0.minX < startX && $0.maxX >= startX - joinReach * ruling.capHeight
        }
        if let end = before.map(\.maxX).max() {
            x = end + joinGap
        }
        var out: [(x: CGFloat, line: Int)] = []
        for w in widths {
            for _ in 0..<64 {
                if x + w > ruling.right && x > ruling.left + 1 {
                    k += 1
                    x = ruling.left
                }
                let hits = obstacles.filter { onLine($0, k, ruling) && min($0.maxX, x + w) > max($0.minX, x) }
                guard let end = hits.map(\.maxX).max() else { break }
                x = end + space
            }
            out.append((x: x, line: k))
            x += w + space
        }
        return out
    }
}
