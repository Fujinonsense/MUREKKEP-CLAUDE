import Foundation

/// The language check of a script written by the downloaded model, piece by piece: which scenes or
/// lines are in the other language, whether the script is still the model's once they are written
/// again or left out, and the request that writes them again. Checked in tools/braincheck.
enum ScriptLanguage {
    /// Indices of the segments (a scene's narration, a dialogue line) that are not in the language.
    static func wrong(_ segments: [String], speaks: (String) -> Bool) -> [Int] {
        segments.indices.filter { !speaks(segments[$0]) }
    }

    /// Whether a script with `wrong` of `total` segments in the other language is kept (the wrong
    /// ones written again or dropped): more than half must be right. Otherwise the model did not keep
    /// to the language and the next writer takes over, as before.
    static func keeps(total: Int, wrong: Int) -> Bool {
        total > 0 && wrong * 2 < total
    }

    /// Asks for `texts` in the overview's language, as a JSON list in the same order, to be voiced.
    static func rewritePrompt(_ texts: [String], english: Bool) -> String {
        let list = (try? JSONSerialization.data(withJSONObject: texts, options: [.prettyPrinted]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        let n = "\(texts.count)"
        let ask = english
            ? "Rewrite the following \(n) texts in English only; keep the meaning and the length. They will be read aloud: no markdown, write symbols as they are spoken. Answer with only a JSON list of \(n) texts in the same order, nothing else."
            : "Aşağıdaki \(n) metni yalnızca Türkçe yaz; anlamı ve uzunluğu koru. Seslendirilecek: markdown yok, sembolleri okunuşuyla yaz. Yanıt yalnızca aynı sırayla \(n) metinlik bir JSON listesi olsun, başka hiçbir şey yazma."
        return ask + "\n\n" + list
    }

    /// The rewrite's reply: `count` texts, none empty, else nil (the segments are then left out).
    static func rewritten(_ reply: String, count: Int) -> [String]? {
        guard let start = reply.firstIndex(of: "["), let end = reply.lastIndex(of: "]"), start < end,
              let data = String(reply[start...end]).data(using: .utf8),
              let list = (try? JSONSerialization.jsonObject(with: data)) as? [Any] else { return nil }
        let texts = list.compactMap { $0 as? String }.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard texts.count == count, !texts.contains(where: \.isEmpty) else { return nil }
        return texts
    }
}
