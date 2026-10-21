import Foundation

/// Finding words inside notes (PDF text, read pages, handwriting): case, Turkish dotted and dotless
/// i and accents do not matter, so "ogrenci" finds "Öğrenci" and "istanbul" finds "İSTANBUL". Each
/// hit comes with a little text around it for the results list.
enum TextSearch {
    struct Hit: Equatable {
        var before: String
        var match: String
        var after: String
        /// Character offset of the match in the text.
        var offset: Int
    }

    private static let contextBefore = 40
    private static let contextAfter = 60

    /// One character for one character: lower case, i for every i (İ I ı i), no accents (ğ→g, ş→s).
    private static func fold(_ c: Character) -> Character {
        switch c {
        case "İ", "I", "ı", "i": return "i"
        default:
            let folded = String(c).lowercased().folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            return folded.count == 1 ? folded.first! : (String(c).lowercased().first ?? c)
        }
    }

    static func normalize(_ s: String) -> String {
        String(s.map(fold))
    }

    static func hits(query: String, in text: String, limit: Int) -> [Hit] {
        let needle = Array(normalize(query.trimmingCharacters(in: .whitespacesAndNewlines)))
        guard !needle.isEmpty, limit > 0 else { return [] }
        let chars = Array(text)
        let hay = chars.map(fold)
        guard hay.count >= needle.count else { return [] }
        var out: [Hit] = []
        var i = 0
        while i <= hay.count - needle.count, out.count < limit {
            if hay[i] == needle[0], Array(hay[i..<(i + needle.count)]) == needle {
                let start = max(0, i - contextBefore)
                let end = min(chars.count, i + needle.count + contextAfter)
                var before = String(chars[start..<i]).replacingOccurrences(of: "\n", with: " ")
                var after = String(chars[(i + needle.count)..<end]).replacingOccurrences(of: "\n", with: " ")
                if start > 0 { before = "…" + before }
                if end < chars.count { after += "…" }
                out.append(Hit(before: before, match: String(chars[i..<(i + needle.count)]), after: after, offset: i))
                i += needle.count
            } else {
                i += 1
            }
        }
        return out
    }
}
