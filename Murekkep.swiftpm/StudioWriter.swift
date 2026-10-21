import Foundation
import NaturalLanguage
#if canImport(FoundationModels) && !MUREKKEP_PLAIN
import FoundationModels
#endif

// MARK: - Sources

/// The text of the chosen sources (PDF text layer, handwriting read on the device).
struct StudioMaterial {
    struct Item {
        var noteID: UUID
        var title: String
        var kind: NoteKind
        var pageCount: Int
        var pdfURL: URL?
        /// Text with page marks ("[s. 3]").
        var text: String
        var claudeFileID: String?
        var claudeFileUploaded: Date?
    }

    var items: [Item]
    /// The chapter the overview is about (one video per chapter of a long book).
    var chapter: BookChapter? = nil

    var allText: String { items.map(\.text).joined(separator: "\n\n") }

    var sample: String { String(allText.prefix(2000)) }

    /// The text of these pages (0-based) of every source, from the "[s. N]" marks; pages are kept
    /// apart by a blank line.
    func text(pages: ClosedRange<Int>) -> String {
        var out: [String] = []
        for item in items {
            var current = -1
            for line in item.text.components(separatedBy: "\n") {
                if line.hasPrefix("[s. "), let n = Int(line.dropFirst(4).prefix(while: { $0.isNumber })) {
                    current = n - 1
                    if !out.isEmpty && pages.contains(current) { out.append("") }
                    continue
                }
                if pages.contains(current) { out.append(line) }
            }
        }
        return out.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `chapter`: only its pages. Scanned pages are read with OCR (and kept on disk).
    static func gather(_ notes: [NoteMeta], library: LibraryStore, chapter: BookChapter? = nil,
                       progress: (@Sendable (Int, Int) -> Void)? = nil) async -> StudioMaterial {
        let range = chapter?.pages
        var items: [Item] = []
        for note in notes {
            let pdf: URL? = note.kind == .pdf ? library.pdfURL(for: note.id) : nil
            let pages = await SectionReader.pages(pdf: pdf, ink: library.inkURL(for: note.id), maxPages: 120,
                                                  noteID: note.id, range: range, progress: progress)
            let text = pages.map { page in
                "[s. \(page.page + 1)\(page.isHandwriting ? ", el yazısı" : "")]\n" + page.text
            }.joined(separator: "\n\n")
            items.append(Item(noteID: note.id, title: note.title, kind: note.kind, pageCount: note.pageCount, pdfURL: pdf,
                              text: text, claudeFileID: note.claudeFileID, claudeFileUploaded: note.claudeFileUploaded))
        }
        return StudioMaterial(items: items, chapter: chapter)
    }
}

enum StudioWriterError: LocalizedError {
    case noText
    case unreadableScript
    case needsKey
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .noText: return Loc.t("Seçilen sayfalarda okunabilir metin yok (boş ya da çok soluk sayfalar).")
        case .unreadableScript: return Loc.t("Senaryo okunamadı. Bir kez daha dene; olmazsa süreyi kısalt.")
        case .needsKey: return Loc.t("Claude için Ayarlar'dan API anahtarı ekle ya da başka bir motor seç.")
        case let .unavailable(reason): return reason
        }
    }
}

// MARK: - Writer

enum StudioWriter {
    typealias WriteProgress = @MainActor (Double, String?) -> Void

    @MainActor
    static func write(options: OverviewOptions, material: StudioMaterial, engine: StudioEngine,
                      library: LibraryStore, settings: AppSettings, progress: @escaping WriteProgress) async throws -> Overview {
        let language = options.language
        switch engine {
        case .claude:
            return try await claude(options: options, material: material, language: language,
                                    library: library, settings: settings, progress: progress)
        case .deviceBrain:
            if let overview = try await brain(options: options, material: material, language: language, progress: progress) {
                return overview
            }
            // The downloaded model could not write it: Apple's model, then the keyless writer.
            progress(0.05, Loc.t("İndirilen model yazamadı, Apple modeliyle yazılıyor…"))
            fallthrough
        case .onDevice:
            do {
                return try await onDevice(options: options, material: material, language: language, progress: progress)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // The small model can refuse or not speak the language: the simple writer still works.
                progress(0.9, Loc.t("Cihazdaki model olmadı, çevrimdışı yazılıyor…"))
                return try offline(options: options, material: material, chosen: language, progress: progress)
            }
        case .offline:
            return try offline(options: options, material: material, chosen: language, progress: progress)
        }
    }

    static func directive(_ language: OverviewLanguage) -> String {
        (language.isEnglish ? AnswerLanguage.english : AnswerLanguage.turkish).directive
    }

    /// The directive for a script: the source is translated, never quoted in its own language.
    static func scriptDirective(_ language: OverviewLanguage) -> String {
        directive(language) + " " + (language.isEnglish
            ? "Write every title, bullet and narration in English only, even when the source text is in another language: translate it."
            : "Kaynak metin İngilizce ya da başka bir dilde olsa bile her başlığı, maddeyi ve anlatımı yalnızca Türkçe yaz; kaynağı çevirerek anlat.")
    }

    /// Whether a piece of a script is in the overview's language (a piece too short to tell counts).
    static func speaks(_ language: OverviewLanguage, _ text: String) -> Bool {
        let wanted: AnswerLanguage = language.isEnglish ? .english : .turkish
        return AnswerLanguage.detect(text, fallback: wanted) == wanted
    }

    /// Put before a prompt whose first answer came back in the other language.
    static func languageReminder(_ language: OverviewLanguage) -> String {
        language.isEnglish
            ? "IMPORTANT: your previous answer was not in English. Write everything in English."
            : "ÖNEMLİ: önceki yanıtın Türkçe değildi. Her şeyi Türkçe yaz; İngilizce metni Türkçeye çevir."
    }

    /// The extractive writer can only repeat the source's own sentences, so it writes in the source's
    /// language: a frame in one language around sentences in another would be voiced half in each.
    static func offlineLanguage(_ material: StudioMaterial, chosen: OverviewLanguage) -> OverviewLanguage {
        let wanted: AnswerLanguage = chosen.isEnglish ? .english : .turkish
        return AnswerLanguage.detect(material.sample, fallback: wanted) == .english ? .english : .turkish
    }

