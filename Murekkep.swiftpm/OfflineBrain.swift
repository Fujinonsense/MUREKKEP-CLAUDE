import Foundation
import NaturalLanguage

/// Rule-based assistant that works on every device without a model, a key or a network:
/// extractive summaries, key terms, fill-in-the-blank quizzes, formula lists, arithmetic
/// checking of handwritten solutions and sentence search inside the pages.
enum OfflineBrain {
    struct Sentence {
        let text: String
        let page: Int
        let order: Int
        let stems: [String]
        /// Where it was found ("s. 3" or "Other note · s. 3").
        var label: String = ""
    }

    static var emptyMessage: String { L("Bu sayfada henüz yazı yok. Bir soru ya da işlem yaz, hemen çözeyim.", "There is no writing on this page yet. Write a question or a calculation and I will solve it.") }

    static func answer(question: String, action: QuickAction?, pages: [PageText], currentPage: Int,
                       web: [WebSource], definitions: [String: WebSource]) -> String {
        switch action {
        case .solve?:
            return solvePage(pages, current: currentPage, web: web)
        case .summarize?:
            return summary(pages)
        case .explain?:
            return explain(pages, current: currentPage, definitions: definitions)
        case .quiz?:
            return quiz(pages)
        case .check?:
            return check(pages, current: currentPage)
        case .formulas?:
            return formulas(pages)
        case nil:
            return freeAnswer(question, pages: pages, web: web, current: currentPage)
        }
    }

    // MARK: - Math on the page

