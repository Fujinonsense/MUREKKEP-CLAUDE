import Foundation
import SwiftUI

// MARK: - Options

/// What the studio makes from a course's sources.
enum OverviewKind: String, Codable, CaseIterable, Identifiable {
    case video
    case audio

    var id: String { rawValue }

    var title: String { self == .video ? Loc.t("Video özeti") : Loc.t("Sesli özet") }
    var symbol: String { self == .video ? "play.rectangle.fill" : "waveform" }

    var blurb: String {
        switch self {
        case .video: return Loc.t("Slaytlar, kaynaktaki şekiller, sesli anlatım ve altyazıyla bir ders videosu.")
        case .audio: return Loc.t("İki sunucunun konuyu sohbet ederek anlattığı podcast. Arada soru sorabilirsin.")
        }
    }
}

/// How an overview tells the material.
enum OverviewFormat: String, Codable, CaseIterable, Identifiable {
    case explainer
    case brief
    case story
    case exam
    case critique
    case debate

    var id: String { rawValue }

    static func options(for kind: OverviewKind) -> [OverviewFormat] {
        kind == .video ? [.explainer, .brief, .story, .exam] : [.explainer, .brief, .critique, .debate, .exam]
    }

    func title(for kind: OverviewKind) -> String {
        switch self {
        case .explainer: return kind == .video ? Loc.t("Açıklayıcı") : Loc.t("Derinlemesine")
        case .brief: return Loc.t("Kısa özet")
        case .story: return Loc.t("Vaka / hikâye")
        case .exam: return Loc.t("Sınav provası")
        case .critique: return Loc.t("Eleştiri")
        case .debate: return Loc.t("Tartışma")
        }
    }

    var symbol: String {
        switch self {
        case .explainer: return "graduationcap"
        case .brief: return "bolt"
        case .story: return "book"
        case .exam: return "checklist"
        case .critique: return "magnifyingglass"
        case .debate: return "bubble.left.and.bubble.right"
        }
    }

    func detail(for kind: OverviewKind) -> String {
        switch self {
        case .explainer:
            return kind == .video ? Loc.t("Konuyu baştan sona mantıklı bir sırayla öğretir.") : Loc.t("Konuyu ayrıntılı, katmanlı ve bağlantılarıyla konuşur.")
        case .brief: return Loc.t("Yalnızca en önemli fikirler, hızlı tempo.")
        case .story: return Loc.t("Konuyu bir vaka ya da örnek olay üzerinden anlatır.")
        case .exam: return Loc.t("Sınavda çıkabilecek yerler, sık hatalar ve ara sorular.")
        case .critique: return Loc.t("Kaynakları uzman gözüyle değerlendirir: güçlü yanlar, eksikler.")
        case .debate: return Loc.t("Sunucular farklı görüşleri savunur, sonunda ortak sonuca varır.")
        }
    }

    /// Instruction for the script writer.
    func prompt(for kind: OverviewKind) -> String {
        switch self {
        case .explainer:
            return kind == .video
                ? "Açıklayıcı: konuyu baştan sona, temelden ileriye mantıklı bir sırayla öğret; her kavramı bir örnekle bağla."
                : "Derinlemesine sohbet: konuyu ayrıntılı ve katmanlı konuşun; kavramlar arasındaki bağlantıları, nedenleri ve sonuçları açın."
        case .brief:
            return "Kısa özet: yalnızca en önemli 4-6 fikir; hızlı, net, tekrar etmeyen bir tempo."
        case .story:
            return "Vaka / hikâye: konuyu gerçekçi bir vaka ya da örnek olay üzerinden anlat (tıpta hasta vakası, mühendislikte bir tasarım problemi gibi); kavramları hikâyenin içinde aç."
        case .exam:
            return kind == .video
                ? "Sınav provası: sınavda çıkabilecek noktaları vurgula, sık yapılan hataları söyle, araya 2-4 quiz sahnesi koy."
                : "Sınav provası: bir sunucu diğerine sınav tarzı sorular sorsun, cevaplar gerekçesiyle açıklansın, sık yapılan hatalar söylensin."
        case .critique:
            return "Eleştiri: kaynakları uzman gözüyle değerlendirin; güçlü yanlar, eksikler, tartışmalı ya da güncelliğini yitirmiş noktalar."
        case .debate:
            return "Tartışma: iki sunucu konunun farklı yorumlarını ya da yaklaşımlarını kanıtlarla savunsun, sonunda ortak bir sonuca varsın."
        }
    }
}