    private static func newOverview(_ options: OverviewOptions, material: StudioMaterial, language: OverviewLanguage,
                                    title: String, engine: String) -> Overview {
        Overview(title: title, sectionID: nil, sourceIDs: material.items.map(\.noteID),
                 sourceTitles: material.items.map(\.title), options: options, language: language,
                 hosts: language.hostNames, engine: engine)
    }

    private static func fallbackTitle(_ material: StudioMaterial) -> String {
        if let chapter = material.chapter, !chapter.title.isEmpty { return chapter.title }
        return material.items.count == 1 ? material.items[0].title : material.items.map(\.title).prefix(2).joined(separator: " · ")
    }

    // MARK: Claude

    @MainActor
    private static func claude(options: OverviewOptions, material: StudioMaterial, language: OverviewLanguage,
                               library: LibraryStore, settings: AppSettings, progress: @escaping WriteProgress) async throws -> Overview {
        guard let key = settings.apiKey else { throw StudioWriterError.needsKey }
        var forceUpload = false
        for attempt in 0..<2 {
            let sources = try await claudeSources(material, library: library, apiKey: key, textOnly: settings.textOnlyPDF,
                                                  forceUpload: forceUpload, progress: progress)
            let prompt = options.kind == .video
                ? StudioPrompts.video(options, language: language, sources: material.items.map(\.title))
                : StudioPrompts.audio(options, language: language, sources: material.items.map(\.title))
            let request = ClaudeRequest(model: settings.model.rawValue, effort: settings.effort.rawValue, maxTokens: 32_000,
                                        system: StudioPrompts.system + "\n" + scriptDirective(language),
                                        context: .sources(sources),
                                        contextNote: "Kaynaklar: " + material.items.enumerated().map { "\($0.offset + 1). \($0.element.title)" }.joined(separator: "; "),
                                        turns: [ClaudeTurn(role: .user, text: prompt, imageJPEG: nil)])
            let words = options.length.minutes * language.wordsPerMinute
            let expected = Double(max(2000, words * 10))
            progress(0.3, Loc.t("Claude senaryoyu yazıyor…"))
            do {
                let reply = try await ClaudeClient.collect(request, apiKey: key) { chars in
                    progress(min(0.98, 0.3 + 0.68 * Double(chars) / expected), nil)
                }
                var overview = try StudioScriptParser.overview(from: reply, options: options, language: language,
                                                               material: material, engine: "Claude · \(settings.model.title)")
                if overview.title.isEmpty { overview.title = fallbackTitle(material) }
                return overview
            } catch let error as ClaudeAPIError where error.isMissingFile && attempt == 0 {
                // An upload expired: send the PDFs again.
                forceUpload = true
                continue
            }
        }
        throw StudioWriterError.unreadableScript
    }

    @MainActor
    private static func claudeSources(_ material: StudioMaterial, library: LibraryStore, apiKey: String, textOnly: Bool,
                                      forceUpload: Bool, progress: @escaping WriteProgress) async throws -> [ClaudeSource] {
        var out: [ClaudeSource] = []
        // Claude reads up to about 100 PDF pages with their pictures in one request; the rest go as text.
        var visualPages = 0
        for (i, item) in material.items.enumerated() {
            progress(0.25 * Double(i) / Double(max(material.items.count, 1)), Loc.t("Kaynaklar Claude'a gönderiliyor…"))
            if let url = item.pdfURL, !textOnly, visualPages + item.pageCount <= 100 {
                var id = item.claudeFileID
                let fresh = item.claudeFileUploaded.map { Date().timeIntervalSince($0) < 25 * 24 * 3600 } ?? false
                if id == nil || !fresh || forceUpload {
                    let data = try await Task.detached(priority: .userInitiated) { try Data(contentsOf: url) }.value
                    let uploaded = try await ClaudeClient.uploadPDF(data, filename: item.title, apiKey: apiKey)
                    library.setClaudeFile(item.noteID, id: uploaded)
                    id = uploaded
                }
                visualPages += item.pageCount
                out.append(ClaudeSource(title: item.title, fileID: id))
            } else {
                let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                out.append(ClaudeSource(title: item.title, fileID: nil, text: String(text.prefix(180_000))))
            }
        }
        if out.isEmpty { throw StudioWriterError.noText }
        return out
    }

    // MARK: The downloaded model

    /// Text of the sources for the downloaded model: excerpts spread over every source (about 14,000
    /// characters, a few seconds of reading on the iPad), each under its source number.
    private static func brainSources(_ material: StudioMaterial) -> String {
        let budget = 14_000
        let items = material.items.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !items.isEmpty else { return "" }
        let share = budget / items.count
        return material.items.enumerated().compactMap { i, item -> String? in
            let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            let body = text.count <= share
                ? text
                : TextChunks.pick(text, count: max(1, share / 1_600), size: 1_600).joined(separator: "\n…\n")
            return "Kaynak \(i + 1): \(item.title)\n\(body)"
        }.joined(separator: "\n\n")
    }

