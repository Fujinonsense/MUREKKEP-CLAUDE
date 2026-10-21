import Foundation

/// The keyless writer of the study tools: it can only use the sources' own sentences, so it looks for
/// what textbooks make easy to find. Definitions ("Türev, … oranıdır.", "… türev denir", "A cell is a
/// …", "Ribosome: …") become cards; the sentences dense with the book's frequent words become
/// fill-the-blank cards and questions whose wrong choices are other key words of the book; the parts'
/// headings become the mind map's branches and the guide's sections.
enum StudyOffline {
    typealias Part = (title: String, text: String)

    // MARK: Text

    // \x22 and \x28 are a quote and an opening bracket: a sentence may start with either.
    private static let sentenceBreak = try! NSRegularExpression(pattern: #"(?<=[.!?])\s+(?=[A-ZÇĞİÖŞÜ0-9\x22“\x28])"#)
    private static let pageMark = try! NSRegularExpression(pattern: #"\[s\.[^\]]*\]"#)

    /// The sentences of a text, in order (lines are kept apart; three words at least).
    static func sentences(_ text: String) -> [String] {
        var out: [String] = []
        for raw in text.components(separatedBy: .newlines) {
            let line = pageMark.stringByReplacingMatches(in: raw, range: NSRange(raw.startIndex..., in: raw), withTemplate: " ")
                .trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            let ns = line as NSString
            var start = 0
            for m in sentenceBreak.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
                out.append(ns.substring(with: NSRange(location: start, length: m.range.location - start)))
                start = m.range.location + m.range.length
            }
            out.append(ns.substring(from: start))
        }
        return out.map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.split(separator: " ").count >= 3 }
    }

    private static let stopwords: Set<String> = [
        "çünkü", "ancak", "fakat", "olarak", "olduğu", "olduğunu", "olduğunda", "olan", "olur", "olması", "gibi", "kadar", "daha",
        "sonra", "önce", "şekilde", "birbirinin", "verilen", "bunun", "şöyle", "böyle", "aynı", "diğer", "tüm", "bütün", "değil",
        "about", "after", "before", "these", "those", "their", "there", "which", "while", "where", "other", "being", "could",
        "would", "should", "because", "between", "through", "called", "refers", "means", "contains", "within",
    ]

    /// Turkish verb forms and possessive/genitive forms make poor answers ("kullanılır", "fonksiyonun"):
    /// key words are the bare nouns.
    private static let turkishEndings = ["lır", "lir", "lur", "lür", "ıyor", "iyor", "uyor", "üyor", "maz", "mez", "dır", "dir",
                                         "dur", "dür", "tır", "tir", "tur", "tür", "mış", "miş", "muş", "müş", "nın", "nin",
                                         "nun", "nün", "abilir", "ebilir", "ması", "mesi"]

    private static func isKeyWord(_ w: String, english: Bool) -> Bool {
        guard w.count >= 5, !stopwords.contains(w) else { return false }
        if english { return !w.hasSuffix("ing") && !w.hasSuffix("ed") && !w.hasSuffix("ly") }
        return !turkishEndings.contains { w.hasSuffix($0) }
    }

    private static func lower(_ s: String, english: Bool) -> String {
        s.lowercased(with: Locale(identifier: english ? "en" : "tr"))
    }

    private static func words(_ s: String) -> [String] {
        s.split { !$0.isLetter }.map(String.init)
    }

    /// The book's key words: the most frequent words of five letters or more that are not glue words.
    static func keyTerms(_ text: String, english: Bool, count: Int) -> [String] {
        var freq: [String: Int] = [:]
        for w in words(text) {
            let l = lower(w, english: english)
            guard isKeyWord(l, english: english) else { continue }
            freq[l, default: 0] += 1
        }
        return freq.filter { $0.value >= 2 }.sorted { a, b in
            a.value != b.value ? a.value > b.value : (a.key.count != b.key.count ? a.key.count > b.key.count : a.key < b.key)
        }.prefix(count).map(\.key)
    }

    /// How much of the book's key vocabulary a sentence holds.
    private static func score(_ sentence: String, weights: [String: Int], english: Bool) -> Double {
        let ws = words(sentence).map { lower($0, english: english) }.filter { $0.count >= 5 }
        guard !ws.isEmpty else { return 0 }
        return ws.reduce(0.0) { $0 + log(1 + Double(weights[$1] ?? 0)) } / Double(ws.count).squareRoot()
    }

    private static func weights(_ text: String, english: Bool) -> [String: Int] {
        var freq: [String: Int] = [:]
        for w in words(text) {
            let l = lower(w, english: english)
            if l.count >= 5, !stopwords.contains(l) { freq[l, default: 0] += 1 }
        }
        return freq
    }

