import Foundation

// MARK: - Settings types

enum ClaudeModel: String, CaseIterable, Identifiable, Codable {
    case sonnet = "claude-sonnet-5-5"
    case haiku = "claude-haiku-5-5"
    case opus = "claude-opus-5-5"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sonnet: return "Claude Sonnet 5.5"
        case .haiku: return "Claude Haiku 5.5"
        case .opus: return "Claude Opus 5.5"
        }
    }

    var detail: String {
        switch self {
        case .sonnet: return Loc.t("Önerilen. Hızlı ve güçlü.")
        case .haiku: return Loc.t("En ucuz ve en hızlı.")
        case .opus: return Loc.t("En güçlü, daha yavaş ve pahalı.")
        }
    }
}

enum ThinkingEffort: String, CaseIterable, Identifiable, Codable {
    case low
    case medium
    case high

    var id: String { rawValue }

    var title: String {
        switch self {
        case .low: return Loc.t("Hızlı")
        case .medium: return Loc.t("Dengeli")
        case .high: return Loc.t("Derin")
        }
    }
}

// MARK: - Request

struct ClaudeTurn: Equatable {
    enum Role: String {
        case user
        case assistant
    }

    var role: Role
    var text: String
    /// JPEG of the page with the user's handwriting (only sent on user turns).
    var imageJPEG: Data?
}

enum ClaudeContext {
    case none
    case pdfBase64(Data, title: String)
    case pdfFile(id: String, title: String)
    case text(String, title: String)
    /// Page images (JPEG) with a short label each, used for handwritten notebooks.
    case images([(label: String, jpeg: Data)])
    /// Several documents at once (the studio's sources): uploaded PDFs and plain text.
    case sources([ClaudeSource])
}

struct ClaudeSource {
    var title: String
    /// Files API id of an uploaded PDF; nil sends `text` instead.
    var fileID: String?
    var text: String = ""
}

struct ClaudeRequest {
    var model: String
    var effort: String
    var maxTokens: Int
    var system: String
    var context: ClaudeContext
    /// Short description of what was attached (pages, current page...).
    var contextNote: String
    var turns: [ClaudeTurn]

    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    static let filesEndpoint = URL(string: "https://api.anthropic.com/v1/files")!
    static let apiVersion = "2023-06-01"

    /// Drops empty turns, merges consecutive same-role turns and makes sure we start and end with the user.
    static func normalized(_ turns: [ClaudeTurn]) -> [ClaudeTurn] {
        var out: [ClaudeTurn] = []
        for t in turns {
            let text = t.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty && t.imageJPEG == nil { continue }
            if var last = out.last, last.role == t.role {
                last.text = last.text.isEmpty ? text : last.text + "\n\n" + text
                if last.imageJPEG == nil { last.imageJPEG = t.imageJPEG }
                out[out.count - 1] = last
            } else {
                out.append(ClaudeTurn(role: t.role, text: text, imageJPEG: t.imageJPEG))
            }
        }
        while let first = out.first, first.role == .assistant { out.removeFirst() }
        while let last = out.last, last.role == .assistant { out.removeLast() }
        return out
    }

    private static var ephemeral: [String: Any] { ["type": "ephemeral"] }

    private func contextBlocks() -> [[String: Any]] {
        var blocks: [[String: Any]] = []
        switch context {
        case .none:
            break
        case let .pdfBase64(data, title):
            blocks.append([
                "type": "document",
                "source": ["type": "base64", "media_type": "application/pdf", "data": data.base64EncodedString()],
                "title": title,
                "cache_control": Self.ephemeral,
            ])
        case let .pdfFile(id, title):
            blocks.append([
                "type": "document",
                "source": ["type": "file", "file_id": id],
                "title": title,
                "cache_control": Self.ephemeral,
            ])
        case let .text(text, title):
            blocks.append([
                "type": "text",
                "text": "<belge baslik=\"\(title)\">\n\(text)\n</belge>",
                "cache_control": Self.ephemeral,
            ])
        case let .images(items):
            for (i, item) in items.enumerated() {
                blocks.append(["type": "text", "text": item.label])
                var image: [String: Any] = [
                    "type": "image",
                    "source": ["type": "base64", "media_type": "image/jpeg", "data": item.jpeg.base64EncodedString()],
                ]
                if i == items.count - 1 { image["cache_control"] = Self.ephemeral }
                blocks.append(image)
            }
        case let .sources(items):
            for (i, item) in items.enumerated() {
                var block: [String: Any]
                if let id = item.fileID {
                    block = ["type": "document", "source": ["type": "file", "file_id": id], "title": "Kaynak \(i + 1): \(item.title)"]
                } else {
                    block = ["type": "text", "text": "<kaynak no=\"\(i + 1)\" baslik=\"\(item.title)\">\n\(item.text)\n</kaynak>"]
                }
                if i == items.count - 1 { block["cache_control"] = Self.ephemeral }
                blocks.append(block)
            }
        }
        if !contextNote.isEmpty {
            blocks.append(["type": "text", "text": contextNote])
        }
        return blocks
    }