enum OverviewLength: String, Codable, CaseIterable, Identifiable {
    case short
    case standard
    case long

    var id: String { rawValue }

    var title: String {
        switch self {
        case .short: return Loc.t("Kısa")
        case .standard: return Loc.t("Standart")
        case .long: return Loc.t("Uzun")
        }
    }

    var minutes: Int {
        switch self {
        case .short: return 3
        case .standard: return 7
        case .long: return 12
        }
    }

    var scenes: ClosedRange<Int> {
        switch self {
        case .short: return 6...8
        case .standard: return 10...14
        case .long: return 16...22
        }
    }
}

enum OverviewLevel: String, Codable, CaseIterable, Identifiable {
    case intro
    case university
    case expert

    var id: String { rawValue }

    var title: String {
        switch self {
        case .intro: return Loc.t("Temel")
        case .university: return Loc.t("Üniversite")
        case .expert: return Loc.t("Uzman")
        }
    }

    var prompt: String {
        switch self {
        case .intro: return "Temel seviye: ön bilgi varsayma, terimleri günlük dille açıkla."
        case .university: return "Üniversite seviyesi: lisans öğrencisine uygun; terimleri doğru kullan ve kısaca tanımla."
        case .expert: return "Uzman seviyesi: temel tanımları atla; mekanizmalara, nüanslara ve istisnalara odaklan."
        }
    }
}

/// The one language of an overview: every title, line and voice uses it. There is no automatic choice,
/// because a guess from an English book with a Turkish user ended up half in each language.
enum OverviewLanguage: String, Codable, CaseIterable, Identifiable {
    case turkish
    case english

    /// The app's language: the default for a new overview.
    static var app: OverviewLanguage { Loc.isEnglish ? .english : .turkish }

    /// Earlier versions also stored "auto": it becomes the app's language.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = OverviewLanguage(rawValue: raw) ?? .app
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .turkish: return "Türkçe"
        case .english: return "English"
        }
    }

    /// BCP 47 code for speech.
    var code: String { self == .english ? "en-US" : "tr-TR" }

    var isEnglish: Bool { self == .english }

    /// Words a voice reads in a minute (Turkish words are longer).
    var wordsPerMinute: Int { self == .english ? 150 : 112 }

    var hostNames: [String] { self == .english ? ["Alex", "Sam"] : ["Deniz", "Ekin"] }
}

/// The look of the video's slides.
enum SlideTheme: String, Codable, CaseIterable, Identifiable {
    /// Grid paper, one accent colour, numbered section cards and sketch illustrations.
    case explainer
    case modern
    case notebook
    case chalkboard
    case night

    var id: String { rawValue }

    var title: String {
        switch self {
        case .explainer: return Loc.t("Açıklayıcı")
        case .modern: return "Modern"
        case .notebook: return Loc.t("Defter")
        case .chalkboard: return Loc.t("Kara tahta")
        case .night: return Loc.t("Gece")
        }
    }

    var detail: String {
        switch self {
        case .explainer: return Loc.t("Numaralı bölümler, çizimler")
        case .modern: return Loc.t("Temiz kartlar")
        case .notebook: return Loc.t("Mürekkeple yazılır")
        case .chalkboard: return Loc.t("Tebeşirle yazılır")
        case .night: return Loc.t("Koyu ve parlak")
        }
    }
}

struct OverviewOptions: Codable, Hashable {
    var kind: OverviewKind = .video
    var format: OverviewFormat = .explainer
    var length: OverviewLength = .standard
    var level: OverviewLevel = .university
    var language: OverviewLanguage = .app
    var theme: SlideTheme = .explainer
    var focus: String = ""
}

// MARK: - Content

enum SceneLayout: String, Codable, CaseIterable {
    case title
    case bullets
    case figure
    case definition
    case compare
    case steps
    case quote
    case quiz
    case summary
    /// A big question with highlighted words (the hook and the closing question).
    case question
    /// The roadmap: the sections as numbered tiles.
    case agenda
    /// A section card with a big number.
    case section
}

struct SceneColumn: Codable, Hashable {
    var title: String
    var items: [String]
}

/// A picture from a source PDF: which source, which page, optionally which part of it.
struct FigureRef: Codable, Hashable {
    /// Index into `Overview.sourceIDs`.
    var source: Int
    /// 0-based page.
    var page: Int
    /// x, y, width, height as fractions of the page (top-left origin).
    var box: [Double]?
}