    /// The `count` most informative sentences of a text, in reading order.
    static func keySentences(_ text: String, english: Bool, count: Int, within whole: String? = nil) -> [String] {
        let w = weights(whole ?? text, english: english)
        let list = sentences(text).enumerated().filter { $0.element.count >= 30 && $0.element.count <= 300 }
        return list.sorted { score($0.element, weights: w, english: english) > score($1.element, weights: w, english: english) }
            .prefix(count).sorted { $0.offset < $1.offset }.map(\.element)
    }

    private static func shorten(_ s: String, words limit: Int) -> String {
        let parts = s.split(separator: " ")
        let trimmed = s.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        guard parts.count > limit else { return trimmed }
        return parts.prefix(limit).joined(separator: " ") + "…"
    }

    private static func capitalizedFirst(_ s: String, english: Bool) -> String {
        guard let first = s.first else { return s }
        return String(first).uppercased(with: Locale(identifier: english ? "en" : "tr")) + s.dropFirst()
    }

    // MARK: Definitions

    private static let turkishComma = try! NSRegularExpression(
        pattern: #"^([^,]{2,40}),\s+(.{8,240}?(?:dır|dir|dur|dür|tır|tir|tur|tür))\.?$"#)
    private static let turkishCalled = try! NSRegularExpression(
        pattern: #"^(.{8,200}?)\s+(\S{2,30})\s+(?:denir|denilir|adı verilir)\.?$"#)
    private static let turkishDefined = try! NSRegularExpression(
        pattern: #"^([^,]{2,40}),\s+(.{8,240}?)\s+olarak tanımlanır\.?$"#)
    private static let englishIs = try! NSRegularExpression(
        pattern: #"^(?:(an?|the)\s+)?([a-z][a-z\- ]{1,40}?)\s+(is|are)\s+(?:(?:defined as|called)\s+)?(?:an?|the)\s+(.{8,})$"#,
        options: [.caseInsensitive])
    private static let englishRefers = try! NSRegularExpression(
        pattern: #"^(?:(an?|the)\s+)?([a-z][a-z\- ]{1,40}?)\s+(refers to|means)\s+(.{8,})$"#, options: [.caseInsensitive])
    private static let glossary = try! NSRegularExpression(pattern: #"^([^:]{2,40}):\s+(.{12,})$"#)

    private static func groups(_ rx: NSRegularExpression, _ s: String) -> [String]? {
        let ns = s as NSString
        guard let m = rx.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (0..<m.numberOfRanges).map { i in
            let r = m.range(at: i)
            return r.location == NSNotFound ? "" : ns.substring(with: r)
        }
    }

    /// Terms defined in the text and the sentence that defines each, in order, one per term.
    static func definitions(_ text: String, english: Bool) -> [(term: String, front: String, sentence: String)] {
        var out: [(term: String, front: String, sentence: String)] = []
        var seen = Set<String>()
        func add(_ term: String, front: String, sentence: String) {
            let key = lower(term, english: english)
            guard term.split(separator: " ").count <= 4, !seen.contains(key) else { return }
            seen.insert(key)
            out.append((term: term, front: front, sentence: sentence))
        }
        for s in sentences(text) {
            if english {
                if let g = groups(englishIs, s) ?? groups(englishRefers, s) {
                    let term = g[2].trimmingCharacters(in: .whitespaces)
                    let article = g[1].isEmpty ? "" : lower(g[1], english: true) + " "
                    let verb = g[3].lowercased() == "are" ? "are" : "is"
                    add(term, front: "What \(verb) \(article)\(lower(term, english: true))?", sentence: s)
                } else if let g = groups(glossary, s) {
                    let term = g[1].trimmingCharacters(in: .whitespaces)
                    add(term, front: "What is \(lower(term, english: true))?", sentence: s)
                }
            } else {
                if let g = groups(turkishComma, s) ?? groups(turkishDefined, s) {
                    let term = g[1].trimmingCharacters(in: .whitespaces)
                    add(term, front: "\(capitalizedFirst(term, english: false)) nedir?", sentence: s)
                } else if let g = groups(turkishCalled, s) {
                    let term = g[2].trimmingCharacters(in: .whitespaces)
                    add(term, front: "\(capitalizedFirst(term, english: false)) nedir?", sentence: s)
                } else if let g = groups(glossary, s) {
                    let term = g[1].trimmingCharacters(in: .whitespaces)
                    add(term, front: "\(capitalizedFirst(term, english: false)) nedir?", sentence: s)
                }
            }
        }
        return out
    }

    // MARK: Fill the blank

    private struct Cloze {
        var question: String
        var answer: String
        var sentence: String
    }

    /// Key sentences with one key word blanked out wherever it stands alone; a sentence is used only
    /// when the word does not still show inside another word ("türevin").
    private static func clozes(_ parts: [Part], english: Bool, terms: [String], count: Int,
                               skipping used: Set<String> = []) -> [Cloze] {
        let whole = parts.map(\.text).joined(separator: "\n")
        var out: [Cloze] = []
        var usedSentences = used
        let candidates = keySentences(whole, english: english, count: count * 3 + 6)
        for s in candidates where out.count < count {
            guard !usedSentences.contains(s) else { continue }
            for term in terms {
                let pattern = "(?<![\\p{L}])" + NSRegularExpression.escapedPattern(for: term) + "(?![\\p{L}])"
                guard let rx = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
                let ns = s as NSString
                guard rx.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) != nil else { continue }
                let blanked = rx.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: ns.length), withTemplate: "_____")
                guard !lower(blanked, english: english).contains(term) else { continue }
                out.append(Cloze(question: blanked, answer: term, sentence: s))
                usedSentences.insert(s)
                break
            }
        }
        return out
    }

    // MARK: Tools

    static func flashcards(parts: [Part], english: Bool, count: Int) -> [Flashcard] {
        let whole = parts.map(\.text).joined(separator: "\n")
        let defined = definitions(whole, english: english)
        var cards = defined.prefix(count).map { Flashcard(front: $0.front, back: $0.sentence) }
        if cards.count < count {
            let terms = keyTerms(whole, english: english, count: 16)
            // Sentences that already gave a definition card are not asked again as a blank.
            for c in clozes(parts, english: english, terms: terms, count: count - cards.count, skipping: Set(defined.map(\.sentence)))
                where !cards.contains(where: { $0.front == c.question }) {
                cards.append(Flashcard(front: c.question, back: capitalizedFirst(c.answer, english: english) + "\n\n" + c.sentence))
            }
        }
        return Array(cards.prefix(count))
    }

    static func quiz(parts: [Part], english: Bool, count: Int) -> [QuizQuestion] {
        let whole = parts.map(\.text).joined(separator: "\n")
        let terms = keyTerms(whole, english: english, count: 16)
        guard terms.count >= 4 else { return [] }
        return clozes(parts, english: english, terms: terms, count: count).compactMap { c in
            // Wrong choices: other key words, closest in length first.
            let others = terms.filter { $0 != c.answer && !lower(c.question, english: english).contains($0) }
                .sorted { abs($0.count - c.answer.count) < abs($1.count - c.answer.count) }
            guard others.count >= 3 else { return nil }
            var choices = [c.answer] + others.prefix(3)
            // A fixed shuffle per question, so the right answer is not always first.
            let shift = c.sentence.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF } % 4
            choices = Array(choices[shift...] + choices[..<shift])
            return QuizQuestion(question: c.question, choices: choices, answer: choices.firstIndex(of: c.answer) ?? 0,
                                explanation: c.sentence)
        }
    }

    static func mindMap(title: String, parts: [Part], english: Bool) -> MindNode {
        let whole = parts.map(\.text).joined(separator: "\n")
        var root = MindNode(title: title)
        for part in parts.prefix(10) {
            var branch = MindNode(title: part.title)
            let partSentences = sentences(part.text)
            for term in keyTerms(part.text, english: english, count: 4) where branch.children.count < 4 {
                var node = MindNode(title: capitalizedFirst(term, english: english))
                if let s = partSentences.first(where: { lower($0, english: english).contains(term) }) {
                    node.children = [MindNode(title: shorten(s, words: 12))]
                }
                branch.children.append(node)
            }
            if branch.children.isEmpty {
                branch.children = keySentences(part.text, english: english, count: 3, within: whole).map { MindNode(title: shorten($0, words: 10)) }
            }
            root.children.append(branch)
        }
        return root
    }

    static func guide(parts: [Part], english: Bool) -> StudyGuide {
        let whole = parts.map(\.text).joined(separator: "\n")
        let summary = keySentences(whole, english: english, count: 3)
        let sections = parts.map { part in
            GuideSection(heading: part.title,
                         points: keySentences(part.text, english: english, count: 4, within: whole).map { shorten($0, words: 34) })
        }
        let defined = definitions(whole, english: english)
        let terms = defined.prefix(14).map { GuideTerm(term: capitalizedFirst($0.term, english: english), definition: $0.sentence) }
        var questions = defined.prefix(4).map { d -> String in
            english ? "What is \(lower(d.term, english: true)), and why does it matter?"
                    : "\(capitalizedFirst(d.term, english: false)) nedir ve neden önemlidir?"
        }
        for part in parts.prefix(4) where questions.count < 8 {
            questions.append(english ? "Explain the main idea of \"\(part.title)\" in your own words."
                                     : "\"\(part.title)\" bölümünün ana fikrini kendi cümlelerinle anlat.")
        }
        return StudyGuide(summary: summary, sections: sections, terms: Array(terms), questions: questions)
    }
}
