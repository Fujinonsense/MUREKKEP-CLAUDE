import Foundation
import NaturalLanguage

/// Which brain answers questions in the assistant panel. None of them needs an API key except Claude.
enum AIEngine: String, CaseIterable, Identifiable, Codable {
    case auto
    case onDevice
    case localServer
    case offline
    case claude

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: return Loc.t("Otomatik")
        case .onDevice: return Loc.t("Cihazda (Apple Intelligence)")
        case .localServer: return Loc.t("Yerel sunucu (Ollama / LM Studio)")
        case .offline: return Loc.t("Çevrimdışı çekirdek")
        case .claude: return Loc.t("Claude API (isteğe bağlı)")
        }
    }

    var shortTitle: String {
        switch self {
        case .auto: return Loc.t("Otomatik")
        case .onDevice: return Loc.t("Cihazda")
        case .localServer: return Loc.t("Yerel sunucu")
        case .offline: return Loc.t("Çevrimdışı")
        case .claude: return "Claude"
        }
    }

    var symbol: String {
        switch self {
        case .auto: return "wand.and.stars"
        case .onDevice: return "cpu"
        case .localServer: return "desktopcomputer"
        case .offline: return "bolt.horizontal.circle"
        case .claude: return "cloud"
        }
    }

    var detail: String {
        switch self {
        case .auto:
            return Loc.t("Önce cihazdaki Apple Intelligence modeli, yoksa yerel sunucun, o da yoksa çevrimdışı çekirdek kullanılır.")
        case .onDevice:
            return Loc.t("iPadOS 26 ve Apple Intelligence destekli iPad'lerde tamamen cihazda çalışır. Ücretsiz, anahtar gerekmez.")
        case .localServer:
            return Loc.t("Bilgisayarında çalışan Ollama, LM Studio ya da llama.cpp sunucusuna Wi‑Fi üzerinden bağlanır. Anahtar gerekmez.")
        case .offline:
            return Loc.t("Her cihazda çalışan kural tabanlı çekirdek: özet, quiz, formül listesi, işlem kontrolü ve sayfa içi arama.")
        case .claude:
            return Loc.t("Anthropic API anahtarı ister ve ücretlidir. Yalnızca bunu seçersen kullanılır.")
        }
    }
}

/// The engine actually used for one answer.
enum ResolvedEngine: Equatable {
    case onDevice
    case localServer(base: URL, model: String)
    case offline
    case claude

    var label: String {
        switch self {
        case .onDevice: return Loc.t("Cihazda · Apple Intelligence")
        case let .localServer(_, model): return model.isEmpty ? Loc.t("Yerel sunucu") : Loc.t("Yerel sunucu · {0}", "\(model)")
        case .offline: return Loc.t("Çevrimdışı çekirdek")
        case .claude: return "Claude API"
        }
    }

    var symbol: String {
        switch self {
        case .onDevice: return AIEngine.onDevice.symbol
        case .localServer: return AIEngine.localServer.symbol
        case .offline: return AIEngine.offline.symbol
        case .claude: return AIEngine.claude.symbol
        }
    }
}

/// A web page the assistant looked at.
struct WebSource: Identifiable, Hashable {
    let id = UUID()
    var title: String
    var url: URL
    var snippet: String
}

/// Collects sources found by tool calls (called from any thread).
final class SourceCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [WebSource] = []

    func add(_ new: [WebSource]) {
        lock.lock()
        for s in new where !items.contains(where: { $0.url == s.url }) {
            items.append(s)
        }
        lock.unlock()
    }

    var all: [WebSource] {
        lock.lock()
        defer { lock.unlock() }
        return items
    }
}

struct LocalAIError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}

/// Text read from one page (PDF text layer or OCR of the page image with its ink).
struct PageText {
    /// Page index in the open note. Pages of other notes in the section get indices from
    /// `PageText.otherNotesBase` up, so they never count as the current page and sort last.
    var page: Int
    var text: String
    var fromOCR: Bool
    /// Title of the other note this page comes from (section-wide questions).
    var source: String? = nil
    /// Page index inside that other note.
    var sourcePage: Int = 0

    static let otherNotesBase = 100_000

    /// "s. 3", or "Calculus 2. hafta · s. 3" for another note ("p. 3" in English answers).
    var label: String {
        let p = L("s.", "p.")
        if let source { return "\(source) · \(p) \(sourcePage + 1)" }
        return "\(p) \(page + 1)"
    }
}

/// The language of an answer: the language the user asked in, or for the ready-made actions the
/// language of the notes. Turkish unless the text is clearly English.
enum AnswerLanguage: Sendable {
    case turkish
    case english

    /// The answer being written right now (set around the offline engine); the app's language otherwise.
    @TaskLocal static var bound: AnswerLanguage? = nil
    static var current: AnswerLanguage { bound ?? app }

    /// The app's own language, for when the text does not tell.
    static var app: AnswerLanguage { Loc.isEnglish ? .english : .turkish }

    static func detect(_ text: String, context: String = "") -> AnswerLanguage {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.range(of: "[çğıöşüÇĞİÖŞÜ]", options: .regularExpression) != nil { return .turkish }
        let sample = t.count >= 14 ? t : (t + " " + String(context.prefix(800)))
        guard sample.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3 else { return app }
        if sample.range(of: "[çğıöşüÇĞİÖŞÜ]", options: .regularExpression) != nil, t.count < 14 { return .turkish }
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = [.turkish, .english]
        recognizer.processString(sample)
        let h = recognizer.languageHypotheses(withMaximum: 2)
        let en = h[.english] ?? 0
        let tr = h[.turkish] ?? 0
        if en > tr + 0.15 { return .english }
        if tr > en + 0.15 { return .turkish }
        return app
    }

    /// Added to every model's instructions, which are written in Turkish.
    var directive: String {
        switch self {
        case .turkish:
            return "YANIT DİLİ: Akıcı, doğru ve akademik bir Türkçe kullan. Terimlerin Türkçe karşılıklarını yaz; gerekirse İngilizcesini parantez içinde ver."
        case .english:
            return "RESPONSE LANGUAGE: The user is working in English. Answer in flawless, fluent academic English, even though these instructions are written in Turkish. Use standard English terminology and refer to pages as \"p. 3\"."
        }
    }
}

/// Turkish or English text for the answer being written.
func L(_ turkish: String, _ english: String) -> String {
    AnswerLanguage.current == .english ? english : turkish
}