struct OverviewScene: Codable, Hashable, Identifiable {
    var id = UUID()
    var layout: SceneLayout
    var title: String
    var subtitle: String?
    var bullets: [String]
    var narration: String
    var term: String?
    var definition: String?
    var left: SceneColumn?
    var right: SceneColumn?
    var choices: [String]
    var answer: Int?
    var figure: FigureRef?
    /// "art:heart" (the app's drawings), "sf:waveform.path.ecg" (a system symbol) or "file:art-….png"
    /// (an illustration in the overview's folder).
    var art: String?
    /// The section's number on a section card.
    var number: Int?

    init(layout: SceneLayout, title: String, subtitle: String? = nil, bullets: [String] = [], narration: String,
         term: String? = nil, definition: String? = nil, left: SceneColumn? = nil, right: SceneColumn? = nil,
         choices: [String] = [], answer: Int? = nil, figure: FigureRef? = nil, art: String? = nil) {
        self.layout = layout
        self.title = title
        self.subtitle = subtitle
        self.bullets = bullets
        self.narration = narration
        self.term = term
        self.definition = definition
        self.left = left
        self.right = right
        self.choices = choices
        self.answer = answer
        self.figure = figure
        self.art = art
    }
}

struct DialogueLine: Codable, Hashable, Identifiable {
    var id = UUID()
    /// 0 or 1.
    var host: Int
    var text: String
    /// Set on the first line of a chapter.
    var chapter: String?
}

struct Overview: Codable, Hashable, Identifiable {
    var id = UUID()
    var title: String
    var sectionID: UUID?
    var sourceIDs: [UUID]
    var sourceTitles: [String]
    var created = Date()
    var options: OverviewOptions
    /// The language it was written and voiced in.
    var language: OverviewLanguage
    var hosts: [String]
    var scenes: [OverviewScene] = []
    var lines: [DialogueLine] = []
    /// Which brain wrote the script ("Claude Sonnet 5.5", "Cihazda"…).
    var engine: String = ""
    /// Seconds of each spoken segment (a scene's narration or a dialogue line).
    var durations: [Double] = []
    /// Audio file of each segment, relative to the overview's folder.
    var audioFiles: [String] = []
    /// The voices the audio was made with.
    var voiceSignature: String = ""

    var kind: OverviewKind { options.kind }
    var segmentTexts: [String] { kind == .video ? scenes.map(\.narration) : lines.map(\.text) }

    /// Gives a segment (a scene's narration or a dialogue line) another spoken text.
    mutating func setSegmentText(_ i: Int, _ text: String) {
        if kind == .video {
            if scenes.indices.contains(i) { scenes[i].narration = text }
        } else if lines.indices.contains(i) {
            lines[i].text = text
        }
    }

    /// Leaves these segments out; a dropped line's chapter title moves to the next line kept.
    mutating func removeSegments(_ indices: Set<Int>) {
        guard !indices.isEmpty else { return }
        if kind == .video {
            scenes = scenes.enumerated().filter { !indices.contains($0.offset) }.map(\.element)
            return
        }
        var kept: [DialogueLine] = []
        var pending: String?
        for (i, line) in lines.enumerated() {
            if indices.contains(i) {
                if pending == nil, let chapter = line.chapter, !chapter.isEmpty { pending = chapter }
                continue
            }
            var next = line
            if let chapter = pending, (next.chapter ?? "").isEmpty { next.chapter = chapter }
            pending = nil
            kept.append(next)
        }
        lines = kept
    }

    var isVoiced: Bool { !durations.isEmpty && durations.count == segmentTexts.count && audioFiles.count == durations.count }

    var timeline: OverviewTimeline { OverviewTimeline(durations: durations, kind: kind) }

    /// Chapters for the player.
    var chapters: [OverviewChapter] {
        if kind == .video {
            return scenes.indices.map { OverviewChapter(title: scenes[$0].title, segment: $0) }
        }
        var out: [OverviewChapter] = []
        for i in lines.indices {
            if let c = lines[i].chapter, !c.isEmpty { out.append(OverviewChapter(title: c, segment: i)) }
        }
        if out.isEmpty, !lines.isEmpty { out.append(OverviewChapter(title: L10n.start(language), segment: 0)) }
        return out
    }

