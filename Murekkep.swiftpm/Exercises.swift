import Foundation

/// A gap of an exercise item; `given` is an answer printed as the example ("ø").
struct ExerciseGap: Equatable {
    var number: Int
    var given: String?
}

/// One item of an exercise; number 0 is the printed example. A running text is one item.
struct ExerciseItem: Equatable {
    var number: Int
    var text: String
    var gaps: [ExerciseGap] = []
    var options: [QuestionOption] = []

    var isExample: Bool { number == 0 }
}

/// One exercise of a textbook page.
struct PageExercise: Equatable {
    enum Kind: String {
        case gaps, options, short, skip
    }

    var number: Int
    var instruction: String
    var kind: Kind
    /// The words that may fill a gap or answer an item ([] when the instruction does not list them).
    var choices: [String]
    var items: [ExerciseItem]
    /// One item: a text whose gaps are numbered in it.
    var running = false
    /// What follows the items (a grammar box).
    var context = ""
    /// The page's text before the first exercise, when the instruction refers to a text.
    var passage: String?
}

/// One call to the model: an item, or a sentence of a running text.
struct ExerciseUnit: Equatable {
    /// The item's number, 0 for a running text.
    var number: Int
    /// Gaps to fill marked "(n) ___".
    var text: String
    /// The gaps to fill, in order ([] for a short answer).
    var gaps: [ExerciseGap]
    /// The sentence before it (running text).
    var before = ""
}

