import Foundation

/// One option of a multiple-choice question.
struct QuestionOption: Equatable {
    var letter: Character
    var text: String
}

/// One question of a page: its number, its stem, its options and the passage it refers to.
struct PageQuestion: Equatable {
    var number: Int
    var stem: String
    var options: [QuestionOption]
    var passage: String?

    /// The question as a model reads it.
    var promptText: String {
        var s = ""
        if let passage, !passage.isEmpty { s += passage + "\n\n" }
        s += "\(number). \(stem)"
        for o in options { s += "\n\(o.letter)) \(o.text)" }
        return s
    }
}

/// The questions of a page (text layer or OCR), so a small model can solve one at a time (twin of
/// tests/ports/questions.py).
///
/// A question starts on a line "N.", "N)" or "(N)" whose N follows the previous question's number (the
/// first one may be any number; OCR's "l." or "I." counts as 1 when a "2." follows). Numbered lines
/// that break the count stay inside the question. A directive ("3. - 5. soruları …", "Questions 1-2
/// refer to …") starts a passage that belongs to the questions it names. Options are markers A) B) C)
/// D) (E) in order, also several on one line, also "(A)" and "A."; fewer than two means an open question.
enum QuestionSplitter {
    private static let question = try! NSRegularExpression(pattern: #"^\s*\(?(\d{1,2}|[lI])\s*[.)]\s+(\S.*)$"#)
    private static let directives = [
        try! NSRegularExpression(pattern: #"^\s*(\d{1,2})\s*\.?\s*(?:-|–|ve|ile)\s*(\d{1,2})\s*\.?\s*sorular"#,
                                 options: [.caseInsensitive]),
        try! NSRegularExpression(pattern: #"^\s*questions?\s+(\d{1,2})\s*(?:-|–|and|to)\s*(\d{1,2})"#,
                                 options: [.caseInsensitive]),
    ]
    private static let option = try! NSRegularExpression(pattern: #"(?:(?<=\s)|^)[(]?([A-Ea-e])\s*[).\]]\s+"#)
    private static let secondQuestion = try! NSRegularExpression(pattern: #"^\s*\(?2\s*[.)]\s+\S"#)
    /// Text before the first question counts as a shared passage only when it is this long.
    private static let passageMinLetters = 120

    /// The capture groups of the first match, nil without a match.
    private static func groups(_ rx: NSRegularExpression, _ s: String) -> [String]? {
        let ns = s as NSString
        guard let m = rx.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (1..<max(m.numberOfRanges, 1)).map { i in
            let r = m.range(at: i)
            return r.location == NSNotFound ? "" : ns.substring(with: r)
        }
    }

    private static func directiveRange(_ line: String) -> (first: Int, last: Int)? {
        for rx in directives {
            if let g = groups(rx, line), g.count == 2, let a = Int(g[0]), let b = Int(g[1]) {
                return (first: a, last: b)
            }
        }
        return nil
    }

    private static func number(_ token: String, expected: Int?, rest: ArraySlice<String>) -> Int? {
        if token == "l" || token == "I" {
            // OCR reads "1." as "l." or "I.": only the first question, and only when a "2." follows.
            guard expected == nil || expected == 1 else { return nil }
            return rest.contains { groups(secondQuestion, $0) != nil } ? 1 : nil
        }
        guard let n = Int(token) else { return nil }
        return expected == nil || n == expected ? n : nil
    }

    private static func nextLetter(_ s: String) -> String {
        guard let u = s.unicodeScalars.first, let n = Unicode.Scalar(u.value + 1) else { return "" }
        return String(Character(n))
    }

    /// The stem and the options of one question's text.
    static func options(in text: String) -> (stem: String, options: [QuestionOption]) {
        let ns = text as NSString
        let marks = option.matches(in: text, range: NSRange(location: 0, length: ns.length))
        var best: [NSTextCheckingResult] = []
        for (i, m) in marks.enumerated() {
            let letter = ns.substring(with: m.range(at: 1))
            guard letter == "A" || letter == "a" else { continue }
            var run = [m]
            var want = nextLetter(letter)
            for later in marks[(i + 1)...] where ns.substring(with: later.range(at: 1)) == want {
                run.append(later)
                want = nextLetter(want)
            }
            if run.count >= best.count { best = run }
        }
        let whole = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard best.count >= 2 else { return (stem: whole, options: []) }
        let stem = ns.substring(to: best[0].range.location).trimmingCharacters(in: .whitespacesAndNewlines)
        var out: [QuestionOption] = []
        for (k, m) in best.enumerated() {
            let start = m.range.location + m.range.length
            let end = k + 1 < best.count ? best[k + 1].range.location : ns.length
            let body = ns.substring(with: NSRange(location: start, length: max(end - start, 0)))
            let letter = Character(ns.substring(with: m.range(at: 1)))
            out.append(QuestionOption(letter: letter, text: body.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        return (stem: stem, options: out)
    }

    static func split(_ text: String) -> [PageQuestion] {
        let lines = text.components(separatedBy: .newlines)
        var blocks: [(number: Int, lines: [String])] = []
        var before: [String] = []
        var reading: (first: Int, last: Int, lines: [String])?
        var passages: [Int: String] = [:]
        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            if let d = directiveRange(line) {
                reading = (first: d.first, last: d.last, lines: [])
                continue
            }
            let expected = blocks.last.map { $0.number + 1 }
            if let g = groups(question, line), g.count == 2,
               let n = number(g[0], expected: expected, rest: lines[(i + 1)...]) {
                if let r = reading, n == r.first {
                    let body = r.lines.joined(separator: " ").trimmingCharacters(in: .whitespaces)
                    if r.first <= r.last {
                        for k in r.first...r.last { passages[k] = body }
                    }
                    reading = nil
                }
                blocks.append((number: n, lines: [g[1]]))
                continue
            }
            if var r = reading {
                r.lines.append(trimmed)
                reading = r
            } else if !blocks.isEmpty {
                blocks[blocks.count - 1].lines.append(trimmed)
            } else {
                before.append(trimmed)
            }
        }
        let shared = before.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        let sharedPassage: String? = shared.filter(\.isLetter).count >= passageMinLetters ? shared : nil
        return blocks.map { block in
            let parts = options(in: block.lines.joined(separator: " "))
            return PageQuestion(number: block.number, stem: parts.stem, options: parts.options,
                                passage: passages[block.number] ?? sharedPassage)
        }
    }
}

/// How a model is asked to solve one question, and how its answer is shown.
enum QuestionSolving {
    /// For models that answer in free text (the local server).
    static func instructions(language: AnswerLanguage) -> String {
        "Sen dikkatli bir sınav öğretmenisin. Soruyu ve varsa parçayı oku, şıkları tek tek değerlendir. Önce doğru şıkkın harfini kalın yaz (örneğin **C**), sonra en fazla üç cümleyle gerekçesini açıkla. Parçada olmayan bilgiyi uydurma; matematikte işlemleri adım adım yap. "
            + language.directive
    }

    /// For the downloaded model, which thinks before it writes: a short reason, then the choice alone
    /// on the last line, where `ThinkingText.choice` reads it.
    static func brainInstructions(language: AnswerLanguage) -> String {
        "Sen dikkatli bir sınav öğretmenisin. Soruyu ve varsa parçayı dikkatle oku. Düşünürken her şıkkı tek tek değerlendir; matematikte işlemleri adım adım yap ve bulduğun sonucu soruda yerine koyarak kontrol et. Parçada olmayan bilgiyi uydurma. Düşünmen bitince en fazla üç cümlelik kısa bir gerekçe yaz, son satıra da yalnızca \"Cevap: X\" yaz (X doğru şıkkın harfi). Şık yoksa son satıra \"Cevap:\" ve kısa sonucu yaz. "
            + language.directive
    }

    /// For the downloaded model on a worded math question with no options (an inequality, an equation,
    /// blanks to fill): the working and every check happen while it thinks, and the answer is the
    /// clean result a textbook prints — "Cevap:" first, a few steps, no LaTeX, no second thoughts.
    static func mathInstructions(language: AnswerLanguage) -> String {
        "Sen titiz bir matematik öğretmenisin. Soruyu dikkatle oku; metin bir sayfadan okundu, OCR hatası ya da kaybolmuş boşluk olabilir (\"a = ____ ve b = ____\" iki boşluk demektir, ikisini de doldur). Bütün hesabı ve kontrolü düşünürken yap: her adımı doğrula, bulduğun sonucu soruda yerine koy, kararsızlığı düşünürken bitir. Düşünmen bitince yalnızca son hâli yaz: ilk satıra \"Cevap: …\" ve kesin sonuç, altına en fazla üç kısa adım (madde madde). Yazdığın cevapta tereddüt, düzeltme, ikinci deneme ya da OCR yorumu olmasın (\"dur\", \"aslında\", \"düzeltme\", \"wait\", \"correction\" yazma). LaTeX kullanma ($, \\frac, \\le, \\sqrt yazma); matematiği düz metin ve Unicode ile yaz: ≤ ≥ ≠ × ÷ √ ² ³ π ∞, kesir (−15 + 7)/2, mutlak değer |x − 2|, aralık [2, ∞). "
            + language.directive
    }

    /// Put under the question when the model's first answer failed the engine's check, so the second
    /// try starts from what substitution showed.
    static func retryNote(reason: String, hint: String?, language: AnswerLanguage) -> String {
        var s = language == .english
            ? "YOUR FIRST ANSWER WAS WRONG: " + reason + "."
            : "İLK CEVABIN YANLIŞTI: " + reason + "."
        if let hint {
            s += language == .english
                ? " By substitution the math engine finds that \(hint) satisfies the equation; solve again towards that and check every case."
                : " Hesap motoru yerine koyarak \(hint) değerinin denklemi sağladığını buldu; çözümü buna göre yeniden yap ve her durumu kontrol et."
        } else {
            s += language == .english ? " Solve again and check every case by substitution." : " Yeniden çöz ve her durumu yerine koyarak kontrol et."
        }
        return s
    }

    /// Added to the assistant's instructions when it solves a whole page in one answer.
    static let pageSolvingRules = "SAYFA ÇÖZÜMÜ: Her soru için ayrı bir blok yaz: numarası, ilk satırda kalın kesin sonuç, altında en fazla üç kısa adım. Bütün hesabı ve kontrolü düşünürken bitir; yazdığın cevapta tereddüt, düzeltme, ikinci deneme ya da OCR yorumu olmasın. Metindeki \"a = ____\" gibi boşluklar doldurulacak yerlerdir. LaTeX yazma; ≤ ≥ √ ² gibi Unicode kullan."

    private static let finalLine = try! NSRegularExpression(
        pattern: #"^[\s*_#>-]*(?:cevap|yan[ıi]t|answer|sonu[çc]|result)\s*[:：]\s*(.+?)\s*$"#, options: [.caseInsensitive])

    /// What a "Cevap: …" / "Answer: …" line states, without its emphasis; nil for any other line.
    static func finalAnswer(in line: String) -> String? {
        let ns = line as NSString
        guard let m = finalLine.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let answer = ns.substring(with: m.range(at: 1)).replacingOccurrences(of: "**", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "*_ "))
        return answer.isEmpty ? nil : answer
    }

    /// The last "Cevap:"/"Answer:" line of a whole answer; nil when it has none.
    static func finalAnswer(of answer: String) -> String? {
        answer.components(separatedBy: "\n").compactMap(finalAnswer(in:)).last
    }

    /// The steps as one block: a line already written is not written again (a small model sometimes
    /// repeats its whole list), and blank lines do not pile up.
    static func stepsBody(_ lines: [String]) -> String {
        var seen = Set<String>()
        var out: [String] = []
        for line in lines {
            let key = line.trimmingCharacters(in: .whitespaces)
            if key.isEmpty {
                if out.last?.trimmingCharacters(in: .whitespaces).isEmpty == false { out.append("") }
            } else if seen.insert(key).inserted {
                out.append(line)
            }
        }
        return out.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// "**3)** **Cevap: −4 < x < 8**" and the steps under it: the last "Cevap:"/"Answer:" line of the
    /// answer comes first, the other lines follow as the steps. A `note` (the engine's check failing)
    /// is shown after the answer, so a number the engine could not confirm is never stated as fact.
    static func openLine(_ q: PageQuestion, answer: String, language: AnswerLanguage, note: String? = nil) -> String {
        var final: String?
        var steps: [String] = []
        for line in answer.components(separatedBy: "\n") {
            if let a = finalAnswer(in: line) {
                final = a
            } else {
                steps.append(line)
            }
        }
        let body = stepsBody(steps)
        var head = "**\(q.number))** "
        guard let final else { return head + body + "\n\n" }
        head += "**\(language == .english ? "Answer" : "Cevap"): \(final)**"
        if let note { head += " ⚠️ " + note }
        return head + (body.isEmpty ? "" : "\n" + body) + "\n\n"
    }

    /// "**3)** **Cevap: x = −7/4**" from the math engine, with the engine's own working under it.
    static func engineLine(_ q: PageQuestion, answer: String, steps: [String], language: AnswerLanguage) -> String {
        let body = stepsBody(steps.filter { finalAnswer(in: $0) == nil })
        let head = "**\(q.number))** **\(language == .english ? "Answer" : "Cevap"): \(answer)**"
        return head + (body.isEmpty ? "" : "\n" + body) + "\n\n"
    }

    /// For models that answer a whole textbook exercise at once (the local server).
    static func exerciseInstructions(language: AnswerLanguage) -> String {
        "Sen dikkatli bir öğretmensin. Alıştırmanın yönergesini ve varsa notlarını oku, maddeleri sırayla çöz. Boşluklu her maddeyi numarasıyla, boşlukları doldurulmuş tam cümle olarak yaz ve doldurduğun kelimeleri kalın yaz (örneğin **the**). Kullanılacak kelimeler verilmişse yalnızca onları kullan; ø boşluğun boş kalacağı anlamına gelir. Diğer maddelerde kısa cevabı kalın yaz ve bir cümleyle gerekçesini ekle. Şık harfi yalnızca maddenin şıkları varsa yaz. "
            + language.directive
    }

    /// "**3)** **C** — the option's text" and the reasoning under it.
    static func line(_ q: PageQuestion, answer: String, reasoning: String) -> String {
        let a = answer.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "*().: "))
        var head = "**\(q.number))** "
        if a.count == 1, let option = q.options.first(where: { String($0.letter).uppercased() == a.uppercased() }) {
            head += "**\(option.letter)** — \(option.text)"
        } else {
            head += "**\(a)**"
        }
        let why = reasoning.trimmingCharacters(in: .whitespacesAndNewlines)
        return head + (why.isEmpty ? "" : "\n" + why) + "\n\n"
    }
}
