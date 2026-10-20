import Foundation

/// OpenAI-compatible chat server on the local network: Ollama, LM Studio, llama.cpp, Jan, LocalAI...
/// No key is sent; everything stays between the iPad and the user's computer.
enum LocalServerClient {
    /// Accepts "192.168.1.20:11434", "http://mac.local:1234/v1" and similar.
    static func normalizedBase(_ raw: String) -> URL? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if !s.lowercased().hasPrefix("http://") && !s.lowercased().hasPrefix("https://") {
            s = "http://" + s
        }
        while s.hasSuffix("/") { s.removeLast() }
        if s.lowercased().hasSuffix("/v1") { s.removeLast(3) }
        while s.hasSuffix("/") { s.removeLast() }
        guard let url = URL(string: s), url.host != nil else { return nil }
        return url
    }

    static func endpoint(_ base: URL, _ path: String) -> URL {
        URL(string: base.absoluteString + path) ?? base
    }

    /// Model ids the server offers.
    static func listModels(base: URL, timeout: TimeInterval = 6) async throws -> [String] {
        var req = URLRequest(url: endpoint(base, "/v1/models"))
        req.timeoutInterval = timeout
        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw LocalAIError(Loc.t("Sunucu yanıt vermedi (HTTP {0}).", "\(status)"))
        }
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let list = obj["data"] as? [[String: Any]] else {
            throw LocalAIError(Loc.t("Sunucudan model listesi okunamadı."))
        }
        return list.compactMap { $0["id"] as? String }.sorted()
    }

    static func isReachable(_ base: URL) async -> Bool {
        (try? await listModels(base: base, timeout: 1.5)) != nil
    }

    /// Streaming chat request. `messages` uses the OpenAI format (text or multi-part with images).
    static func chatRequest(base: URL, model: String, messages: [[String: Any]], temperature: Double) throws -> URLRequest {
        let body: [String: Any] = [
            "model": model,
            "messages": messages,
            "stream": true,
            "temperature": temperature,
        ]
        var req = URLRequest(url: endpoint(base, "/v1/chat/completions"))
        req.httpMethod = "POST"
        req.timeoutInterval = 600
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.withoutEscapingSlashes])
        return req
    }

    enum Event {
        case delta(String)
        case done
        case error(String)
        case ignored
    }

    /// Parses one line of the server-sent event stream.
    static func parse(line: String) -> Event {
        var payload = line.trimmingCharacters(in: .whitespaces)
        if payload.hasPrefix("data:") {
            payload = String(payload.dropFirst(5)).trimmingCharacters(in: .whitespaces)
        } else if !payload.hasPrefix("{") {
            return .ignored
        }
        if payload == "[DONE]" { return .done }
        guard let data = payload.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return .ignored }
        if let err = obj["error"] {
            if let e = err as? [String: Any], let m = e["message"] as? String { return .error(m) }
            return .error(String(describing: err))
        }
        if let choices = obj["choices"] as? [[String: Any]], let first = choices.first {
            if let delta = first["delta"] as? [String: Any], let text = delta["content"] as? String {
                return .delta(text)
            }
            // Non-streaming servers answer with one full message.
            if let message = first["message"] as? [String: Any], let text = message["content"] as? String {
                return .delta(text)
            }
        }
        return .ignored
    }

    static func readError(_ bytes: URLSession.AsyncBytes, status: Int) async -> LocalAIError {
        var data = Data()
        do {
            for try await b in bytes {
                data.append(b)
                if data.count > 32_768 { break }
            }
        } catch {}
        var detail = String(data: data, encoding: .utf8) ?? ""
        if let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            if let e = obj["error"] as? [String: Any], let m = e["message"] as? String {
                detail = m
            } else if let m = obj["error"] as? String {
                detail = m
            }
        }
        detail = String(detail.prefix(240))
        if status == 404 {
            return LocalAIError(Loc.t("Model bulunamadı. Ayarlar'dan sunucudaki bir modeli seç. {0}", "\(detail)"))
        }
        return LocalAIError(Loc.t("Yerel sunucu hatası ({0}). {1}", "\(status)", "\(detail)"))
    }

    static func friendly(_ error: Error) -> String {
        if let e = error as? URLError {
            switch e.code {
            case .cannotConnectToHost, .cannotFindHost, .timedOut, .networkConnectionLost, .notConnectedToInternet:
                return Loc.t("Yerel sunucuya ulaşılamadı. Bilgisayarın açık mı, iPad ile aynı Wi‑Fi'de mi? Ollama için OLLAMA_HOST=0.0.0.0 ile başlat.")
            case .appTransportSecurityRequiresSecureConnection:
                return Loc.t("iPadOS bu adrese şifresiz bağlanmaya izin vermedi. Sunucu adresini IP numarasıyla yaz (ör. 192.168.1.20:11434).")
            default:
                break
            }
        }
        return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
