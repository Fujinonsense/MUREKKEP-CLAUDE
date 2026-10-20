import AVFoundation
import SwiftUI
import UIKit

// MARK: - Settings

/// The studio's voices: the app's own embedded voices (Supertonic 3, see `EmbeddedVoices`), five
/// women's and five men's, each speaking Turkish and English. The user picks which woman's and which
/// man's voice; the narrator speaks with the chosen gender, and in a two-host podcast the second host
/// with the other one. Nothing leaves the iPad and no key is needed.
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

    /// The narrator's voice.
    @Published var gender: Gender {
        didSet { save() }
    }
    /// Which of the five women's voices (0–4).
    @Published var femaleVoice: Int {
        didSet { save() }
    }
    /// Which of the five men's voices (0–4).
    @Published var maleVoice: Int {
        didSet { save() }
    }
    /// 0.85 (slower) … 1.3 (faster).
    @Published var speed: Double {
        didSet { save() }
    }
    /// Bumped when anything that shapes the sound changes.
    @Published private(set) var revision = 0

    private init() {
        let d = UserDefaults.standard
        gender = Gender(rawValue: d.string(forKey: "voice.gender") ?? "") ?? .female
        femaleVoice = min(max(d.integer(forKey: "voice.female"), 0), EmbeddedVoices.women.count - 1)
        maleVoice = min(max(d.integer(forKey: "voice.male"), 0), EmbeddedVoices.men.count - 1)
        let s = d.double(forKey: "voice.speed")
        speed = s >= 0.85 && s <= 1.3 ? s : 1.0
    }

    private func save() {
        let d = UserDefaults.standard
        d.set(gender.rawValue, forKey: "voice.gender")
        d.set(femaleVoice, forKey: "voice.female")
        d.set(maleVoice, forKey: "voice.male")
        d.set(speed, forKey: "voice.speed")
        revision += 1
    }

    /// The narrator (host 0) speaks with the chosen voice, the second host with the other one.
    func gender(host: Int) -> Gender {
        host == 0 ? gender : gender.other
    }

    /// The model's speaker id for a gender.
    func sid(_ gender: Gender) -> Int32 {
        gender == .female ? EmbeddedVoices.women[femaleVoice] : EmbeddedVoices.men[maleVoice]
    }

    /// Changes when anything that shapes the sound changes (an overview is voiced again then).
    func signature(_ language: OverviewLanguage) -> String {
        "supertonic3:\(sid(gender(host: 0))),\(sid(gender(host: 1))):\(String(format: "%.2f", speed))"
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
    case unavailable

    var errorDescription: String? {
        switch self {
        case .silent:
            return Loc.t("Ses üretilemedi. Biraz sonra tekrar dene.")
        case .unavailable:
            return Loc.t("Bu derlemede gömülü sesler yok. Özet sessiz kaydedildi; sesli derlemede menüden \"Yeniden seslendir\"i seç.")
        }
    }
}

// MARK: - Speaking

enum StudioVoicer {
    /// Speaks `text` with the chosen voice of `gender`.
    @MainActor
    static func speak(_ text: String, gender: VoiceSettings.Gender, language: OverviewLanguage, to url: URL) async throws -> Double {
        let settings = VoiceSettings.shared
        return try await EmbeddedVoices.speak(text, language: language, sid: settings.sid(gender), speed: Float(settings.speed), to: url)
    }

    /// Speaks every segment of the overview into files in `folder` (one after another: the voice runs
    /// on the iPad) and stores their lengths.
    @MainActor
    static func voice(_ overview: Overview, folder: URL, progress: @escaping @MainActor (Double) -> Void) async throws -> Overview {
        guard EmbeddedVoices.isAvailable else { throw SpeechError.unavailable }
        let settings = VoiceSettings.shared
        var o = overview
        let language = o.language
        let texts = o.segmentTexts
        let hosts: [Int] = o.kind == .video ? Array(repeating: 0, count: texts.count) : o.lines.map { min(max($0.host, 0), 1) }
        for f in o.audioFiles where !f.isEmpty {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(f))
        }
        let stamp = Int(Date().timeIntervalSince1970) % 1_000_000
        var durations = Array(repeating: 0.6, count: texts.count)
        var files = Array(repeating: "", count: texts.count)
        var spoken = 0
        for (i, text) in texts.enumerated() {
            try Task.checkCancellation()
            progress(Double(i) / Double(max(texts.count, 1)))
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let url = folder.appendingPathComponent("seg-\(stamp)-\(i).wav")
            let gender = settings.gender(host: hosts.indices.contains(i) ? hosts[i] : 0)
            durations[i] = try await speak(text, gender: gender, language: language, to: url)
            files[i] = url.lastPathComponent
            spoken += 1
        }
        guard spoken > 0 else { throw SpeechError.silent }
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
        guard EmbeddedVoices.isAvailable else {
            failure = SpeechError.unavailable.errorDescription
            return
        }
        isSpeaking = true
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("murekkep-say-\(UUID().uuidString).wav")
        work = Task { @MainActor [weak self] in
            do {
                _ = try await StudioVoicer.speak(text, gender: gender, language: language, to: url)
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

    var body: some View {
        NavigationStack {
            Form {
                if !EmbeddedVoices.isAvailable {
                    Section {
                        Label(Loc.t("Bu derlemede gömülü sesler yok. Sesli derleme GitHub'daki iş akışıyla yapılır."),
                              systemImage: "speaker.slash")
                            .foregroundStyle(.orange)
                    }
                }
                Section {
                    Picker(Loc.t("Anlatıcı"), selection: $voices.gender) {
                        ForEach(VoiceSettings.Gender.allCases) { g in
                            Text(g.title).tag(g)
                        }
                    }
                    .pickerStyle(.segmented)
                    Picker(Loc.t("Kadın sesi"), selection: $voices.femaleVoice) {
                        ForEach(EmbeddedVoices.women.indices, id: \.self) { i in
                            Text("\(i + 1)").tag(i)
                        }
                    }
                    .pickerStyle(.segmented)
                    Picker(Loc.t("Erkek sesi"), selection: $voices.maleVoice) {
                        ForEach(EmbeddedVoices.men.indices, id: \.self) { i in
                            Text("\(i + 1)").tag(i)
                        }
                    }
                    .pickerStyle(.segmented)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Loc.t("Hız: {0}", String(format: "%.2f×", voices.speed)))
                            .font(.subheadline)
                        Slider(value: $voices.speed, in: 0.85...1.3, step: 0.05)
                    }
                    HStack(spacing: 12) {
                        sampleButton(.turkish, title: "Türkçe")
                        sampleButton(.english, title: "English")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!EmbeddedVoices.isAvailable)
                    if let failure = speaker.failure {
                        Text(failure)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text(Loc.t("Anlatıcının sesi"))
                } footer: {
                    Text(Loc.t("Sesler uygulamanın içinde, iPad'de üretilir: internet ve anahtar gerekmez. Her ses Türkçe ve İngilizce konuşur; sesli sohbette ikinci sunucu öbür cinsiyetteki seçili sesle konuşur."))
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