/// The exercises of a textbook page, so a small model answers one item at a time with the exercise's
/// instruction in front of it (twin of tests/ports/exercises.py).
///
/// An exercise starts on a line "N <instruction>" whose N follows the previous exercise's number (the
/// first may be any number) and whose text is an instruction: a sentence that starts with an
/// instruction verb ("Complete", "In pairs, match"), a Turkish instruction verb anywhere
/// ("tamamlayınız"), or a section label ("SPEAKING"). The instruction runs on to the end of its
/// sentence (at most four lines); then come items "N text" numbered from 1 (or 0 for the example), or a
/// running text whose gaps are numbered inside it. A short heading ("Articles", "WATCH OUT!") ends the
/// items; what follows is the exercise's context (a grammar box). Text before the first exercise is the
/// page's passage.
///
/// Gaps are printed blanks ("___", see `ReadingOrder.normalizeBlanks`). In a running text a gap's
/// number may be glued to the word before it ("is3"), stand alone ("2 ___"), be misread ("1o" for 10)
/// or have lost its blank ("wearing5 old"); gaps are counted in order, so a lost number costs nothing.
/// The words that may fill a gap come from the instruction ("with ø (no article), a/an or the",
/// "rules a-g") or from a box of words. Exercises with no writing to do (speaking, discussion) are
/// skipped.
enum ExerciseSplitter {
    private static func rx(_ pattern: String, _ options: NSRegularExpression.Options = []) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: options)
    }

    private static let header = rx(#"^\s*(\d{1,2})[.)]?\s+(\S.*)$"#)
    private static let track = rx(#"^[A-Z]?\d{1,2}\.\d{1,2}\s+"#)
    private static let label = rx(#"^(?:[A-ZÇĞİÖŞÜ]{4,}\s+)+(?=\S)"#)
    private static let lead = rx(#"^(?:(?:in pairs|in groups|then|now|first|finally|individually)\s*,?\s*)+"#, .caseInsensitive)
    private static let writeVerbs: Set<String> = [
        "complete", "fill", "choose", "circle", "underline", "match", "rewrite", "write", "put", "correct",
        "order", "tick", "find", "answer", "translate", "decide", "label", "add", "replace", "change",
        "join", "combine", "cross", "number", "sort", "make", "use", "mark", "identify", "unscramble",
        "rearrange", "transform", "select", "give",
    ]
    private static let otherVerbs: Set<String> = [
        "read", "listen", "discuss", "study", "look", "work", "talk", "ask", "say", "check", "think",
        "imagine", "compare", "describe", "practise", "practice", "repeat", "watch", "note", "guess",
        "tell", "share", "play", "act", "prepare", "take", "plan", "present", "review",
    ]
    private static let turkishVerb = rx(
        #"(?<![\wçğıöşü])(?:tamamla|doldur|eşleştir|işaretle|cevapla|yanıtla|düzelt|sırala|çevir|belirle|birleştir)"#
            + #"(?:y?[ıiuü]n(?:[ıiuü]z)?)?(?![\wçğıöşü])"#
            + #"|(?<![\wçğıöşü])(?:yaz|seç|bul|çiz)[ıiuü]n(?:[ıiuü]z)?(?![\wçğıöşü])"#, .caseInsensitive)
    private static let turkishSkip = rx(#"(?<![\wçğıöşü])(?:tartış|konuş|dinle)"#, .caseInsensitive)
    private static let strong = rx(#"\b(?:the|these) (?:gaps|sentences|text|questions|words|blanks|dialogue|table|box|email|"#
        + #"paragraph|conversation)\b"#, .caseInsensitive)
    private static let passageCue = rx(#"\b(?:text|passage|letter|email|story|article on|metin|metne|parça)"#, .caseInsensitive)
    private static let noArticle = rx(#"(?:^|(?<=\s))[-–o0Øø]\s*\((?:no article|ø|o|0)\)"#, .caseInsensitive)
    private static let articleO = rx(#"\bno article \([o0Ø]\)"#, .caseInsensitive)
    private static let letterRange = rx(#"(?:with|to|rules?|options?|endings?|letters?|from)\s+([a-h])\s*[-–]\s*([a-h])\b"#)
    private static let trueFalse = rx(#"\btrue or false\b"#, .caseInsensitive)
    private static let listTail = rx(#"\b(?:with|using)\s+(.+?)(?:[.:;!?](?:\s|$)|$)"#, .caseInsensitive)
    private static let glued = rx(#"^(.*?[^\d\s])(\d{1,2})$"#)
    private static let superscriptMisread = Set("éèêº°¹²³⁴⁵⁶⁷⁸⁹⁰")
    private static let givenO: Set<String> = ["o", "0", "-", "–"]
    private static let maxInstructionLines = 4
    private static let maxLostGaps = 3
    static let contextChars = 1500
    static let passageChars = 1500

    private static let anWords = ["hour", "honest", "honour", "honor", "heir"]
    private static let aPrefixes = ["unic", "unif", "unio", "uniq", "unit", "univ", "use", "usu", "usa", "uti", "ure", "eu",
                                    "one", "ewe", "ufo", "uk"]
    private static let anLetters = Set("AEFHILMNORSX")

    // MARK: Regex helpers

    private static func range(_ s: String) -> NSRange { NSRange(location: 0, length: (s as NSString).length) }

    private static func found(_ r: NSRegularExpression, _ s: String) -> Bool {
        r.firstMatch(in: s, range: range(s)) != nil
    }

    /// The capture groups of the first match ("" for a group that did not take part), nil without one.
    private static func groups(_ r: NSRegularExpression, _ s: String) -> [String]? {
        let ns = s as NSString
        guard let m = r.firstMatch(in: s, range: range(s)) else { return nil }
        return (0..<m.numberOfRanges).map { i in
            let g = m.range(at: i)
            return g.location == NSNotFound ? "" : ns.substring(with: g)
        }
    }

    private static func replace(_ r: NSRegularExpression, in s: String, with t: String) -> String {
        r.stringByReplacingMatches(in: s, range: range(s), withTemplate: t)
    }

    private static func replace(_ pattern: String, in s: String, _ body: ([String]) -> String) -> String {
        let r = rx(pattern)
        let ns = s as NSString
        var out = ""
        var last = 0
        for m in r.matches(in: s, range: range(s)) {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            out += body((0..<m.numberOfRanges).map { m.range(at: $0).location == NSNotFound ? "" : ns.substring(with: m.range(at: $0)) })
            last = m.range.location + m.range.length
        }
        return out + ns.substring(from: last)
    }

    private static func tokens(_ s: String) -> [String] {
        s.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    private static func words(_ s: String) -> [String] {
        let r = rx(#"[A-Za-z']+"#)
        let ns = s.lowercased() as NSString
        return r.matches(in: ns as String, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
    }

    private static func sentences(_ s: String) -> [String] {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        let r = rx(#"(?<=[.!?])\s+"#)
        let ns = t as NSString
        var out: [String] = []
        var last = 0
        for m in r.matches(in: t, range: range(t)) {
            out.append(ns.substring(with: NSRange(location: last, length: m.range.location - last)))
            last = m.range.location + m.range.length
        }
        out.append(ns.substring(from: last))
        return out.filter { !$0.isEmpty }
    }

    // MARK: Lines

    private static func cleanHeader(_ rest: String) -> String {
        var s = replace(rx(#"^___\s+"#), in: rest, with: "")
        s = replace(track, in: s, with: "")
        s = replace(label, in: s, with: "")
        return s.trimmingCharacters(in: .whitespaces)
    }

    private static func isInstruction(_ rest: String) -> Bool {
        if found(label, rest) || found(turkishVerb, rest) { return true }
        for sentence in sentences(cleanHeader(replace(track, in: rest, with: ""))) {
            if let first = words(replace(lead, in: sentence, with: "")).first,
               writeVerbs.contains(first) || otherVerbs.contains(first) {
                return true
            }
        }
        return false
    }

    private static func isStrong(_ rest: String) -> Bool {
        found(track, rest) || found(label, replace(track, in: rest, with: "")) || found(strong, rest) || found(turkishVerb, rest)
    }

    /// A sentence end, maybe followed by a closing quote or bracket (' " ’ ” and a right parenthesis).
    private static func endsSentence(_ s: String) -> Bool {
        found(rx(#"[.!?:][\x{27}\x{22}\x{2019}\x{201D}\x{29}]?$"#), s.trimmingCharacters(in: .whitespaces))
    }

    private static func isHeading(_ line: String) -> Bool {
        let s = line.trimmingCharacters(in: .whitespaces)
        guard let first = s.first, !first.isWholeNumber, first.isUppercase,
              !found(rx(#"[.,;:?]$"#), s) else { return false }
        return tokens(s).count <= 4
    }

    private static func boxWords(_ line: String) -> [String]? {
        let t = line.trimmingCharacters(in: .whitespaces)
        let ns = t as NSString
        var parts: [String] = []
        var last = 0
        for m in rx(#"\s*[/•|,]\s*|\s{2,}"#).matches(in: t, range: range(t)) {
            parts.append(ns.substring(with: NSRange(location: last, length: m.range.location - last)))
            last = m.range.location + m.range.length
        }
        parts.append(ns.substring(from: last))
        parts = parts.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard (3...15).contains(parts.count),
              parts.allSatisfy({ tokens($0).count <= 2 && !($0.first?.isWholeNumber ?? false) }) else { return nil }
        return parts
    }

    private static func withNoArticle(_ s: String) -> String {
        replace(articleO, in: replace(noArticle, in: s, with: "ø (no article)"), with: "no article (ø)")
    }

    /// The words that may fill a gap, from the instruction; [] when it does not list them.
    static func choices(_ instruction: String) -> [String] {
        let s = withNoArticle(instruction)
        if let g = groups(letterRange, s), let a = g[1].unicodeScalars.first, let b = g[2].unicodeScalars.first, a <= b {
            return (a.value...b.value).compactMap { Unicode.Scalar($0).map { String(Character($0)) } }
        }
        if found(trueFalse, s) { return ["True", "False"] }
        guard let g = groups(listTail, s) else { return [] }
        // Without parentheticals such as "(no article)".
        let tail = replace(rx(#"[(][^\x{29}]*[)]"#), in: g[1], with: "")
        let ns = tail as NSString
        var raw: [String] = []
        var last = 0
        for m in rx(#",\s*|\s+or\s+|\s+and\s+|/"#).matches(in: tail, range: range(tail)) {
            raw.append(ns.substring(with: NSRange(location: last, length: m.range.location - last)))
            last = m.range.location + m.range.length
        }
        raw.append(ns.substring(from: last))
        let parts = raw.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " '\"")) }.filter { !$0.isEmpty }
        guard (2...8).contains(parts.count), parts.allSatisfy({ tokens($0).count <= 2 }) else { return [] }
        var out: [String] = []
        for p in parts {
            let t = ["ø", "Ø", "-", "–"].contains(p) ? "ø" : p
            if !out.contains(t) { out.append(t) }
        }
        return out
    }

    // MARK: Gaps

    private static func given(_ token: String, _ options: [String]) -> String? {
        if token == "ø" || token == "Ø" { return "ø" }
        if givenO.contains(token) && options.contains("ø") { return "ø" }
        return options.contains(token) ? token : nil
    }

    /// (base, n) when the token is a gap number n from k to k + slack, alone ("2", "1o") or glued to
    /// the word before it ("is3", base "is").
    private static func gapNumber(_ token: String, _ k: Int, slack: Int) -> (base: String, number: Int)? {
        if found(rx(#"^[0-9oOlI]{1,2}$"#), token), token.contains(where: { $0.isASCII && $0.isNumber }) {
            let digits = String(token.map { c -> Character in
                switch c {
                case "o", "O": return "0"
                case "l", "I": return "1"
                default: return c
                }
            })
            guard let n = Int(digits), (k...(k + slack)).contains(n) else { return nil }
            return ("", n)
        }
        if let g = groups(glued, token), let n = Int(g[2]), (k...(k + slack)).contains(n),
           g[1].contains(where: { $0.isASCII && $0.isLetter }) {
            return (g[1], n)
        }
        return nil
    }

    private static func stripMisread(_ token: String) -> String {
        var t = token
        while t.count > 1, let last = t.last, superscriptMisread.contains(last) {
            t.removeLast()
        }
        return t
    }

    /// A running text with its gaps written "(n) ___" (or "(n) ø" for a printed example).
    private static func numberGaps(_ text: String, _ options: [String]) -> (String, [ExerciseGap]) {
        let toks = tokens(text)
        var out: [String] = []
        var gaps: [ExerciseGap] = []
        var k = 1
        var i = 0
        while i < toks.count {
            let t = toks[i]
            let next: String? = i + 1 < toks.count ? toks[i + 1] : nil
            // A number just before a blank may skip a gap the scan lost; the count follows the book.
            if let hit = gapNumber(t, k, slack: next == "___" ? maxLostGaps : 0) {
                k = hit.number
                if !hit.base.isEmpty { out.append(hit.base) }
                if next == "___" {
                    out.append("(\(k)) ___")
                    gaps.append(ExerciseGap(number: k))
                    k += 1
                    i += 2
                    continue
                }
                if hit.base.isEmpty, let n = next, let g = given(n, options) {
                    out.append("(\(k)) \(g)")
                    gaps.append(ExerciseGap(number: k, given: g))
                    k += 1
                    i += 2
                    continue
                }
                if !hit.base.isEmpty {
                    out.append("(\(k)) ___")
                    gaps.append(ExerciseGap(number: k))
                    k += 1
                    i += 1
                    continue
                }
                out.append(t)
                i += 1
                continue
            }
            if t == "___" {
                out.append("(\(k)) ___")
                gaps.append(ExerciseGap(number: k))
                k += 1
                i += 1
                continue
            }
            out.append(next == "___" ? stripMisread(t) : t)
            i += 1
        }
        return (out.joined(separator: " "), gaps)
    }

    private static func itemGaps(_ text: String, _ options: [String]) -> (String, [ExerciseGap]) {
        let toks = tokens(text)
        var gaps: [ExerciseGap] = []
        var out: [String] = []
        for (i, token) in toks.enumerated() {
            var t = token
            let next: String? = i + 1 < toks.count ? toks[i + 1] : nil
            if t == "___" {
                gaps.append(ExerciseGap(number: gaps.count + 1))
            } else if t == "ø" || t == "Ø" || ((t == "o" || t == "0") && options.contains("ø")) {
                gaps.append(ExerciseGap(number: gaps.count + 1, given: "ø"))
                t = "ø"
            } else if next == "___" {
                t = stripMisread(t)
            }
            out.append(t)
        }
        return (out.joined(separator: " "), gaps)
    }

    // MARK: Splitting

    private struct Draft {
        var number: Int
        var instruction: [String]
        var mode: Mode
        var items: [(number: Int, lines: [String])] = []
        var body: [String] = []
        var preface: [String] = []
        var box: [String]?
        var context: [String] = []

        enum Mode {
            case instruction, body, context
        }
    }

    static func split(_ text: String) -> [PageExercise] {
        let lines = text.components(separatedBy: .newlines).map(ReadingOrder.normalizeBlanks).filter { !$0.isEmpty }
        var pre: [String] = []
        var drafts: [Draft] = []
        for line in lines {
            if let g = groups(header, line), let n = Int(g[1]) {
                let rest = g[2]
                let current = drafts.last
                let expected = current.map { $0.number + 1 }
                if expected == nil || n == expected!, isInstruction(rest) {
                    let nextItem = current.flatMap { $0.items.last.map { $0.number + 1 } } ?? 1
                    let inItems = current.map { $0.mode == .body && !$0.items.isEmpty && n == nextItem } ?? false
                    if !inItems || isStrong(rest) {
                        let first = cleanHeader(rest)
                        drafts.append(Draft(number: n, instruction: [first], mode: endsSentence(first) ? .body : .instruction))
                        continue
                    }
                }
            }
            guard !drafts.isEmpty else {
                pre.append(line)
                continue
            }
            var d = drafts.removeLast()
            defer { drafts.append(d) }
            if d.mode == .instruction {
                if let g = groups(header, line), let n = Int(g[1]), n == 0 || n == 1 {
                    d.mode = .body
                } else if d.instruction.count < maxInstructionLines && !endsSentence(d.instruction.joined(separator: " ")) {
                    d.instruction.append(line)
                    if endsSentence(line) { d.mode = .body }
                    continue
                } else {
                    d.mode = .body
                }
            }
            if d.mode == .body {
                if isHeading(line) {
                    d.mode = .context
                    d.context.append(line)
                    continue
                }
                if let g = groups(header, line), let n = Int(g[1]) {
                    let want = d.items.last.map { $0.number + 1 }
                    if (want == nil && (n == 0 || n == 1)) || n == want {
                        if d.items.isEmpty && !d.body.isEmpty {
                            d.preface = d.body
                            d.body = []
                        }
                        d.items.append((number: n, lines: [g[2]]))
                        continue
                    }
                }
                if d.items.isEmpty && d.body.isEmpty && d.box == nil, let box = boxWords(line) {
                    d.box = box
                    continue
                }
                if d.items.isEmpty {
                    d.body.append(line)
                } else {
                    d.items[d.items.count - 1].lines.append(line)
                }
                continue
            }
            d.context.append(line)
        }
        let passage = pre.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return drafts.map { finish($0, passage: passage.isEmpty ? nil : passage) }
    }

    private static func finish(_ d: Draft, passage: String?) -> PageExercise {
        let instruction = withNoArticle(d.instruction.joined(separator: " ").trimmingCharacters(in: .whitespaces))
        var options = choices(instruction)
        if options.isEmpty, let box = d.box, found(rx(#"\b(?:box|below|list|kutu)"#, .caseInsensitive), instruction) {
            options = box
        }
        var items: [ExerciseItem] = []
        var running = false
        if !d.items.isEmpty {
            for (n, body) in d.items {
                let raw = withNoArticle(body.joined(separator: " ").trimmingCharacters(in: .whitespaces))
                let parts = QuestionSplitter.options(in: raw)
                if parts.options.count >= 2 {
                    items.append(ExerciseItem(number: n, text: parts.stem, options: parts.options))
                    continue
                }
                let (text, gaps) = itemGaps(raw, options)
                items.append(ExerciseItem(number: n, text: text, gaps: gaps))
            }
        } else if !d.body.isEmpty {
            let (text, gaps) = numberGaps(withNoArticle(d.body.joined(separator: " ")), options)
            if !gaps.isEmpty {
                items = [ExerciseItem(number: 0, text: text, gaps: gaps)]
                running = true
            }
        }
        let verbs = Set(words(instruction))
        let kind: PageExercise.Kind
        if items.contains(where: { !$0.options.isEmpty }) {
            kind = .options
        } else if items.contains(where: { !$0.gaps.isEmpty }) {
            kind = .gaps
        } else if verbs.isDisjoint(with: writeVerbs) && !found(turkishVerb, instruction) && options.isEmpty {
            kind = .skip
        } else if found(turkishSkip, instruction) && !found(turkishVerb, instruction) {
            kind = .skip
        } else {
            kind = .short
        }
        let context = withNoArticle((d.preface + d.context).joined(separator: " ").trimmingCharacters(in: .whitespaces))
        return PageExercise(number: d.number, instruction: instruction, kind: kind, choices: options, items: items,
                            running: running, context: context,
                            passage: found(passageCue, instruction) ? passage : nil)
    }

    // MARK: Solving

    private static let numberedBlank = #"\((\d+)\) ___"#

    private static func numbered(_ itemText: String) -> String {
        var k = 0
        return replace(#"(?<!\S)(___|ø)(?!\S)"#, in: itemText) { g in
            k += 1
            return "(\(k)) \(g[1])"
        }
    }

    /// The calls a model answers for an exercise, in order.
    static func units(_ e: PageExercise) -> [ExerciseUnit] {
        if e.kind == .skip { return [] }
        if e.running, let item = e.items.first {
            var out: [ExerciseUnit] = []
            var before = ""
            for sentence in sentences(item.text) {
                let r = rx(numberedBlank)
                let ns = sentence as NSString
                let numbers = r.matches(in: sentence, range: range(sentence)).compactMap { Int(ns.substring(with: $0.range(at: 1))) }
                let gaps = item.gaps.filter { numbers.contains($0.number) && $0.given == nil }
                if !gaps.isEmpty {
                    out.append(ExerciseUnit(number: 0, text: sentence, gaps: gaps, before: before))
                }
                before = sentence
            }
            return out
        }
        return e.items.filter { !$0.isExample }.map { item in
            if e.kind == .gaps && !item.gaps.isEmpty {
                return ExerciseUnit(number: item.number, text: numbered(item.text), gaps: item.gaps.filter { $0.given == nil })
            }
            return ExerciseUnit(number: item.number, text: item.text, gaps: [])
        }
    }

    /// "a" or "an" as the next word sounds; any other fill unchanged.
    static func article(_ fill: String, next: String) -> String {
        guard fill == "a" || fill == "an", !next.isEmpty else { return fill }
        let w = replace(rx(#"^[^\w]+|[^\w-]+$"#), in: next, with: "")
        guard let first = w.first else { return fill }
        if first.isWholeNumber {
            return found(rx(#"^(8|11|18|8\d)(?!\d)"#), w) ? "an" : "a"
        }
        if w.count > 1 && w.count <= 5 && w == w.uppercased() && w != w.lowercased() {
            return anLetters.contains(first) ? "an" : "a"
        }
        let low = w.lowercased()
        if anWords.contains(where: { low.hasPrefix($0) }) { return "an" }
        if aPrefixes.contains(where: { low.hasPrefix($0) }) { return "a" }
        return "aeiou".contains(low.first!) ? "an" : "a"
    }

    /// The text with its blanks ("(n) ___", "___") filled in order and a printed "ø" kept, a/an as the
    /// next word sounds; bold for showing, plain for the next prompt.
    static func fillText(_ text: String, fills: [String], choices: [String], bold: Bool = true) -> String {
        let toks = tokens(text)
        var queue = fills[...]
        var out: [String] = []
        var i = 0
        while i < toks.count {
            let t = toks[i]
            let isNumber = found(rx(#"^\(\d+\)$"#), t) && i + 1 < toks.count
            let j = isNumber ? i + 1 : i
            guard toks[j] == "___" || toks[j] == "ø" else {
                out.append(t)
                i += 1
                continue
            }
            var fill: String? = toks[j] == "ø" ? "ø" : queue.popFirst()
            let after = j + 1 < toks.count ? toks[j + 1] : ""
            if let f = fill, choices.contains("a") && choices.contains("an") {
                fill = article(f, next: after)
            }
            let shown: String
            if let f = fill, !f.isEmpty {
                shown = bold ? "**\(f)**" : f
            } else {
                shown = bold ? "**?**" : "___"
            }
            out.append(isNumber ? "\(t) \(shown)" : shown)
            i = j + 1
        }
        return out.joined(separator: " ")
    }

    /// A running sentence with the gaps already answered written in ("(7) the").
    static func fillNumbered(_ text: String, known: [Int: String]) -> String {
        replace(numberedBlank, in: text) { g in
            guard let n = Int(g[1]), let fill = known[n] else { return g[0] }
            return "(\(n)) \(fill)"
        }
    }

    /// What a small model reads for one unit: the instruction, what it needs to know, the unit.
    static func unitPrompt(_ e: PageExercise, _ u: ExerciseUnit, before: String) -> String {
        var lines = ["Exercise: \(e.instruction)"]
        if !e.context.isEmpty { lines.append("Notes: " + String(e.context.prefix(contextChars))) }
        if u.gaps.isEmpty {
            if let passage = e.passage { lines.append("Text: " + String(passage.prefix(passageChars))) }
            lines.append("Item \(u.number): \(u.text)")
            lines.append(e.choices.isEmpty ? "Answer briefly." : "Answer with exactly one of: " + e.choices.joined(separator: ", ") + ".")
            return lines.joined(separator: "\n")
        }
        if !before.isEmpty { lines.append("Previous sentence: " + before) }
        lines.append("Sentence: " + u.text)
        let names = u.gaps.map { "(\($0.number))" }.joined(separator: ", ")
        var tail = u.gaps.count > 1 ? "Fill the gaps \(names) in this order." : "Fill the gap \(names)."
        if !e.choices.isEmpty { tail += " Each fill is exactly one of: " + e.choices.joined(separator: ", ") + "." }
        if e.choices.contains("ø") { tail += " ø means the gap stays empty." }
        lines.append(tail)
        return lines.joined(separator: "\n")
    }

    /// The whole exercise for a model strong enough to answer it at once.
    static func exercisePrompt(_ e: PageExercise) -> String {
        var lines = ["Exercise \(e.number): \(e.instruction)"]
        if !e.choices.isEmpty {
            lines.append("Words to use: " + e.choices.joined(separator: ", ")
                + (e.choices.contains("ø") ? " (ø means the gap stays empty)" : ""))
        }
        if !e.context.isEmpty { lines.append("Notes: " + String(e.context.prefix(contextChars))) }
        if let passage = e.passage { lines.append("Text: " + String(passage.prefix(passageChars))) }
        if e.running, let item = e.items.first {
            lines.append(item.text)
        } else {
            for item in e.items {
                var line = "\(item.number). " + (item.gaps.isEmpty ? item.text : numbered(item.text))
                    + (item.isExample ? " (example)" : "")
                for o in item.options { line += "\n\(o.letter)) \(o.text)" }
                lines.append(line)
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Markdown: the exercise number and instruction, then each item with its answers. `fills` holds,
    /// per item (0 for a running text), the fills of its open gaps in order, or a short answer.
    static func render(_ e: PageExercise, fills: [Int: [String]], notes: [Int: String] = [:],
                       skipped: String = "Konuşma/dinleme alıştırması, atlandı.") -> String {
        let head = "**\(e.number)** \(e.instruction)"
        if e.kind == .skip { return head + "\n_\(skipped)_\n\n" }
        var out = [head]
        if e.running, let item = e.items.first {
            out.append(fillText(item.text, fills: fills[0] ?? [], choices: e.choices))
        } else {
            for item in e.items where !item.isExample {
                let got = fills[item.number] ?? []
                if e.kind == .gaps && !item.gaps.isEmpty {
                    out.append("\(item.number). " + fillText(item.text, fills: got, choices: e.choices))
                } else {
                    var answer = got.first ?? "?"
                    let letter = answer.trimmingCharacters(in: CharacterSet(charactersIn: " *().:")).lowercased()
                    if let o = item.options.first(where: { String($0.letter).lowercased() == letter }) {
                        answer = "\(o.letter)) \(o.text)"
                    }
                    out.append("\(item.number). \(item.text) — **\(answer)**")
                }
                if let note = notes[item.number], !note.isEmpty { out.append("_\(note)_") }
            }
        }
        return out.joined(separator: "\n") + "\n\n"
    }
}
