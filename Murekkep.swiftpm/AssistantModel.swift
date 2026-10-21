import Combine
import Foundation
import UIKit

struct ChatMessage: Identifiable, Equatable {
    enum Role {
        case user
        case assistant
    }

    let id = UUID()
    var role: Role
    var text: String
    /// Small caption under the bubble (pages sent, handwriting...).
    var note: String?
    var isError = false
    /// Handwriting snapshot that went with this question (only the latest one is re-sent).
    var imageJPEG: Data?
    /// Web pages the answer used.
    var sources: [WebSource] = []
    /// Which engine produced the answer.
    var engine: String?
}

enum AIScope: String, CaseIterable, Identifiable {
    case page
    case nearby
    case document
    /// Every note and PDF in the note's library section (a whole course).
    case section

    var id: String { rawValue }

    var title: String {
        switch self {
        case .page: return Loc.t("Bu sayfa")
        case .nearby: return Loc.t("Yakın sayfalar")
        case .document: return Loc.t("Tüm belge")
        case .section: return Loc.t("Tüm bölüm")
        }
    }
}

enum QuickAction: String, CaseIterable, Identifiable {
    case solve
    case check
    case summarize
    case explain
    case quiz
    case formulas

    var id: String { rawValue }

    var title: String {
        switch self {
        case .solve: return Loc.t("Sayfadaki soruları çöz")
        case .summarize: return Loc.t("Özetle")
        case .explain: return Loc.t("Açıkla")
        case .quiz: return "Quiz"
        case .check: return Loc.t("Çözümümü kontrol et")
        case .formulas: return Loc.t("Formüller")
        }
    }

    var symbol: String {
        switch self {
        case .solve: return "wand.and.stars"
        case .summarize: return "text.alignleft"
        case .explain: return "lightbulb"
        case .quiz: return "questionmark.circle"
        case .check: return "checkmark.seal"
        case .formulas: return "function"
        }
    }

    /// Works on the page in front of the user, whatever the scope picker says.
    var currentPageOnly: Bool { self == .solve || self == .check }

    var prompt: String {
        switch self {
        case .solve:
            return Loc.t("Bu sayfadaki bütün soruları ve işlemleri sırayla çöz. Her biri için sonucu kalın yaz, kısa çözüm adımlarını göster. Yanlış yazılmış bir işlem varsa doğrusunu söyle.")
        case .summarize:
            return Loc.t("Gönderdiğim sayfaları kısaca özetle. Önemli kavramları madde madde yaz.")
        case .explain:
            return Loc.t("Şu an baktığım sayfadaki konuyu bir öğrenciye anlatır gibi adım adım açıkla. Gerekirse kısa bir örnek ver.")
        case .quiz:
            return Loc.t("Bu içerikten 5 soruluk kısa bir quiz hazırla. Cevapları en sonda ayrı bir başlık altında ver.")
        case .check:
            return Loc.t("Sayfadaki el yazısı çözümümü kontrol et. Hata varsa hangi adımda olduğunu söyle ve doğrusunu göster.")
        case .formulas:
            return Loc.t("Bu sayfalardaki önemli formülleri listele. Her birinde sembollerin anlamını ve birimlerini yaz.")
        }
    }
}

