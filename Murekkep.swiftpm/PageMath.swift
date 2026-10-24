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

    /// The reading of a math line: the text pen's (the readers tuned on the user's hand, with Vision's
    /// readings among their candidates) when the engine can work it out, otherwise Vision's.
    static func reading(vision: String, pen: String?) -> String {
        guard let pen = pen?.trimmingCharacters(in: .whitespaces), !pen.isEmpty,
              MathEngine.analyze(pen) != nil else { return vision }
        return pen
    }
}