    /// The same script Claude writes (StudioPrompts), by the model downloaded to the iPad; nil when it
    /// is not there, fails, or answers in the other language.
    @MainActor
    private static func brain(options: OverviewOptions, material: StudioMaterial, language: OverviewLanguage,
                              progress: @escaping WriteProgress) async throws -> Overview? {
        guard let directory = DeviceBrain.shared.directory else { return nil }
        let sources = brainSources(material)
        guard !sources.isEmpty else { return nil }
        let titles = material.items.map(\.title)
        let task = options.kind == .video
            ? StudioPrompts.video(options, language: language, sources: titles)
                + "\n- Bu kaynakların yalnızca metni var, sayfa görüntüleri yok: \"figure\" düzenini kullanma."
            : StudioPrompts.audio(options, language: language, sources: titles)
        let words = options.length.minutes * language.wordsPerMinute
        let request = BrainRuntime.Request(system: StudioPrompts.system + "\n" + scriptDirective(language),
                                           prompt: "KAYNAKLAR:\n" + sources + "\n\n" + task,
                                           thinking: nil, maxAnswerTokens: min(7_000, words * 3 + 1_200), temperature: 0.6)
        let title = DeviceBrain.shared.model?.title ?? "Qwen3.5"
        progress(0.1, Loc.t("{0} senaryoyu yazıyor…", title))
        do {
            var reply = ""
            for try await raw in BrainRuntime.stream(request, directory: directory) {
                reply = ThinkingText.split(raw, thinking: false).answer
                progress(min(0.95, 0.1 + 0.85 * Double(reply.count) / Double(max(words * 9, 2_000))), nil)
            }
            var overview = try StudioScriptParser.overview(from: reply, options: options, language: language,
                                                           material: material, engine: Loc.t("Cihazda · {0}", title))
            guard speaks(language, overview.segmentTexts.joined(separator: " ")) else { return nil }
            if overview.title.isEmpty { overview.title = fallbackTitle(material) }
            return overview
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return nil
        }
    }

    // MARK: On the device

