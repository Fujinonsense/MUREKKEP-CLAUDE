import Foundation
#if canImport(FoundationModels) && !MUREKKEP_PLAIN
import FoundationModels
#endif

/// A question solved by a model: the chosen option (or a short answer) and why.
struct SolvedQuestion {
    var answer: String
    var reasoning: String
}

/// One unit of an exercise answered by a model: the fills of its gaps in order (or one short answer)
/// and why.
struct ExerciseAnswer {
    var fills: [String]
    var note: String
}

/// Apple's on-device language model (Foundation Models framework, iPadOS 26+).
/// Runs entirely on the iPad: free, private, works offline. Web search is offered to the
/// model as a tool that uses the keyless `WebSearch`.
enum OnDeviceAI {
    /// nil when the model is ready, otherwise a reason the user can act on.
    static var unavailableReason: String? {
        #if canImport(FoundationModels) && !MUREKKEP_PLAIN
        if #available(iOS 26.0, *) {
            return AppleModelBridge.unavailableReason
        }
        return Loc.t("Cihaz üstü model için iPadOS 26 veya üstü gerekir.")
        #else
        return Loc.t("Bu derlemede Apple Intelligence (Foundation Models) yok. iPadOS 26 SDK ile derlendiğinde otomatik açılır.")
        #endif
    }

    static var isAvailable: Bool { unavailableReason == nil }

    /// The on-device context window is small (about 4K tokens), so callers keep prompts short.
    static let contextBudget = 2_200

    static func respond(instructions: String, prompt: String, useWeb: Bool, collector: SourceCollector) async throws -> String {
        #if canImport(FoundationModels) && !MUREKKEP_PLAIN
        if #available(iOS 26.0, *) {
            return try await AppleModelBridge.respond(instructions: instructions, prompt: prompt,
                                                      useWeb: useWeb, collector: collector)
        }
        #endif
        throw LocalAIError(unavailableReason ?? Loc.t("Cihaz üstü model kullanılamıyor."))
    }

    /// One question of a page, solved on its own (the small model is far more accurate this way than
    /// with a whole page of questions at once).
    static func solve(_ question: PageQuestion, language: AnswerLanguage) async throws -> SolvedQuestion {
        #if canImport(FoundationModels) && !MUREKKEP_PLAIN
        if #available(iOS 26.0, *) {
            return try await AppleModelBridge.solve(question, language: language)
        }
        #endif
        throw LocalAIError(unavailableReason ?? Loc.t("Cihaz üstü model kullanılamıyor."))
    }

    /// One item of a textbook exercise (or one sentence of a running text), answered with the
    /// exercise's instruction in front of the model. When the instruction lists the words that may
    /// fill a gap, the model can only write those words, never an option letter.
    static func answer(_ unit: ExerciseUnit, of exercise: PageExercise, before: String,
                       language: AnswerLanguage) async throws -> ExerciseAnswer {
        #if canImport(FoundationModels) && !MUREKKEP_PLAIN
        if #available(iOS 26.0, *) {
            return try await AppleModelBridge.answer(unit, of: exercise, before: before, language: language)
        }
        #endif
        throw LocalAIError(unavailableReason ?? Loc.t("Cihaz üstü model kullanılamıyor."))
    }

    /// Maps framework errors to short Turkish messages without depending on exact case names.
    static func friendly(_ error: Error) -> String? {
        let d = String(describing: error)
        if d.contains("exceededContextWindowSize") {
            return Loc.t("Sayfalar cihazdaki model için çok uzun. Kapsamı \"Bu sayfa\" yap ve tekrar dene.")
        }
        if d.contains("guardrailViolation") || d.contains("refusal") {
            return Loc.t("Apple'ın güvenlik filtresi bu isteği yanıtlamadı. Soruyu farklı ifade etmeyi dene.")
        }
        if d.contains("unsupportedLanguageOrLocale") {
            return Loc.t("Cihazdaki model bu dili henüz desteklemiyor. Ayarlar'dan çevrimdışı çekirdeği ya da yerel sunucuyu seçebilirsin.")
        }
        if d.contains("assetsUnavailable") {
            return Loc.t("Apple Intelligence modeli henüz hazır değil (indiriliyor olabilir). Biraz sonra tekrar dene.")
        }
        if d.contains("rateLimited") || d.contains("concurrentRequests") {
            return Loc.t("Cihazdaki model meşgul. Birkaç saniye sonra tekrar dene.")
        }
        return nil
    }

    static func isContextOverflow(_ error: Error) -> Bool {
        String(describing: error).contains("exceededContextWindowSize")
    }
}