    /// The whole script as plain text (sharing, questions).
    var scriptText: String {
        if kind == .video {
            return scenes.enumerated().map { (i: Int, s: OverviewScene) -> String in
                var parts = ["\(i + 1). \(s.title)"]
                if let sub = s.subtitle, !sub.isEmpty { parts.append(sub) }
                parts += s.bullets.map { "• " + $0 }
                parts.append(s.narration)
                return parts.joined(separator: "\n")
            }.joined(separator: "\n\n")
        }
        return lines.map { (line: DialogueLine) -> String in
            var s = ""
            if let c = line.chapter, !c.isEmpty { s += "\n## \(c)\n" }
            let name = hosts.indices.contains(line.host) ? hosts[line.host] : "?"
            return s + "\(name): \(line.text)"
        }.joined(separator: "\n")
    }
}

struct OverviewChapter: Identifiable, Hashable {
    var title: String
    var segment: Int
    var id: Int { segment }
}

enum L10n {
    static func start(_ language: OverviewLanguage) -> String { language.isEnglish ? "Start" : "Başlangıç" }
}

/// When each spoken segment starts, with short pauses between them.
struct OverviewTimeline {
    let starts: [Double]
    let durations: [Double]
    let total: Double
    let gap: Double
    let kind: OverviewKind

    init(durations: [Double], kind: OverviewKind) {
        self.kind = kind
        self.durations = durations
        let lead = kind == .video ? 0.8 : 0.4
        let gap = kind == .video ? 0.9 : 0.3
        let tail = kind == .video ? 2.0 : 0.8
        var t = lead
        var starts: [Double] = []
        for d in durations {
            starts.append(t)
            t += max(d, 0.2) + gap
        }
        self.starts = starts
        self.gap = gap
        total = durations.isEmpty ? 0 : t - gap + tail
    }

    /// The segment being spoken (or the last one before a pause) at `time`.
    func segment(at time: Double) -> Int {
        guard !starts.isEmpty else { return 0 }
        let early = kind == .video ? 0.5 : 0.05
        // Starts only grow: count those already reached (binary search), the last of them is current.
        var lo = 0
        var hi = starts.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if starts[mid] - early <= time { lo = mid + 1 } else { hi = mid }
        }
        return max(lo - 1, 0)
    }

    /// When the scene's slide comes in (a little before its narration).
    func sceneStart(_ i: Int) -> Double {
        guard starts.indices.contains(i) else { return 0 }
        return i == 0 ? 0 : starts[i] - 0.5
    }

    func end(of i: Int) -> Double {
        guard starts.indices.contains(i) else { return total }
        return starts[i] + durations[i]
    }
}

// MARK: - Store

/// The studio's overviews on disk: Documents/Murekkep/Studio/overviews.json plus a folder per
/// overview with its audio and exports.
final class StudioStore: ObservableObject {
    @Published private(set) var overviews: [Overview] = []
    @Published private(set) var jobs: [StudioJob] = []
    /// The overview that just got ready (the library shows a banner).
    @Published var justFinished: UUID?
    /// The last overview job started; the next one waits for it.
    private var queueTail: Task<Void, Never>?

    let root: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        root = docs.appendingPathComponent("Murekkep", isDirectory: true).appendingPathComponent("Studio", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        load()
    }

    private var indexURL: URL { root.appendingPathComponent("overviews.json") }

    func folder(for id: UUID) -> URL {
        let url = root.appendingPathComponent(id.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Only a path: the cards ask for it on every draw, so it creates nothing.
    func thumbnailURL(for id: UUID) -> URL {
        root.appendingPathComponent(id.uuidString, isDirectory: true).appendingPathComponent("thumb.jpg")
    }

    func overview(_ id: UUID) -> Overview? {
        overviews.first { $0.id == id }
    }

    func overviews(in sectionID: UUID?) -> [Overview] {
        guard let sectionID else { return overviews }
        return overviews.filter { $0.sectionID == sectionID }
    }

    func jobs(in sectionID: UUID?) -> [StudioJob] {
        guard let sectionID else { return jobs }
        return jobs.filter { $0.sectionID == sectionID }
    }

    private func load() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: indexURL),
              let list = try? decoder.decode([Overview].self, from: data) else { return }
        overviews = list.sorted { $0.created > $1.created }
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(overviews) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    func save(_ overview: Overview) {
        if let i = overviews.firstIndex(where: { $0.id == overview.id }) {
            overviews[i] = overview
        } else {
            overviews.insert(overview, at: 0)
        }
        persist()
    }

    func rename(_ id: UUID, to title: String) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, let i = overviews.firstIndex(where: { $0.id == id }) else { return }
        overviews[i].title = t
        persist()
    }