/// Chat about the open note. Answers come from the on-device model, a local server, the offline
/// engine or (only when chosen) Claude. All UI state changes happen on the main thread.
final class AssistantModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var draft = ""
    @Published var scope: AIScope = .nearby
    @Published var includeHandwriting = false
    @Published private(set) var isBusy = false
    @Published private(set) var status: String?
    @Published private(set) var lastEngine: String?

    private weak var editor: EditorModel?
    private let settings: AppSettings
    private var task: Task<Void, Never>?
    private var ocrCache: [Int: (version: Int, text: String)] = [:]
    private var sectionCache: [UUID: (modified: Date, pages: [SectionReader.Page])] = [:]

    init(editor: EditorModel, settings: AppSettings) {
        self.editor = editor
        self.settings = settings
    }

    /// What the header shows (before and after answers).
    var engineBadge: (title: String, symbol: String) {
        if let lastEngine, isBusy || !messages.isEmpty {
            return (lastEngine, settings.engine == .auto ? AIEngine.auto.symbol : settings.engine.symbol)
        }
        switch settings.engine {
        case .auto:
            if OnDeviceAI.isAvailable { return (ResolvedEngine.onDevice.label, AIEngine.onDevice.symbol) }
            if LocalServerClient.normalizedBase(settings.serverURL) != nil { return (Loc.t("Otomatik · yerel sunucu"), AIEngine.localServer.symbol) }
            return (Loc.t("Otomatik · çevrimdışı"), AIEngine.offline.symbol)
        case .onDevice:
            return (OnDeviceAI.isAvailable ? ResolvedEngine.onDevice.label : Loc.t("Apple Intelligence yok"), AIEngine.onDevice.symbol)
        case .localServer:
            let model = settings.serverModel.isEmpty ? "" : " · \(settings.serverModel)"
            return (Loc.t("Yerel sunucu") + model, AIEngine.localServer.symbol)
        case .offline:
            return (ResolvedEngine.offline.label, AIEngine.offline.symbol)
        case .claude:
            return ("Claude · \(settings.model.title)", AIEngine.claude.symbol)
        }
    }

    func run(_ action: QuickAction) {
        send(action.prompt, action: action, forceHandwriting: action.currentPageOnly)
    }

    func send(_ text: String? = nil, action: QuickAction? = nil, forceHandwriting: Bool = false) {
        guard !isBusy else { return }
        let question = (text ?? draft).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, let editor else { return }
        let engine = settings.engine
        var apiKey: String?
        if engine == .claude {
            guard let key = settings.apiKey else {
                messages.append(ChatMessage(role: .assistant,
                                            text: Loc.t("Claude seçili ama API anahtarı yok. Ayarlar'dan anahtar ekle ya da anahtarsız bir motor seç (Otomatik, Cihazda, Yerel sunucu, Çevrimdışı)."),
                                            isError: true))
                return
            }
            apiKey = key
        }
        if text == nil { draft = "" }

        let withInk = (includeHandwriting || forceHandwriting) && editor.isPDF
        var image: Data?
        if withInk && engine == .claude {
            image = editor.pageImageJPEG(editor.currentPage)
        }
        var note = action?.currentPageOnly == true ? Loc.t("s. {0}", "\(editor.currentPage + 1)") : scopeLabel(editor: editor)
        if withInk && editor.isPDF { note += Loc.t(" · el yazısı dahil") }
        if engine != .claude && settings.webSearch && (action == nil || action == .explain) {
            note += Loc.t(" · internet")
        }
        messages.append(ChatMessage(role: .user, text: question, note: note, imageJPEG: image))
        messages.append(ChatMessage(role: .assistant, text: ""))
        isBusy = true
        status = Loc.t("Hazırlanıyor…")

        task = Task { @MainActor [weak self] in
            guard let self else { return }
            if let apiKey {
                await self.perform(apiKey: apiKey, allowFileRetry: true)
            } else {
                await self.performLocal(question: question, action: action, withInk: withInk)
            }
        }
    }

    func cancel() {
        task?.cancel()
    }

    func reset() {
        task?.cancel()
        messages.removeAll()
        status = nil
        lastEngine = nil
    }

    private func scopeLabel(editor: EditorModel) -> String {
        if scope == .section, let section = self.section(of: editor) {
            return Loc.t("bölüm: {0}", "\(section.name)")
        }
        let range = range(for: scope, editor: editor)
        let pages = range.count == 1 ? Loc.t("s. {0}", "\(range.lowerBound + 1)") : Loc.t("s. {0}–{1}", "\(range.lowerBound + 1)", "\(range.upperBound + 1)")
        return editor.isPDF ? pages : pages + Loc.t(" (el yazısı)")
    }

    private func range(for scope: AIScope, editor: EditorModel) -> ClosedRange<Int> {
        switch scope {
        case .page: return editor.pageRange(around: editor.currentPage, radius: 0)
        case .nearby: return editor.pageRange(around: editor.currentPage, radius: 2)
        case .document, .section: return 0...max(0, editor.pageCount - 1)
        }
    }

    // MARK: - Section-wide questions

    private func section(of editor: EditorModel) -> NoteSection? {
        guard let id = editor.store.note(editor.meta.id)?.sectionID else { return nil }
        return editor.store.sections.first { $0.id == id }
    }

    /// Text of the other notes and PDFs in the same section, cached until a note changes.
    @MainActor
    private func gatherSectionPages(editor: EditorModel, limit: Int) async -> [PageText] {
        guard let section = self.section(of: editor) else { return [] }
        let others = editor.store.notes.filter { $0.sectionID == section.id && $0.id != editor.meta.id }
        var out: [PageText] = []
        var index = PageText.otherNotesBase
        for note in others {
            if Task.isCancelled || out.count >= limit { break }
            let pages: [SectionReader.Page]
            if let cached = sectionCache[note.id], cached.modified == note.modified {
                pages = cached.pages
            } else {
                status = Loc.t("{0} okunuyor…", "\(note.title)")
                let pdf = note.kind == .pdf ? editor.store.pdfURL(for: note.id) : nil
                let ink = editor.store.inkURL(for: note.id)
                pages = await SectionReader.pages(pdf: pdf, ink: ink, maxPages: 6, noteID: note.id)
                sectionCache[note.id] = (note.modified, pages)
            }
            for p in pages where out.count < limit {
                out.append(PageText(page: index, text: p.text, fromOCR: p.fromOCR, source: note.title, sourcePage: p.page))
                index += 1
            }
        }
        return out
    }

    // MARK: - Keyless engines

    @MainActor
    private func performLocal(question: String, action: QuickAction?, withInk: Bool) async {
        defer {
            isBusy = false
            status = nil
        }
        guard let editor else { return }
        do {
            let (resolved, warning) = await resolveEngine()
            try Task.checkCancellation()
            setEngine(resolved.label + (warning == nil ? "" : Loc.t(" (yedek)")))
            let pageLimit: Int
            switch resolved {
            case .onDevice: pageLimit = 5
            case .localServer: pageLimit = 12
            case .offline, .claude: pageLimit = 30
            }
            let pageRange = action?.currentPageOnly == true
                ? editor.pageRange(around: editor.currentPage, radius: 0)
                : range(for: scope, editor: editor)
            var pages = await gatherPages(range: pageRange, withInk: withInk, editor: editor, limit: pageLimit)
            if scope == .section && action?.currentPageOnly != true {
                pages += await gatherSectionPages(editor: editor, limit: max(pageLimit, 24))
            }
            try Task.checkCancellation()
            let wantsWeb = settings.webSearch && (action == nil || action == .explain || action == .solve)
            if let warning {
                appendToAnswer("_\(warning)_\n\n")
            }
            // Answer in the language of the question (or, for the ready-made actions, of the notes).
            let language = Self.answerLanguage(question: question, action: action, pages: pages)
            // Exact results of the math engine, so a language model never gets the arithmetic wrong.
            let facts = AnswerLanguage.$bound.withValue(language) { OfflineBrain.mathFacts(pages, current: editor.currentPage) }
            // A page of questions: the small models are far more accurate one question at a time. A
            // textbook page goes exercise by exercise, each item with its exercise's instruction.
            if Self.wantsSolving(question: question, action: action) {
                let here = pages.filter { $0.page == editor.currentPage }
                let source = here.isEmpty ? pages : here
                let text = source.map(\.text).joined(separator: "\n")
                let questions = QuestionSplitter.split(text)
                let exercises = ExerciseSplitter.split(text)
                let multipleChoice = questions.filter { $0.options.count >= 2 }.count >= 2
                let textbook = !multipleChoice && exercises.contains { $0.kind != .skip }
                if textbook || questions.count >= 2 {
                    switch resolved {
                    case .onDevice:
                        if textbook {
                            try await solveExercisesOnDevice(exercises, language: language)
                        } else {
                            try await solveOnDevice(questions, language: language)
                        }
                        return
                    case let .localServer(base, model):
                        if textbook {
                            // A vision model checks the gaps and their numbers on the scan itself.
                            let scanned = source.contains { $0.fromOCR }
                            let picture = scanned && settings.serverSendsImages ? pagePictureJPEG(editor: editor) : nil
                            try await solveExercisesWithServer(exercises, base: base, model: model, language: language,
                                                               picture: picture)
                        } else {
                            try await solveWithServer(questions, base: base, model: model, language: language)
                        }
                        return
                    case .offline, .claude:
                        appendToAnswer("_" + Loc.t("Çevrimdışı çekirdek soruları gerçekten çözemez, yalnızca sayfadaki ipuçlarını gösterir. Çözüm için Apple Intelligence (iPadOS 26) ya da bilgisayarındaki yerel sunucu (Ollama, LM Studio) gerekir.") + "_\n\n")
                    }
                }
            }
            switch resolved {
            case .onDevice:
                try await answerOnDevice(question: question, pages: pages, facts: facts, wantsWeb: wantsWeb, editor: editor,
                                         language: language)
            case let .localServer(base, model):
                try await answerWithServer(base: base, model: model, question: question, action: action,
                                           pages: pages, facts: facts, wantsWeb: wantsWeb, withInk: withInk, editor: editor,
                                           language: language)
            case .offline, .claude:
                try await answerOffline(question: question, action: action, pages: pages, wantsWeb: wantsWeb, editor: editor,
                                        language: language)
            }
            if let last = messages.last, last.role == .assistant,
               last.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                setAnswer(Loc.t("(Boş yanıt geldi. Tekrar dene.)"), isError: true)
            }
        } catch is CancellationError {
            finishCancelled()
        } catch let error as URLError where error.code == .cancelled {
            finishCancelled()
        } catch {
            let text = OnDeviceAI.friendly(error) ?? LocalServerClient.friendly(error)
            if let last = messages.last, last.role == .assistant, !last.text.isEmpty {
                appendToAnswer("\n\n⚠️ \(text)")
            } else {
                setAnswer(text, isError: true)
            }
        }
    }

    /// Picks the engine for this answer; the warning explains a fallback.
    @MainActor
    private func resolveEngine() async -> (ResolvedEngine, String?) {
        let base = LocalServerClient.normalizedBase(settings.serverURL)
        switch settings.engine {
        case .onDevice:
            if let reason = OnDeviceAI.unavailableReason {
                return (.offline, Loc.t("Apple Intelligence kullanılamadı: {0} Şimdilik çevrimdışı çekirdekle yanıtlıyorum.", "\(reason)"))
            }
            return (.onDevice, nil)
        case .localServer:
            guard let base else {
                return (.offline, Loc.t("Yerel sunucu adresi girilmemiş (Ayarlar > Yerel sunucu). Şimdilik çevrimdışı çekirdekle yanıtlıyorum."))
            }
            status = Loc.t("Sunucuya bağlanılıyor…")
            return (.localServer(base: base, model: await serverModel(base: base)), nil)
        case .offline, .claude:
            return (.offline, nil)
        case .auto:
            if OnDeviceAI.isAvailable { return (.onDevice, nil) }
            if let base {
                status = Loc.t("Yerel sunucu aranıyor…")
                if await LocalServerClient.isReachable(base) {
                    return (.localServer(base: base, model: await serverModel(base: base)), nil)
                }
            }
            return (.offline, nil)
        }
    }

    @MainActor
    private func serverModel(base: URL) async -> String {
        let configured = settings.serverModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !configured.isEmpty { return configured }
        if let models = try? await LocalServerClient.listModels(base: base), let first = models.first {
            settings.serverModel = first
            return first
        }
        return ""
    }

    /// Text of the pages in scope: PDF text where it exists, otherwise on-device OCR of the page with its ink.
    @MainActor
    private func gatherPages(range: ClosedRange<Int>, withInk: Bool, editor: EditorModel, limit: Int) async -> [PageText] {
        var out: [PageText] = []
        let current = editor.currentPage
        // The current page and its neighbours first, so the limit keeps the most relevant ones.
        let ordered = Array(range).sorted { abs($0 - current) < abs($1 - current) }.prefix(limit).sorted()
        for (n, i) in ordered.enumerated() {
            if Task.isCancelled { break }
            let label = ordered.count > 1 ? Loc.t("Sayfa {0} okunuyor ({1}/{2})…", "\(i + 1)", "\(n + 1)", "\(ordered.count)") : Loc.t("Sayfa okunuyor…")
            guard editor.pages.indices.contains(i) else { continue }
            if editor.isPDF {
                let text = editor.plainText(page: i)
                if text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 25 {
                    out.append(PageText(page: i, text: text, fromOCR: false))
                } else {
                    let ocr = await recognizedScan(page: i, editor: editor, label: label)
                    if !ocr.isEmpty { out.append(PageText(page: i, text: ocr, fromOCR: true)) }
                }
                if withInk && i == current && !editor.pages[i].strokes.isEmpty {
                    let ocr = await recognizedInk(page: i, editor: editor, label: Loc.t("El yazısı okunuyor…"))
                    if !ocr.isEmpty { out.append(PageText(page: i, text: ocr, fromOCR: true)) }
                }
            } else {
                guard !editor.pages[i].strokes.isEmpty else { continue }
                let ocr = await recognizedInk(page: i, editor: editor, label: label)
                if !ocr.isEmpty { out.append(PageText(page: i, text: ocr, fromOCR: true)) }
            }
        }
        return out
    }

    /// Handwriting of a page, read from the plain ink image (same result for every brush). When the
    /// first pass finds little, a second pass with thicker lines catches faint or thin writing.
    @MainActor
    private func recognizedInk(page i: Int, editor: EditorModel, label: String) async -> String {
        guard editor.pages.indices.contains(i) else { return "" }
        let version = editor.pages[i].version
        if let cached = ocrCache[i], cached.version == version { return cached.text }
        status = label
        let strokes = editor.pages[i].strokes
        var text = ""
        if let raster = await Task.detached(priority: .userInitiated, operation: { InkRaster.render(strokes) }).value {
            text = Spelling.polish(await PageOCR.lines(in: raster)).map(\.text).joined(separator: "\n")
        }
        let inkCount = strokes.filter { $0.brush != .highlighter }.count
        if text.count < max(2, inkCount / 6),
           let thick = await Task.detached(priority: .userInitiated, operation: { InkRaster.render(strokes, lineScale: 1.7) }).value {
            let second = Spelling.polish(await PageOCR.lines(in: thick)).map(\.text).joined(separator: "\n")
            if second.count > text.count { text = second }
        }
        ocrCache[i] = (version: version, text: text)
        return text
    }

    /// Scanned PDF pages without a text layer: the whole page is read.
    @MainActor
    private func recognizedScan(page i: Int, editor: EditorModel, label: String) async -> String {
        guard editor.pages.indices.contains(i) else { return "" }
        let key = -1 - i
        let version = editor.pages[i].version
        if let cached = ocrCache[key], cached.version == version { return cached.text }
        // Without ink the picture is the PDF page itself: its reading (by the Studio or an earlier
        // question) is on disk and shared.
        let noteID = editor.meta.id
        let inkless = editor.pages[i].strokes.isEmpty && editor.pages[i].stickers.isEmpty
        if inkless, let stored = PageTextCache.load(note: noteID, page: i), stored.fromOCR {
            ocrCache[key] = (version: version, text: stored.text)
            return stored.text
        }
        status = label
        guard let image = editor.pageImage(i, longEdge: 2400, plainInk: true)?.cgImage else { return "" }
        let text = await PageOCR.recognize(image)
        ocrCache[key] = (version: version, text: text)
        if inkless { PageTextCache.save(text, fromOCR: true, note: noteID, page: i) }
        return text
    }

    /// Picture of the current page for vision models: the plain ink for notebooks, the page for PDFs.
    @MainActor
    private func pagePictureJPEG(editor: EditorModel) -> Data? {
        let i = editor.currentPage
        if !editor.isPDF, editor.pages.indices.contains(i),
           let raster = InkRaster.render(editor.pages[i].strokes, lineScale: 1.2, maxPixels: 1800) {
            return UIImage(cgImage: raster.image).jpegData(compressionQuality: 0.85)
        }
        return editor.pageImageJPEG(i, longEdge: 1600)
    }

    @MainActor
    private func answerOnDevice(question: String, pages: [PageText], facts: String, wantsWeb: Bool,
                                editor: EditorModel, language: AnswerLanguage) async throws {
        let collector = SourceCollector()
        var budget = OnDeviceAI.contextBudget
        var useHistory = true
        for attempt in 0..<2 {
            let prompt = localPrompt(question: question, pages: pages, facts: facts, budget: budget, editor: editor,
                                     history: useHistory ? recentHistory(maxTurns: 2, maxChars: 280) : [], web: [])
            status = wantsWeb ? Loc.t("Cihazdaki model düşünüyor, gerekirse internete bakıyor…") : Loc.t("Cihazdaki model düşünüyor…")
            do {
                let answer = try await OnDeviceAI.respond(instructions: Self.instructions(web: wantsWeb, tool: true, language: language),
                                                          prompt: prompt, useWeb: wantsWeb, collector: collector)
                status = nil
                try await reveal(answer)
                setSources(collector.all)
                return
            } catch {
                if attempt == 0 && OnDeviceAI.isContextOverflow(error) {
                    budget = 900
                    useHistory = false
                    continue
                }
                throw error
            }
        }
    }

    /// "Solve the questions" (the button, or a short request like "bu soruları çöz").
    static func wantsSolving(question: String, action: QuickAction?) -> Bool {
        if action == .solve { return true }
        guard action == nil, AnswerLanguage.isPageCommand(question) else { return false }
        let q = question.lowercased()
        return ["çöz", "solve", "cevap", "yanıt", "answer"].contains { q.contains($0) }
    }

    @MainActor
    private func solveOnDevice(_ questions: [PageQuestion], language: AnswerLanguage) async throws {
        for (i, q) in questions.enumerated() {
            try Task.checkCancellation()
            status = Loc.t("Soru {0}/{1} çözülüyor…", "\(i + 1)", "\(questions.count)")
            do {
                let solved = try await OnDeviceAI.solve(q, language: language)
                appendToAnswer(QuestionSolving.line(q, answer: solved.answer, reasoning: solved.reasoning))
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                appendToAnswer("**\(q.number))** ⚠️ " + (OnDeviceAI.friendly(error) ?? error.localizedDescription) + "\n\n")
            }
        }
        status = nil
    }

    @MainActor
    private func solveWithServer(_ questions: [PageQuestion], base: URL, model: String, language: AnswerLanguage) async throws {
        guard !model.isEmpty else {
            throw LocalAIError(Loc.t("Sunucuda yüklü model bulunamadı. Bilgisayarda örneğin \"ollama pull llama3.2\" çalıştır, sonra Ayarlar'dan modeli seç."))
        }
        let system = QuestionSolving.instructions(language: language)
        for (i, q) in questions.enumerated() {
            try Task.checkCancellation()
            status = Loc.t("Soru {0}/{1} çözülüyor…", "\(i + 1)", "\(questions.count)")
            let chat: [[String: Any]] = [["role": "system", "content": system], ["role": "user", "content": q.promptText]]
            let request = try LocalServerClient.chatRequest(base: base, model: model, messages: chat, temperature: 0.2)
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard code == 200 else {
                throw await LocalServerClient.readError(bytes, status: code)
            }
            appendToAnswer("**\(q.number))** ")
            streamLoop: for try await line in bytes.lines {
                switch LocalServerClient.parse(line: line) {
                case let .delta(text):
                    appendToAnswer(text)
                case .done:
                    break streamLoop
                case let .error(message):
                    throw LocalAIError(message)
                case .ignored:
                    break
                }
            }
            appendToAnswer("\n\n")
        }
        status = nil
    }

    /// Said in the answer's language, like the answers around it.
    private static func skippedNote(_ language: AnswerLanguage) -> String {
        language == .english ? "Speaking or listening exercise, skipped." : "Konuşma/dinleme alıştırması, atlandı."
    }

    /// A textbook page on the iPad: every item (or every sentence of a running text) is one call with
    /// its exercise's instruction, and each exercise is shown when its items are done, with the answers
    /// written into the sentences.
    @MainActor
    private func solveExercisesOnDevice(_ exercises: [PageExercise], language: AnswerLanguage) async throws {
        let total = exercises.reduce(0) { $0 + ExerciseSplitter.units($1).count }
        let skipped = Self.skippedNote(language)
        var done = 0
        for e in exercises {
            try Task.checkCancellation()
            var fills: [Int: [String]] = [:]
            var notes: [Int: String] = [:]
            // A running text's answered gaps, written into the sentence before the next one.
            var known: [Int: String] = [:]
            var problem: String?
            for u in ExerciseSplitter.units(e) {
                try Task.checkCancellation()
                done += 1
                status = Loc.t("Soru {0}/{1} çözülüyor…", "\(done)", "\(total)")
                do {
                    if let item = e.items.first(where: { $0.number == u.number && !$0.options.isEmpty }) {
                        let q = PageQuestion(number: item.number, stem: e.instruction + "\n" + item.text,
                                             options: item.options, passage: e.passage)
                        let solved = try await OnDeviceAI.solve(q, language: language)
                        fills[u.number] = [solved.answer]
                        notes[u.number] = solved.reasoning
                        continue
                    }
                    let before = ExerciseSplitter.fillNumbered(u.before, known: known)
                    let answer = try await OnDeviceAI.answer(u, of: e, before: before, language: language)
                    fills[u.number, default: []] += answer.fills
                    for (gap, fill) in zip(u.gaps, answer.fills) {
                        known[gap.number] = fill
                    }
                    if u.gaps.isEmpty {
                        notes[u.number] = answer.note
                    }
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    fills[u.number, default: []] += Array(repeating: "?", count: max(u.gaps.count, 1))
                    problem = OnDeviceAI.friendly(error) ?? error.localizedDescription
                }
            }
            appendToAnswer(ExerciseSplitter.render(e, fills: fills, notes: notes, skipped: skipped))
            if let problem {
                appendToAnswer("⚠️ \(problem)\n\n")
            }
        }
        status = nil
    }

    /// A textbook page on the local server: a model that size answers a whole exercise at once.
    @MainActor
    private func solveExercisesWithServer(_ exercises: [PageExercise], base: URL, model: String, language: AnswerLanguage,
                                          picture: Data?) async throws {
        guard !model.isEmpty else {
            throw LocalAIError(Loc.t("Sunucuda yüklü model bulunamadı. Bilgisayarda örneğin \"ollama pull llama3.2\" çalıştır, sonra Ayarlar'dan modeli seç."))
        }
        let system = QuestionSolving.exerciseInstructions(language: language)
        let skipped = Self.skippedNote(language)
        for (index, e) in exercises.enumerated() {
            try Task.checkCancellation()
            guard e.kind != .skip else {
                appendToAnswer(ExerciseSplitter.render(e, fills: [:], skipped: skipped))
                continue
            }
            status = Loc.t("Soru {0}/{1} çözülüyor…", "\(index + 1)", "\(exercises.count)")
            let text = ExerciseSplitter.exercisePrompt(e)
            var user: Any = text
            if let picture {
                let textPart: [String: Any] = ["type": "text",
                                               "text": text + "\n(Ekte sayfanın görüntüsü var; boşlukları ve numaralarını oradan doğrula.)"]
                let imagePart: [String: Any] = ["type": "image_url",
                                                "image_url": ["url": "data:image/jpeg;base64," + picture.base64EncodedString()]]
                user = [textPart, imagePart]
            }
            let chat: [[String: Any]] = [["role": "system", "content": system], ["role": "user", "content": user]]
            let request = try LocalServerClient.chatRequest(base: base, model: model, messages: chat, temperature: 0.2)
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard code == 200 else {
                throw await LocalServerClient.readError(bytes, status: code)
            }
            appendToAnswer("**\(e.number)** \(e.instruction)\n")
            streamLoop: for try await line in bytes.lines {
                switch LocalServerClient.parse(line: line) {
                case let .delta(text):
                    appendToAnswer(text)
                case .done:
                    break streamLoop
                case let .error(message):
                    throw LocalAIError(message)
                case .ignored:
                    break
                }
            }
            appendToAnswer("\n\n")
        }
        status = nil
    }

    @MainActor
    private func answerWithServer(base: URL, model: String, question: String, action: QuickAction?, pages: [PageText],
                                  facts: String, wantsWeb: Bool, withInk: Bool, editor: EditorModel,
                                  language: AnswerLanguage) async throws {
        guard !model.isEmpty else {
            throw LocalAIError(Loc.t("Sunucuda yüklü model bulunamadı. Bilgisayarda örneğin \"ollama pull llama3.2\" çalıştır, sonra Ayarlar'dan modeli seç."))
        }
        var web: [WebSource] = []
        if wantsWeb {
            status = Loc.t("İnternette aranıyor…")
            web = await WebSearch.search(searchQuery(question: question, action: action, pages: pages, editor: editor), limit: 4)
        }
        try Task.checkCancellation()
        var chat: [[String: Any]] = [["role": "system", "content": Self.instructions(web: !web.isEmpty, tool: false, language: language)]]
        for h in recentHistory(maxTurns: 8, maxChars: 2_000) {
            chat.append(["role": h.role == .user ? "user" : "assistant", "content": h.text])
        }
        let prompt = localPrompt(question: question, pages: pages, facts: facts, budget: 12_000, editor: editor,
                                 history: [], web: web)
        if settings.serverSendsImages, withInk || !editor.isPDF,
           let jpeg = pagePictureJPEG(editor: editor) {
            let textPart: [String: Any] = ["type": "text", "text": prompt + "\n(Ekte şu anki sayfanın görüntüsü var.)"]
            let imagePart: [String: Any] = ["type": "image_url",
                                            "image_url": ["url": "data:image/jpeg;base64," + jpeg.base64EncodedString()]]
            let parts: [[String: Any]] = [textPart, imagePart]
            chat.append(["role": "user", "content": parts])
        } else {
            chat.append(["role": "user", "content": prompt])
        }
        let request = try LocalServerClient.chatRequest(base: base, model: model, messages: chat, temperature: 0.4)
        status = Loc.t("{0} yanıtlıyor…", "\(model)")
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else {
            throw await LocalServerClient.readError(bytes, status: code)
        }
        streamLoop: for try await line in bytes.lines {
            switch LocalServerClient.parse(line: line) {
            case let .delta(text):
                status = nil
                appendToAnswer(text)
            case .done:
                break streamLoop
            case let .error(message):
                throw LocalAIError(message)
            case .ignored:
                break
            }
        }
        setSources(web)
    }

    @MainActor
    private func answerOffline(question: String, action: QuickAction?, pages: [PageText], wantsWeb: Bool,
                               editor: EditorModel, language: AnswerLanguage) async throws {
        var web: [WebSource] = []
        var definitions: [String: WebSource] = [:]
        let current = editor.currentPage
        if wantsWeb {
            status = Loc.t("İnternette aranıyor…")
            if action == .explain {
                let here = pages.filter { $0.page == current }
                for term in OfflineBrain.keyTerms(here.isEmpty ? pages : here, count: 3) {
                    if let d = await WebSearch.definition(of: term) {
                        definitions[term] = d
                        web.append(d)
                    }
                }
            } else {
                web = await WebSearch.search(searchQuery(question: question, action: action, pages: pages, editor: editor), limit: 3)
            }
        }
        try Task.checkCancellation()
        status = Loc.t("Yanıt hazırlanıyor…")
        let found = web
        let defs = definitions
        let answer = await Task.detached(priority: .userInitiated) {
            AnswerLanguage.$bound.withValue(language) {
                OfflineBrain.answer(question: question, action: action, pages: pages, currentPage: current,
                                    web: found, definitions: defs)
            }
        }.value
        status = nil
        try await reveal(answer)
        setSources(web)
    }

    private func searchQuery(question: String, action: QuickAction?, pages: [PageText], editor: EditorModel) -> String {
        if action != nil {
            let here = pages.filter { $0.page == editor.currentPage }
            return OfflineBrain.keyTerms(here.isEmpty ? pages : here, count: 3).joined(separator: " ")
        }
        let q = question.replacingOccurrences(of: "?", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        if q.count <= 90 { return q }
        return OfflineBrain.keyTerms(of: q, count: 6).joined(separator: " ")
    }

    /// See `AnswerLanguage.forAnswer`.
    static func answerLanguage(question: String, action: QuickAction?, pages: [PageText]) -> AnswerLanguage {
        let notes = String(pages.prefix(4).map(\.text).joined(separator: " ").prefix(1_500))
        return AnswerLanguage.forAnswer(question: question, isAction: action != nil, page: notes)
    }

    static func instructions(web: Bool, tool: Bool, language: AnswerLanguage) -> String {
        var s = """
        Sen "Mürekkep" adlı not uygulamasındaki çalışma asistanısın. Kullanıcı bir öğrenci.
        - Kullanıcının yazdığı dilde yanıt ver (Türkçe ya da İngilizce). Kısa, net ve öğretici ol.
        - Önce verilen not sayfalarına dayan ve bilgiyi aldığın sayfayı belirt (ör. s. 3). Sayfalarda olmayan genel bilgiyi böyle belirt.
        - El yazısından okunan metinde OCR hataları olabilir; anlamı bağlamdan çıkar.
        - Matematiği düz metin ve Unicode ile yaz: x², √(2gh), π, Δv, ≤. LaTeX kullanma.
        - Başlık için ## ve liste için - kullan. Tablo kullanma.
        - Emin olmadığın yerde bunu açıkça söyle.
        - Sayfada soru ya da işlem varsa doğrudan çöz; "göremiyorum" deme, okunan metinle en iyi yorumu yap.
        - HESAP_MOTORU bölümündeki sonuçlar kesindir; sayıları ve doğru/yanlış kararlarını oradan al.
        """
        if web && tool {
            s += "\n- Sayfalarda olmayan bir bilgi gerekiyorsa webSearch aracını kullan ve yanıtın sonunda kaynak başlığını yaz."
        } else if web {
            s += "\n- İNTERNET SONUÇLARI verildiyse onları da kullan ve [1], [2] gibi numarayla kaynağını göster."
        }
        s += "\n- " + language.directive
        return s
    }

    private func localPrompt(question: String, pages: [PageText], facts: String, budget: Int, editor: EditorModel,
                             history: [(role: ChatMessage.Role, text: String)], web: [WebSource]) -> String {
        var s = "Belge: \"\(editor.title)\" (\(editor.pageCount) sayfa). Kullanıcı şu an \(editor.currentPage + 1). sayfada.\n"
        let context = contextText(pages, budget: budget, current: editor.currentPage)
        if context.isEmpty {
            s += "(Sayfa boş ya da yalnızca çizim var.)\n"
        } else {
            s += "<NOT_SAYFALARI>\n\(context)\n</NOT_SAYFALARI>\n"
        }
        if !facts.isEmpty {
            s += "<HESAP_MOTORU>\n\(String(facts.prefix(1_500)))\n</HESAP_MOTORU>\n"
        }
        if !web.isEmpty {
            s += "<INTERNET_SONUCLARI>\n"
            for (i, w) in web.enumerated() {
                s += "[\(i + 1)] \(w.title): \(w.snippet) (\(w.url.absoluteString))\n"
            }
            s += "</INTERNET_SONUCLARI>\n"
        }
        if !history.isEmpty {
            s += "Önceki konuşma:\n"
            for h in history {
                s += (h.role == .user ? "Kullanıcı: " : "Asistan: ") + h.text + "\n"
            }
        }
        s += "\nSoru: \(question)"
        return s
    }

    private func contextText(_ pages: [PageText], budget: Int, current: Int) -> String {
        var remaining = budget
        var parts: [(page: Int, text: String)] = []
        for p in pages.sorted(by: { abs($0.page - current) < abs($1.page - current) }) {
            guard remaining > 120 else { break }
            let clean = p.text
                .replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
                .replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { continue }
            let chunk = String(clean.prefix(remaining))
            remaining -= chunk.count
            let tag = p.fromOCR ? " (el yazısı / görüntüden okundu)" : ""
            let title = p.source.map { "\($0) · Sayfa \(p.sourcePage + 1)" } ?? "Sayfa \(p.page + 1)"
            parts.append((page: p.page, text: "[\(title)\(tag)]\n\(chunk)"))
        }
        return parts.sorted { $0.page < $1.page }.map { $0.text }.joined(separator: "\n\n")
    }

    /// Earlier turns (without the current question and its empty answer).
    private func recentHistory(maxTurns: Int, maxChars: Int) -> [(role: ChatMessage.Role, text: String)] {
        let past = messages.dropLast(2).filter { !$0.isError && !$0.text.isEmpty }
        return past.suffix(maxTurns).map { (role: $0.role, text: String($0.text.prefix(maxChars))) }
    }

    /// Shows a finished answer progressively so it reads like a live reply.
    @MainActor
    private func reveal(_ text: String) async throws {
        let chars = Array(text)
        guard !chars.isEmpty else { return }
        let step = max(4, chars.count / 80)
        var i = 0
        while i < chars.count {
            let j = min(chars.count, i + step)
            appendToAnswer(String(chars[i..<j]))
            i = j
            if i < chars.count {
                try await Task.sleep(nanoseconds: 14_000_000)
            }
        }
    }

    // MARK: - Claude (optional, needs a key)

    @MainActor
    private func perform(apiKey: String, allowFileRetry: Bool) async {
        defer {
            isBusy = false
            status = nil
        }
        setEngine("Claude · \(settings.model.title)")
        do {
            let (context, note) = try await prepareContext(apiKey: apiKey)
            // Same language rule as the keyless engines (see `AnswerLanguage.forAnswer`).
            let question = messages.last(where: { $0.role == .user })?.text ?? ""
            let pageText = editor.map { $0.plainText(page: $0.currentPage) } ?? ""
            let isAction = QuickAction.allCases.contains { $0.prompt == question }
            let language = AnswerLanguage.forAnswer(question: question, isAction: isAction, page: pageText)
            let request = ClaudeRequest(model: settings.model.rawValue,
                                        effort: settings.effort.rawValue,
                                        maxTokens: 16_000,
                                        system: ClaudeRequest.tutorSystemPrompt + "\n" + language.directive,
                                        context: context,
                                        contextNote: note,
                                        turns: historyTurns())
            status = Loc.t("Gönderiliyor…")
            let body = try await Task.detached(priority: .userInitiated) { try request.jsonData() }.value
            if body.count > 31_000_000 {
                throw ClaudeAPIError(status: 413, type: "request_too_large", message: nil)
            }
            try Task.checkCancellation()
            let urlRequest = ClaudeClient.messagesRequest(apiKey: apiKey, body: body)
            let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard statusCode == 200 else {
                throw await ClaudeClient.readError(bytes, status: statusCode)
            }
            status = Loc.t("Claude okuyor…")
            streamLoop: for try await line in bytes.lines {
                guard let event = ClaudeSSE.parse(line: line) else { continue }
                switch event {
                case .thinking:
                    status = Loc.t("Düşünüyor…")
                case let .textDelta(text):
                    status = nil
                    appendToAnswer(text)
                case let .stopReason(reason):
                    if reason == "max_tokens" {
                        appendToAnswer(Loc.t("\n\n(Yanıt uzunluk sınırına ulaştı.)"))
                    } else if reason == "refusal" {
                        appendToAnswer(Loc.t("\n\n(Claude bu isteğe yanıt vermedi.)"))
                    }
                case .messageStop:
                    break streamLoop
                case let .error(type, message):
                    throw ClaudeAPIError(status: 0, type: type, message: message)
                case .ignored:
                    break
                }
            }
            if let last = messages.last, last.role == .assistant, last.text.isEmpty {
                setAnswer(Loc.t("(Boş yanıt geldi. Tekrar dene.)"), isError: true)
            }
        } catch let error as ClaudeAPIError where allowFileRetry && error.isMissingFile && scope == .document {
            editor?.updateClaudeFile(id: nil)
            await perform(apiKey: apiKey, allowFileRetry: false)
        } catch is CancellationError {
            finishCancelled()
        } catch let error as URLError where error.code == .cancelled {
            finishCancelled()
        } catch {
            let text = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            if let last = messages.last, last.role == .assistant, !last.text.isEmpty {
                appendToAnswer("\n\n⚠️ \(text)")
            } else {
                setAnswer(text, isError: true)
            }
        }
    }

    @MainActor
    private func prepareContext(apiKey: String) async throws -> (ClaudeContext, String) {
        guard let editor else { return (.none, "") }
        let range = range(for: scope, editor: editor)
        let current = editor.currentPage + 1
        let label = range.count == 1 ? "\(range.lowerBound + 1). sayfa" : "\(range.lowerBound + 1)–\(range.upperBound + 1). sayfalar"
        var note = "Belge: \"\(editor.title)\" (\(editor.pageCount) sayfa). Gönderilen kısım: \(label). Kullanıcı şu an \(current). sayfada."

        // A whole course: the text of every note in the section.
        if scope == .section, let section = self.section(of: editor) {
            status = Loc.t("Bölüm hazırlanıyor…")
            var parts: [String] = []
            if editor.isPDF {
                parts.append("=== \(editor.title) ===\n" + editor.pageText(range))
            }
            let others = await gatherSectionPages(editor: editor, limit: 80)
            for p in others {
                parts.append("--- \(p.label)\(p.fromOCR ? " (el yazısı)" : "") ---\n\(p.text)")
            }
            let text = String(parts.joined(separator: "\n\n").prefix(400_000))
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                note = "Bölüm: \"\(section.name)\" (\(Set(others.compactMap(\.source)).count + 1) not). Kullanıcı şu an \"\(editor.title)\" notunun \(current). sayfasında."
                return (.text(text, title: section.name), note)
            }
        }

        if !editor.isPDF {
            status = Loc.t("Sayfalar hazırlanıyor…")
            var items: [(label: String, jpeg: Data)] = []
            for i in range.prefix(20) {
                if let jpeg = editor.pageImageJPEG(i, longEdge: 1800) {
                    items.append((label: "Sayfa \(i + 1):", jpeg: jpeg))
                }
            }
            note += " Sayfalar kullanıcının el yazısı notlarının görüntüsü."
            if range.count > 20 { note += " Yalnızca ilk 20 sayfa gönderildi." }
            return (.images(items), note)
        }

        if settings.textOnlyPDF {
            let text = editor.pageText(range)
            if text.replacingOccurrences(of: "--- Sayfa", with: "").trimmingCharacters(in: .whitespacesAndNewlines).count > 40 {
                note += " PDF yalnızca metin olarak gönderildi, şekiller görünmüyor."
                return (.text(text, title: editor.title), note)
            }
            note += " (PDF'te metin yok, sayfalar görsel olarak gönderildi.)"
        }

        if scope == .document {
            if let id = editor.meta.claudeFileID, let date = editor.meta.claudeFileUploaded,
               Date().timeIntervalSince(date) < 25 * 24 * 3600 {
                return (.pdfFile(id: id, title: editor.title), note)
            }
            guard let url = editor.pdfURL else { return (.none, note) }
            status = Loc.t("PDF Claude'a yükleniyor…")
            let data = try await Task.detached(priority: .userInitiated) { try Data(contentsOf: url) }.value
            let id = try await ClaudeClient.uploadPDF(data, filename: editor.title, apiKey: apiKey)
            editor.updateClaudeFile(id: id)
            return (.pdfFile(id: id, title: editor.title), note)
        }

        status = Loc.t("Sayfalar hazırlanıyor…")
        guard let data = editor.subPDFData(range) else {
            throw ClaudeAPIError(status: 0, type: "pdf", message: Loc.t("Sayfalar PDF'ten çıkarılamadı."))
        }
        if data.count > 22_000_000 {
            throw ClaudeAPIError(status: 413, type: "request_too_large", message: nil)
        }
        return (.pdfBase64(data, title: editor.title), note)
    }

    /// Conversation without the empty placeholder, error bubbles and old handwriting images.
    private func historyTurns() -> [ClaudeTurn] {
        var items = Array(messages.dropLast())
        if items.count > 24 { items = Array(items.suffix(24)) }
        let lastUserID = items.last(where: { $0.role == .user })?.id
        return items.compactMap { m in
            guard !m.isError else { return nil }
            return ClaudeTurn(role: m.role == .user ? .user : .assistant,
                              text: m.text,
                              imageJPEG: m.id == lastUserID ? m.imageJPEG : nil)
        }
    }

    // MARK: - Message helpers

    private func appendToAnswer(_ text: String) {
        guard let i = messages.indices.last, messages[i].role == .assistant else { return }
        messages[i].text += text
    }

    private func setAnswer(_ text: String, isError: Bool) {
        guard let i = messages.indices.last, messages[i].role == .assistant else { return }
        messages[i].text = text
        messages[i].isError = isError
    }

    private func setSources(_ sources: [WebSource]) {
        guard !sources.isEmpty, let i = messages.indices.last, messages[i].role == .assistant else { return }
        messages[i].sources = sources
    }

    private func setEngine(_ label: String) {
        lastEngine = label
        guard let i = messages.indices.last, messages[i].role == .assistant else { return }
        messages[i].engine = label
    }

    private func finishCancelled() {
        if let last = messages.last, last.role == .assistant {
            if last.text.isEmpty {
                messages.removeLast()
            } else {
                appendToAnswer(Loc.t("\n\n(Durduruldu.)"))
            }
        }
        isBusy = false
        status = nil
    }
}
