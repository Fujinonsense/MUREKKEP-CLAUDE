import Foundation
#if canImport(FoundationModels) && !MUREKKEP_PLAIN
import FoundationModels
#endif

/// What to make.
struct StudyOptions {
    var kind: StudyKind
    var english: Bool
    /// Cards or questions.
    var count: Int
    /// The student's note to the writer ("only definitions", "hard, exam-style questions"…).
    var note = ""

    /// The note as a prompt line, or "" without one.
    var noteLine: String {
        let n = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? "" : "Öğrencinin notu (kaynaklara bağlı kalarak buna uy): \(n)"
    }
}

/// Writes a study tool from the gathered sources with the chosen brain: the on-device model (part by
/// part, in structured drafts, each checked for its language), Claude (one JSON reply) or the keyless
/// writer. A piece the model cannot write falls back to the keyless writer, so a set never comes back
/// empty while the sources have text.
enum StudyWriter {
    typealias Progress = @MainActor (Double, String?) -> Void

    @MainActor
    static func write(options: StudyOptions, material: StudioMaterial, engine: StudioEngine, settings: AppSettings,
                      progress: @escaping Progress) async throws -> StudySet {
        let parts = StudioPlan.parts(material).map { (title: $0.title, text: $0.text) }
        guard !parts.isEmpty else { throw StudioWriterError.noText }
        var set = StudySet(kind: options.kind, title: title(material), sectionID: nil,
                           sourceIDs: material.items.map(\.noteID), sourceTitles: material.items.map(\.title),
                           english: options.english, engine: Loc.t("Çevrimdışı"))
        switch engine {
        case .claude:
            try await claude(&set, options: options, material: material, settings: settings, progress: progress)
        case .deviceBrain:
            do {
                try await brain(&set, options: options, material: material, progress: progress)
            } catch is CancellationError {
                throw CancellationError()
            } catch let interrupted as BrainInterrupted {
                // The app went to the background: the job does this step again on screen, with the
                // same writer (BackgroundWork).
                throw interrupted
            } catch {
                // Not on the iPad yet, or it failed: Apple's model, then the keyless writer below.
                set.engine = Loc.t("Çevrimdışı")
                #if canImport(FoundationModels) && !MUREKKEP_PLAIN
                if #available(iOS 26.0, *), OnDeviceAI.isAvailable {
                    do {
                        try await onDevice(&set, options: options, parts: parts, progress: progress)
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {}
                }
                #endif
            }
        case .onDevice:
            #if canImport(FoundationModels) && !MUREKKEP_PLAIN
            if #available(iOS 26.0, *), OnDeviceAI.isAvailable {
                try await onDevice(&set, options: options, parts: parts, progress: progress)
            } else {
                offline(&set, options: options, parts: parts)
            }
            #else
            offline(&set, options: options, parts: parts)
            #endif
        case .offline:
            offline(&set, options: options, parts: parts)
        }
        // Whatever the brain left empty, the keyless writer fills.
        if set.isEmpty {
            offline(&set, options: options, parts: parts)
        }
        guard !set.isEmpty else { throw StudioWriterError.noText }
        return set
    }

    private static func title(_ material: StudioMaterial) -> String {
        if let chapter = material.chapter, !chapter.title.isEmpty { return chapter.title }
        return material.items.count == 1 ? material.items[0].title : material.items.map(\.title).prefix(2).joined(separator: " · ")
    }

    private static func offline(_ set: inout StudySet, options: StudyOptions, parts: [StudyOffline.Part]) {
        set.engine = Loc.t("Çevrimdışı")
        switch options.kind {
        case .flashcards: set.cards = StudyOffline.flashcards(parts: parts, english: options.english, count: options.count)
        case .quiz: set.questions = StudyOffline.quiz(parts: parts, english: options.english, count: options.count)
        case .mindMap: set.map = StudyOffline.mindMap(title: set.title, parts: parts, english: options.english)
        case .guide: set.guide = StudyOffline.guide(parts: parts, english: options.english)
        }
    }

    private static func language(_ english: Bool) -> OverviewLanguage { english ? .english : .turkish }

    // MARK: Claude

    @MainActor
    private static func claude(_ set: inout StudySet, options: StudyOptions, material: StudioMaterial, settings: AppSettings,
                               progress: @escaping Progress) async throws {
        guard let key = settings.apiKey else { throw StudioWriterError.needsKey }
        let lang = language(options.english)
        let text = String(material.allText.prefix(120_000))
        let request = ClaudeRequest(model: settings.model.rawValue, effort: settings.effort.rawValue, maxTokens: 16_000,
                                    system: system(lang), context: .none, contextNote: "",
                                    turns: [ClaudeTurn(role: .user, text: jsonPrompt(options, sources: text), imageJPEG: nil)])
        progress(0.2, Loc.t("Claude hazırlıyor…"))
        let reply = try await ClaudeClient.collect(request, apiKey: key) { chars in
            progress(min(0.95, 0.2 + Double(chars) / 30_000), nil)
        }
        guard let json = jsonObject(in: reply) else { throw StudioWriterError.unreadableScript }
        set.engine = "Claude · \(settings.model.title)"
        apply(json, to: &set, kind: options.kind)
    }

    // MARK: Downloaded model

    /// The downloaded model writes the same JSON as Claude, from as much of the sources as its prompt
    /// takes in a reasonable time.
    @MainActor
    private static func brain(_ set: inout StudySet, options: StudyOptions, material: StudioMaterial,
                              progress: @escaping Progress) async throws {
        guard let directory = DeviceBrain.shared.directory else { throw StudioWriterError.noText }
        let lang = language(options.english)
        let text = String(material.allText.prefix(14_000))
        let request = BrainRuntime.Request(system: system(lang), prompt: jsonPrompt(options, sources: text),
                                           thinking: nil, maxAnswerTokens: 3_500, temperature: 0.5)
        progress(0.1, Loc.t("İndirilen model hazırlıyor…"))
        var reply = ""
        for try await raw in BrainRuntime.stream(request, directory: directory) {
            reply = ThinkingText.split(raw, thinking: false).answer
            progress(min(0.95, 0.15 + Double(reply.count) / 9_000), nil)
        }
        guard let json = jsonObject(in: reply) else { throw StudioWriterError.unreadableScript }
        set.engine = Loc.t("Cihazda · {0}", DeviceBrain.shared.model?.title ?? "Qwen3.5")
        apply(json, to: &set, kind: options.kind)
    }

    // MARK: JSON

    private static func system(_ lang: OverviewLanguage) -> String {
        "Sen titiz bir öğretmensin; öğrencinin kaynaklarından çalışma araçları hazırlarsın. " + StudioWriter.scriptDirective(lang)
    }

    private static func jsonPrompt(_ options: StudyOptions, sources text: String) -> String {
        let shape: String
        switch options.kind {
        case .flashcards:
            shape = #"{"cards":[{"front":"…","back":"…"}]}"# + " — \(options.count) kart; ön yüz kısa bir soru ya da terim, arka yüz 1-3 cümlelik net cevap."
        case .quiz:
            shape = #"{"questions":[{"question":"…","choices":["…","…","…","…"],"answer":0,"explanation":"…"}]}"#
                + " — \(options.count) soru; dört şık, yalnızca biri doğru, answer doğru şıkkın 0'dan başlayan sırası, explanation kısa gerekçe."
        case .mindMap:
            shape = #"{"title":"…","children":[{"title":"…","children":[{"title":"…","children":[]}]}]}"#
                + " — 4-8 ana dal, her dalda 2-5 alt dal, gerekirse bir seviye daha; düğümler en fazla 6 kelime."
        case .guide:
            shape = #"{"summary":["…"],"sections":[{"heading":"…","points":["…"]}],"terms":[{"term":"…","definition":"…"}],"questions":["…"]}"#
                + " — 3 cümlelik özet, her bölüm için 3-5 madde, 8-14 terim, 5-8 düşündürücü soru."
        }
        let note = options.noteLine.isEmpty ? "" : "\n\(options.noteLine)"
        return "Aşağıdaki kaynaklardan bir çalışma aracı hazırla. Yalnızca kaynaklara dayan. Yanıtın yalnızca şu biçimde tek bir JSON olsun, başka hiçbir şey yazma:\n\(shape)\(note)\n\nKaynaklar:\n\(text)"
    }

    /// The JSON object in a reply (models sometimes wrap it in a sentence or a code fence).
    private static func jsonObject(in reply: String) -> [String: Any]? {
        guard let start = reply.firstIndex(of: "{"), let end = reply.lastIndex(of: "}"), start < end,
              let data = String(reply[start...end]).data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func apply(_ json: [String: Any], to set: inout StudySet, kind: StudyKind) {
        switch kind {
        case .flashcards:
            set.cards = (json["cards"] as? [[String: Any]] ?? []).compactMap { c in
                guard let f = c["front"] as? String, let b = c["back"] as? String, !f.isEmpty, !b.isEmpty else { return nil }
                return Flashcard(front: f, back: b)
            }
        case .quiz:
            set.questions = (json["questions"] as? [[String: Any]] ?? []).compactMap { q in
                guard let text = q["question"] as? String, let choices = q["choices"] as? [String], choices.count >= 2,
                      let answer = (q["answer"] as? Int) ?? (q["answer"] as? NSNumber)?.intValue, choices.indices.contains(answer) else { return nil }
                return QuizQuestion(question: text, choices: choices, answer: answer, explanation: q["explanation"] as? String ?? "")
            }
        case .mindMap:
            func node(_ v: Any?) -> MindNode? {
                guard let d = v as? [String: Any], let t = d["title"] as? String else { return nil }
                return MindNode(title: t, children: (d["children"] as? [Any] ?? []).compactMap(node))
            }
            set.map = node(json)
            if let t = set.map?.title, t.isEmpty { set.map?.title = set.title }
        case .guide:
            set.guide = StudyGuide(
                summary: json["summary"] as? [String] ?? [],
                sections: (json["sections"] as? [[String: Any]] ?? []).compactMap { s in
                    guard let h = s["heading"] as? String else { return nil }
                    return GuideSection(heading: h, points: s["points"] as? [String] ?? [])
                },
                terms: (json["terms"] as? [[String: Any]] ?? []).compactMap { t in
                    guard let term = t["term"] as? String, let def = t["definition"] as? String else { return nil }
                    return GuideTerm(term: term, definition: def)
                },
                questions: json["questions"] as? [String] ?? [])
        }
    }

    // MARK: On device

    #if canImport(FoundationModels) && !MUREKKEP_PLAIN
    @available(iOS 26.0, *)
    @MainActor
    private static func onDevice(_ set: inout StudySet, options: StudyOptions, parts: [StudyOffline.Part],
                                 progress: @escaping Progress) async throws {
        let lang = language(options.english)
        let instructions = "Sen titiz bir öğretmensin. Yalnızca verilen metne dayan, uydurma. " + StudioWriter.scriptDirective(lang)
            + (options.noteLine.isEmpty ? "" : " " + options.noteLine)
        set.engine = Loc.t("Cihazda · Apple Intelligence")
        let chunks = parts.prefix(10)
        // Cards and questions are spread over the parts.
        let perPart = max(2, Int((Double(options.count) / Double(max(chunks.count, 1))).rounded(.up)))
        var guideSections: [GuideSection] = []
        var guideTerms: [GuideTerm] = []
        var root = MindNode(title: set.title)
        for (i, part) in chunks.enumerated() {
            try Task.checkCancellation()
            progress(Double(i) / Double(chunks.count), Loc.t("Cihazdaki model hazırlıyor ({0}/{1})…", "\(i + 1)", "\(chunks.count)"))
            let text = String(part.text.prefix(2_600))
            let head = "Bölüm: \(part.title)\n\nMetin:\n\(text)"
            switch options.kind {
            case .flashcards where set.cards.count < options.count:
                let prompt = "Bu metinden \(perPart) bilgi kartı hazırla: ön yüz kısa bir soru ya da terim, arka yüz kısa ve net cevap.\n\n" + head
                if let draft = try? await AppleStudyBridge.cards(instructions: instructions, prompt: prompt) {
                    for c in draft.cards where StudioWriter.speaks(lang, c.front + " " + c.back) && set.cards.count < options.count {
                        set.cards.append(Flashcard(front: c.front, back: c.back))
                    }
                }
            case .quiz where set.questions.count < options.count:
                let prompt = "Bu metinden \(perPart) çoktan seçmeli soru hazırla: dört şık, yalnızca biri doğru; doğru şıkkın sırasını ve kısa bir gerekçe ver.\n\n" + head
                if let draft = try? await AppleStudyBridge.quiz(instructions: instructions, prompt: prompt) {
                    for q in draft.questions where q.choices.count == 4 && (0..<4).contains(q.answer)
                        && StudioWriter.speaks(lang, q.question) && set.questions.count < options.count {
                        set.questions.append(QuizQuestion(question: q.question, choices: q.choices, answer: q.answer, explanation: q.explanation))
                    }
                }
            case .mindMap:
                let prompt = "Bu bölüm için bir zihin haritası dalı hazırla: 2-5 alt başlık, her birinin altında 1-3 kısa nokta (en fazla 6 kelime).\n\n" + head
                if let draft = try? await AppleStudyBridge.branch(instructions: instructions, prompt: prompt),
                   StudioWriter.speaks(lang, draft.topics.map(\.title).joined(separator: " ")) {
                    root.children.append(MindNode(title: part.title, children: draft.topics.map { t in
                        MindNode(title: t.title, children: t.points.map { MindNode(title: $0) })
                    }))
                }
            case .guide:
                let prompt = "Bu bölüm için bir çalışma rehberi kısmı hazırla: 3-5 ana madde ve metinde tanımlanan 1-3 terim.\n\n" + head
                if let draft = try? await AppleStudyBridge.guideSection(instructions: instructions, prompt: prompt),
                   StudioWriter.speaks(lang, draft.points.joined(separator: " ")) {
                    guideSections.append(GuideSection(heading: part.title, points: draft.points))
                    guideTerms += draft.terms.map { GuideTerm(term: $0.term, definition: $0.definition) }
                }
            default:
                break
            }
        }
        switch options.kind {
        case .mindMap:
            if !root.children.isEmpty { set.map = root }
        case .guide:
            guard !guideSections.isEmpty else { return }
            let sample = parts.map { String($0.text.prefix(500)) }.joined(separator: "\n\n").prefix(2_400)
            let prompt = "Bu ders için 3 cümlelik bir özet ve öğrenciyi düşündüren 5-8 soru yaz.\n\nBölümler: \(parts.map(\.title).joined(separator: " | "))\n\nMetinden örnek:\n\(sample)"
            let wrap = try? await AppleStudyBridge.summary(instructions: instructions, prompt: prompt)
            set.guide = StudyGuide(summary: wrap?.summary ?? [], sections: guideSections, terms: guideTerms,
                                   questions: wrap?.questions ?? [])
        default:
            break
        }
        progress(1, nil)
    }
    #endif
}