    /// Lines of the current page (handwriting first), falling back to every page in scope.
    static func mathLines(_ pages: [PageText], current: Int) -> [String] {
        let here = pages.filter { $0.page == current }
        let source = here.isEmpty ? pages : here
        return source.flatMap { $0.text.components(separatedBy: .newlines) }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Exact results for every math line of the page, for the language models to rely on: the
    /// calculations and equations the engine reads, and the worded questions it solves exactly
    /// ("Solve |4x + 23| = |4x − 9|" → x = −7/4).
    static func mathFacts(_ pages: [PageText], current: Int) -> String {
        let lines = mathLines(pages, current: current)
        var facts: [String] = []
        for line in lines {
            if let finding = MathEngine.analyze(line) {
                facts.append("- " + MathFormat.describe(finding))
            } else if let exact = ExactMath.solve(line) {
                facts.append("- `\(exact.given)` → **\(exact.answer)**")
            }
        }
        if let system = MathEngine.solveSystem(lines) {
            facts.append("- " + describe(system))
        }
        return facts.joined(separator: "\n")
    }

    static func describe(_ system: MathSystemSolution) -> String {
        let eqs = system.equations.map { "`\($0)`" }.joined(separator: ", ")
        let values = zip(system.variables, system.values).map { "\($0) = \(MathFormat.number($1))" }.joined(separator: ", ")
        return L("Denklem sistemi", "System of equations") + " \(eqs) → **\(values)**"
    }

    /// Solves everything on the page: arithmetic, true/false claims, equations, systems and,
    /// as far as the notes allow, word questions.
    static func solvePage(_ pages: [PageText], current: Int, web: [WebSource]) -> String {
        let lines = mathLines(pages, current: current)
        guard !lines.isEmpty else { return emptyMessage }
        var items: [String] = []
        var mathLineSet = Set<String>()
        for line in lines {
            guard let finding = MathEngine.analyze(line) else { continue }
            mathLineSet.insert(line)
            if case let .claim(text, holds, left, _, _) = finding {
                items.append(holds ? "✓ `\(text)` " + L("doğru", "is correct") : "✗ `\(text)` " + L("yanlış, doğrusu", "is wrong; the correct value is") + " **\(MathFormat.number(left))**")
            } else {
                items.append(MathFormat.describe(finding))
            }
        }
        if let system = MathEngine.solveSystem(lines) {
            items.append(describe(system))
        }
        let questionWords = ["nedir", "nelerdir", "nasıl", "neden", "niçin", "hangi", "kimdir", "açıklayınız",
                             "açıkla", "tanımla", "tanımlayınız", "what", "why", "how"]
        let sents = sentences(from: pages)
        for line in lines where !mathLineSet.contains(line) {
            let lower = line.lowercased(with: trLocale)
            guard line.contains("?") || questionWords.contains(where: { lower.contains($0) }) else { continue }
            if let best = rankedSentences(for: line, in: sents).first(where: { $0.text != line }) {
                items.append("**\(line)** → \(best.text) _(\(best.label))_")
            } else if let w = web.first {
                items.append("**\(line)** → \(w.snippet) [1]")
            } else {
                items.append("**\(line)** → " + L("Soruyu okudum ama cevabı notlarında yok. Sözel sorular için Ayarlar'dan yerel sunucu (Ollama / LM Studio) seçersen tam cevap veririm; internet araması açıksa oradan da bakarım.", "I read the question, but the answer is not in your notes. For written questions choose a local server (Ollama / LM Studio) in Settings for a full answer; with web search on I also look it up online."))
            }
        }
        guard !items.isEmpty else {
            return L("Sayfada soru ya da işlem bulamadım. Okuduğum satırlar:", "I found no question or calculation on the page. Lines I read:") + "\n"
                + lines.prefix(10).map { "- \($0)" }.joined(separator: "\n")
        }
        return L("## Sayfadaki sorular", "## Questions on the page") + "\n" + items.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
    }

    static func rankedSentences(for question: String, in sents: [Sentence]) -> [Sentence] {
        let questionStems = Set(stems(question)).subtracting(questionWordStems)
        guard !questionStems.isEmpty, !sents.isEmpty else { return [] }
        let idfs = idf(sents)
        return sents.map { s -> (Sentence, Double) in
            let overlap = questionStems.intersection(Set(s.stems))
            let score = overlap.reduce(0.0) { $0 + (idfs[$1] ?? 1) } / (1 + 0.015 * Double(s.text.count)).squareRoot()
            return (s, score)
        }
        .filter { $0.1 > 0 }
        .sorted { $0.1 > $1.1 }
        .prefix(4)
        .map { $0.0 }
    }

    // MARK: - Actions

    static func summary(_ pages: [PageText]) -> String {
        let sents = sentences(from: pages)
        guard !sents.isEmpty else { return emptyMessage }
        let n = min(7, max(3, sents.count / 6))
        let top = topSentences(sents, count: n)
        let terms = keyTerms(sents, count: 8)
        var out = L("## Özet", "## Summary") + "\n"
        out += top.map { "- \($0.text) _(\($0.label))_" }.joined(separator: "\n")
        if !terms.isEmpty {
            out += "\n\n" + L("## Anahtar kavramlar", "## Key terms") + "\n" + terms.map(capitalized).joined(separator: " · ")
        }
        return out
    }

    static func explain(_ pages: [PageText], current: Int, definitions: [String: WebSource]) -> String {
        let here = pages.filter { $0.page == current }
        let sents = sentences(from: here.isEmpty ? pages : here)
        guard !sents.isEmpty else { return emptyMessage }
        let top = topSentences(sents, count: 4)
        let terms = keyTerms(sents, count: 5)
        var out = L("## Bu sayfanın ana fikri", "## Main idea of this page") + "\n" + top.map { "- \($0.text)" }.joined(separator: "\n")
        if !terms.isEmpty {
            out += "\n\n" + L("## Anahtar kavramlar", "## Key terms") + "\n"
            out += terms.map { term -> String in
                if let d = definitions[term] {
                    return "- **\(capitalized(term))**: \(d.snippet)"
                }
                if let ctx = sents.first(where: { $0.text.range(of: term, options: .caseInsensitive) != nil }) {
                    return "- **\(capitalized(term))**: \(ctx.text)"
                }
                return "- **\(capitalized(term))**"
            }.joined(separator: "\n")
        }
        out += "\n\n" + L("## Çalışma önerisi\n- Anahtar kavramları kendi cümlelerinle tanımla.\n- Ana fikir maddelerini birbirine bağlayan kısa bir paragraf yaz.\n- Sonra \"Quiz\" ile kendini dene.", "## How to study it\n- Define the key terms in your own words.\n- Write a short paragraph that links the main points.\n- Then test yourself with \"Quiz\".")
        return out
    }

    static func quiz(_ pages: [PageText]) -> String {
        let sents = sentences(from: pages).filter { !$0.text.contains("=") }
        guard sents.count >= 2 else {
            return L("Quiz hazırlamak için yeterli metin bulamadım. Sayfada daha fazla yazı olmalı.", "There is not enough text for a quiz yet. The page needs more writing.")
        }
        let terms = keyTerms(sents, count: 16)
        let candidates = topSentences(sents, count: 16)
        var questions: [(q: String, a: String)] = []
        var used = Set<String>()
        for s in candidates where questions.count < 5 {
            for term in terms where !used.contains(term.lowercased(with: trLocale)) {
                guard let blank = cloze(s.text, term: term) else { continue }
                used.insert(term.lowercased(with: trLocale))
                questions.append((q: L("Boşluğu doldur:", "Fill in the blank:") + " \"\(blank.text)\" _(\(s.label))_", a: blank.answer))
                break
            }
        }
        for term in terms where questions.count < 5 && !used.contains(term.lowercased(with: trLocale)) {
            used.insert(term.lowercased(with: trLocale))
            questions.append((q: L("Kendi cümlelerinle açıkla: **\(capitalized(term))** nedir, konuyla ilişkisi ne?", "Explain in your own words: what is **\(capitalized(term))** and how does it relate to the topic?"),
                              a: L("Notlarındaki \"\(term)\" geçen bölüme bak.", "See the part of your notes that mentions \"\(term)\".")))
        }
        guard !questions.isEmpty else {
            return L("Quiz için uygun cümle bulamadım.", "I could not find suitable sentences for a quiz.")
        }
        var out = "## Quiz\n"
        for (i, item) in questions.enumerated() {
            out += "\(i + 1). \(item.q)\n"
        }
        out += "\n" + L("## Cevaplar", "## Answers") + "\n"
        for (i, item) in questions.enumerated() {
            out += "\(i + 1). \(item.a)\n"
        }
        return out
    }

    static func formulas(_ pages: [PageText]) -> String {
        let found = formulaLines(pages)
        guard !found.isEmpty else {
            return L("Bu sayfalarda formül bulamadım. El yazısı formüller için kalemle net ve büyükçe yazmak OCR'ı kolaylaştırır.", "I found no formulas on these pages. Writing formulas clearly and a little larger helps the reading.")
        }
        var out = L("## Formüller", "## Formulas") + "\n"
        for (line, label) in found.prefix(20) {
            out += "- `\(line)` _(\(label))_\n"
            let symbols = symbolsIn(line)
            let known = symbols.compactMap { s in symbolMeanings[s].map { "\(s): \($0)" } }
            if !known.isEmpty {
                out += "  - " + known.joined(separator: " · ") + "\n"
            }
        }
        out += "\n" + L("_Sembol anlamları yaygın kullanıma göre tahmin edildi; ders notundaki tanımı esas al._", "_Symbol meanings are guessed from common usage; follow the definitions in your course notes._")
        return out
    }

    /// Checks the handwritten solution line by line: numeric claims, and for equations whether every
    /// step keeps the same solution as the line before it (the step where it changes is the mistake).
    static func check(_ pages: [PageText], current: Int) -> String {
        let lines = mathLines(pages, current: current)
        guard !lines.isEmpty else { return emptyMessage }
        var report: [String] = []
        var wrong = 0
        var checked = 0
        var previous: (variable: String, roots: [Double])?
        for line in lines {
            guard let finding = MathEngine.analyze(line) else { continue }
            switch finding {
            case let .claim(_, holds, _, _, _):
                checked += 1
                if !holds { wrong += 1 }
                report.append("- " + MathFormat.describe(finding))
                previous = nil
            case let .solved(text, variable, roots, _, trig):
                checked += 1
                if let prev = previous, prev.variable == variable {
                    if MathEngine.sameRoots(prev.roots, roots) {
                        report.append("- ✓ `\(text)` " + L("önceki adımla tutarlı", "is consistent with the previous step"))
                    } else {
                        wrong += 1
                        let expected = MathFormat.roots(prev.roots, variable: variable, trig: trig)
                        let got = MathFormat.roots(roots, variable: variable, trig: trig)
                        report.append("- ✗ `\(text)` → " + L("hata bu adımda: önceki satıra göre **\(expected)** olmalı, bu satır \(got) veriyor", "the mistake is in this step: from the line before it should be **\(expected)**, but this line gives \(got)"))
                    }
                } else {
                    report.append("- " + MathFormat.describe(finding))
                }
                previous = (variable, roots)
            default:
                report.append("- " + MathFormat.describe(finding))
            }
        }
        if let system = MathEngine.solveSystem(lines) {
            report.append("- " + describe(system))
        }
        guard !report.isEmpty else {
            return L("Sayfada kontrol edilecek bir işlem bulamadım. Okuduğum satırlar:", "I found no calculation to check on the page. Lines I read:") + "\n"
                + lines.prefix(10).map { "- \($0)" }.joined(separator: "\n")
        }
        var out = L("## Çözüm kontrolü", "## Solution check") + "\n"
        if checked > 0 {
            out += wrong == 0 ? L("Kontrol ettiğim adımların hepsi doğru. 👏", "Every step I checked is correct. 👏") + "\n\n" : L("\(wrong) yerde hata var.", "There are \(wrong) mistake(s).") + "\n\n"
        }
        out += report.joined(separator: "\n")
        return out
    }

    static func freeAnswer(_ question: String, pages: [PageText], web: [WebSource], current: Int) -> String {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = q.lowercased(with: trLocale)
        let greetings = ["merhaba", "selam", "hey", "günaydın", "iyi akşamlar", "naber", "hello", "hi"]
        if lower.count < 25, greetings.contains(where: { lower.hasPrefix($0) }) {
            return L("Merhaba! 👋 Sayfadaki soruları çözebilir, çözümünü kontrol edebilir, özet ya da quiz hazırlayabilirim.", "Hello! 👋 I can solve the questions on the page, check your solution, or make a summary or a quiz.")
        }
        let pageWords = ["sayfa", "buradaki", "bunları", "bunu", "page", "these", "this"]
        let solveWords = ["çöz", "soru", "işlem", "denklem", "cevap", "hesapla", "doğru mu", "kontrol", "solve", "question", "equation", "answer", "check"]
        if pageWords.contains(where: { lower.contains($0) }) && solveWords.contains(where: { lower.contains($0) }) {
            return lower.contains("kontrol") || lower.contains("doğru mu") || lower.contains("check")
                ? check(pages, current: current)
                : solvePage(pages, current: current, web: web)
        }
        if let finding = MathEngine.analyze(q) {
            return L("## Hesap", "## Calculation") + "\n" + MathFormat.describe(finding)
        }

        var out = ""
        let sents = sentences(from: pages)
        let ranked = rankedSentences(for: q, in: sents)
        if !ranked.isEmpty {
            out += L("## Sayfalarda bulduklarım", "## Found in your pages") + "\n"
            out += ranked.map { "- \($0.text) _(\($0.label))_" }.joined(separator: "\n")
        }
        if !web.isEmpty {
            if !out.isEmpty { out += "\n\n" }
            out += L("## İnternetten", "## From the web") + "\n"
            out += web.enumerated().map { i, w in "- **\(w.title)** [\(i + 1)]: \(w.snippet)" }.joined(separator: "\n")
        }
        if out.isEmpty {
            out = L("Sayfalarda bu soruyla eşleşen bir bölüm bulamadım.", "I found nothing in the pages that matches this question.")
            if web.isEmpty {
                out += L(" İnternet araması açıksa daha fazla sonuç gelebilir.", " With web search on, more results may come.")
            }
            out += "\n\n" + L("_Çevrimdışı çekirdek cümle seçerek yanıt verir. Serbest sohbet için Ayarlar'dan Apple Intelligence ya da yerel sunucu (Ollama / LM Studio) seç; ikisi de API anahtarı istemez._", "_The offline engine answers by picking sentences. For free conversation choose Apple Intelligence or a local server (Ollama / LM Studio) in Settings; neither needs an API key._")
        }
        return out
    }

    // MARK: - Text analysis

    static let trLocale = Locale(identifier: "tr_TR")

    static let stopwords: Set<String> = [
        "ve", "veya", "ile", "bir", "bu", "şu", "da", "de", "ki", "mi", "mı", "mu", "mü", "için", "gibi", "daha",
        "çok", "en", "ama", "fakat", "ancak", "ise", "olan", "olarak", "olduğu", "olduğunu", "olur", "her", "hem",
        "ne", "nasıl", "neden", "niçin", "kadar", "sonra", "önce", "göre", "üzere", "diye", "yani", "eğer", "çünkü",
        "ya", "hiç", "bazı", "tüm", "bütün", "şey", "bunu", "buna", "bunun", "şunu", "onun", "ona", "onu", "bunlar",
        "onlar", "biz", "siz", "ben", "sen", "var", "yok", "değil", "dır", "dir", "dur", "dür", "tır", "tir", "tur",
        "tür", "ayrıca", "bile", "sadece", "yalnız", "kendi", "aynı", "başka", "diğer", "birçok", "birkaç",
        "arasında", "üzerinde", "içinde", "şekilde", "durumda", "zaman", "dolayı", "nedeniyle", "veya", "yine",
        "the", "and", "for", "are", "with", "that", "this", "from", "was", "were", "which", "their", "have", "has",
        "not", "but", "can", "into", "its", "also", "such", "than", "then", "these", "those", "there", "when",
        "where", "what", "how", "why", "will", "would", "should", "could", "been", "being", "about", "between",
        "each", "other", "more", "most", "some", "any", "all", "one", "two",
    ]

    private static let questionWordStems: Set<String> = Set(
        ["nedir", "nasıl", "neden", "niçin", "hangi", "hangisi", "nerede", "kimdir", "nelerdir", "açıkla", "anlat",
         "midir", "mıdır", "denir", "demek", "örnek", "bana", "lütfen", "söyle", "what", "explain"]
            .map { String($0.prefix(5)) }
    )

    static func words(_ text: String) -> [String] {
        var out: [String] = []
        var current = ""
        for ch in text {
            if ch.isLetter || ch.isNumber {
                current.append(ch)
            } else if !current.isEmpty {
                out.append(current)
                current = ""
            }
        }
        if !current.isEmpty { out.append(current) }
        return out
    }

    /// Turkish is agglutinative; the first five letters ("F5 stemming") match word forms well enough.
    static func stem(_ word: String) -> String? {
        let w = word.lowercased(with: trLocale)
        guard w.count >= 3, !stopwords.contains(w), !w.allSatisfy({ $0.isNumber }) else { return nil }
        return String(w.prefix(5))
    }

    static func stems(_ text: String) -> [String] {
        words(text).compactMap { stem($0) }
    }

    static func cleaned(_ text: String) -> String {
        var t = text.replacingOccurrences(of: "\r", with: "")
        t = t.replacingOccurrences(of: "-\n", with: "")
        t = t.replacingOccurrences(of: "\n{2,}", with: "\u{2029}", options: .regularExpression)
        t = t.replacingOccurrences(of: "\n", with: " ")
        t = t.replacingOccurrences(of: "\u{2029}", with: "\n")
        t = t.replacingOccurrences(of: "[ \t]{2,}", with: " ", options: .regularExpression)
        return t
    }

    static func sentences(from pages: [PageText]) -> [Sentence] {
        var out: [Sentence] = []
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.setLanguage(.turkish)
        for p in pages {
            // Handwriting comes back line by line: every line is its own unit.
            let blocks: [String] = p.fromOCR ? p.text.components(separatedBy: .newlines) : cleaned(p.text).components(separatedBy: "\n")
            let minLength = p.fromOCR ? 3 : 18
            for block in blocks {
                let b = block.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !b.isEmpty else { continue }
                tokenizer.string = b
                tokenizer.enumerateTokens(in: b.startIndex..<b.endIndex) { range, _ in
                    let s = b[range].trimmingCharacters(in: .whitespacesAndNewlines)
                    if s.count >= minLength && s.count <= 420 {
                        out.append(Sentence(text: s, page: p.page, order: out.count, stems: stems(s), label: p.label))
                    }
                    return true
                }
            }
        }
        return out
    }

    static func idf(_ sentences: [Sentence]) -> [String: Double] {
        var df: [String: Int] = [:]
        for s in sentences {
            for t in Set(s.stems) {
                df[t, default: 0] += 1
            }
        }
        let n = Double(max(sentences.count, 1))
        return df.mapValues { log((n + 1) / (Double($0) + 0.5)) }
    }

    static func topSentences(_ sentences: [Sentence], count: Int) -> [Sentence] {
        guard !sentences.isEmpty, count > 0 else { return [] }
        let idfs = idf(sentences)
        var tf: [String: Int] = [:]
        for s in sentences {
            for t in s.stems {
                tf[t, default: 0] += 1
            }
        }
        var weight: [String: Double] = [:]
        for (k, v) in tf {
            weight[k] = Double(v).squareRoot() * (idfs[k] ?? 0)
        }
        var seenPages = Set<Int>()
        var scored: [(Sentence, Double)] = []
        for s in sentences {
            let uniq = Set(s.stems)
            var score = uniq.reduce(0.0) { $0 + (weight[$1] ?? 0) } / (Double(uniq.count) + 4).squareRoot()
            if seenPages.insert(s.page).inserted { score *= 1.15 }
            let low = s.text.lowercased(with: trLocale)
            if low.contains(" denir") || low.contains(" tanım") || low.contains(" demektir") || s.text.contains(":") {
                score *= 1.2
            }
            scored.append((s, score))
        }
        scored.sort { $0.1 > $1.1 }
        var picked: [Sentence] = []
        for (s, _) in scored {
            let a = Set(s.stems)
            let similar = picked.contains { p in
                let b = Set(p.stems)
                let union = a.union(b).count
                return union > 0 && Double(a.intersection(b).count) / Double(union) > 0.55
            }
            if !similar { picked.append(s) }
            if picked.count >= count { break }
        }
        return picked.sorted { $0.order < $1.order }
    }

    static func keyTerms(_ pages: [PageText], count: Int) -> [String] {
        keyTerms(sentences(from: pages), count: count)
    }

    static func keyTerms(of text: String, count: Int) -> [String] {
        keyTerms([PageText(page: 0, text: text, fromOCR: true)], count: count)
    }

    static func keyTerms(_ sentences: [Sentence], count: Int) -> [String] {
        guard !sentences.isEmpty else { return [] }
        let idfs = idf(sentences)
        var tf: [String: Int] = [:]
        var surface: [String: [String: Int]] = [:]
        for s in sentences {
            for w in words(s.text) {
                guard let st = stem(w), w.count >= 4 else { continue }
                tf[st, default: 0] += 1
                surface[st, default: [:]][w, default: 0] += 1
            }
        }
        let minCount = sentences.count < 8 ? 1 : 2
        let ranked = tf.filter { $0.value >= minCount }
            .map { (key: $0.key, score: Double($0.value).squareRoot() * (idfs[$0.key] ?? 0.5)) }
            .sorted { $0.score > $1.score }
        var out: [String] = []
        for item in ranked {
            guard let forms = surface[item.key], let top = forms.max(by: { $0.value < $1.value }) else { continue }
            // Prefer the shortest common form ("fotosentez" over "fotosentezin").
            let common = forms.filter { $0.value * 2 >= top.value }.map { $0.key }
            let best = common.min { $0.count < $1.count } ?? top.key
            out.append(best)
            if out.count >= count { break }
        }
        return out
    }

    static func capitalized(_ s: String) -> String {
        guard let first = s.first else { return s }
        return String(first).uppercased(with: trLocale) + s.dropFirst()
    }

    /// Blanks out the whole word that contains `term`.
    private static func cloze(_ sentence: String, term: String) -> (text: String, answer: String)? {
        guard let r = sentence.range(of: term, options: .caseInsensitive) else { return nil }
        var lo = r.lowerBound
        var hi = r.upperBound
        while lo > sentence.startIndex {
            let prev = sentence.index(before: lo)
            guard sentence[prev].isLetter else { break }
            lo = prev
        }
        while hi < sentence.endIndex, sentence[hi].isLetter {
            hi = sentence.index(after: hi)
        }
        let answer = String(sentence[lo..<hi])
        guard answer.count >= 3 else { return nil }
        var text = sentence
        text.replaceSubrange(lo..<hi, with: "______")
        return (text: text, answer: answer)
    }

    // MARK: - Formulas

    static func formulaLines(_ pages: [PageText]) -> [(String, String)] {
        let mathChars = CharacterSet(charactersIn: "=∑∫√²³πΔσλαβθμΩ≤≥≈±×÷→∞∂")
        var out: [(String, String)] = []
        var seen = Set<String>()
        for p in pages {
            for raw in p.text.components(separatedBy: .newlines) {
                let line = raw.trimmingCharacters(in: .whitespaces)
                guard line.count >= 3, line.count <= 140 else { continue }
                guard line.unicodeScalars.contains(where: { mathChars.contains($0) }) else { continue }
                guard line.contains("=") || line.contains("≈") || line.contains("∫") || line.contains("∑") else { continue }
                let letters = line.filter { $0.isLetter }.count
                guard Double(letters) < Double(line.count) * 0.75 else { continue }
                let key = line.replacingOccurrences(of: " ", with: "")
                if seen.insert(key).inserted {
                    out.append((line, p.label))
                }
            }
        }
        return out
    }

    private static func symbolsIn(_ line: String) -> [String] {
        var out: [String] = []
        for w in words(line) where w.count == 1 && w.first?.isLetter == true && !out.contains(w) {
            out.append(w)
        }
        for ch in ["Δ", "π"] where line.contains(ch) && !out.contains(ch) {
            out.append(ch)
        }
        return out
    }

    private static let symbolMeanings: [String: String] = [
        "F": "kuvvet (N)", "m": "kütle (kg)", "a": "ivme (m/s²)", "v": "hız (m/s)", "t": "zaman (s)",
        "E": "enerji (J)", "P": "güç (W) ya da basınç (Pa)", "V": "hacim (m³) ya da gerilim (V)", "I": "akım (A)",
        "R": "direnç (Ω) ya da yarıçap", "Q": "yük (C) ya da ısı (J)", "q": "yük (C)", "g": "yer çekimi ivmesi (≈9,81 m/s²)",
        "h": "yükseklik (m)", "k": "sabit (ör. yay sabiti)", "x": "konum / değişken", "p": "momentum (kg·m/s)",
        "W": "iş (J)", "T": "periyot (s) ya da sıcaklık (K)", "f": "frekans (Hz)", "λ": "dalga boyu (m)",
        "ρ": "yoğunluk (kg/m³)", "σ": "gerilme (Pa)", "ε": "birim şekil değiştirme", "A": "alan (m²)",
        "d": "mesafe (m)", "r": "yarıçap (m)", "n": "mol sayısı / kırılma indisi", "c": "ışık hızı ya da öz ısı",
        "Δ": "değişim", "ω": "açısal hız (rad/s)", "θ": "açı", "μ": "sürtünme katsayısı", "π": "pi ≈ 3,14159",
    ]

    // MARK: - Numbers

    private static func approxEqual(_ a: Double, _ b: Double, written: String) -> Bool {
        let normalized = SafeMath.normalize(written)
        var decimals = 0
        if let dot = normalized.lastIndex(of: ".") {
            decimals = normalized[normalized.index(after: dot)...].prefix(while: { $0.isNumber }).count
        }
        let tolerance = decimals > 0 ? 0.5 * pow(10, -Double(decimals)) + 1e-9 : max(1e-9, 1e-9 * max(abs(a), abs(b)))
        return abs(a - b) <= tolerance
    }

    static func format(_ v: Double) -> String {
        if v.rounded() == v && abs(v) < 1e15 {
            return String(Int64(v))
        }
        let f = NumberFormatter()
        f.locale = trLocale
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 4
        return f.string(from: NSNumber(value: v)) ?? String(v)
    }
}

/// Tiny arithmetic evaluator for checking handwritten calculations. Never crashes on bad input.
struct SafeMath {
    private let chars: [Character]
    private var pos = 0

