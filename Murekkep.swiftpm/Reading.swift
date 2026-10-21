import CoreGraphics
import Foundation

/// Which reading of a handwritten line wins, and where its exponents go (twin of
/// tests/ports/reading.py).
///
/// Every candidate — the model's beam, and Vision's readings scored by the model — is worth
/// log P / length + 0.6 × the share of its words the dictionary knows (case does not count). The
/// model decides when it is sure, the dictionary when it hesitates (kucuk / küçük); math lines are
/// left to the model alone. Without the model, Vision's first reading stands.
///
/// The pen-motion reader (OnlineReader) has a say too: onlineWeight × its log P / length, measured
/// from its best candidate and never below onlineFloor, so a reading it cannot follow (too few
/// points for the characters) is not thrown out, only outvoted.
enum Reading {
    static let dictionaryWeight = 0.6
    static let onlineWeight = 0.5
    static let onlineFloor = -4.0
    /// Small high marks that are punctuation, not exponents.
    static let punctuation: Set<Character> = ["'", "\"", "`", ",", "."]

    static func choose(model: [(text: String, score: Float)], vision: [(text: String, score: Float?)],
                       length: Int, isMath: Bool, dictionary: [String: Double],
                       online: [String: Float]? = nil) -> String {
        guard let first = model.first else { return vision.first?.text ?? "" }
        let n = Double(max(length, 1))
        let top = online?.values.filter { $0 > -.infinity }.max()
        var best = first.text
        var bestValue = -Double.infinity
        let all: [(text: String, score: Float?)] = model.map { (text: $0.text, score: Optional($0.score)) } + vision
        for candidate in all {
            guard let s = candidate.score else { continue }
            let known = isMath ? 0 : dictionaryWeight * (dictionary[candidate.text] ?? 0)
            var value = Double(s) / n + known
            if let top, let online {
                let o = online[candidate.text] ?? -.infinity
                value += onlineWeight * max(Double(o - top) / n, onlineFloor)
            }
            if value > bestValue {
                best = candidate.text
                bestValue = value
            }
        }
        return best
    }

    /// An exponent as StrokeFont writes it: raised characters, "^" + text when one has no raised
    /// form, and punctuation (an apostrophe written high) as itself.
    static func raisedText(_ text: String) -> String {
        if !text.isEmpty, text.allSatisfy({ punctuation.contains($0) }) { return text }
        let forms = text.map { StrokeFont.raised($0) }
        if !text.isEmpty, forms.allSatisfy({ $0 != nil }) { return String(forms.compactMap { $0 }) }
        return "^" + text
    }

    /// `text` with each exponent put after the last character left of where it was written.
    static func insertSuperscripts(_ text: String, charX: [CGFloat], raised: [(text: String, x: CGFloat)]) -> String {
        var at: [Int: String] = [:]
        for group in raised where !group.text.isEmpty {
            let pos = charX.filter { $0 <= group.x }.count
            at[pos, default: ""] += raisedText(group.text)
        }
        var out = at[0] ?? ""
        for (i, c) in text.enumerated() {
            out.append(c)
            out += at[i + 1] ?? ""
        }
        return out
    }
}