    @MainActor
    private static func onDevice(options: OverviewOptions, material: StudioMaterial, language: OverviewLanguage,
                                 progress: @escaping WriteProgress) async throws -> Overview {
        #if canImport(FoundationModels) && !MUREKKEP_PLAIN
        if #available(iOS 26.0, *) {
            if options.kind == .video {
                return try await onDeviceVideo(options: options, material: material, language: language, progress: progress)
            }
            let chunks = TextChunks.pick(material.allText, count: max(3, options.length.scenes.lowerBound - 2), size: 1600)
            guard !chunks.isEmpty else { throw StudioWriterError.noText }
            var overview = newOverview(options, material: material, language: language, title: fallbackTitle(material),
                                       engine: Loc.t("Cihazda · Apple Intelligence"))
            let instructions = "Sen bir ders anlatıcısısın. Yalnızca verilen metne dayan, uydurma. " + scriptDirective(language)
            for (i, chunk) in chunks.enumerated() {
                try Task.checkCancellation()
                progress(Double(i) / Double(chunks.count), Loc.t("Cihazdaki model yazıyor ({0}/{1})…", "\(i + 1)", "\(chunks.count)"))
                let prompt = "\(options.format.prompt(for: .audio)) \(options.level.prompt) \(focusLine(options))\nİki sunucu (\(language.hostNames[0]) = 0, \(language.hostNames[1]) = 1) aşağıdaki metni doğal bir sohbetle anlatsın. Seslendirilecek: markdown yok, sembolleri okunuşuyla yaz.\n\nMetin:\n\(chunk)"
                var draft = try await AppleStudioBridge.dialogue(instructions: instructions, prompt: prompt)
                if !speaks(language, draft.lines.map(\.text).joined(separator: " ")) {
                    draft = try await AppleStudioBridge.dialogue(instructions: instructions,
                                                                 prompt: languageReminder(language) + "\n" + prompt)
                }
                var first = true
                // A line still in the other language is left out rather than voiced in the wrong accent.
                for line in draft.lines where !line.text.trimmingCharacters(in: .whitespaces).isEmpty && speaks(language, line.text) {
                    let chapter = first ? TextChunks.heading(in: chunk) ?? (language.isEnglish ? "Part \(i + 1)" : "Bölüm \(i + 1)") : nil
                    overview.lines.append(DialogueLine(host: min(max(line.host, 0), 1), text: line.text, chapter: chapter))
                    first = false
                }
            }
            frame(&overview, language: language)
            guard !overview.segmentTexts.isEmpty else { throw StudioWriterError.unreadableScript }
            return overview
        }
        #endif
        throw StudioWriterError.unavailable(OnDeviceAI.unavailableReason ?? Loc.t("Cihazdaki model kullanılamıyor."))
    }

    #if canImport(FoundationModels) && !MUREKKEP_PLAIN
    /// A video like NotebookLM's: the model plans the hook, the section names and the closing question,
    /// then writes each section's scenes from that section's own pages.
    @available(iOS 26.0, *)
    @MainActor
    private static func onDeviceVideo(options: OverviewOptions, material: StudioMaterial, language: OverviewLanguage,
                                      progress: @escaping WriteProgress) async throws -> Overview {
        let plan = StudioPlan.parts(material)
        guard !plan.isEmpty else { throw StudioWriterError.noText }
        let topic = fallbackTitle(material)
        let instructions = "Sen ödüllü bir ders anlatıcısısın: merak uyandırır, somut örneklerle ve sıcak bir dille anlatırsın. Yalnızca verilen metne dayan, uydurma. "
            + scriptDirective(language)
        progress(0.03, Loc.t("Cihazdaki model videoyu planlıyor…"))
        let planPrompt = """
        \(options.level.prompt) \(focusLine(options))
        Konu: \(topic)
        Bölümler (bu sırayla): \(plan.map(\.title).joined(separator: " | "))
        Metinden örnek:
        \(String(material.allText.prefix(1800)))

        Bu konu için bir video özeti planla: kısa bir başlık, merak uyandıran bir kanca sorusu ve onu somut bir örnekle açan anlatım, her bölüm için kısa bir başlık (aynı sırayla) ve izleyiciyi düşündüren bir kapanış sorusu. Sorularda en önemli 1-3 kelimeyi ** ** içine al. Anlatım seslendirilecek: sembolleri okunuşuyla yaz.
        """
        var outline = try await AppleStudioBridge.plan(instructions: instructions, prompt: planPrompt)
        if !speaks(language, outline.hook + " " + outline.hookNarration + " " + outline.closing) {
            outline = try await AppleStudioBridge.plan(instructions: instructions, prompt: languageReminder(language) + "\n" + planPrompt)
        }
        if !speaks(language, outline.hook + " " + outline.hookNarration + " " + outline.closing) {
            // Still the other language: the plain opening and closing, so nothing is voiced half in each.
            let en = language.isEnglish
            outline.hook = en ? "What is **\(topic)**, and why does it matter?" : "**\(topic)** nedir, neden önemlidir?"
            outline.hookNarration = en ? "In this video we'll see it step by step." : "Bu videoda bunu adım adım göreceğiz."
            outline.closing = en ? "So where do you see **\(topic)** in everyday life?" : "Peki **\(topic)** konusunu günlük hayatta nerede görüyorsun?"
            outline.sectionTitles = []
        }
        let counts = StudioPlan.sceneCounts(options, parts: plan.count)
        let total = counts.reduce(0, +)
        var done = 0
        var sections: [OutlineSection] = []
        for (i, part) in plan.enumerated() {
            var scenes: [OverviewScene] = []
            for chunk in TextChunks.pick(part.text, count: counts[i], size: 1600) {
                try Task.checkCancellation()
                progress(0.08 + 0.9 * Double(done) / Double(max(total, 1)),
                         Loc.t("Cihazdaki model yazıyor ({0}/{1})…", "\(done + 1)", "\(total)"))
                let prompt = "\(options.format.prompt(for: .video)) \(options.level.prompt) \(focusLine(options))\nBölüm: \(part.title)\nAşağıdaki ders metninden bu bölüm için bir video slaytı hazırla. Bir tanım varsa definition, adım adım bir süreç varsa steps düzenini seç. Anlatım seslendirilecek: doğal konuşma dili, somut bir örnek, sembolleri okunuşuyla yaz, markdown kullanma.\n\nMetin:\n\(chunk)"
                var draft = try? await AppleStudioBridge.scene(instructions: instructions, prompt: prompt)
                if let d = draft, !speaks(language, d.title + " " + d.narration) {
                    draft = try? await AppleStudioBridge.scene(instructions: instructions,
                                                               prompt: languageReminder(language) + "\n" + prompt)
                }
                // A scene still in the other language is left out rather than voiced in the wrong accent.
                if let d = draft, speaks(language, d.narration) {
                    scenes.append(scene(from: d))
                }
                done += 1
            }
            var short = i < outline.sectionTitles.count ? outline.sectionTitles[i].trimmingCharacters(in: .whitespaces) : ""
            if !speaks(language, short) { short = "" }
            let title = short.isEmpty ? part.title : short
            sections.append(OutlineSection(title: title, subtitle: title == part.title ? part.subtitle : part.title, scenes: scenes))
        }
        guard sections.contains(where: { !$0.scenes.isEmpty }) else { throw StudioWriterError.unreadableScript }
        let name = outline.title.trimmingCharacters(in: .whitespaces)
        var overview = newOverview(options, material: material, language: language,
                                   title: material.chapter != nil || name.isEmpty ? topic : name,
                                   engine: Loc.t("Cihazda · Apple Intelligence"))
        overview.scenes = VideoOutline.assemble(title: overview.title, hook: outline.hook, hookNarration: outline.hookNarration,
                                                sections: sections.filter { !$0.scenes.isEmpty }, closing: outline.closing,
                                                language: language)
        return overview
    }

    @available(iOS 26.0, *)
    private static func scene(from draft: StudioSceneDraft) -> OverviewScene {
        let bullets = Array(draft.bullets.prefix(5))
        let term = draft.term.trimmingCharacters(in: .whitespaces)
        let definition = draft.definition.trimmingCharacters(in: .whitespaces)
        switch draft.layout {
        case "definition" where !term.isEmpty && !definition.isEmpty:
            return OverviewScene(layout: .definition, title: draft.title, narration: draft.narration, term: term, definition: definition)
        case "steps" where bullets.count >= 2:
            return OverviewScene(layout: .steps, title: draft.title, bullets: bullets, narration: draft.narration)
        default:
            return OverviewScene(layout: .bullets, title: draft.title, bullets: bullets, narration: draft.narration)
        }
    }
    #endif

    private static func focusLine(_ options: OverviewOptions) -> String {
        let f = options.focus.trimmingCharacters(in: .whitespacesAndNewlines)
        return f.isEmpty ? "" : "Odak: \(f)."
    }

    /// Opening and closing of a podcast written piece by piece.
    private static func frame(_ overview: inout Overview, language: OverviewLanguage) {
        let en = language.isEnglish
        let a = en ? "Today we're looking at \(overview.title). There's a lot in here, so let's get into it."
                   : "Bugün \(overview.title) üzerine konuşacağız. Konuşacak çok şey var, hemen başlayalım."
        overview.lines.insert(DialogueLine(host: 0, text: a, chapter: en ? "Intro" : "Giriş"), at: 0)
        let z = en ? "That's a good place to stop. Think about which part you'd explain to a friend first."
                   : "Burada toparlayalım. Bir arkadaşına anlatsan ilk hangi kısmı anlatırdın, bir düşün."
        overview.lines.append(DialogueLine(host: 1, text: z, chapter: en ? "Wrap-up" : "Kapanış"))
    }

    // MARK: Offline

    @MainActor
    private static func offline(options: OverviewOptions, material: StudioMaterial, chosen: OverviewLanguage,
                                progress: WriteProgress) throws -> Overview {
        let language = offlineLanguage(material, chosen: chosen)
        if language != chosen {
            progress(0.92, Loc.t("Çevrimdışı yazar çeviri yapamaz: özet kaynağın dilinde ({0}) hazırlanıyor.", language.title))
        }
        if options.kind == .video { return try offlineVideo(options: options, material: material, language: language) }
        let text = material.allText
        let chunks = TextChunks.pick(text, count: max(3, options.length.scenes.lowerBound - 2), size: 1400)
        guard !chunks.isEmpty else { throw StudioWriterError.noText }
        let weights = TextChunks.wordWeights(text)
        var overview = newOverview(options, material: material, language: language, title: fallbackTitle(material),
                                   engine: Loc.t("Çevrimdışı"))
        let en = language.isEnglish
        for (i, chunk) in chunks.enumerated() {
            let best = TextChunks.keySentences(chunk, weights: weights, count: 3)
            guard !best.isEmpty else { continue }
            let title = TextChunks.heading(in: chunk) ?? TextChunks.shorten(best[0], words: 6)
            overview.lines.append(DialogueLine(host: 0, text: en ? "Let's look at \(title)." : "\(title) konusuna bakalım.",
                                               chapter: title))
            for (k, sentence) in best.enumerated() {
                overview.lines.append(DialogueLine(host: (k + 1) % 2, text: sentence, chapter: nil))
            }
            if i > 40 { break }
        }
        frame(&overview, language: language)
        guard !overview.segmentTexts.isEmpty else { throw StudioWriterError.noText }
        return overview
    }

    /// The same shape as the on-device video, from the text's key sentences.
    private static func offlineVideo(options: OverviewOptions, material: StudioMaterial, language: OverviewLanguage) throws -> Overview {
        let plan = StudioPlan.parts(material)
        guard !plan.isEmpty else { throw StudioWriterError.noText }
        let weights = TextChunks.wordWeights(material.allText)
        let counts = StudioPlan.sceneCounts(options, parts: plan.count)
        var sections: [OutlineSection] = []
        for (i, part) in plan.enumerated() {
            var scenes: [OverviewScene] = []
            for chunk in TextChunks.pick(part.text, count: counts[i], size: 1400) {
                let best = TextChunks.keySentences(chunk, weights: weights, count: 3)
                guard !best.isEmpty else { continue }
                let title = TextChunks.heading(in: chunk) ?? TextChunks.shorten(best[0], words: 6)
                scenes.append(OverviewScene(layout: .bullets, title: title, bullets: best.map { TextChunks.shorten($0, words: 13) },
                                            narration: best.joined(separator: " ")))
            }
            if !scenes.isEmpty { sections.append(OutlineSection(title: part.title, subtitle: part.subtitle, scenes: scenes)) }
        }
        guard !sections.isEmpty else { throw StudioWriterError.noText }
        let topic = fallbackTitle(material)
        let en = language.isEnglish
        let opening = TextChunks.keySentences(TextChunks.pick(material.allText, count: 1, size: 2000).first ?? "", weights: weights, count: 1)
            .first ?? ""
        var overview = newOverview(options, material: material, language: language, title: topic, engine: Loc.t("Çevrimdışı"))
        overview.scenes = VideoOutline.assemble(
            title: topic,
            hook: en ? "What is **\(topic)**, and why does it matter?" : "**\(topic)** nedir, neden önemlidir?",
            hookNarration: opening + (en ? " In this video we'll see it step by step." : " Bu videoda bunu adım adım göreceğiz."),
            sections: sections,
            closing: en ? "So where do you see **\(topic)** in everyday life?" : "Peki **\(topic)** konusunu günlük hayatta nerede görüyorsun?",
            language: language)
        return overview
    }
}

