import AVFoundation
import SwiftUI
import UIKit

// MARK: - Settings

/// The studio's voices: two fixed, natural voices, a woman's and a man's, that speak Turkish and
/// English alike. The only choice is which of them narrates; in a two-host podcast the second host
/// is the other one. They are ElevenLabs voices (the user's own key); with only an OpenAI key,
/// OpenAI's voices of the same kind stand in. The device's (Siri) voices are never used.
final class VoiceSettings: ObservableObject {
    static let shared = VoiceSettings()

    enum Gender: String, CaseIterable, Identifiable {
        case female
        case male

        var id: String { rawValue }

        var title: String {
            switch self {
            case .female: return Loc.t("Kadın")
            case .male: return Loc.t("Erkek")
            }
        }

        var other: Gender { self == .female ? .male : .female }
    }

    enum Engine {
        case eleven
        case openAI
    }

    private static let keyAccount = "openai-api-key"
    private static let fallbackKey = "openAIKeyFallback"
    private static let elevenAccount = "elevenlabs-api-key"
    private static let elevenFallbackKey = "elevenKeyFallback"

    /// The narrator's voice.
    @Published var gender: Gender {
        didSet {
            UserDefaults.standard.set(gender.rawValue, forKey: "voice.gender")
            revision += 1
        }
    }
    @Published private(set) var hasCloudKey: Bool
    @Published private(set) var hasElevenKey: Bool
    /// Bumped when anything that shapes the sound changes.
    @Published private(set) var revision = 0

    private init() {
        let d = UserDefaults.standard
        gender = Gender(rawValue: d.string(forKey: "voice.gender") ?? "") ?? .female
        hasCloudKey = (Keychain.read(account: Self.keyAccount) ?? d.string(forKey: Self.fallbackKey)) != nil
        hasElevenKey = (Keychain.read(account: Self.elevenAccount) ?? d.string(forKey: Self.elevenFallbackKey)) != nil
    }

    /// The narrator (host 0) speaks with the chosen voice, the second host with the other one.
    func gender(host: Int) -> Gender {
        host == 0 ? gender : gender.other
    }

    /// ElevenLabs when its key is there, else OpenAI; nil without either key.
    var engine: Engine? {
        if elevenKey != nil { return .eleven }
        if cloudKey != nil { return .openAI }
        return nil
    }

    /// Changes when anything that shapes the sound changes (an overview is voiced again then).
    func signature(_ language: OverviewLanguage) -> String {
        switch engine {
        case .eleven: return "eleven:\(ElevenSpeech.model):\(gender.rawValue)"
        case .openAI: return "openai:\(CloudSpeech.voice(for: gender)),\(CloudSpeech.voice(for: gender.other))"
        case nil: return "none"
        }
    }

    // MARK: Keys

    var cloudKey: String? {
        if let k = Keychain.read(account: Self.keyAccount), !k.isEmpty { return k }
        if let k = UserDefaults.standard.string(forKey: Self.fallbackKey), !k.isEmpty { return k }
        return nil
    }

    func saveCloudKey(_ raw: String) {
        let k = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !k.isEmpty else { return }
        if Keychain.save(k, account: Self.keyAccount) {
            UserDefaults.standard.removeObject(forKey: Self.fallbackKey)
        } else {
            UserDefaults.standard.set(k, forKey: Self.fallbackKey)
        }
        hasCloudKey = true
        revision += 1
    }

    func deleteCloudKey() {
        Keychain.delete(account: Self.keyAccount)
        UserDefaults.standard.removeObject(forKey: Self.fallbackKey)
        hasCloudKey = false
        revision += 1
    }

    var elevenKey: String? {
        if let k = Keychain.read(account: Self.elevenAccount), !k.isEmpty { return k }
        if let k = UserDefaults.standard.string(forKey: Self.elevenFallbackKey), !k.isEmpty { return k }
        return nil
    }

    func saveElevenKey(_ raw: String) {
        let k = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !k.isEmpty else { return }
        if Keychain.save(k, account: Self.elevenAccount) {
            UserDefaults.standard.removeObject(forKey: Self.elevenFallbackKey)
        } else {
            UserDefaults.standard.set(k, forKey: Self.elevenFallbackKey)
        }
        ElevenSpeech.forgetResolvedVoices()
        hasElevenKey = true
        revision += 1
    }

