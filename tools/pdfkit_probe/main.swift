import Foundation
import PDFKit

// A PDF page's text as Apple's PDFKit gives it (the iPad reads pages the same way), written to a file
// and printed with every character outside plain ASCII spelled out, then the page's questions as the
// app splits them and the math engine's answers. Runs on a Mac (Codemagic's "pdfkit-probe" workflow).
//     probe <page.pdf> <out.txt>

let args = CommandLine.arguments
guard args.count >= 3, let doc = PDFDocument(url: URL(fileURLWithPath: args[1])), let page = doc.page(at: 0) else {
    print("usage: probe <page.pdf> <out.txt>")
    exit(1)
}
let text = page.string ?? ""
try text.write(toFile: args[2], atomically: true, encoding: .utf8)

/// The text with tabs, unusual spaces and every non-ASCII character made visible.
func visible(_ s: String) -> String {
    var out = ""
    for u in s.unicodeScalars {
        switch u.value {
        case 0x0A: out += "⏎\n"
        case 0x09: out += "⇥"
        case 0x20...0x7E: out.unicodeScalars.append(u)
        default: out += "⟨U+\(String(u.value, radix: 16, uppercase: true)) \(Character(u))⟩"
        }
    }
    return out
}

print("===== PDFKit page.string (\(text.count) characters) =====")
print(visible(text))
// Every character's own tight box in page points (origin bottom-left), one per line: the UTF-16
// code, then x, y, width, height to a tenth of a point. characterBounds(at:) is numbered in an order
// of its own, so each character of page.string takes the unused tight box whose centre lies in its
// one-character selection (exact across, a whole line high), nearest its middle.
let units = text as NSString
var tight: [CGRect] = []
for j in 0..<page.numberOfCharacters {
    let r = page.characterBounds(at: j)
    if r.width > 0, r.height > 0 { tight.append(r) }
}
var used = [Bool](repeating: false, count: tight.count)
var glyphs = ""
var found = 0
var missing = 0
for i in 0..<units.length {
    let unit = units.character(at: i)
    guard unit != 0x20, unit != 0x0A, let sel = page.selection(for: NSRange(location: i, length: 1)) else { continue }
    let s = sel.bounds(for: page).insetBy(dx: -0.5, dy: -0.5)
    var best = -1
    var bestDistance = Double.infinity
    for (j, r) in tight.enumerated() where !used[j] && s.contains(CGPoint(x: r.midX, y: r.midY)) {
        let d = abs(r.midX - s.midX)
        if d < bestDistance { best = j; bestDistance = d }
    }
    guard best >= 0 else { missing += 1; continue }
    used[best] = true
    found += 1
    let r = tight[best]
    glyphs += String(format: "G %@ %.1f %.1f %.1f %.1f\n", String(unit, radix: 16, uppercase: true), r.minX, r.minY, r.width, r.height)
}
print("===== Glyphs: \(found) characters boxed, \(missing) without a box, \(used.filter { !$0 }.count) of \(tight.count) boxes unused =====")
print(glyphs, terminator: "")
try glyphs.write(toFile: args[2] + ".glyphs", atomically: true, encoding: .utf8)
// The same page rebuilt from the glyph boxes (PageLayout), and the engine's answers on that text.
var layoutGlyphs: [PageLayout.Glyph] = []
for line in glyphs.split(separator: "\n") {
    let f = line.split(separator: " ")
    guard f.count == 6, let code = UInt32(f[1], radix: 16), let scalar = Unicode.Scalar(code),
          let x = Double(f[2]), let y = Double(f[3]), let w = Double(f[4]), let h = Double(f[5]) else { continue }
    layoutGlyphs.append(PageLayout.Glyph(char: Character(scalar), x: x, y: y, w: w, h: h))
}
let layout = PageLayout.text(layoutGlyphs) ?? ""
print("===== Page rebuilt from the glyph boxes =====")
print(layout)
print("===== Questions on the rebuilt page and the engine's answers =====")
for q in QuestionSplitter.split(MathText.pageForSolving(layout)) {
    print("(\(q.number)) \(ExactMath.solve(q.stem)?.answer ?? "-")    <- \(q.stem.replacingOccurrences(of: "\n", with: "⏎"))")
}
print("===== Questions and the engine's answers =====")
for q in QuestionSplitter.split(MathText.pageForSolving(text)) {
    let answer = ExactMath.solve(q.stem)?.answer ?? "-"
    print("(\(q.number)) \(answer)    <- \(visible(q.stem).replacingOccurrences(of: "⏎\n", with: "⏎"))")
}