/// How a video's material is divided into sections: a chapter's own sections when it has at least
/// two with text, otherwise even pieces of the text named by their headings.
enum StudioPlan {
    struct Part {
        var title: String
        var subtitle: String
        var text: String
    }

    static func parts(_ material: StudioMaterial) -> [Part] {
        if let chapter = material.chapter, chapter.sections.count >= 2 {
            var out: [Part] = []
            for (k, s) in chapter.sections.enumerated() {
                let end = k + 1 < chapter.sections.count ? max(s.page, chapter.sections[k + 1].page - 1) : max(s.page, chapter.endPage)
                let text = material.text(pages: s.page...end)
                if text.count > 200 { out.append(Part(title: s.title, subtitle: s.number, text: text)) }
            }
            if out.count >= 2 { return out }
        }
        let all = material.allText
        guard all.count > 200 else { return [] }
        let weights = TextChunks.wordWeights(all)
        let pieces = TextChunks.pick(all, count: 4, size: max(1500, all.count / 4))
        return pieces.map { piece in
            let title = TextChunks.heading(in: piece)
                ?? TextChunks.shorten(TextChunks.keySentences(piece, weights: weights, count: 1).first ?? "", words: 5)
            return Part(title: title, subtitle: "", text: piece)
        }.filter { !$0.title.isEmpty }
    }

    /// Content scenes per part: about the length's scene count minus the frame scenes, spread evenly,
    /// at least one per part.
    static func sceneCounts(_ options: OverviewOptions, parts: Int) -> [Int] {
        guard parts > 0 else { return [] }
        let total = max(parts, options.length.scenes.lowerBound - 4)
        return (0..<parts).map { i in total / parts + (i < total % parts ? 1 : 0) }
    }
}

#if canImport(FoundationModels) && !MUREKKEP_PLAIN
@available(iOS 26.0, *)
@Generable
struct StudioSceneDraft {
    @Guide(description: "Slayt başlığı, en fazla 7 kelime")
    var title: String
    @Guide(description: "Slayt düzeni: bullets (maddeler), steps (sıralı adımlar) ya da definition (bir terimin tanımı)",
           .anyOf(["bullets", "steps", "definition"]))
    var layout: String
    @Guide(description: "Slayttaki 3 kısa madde ya da adım, her biri en fazla 12 kelime")
    var bullets: [String]
    @Guide(description: "definition düzeninde tanımlanan terim; başka düzende boş bırak")
    var term: String
    @Guide(description: "definition düzeninde terimin 1-2 cümlelik tanımı; başka düzende boş bırak")
    var definition: String
    @Guide(description: "Bu slaytın sesli anlatımı: 4-6 cümle, somut bir örnekle, sıcak ve doğal konuşma dili")
    var narration: String
}

@available(iOS 26.0, *)
@Generable
struct VideoPlanDraft {
    @Guide(description: "Videonun kısa başlığı, en fazla 6 kelime")
    var title: String
    @Guide(description: "Merak uyandıran tek bir soru, en fazla 12 kelime; en önemli 1-3 kelime ** işaretleri arasında")
    var hook: String
    @Guide(description: "Soruyu somut bir örnekle açan 3-4 cümlelik sesli anlatım")
    var hookNarration: String
    @Guide(description: "Verilen her bölüm için en fazla 5 kelimelik kısa başlık, aynı sırayla")
    var sectionTitles: [String]
    @Guide(description: "İzleyiciyi düşündüren kapanış sorusu; en önemli 1-3 kelime ** işaretleri arasında")
    var closing: String
}

