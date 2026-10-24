import Foundation

/// Handwritten math that the math engine settles on its own. Its results are exact and come at
/// once, where the downloaded model would think for a minute to say the same thing.
enum PageMath {
    /// True when the page has a calculation the engine works out and nothing else but labels ("Soru 1",
    /// a date, a stray mark): no sentence or question that needs a language model. A sum inside a
    /// worded question does not count: the engine would answer it without the question's options.
    static func engineSettles(_ lines: [String]) -> Bool {
        var found = false
        for line in lines {
            if isProse(line) { return false }
            if MathEngine.analyze(line) != nil { found = true }
        }
        return found
    }

    /// A sentence or a question in words: two words of three letters or more, or one with a "?".
    static func isProse(_ line: String) -> Bool {
        let words = line.split(whereSeparator: { !$0.isLetter }).filter { $0.count >= 3 }.count
        return words >= 2 || (words == 1 && line.contains("?"))
    }

    /// Words that only ask about a calculation ("3+3=33 doğru mu?", "3+4×2 kaç eder?").
    private static let askingWords: Set<String> = [
        "doğru", "mu", "mı", "mü", "mudur", "midir", "mıdır", "yanlış", "kaç", "kaçtır", "kaçtir", "eder", "nedir",
        "sonucu", "sonuç", "işleminin", "işlemin", "hesapla", "hesaplar", "mısın", "misin", "ise", "bul", "çöz",
        "değeri", "değer", "olur", "what", "is", "correct", "right", "wrong", "solve", "find", "calculate", "equals",
    ]

    /// The engine's answer to a calculation typed into the chat, when only question words surround it;
    /// nil sends the question to the model.
    static func question(_ text: String) -> MathFinding? {
        // Turkish lowercasing turns "Is" into "ıs": a word counts in either form.
        let tr = Locale(identifier: "tr_TR")
        func among(_ word: Substring, _ set: Set<String>) -> Bool {
            set.contains(word.lowercased(with: tr)) || set.contains(word.lowercased())
        }
        let words = text.split(whereSeparator: { !$0.isLetter })
        guard words.allSatisfy({ $0.count == 1 || among($0, askingWords) }) else { return nil }
        if let finding = MathEngine.analyze(text) { return finding }
        // "… doğru mu?", "Is … correct?": the claim without the asking.
        let claim = text.split(separator: " ").filter { token in
            !among(Substring(token.trimmingCharacters(in: .punctuationCharacters)), checkWords)
        }.joined(separator: " ")
        return claim == text ? nil : MathEngine.analyze(claim)
    }

    private static let checkWords: Set<String> = ["doğru", "mu", "mı", "mü", "mudur", "midir", "mıdır", "yanlış",
                                                  "is", "correct", "right", "wrong"]

    /// The reading of a math line: the text pen's (the readers tuned on the user's hand, with Vision's
    /// readings among their candidates) when the engine can work it out, otherwise Vision's.
    static func reading(vision: String, pen: String?) -> String {
        guard let pen = pen?.trimmingCharacters(in: .whitespaces), !pen.isEmpty,
              MathEngine.analyze(pen) != nil else { return vision }
        return pen
    }
}