extension StudySet {
    var isEmpty: Bool {
        switch kind {
        case .flashcards: return cards.isEmpty
        case .quiz: return questions.isEmpty
        case .mindMap: return (map?.children ?? []).isEmpty
        case .guide: return guide.map { $0.sections.isEmpty && $0.summary.isEmpty } ?? true
        }
    }
}

#if canImport(FoundationModels) && !MUREKKEP_PLAIN
@available(iOS 26.0, *)
@Generable
struct StudyCardDraft {
    @Guide(description: "Ön yüz: kısa bir soru ya da terim")
    var front: String
    @Guide(description: "Arka yüz: 1-3 cümlelik net cevap")
    var back: String
}

@available(iOS 26.0, *)
@Generable
struct StudyCardsDraft {
    @Guide(description: "Bilgi kartları", .maximumCount(8))
    var cards: [StudyCardDraft]
}

@available(iOS 26.0, *)
@Generable
struct StudyQuestionDraft {
    @Guide(description: "Soru kökü")
    var question: String
    @Guide(description: "Dört şık; yalnızca biri doğru", .count(4))
    var choices: [String]
    @Guide(description: "Doğru şıkkın sırası: 0, 1, 2 ya da 3", .range(0...3))
    var answer: Int
    @Guide(description: "Doğru cevabın kısa gerekçesi")
    var explanation: String
}