    func deleteElevenKey() {
        Keychain.delete(account: Self.elevenAccount)
        UserDefaults.standard.removeObject(forKey: Self.elevenFallbackKey)
        ElevenSpeech.forgetResolvedVoices()
        hasElevenKey = false
        revision += 1
    }
}

// MARK: - Text for speech

enum SpeechText {
    /// Removes what voices read badly (markdown, page marks) and spells out common symbols.
    static func clean(_ text: String, language: OverviewLanguage) -> String {
        let en = language.isEnglish
        var t = text
        t = t.replacingOccurrences(of: "\\[s\\.[^\\]]*\\]", with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: "\\((s|p)\\. ?[0-9–-]+\\)", with: "", options: .regularExpression)
        let words: [(String, String, String)] = [
            ("**", "", ""), ("__", "", ""), ("#", "", ""), ("•", "", ""), ("`", "", ""),
            ("→", ", ", ", "), ("⇒", ", ", ", "), ("←", ", ", ", "), ("↔", ", ", ", "),
            ("≈", " yaklaşık ", " approximately "), ("≤", " küçük eşit ", " less than or equal to "),
            ("≥", " büyük eşit ", " greater than or equal to "), ("≠", " eşit değil ", " not equal to "),
            ("±", " artı eksi ", " plus or minus "), ("×", " çarpı ", " times "), ("÷", " bölü ", " divided by "),
            ("√", " karekök ", " square root of "), ("²", " kare", " squared"), ("³", " küp", " cubed"),
            ("π", " pi ", " pi "), ("Δ", " delta ", " delta "), ("∆", " delta ", " delta "), ("α", " alfa ", " alpha "),
            ("β", " beta ", " beta "), ("γ", " gama ", " gamma "), ("μ", " mü ", " mu "), ("λ", " lamda ", " lambda "),
            ("σ", " sigma ", " sigma "), ("Σ", " toplam ", " sum "), ("∫", " integral ", " integral of "),
            ("∞", " sonsuz ", " infinity "), ("°C", " derece ", " degrees Celsius "), ("°", " derece ", " degrees "),
        ]
        for (symbol, tr, english) in words {
            t = t.replacingOccurrences(of: symbol, with: en ? english : tr)
        }
        t = t.replacingOccurrences(of: "[ \\t]{2,}", with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: " ,", with: ",")
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum StudioAudioSession {
    static func activate() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [])
        try? session.setActive(true, options: [])
    }

    static func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }
}

enum SpeechError: LocalizedError {
    case silent
    case noKey
    case cloud(Int, String)
    case eleven(Int, String)

    var errorDescription: String? {
        switch self {
        case .silent:
            return Loc.t("Ses üretilemedi. Biraz sonra tekrar dene.")
        case .noKey:
            return Loc.t("Seslendirme için Sesler ayarına ElevenLabs anahtarını ekle. Özet kaydedildi; anahtarı ekleyince menüden \"Yeniden seslendir\"i seç.")
        case let .cloud(status, message):
            switch status {
            case 401: return Loc.t("OpenAI anahtarı geçersiz. Ses ayarlarından kontrol et.")
            case 429: return Loc.t("OpenAI kotası ya da hız sınırı doldu. Biraz bekleyip tekrar dene.")
            default:
                return message.isEmpty ? Loc.t("Bulut sesi alınamadı ({0}).", "\(status)") : Loc.t("Bulut sesi alınamadı: {0}", message)
            }
        case let .eleven(status, message):
            switch status {
            case 401: return Loc.t("ElevenLabs anahtarı geçersiz ya da seslendirme izni yok. Ses ayarlarından kontrol et.")
            case 402, 403:
                return Loc.t("ElevenLabs karakter kotası bitti ya da planın bu modeli kapsamıyor.") + (message.isEmpty ? "" : " (\(message))")
            case 429: return Loc.t("ElevenLabs aynı anda çok fazla istek aldı. Biraz bekleyip tekrar dene.")
            default:
                return message.isEmpty ? Loc.t("ElevenLabs sesi alınamadı ({0}).", "\(status)") : Loc.t("ElevenLabs sesi alınamadı: {0}", message)
            }
        }
    }
}

