import UIKit

/// Word knowledge from the system's Turkish and English spelling dictionaries, used to read
/// handwriting well. Vision can read Turkish without its letters (ş → s, ı → i, ğ → g…) or pick a
/// wrong reading of a word; the dictionaries choose the reading made of real words and put the
/// Turkish letters back. Math lines are never touched.
@MainActor
enum Spelling {
    private static let checker = UITextChecker()
    private static let turkish: String? = UITextChecker.availableLanguages.first { $0.hasPrefix("tr") }
    private static let english: String? = UITextChecker.availableLanguages.first { $0.hasPrefix("en") }
    private static let tr = Locale(identifier: "tr_TR")

    /// The most plausible reading of every line, with Turkish letters restored.
    static func polish(_ lines: [OCRLine]) -> [OCRLine] {
        lines.map { (line: OCRLine) -> OCRLine in
            guard !isMath(line.text) else { return line }
            var options: [(text: String, words: [OCRWord])] = [(line.text, line.words)]
            options += line.alternatives.prefix(5).map { (text: $0.text, words: $0.words) }
            // Readings are compared after repair, so "kucuk" and "küçük" count the same.
            var best = options[0]
            var bestText = repair(best.text)
            var bestScore = score(bestText)
            for option in options.dropFirst() where !isMath(option.text) {
                // Scores stop at 1: once the bar is there no other reading can win, and the
                // dictionary lookups (on the main thread) are skipped.
                if bestScore + 0.15 >= 1 { break }
                let text = repair(option.text)
                let s = score(text)
                // Another reading must be clearly better made of real words to replace the first one.
                if s > bestScore + 0.15 {
                    best = option
                    bestText = text
                    bestScore = s
                }
            }
            var out = line
            out.text = bestText
            out.words = best.words.map { OCRWord(text: repair($0.text), box: $0.box) }
            return out
        }
    }

    /// Fraction of the line's words that the Turkish or English dictionary knows.
    static func score(_ text: String) -> Double {
        let words = letterWords(text).filter { $0.count >= 2 }
        guard !words.isEmpty else { return 0 }
        let known = words.filter { isKnown($0, turkish) || isKnown($0, english) }.count
        return Double(known) / Double(words.count)
    }

    /// Restores missing Turkish letters word by word; anything else stays as written.
    static func repair(_ text: String) -> String {
        var out = ""
        var token = ""
        for ch in text {
            if ch.isWhitespace {
                out += repairToken(token)
                token = ""
                out.append(ch)
            } else {
                token.append(ch)
            }
        }
        out += repairToken(token)
        return out
    }

    /// One space-separated piece: digits that are really letters first ("b0yut" → "boyut"), then
    /// every run of letters on its own.
    private static func repairToken(_ token: String) -> String {
        guard !token.isEmpty else { return token }
        let fixed = digitsAsLetters(token) ?? token
        var out = ""
        var word = ""
        for ch in fixed {
            if ch.isLetter {
                word.append(ch)
            } else {
                if !word.isEmpty { out += repairWord(word) }
                word = ""
                out.append(ch)
            }
        }
        if !word.isEmpty { out += repairWord(word) }
        return out
    }

    /// Letters Vision often reads as digits in handwriting.
    private static let digitLetters: [Character: [Character]] = [
        "0": ["o"], "1": ["l", "ı", "i"], "5": ["s"], "6": ["b"], "8": ["B"], "9": ["g"], "2": ["z"]
    ]

