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
// Every character with its box in page points (origin bottom-left), one per line: the UTF-16 code
// in hex, then x, y, width, height to a tenth of a point.
print("===== Glyphs (\(page.numberOfCharacters)) =====")
let units = text as NSString
var glyphs = ""
for i in 0..<page.numberOfCharacters {
    let r = page.characterBounds(at: i)
    let code = i < units.length ? String(units.character(at: i), radix: 16, uppercase: true) : "?"
    glyphs += String(format: "G %@ %.1f %.1f %.1f %.1f\n", code, r.minX, r.minY, r.width, r.height)
}
print(glyphs, terminator: "")
try glyphs.write(toFile: args[2] + ".glyphs", atomically: true, encoding: .utf8)
print("===== Questions and the engine's answers =====")
for q in QuestionSplitter.split(MathText.pageForSolving(text)) {
    let answer = ExactMath.solve(q.stem)?.answer ?? "-"
    print("(\(q.number)) \(answer)    <- \(visible(q.stem).replacingOccurrences(of: "⏎\n", with: "⏎"))")
}