@available(iOS 26.0, *)
@Generable
struct StudioLineDraft {
    @Guide(description: "Konuşan sunucu: 0 ya da 1")
    var host: Int
    @Guide(description: "Sunucunun söylediği 1-3 cümle")
    var text: String
}

@available(iOS 26.0, *)
@Generable
struct StudioDialogueDraft {
    @Guide(description: "Sırayla konuşan iki sunucunun 4-8 satırı")
    var lines: [StudioLineDraft]
}

@available(iOS 26.0, *)
enum AppleStudioBridge {
    static func scene(instructions: String, prompt: String) async throws -> StudioSceneDraft {
        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(to: prompt, generating: StudioSceneDraft.self)
        return response.content
    }

    static func plan(instructions: String, prompt: String) async throws -> VideoPlanDraft {
        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(to: prompt, generating: VideoPlanDraft.self)
        return response.content
    }

    static func dialogue(instructions: String, prompt: String) async throws -> StudioDialogueDraft {
        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(to: prompt, generating: StudioDialogueDraft.self)
        return response.content
    }
}
#endif

// MARK: - Prompts

enum StudioPrompts {
    static let system = """
    Sen "Mürekkep" not uygulamasının stüdyosunda çalışan ödüllü bir eğitim içeriği yazarı ve ders anlatıcısısın. Öğrencinin kendi kaynaklarından (ders PDF'leri, el yazısı notlar) sürükleyici, doğru ve akılda kalıcı video ve sesli özetler yazarsın.
    - Bilgiyi kaynaklara dayandır, uydurma. Kaynakta olmayan genel bilgiyi kısa tut.
    - İyi bir hoca gibi anlat: merak uyandır, örnek ve benzetme kullan, önemli yerleri vurgula, sonunda toparla.
    - Yalnızca istenen JSON'u yaz; öncesinde ya da sonrasında hiçbir şey yazma.
    """

    private static func common(_ options: OverviewOptions, language: OverviewLanguage, sources: [String]) -> String {
        let words = options.length.minutes * language.wordsPerMinute
        let focus = options.focus.trimmingCharacters(in: .whitespacesAndNewlines)
        return """
        Ayarlar:
        - Biçim: \(options.format.prompt(for: options.kind))
        - Süre: yaklaşık \(options.length.minutes) dakika; toplam seslendirme yaklaşık \(words) kelime.
        - Seviye: \(options.level.prompt)
        - Odak: \(focus.isEmpty ? "kaynakların en önemli konuları" : focus)
        - Dil: \(language.isEnglish ? "İngilizce (English)" : "Türkçe")
        - Kaynaklar: \(sources.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "; "))

        Seslendirme kuralları (narration ve text alanları sesli okunacak):
        - Doğal, sıcak, akıcı konuşma dili; kısa ve orta uzunlukta cümleler.
        - Markdown, emoji, madde işareti, parantez içi kaynak etiketi kullanma.
        - Sembol ve formülleri okunuşuyla yaz ("x kare", "delta G", "yüzde kırk", "integral"); kısaltmaları ilk geçtiği yerde aç.
        """
    }

    static func video(_ options: OverviewOptions, language: OverviewLanguage, sources: [String]) -> String {
        let r = options.length.scenes
        return """
        GÖREV: Yukarıdaki kaynaklardan bir VİDEO ÖZETİ senaryosu yaz. Uygulama her sahneyi bir slayta ve seslendirmeye çevirecek.

        \(common(options, language: language, sources: sources))

        Yapı (sırayla):
        1. "title": selamlama ve konu (narration 20-35 kelime).
        2. "question": merak uyandıran tek bir kanca sorusu (title; en önemli 1-3 kelimeyi ** ** içine al); narration soruyu somut bir örnek ya da hikâyeyle açar (60-90 kelime).
        3. "agenda": yol haritası; bullets = bölüm başlıkları (3-6, her biri en fazla 5 kelime); narration "İşte yol haritamız. Birincisi, … Ve son olarak, …".
        4. Her bölüm için önce "section" sahnesi (number = 1'den başlayan bölüm no, title = bölüm başlığı, subtitle = 3-6 kelimelik alt başlık; narration tek kısa cümle: "Birinci bölümümüz: …"), sonra o bölümün 1-3 içerik sahnesi.
        5. "summary": 3-6 maddelik toparlama.
        6. "question": izleyiciyi düşündüren kapanış sorusu (** ile vurgulu) ve kanca sorusuna geri dönen kısa narration.

        Sahne kuralları:
        - Toplam yaklaşık \(r.lowerBound + 4)–\(r.upperBound + 6) sahne.
        - Her sahnenin narration'ı slaytı okumaz, slaytı tamamlar ve açıklar (sahne başına 40-120 kelime).
        - Slayt metinleri kısa: başlık en fazla 7 kelime, madde en fazla 12 kelime, en fazla 5 madde. Slaytlarda sembol ve formül kullanabilirsin (ΔG, x², →).
        - Düzenleri çeşitlendir; aynı düzeni art arda üçten fazla kullanma.
        - Kaynaklardaki önemli şekil, tablo, grafik ve çizimleri "figure" düzeniyle göster. Kaynak ve sayfa numarası doğru olmalı; emin değilsen figure kullanma.

        Düzenler (layout) ve alanları:
        - "title": title, subtitle
        - "bullets": title, bullets (3-5)
        - "figure": title, figure {"source": kaynak no (1'den), "page": sayfa no (1'den), "box": [x, y, genişlik, yükseklik] sayfanın 0-1 oranları, sol üst köşeden; şeklin yerini bilmiyorsan box yazma}, bullets (0-2 kısa not)
        - "definition": term, definition (1-2 cümle)
        - "compare": title, left {"title": "...", "items": [...]}, right {"title": "...", "items": [...]}
        - "steps": title, bullets (3-5 adım, sırayla)
        - "quote": title (kısa etiket), subtitle (vurgulanacak tek cümle)
        - "quiz": title, subtitle (soru), choices (4 şık), answer (doğru şıkkın 0'dan başlayan indeksi). narration'da soruyu sor, "Bir düşün…" de, sonra cevabı ve nedenini açıkla.
        - "summary": title, bullets (4-6)
        - "question": title (soru, ** ile vurgulu kelimeler)
        - "agenda": title, bullets (bölüm başlıkları)
        - "section": number, title, subtitle
        İsteğe bağlı "art": slayta uygun bir çizim adı: heart, lungs, kidney, spleen, liver, stomach, brain, atom, flask, bulb, star, check, warning, question; ya da bir SF Symbols adı "sf:" önekiyle (ör. "sf:waveform.path.ecg").

        ÇIKTI (yalnızca geçerli JSON):
        {"title": "videonun başlığı", "scenes": [{"layout": "title", "title": "...", "subtitle": "...", "narration": "...", "art": "..."}, ...]}
        """
    }

