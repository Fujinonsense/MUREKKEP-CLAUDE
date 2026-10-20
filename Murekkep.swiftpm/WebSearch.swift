import Foundation

/// Keyless web lookup: DuckDuckGo Instant Answers and Wikipedia (Turkish first, then English).
/// Nothing here needs an account or an API key.
enum WebSearch {
    private static let userAgent = "Murekkep/2.0 (iPadOS; egitim amacli not uygulamasi)"

    /// Best few results for `query`, most useful first.
    static func search(_ query: String, limit: Int = 4) async -> [WebSource] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        async let instant = duckDuckGo(q)
        async let turkish = wikipedia(q, lang: "tr", limit: 3)
        var results = await instant
        results += await turkish
        if results.count < 2 {
            results += await wikipedia(q, lang: "en", limit: 2)
        }
        var seen = Set<String>()
        results = results.filter { seen.insert($0.url.absoluteString).inserted }
        return Array(results.prefix(limit))
    }

    /// Short encyclopedia definition of a term (used by the offline engine's "Açıkla").
    static func definition(of term: String) async -> WebSource? {
        if let hit = await wikipedia(term, lang: "tr", limit: 1).first { return hit }
        return await duckDuckGo(term).first
    }

    // MARK: - DuckDuckGo

    private static func duckDuckGo(_ query: String) async -> [WebSource] {
        var c = URLComponents(string: "https://api.duckduckgo.com/")!
        c.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "no_html", value: "1"),
            URLQueryItem(name: "skip_disambig", value: "1"),
            URLQueryItem(name: "kl", value: "tr-tr"),
        ]
        guard let url = c.url, let obj = await getJSON(url) else { return [] }
        var out: [WebSource] = []
        let heading = (obj["Heading"] as? String) ?? query
        if let answer = obj["Answer"] as? String, !answer.isEmpty {
            out.append(WebSource(title: heading, url: URL(string: "https://duckduckgo.com/?q=\(encoded(query))")!, snippet: clip(answer)))
        }
        if let abstract = obj["AbstractText"] as? String, !abstract.isEmpty,
           let link = (obj["AbstractURL"] as? String).flatMap(URL.init(string:)) {
            out.append(WebSource(title: heading, url: link, snippet: clip(abstract)))
        } else if let def = obj["Definition"] as? String, !def.isEmpty,
                  let link = (obj["DefinitionURL"] as? String).flatMap(URL.init(string:)) {
            out.append(WebSource(title: heading, url: link, snippet: clip(def)))
        }
        if out.isEmpty, let related = obj["RelatedTopics"] as? [[String: Any]] {
            for item in related.prefix(2) {
                if let text = item["Text"] as? String, !text.isEmpty,
                   let link = (item["FirstURL"] as? String).flatMap(URL.init(string:)) {
                    out.append(WebSource(title: String(text.prefix(60)), url: link, snippet: clip(text)))
                }
            }
        }
        return out
    }

    // MARK: - Wikipedia

    private static func wikipedia(_ query: String, lang: String, limit: Int) async -> [WebSource] {
        var c = URLComponents(string: "https://\(lang).wikipedia.org/w/rest.php/v1/search/page")!
        c.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        guard let url = c.url, let obj = await getJSON(url),
              let pages = obj["pages"] as? [[String: Any]] else { return [] }
        var out: [WebSource] = []
        for (i, page) in pages.prefix(limit).enumerated() {
            guard let key = page["key"] as? String else { continue }
            let title = (page["title"] as? String) ?? key
            let pageURL = URL(string: "https://\(lang).wikipedia.org/wiki/\(pathEncoded(key))")
                ?? URL(string: "https://\(lang).wikipedia.org")!
            // The first hits get the full lead paragraph, the rest keep the search excerpt.
            if i < 2, let summary = await wikiSummary(key: key, lang: lang), !summary.isEmpty {
                out.append(WebSource(title: title, url: pageURL, snippet: clip(summary)))
            } else {
                let excerpt = stripHTML((page["excerpt"] as? String) ?? (page["description"] as? String) ?? "")
                if !excerpt.isEmpty {
                    out.append(WebSource(title: title, url: pageURL, snippet: clip(excerpt)))
                }
            }
        }
        return out
    }

    private static func wikiSummary(key: String, lang: String) async -> String? {
        guard let url = URL(string: "https://\(lang).wikipedia.org/api/rest_v1/page/summary/\(pathEncoded(key))"),
              let obj = await getJSON(url) else { return nil }
        return obj["extract"] as? String
    }

    // MARK: - Helpers

    private static func getJSON(_ url: URL) async -> [String: Any]? {
        var req = URLRequest(url: url)
        req.timeoutInterval = 8
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue(userAgent, forHTTPHeaderField: "Api-User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let result = try? await URLSession.shared.data(for: req) else { return nil }
        let (data, response) = result
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func encoded(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s
    }

    private static func pathEncoded(_ s: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    static func stripHTML(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let entities = ["&quot;": "\"", "&#39;": "'", "&amp;": "&", "&lt;": "<", "&gt;": ">", "&nbsp;": " "]
        for (k, v) in entities {
            t = t.replacingOccurrences(of: k, with: v)
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func clip(_ s: String, _ n: Int = 420) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count > n else { return t }
        let cut = t.prefix(n)
        if let dot = cut.lastIndex(where: { $0 == "." || $0 == "!" || $0 == "?" }), cut.distance(from: cut.startIndex, to: dot) > n / 2 {
            return String(cut[...dot])
        }
        return String(cut) + "…"
    }
}