@available(iOS 26.0, *)
@Generable
struct StudyQuizDraft {
    @Guide(description: "Çoktan seçmeli sorular", .maximumCount(6))
    var questions: [StudyQuestionDraft]
}

@available(iOS 26.0, *)
@Generable
struct StudyTopicDraft {
    @Guide(description: "Alt başlık, en fazla 6 kelime")
    var title: String
    @Guide(description: "Kısa noktalar, her biri en fazla 6 kelime", .maximumCount(3))
    var points: [String]
}

@available(iOS 26.0, *)
@Generable
struct StudyBranchDraft {
    @Guide(description: "Bölümün alt başlıkları", .maximumCount(5))
    var topics: [StudyTopicDraft]
}

@available(iOS 26.0, *)
@Generable
struct StudyTermDraft {
    @Guide(description: "Terim")
    var term: String
    @Guide(description: "Terimin 1-2 cümlelik tanımı")
    var definition: String
}

@available(iOS 26.0, *)
@Generable
struct StudyGuideSectionDraft {
    @Guide(description: "Bölümün ana maddeleri, her biri tek cümle", .maximumCount(5))
    var points: [String]
    @Guide(description: "Metinde tanımlanan terimler", .maximumCount(3))
    var terms: [StudyTermDraft]
}

@available(iOS 26.0, *)
@Generable
struct StudySummaryDraft {
    @Guide(description: "Dersin özeti: 3 cümle", .maximumCount(3))
    var summary: [String]
    @Guide(description: "Öğrenciyi düşündüren sorular", .maximumCount(8))
    var questions: [String]
}

@available(iOS 26.0, *)
enum AppleStudyBridge {
    private static func session(_ instructions: String) -> LanguageModelSession {
        LanguageModelSession(instructions: instructions)
    }

    static func cards(instructions: String, prompt: String) async throws -> StudyCardsDraft {
        try await session(instructions).respond(to: prompt, generating: StudyCardsDraft.self).content
    }

    static func quiz(instructions: String, prompt: String) async throws -> StudyQuizDraft {
        try await session(instructions).respond(to: prompt, generating: StudyQuizDraft.self).content
    }

    static func branch(instructions: String, prompt: String) async throws -> StudyBranchDraft {
        try await session(instructions).respond(to: prompt, generating: StudyBranchDraft.self).content
    }

    static func guideSection(instructions: String, prompt: String) async throws -> StudyGuideSectionDraft {
        try await session(instructions).respond(to: prompt, generating: StudyGuideSectionDraft.self).content
    }

    static func summary(instructions: String, prompt: String) async throws -> StudySummaryDraft {
        try await session(instructions).respond(to: prompt, generating: StudySummaryDraft.self).content
    }
}
#endif