// MARK: - OpenAI voices (stand-in)

enum CloudSpeech {
    /// The woman's and the man's voice.
    static func voice(for gender: VoiceSettings.Gender) -> String {
        gender == .female ? "coral" : "ash"
    }

    private static func instructions(_ language: OverviewLanguage) -> String {
        language.isEnglish
            ? "Speak like a warm, engaging lecturer explaining to a student: natural pace, clear articulation, lively intonation."
            : "Kusursuz Türkçe telaffuzla, öğrencisine konu anlatan sıcak ve samimi bir hoca gibi konuş: doğal tempo, net diksiyon, canlı tonlama."
    }

    /// Speaks `text` into an MP3 at `url` and returns its length in seconds.
    static func synthesize(_ text: String, voice: String, language: OverviewLanguage, apiKey: String, to url: URL) async throws -> Double {
        guard let endpoint = URL(string: "https://api.openai.com/v1/audio/speech") else { throw SpeechError.silent }
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.timeoutInterval = 120
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let models = ["gpt-4o-mini-tts", "tts-1-hd"]
        for (i, model) in models.enumerated() {
            var body: [String: Any] = ["model": model, "voice": voice, "input": String(text.prefix(4000)), "response_format": "mp3"]
            if i == 0 { body["instructions"] = instructions(language) }
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await URLSession.shared.data(for: req)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 200 {
                try data.write(to: url, options: .atomic)
                return try await duration(of: url)
            }
            let message = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])
                .flatMap { $0["error"] as? [String: Any] }
                .flatMap { $0["message"] as? String } ?? ""
            // An account without the newer model: try the classic one.
            if i == 0, status == 404 || (status == 400 && message.lowercased().contains("model")) { continue }
            throw SpeechError.cloud(status, message)
        }
        throw SpeechError.silent
    }

    static func duration(of url: URL) async throws -> Double {
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let d = try await asset.load(.duration)
        return d.seconds.isFinite ? d.seconds : 0
    }
}

// MARK: - ElevenLabs voices

/// ElevenLabs text to speech with Multilingual v2, its most natural model for Turkish and
/// English. The voices are two of ElevenLabs' own default voices, which every account has.
enum ElevenSpeech {
    static let model = "eleven_multilingual_v2"

    /// The default voices to use, best first, by name (as the account lists them) and id.
    private static let preferred: [VoiceSettings.Gender: [(name: String, id: String)]] = [
        .female: [("Sarah", "EXAVITQu4vr4xnSDxMaL"), ("Alice", "Xb7hH8MSUJpSbSDYk0k2"),
                  ("Matilda", "XrExE9yKIg1WjnnlVkGX"), ("Laura", "FGY2WhTYpPnrIDTdsKH5")],
        .male: [("Brian", "nPczCjzI2devNBz1zQrb"), ("George", "JBFqnCBsd6RMkjVDRZzb"),
                ("Daniel", "onwK4e9ZLuTAKqWW03F9"), ("Eric", "cjVigY5qzO86Huf0OWal")],
    ]

    private static let base = "https://api.elevenlabs.io/v1"

    private static func resolvedKey(_ gender: VoiceSettings.Gender) -> String {
        "voice.eleven.resolved.\(gender.rawValue)"
    }

    /// After another key: the voices are looked up again in that account.
    static func forgetResolvedVoices() {
        for g in VoiceSettings.Gender.allCases {
            UserDefaults.standard.removeObject(forKey: resolvedKey(g))
        }
    }

    /// The voice ids to try for `gender`, the one found in the account first.
    static func candidates(_ gender: VoiceSettings.Gender, apiKey: String) async -> [String] {
        let fixed = (preferred[gender] ?? []).map(\.id)
        if let known = UserDefaults.standard.string(forKey: resolvedKey(gender)) {
            return [known] + fixed.filter { $0 != known }
        }
        if let found = await lookUp(gender, apiKey: apiKey) {
            UserDefaults.standard.set(found, forKey: resolvedKey(gender))
            return [found] + fixed.filter { $0 != found }
        }
        return fixed
    }