    /// A word with one or two stray digits that becomes a real word when they are read as letters.
    /// Numbers, units and codes ("H2O", "3x", "COVID19") stay as they are.
    private static func digitsAsLetters(_ token: String) -> String? {
        let chars = Array(token)
        let digitSpots = chars.indices.filter { chars[$0].isNumber }
        let letterCount = chars.filter(\.isLetter).count
        guard !digitSpots.isEmpty, digitSpots.count <= 2, letterCount >= 2, letterCount > digitSpots.count * 2,
              digitSpots.allSatisfy({ digitLetters[chars[$0]] != nil }),
              chars.allSatisfy({ $0.isLetter || $0.isNumber || ".,;:!?'\"()".contains($0) }) else { return nil }
        var tries: [[Character]] = [chars]
        for spot in digitSpots {
            tries = tries.flatMap { t in
                (digitLetters[t[spot]] ?? []).map { letter -> [Character] in
                    var c = t
                    // Keep the case of the word around it.
                    let upper = letterCount > 1 && chars.filter(\.isLetter).allSatisfy(\.isUppercase)
                    c[spot] = upper ? Character(String(letter).uppercased(with: tr)) : letter
                    return c
                }
            }
        }
        for t in tries {
            let candidate = String(t)
            let core = candidate.filter(\.isLetter)
            if isKnown(core, turkish) || isKnown(core, english) { return candidate }
        }
        return nil
    }

    /// Repaired words, so the readings of a line (which share most words) ask the dictionary once.
    private static var memo: [String: String] = [:]

    private static func repairWord(_ core: String) -> String {
        if let known = memo[core] { return known }
        let fixed = freshRepair(core)
        if memo.count > 4000 { memo.removeAll() }
        memo[core] = fixed
        return fixed
    }

    private static func freshRepair(_ core: String) -> String {
        guard core.count >= 3, let turkish else { return core }
        if isKnown(core, turkish) { return core }
        let ns = core as NSString
        let guesses = checker.guesses(forWordRange: NSRange(location: 0, length: ns.length), in: core, language: turkish) ?? []
        let folded = fold(core)
        // The same letters with Turkish marks: "kucuk" → "küçük", "isik" → "ışık".
        if let guess = guesses.first(where: { fold($0) == folded }) {
            return matchCase(guess, like: core)
        }
        if isKnown(core, english) { return core }
        // One misread letter in a longer word ("kitab" → "kitap").
        if core.count >= 5, let guess = guesses.first, distance(fold(guess), folded) <= 1 {
            return matchCase(guess, like: core)
        }
        return core
    }

    private static func isKnown(_ word: String, _ language: String?) -> Bool {
        guard let language else { return false }
        let range = NSRange(location: 0, length: (word as NSString).length)
        return checker.rangeOfMisspelledWord(in: word, range: range, startingAt: 0, wrap: false, language: language).location == NSNotFound
    }

    private static func letterWords(_ text: String) -> [String] {
        text.split(whereSeparator: { !$0.isLetter }).map(String.init)
    }

    private static func isMath(_ text: String) -> Bool {
        PageOCR.mathScore(text) >= 2 || text.contains("=")
    }

    /// Lowercase without Turkish marks, for comparing readings.
    private static func fold(_ s: String) -> String {
        var t = s.lowercased(with: tr)
        for (a, b) in [("ç", "c"), ("ğ", "g"), ("ı", "i"), ("ö", "o"), ("ş", "s"), ("ü", "u"), ("â", "a"), ("î", "i"), ("û", "u")] {
            t = t.replacingOccurrences(of: a, with: b)
        }
        return t
    }

    private static func matchCase(_ guess: String, like original: String) -> String {
        let letters = original.filter(\.isLetter)
        if letters.count > 1, letters == letters.uppercased(with: tr) {
            return guess.uppercased(with: tr)
        }
        if let first = original.first, first.isUppercase, let g = guess.first {
            return String(g).uppercased(with: tr) + guess.dropFirst()
        }
        return guess
    }

    private static func distance(_ a: String, _ b: String) -> Int {
        let x = Array(a)
        let y = Array(b)
        guard !x.isEmpty else { return y.count }
        guard !y.isEmpty else { return x.count }
        var previous = Array(0...y.count)
        for i in 1...x.count {
            var current = [i] + Array(repeating: 0, count: y.count)
            for j in 1...y.count {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (x[i - 1] == y[j - 1] ? 0 : 1))
            }
            previous = current
        }
        return previous[y.count]
    }
}