    func delete(_ id: UUID) {
        try? FileManager.default.removeItem(at: root.appendingPathComponent(id.uuidString, isDirectory: true))
        overviews.removeAll { $0.id == id }
        persist()
    }

    /// Overviews of a deleted course stay in the studio without a course.
    func detachSection(_ sectionID: UUID) {
        for i in overviews.indices where overviews[i].sectionID == sectionID {
            overviews[i].sectionID = nil
        }
        persist()
    }

    // MARK: Making overviews

    /// Starts writing and voicing an overview in the background; its progress shows as a job.
    /// `chapter`: only that chapter of the (single) source. Overviews are made one at a time: reading,
    /// writing and voicing several at once would make the iPad stutter.
    @MainActor
    func start(options: OverviewOptions, sources: [NoteMeta], sectionID: UUID?, engine: StudioEngine,
               library: LibraryStore, settings: AppSettings, chapter: BookChapter? = nil) {
        let title = chapter.map { Loc.t("Bölüm {0} · {1}", "\($0.number)", $0.title) }
            ?? (sources.count == 1 ? sources[0].title : (library.sections.first { $0.id == sectionID }?.name ?? Loc.t("Kaynaklar")))
        let job = StudioJob(kind: options.kind, sectionID: sectionID, title: title)
        jobs.insert(job, at: 0)
        let previous = queueTail
        if previous != nil { job.phase = Loc.t("Sırada…") }
        job.task = Task { @MainActor [weak self] in
            await previous?.value
            guard let self else { return }
            // The free plan's use counts only for an overview that gets made: cancelled, stopped or
            // failed, it is given back (a failed job offers a retry, which counts again).
            var made = false
            defer { if !made { ProStore.shared.refund(.overview) } }
            if Task.isCancelled {
                self.jobs.removeAll { $0.id == job.id }
                return
            }
            // The app may leave the screen in the middle: iOS gives it a while to go on.
            let background = BackgroundWork("studio")
            defer { background.end() }
            do {
                job.phase = Loc.t("Kaynaklar okunuyor…")
                job.progress = 0.03
                let material = await StudioMaterial.gather(sources, library: library, chapter: chapter) { done, total in
                    Task { @MainActor in
                        job.phase = Loc.t("Sayfalar okunuyor ({0}/{1})…", "\(done + 1)", "\(total)")
                        job.progress = 0.03 + 0.05 * Double(done + 1) / Double(max(total, 1))
                    }
                }
                try Task.checkCancellation()
                job.phase = Loc.t("Senaryo yazılıyor…")
                job.progress = 0.08
                // Stopped by the background (the GPU may not be used there), the script is written
                // again once the app is back on screen, by the same writer.
                var overview = try await BackgroundWork.retrying(paused: { job.phase = $0 }) {
                    try await StudioWriter.write(options: options, material: material, engine: engine,
                                                 library: library, settings: settings) { fraction, phase in
                        job.progress = 0.08 + 0.52 * fraction
                        if let phase { job.phase = phase }
                    }
                }
                overview.sectionID = sectionID
                try Task.checkCancellation()
                let folder = self.folder(for: overview.id)
                if overview.kind == .video && (options.theme == .explainer || options.theme == .modern) {
                    job.phase = Loc.t("Çizimler hazırlanıyor…")
                    await StudioIllustrator.illustrate(&overview, folder: folder) { fraction in
                        job.progress = 0.58 + 0.02 * fraction
                    }
                    try Task.checkCancellation()
                }
                job.phase = Loc.t("Seslendiriliyor…")
                job.progress = 0.6
                guard EmbeddedVoices.isAvailable else {
                    // A build without the embedded voices: the script is kept, silent.
                    await OverviewThumbnail.make(for: overview, folder: folder, library: library)
                    self.save(overview)
                    made = true
                    job.phase = Loc.t("Sessiz kaydedildi")
                    job.error = SpeechError.unavailable.errorDescription
                    return
                }
                overview = try await StudioVoicer.voice(overview, folder: folder) { fraction in
                    job.progress = 0.6 + 0.38 * fraction
                }
                job.progress = 0.99
                job.phase = Loc.t("Son dokunuşlar…")
                await OverviewThumbnail.make(for: overview, folder: folder, library: library)
                self.save(overview)
                made = true
                self.jobs.removeAll { $0.id == job.id }
                self.justFinished = overview.id
            } catch is CancellationError {
                self.jobs.removeAll { $0.id == job.id }
            } catch let error as URLError where error.code == .cancelled {
                self.jobs.removeAll { $0.id == job.id }
            } catch {
                job.phase = Loc.t("Olmadı")
                job.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                // The same overview again, from the start; the use given back is counted again (with
                // none left the Pro page opens instead).
                job.retry = { [weak self] in
                    Task { @MainActor in
                        guard let self, ProStore.shared.use(.overview) else { return }
                        self.jobs.removeAll { $0.id == job.id }
                        self.start(options: options, sources: sources, sectionID: sectionID, engine: engine,
                                   library: library, settings: settings, chapter: chapter)
                    }
                }
            }
        }
        queueTail = job.task
    }