    func jsonObject() -> [String: Any] {
        var messages: [[String: Any]] = []
        var contextAdded = false
        for turn in Self.normalized(turns) {
            var content: [[String: Any]] = []
            if turn.role == .user && !contextAdded {
                content.append(contentsOf: contextBlocks())
                contextAdded = true
            }
            if turn.role == .user, let jpeg = turn.imageJPEG {
                content.append(["type": "text", "text": "Kullanıcının bu sayfadaki el yazısı notları:"])
                content.append([
                    "type": "image",
                    "source": ["type": "base64", "media_type": "image/jpeg", "data": jpeg.base64EncodedString()],
                ])
            }
            let text = turn.text.isEmpty ? "(görsele bak)" : turn.text
            content.append(["type": "text", "text": text])
            messages.append(["role": turn.role.rawValue, "content": content])
        }
        return [
            "model": model,
            "max_tokens": maxTokens,
            "stream": true,
            "system": system,
            "messages": messages,
            "cache_control": Self.ephemeral,
            "output_config": ["effort": effort],
        ]
    }

    func jsonData() throws -> Data {
        try JSONSerialization.data(withJSONObject: jsonObject(), options: [.withoutEscapingSlashes])
    }

    static let tutorSystemPrompt = """
    Sen "Mürekkep" adlı not uygulamasının içindeki çalışma asistanısın. Kullanıcı bir öğrenci. Sana ders PDF'lerinden sayfalar ve bazen kendi el yazısı notlarının görüntüsünü gönderir.

    Kurallar:
    - Kullanıcının yazdığı dilde cevap ver: Türkçe soruya akademik Türkçe, İngilizce soruya akademik İngilizce.
    - Kısa, net ve öğretici ol. Giriş cümlesiyle vakit kaybetme.
    - Cevabını gönderilen sayfalara dayandır ve bilgiyi aldığın sayfayı belirt (ör. s. 12). Sayfalarda olmayan bir bilgi eklersen bunun genel bilgi olduğunu söyle.
    - Uygulama LaTeX gösteremez. Matematiği düz metin ve Unicode sembollerle yaz: F = m·a, σ = F/A, x², √(2gh), ∫ f(x) dx, Δv, ≈, ≤, π.
    - Başlık için ## ve liste için - kullanabilirsin. Tablo kullanma.
    - El yazısını kontrol ederken önce ne yazdığını kısaca oku, sonra hatayı tam yerini göstererek açıkla ve doğru adımı ver.
    - Emin olmadığın yerde bunu açıkça söyle.
    """
}

// MARK: - Streaming

enum ClaudeStreamEvent: Equatable {
    case thinking
    case textDelta(String)
    case stopReason(String)
    case messageStop
    case error(type: String, message: String)
    case ignored
}

enum ClaudeSSE {
    /// Parses one server-sent-event line. Returns nil for lines that are not `data:` lines.
    static func parse(line: String) -> ClaudeStreamEvent? {
        guard line.hasPrefix("data:") else { return nil }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard let data = payload.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let type = obj["type"] as? String
        else { return .ignored }
        switch type {
        case "content_block_start":
            if let block = obj["content_block"] as? [String: Any], let bt = block["type"] as? String,
               bt == "thinking" || bt == "redacted_thinking" {
                return .thinking
            }
            return .ignored
        case "content_block_delta":
            if let delta = obj["delta"] as? [String: Any], (delta["type"] as? String) == "text_delta",
               let text = delta["text"] as? String {
                return .textDelta(text)
            }
            return .ignored
        case "message_delta":
            if let delta = obj["delta"] as? [String: Any], let reason = delta["stop_reason"] as? String {
                return .stopReason(reason)
            }
            return .ignored
        case "message_stop":
            return .messageStop
        case "error":
            let err = obj["error"] as? [String: Any]
            return .error(type: err?["type"] as? String ?? "error", message: err?["message"] as? String ?? "")
        default:
            return .ignored
        }
    }

    static func parseErrorBody(_ data: Data) -> (type: String, message: String)? {
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let err = obj["error"] as? [String: Any]
        else { return nil }
        return (err["type"] as? String ?? "error", err["message"] as? String ?? "")
    }

    static func friendlyMessage(status: Int, type: String?, message: String?) -> String {
        let msg = message ?? ""
        let lower = msg.lowercased()
        if lower.contains("credit balance") {
            return Loc.t("API hesabında kredi kalmamış. Claude Console'dan bakiye ekleyip tekrar dene.")
        }
        if lower.contains("prompt is too long") || lower.contains("too many pages") || status == 413 {
            return Loc.t("Gönderilen içerik çok büyük. Kapsamı küçült (ör. \"Bu sayfa\") ve tekrar dene.")
        }
        switch (status, type ?? "") {
        case (401, _), (_, "authentication_error"):
            return Loc.t("API anahtarı geçersiz. Ayarlardan anahtarı kontrol et.")
        case (403, _), (_, "permission_error"):
            return Loc.t("Bu API anahtarının bu işlem için izni yok.")
        case (429, _), (_, "rate_limit_error"):
            return Loc.t("Hız sınırına takıldın. Biraz bekleyip tekrar dene.")
        case (529, _), (_, "overloaded_error"):
            return Loc.t("Claude şu an çok yoğun. Birkaç saniye sonra tekrar dene.")
        case (500..<600, _), (_, "api_error"):
            return Loc.t("Sunucu hatası oluştu. Tekrar dene.")
        case (404, _), (_, "not_found_error"):
            return Loc.t("Model ya da dosya bulunamadı. {0}", "\(msg)")
        default:
            return msg.isEmpty ? Loc.t("Beklenmeyen hata ({0}).", "\(status)") : Loc.t("Hata ({0}): {1}", "\(status)", "\(msg)")
        }
    }
}
