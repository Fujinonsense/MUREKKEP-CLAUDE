import Foundation
import PDFKit
import Vision

/// A section of a chapter ("1.2 Domain and Range", "1B Vocabulary", "Text 2 …").
struct BookSection: Codable, Hashable {
    var number: String
    var title: String
    var page: Int
}

/// A chapter (or unit) of a long book, with its pages (0-based, inclusive).
struct BookChapter: Codable, Hashable, Identifiable {
    var number: Int
    var title: String
    var startPage: Int
    var endPage: Int
    var sections: [BookSection]

    var id: Int { startPage }
    var pages: ClosedRange<Int> { startPage...max(startPage, endPage) }
}

/// The first lines of a page (a contents page keeps all its lines).
struct PageHead {
    var page: Int
    var lines: [String]
}

/// The chapters of a long book (twin of tests/ports/chapters.py).
///
/// The PDF outline's top level wins when it has at least two chapters. Otherwise every rule below
/// proposes chapter openers, each rule keeps the first page per number and only increasing numbers,
/// and the rule with the most chapters wins (ties: section outline, then words, then padded numbers):
/// a page listing two or more "N.k Title" lines of one N including N.1; "Unit 3 …", "Chapter 2: …",
/// "BÖLÜM 4", "3. ÜNİTE …" (one family per word kind); a first line "03 Active and healthy". Contents
/// pages never open a chapter. The contents give titles, the sections with their pages (printed page
/// plus the chapter's offset) and where back matter starts; without contents, sections come from the
/// pages' first lines. The last chapter ends before back matter. Fewer than two chapters → none.
enum ChapterFinder {
    static let headLines = 8

    fileprivate struct Rx {
        let re: NSRegularExpression

        init(_ pattern: String, caseless: Bool = false) {
            re = try! NSRegularExpression(pattern: pattern, options: caseless ? [.caseInsensitive] : [])
        }

        func match(_ s: String) -> Hit? {
            let ns = s as NSString
            guard let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
            return Hit(ns: ns, m: m)
        }
    }

    fileprivate struct Hit {
        let ns: NSString
        let m: NSTextCheckingResult

        func group(_ i: Int) -> String {
            let r = m.range(at: i)
            return r.location == NSNotFound ? "" : ns.substring(with: r)
        }

        func named(_ name: String) -> String {
            let r = m.range(withName: name)
            return r.location == NSNotFound ? "" : ns.substring(with: r)
        }

        /// The text from where `name` starts to the end of the line (the original, unfolded line).
        func tail(from name: String, of line: String) -> String {
            let r = m.range(withName: name)
            guard r.location != NSNotFound else { return "" }
            return (line as NSString).substring(from: min(r.location, (line as NSString).length))
        }
    }