    static func audio(_ options: OverviewOptions, language: OverviewLanguage, sources: [String]) -> String {
        let a = language.hostNames[0]
        let b = language.hostNames[1]
        return """
        GÖREV: Yukarıdaki kaynaklardan iki sunuculu bir SESLİ ÖZET (podcast) metni yaz.

        \(common(options, language: language, sources: sources))

        Sunucular: \(a) (host 0) sohbeti yönlendirir ve konuyu iyi bilir; \(b) (host 1) zeki ve meraklı: soru sorar, örnek verir, gerektiğinde itiraz eder.
        Sohbet kuralları:
        - Gerçek bir sohbet gibi: kısa tepkiler ("Evet, kesinlikle.", "Dur bir saniye…", "Bu çok ilginç.") ama abartmadan. Bir satır en fazla 3-4 cümle; monolog yok.
        - Kendinizi ya da programı tanıtmayın; doğrudan merak uyandıran bir girişle başlayın.
        - Konuyu bölümlere ayırın; bir bölümün ilk satırına kısa bir "chapter" başlığı koyun.
        - Kapanışta kısa bir toparlama ve dinleyiciye bir düşünme sorusu.

        ÇIKTI (yalnızca geçerli JSON):
        {"title": "bölümün başlığı", "lines": [{"host": 0, "text": "...", "chapter": "Giriş"}, {"host": 1, "text": "..."}, ...]}
        """
    }

    /// For questions asked in the middle of an overview.
    static func question(_ question: String, overview: Overview, position: Int) -> String {
        let segments = overview.segmentTexts
        let lo = max(0, position - 2)
        let hi = min(segments.count, position + 2)
        let near = lo < hi ? segments[lo..<hi].joined(separator: "\n") : ""
        return """
        Kullanıcı "\(overview.title)" özetini dinlerken durdu ve bir soru sordu. Kısa (3-6 cümle), sohbet havasında ve seslendirmeye uygun cevap ver; markdown kullanma, sembolleri okunuşuyla yaz. Cevabın sonunda özetin kaldığı yere bağla.

        Özetin şu an çalan kısmı:
        \(near)

        Soru: \(question)
        """
    }
}

// MARK: - Parsing

enum StudioScriptParser {
    static func overview(from reply: String, options: OverviewOptions, language: OverviewLanguage,
                         material: StudioMaterial, engine: String) throws -> Overview {
        guard let obj = json(from: reply) else { throw StudioWriterError.unreadableScript }
        var overview = Overview(title: str(obj["title"]) ?? "", sectionID: nil, sourceIDs: material.items.map(\.noteID),
                                sourceTitles: material.items.map(\.title), options: options, language: language,
                                hosts: language.hostNames, engine: engine)
        if options.kind == .video {
            overview.scenes = scenes(obj["scenes"], sourceCount: material.items.count)
        } else {
            overview.lines = lines(obj["lines"], hosts: language.hostNames)
        }
        guard !overview.segmentTexts.isEmpty else { throw StudioWriterError.unreadableScript }
        return overview
    }

    static func json(from text: String) -> [String: Any]? {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end else { return nil }
        if let obj = parse(String(text[start...end])) { return obj }
        // A reply cut off at the length limit: close it after the last complete scene or line.
        let body = text[start...]
        var limit = body.endIndex
        for _ in 0..<60 {
            guard let close = body[..<limit].lastIndex(of: "}") else { break }
            if let obj = parse(String(body[...close]) + "]}") { return obj }
            limit = close
        }
        return nil
    }