    /// The account's own copy of the preferred voice (by name), or any default voice of that gender.
    private static func lookUp(_ gender: VoiceSettings.Gender, apiKey: String) async -> String? {
        guard let url = URL(string: "\(base)/voices") else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 20
        req.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let result = try? await URLSession.shared.data(for: req),
              (result.1 as? HTTPURLResponse)?.statusCode == 200,
              let object = (try? JSONSerialization.jsonObject(with: result.0)) as? [String: Any],
              let list = object["voices"] as? [[String: Any]] else { return nil }
        let voices = list.compactMap { v -> (id: String, name: String, gender: String, premade: Bool)? in
            guard let id = v["voice_id"] as? String, let name = v["name"] as? String else { return nil }
            let labels = v["labels"] as? [String: Any] ?? [:]
            return (id, name, ((labels["gender"] as? String) ?? "").lowercased(), (v["category"] as? String) == "premade")
        }
        for wanted in preferred[gender] ?? [] {
            if let v = voices.first(where: { $0.id == wanted.id }) { return v.id }
            if let v = voices.first(where: { $0.premade && $0.name.lowercased().hasPrefix(wanted.name.lowercased()) }) { return v.id }
        }
        return voices.first { $0.premade && $0.gender == gender.rawValue }?.id
    }

    /// Speaks `text` into an MP3 at `url` with the voice of `gender` and returns its length in seconds.
    static func synthesize(_ text: String, gender: VoiceSettings.Gender, apiKey: String, to url: URL) async throws -> Double {
        let ids = await candidates(gender, apiKey: apiKey)
        var lastError: Error = SpeechError.silent
        for id in ids {
            do {
                let d = try await synthesize(text, voice: id, apiKey: apiKey, to: url)
                UserDefaults.standard.set(id, forKey: resolvedKey(gender))
                return d
            } catch SpeechError.eleven(let status, let message) where status == 404 || (status == 400 && message.lowercased().contains("voice")) {
                // That voice is not in this account: the next one.
                lastError = SpeechError.eleven(status, message)
                UserDefaults.standard.removeObject(forKey: resolvedKey(gender))
                continue
            }
        }
        throw lastError
    }

    private static func synthesize(_ text: String, voice: String, apiKey: String, to url: URL) async throws -> Double {
        guard let endpoint = URL(string: "\(base)/text-to-speech/\(voice)?output_format=mp3_44100_128") else {
            throw SpeechError.silent
        }
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.timeoutInterval = 120
        req.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        let input = String(text.prefix(4500))
        let full: [String: Any] = [
            "text": input,
            "model_id": model,
            "voice_settings": [
                "stability": 0.5,
                "similarity_boost": 0.8,
                "style": 0.2,
                "use_speaker_boost": true,
            ],
        ]
        // When a setting is not accepted, the bare request still speaks.
        let bare: [String: Any] = ["text": input, "model_id": model]
        for (attempt, body) in [full, bare].enumerated() {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await URLSession.shared.data(for: req)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 200, !data.isEmpty {
                try data.write(to: url, options: .atomic)
                return try await CloudSpeech.duration(of: url)
            }
            if attempt == 0, status == 422 { continue }
            throw SpeechError.eleven(status, errorMessage(data))
        }
        throw SpeechError.silent
    }

    /// The message of an ElevenLabs error body ({"detail": {"message": …}} or {"detail": "…"}).
    private static func errorMessage(_ data: Data) -> String {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return "" }
        if let detail = object["detail"] as? [String: Any] {
            return (detail["message"] as? String) ?? (detail["status"] as? String) ?? ""
        }
        return (object["detail"] as? String) ?? ""
    }
}

// MARK: - Speaking

enum StudioVoicer {
    /// One segment to speak.
    struct Job: Sendable {
        let index: Int
        let text: String
        let gender: VoiceSettings.Gender
        let url: URL
    }