    private static let wordFamilies: [[String]] = [["chapter", "bölüm"], ["unit", "ünite"], ["module", "modül"],
                                                   ["part", "kısım"], ["lesson", "ders"]]
    private static let allWords = wordFamilies.flatMap { $0 }.joined(separator: "|")
    private static let contentsTitle = Rx(#"^(contents|table of contents|içindekiler)\b"#, caseless: true)
    private static let numberedLine = Rx(#"\s\d{1,4}$"#)
    private static let section = Rx(#"^(\d{1,2})\.(\d{1,2})\s+([^\d\s].*?)(?:\s+\d{1,4})?$"#)
    private static let wordFirst = Rx(#"^(?<kw>"# + allWords + #")\s*[:.]?\s*(?<num>\d{1,2}|[IVX]{1,4})\b\s*[:.\-–]?\s*(?<title>.*)$"#,
                                      caseless: true)
    private static let numberFirst = Rx(#"^(?<num>\d{1,2})\s*\.\s*(?<kw>"# + allWords + #")\b\s*[:.\-–]?\s*(?<title>.*)$"#,
                                        caseless: true)
    private static let padded = Rx(#"^(0[1-9]|[1-9]\d)\s+(\p{L}.{2,})$"#)
    private static let contentsChapter = Rx(#"^(?:(?:"# + allWords + #")\s+)?(\d{1,2})\s+([^\d\s].*?)\s+(\d{1,4})$"#, caseless: true)
    private static let contentsSection = Rx(#"^(\d{1,2})\.(\d{1,2})\s+([^\d\s].*?)\s+(\d{1,4})$"#)
    private static let contentsBack = Rx(#"^(?:[A-H]\s+\S.*|(?:appendix|answer key|answers|index|glossary|references|bibliography|ekler|cevap anahtarı|dizin|kaynakça|sözlük)\b.*?)\s+(\d{1,4})$"#,
                                         caseless: true)
    private static let lesson = Rx(#"^(\d{1,2})([A-H])\s+(\p{L}.*)$"#)
    private static let textSection = Rx(#"^(text|reading|section|metin|okuma)\s*(\d{1,2})\b\s*[:.\-–]?\s*(.*)$"#, caseless: true)
    private static let backMatter = Rx(#"^(answer key|answers|index|glossary|appendix|references|bibliography|credits|acknowledg|grammar reference|irregular verbs|cevap anahtarı|cevaplar|dizin|kaynakça|sözlük|ekler)"#,
                                       caseless: true)
    private static let notASection = Rx(#"^(section exercises|exercises|review|chapter review|key terms|key concepts)\b"#, caseless: true)
    private static let frontMatter = Rx(#"^(cover|title|copyright|contents|preface|foreword|kapak|önsöz|içindekiler)\b"#, caseless: true)
    private static let byline = Rx(#"\s+by\s+[A-Z][\w.'-]*(\s+[A-Z][\w.'-]*)*\s*$"#)
    private static let letterRun = Rx(#"\p{L}{3,}"#)
    private static let roman = ["I": 1, "II": 2, "III": 3, "IV": 4, "V": 5, "VI": 6, "VII": 7, "VIII": 8, "IX": 9, "X": 10]
    private static let small: Set<String> = ["and", "or", "of", "the", "a", "an", "to", "in", "for", "on", "at", "by",
                                             "ve", "ile", "ya", "da", "de"]
    private static let turkishLetters = Set("ÇĞİÖŞÜçğıöşü")

    /// Case-insensitive matching misses the dotted capital İ: it is folded to i for matching only.
    private static func fold(_ s: String) -> String { s.replacingOccurrences(of: "İ", with: "i") }

    private static func hasWord(_ s: String) -> Bool { letterRun.match(s) != nil }

    // MARK: Titles

    private static func isCaps(_ word: String) -> Bool {
        let letters = word.filter(\.isLetter)
        return !letters.isEmpty && !letters.contains { $0.isLowercase }
    }

    private static func titleCase(_ words: [String], turkish: Bool) -> [String] {
        var out: [String] = []
        for (k, w) in words.enumerated() {
            let source = turkish ? w.replacingOccurrences(of: "I", with: "ı").replacingOccurrences(of: "İ", with: "i") : w
            let low = source.lowercased()
            guard let first = low.first, !(k > 0 && small.contains(low)) else {
                out.append(low)
                continue
            }
            let head = turkish && first == "i" ? "İ" : String(first).uppercased()
            out.append(head + String(low.dropFirst()))
        }
        return out
    }

    /// A title as people write it: no bullets, bars or bylines; ALL-CAPS words in Title Case
    /// (Turkish-aware); a leading ALL-CAPS label before ordinary text becomes "Label – text".
    static func tidy(_ title: String) -> String {
        var t = title.replacingOccurrences(of: "•", with: " ").replacingOccurrences(of: "|", with: " ")
        t = t.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if let b = byline.match(t) { t = b.ns.substring(to: b.m.range.location) }
        t = t.trimmingCharacters(in: CharacterSet(charactersIn: " :.-–"))
        let words = t.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return "" }
        let turkish = t.contains { turkishLetters.contains($0) }
        if words.allSatisfy({ isCaps($0) || !$0.contains(where: \.isLetter) }) {
            return t.filter(\.isLetter).count >= 4 ? titleCase(words, turkish: turkish).joined(separator: " ") : t
        }
        // A label is made of capital words of two letters or more ("WRITING A formal letter").
        var caps = 0
        while caps < words.count && isCaps(words[caps]) && words[caps].filter(\.isLetter).count >= 2 {
            caps += 1
        }
        let letters = words[..<caps].joined(separator: " ").filter(\.isLetter).count
        if caps >= 1 && letters >= 4 {
            return titleCase(Array(words[..<caps]), turkish: turkish).joined(separator: " ") + " – "
                + words[caps...].joined(separator: " ")
        }
        return t
    }

    // MARK: Rules

    private static func number(_ token: String) -> Int? {
        Int(token) ?? roman[token.uppercased()]
    }

    private static func contentsPages(_ heads: [PageHead]) -> [Int] {
        var out: [Int] = []
        var previous = false
        for h in heads {
            let numbered = h.lines.filter { numberedLine.match($0) != nil }.count
            let isContents = !h.lines.isEmpty
                && (contentsTitle.match(h.lines[0]) != nil || (previous && numbered >= max(3, h.lines.count / 2)))
            if isContents { out.append(h.page) }
            previous = isContents
        }
        return out
    }

    private enum Entry {
        case chapter(Int, String, Int)
        case section(String, String, Int)
        case back(Int)
    }

    private static func contentsEntries(_ heads: [PageHead], pages: [Int]) -> [Entry] {
        var out: [Entry] = []
        for p in pages where heads.indices.contains(p) {
            for line in heads[p].lines {
                if let m = contentsSection.match(line), let printed = Int(m.group(4)) {
                    out.append(.section("\(m.group(1)).\(m.group(2))", m.group(3), printed))
                } else if let m = contentsChapter.match(line), let n = Int(m.group(1)), let printed = Int(m.group(3)) {
                    out.append(.chapter(n, m.group(2), printed))
                } else if let m = contentsBack.match(line), let printed = Int(m.group(1)) {
                    out.append(.back(printed))
                }
            }
        }
        return out
    }

    private typealias Candidate = (page: Int, number: Int?, title: String)

    /// First page per number, numbers increasing along the book.
    private static func keepIncreasing(_ found: [Candidate]) -> [(page: Int, number: Int, title: String)] {
        var out: [(page: Int, number: Int, title: String)] = []
        var last = 0
        for c in found.sorted(by: { $0.page < $1.page }) {
            if let n = c.number, n > last {
                out.append((page: c.page, number: n, title: c.title))
                last = n
            }
        }
        return out
    }

    private static func sectionMajors(_ lines: [String]) -> [(Int, Int)] {
        lines.prefix(headLines).compactMap { line -> (Int, Int)? in
            guard let m = section.match(line), let a = Int(m.group(1)), let b = Int(m.group(2)) else { return nil }
            return (a, b)
        }
    }

    private static func outlineRule(_ heads: [PageHead], skip: Set<Int>) -> [(page: Int, number: Int, title: String)] {
        var found: [Candidate] = []
        for h in heads where !skip.contains(h.page) {
            let majors = sectionMajors(h.lines)
            if majors.count >= 2, Set(majors.map { $0.0 }).count == 1, majors.contains(where: { $0.1 == 1 }) {
                found.append((page: h.page, number: majors[0].0, title: ""))
            }
        }
        return keepIncreasing(found)
    }

    private static func wordRule(_ heads: [PageHead], skip: Set<Int>, words: [String]) -> [(page: Int, number: Int, title: String)] {
        var found: [Candidate] = []
        for h in heads where !skip.contains(h.page) {
            let lines = Array(h.lines.prefix(3))
            for (k, line) in lines.enumerated() {
                let folded = fold(line)
                guard let m = wordFirst.match(folded) ?? numberFirst.match(folded),
                      words.contains(m.named("kw").lowercased()) else { continue }
                var title = m.named("title").isEmpty ? "" : m.tail(from: "title", of: line).trimmingCharacters(in: .whitespaces)
                if !hasWord(title) && k + 1 < lines.count { title = lines[k + 1] }
                found.append((page: h.page, number: number(m.named("num")), title: title))
                break
            }
        }
        return keepIncreasing(found)
    }

    private static func paddedRule(_ heads: [PageHead], skip: Set<Int>) -> [(page: Int, number: Int, title: String)] {
        var found: [Candidate] = []
        for h in heads where !skip.contains(h.page) {
            guard let first = h.lines.first, let m = padded.match(first) else { continue }
            found.append((page: h.page, number: Int(m.group(1)), title: m.group(2)))
        }
        return keepIncreasing(found)
    }

    private static func naturalKey(_ number: String) -> [String] {
        // Digits padded so "1.10" sorts after "1.2" and "Text 10" after "Text 9".
        var out: [String] = []
        var digits = ""
        var other = ""
        for ch in number {
            if ch.isNumber {
                if !other.isEmpty { out.append(other); other = "" }
                digits.append(ch)
            } else {
                if !digits.isEmpty { out.append(String(repeating: "0", count: max(0, 6 - digits.count)) + digits); digits = "" }
                other.append(ch)
            }
        }
        if !digits.isEmpty { out.append(String(repeating: "0", count: max(0, 6 - digits.count)) + digits) }
        if !other.isEmpty { out.append(other) }
        return out
    }

    private static func sortedSections(_ s: [BookSection]) -> [BookSection] {
        s.sorted { naturalKey($0.number).lexicographicallyPrecedes(naturalKey($1.number)) }
    }

    private static func sectionsFromPages(_ heads: [PageHead], _ c: BookChapter) -> [BookSection] {
        var seen: [String: BookSection] = [:]
        guard c.startPage <= c.endPage else { return [] }
        for h in heads where h.page >= c.startPage && h.page <= c.endPage {
            for line in h.lines.prefix(headLines) {
                var key = ""
                var title = ""
                if let m = section.match(line), Int(m.group(1)) == c.number {
                    key = "\(m.group(1)).\(m.group(2))"
                    title = m.group(3)
                } else if let m = lesson.match(line), Int(m.group(1)) == c.number {
                    key = m.group(1) + m.group(2)
                    title = m.group(3)
                } else if let m = textSection.match(fold(line)), let n = Int(m.group(2)) {
                    key = m.group(1).prefix(1).uppercased() + m.group(1).dropFirst().lowercased() + " \(n)"
                    let r = m.m.range(at: 3)
                    title = r.location == NSNotFound ? "" : (line as NSString).substring(from: min(r.location, (line as NSString).length))
                } else {
                    continue
                }
                let clean = tidy(title)
                if notASection.match(clean) != nil { continue }
                if seen[key] == nil { seen[key] = BookSection(number: key, title: clean, page: h.page) }
            }
        }
        return sortedSections(Array(seen.values))
    }

    // MARK: Finding

    static func find(outline: [(title: String, level: Int, page: Int)], heads: [PageHead], pageCount: Int) -> [BookChapter] {
        // 1. The PDF outline.
        let top = outline.filter { $0.level == 0 && $0.page >= 0 && $0.page < pageCount }.sorted { $0.page < $1.page }
        if top.count >= 2 {
            var chapters: [BookChapter] = []
            var back = pageCount
            for item in top {
                let t = item.title.trimmingCharacters(in: .whitespaces)
                if backMatter.match(t) != nil {
                    if !chapters.isEmpty { back = min(back, item.page) }
                    continue
                }
                if frontMatter.match(t) != nil { continue }
                chapters.append(BookChapter(number: chapters.count + 1, title: tidy(t), startPage: item.page, endPage: item.page,
                                            sections: []))
            }
            chapters = chapters.filter { $0.startPage < back }
            if chapters.count >= 2 {
                for k in chapters.indices {
                    chapters[k].endPage = (k + 1 < chapters.count ? chapters[k + 1].startPage : back) - 1
                }
                return chapters
            }
        }

        // 2. Openers found in the pages.
        let contents = contentsPages(heads)
        var skip = Set(contents)
        for h in heads where Set(sectionMajors(h.lines).map { $0.0 }).count >= 2 {
            skip.insert(h.page)
        }
        var rules = [outlineRule(heads, skip: skip)]
        rules += wordFamilies.map { wordRule(heads, skip: skip, words: $0) }
        rules.append(paddedRule(heads, skip: skip))
        // The first of equally long rules wins: the priority order above.
        var best = rules[0]
        for r in rules.dropFirst() where r.count > best.count { best = r }
        guard best.count >= 2 else { return [] }

        let entries = contentsEntries(heads, pages: contents)
        var listed: [Int: (title: String, printed: Int)] = [:]
        for case let .chapter(n, title, printed) in entries where listed[n] == nil {
            listed[n] = (title: title, printed: printed)
        }
        var chapters = best.map { c -> BookChapter in
            let name = hasWord(c.title) ? c.title : (listed[c.number]?.title ?? "")
            return BookChapter(number: c.number, title: tidy(name), startPage: c.page, endPage: c.page, sections: [])
        }
        var offsets: [Int: Int] = [:]
        for c in chapters {
            if let l = listed[c.number] { offsets[c.number] = c.startPage - l.printed }
        }

        // Back matter: from the contents (first entry after the last chapter's) or from the pages.
        var back = pageCount
        let last = chapters[chapters.count - 1]
        var afterLast = false
        for entry in entries {
            if case let .chapter(n, _, _) = entry, n == last.number {
                afterLast = true
            } else if afterLast, case let .back(printed) = entry, let offset = offsets[last.number] {
                back = min(back, printed + offset)
                break
            }
        }
        if last.startPage + 1 < back {
            for h in heads where h.page > last.startPage && h.page < back {
                if h.lines.prefix(2).contains(where: { backMatter.match(fold($0)) != nil }) {
                    back = h.page
                    break
                }
            }
        }

        for k in chapters.indices {
            chapters[k].endPage = (k + 1 < chapters.count ? chapters[k + 1].startPage : back) - 1
            let c = chapters[k]
            var listedSections: [BookSection] = []
            if let offset = offsets[c.number] {
                var seen = Set<String>()
                for case let .section(key, title, printed) in entries {
                    guard key.split(separator: ".").first.flatMap({ Int($0) }) == c.number, seen.insert(key).inserted else { continue }
                    let page = min(max(printed + offset, c.startPage), max(c.endPage, c.startPage))
                    listedSections.append(BookSection(number: key, title: tidy(title), page: page))
                }
            }
            chapters[k].sections = listedSections.isEmpty ? sectionsFromPages(heads, c) : sortedSections(listedSections)
            if chapters[k].title.isEmpty, let first = chapters[k].sections.first {
                chapters[k].title = first.title
            }
        }
        return chapters
    }
}

/// The chapters of a PDF note, found once (text layer, or OCR of the top third of scanned pages) and
/// kept on disk next to its page texts. Runs off the main thread.
enum BookIndex {
    private static func cacheURL(_ note: UUID) -> URL? {
        PageTextCache.folder(note: note)?.appendingPathComponent("chapters-v1.json")
    }

    static func cached(note: UUID) -> [BookChapter]? {
        guard let url = cacheURL(note), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([BookChapter].self, from: data)
    }

    static func chapters(pdf: URL, note: UUID, progress: (@Sendable (Int, Int) -> Void)? = nil) async -> [BookChapter] {
        if let known = cached(note: note) { return known }
        let found = await Task.detached(priority: .userInitiated) { () async -> [BookChapter]? in
            guard let doc = PDFDocument(url: pdf), doc.pageCount > 0 else { return [] }
            var heads: [PageHead] = []
            var previousContents = false
            for i in 0..<doc.pageCount {
                if Task.isCancelled { return nil }
                progress?(i, doc.pageCount)
                let lines = await BookIndex.headLines(doc, page: i, note: note)
                let numbered = lines.filter { $0.range(of: #"\s\d{1,4}$"#, options: .regularExpression) != nil }.count
                let isContents = !lines.isEmpty
                    && (lines[0].range(of: #"^(contents|table of contents|içindekiler)\b"#, options: [.regularExpression, .caseInsensitive]) != nil
                        || (previousContents && numbered >= max(3, lines.count / 2)))
                previousContents = isContents
                heads.append(PageHead(page: i, lines: isContents ? lines : Array(lines.prefix(ChapterFinder.headLines))))
            }
            return ChapterFinder.find(outline: BookIndex.outline(doc), heads: heads, pageCount: doc.pageCount)
        }.value
        guard let found else { return [] }
        if let url = cacheURL(note), let data = try? JSONEncoder().encode(found) {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
        return found
    }

    private static func outline(_ doc: PDFDocument) -> [(title: String, level: Int, page: Int)] {
        guard let root = doc.outlineRoot else { return [] }
        var out: [(title: String, level: Int, page: Int)] = []
        for i in 0..<root.numberOfChildren {
            guard let item = root.child(at: i), let page = item.destination?.page else { continue }
            out.append((title: item.label ?? "", level: 0, page: doc.index(for: page)))
        }
        return out
    }

    /// The page's lines: its text layer when it has one, the full OCR when the Studio already read it,
    /// otherwise OCR of the top third (where headings are).
    private static func headLines(_ doc: PDFDocument, page i: Int, note: UUID) async -> [String] {
        func split(_ s: String) -> [String] {
            s.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        if let cached = PageTextCache.load(note: note, page: i) { return split(cached.text) }
        guard let page = doc.page(at: i) else { return [] }
        let text = page.string ?? ""
        if TextLayer.isUsable(text) { return split(text) }
        guard let image = PDFPageReader.render(page, longEdge: 1600),
              let top = image.cropping(to: CGRect(x: 0, y: 0, width: image.width, height: image.height / 3)) else { return [] }
        return await HeadOCR.lines(top)
    }
}

/// One accurate Vision pass over a page's top: lines in reading order, pieces on the same row joined.
enum HeadOCR {
    static func lines(_ image: CGImage) async -> [String] {
        await withCheckedContinuation { (cont: CheckedContinuation<[String], Never>) in
            DispatchQueue.global(qos: .utility).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                if let supported = try? request.supportedRecognitionLanguages() {
                    let wanted = ["tr-TR", "en-US"].filter { supported.contains($0) }
                    if !wanted.isEmpty { request.recognitionLanguages = wanted }
                }
                let handler = VNImageRequestHandler(cgImage: image, options: [:])
                try? handler.perform([request])
                let found = (request.results ?? []).compactMap { obs -> (box: CGRect, text: String)? in
                    guard let best = obs.topCandidates(1).first else { return nil }
                    return (box: obs.boundingBox, text: best.string)
                }
                // Vision's boxes start at the bottom: higher maxY first; pieces within 1.5 % of the
                // height form one row, left to right.
                let sorted = found.sorted { $0.box.maxY > $1.box.maxY }
                var rows: [(y: CGFloat, parts: [(x: CGFloat, text: String)])] = []
                for f in sorted {
                    if let k = rows.indices.last, abs(rows[k].y - f.box.maxY) < 0.015 {
                        rows[k].parts.append((x: f.box.minX, text: f.text))
                    } else {
                        rows.append((y: f.box.maxY, parts: [(x: f.box.minX, text: f.text)]))
                    }
                }
                cont.resume(returning: rows.map { row in row.parts.sorted { $0.x < $1.x }.map(\.text).joined(separator: " ") })
            }
        }
    }
}