    private init(_ s: String) {
        chars = Array(s)
    }

    /// Normalizes OCR'd math ("3 x 4", "2,5", "√9", "5²") and evaluates it. nil when it isn't plain arithmetic.
    static func evaluate(_ raw: String) -> Double? {
        let s = normalize(raw)
        guard !s.isEmpty, s.count <= 200, s.contains(where: { $0.isNumber }) else { return nil }
        var parser = SafeMath(s)
        guard let v = parser.expression(), parser.pos == parser.chars.count, v.isFinite else { return nil }
        return v
    }

    static func normalize(_ raw: String) -> String {
        var s = raw
        let map: [(String, String)] = [
            ("×", "*"), ("·", "*"), ("∙", "*"), ("÷", "/"), (":", "/"), ("−", "-"), ("–", "-"), ("—", "-"),
            ("²", "^2"), ("³", "^3"), ("√", "r"), ("π", "p"), ("[", "("), ("]", ")"), ("{", "("), ("}", ")"),
        ]
        for (k, v) in map {
            s = s.replacingOccurrences(of: k, with: v)
        }
        s = s.replacingOccurrences(of: "(?<=[0-9)])\\s*[xX]\\s*(?=[0-9(])", with: "*", options: .regularExpression)
        s = s.replacingOccurrences(of: "(?<=[0-9]),(?=[0-9])", with: ".", options: .regularExpression)
        s = s.replacingOccurrences(of: " ", with: "")
        return s
    }