    /// Speaks `text` with the voice of `gender` through the engine in use.
    static func speak(_ text: String, gender: VoiceSettings.Gender, language: OverviewLanguage, to url: URL) async throws -> Double {
        let settings = VoiceSettings.shared
        if let key = settings.elevenKey {
            return try await ElevenSpeech.synthesize(text, gender: gender, apiKey: key, to: url)
        }
        if let key = settings.cloudKey {
            return try await CloudSpeech.synthesize(text, voice: CloudSpeech.voice(for: gender), language: language, apiKey: key, to: url)
        }
        throw SpeechError.noKey
    }

    /// Speaks the jobs, `limit` at a time, and returns their lengths by segment index.
    private static func speakAll(_ jobs: [Job], limit: Int, progress: @escaping @MainActor (Double) -> Void,
                                 speak: @escaping @Sendable (Job) async throws -> Double) async throws -> [Int: Double] {
        var lengths: [Int: Double] = [:]
        try await withThrowingTaskGroup(of: (Int, Double).self) { group in
            var next = 0
            while next < jobs.count && next < limit {
                let job = jobs[next]
                group.addTask {
                    let d = try await speak(job)
                    return (job.index, d)
                }
                next += 1
            }
            while let result = try await group.next() {
                lengths[result.0] = result.1
                await progress(Double(lengths.count) / Double(max(jobs.count, 1)))
                if next < jobs.count {
                    let job = jobs[next]
                    group.addTask {
                        let d = try await speak(job)
                        return (job.index, d)
                    }
                    next += 1
                }
            }
        }
        return lengths
    }

    /// Speaks every segment of the overview into files in `folder` and stores their lengths.
    @MainActor
    static func voice(_ overview: Overview, folder: URL, progress: @escaping @MainActor (Double) -> Void) async throws -> Overview {
        let settings = VoiceSettings.shared
        guard let engine = settings.engine else { throw SpeechError.noKey }
        var o = overview
        let language = o.language
        let texts = o.segmentTexts.map { SpeechText.clean($0, language: language) }
        let hosts: [Int] = o.kind == .video ? Array(repeating: 0, count: texts.count) : o.lines.map { min(max($0.host, 0), 1) }
        for f in o.audioFiles where !f.isEmpty {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(f))
        }
        let stamp = Int(Date().timeIntervalSince1970) % 1_000_000
        let urls = texts.indices.map { folder.appendingPathComponent("seg-\(stamp)-\($0).mp3") }
        var durations = Array(repeating: 0.6, count: texts.count)
        var files = Array(repeating: "", count: texts.count)
        let jobs = texts.indices.filter { !texts[$0].isEmpty }.map { i in
            Job(index: i, text: texts[i], gender: settings.gender(host: hosts.indices.contains(i) ? hosts[i] : 0), url: urls[i])
        }
        // ElevenLabs limits how many requests an account runs at once; OpenAI takes a few more.
        let lengths = try await speakAll(jobs, limit: engine == .eleven ? 3 : 4, progress: progress) { job in
            try await speak(job.text, gender: job.gender, language: language, to: job.url)
        }
        for (i, d) in lengths {
            durations[i] = d
            files[i] = urls[i].lastPathComponent
        }
        o.durations = durations
        o.audioFiles = files
        o.voiceSignature = settings.signature(language)
        return o
    }
}