    private static func parse(_ s: String) -> [String: Any]? {
        guard let data = s.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func str(_ v: Any?) -> String? {
        if let s = v as? String {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        if let n = v as? NSNumber { return n.stringValue }
        return nil
    }

    static func strs(_ v: Any?) -> [String] {
        (v as? [Any])?.compactMap { str($0) } ?? []
    }

    static func int(_ v: Any?) -> Int? {
        if let n = v as? NSNumber { return n.intValue }
        if let s = v as? String { return Int(s.trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    static func double(_ v: Any?) -> Double? {
        if let n = v as? NSNumber { return n.doubleValue }
        if let s = v as? String { return Double(s.trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    private static func column(_ v: Any?) -> SceneColumn? {
        guard let o = v as? [String: Any] else { return nil }
        let items = strs(o["items"])
        guard let title = str(o["title"]), !items.isEmpty else { return nil }
        return SceneColumn(title: title, items: Array(items.prefix(5)))
    }

    static func art(_ v: Any?) -> String? {
        guard var name = str(v) else { return nil }
        if name.hasPrefix("art:") { name = String(name.dropFirst(4)) }
        if name.hasPrefix("sf:") { return name }
        if StickerArt.library[name] != nil { return "art:" + name }
        if name.contains(".") || name.allSatisfy({ $0.isLetter || $0.isNumber }) { return "sf:" + name }
        return nil
    }

    static func scenes(_ v: Any?, sourceCount: Int) -> [OverviewScene] {
        guard let list = v as? [Any] else { return [] }
        var out: [OverviewScene] = []
        for item in list {
            guard let o = item as? [String: Any], let narration = str(o["narration"]) else { continue }
            var layout = SceneLayout(rawValue: (str(o["layout"]) ?? "").lowercased()) ?? .bullets
            let title = str(o["title"]) ?? ""
            var scene = OverviewScene(layout: layout, title: title, subtitle: str(o["subtitle"]),
                                      bullets: Array(strs(o["bullets"]).prefix(6)), narration: narration,
                                      term: str(o["term"]), definition: str(o["definition"]),
                                      left: column(o["left"]), right: column(o["right"]),
                                      choices: Array(strs(o["choices"]).prefix(4)), answer: int(o["answer"]),
                                      figure: nil, art: art(o["art"]))
            scene.number = int(o["number"])
            if let f = o["figure"] as? [String: Any], let source = int(f["source"]), let page = int(f["page"]),
               source >= 1, source <= sourceCount, page >= 1 {
                var box: [Double]?
                if let raw = f["box"] as? [Any] {
                    let values = raw.compactMap { double($0) }
                    if values.count == 4, values.allSatisfy({ $0 >= 0 && $0 <= 1.0001 }), values[2] > 0.05, values[3] > 0.05 {
                        box = values
                    }
                }
                scene.figure = FigureRef(source: source - 1, page: page - 1, box: box)
            }
            // A layout without what it needs falls back to a plain list.
            switch layout {
            case .figure where scene.figure == nil,
                 .compare where scene.left == nil || scene.right == nil,
                 .quiz where scene.choices.count < 2,
                 .definition where scene.term == nil || scene.definition == nil:
                layout = scene.bullets.isEmpty ? .title : .bullets
            case .quote where scene.subtitle == nil:
                layout = .title
            case .agenda where scene.bullets.isEmpty:
                layout = .title
            default:
                break
            }
            if layout == .quiz {
                if let a = scene.answer {
                    scene.answer = min(max(a, 0), scene.choices.count - 1)
                } else {
                    // Without the right answer the choices are only a list.
                    layout = .bullets
                    if scene.bullets.isEmpty { scene.bullets = scene.choices }
                    if let q = scene.subtitle, scene.title.isEmpty { scene.title = q }
                }
            }
            scene.layout = layout
            if scene.title.isEmpty { scene.title = scene.term ?? "" }
            out.append(scene)
        }
        return out
    }

    static func lines(_ v: Any?, hosts: [String]) -> [DialogueLine] {
        guard let list = v as? [Any] else { return [] }
        var out: [DialogueLine] = []
        for item in list {
            guard let o = item as? [String: Any], let text = str(o["text"]) else { continue }
            var host = int(o["host"]) ?? 0
            if let s = str(o["host"] ?? o["speaker"]), Int(s) == nil {
                // "Ekin", "B", "host1"…
                let lower = s.lowercased()
                let second = hosts.count > 1 ? hosts[1].lowercased() : "b"
                host = (lower == second || lower == "b" || lower.hasSuffix("1")) ? 1 : 0
            }
            out.append(DialogueLine(host: min(max(host, 0), 1), text: text, chapter: str(o["chapter"])))
        }
        return out
    }
}

// MARK: - Plain text helpers (on-device and offline writers)

enum TextChunks {
    /// `count` pieces of about `size` characters, spread evenly over the text.
    static func pick(_ text: String, count: Int, size: Int) -> [String] {
        let paragraphs = text.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count > 30 }
        var pieces: [String] = []
        var current = ""
        for p in paragraphs {
            if current.count + p.count > size, !current.isEmpty {
                pieces.append(current)
                current = ""
            }
            current += (current.isEmpty ? "" : "\n\n") + String(p.prefix(size * 2))
        }
        if current.count > 60 { pieces.append(current) }
        guard pieces.count > count else { return pieces }
        let step = Double(pieces.count) / Double(count)
        return (0..<count).map { pieces[min(pieces.count - 1, Int(Double($0) * step))] }
    }

    /// A short line that looks like a heading ("2.3 Kalbin iletim sistemi").
    static func heading(in chunk: String) -> String? {
        for raw in chunk.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[s.") { continue }
            guard line.count >= 4, line.count <= 70, let last = line.last, !".,;:".contains(last),
                  line.split(separator: " ").count <= 9, line.contains(where: \.isLetter) else { continue }
            return line
        }
        return nil
    }

    static func wordWeights(_ text: String) -> [String: Double] {
        var counts: [String: Double] = [:]
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let w = text[range].lowercased()
            if w.count > 3 { counts[w, default: 0] += 1 }
            return true
        }
        return counts
    }

    /// The most informative sentences of a chunk, in reading order.
    static func keySentences(_ chunk: String, weights: [String: Double], count: Int) -> [String] {
        let clean = chunk.replacingOccurrences(of: "\\[s\\.[^\\]]*\\]", with: " ", options: .regularExpression)
        var sentences: [(index: Int, text: String, score: Double)] = []
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = clean
        var i = 0
        tokenizer.enumerateTokens(in: clean.startIndex..<clean.endIndex) { range, _ in
            let s = clean[range].replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            if s.count >= 40, s.count <= 280 {
                let words = s.lowercased().split { !$0.isLetter }.map(String.init).filter { $0.count > 3 }
                let score = words.reduce(0.0) { $0 + log(1 + (weights[$1] ?? 0)) } / Double(max(words.count, 1)).squareRoot()
                sentences.append((index: i, text: s, score: score))
            }
            i += 1
            return true
        }
        let best = sentences.sorted { $0.score > $1.score }.prefix(count)
        return best.sorted { $0.index < $1.index }.map { $0.text }
    }

    static func shorten(_ s: String, words: Int) -> String {
        let parts = s.split(separator: " ")
        guard parts.count > words else { return s.trimmingCharacters(in: CharacterSet(charactersIn: ".")) }
        return parts.prefix(words).joined(separator: " ") + "…"
    }
}
