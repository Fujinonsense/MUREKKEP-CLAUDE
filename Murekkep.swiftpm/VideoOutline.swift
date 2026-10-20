import Foundation

/// One section of a video overview: its card and the scenes after it.
struct OutlineSection {
    var title: String
    var subtitle: String
    var scenes: [OverviewScene]
}

/// The order of a video overview's scenes, as in NotebookLM's explainers (twin of
/// tests/ports/outline.py): greeting and topic, a hook question (key words in **…**), the roadmap, a
/// numbered card per section followed by its scenes, a recap, and a closing question. At most six
/// sections: the neighbours with the fewest scenes are merged until six are left.
enum VideoOutline {
    static let maxSections = 6
    private static let cardTR = ["Birinci", "İkinci", "Üçüncü", "Dördüncü", "Beşinci", "Altıncı"]
    private static let cardTRLower = ["birinci", "ikinci", "üçüncü", "dördüncü", "beşinci", "altıncı"]
    private static let listTR = ["Birincisi", "İkincisi", "Üçüncüsü", "Dördüncüsü", "Beşincisi", "Altıncısı"]
    private static let cardEN = ["one", "two", "three", "four", "five", "six"]
    private static let listEN = ["First", "Second", "Third", "Fourth", "Fifth", "Sixth"]

    /// The text without its highlight markers (for speech).
    static func plain(_ s: String) -> String {
        s.replacingOccurrences(of: "**", with: "")
    }

    static func merge(_ sections: [OutlineSection]) -> [OutlineSection] {
        var parts = sections
        while parts.count > maxSections {
            var best = 0
            var bestSize = Int.max
            for k in 0..<(parts.count - 1) {
                let size = parts[k].scenes.count + parts[k + 1].scenes.count
                if size < bestSize {
                    best = k
                    bestSize = size
                }
            }
            let a = parts[best]
            let b = parts[best + 1]
            parts.replaceSubrange(best...(best + 1), with: [OutlineSection(title: a.title, subtitle: a.subtitle.isEmpty ? b.title : a.subtitle,
                                                                            scenes: a.scenes + b.scenes)])
        }
        return parts
    }

    static func assemble(title: String, hook: String, hookNarration: String, sections: [OutlineSection], closing: String,
                         language: OverviewLanguage) -> [OverviewScene] {
        let en = language.isEnglish
        let parts = merge(sections)
        let titles = parts.map(\.title)
        let n = parts.count
        var out: [OverviewScene] = [
            OverviewScene(layout: .title, title: title, subtitle: en ? "Video overview" : "Video özeti",
                          narration: en ? "Hi everyone. In this video we're going to explore \(title) together. Let's get started."
                                        : "Herkese merhaba. Bu videoda \(title) konusunu birlikte keşfedeceğiz. Hazırsanız başlayalım."),
            OverviewScene(layout: .question, title: hook, narration: hookNarration),
        ]
        if n > 0 {
            var items: [String] = []
            for (i, t) in titles.enumerated() {
                if i == n - 1 {
                    items.append(n > 1 ? (en ? "And finally, \(t)." : "Ve son olarak, \(t).") : "\(t).")
                } else {
                    items.append("\(en ? listEN[i] : listTR[i]), \(t).")
                }
            }
            let road = (en ? "Here's our roadmap. " : "İşte yol haritamız. ") + items.joined(separator: " ")
            out.append(OverviewScene(layout: .agenda, title: en ? "Our roadmap" : "Yol haritamız", bullets: titles, narration: road))
        }
        for (i, s) in parts.enumerated() {
            let last = i == n - 1 && n > 1
            let card: String
            if en {
                card = last ? "And finally, section \(cardEN[i]): \(s.title)." : "Section \(cardEN[i]): \(s.title)."
            } else {
                card = last ? "Ve son olarak \(cardTRLower[i]) bölümümüz: \(s.title)." : "\(cardTR[i]) bölümümüz: \(s.title)."
            }
            var scene = OverviewScene(layout: .section, title: s.title, subtitle: s.subtitle.isEmpty ? nil : s.subtitle, narration: card)
            scene.number = i + 1
            out.append(scene)
            out += s.scenes
        }
        if n > 0 {
            let joined = n > 1 ? titles.dropLast().joined(separator: ", ") + (en ? " and " : " ve ") + titles[n - 1] : titles[0]
            out.append(OverviewScene(layout: .summary, title: en ? "To sum up" : "Özetle", bullets: titles,
                                     narration: en ? "To sum up, we covered \(joined)." : "Özetlersek, \(joined) konularını gördük."))
        }
        out.append(OverviewScene(layout: .question, title: closing,
                                 narration: plain(closing) + (en ? " See you in the next one." : " Bir sonraki videoda görüşmek üzere.")))
        return out
    }
}