    private func peek() -> Character? {
        pos < chars.count ? chars[pos] : nil
    }

    private mutating func expression() -> Double? {
        guard var value = term() else { return nil }
        while let c = peek(), c == "+" || c == "-" {
            pos += 1
            guard let rhs = term() else { return nil }
            value = c == "+" ? value + rhs : value - rhs
        }
        return value
    }

    private mutating func term() -> Double? {
        guard var value = unary() else { return nil }
        while let c = peek() {
            if c == "*" || c == "/" {
                pos += 1
                guard let rhs = unary() else { return nil }
                if c == "/" {
                    guard rhs != 0 else { return nil }
                    value /= rhs
                } else {
                    value *= rhs
                }
            } else if c == "(" || c == "r" || c == "p" {
                // Implicit multiplication: 2(3+4), 2√9, 2π
                guard let rhs = unary() else { return nil }
                value *= rhs
            } else {
                break
            }
        }
        return value
    }

    private mutating func unary() -> Double? {
        if let c = peek(), c == "-" || c == "+" {
            pos += 1
            guard let v = unary() else { return nil }
            return c == "-" ? -v : v
        }
        return power()
    }

    private mutating func power() -> Double? {
        guard let base = primary() else { return nil }
        if peek() == "^" {
            pos += 1
            guard let exponent = unary() else { return nil }
            let v = pow(base, exponent)
            return v.isFinite ? v : nil
        }
        return base
    }

    private mutating func primary() -> Double? {
        guard let c = peek() else { return nil }
        if c == "(" {
            pos += 1
            guard let v = expression(), peek() == ")" else { return nil }
            pos += 1
            return v
        }
        if c == "r" {
            pos += 1
            guard let v = primary(), v >= 0 else { return nil }
            return v.squareRoot()
        }
        if c == "p" {
            pos += 1
            return Double.pi
        }
        var digits = ""
        while let d = peek(), d.isASCII, d.isNumber || d == "." {
            digits.append(d)
            pos += 1
        }
        return digits.isEmpty ? nil : Double(digits)
    }
}
