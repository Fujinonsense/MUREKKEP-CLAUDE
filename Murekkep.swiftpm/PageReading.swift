import Foundation
import PDFKit
import UIKit

/// Whether a PDF page's text layer can be used, and the repair of ligatures its fonts lost (twin of
/// tests/ports/textlayer.py).
///
/// A text layer is used when it has at least 25 letters and at most 2 % of its visible characters are
/// broken glyphs (U+FFFD, U+FFFE, private use, the empty box U+2B1A); otherwise the page is read with
/// OCR. Books whose fonts map ligatures to nothing ("de_ned", "coXee") are repaired word by word: "_"
/// and an "X" between lowercase letters become fi, fl, ff, ffi or ffl, whichever first makes a word.
enum TextLayer {
    static let minLetters = 25
    static let maxBroken = 0.02
    private static let ligatures = ["fi", "fl", "ff", "ffi", "ffl"]
    private static let token = try! NSRegularExpression(pattern: "[A-Za-zÇĞİÖŞÜçğıöşü_]+")
    private static let innerX = try! NSRegularExpression(pattern: "(?<=[a-zçğıöşü])X(?=[a-zçğıöşü])")

    private static func isBroken(_ u: Unicode.Scalar) -> Bool {
        u.value == 0xFFFD || u.value == 0xFFFE || u.value == 0x2B1A || (0xE000...0xF8FF).contains(u.value)
    }

    static func isUsable(_ text: String) -> Bool {
        var visible = 0
        var letters = 0
        var broken = 0
        for u in text.unicodeScalars where !CharacterSet.whitespacesAndNewlines.contains(u) {
            visible += 1
            if CharacterSet.letters.contains(u) { letters += 1 }
            if isBroken(u) { broken += 1 }
        }
        guard letters >= minLetters else { return false }
        return Double(broken) <= maxBroken * Double(visible)
    }

    private static func hasInnerX(_ s: String) -> Bool {
        innerX.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)) != nil
    }

    /// Whether the text has words a repair could change (cheap; avoids the dictionary otherwise).
    static func needsRepair(_ text: String) -> Bool {
        text.contains("_") || hasInnerX(text)
    }

    static func repairLigatures(_ text: String, isWord: (String) -> Bool) -> String {
        let ns = text as NSString
        let matches = token.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return text }
        var out = ""
        var last = 0
        for m in matches {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            out += repaired(ns.substring(with: m.range), isWord: isWord)
            last = m.range.location + m.range.length
        }
        out += ns.substring(from: last)
        return out
    }

    private static func repaired(_ word: String, isWord: (String) -> Bool) -> String {
        guard word.contains("_") || hasInnerX(word) else { return word }
        for lig in ligatures {
            let replaced = word.replacingOccurrences(of: "_", with: lig)
            let candidate = innerX.stringByReplacingMatches(in: replaced, range: NSRange(location: 0, length: (replaced as NSString).length),
                                                            withTemplate: lig)
            if isWord(candidate) { return candidate }
        }
        return word
    }
}

/// Which pages of a long range are read: `limit` pages spread evenly, first and last included.
enum PageSample {
    static func pages(count: Int, limit: Int) -> [Int] {
        guard count > limit else { return Array(0..<max(count, 0)) }
        guard limit > 1 else { return [0] }
        return (0..<limit).map { i in Int((Double(i * (count - 1)) / Double(limit - 1)).rounded()) }
    }
}

/// Words the system dictionary knows, in English or Turkish (lower-cased), remembered.
@MainActor
enum WordCheck {
    private static let checker = UITextChecker()
    private static var known: [String: Bool] = [:]
    private static let languages = ["en_US", "tr_TR"].filter { UITextChecker.availableLanguages.contains($0) }

    static func isWord(_ word: String) -> Bool {
        let w = word.lowercased()
        if let answer = known[w] { return answer }
        let range = NSRange(location: 0, length: (w as NSString).length)
        var ok = false
        for language in languages {
            let miss = checker.rangeOfMisspelledWord(in: w, range: range, startingAt: 0, wrap: false, language: language)
            if miss.location == NSNotFound {
                ok = true
                break
            }
        }
        known[w] = ok
        return ok
    }
}

/// Text of PDF pages already read (repaired text layer, or OCR), kept on disk per note so a book is
/// read only once. An empty file is a blank page. OCR is kept as ".ocr2": the ".ocr" files of earlier
/// builds were read row by row across both columns of a page (before `ReadingOrder`), so they are
/// dropped and those pages read once more.
enum PageTextCache {
    private static var root: URL? {
        guard let support = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                         appropriateFor: nil, create: true) else { return nil }
        return support.appendingPathComponent("Murekkep/PageText/v1", isDirectory: true)
    }

    private static func url(_ note: UUID, _ page: Int, _ kind: String) -> URL? {
        root?.appendingPathComponent(note.uuidString, isDirectory: true).appendingPathComponent("\(page).\(kind)")
    }

    static func load(note: UUID, page: Int) -> (text: String, fromOCR: Bool)? {
        if let u = url(note, page, "txt"), let s = try? String(contentsOf: u, encoding: .utf8) { return (text: s, fromOCR: false) }
        if let u = url(note, page, "ocr2"), let s = try? String(contentsOf: u, encoding: .utf8) { return (text: s, fromOCR: true) }
        if let old = url(note, page, "ocr") { try? FileManager.default.removeItem(at: old) }
        return nil
    }

    static func save(_ text: String, fromOCR: Bool, note: UUID, page: Int) {
        guard let u = url(note, page, fromOCR ? "ocr2" : "txt") else { return }
        try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? text.write(to: u, atomically: true, encoding: .utf8)
    }

    /// Folder of a note's cached pages (other caches of the same book live next to them).
    static func folder(note: UUID) -> URL? {
        root?.appendingPathComponent(note.uuidString, isDirectory: true)
    }
}

/// One PDF page as text: the text layer when it is real (ligatures repaired), otherwise Vision OCR of
/// the page image. Call off the main thread.
enum PDFPageReader {
    static func read(_ doc: PDFDocument, page i: Int, noteID: UUID?) async -> (text: String, fromOCR: Bool) {
        if let noteID, let cached = PageTextCache.load(note: noteID, page: i) { return cached }
        guard let page = doc.page(at: i) else { return (text: "", fromOCR: false) }
        var text = page.string ?? ""
        var fromOCR = false
        if TextLayer.isUsable(text) {
            if TextLayer.needsRepair(text) {
                let raw = text
                text = await MainActor.run { TextLayer.repairLigatures(raw) { WordCheck.isWord($0) } }
            }
        } else {
            fromOCR = true
            text = ""
            if let image = render(page, longEdge: 2000) {
                text = await PageOCR.recognize(image)
            }
        }
        if let noteID { PageTextCache.save(text, fromOCR: fromOCR, note: noteID, page: i) }
        return (text: text, fromOCR: fromOCR)
    }

    static func render(_ page: PDFPage, longEdge: CGFloat) -> CGImage? {
        let box = page.bounds(for: .mediaBox)
        guard box.width > 0, box.height > 0 else { return nil }
        let scale = longEdge / max(box.width, box.height)
        return page.thumbnail(of: CGSize(width: box.width * scale, height: box.height * scale), for: .mediaBox).cgImage
    }

    static func letterCount(_ s: String) -> Int {
        s.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
    }
}
