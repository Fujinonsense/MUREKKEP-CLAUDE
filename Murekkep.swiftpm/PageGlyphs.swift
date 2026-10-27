import Foundation
import PDFKit

/// A PDF page's characters with their own tight boxes, for PageLayout. PDFKit numbers its glyph boxes
/// (characterBounds) in an order of its own, so each character of page.string takes the box whose
/// centre lies in that character's one-character selection (exact across, a whole line high) and
/// whose sides are nearest the selection's: the spaces PDFKit put between words first, since their
/// boxes fill the same gaps a neighbour's selection reaches into. Checked on CALCULUS p.14 by
/// tools/pdfkit_probe on a Mac: every character finds its box.
enum PageGlyphs {
    static func read(_ page: PDFPage) -> [PageLayout.Glyph] {
        let text = (page.string ?? "") as NSString
        var boxes: [CGRect] = []
        for j in 0..<page.numberOfCharacters {
            let r = page.characterBounds(at: j)
            if r.width > 0, r.height > 0 { boxes.append(r) }
        }
        var used = [Bool](repeating: false, count: boxes.count)
        var out: [PageLayout.Glyph] = []
        for spaces in [true, false] {
            for i in 0..<text.length {
                let unit = text.character(at: i)
                guard unit != 0x0A, (unit == 0x20) == spaces,
                      let selection = page.selection(for: NSRange(location: i, length: 1)) else { continue }
                let s = selection.bounds(for: page).insetBy(dx: -0.5, dy: -0.5)
                var best = -1
                var cost = Double.infinity
                for (j, r) in boxes.enumerated() where !used[j] && s.contains(CGPoint(x: r.midX, y: r.midY)) {
                    let c = Double(abs(r.minX - s.minX) + abs(r.maxX - s.maxX))
                    if c < cost { best = j; cost = c }
                }
                guard best >= 0, !spaces || cost < 1.5 else { continue }
                used[best] = true
                guard !spaces, let scalar = Unicode.Scalar(unit) else { continue }
                let r = boxes[best]
                out.append(PageLayout.Glyph(char: Character(scalar), x: Double(r.minX), y: Double(r.minY),
                                            w: Double(r.width), h: Double(r.height)))
            }
        }
        return out
    }

    /// The page rebuilt from its glyphs (fractions, powers and moved pieces back in place); nil when
    /// the page has too little text.
    static func text(_ page: PDFPage) -> String? {
        PageLayout.text(read(page))
    }
}
