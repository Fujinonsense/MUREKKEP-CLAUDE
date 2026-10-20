import Foundation

struct ClaudeAPIError: LocalizedError {
    let status: Int
    let type: String?
    let message: String?

    var errorDescription: String? {
        ClaudeSSE.friendlyMessage(status: status, type: type, message: message)
    }

    /// The referenced Files API upload is gone (expired or deleted).
    var isMissingFile: Bool {
        let m = (message ?? "").lowercased()
        return m.contains("file") && (status == 404 || type == "not_found_error" || m.contains("not found") || m.contains("expired"))
    }
}

enum ClaudeClient {
    static func messagesRequest(apiKey: String, body: Data) -> URLRequest {
        var req = URLRequest(url: ClaudeRequest.endpoint)
        req.httpMethod = "POST"
        req.timeoutInterval = 600
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue(ClaudeRequest.apiVersion, forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.setValue("text/event-stream", forHTTPHeaderField: "accept")
        req.httpBody = body
        return req
    }

    /// Reads an error response body (at most 64 KB) from a streamed response.
    static func readError(_ bytes: URLSession.AsyncBytes, status: Int) async -> ClaudeAPIError {
        var data = Data()
        do {
            for try await b in bytes {
                data.append(b)
                if data.count > 65_536 { break }
            }
        } catch {}
        let parsed = ClaudeSSE.parseErrorBody(data)
        return ClaudeAPIError(status: status, type: parsed?.type, message: parsed?.message)
    }

    /// Uploads a PDF to the Files API and returns its file id. Files expire after 30 days.
    static func uploadPDF(_ data: Data, filename: String, apiKey: String) async throws -> String {
        let boundary = "MurekkepBoundary-\(UUID().uuidString)"
        var req = URLRequest(url: ClaudeRequest.filesEndpoint)
        req.httpMethod = "POST"
        req.timeoutInterval = 600
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue(ClaudeRequest.apiVersion, forHTTPHeaderField: "anthropic-version")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "content-type")

        var body = Data()
        func add(_ s: String) { body.append(Data(s.utf8)) }
        add("--\(boundary)\r\n")
        add("Content-Disposition: form-data; name=\"file\"; filename=\"\(safeFilename(filename))\"\r\n")
        add("Content-Type: application/pdf\r\n\r\n")
        body.append(data)
        add("\r\n--\(boundary)\r\n")
        add("Content-Disposition: form-data; name=\"expires_in_seconds\"\r\n\r\n")
        add("2592000\r\n")
        add("--\(boundary)--\r\n")

        let (respData, response) = try await URLSession.shared.upload(for: req, from: body)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 || status == 201 else {
            let parsed = ClaudeSSE.parseErrorBody(respData)
            throw ClaudeAPIError(status: status, type: parsed?.type, message: parsed?.message)
        }
        guard let obj = (try? JSONSerialization.jsonObject(with: respData)) as? [String: Any],
              let id = obj["id"] as? String else {
            throw ClaudeAPIError(status: status, type: "invalid_response", message: Loc.t("Dosya kimliği alınamadı."))
        }
        return id
    }

    /// Sends a request and returns the whole reply text. `onProgress` gets the number of characters
    /// received so far (on the main thread).
    static func collect(_ request: ClaudeRequest, apiKey: String,
                        onProgress: @escaping @MainActor (Int) -> Void = { _ in }) async throws -> String {
        let body = try await Task.detached(priority: .userInitiated) { try request.jsonData() }.value
        if body.count > 31_000_000 {
            throw ClaudeAPIError(status: 413, type: "request_too_large", message: nil)
        }
        let urlRequest = messagesRequest(apiKey: apiKey, body: body)
        let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw await readError(bytes, status: status)
        }
        var text = ""
        var lastReport = 0
        streamLoop: for try await line in bytes.lines {
            guard let event = ClaudeSSE.parse(line: line) else { continue }
            switch event {
            case let .textDelta(delta):
                text += delta
                if text.count - lastReport > 400 {
                    lastReport = text.count
                    let n = text.count
                    await MainActor.run { onProgress(n) }
                }
            case let .stopReason(reason):
                if reason == "refusal" {
                    throw ClaudeAPIError(status: 0, type: "refusal", message: Loc.t("Claude bu isteğe yanıt vermedi."))
                }
            case .messageStop:
                break streamLoop
            case let .error(type, message):
                throw ClaudeAPIError(status: 0, type: type, message: message)
            case .thinking, .ignored:
                break
            }
        }
        return text
    }

    static func deleteFile(id: String, apiKey: String) {
        guard let url = URL(string: "https://api.anthropic.com/v1/files/\(id)") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue(ClaudeRequest.apiVersion, forHTTPHeaderField: "anthropic-version")
        URLSession.shared.dataTask(with: req).resume()
    }

    /// Small request used by the settings screen to check the key.
    static func ping(apiKey: String, model: ClaudeModel) async -> String {
        let body: [String: Any] = [
            "model": model.rawValue,
            "max_tokens": 64,
            "messages": [["role": "user", "content": "Sadece 'tamam' yaz."]],
            "output_config": ["effort": "low"],
        ]
        guard let json = try? JSONSerialization.data(withJSONObject: body) else { return Loc.t("İstek hazırlanamadı.") }
        var req = URLRequest(url: ClaudeRequest.endpoint)
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue(ClaudeRequest.apiVersion, forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = json
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 200 { return Loc.t("Bağlantı başarılı. {0} hazır.", "\(model.title)") }
            let parsed = ClaudeSSE.parseErrorBody(data)
            return ClaudeSSE.friendlyMessage(status: status, type: parsed?.type, message: parsed?.message)
        } catch {
            return Loc.t("Bağlantı kurulamadı: {0}", "\(error.localizedDescription)")
        }
    }

    private static func safeFilename(_ name: String) -> String {
        let forbidden = CharacterSet(charactersIn: "<>:\"|?*\\/").union(.controlCharacters)
        var cleaned = name.components(separatedBy: forbidden).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty { cleaned = "belge" }
        if cleaned.count > 120 { cleaned = String(cleaned.prefix(120)) }
        return cleaned.lowercased().hasSuffix(".pdf") ? cleaned : cleaned + ".pdf"
    }
}