    /// Makes the audio again with the voices chosen now.
    @MainActor
    func revoice(_ overview: Overview, library: LibraryStore) {
        let job = StudioJob(kind: overview.kind, sectionID: overview.sectionID, title: overview.title)
        jobs.insert(job, at: 0)
        job.task = Task { @MainActor [weak self] in
            guard let self else { return }
            let background = BackgroundWork("studio-voice")
            defer { background.end() }
            do {
                job.phase = Loc.t("Yeniden seslendiriliyor…")
                let folder = self.folder(for: overview.id)
                let updated = try await StudioVoicer.voice(overview, folder: folder) { fraction in
                    job.progress = 0.95 * fraction
                }
                await OverviewThumbnail.make(for: updated, folder: folder, library: library)
                self.save(updated)
                self.jobs.removeAll { $0.id == job.id }
                self.justFinished = updated.id
            } catch is CancellationError {
                self.jobs.removeAll { $0.id == job.id }
            } catch {
                job.phase = Loc.t("Olmadı")
                job.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    func dismiss(_ job: StudioJob) {
        job.task?.cancel()
        jobs.removeAll { $0.id == job.id }
    }
}

/// One overview being made.
final class StudioJob: ObservableObject, Identifiable {
    let id = UUID()
    let kind: OverviewKind
    let sectionID: UUID?
    let title: String
    @Published var phase = Loc.t("Hazırlanıyor…")
    @Published var progress: Double = 0
    @Published var error: String?
    var task: Task<Void, Never>?
    /// Starts the job again after it failed (set with `error`).
    var retry: (() -> Void)?

    init(kind: OverviewKind, sectionID: UUID?, title: String) {
        self.kind = kind
        self.sectionID = sectionID
        self.title = title
    }
}

/// Which brain writes the script.
enum StudioEngine: String, CaseIterable, Identifiable {
    case claude
    case deviceBrain
    case onDevice
    case offline

    var id: String { rawValue }

    var title: String {
        switch self {
        case .claude: return "Claude"
        case .deviceBrain: return "Qwen3.5"
        case .onDevice: return Loc.t("Cihazda")
        case .offline: return Loc.t("Çevrimdışı")
        }
    }

    var detail: String {
        switch self {
        case .claude: return Loc.t("En iyi kalite. PDF'lerin şekilleriyle birlikte okunur; API kredisi harcar.")
        case .deviceBrain: return Loc.t("iPad'e indirilen Qwen3.5 ile ücretsiz ve internetsiz. Apple'ın modelinden daha güçlü.")
        case .onDevice: return Loc.t("Apple Intelligence ile ücretsiz ve internetsiz. Kısa kaynaklarda iyi.")
        case .offline: return Loc.t("Her cihazda çalışır; kaynaklardan önemli cümleleri seçer. Basit.")
        }
    }

    var symbol: String {
        switch self {
        case .claude: return "cloud"
        case .deviceBrain: return "brain"
        case .onDevice: return "cpu"
        case .offline: return "bolt.horizontal.circle"
        }
    }

    /// The downloaded model (Claude only when chosen). Until it is on the iPad, the writers fall back
    /// to Apple's model and then the keyless writer by themselves.
    static func preferred(settings: AppSettings) -> StudioEngine {
        settings.hasAPIKey && settings.engine == .claude ? .claude : .deviceBrain
    }

    /// The writers the app lists: the downloaded model, and Claude once its key is saved.
    static func visible(settings: AppSettings) -> [StudioEngine] {
        [.deviceBrain] + (settings.hasAPIKey ? [.claude] : [])
    }

    func isAvailable(settings: AppSettings) -> Bool {
        switch self {
        case .claude: return settings.hasAPIKey
        case .deviceBrain: return DeviceBrain.shared.isReady
        case .onDevice: return OnDeviceAI.isAvailable
        case .offline: return true
        }
    }
}
