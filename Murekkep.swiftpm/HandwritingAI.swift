import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Reads handwriting with Claude's vision. On fast, joined-up writing and on mathematics (∫, Σ,
/// exponents, indices, fractions) it is far more accurate than the on-device reader, which stays
/// the fallback without a key, offline, or when an answer does not fit.
///
/// The strokes are split into written lines here, so every line Claude reads keeps its own strokes
/// and position; each line goes as its own picture, all of them in one request.
enum HandwritingAI {
    struct Access: Sendable {
        var apiKey: String
        var model: String
    }

    /// One written line: its strokes and their bounds (page space).
    struct Group {
        var box: CGRect
        var strokes: [Stroke]
    }

    // MARK: Lines

    /// The strokes grouped into written lines, top to bottom. Dots, accents, exponents and indices
    /// join the line they belong to; a fraction written as a stack (number, bar, number) stays one line.
    static func groups(_ strokes: [Stroke]) -> [Group] {
        let ink = strokes.filter { !$0.points.isEmpty && !$0.bounds.isEmpty }
        guard !ink.isEmpty else { return [] }
        let boxes = ink.map { CGRect(ink: $0.bounds) }
        let heights = boxes.map(\.height).filter { $0 >= 3 && $0 < 120 }.sorted()
        let letter: CGFloat = heights.isEmpty ? 16 : min(max(heights[heights.count / 2], 6), 60)

        // Each line: running mean of its strokes' centers and the strokes in it.
        var lines: [(sum: CGFloat, count: Int, members: [Int])] = []
        let order = ink.indices.sorted { boxes[$0].midY < boxes[$1].midY }
        for i in order {
            let cy = boxes[i].midY
            var best = -1
            var bestGap = letter * 0.95
            for (k, line) in lines.enumerated() {
                let gap = abs(cy - line.sum / CGFloat(line.count))
                if gap < bestGap {
                    bestGap = gap
                    best = k
                }
            }
            if best >= 0 {
                lines[best].sum += cy
                lines[best].count += 1
                lines[best].members.append(i)
            } else {
                lines.append((sum: cy, count: 1, members: [i]))
            }
        }

        var groups: [Group] = lines.map { line in
            let box = line.members.reduce(CGRect.null) { $0.union(boxes[$1]) }
            return Group(box: box, strokes: line.members.sorted().map { ink[$0] })
        }
        groups.sort { $0.box.midY < $1.box.midY }

        // A line of nothing but flat strokes is a fraction bar: it joins the lines just above and
        // below it that it spans.
        var k = 0
        while k < groups.count {
            let g = groups[k]
            let flat = g.strokes.allSatisfy { s in
                let b = CGRect(ink: s.bounds)
                return b.height < letter * 0.35 && b.width > letter * 0.8
            }
            guard flat else {
                k += 1
                continue
            }
            var merged = g
            var removeAbove = false
            if k > 0 {
                let above = groups[k - 1]
                if g.box.minY - above.box.maxY < letter * 1.2, horizontalOverlap(above.box, g.box) > 0.5 * min(above.box.width, g.box.width) {
                    merged = Group(box: merged.box.union(above.box), strokes: above.strokes + merged.strokes)
                    removeAbove = true
                }
            }
            if k + 1 < groups.count {
                let below = groups[k + 1]
                if below.box.minY - g.box.maxY < letter * 1.2, horizontalOverlap(below.box, g.box) > 0.5 * min(below.box.width, g.box.width) {
                    merged = Group(box: merged.box.union(below.box), strokes: merged.strokes + below.strokes)
                    groups.remove(at: k + 1)
                }
            }
            groups[k] = merged
            if removeAbove {
                groups.remove(at: k - 1)
            } else {
                k += 1
            }
        }
        return groups
    }

    private static func horizontalOverlap(_ a: CGRect, _ b: CGRect) -> CGFloat {
        max(0, min(a.maxX, b.maxX) - max(a.minX, b.minX))
    }

    // MARK: Reading

    private static let instructions = """
    You transcribe handwriting from a student's digital notebook. Each image is ONE line of handwriting (black ink on white). \
    Reply with ONLY a JSON array of strings, exactly one string per image, in the same order. No commentary, no markdown.

    Rules:
    1. Write exactly what is written: the same words, in the same order, with the same capitals. Do not translate, complete, \
    summarize, reword or correct grammar. Read hasty or joined-up letters by what the word is.
    2. The language is usually Turkish, sometimes English. Use the Turkish letters ç ğ ı İ ö ş ü wherever the written word \
    needs them, even when the dots or the cedilla were written quickly, misplaced or left out.
    3. Exactly one space between words. Keep punctuation where it was written.
    4. Mathematics: Unicode only, never LaTeX. Symbols: ∫ ∮ Σ ∏ √ ∞ π ∂ ∇ Δ θ α β γ λ μ σ φ ω ε ρ ≤ ≥ ≠ ≈ ± × ÷ · → ⇒ ⇔ ∈ ∉ ∀ ∃ ∪ ∩ °. \
    Exponents as superscript characters (x², eˣ, 10⁻³, xⁿ⁺¹, aᵇ). Indices as subscript characters (x₁, aₙ, log₂ x, xᵢ). \
    Limits of an integral or a sum go right after the sign: ∫₀¹ x² dx, Σᵢ₌₁ⁿ i, ∫ₐᵇ f(x) dx. \
    A fraction written as a stack becomes numerator/denominator, with parentheses around a side that has more than one term: \
    (x+1)/(x−1), 1/2. Functions as f(x), g'(x), sin(x), ln(x). Limits as lim x→0. Vectors and other notation as close as Unicode allows.
    5. If a line is only a drawing, a scribble or unreadable, return "" for it.
    """

    /// One string per group, or nil when anything goes wrong (the caller falls back to the device).
    static func read(_ groups: [Group], access: Access) async -> [String]? {
        guard !groups.isEmpty, groups.count <= 40 else { return nil }
        var content: [[String: Any]] = []
        for (i, g) in groups.enumerated() {
            // At most ~1560 px on the long side: larger pictures are shrunk by the service anyway.
            guard let raster = InkRaster.render(g.strokes, maxPixels: 1560), let data = png(raster.image) else { return nil }
            content.append(["type": "text", "text": "Satır \(i + 1):"])
            content.append(["type": "image", "source": ["type": "base64", "media_type": "image/png", "data": data.base64EncodedString()]])
        }
        content.append(["type": "text", "text": "\(groups.count) satır. Yalnızca \(groups.count) dizgilik JSON dizisini yaz."])
        let body: [String: Any] = [
            "model": access.model,
            "max_tokens": 2048,
            "system": instructions + (Loc.isEnglish ? "\nIn this notebook the language is usually English." : ""),
            "messages": [["role": "user", "content": content]],
            "output_config": ["effort": "low"],
        ]
        guard let json = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        var request = URLRequest(url: ClaudeRequest.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue(access.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(ClaudeRequest.apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = json
        guard let result = try? await URLSession.shared.data(for: request) else { return nil }
        let (data, response) = result
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let blocks = object["content"] as? [[String: Any]] else { return nil }
        let text = blocks.compactMap { block -> String? in
            (block["type"] as? String) == "text" ? block["text"] as? String : nil
        }.joined()
        guard let start = text.firstIndex(of: "["), let end = text.lastIndex(of: "]"), start < end,
              let arrayData = String(text[start...end]).data(using: .utf8),
              let array = (try? JSONSerialization.jsonObject(with: arrayData)) as? [Any] else { return nil }
        let strings = array.map { (($0 as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
        guard strings.count == groups.count else { return nil }
        return strings
    }

    private static func png(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