/// Speaks right away (answers in the player, the samples in the settings).
final class LiveSpeaker: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var isSpeaking = false
    @Published private(set) var failure: String?
    private var player: AVAudioPlayer?
    private var work: Task<Void, Never>?

    /// A host speaks `text` with its voice.
    func speak(_ text: String, language: OverviewLanguage, host: Int) {
        speak(text, language: language, gender: VoiceSettings.shared.gender(host: host))
    }

    func speak(_ text: String, language: OverviewLanguage, gender: VoiceSettings.Gender) {
        stop()
        failure = nil
        guard VoiceSettings.shared.engine != nil else {
            failure = SpeechError.noKey.errorDescription
            return
        }
        isSpeaking = true
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("murekkep-say-\(UUID().uuidString).mp3")
        let clean = SpeechText.clean(text, language: language)
        work = Task { @MainActor [weak self] in
            do {
                _ = try await StudioVoicer.speak(clean, gender: gender, language: language, to: url)
                guard let self, !Task.isCancelled else { return }
                StudioAudioSession.activate()
                let p = try AVAudioPlayer(contentsOf: url)
                p.delegate = self
                self.player = p
                self.work = nil
                p.play()
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.work = nil
                self.isSpeaking = false
                self.failure = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    func stop() {
        work?.cancel()
        work = nil
        player?.stop()
        player = nil
        isSpeaking = false
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.player = nil
            if self.work == nil { self.isSpeaking = false }
        }
    }
}

// MARK: - Settings screen

struct VoiceSettingsView: View {
    @ObservedObject private var voices = VoiceSettings.shared
    @StateObject private var speaker = LiveSpeaker()
    @Environment(\.dismiss) private var dismiss
    @State private var keyInput = ""
    @State private var elevenKeyInput = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(Loc.t("Ses"), selection: $voices.gender) {
                        ForEach(VoiceSettings.Gender.allCases) { g in
                            Text(g.title).tag(g)
                        }
                    }
                    .pickerStyle(.segmented)
                    HStack(spacing: 12) {
                        sampleButton(.turkish, title: "Türkçe")
                        sampleButton(.english, title: "English")
                    }
                    .buttonStyle(.bordered)
                    .disabled(voices.engine == nil)
                    if let failure = speaker.failure {
                        Text(failure)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text(Loc.t("Anlatıcının sesi"))
                } footer: {
                    Text(Loc.t("İki sabit, doğal ses var: bir kadın ve bir erkek sesi; ikisi de Türkçe ve İngilizce konuşur. Sesli sohbette ikinci sunucu öbür sesle konuşur."))
                }

                Section {
                    if voices.hasElevenKey {
                        Label(Loc.t("ElevenLabs anahtarı kayıtlı"), systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                        Button(Loc.t("Anahtarı sil"), role: .destructive) {
                            voices.deleteElevenKey()
                        }
                    } else {
                        SecureField(Loc.t("ElevenLabs API anahtarı"), text: $elevenKeyInput)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button(Loc.t("Kaydet")) {
                            voices.saveElevenKey(elevenKeyInput)
                            elevenKeyInput = ""
                        }
                        .disabled(elevenKeyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: {
                    Text(Loc.t("ElevenLabs API anahtarı"))
                } footer: {
                    Text(Loc.t("Sesler ElevenLabs'in en doğal modeliyle (Multilingual v2) üretilir. Anahtar elevenlabs.io › profil › API Keys bölümünden alınır (seslendirme izni açık olmalı) ve yalnızca bu cihazda saklanır. Metinler seslendirme için ElevenLabs'e gönderilir; karakterler hesabının kotasından düşer."))
                }

                Section {
                    if voices.hasCloudKey {
                        Label(Loc.t("OpenAI anahtarı kayıtlı"), systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                        Button(Loc.t("Anahtarı sil"), role: .destructive) {
                            voices.deleteCloudKey()
                        }
                    } else {
                        SecureField("sk-…", text: $keyInput)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button(Loc.t("Kaydet")) {
                            voices.saveCloudKey(keyInput)
                            keyInput = ""
                        }
                        .disabled(keyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: {
                    Text(Loc.t("Yedek: OpenAI API anahtarı (isteğe bağlı)"))
                } footer: {
                    Text(Loc.t("ElevenLabs anahtarı yokken OpenAI'nin aynı türden kadın ve erkek sesi kullanılır."))
                }
            }
            .navigationTitle(Loc.t("Sesler"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(Loc.t("Bitti")) { dismiss() }
                }
            }
            .onDisappear { speaker.stop() }
        }
    }

    private func sampleButton(_ language: OverviewLanguage, title: String) -> some View {
        Button {
            if speaker.isSpeaking {
                speaker.stop()
            } else {
                speaker.speak(sample(language), language: language, gender: voices.gender)
            }
        } label: {
            Label(title, systemImage: speaker.isSpeaking ? "stop.fill" : "play.fill")
                .frame(maxWidth: .infinity)
        }
        .accessibilityLabel(Loc.t("Dinle: {0}", title))
    }

    private func sample(_ language: OverviewLanguage) -> String {
        language.isEnglish
            ? "Hi! Today we're turning your notes into a short lesson you'll remember."
            : "Merhaba! Bugün notlarını kısa ve akılda kalıcı bir derse çeviriyoruz."
    }
}