#if canImport(FoundationModels) && !MUREKKEP_PLAIN
@available(iOS 26.0, *)
enum AppleModelBridge {
    static var unavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return Loc.t("Bu iPad Apple Intelligence'ı desteklemiyor (M1 ya da üstü gerekir).")
            case .appleIntelligenceNotEnabled:
                return Loc.t("Ayarlar > Apple Intelligence ve Siri bölümünden Apple Intelligence'ı aç.")
            case .modelNotReady:
                return Loc.t("Apple Intelligence modeli indiriliyor. Bitince otomatik kullanılır.")
            @unknown default:
                return Loc.t("Apple Intelligence şu an kullanılamıyor.")
            }
        @unknown default:
            return Loc.t("Apple Intelligence şu an kullanılamıyor.")
        }
    }

    static func respond(instructions: String, prompt: String, useWeb: Bool, collector: SourceCollector) async throws -> String {
        var tools: [any Tool] = []
        if useWeb {
            tools.append(WebLookupTool(collector: collector))
        }
        let session = LanguageModelSession(tools: tools, instructions: instructions)
        let options = GenerationOptions(temperature: 0.4, maximumResponseTokens: 900)
        let response = try await session.respond(to: prompt, options: options)
        return response.content
    }

    /// The reasoning is generated before the answer (property order), so the model thinks first.
    static func solve(_ question: PageQuestion, language: AnswerLanguage) async throws -> SolvedQuestion {
        let instructions = "Sen dikkatli bir sınav öğretmenisin. Soruyu ve varsa parçayı oku, şıkları tek tek değerlendir, sonra doğru şıkkı seç. Parçada olmayan bilgiyi uydurma; matematikte işlemleri adım adım yap. "
            + language.directive
        let options = GenerationOptions(temperature: 0.2, maximumResponseTokens: 400)
        var text = question.promptText
        for attempt in 0..<2 {
            do {
                let session = LanguageModelSession(instructions: instructions)
                let response = try await session.respond(to: text, generating: SolvedQuestionDraft.self, options: options)
                return SolvedQuestion(answer: response.content.answer, reasoning: response.content.reasoning)
            } catch let error where attempt == 0 && OnDeviceAI.isContextOverflow(error) {
                var shorter = question
                shorter.passage = question.passage.map { String($0.prefix(3_000)) }
                text = shorter.promptText
            }
        }
        throw LocalAIError(Loc.t("Bu soru cihazdaki model için çok uzun."))
    }

    /// The schema is built for each unit: an array with one entry per gap, each entry one of the
    /// exercise's words (or free text when the instruction lists none). The reason comes first, so the
    /// model thinks before it fills.
    static func answer(_ unit: ExerciseUnit, of exercise: PageExercise, before: String,
                       language: AnswerLanguage) async throws -> ExerciseAnswer {
        let gaps = unit.gaps.count
        let plain = DynamicGenerationSchema(type: String.self, guides: [])
        let word = exercise.choices.isEmpty
            ? plain
            : DynamicGenerationSchema(name: "Word", description: "One of the allowed words", anyOf: exercise.choices)
        let reason = gaps > 0
            ? "One short reason per gap, in order"
            : "Kısa gerekçe: en fazla iki cümle"
        let answerProperty = gaps > 0
            ? DynamicGenerationSchema.Property(name: "fills", description: "The word for each gap, in order",
                                               schema: DynamicGenerationSchema(arrayOf: word, minimumElements: gaps,
                                                                               maximumElements: gaps),
                                               isOptional: false)
            : DynamicGenerationSchema.Property(name: "answer", description: "The answer to the item, short",
                                               schema: word, isOptional: false)
        let root = DynamicGenerationSchema(name: "ExerciseAnswer", description: nil, properties: [
            DynamicGenerationSchema.Property(name: "reasoning", description: reason, schema: plain, isOptional: false),
            answerProperty,
        ])
        let schema = try GenerationSchema(root: root, dependencies: [])
        let instructions = gaps > 0
            ? "You solve one item of a textbook exercise. Read the instruction and the sentence, decide what belongs in each numbered gap, then fill every gap in order. Use only the allowed words when they are given. Never answer with an option letter."
            : "Sen dikkatli bir öğretmensin. Alıştırmanın yönergesini ve varsa notları oku, maddeyi çöz. Şık harfi yalnızca izin verilen cevaplar harfse yaz. " + language.directive
        let options = GenerationOptions(temperature: 0.1, maximumResponseTokens: 300)
        var shown = exercise
        var previous = before
        for attempt in 0..<2 {
            do {
                let prompt = ExerciseSplitter.unitPrompt(shown, unit, before: previous)
                let session = LanguageModelSession(instructions: instructions)
                let response = try await session.respond(to: prompt, schema: schema, options: options)
                let note = text(property(response.content, "reasoning"))
                if gaps > 0 {
                    var fills: [String] = []
                    if let list = property(response.content, "fills"), case let .array(elements) = list.kind {
                        fills = elements.map { text($0) }
                    }
                    return ExerciseAnswer(fills: fills, note: note)
                }
                return ExerciseAnswer(fills: [text(property(response.content, "answer"))], note: note)
            } catch let error where attempt == 0 && OnDeviceAI.isContextOverflow(error) {
                shown.context = ""
                shown.passage = nil
                previous = ""
            }
        }
        throw LocalAIError(Loc.t("Bu soru cihazdaki model için çok uzun."))
    }

    private static func property(_ content: GeneratedContent, _ name: String) -> GeneratedContent? {
        if case let .structure(properties: properties, orderedKeys: _) = content.kind {
            return properties[name]
        }
        return nil
    }

    private static func text(_ content: GeneratedContent?) -> String {
        if let content, case let .string(s) = content.kind {
            return s
        }
        return ""
    }
}

@available(iOS 26.0, *)
@Generable
struct SolvedQuestionDraft {
    @Guide(description: "Kısa gerekçe: en fazla 3 cümle, adım adım")
    var reasoning: String
    @Guide(description: "Yalnızca doğru şıkkın harfi (A, B, C, D ya da E); şık yoksa kısa cevap")
    var answer: String
}

@available(iOS 26.0, *)
struct WebLookupTool: Tool {
    let name = "webSearch"
    let description = "İnternette (Vikipedi ve DuckDuckGo) arama yapar. Not sayfalarında olmayan tanımlar, tarihler, kişiler ve güncel bilgiler için kullan."
    let collector: SourceCollector

    @Generable
    struct Arguments {
        @Guide(description: "Kısa arama sorgusu, 2-6 kelime")
        var query: String
    }

    func call(arguments: Arguments) async throws -> String {
        let results = await WebSearch.search(arguments.query, limit: 3)
        collector.add(results)
        if results.isEmpty {
            return Loc.t("Sonuç bulunamadı.")
        }
        return results.enumerated().map { i, r in
            "[\(i + 1)] \(r.title): \(String(r.snippet.prefix(300))) (\(r.url.absoluteString))"
        }.joined(separator: "\n")
    }
}
#endif
