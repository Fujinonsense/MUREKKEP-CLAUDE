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
// Every glyph's own tight box in page points (origin bottom-left), one per line: the UTF-16 code of
// the character, then x, y, width, height to a tenth of a point. characterBounds(at:) and
// characterIndex(at:) are numbered in an order of their own, so the character is read from a
// selection of the box's middle, which PDFKit fills from the same text as page.string.
let units = text as NSString
var glyphs = ""
var count = 0
var ambiguous = 0
for j in 0..<page.numberOfCharacters {
    let r = page.characterBounds(at: j)
    guard r.width > 0, r.height > 0 else { continue }
    let middle = r.insetBy(dx: r.width * 0.3, dy: r.height * 0.3)
    let s = (page.selection(for: middle)?.string ?? "").filter { !$0.isWhitespace }
    guard let c = s.unicodeScalars.first else { continue }
    if s.count > 1 { ambiguous += 1 }
    count += 1
    glyphs += String(format: "G %@ %.1f %.1f %.1f %.1f\n", String(c.value, radix: 16, uppercase: true), r.minX, r.minY, r.width, r.height)
}
let printable = (0..<units.length).filter { units.character(at: $0) != 0x20 && units.character(at: $0) != 0x0A }.count
print("===== Glyphs: \(count) boxes for \(printable) printable characters, \(ambiguous) boxes with more than one =====")
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
