import Foundation
import UIKit

/// A word of the chosen reading that the word list does not know is swapped for a known word one
/// letter away (two from five letters on) when the readers find the swap almost as likely: their
/// summed log P may drop by at most `perReader` per reader (twin of tests/ports/wordfix.py). Both
/// readers can be sure of a wrong letter ("becavse": a hand whose u is pointed); the word list knows
/// "because" one letter away. Short words, words next to an apostrophe (37'sini, Ankara'da, isn't)
/// and words with more than one capital are left alone, and so are formulas (an "=" or two operators); a line with
/// numbers is still prose ("Sınavda 40 sorunun 37'sini").
///
/// The word list (wordlist.dataset, from ml/handwriting/lexicon.py) holds Tatoeba's Turkish and
/// English word forms seen at least `knownMin` times; swaps come from forms seen at least `swapMin`
/// times, tried shortest first and in the list's order.
enum WordFix {
    static let knownMin = 2
    static let swapMin = 3
    static let perReader: Float = 7

    struct Lexicon {
        private(set) var known: Set<String> = []
        private(set) var byLength: [Int: [(word: String, scalars: [UInt32])]] = [:]

        /// Lines of "word count", most frequent first.
        init(text: String) {
            for line in text.split(separator: "\n") {
                let parts = line.split(separator: " ")
                guard parts.count == 2, let n = Int(parts[1]) else { continue }
                let word = String(parts[0])
                if n >= WordFix.knownMin { known.insert(word) }
                if n >= WordFix.swapMin {
                    let scalars = word.unicodeScalars.map(\.value)
                    byLength[scalars.count, default: []].append((word, scalars))
                }
            }
        }

        func knows(_ word: String) -> Bool {
            known.contains(WordFix.lowerTR(word)) || known.contains(WordFix.lowerEN(word))
        }
    }

    static let shared: Lexicon? = {
        guard let asset = NSDataAsset(name: "wordlist"), let text = String(data: asset.data, encoding: .utf8) else { return nil }
        return Lexicon(text: text)
    }()

    /// A formula, which keeps its letters as read: an "=" or at least two operators.
    static func isFormula(_ text: String) -> Bool {
        text.contains("=") || text.filter { "+-−×÷*/^√<>±".contains($0) }.count >= 2
    }

    static func lowerTR(_ w: String) -> String {
        w.replacingOccurrences(of: "I", with: "ı").replacingOccurrences(of: "İ", with: "i").lowercased()
    }

    static func lowerEN(_ w: String) -> String {
        w.replacingOccurrences(of: "İ", with: "i").lowercased()
    }

    /// `text` with its unknown words swapped; `score` gives the readers' summed log P of a text.
    static func fix(_ text: String, readers: Int, lexicon: Lexicon, score: (String) -> Float?) -> String {
        guard var base = score(text) else { return text }
        let limit = perReader * Float(readers)
        let chars = Array(text)
        var runs: [Range<Int>] = []
        var i = 0
        while i < chars.count {
            guard chars[i].isLetter else {
                i += 1
                continue
            }
            var j = i
            while j < chars.count, chars[j].isLetter { j += 1 }
            runs.append(i..<j)
            i = j
        }
        // Right to left, so the runs still to come keep their places.
        var out = chars
        for run in runs.reversed() {
            let word = String(chars[run])
            guard word.unicodeScalars.count >= 3, word.filter(\.isUppercase).count <= 1, !lexicon.knows(word) else { continue }
            if run.lowerBound > 0, "'’".contains(chars[run.lowerBound - 1]) { continue }
            if run.upperBound < chars.count, "'’".contains(chars[run.upperBound]) { continue }
            var best: String?
            var bestDrop: Float = 0
            for candidate in near(word, lexicon) {
                let swap = cased(candidate, like: word)
                var trial = out
                trial.replaceSubrange(run, with: Array(swap))
                guard let s = score(String(trial)) else { continue }
                if best == nil || s - base > bestDrop {
                    best = swap
                    bestDrop = s - base
                }
            }
            if let best, bestDrop >= -limit {
                out.replaceSubrange(run, with: Array(best))
                base = score(String(out)) ?? base
            }
        }
        return String(out)
    }

    /// Known words one edit from `word` (two from five letters on), shortest first.
    static func near(_ word: String, _ lexicon: Lexicon) -> [String] {
        let n = word.unicodeScalars.count
        let cap = n <= 4 ? 1 : 2
        let forms = Set([lowerTR(word), lowerEN(word)]).map { $0.unicodeScalars.map(\.value) }
        var out: [String] = []
        for length in (n - cap)...(n + cap) {
            for entry in lexicon.byLength[length] ?? [] where forms.contains(where: { distance($0, entry.scalars, cap: cap) <= cap }) {
                out.append(entry.word)
            }
        }
        return out
    }

    /// Levenshtein distance, or cap + 1 once it is sure to pass cap.
    static func distance(_ a: [UInt32], _ b: [UInt32], cap: Int) -> Int {
        if abs(a.count - b.count) > cap { return cap + 1 }
        var prev = Array(0...b.count)
        var cur = [Int](repeating: 0, count: b.count + 1)
        for (i, ca) in a.enumerated() {
            cur[0] = i + 1
            var low = i + 1
            for (j, cb) in b.enumerated() {
                cur[j + 1] = min(prev[j + 1] + 1, cur[j] + 1, prev[j] + (ca == cb ? 0 : 1))
                low = min(low, cur[j + 1])
            }
            if low > cap { return cap + 1 }
            swap(&prev, &cur)
        }
        return prev[b.count]
    }

    /// The known word written like `word`: its capital first letter stays a capital.
    static func cased(_ known: String, like word: String) -> String {
        guard let first = word.first, first.isUppercase, let k = known.first else { return known }
        let head = String(first)
        if lowerTR(head) == String(k) || lowerEN(head) == String(k) { return head + known.dropFirst() }
        if k == "i" { return (known.contains(where: { "çğışöü".contains($0) }) ? "İ" : "I") + known.dropFirst() }
        return lowerEN(String(k)).uppercased() + known.dropFirst()
    }
}
