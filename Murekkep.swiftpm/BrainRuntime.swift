import Foundation
import os
#if canImport(MLX) && canImport(MLXLLM) && canImport(MLXLMCommon) && canImport(Tokenizers) && !MUREKKEP_PLAIN
import MLX
import MLXLLM
import MLXLMCommon
import Tokenizers
#endif

/// Runs the downloaded model on the iPad's GPU (MLX). It is compiled in only when the build has the
/// MLX packages; otherwise `isCompiledIn` is false and the assistant uses Apple's model.
enum BrainRuntime {
    struct Request: Sendable {
        var system: String
        var prompt: String
        /// Tokens the model may think before it answers; nil answers at once.
        var thinking: Int?
        var maxAnswerTokens: Int
        var temperature: Float
    }

    static var isCompiledIn: Bool {
        #if canImport(MLX) && canImport(MLXLLM) && canImport(MLXLMCommon) && canImport(Tokenizers) && !MUREKKEP_PLAIN
        return true
        #else
        return false
        #endif
    }

    private static let gate = BrainGate()

    /// Posted on the main thread when the model needs room to load: the page lets go of the PDF images
    /// and caches it can draw again.
    static let needsMemory = Notification.Name("MurekkepBrainNeedsMemory")

    /// Called as the app goes to the background, where the GPU may not be used: the answer in
    /// progress stops (this waits for it briefly) and an idle model leaves memory.
    static func pauseForBackground() {
        gate.pause()
        Task { await BrainRuntime.unloadIfIdle() }
    }

    static func resume() {
        gate.resume()
    }

    /// The reply as it grows: thinking and answer, raw. Only the newest text matters, so older
    /// versions waiting in the stream are dropped.
    static func stream(_ request: Request, directory: URL) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let task = Task.detached(priority: .userInitiated) {
                do {
                    try await BrainRuntime.generate(request, directory: directory) { continuation.yield($0) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The whole reply at once (raw).
    static func complete(_ request: Request, directory: URL) async throws -> String {
        var last = ""
        for try await raw in BrainRuntime.stream(request, directory: directory) {
            last = raw
        }
        return last
    }

    static func unload() async {
        #if canImport(MLX) && canImport(MLXLLM) && canImport(MLXLMCommon) && canImport(Tokenizers) && !MUREKKEP_PLAIN
        await BrainHost.shared.unload(force: true)
        #endif
    }

    static func unloadIfIdle() async {
        #if canImport(MLX) && canImport(MLXLLM) && canImport(MLXLMCommon) && canImport(Tokenizers) && !MUREKKEP_PLAIN
        await BrainHost.shared.unload(force: false)
        #endif
    }

    private static func generate(_ request: Request, directory: URL, update: @escaping (String) -> Void) async throws {
        #if canImport(MLX) && canImport(MLXLLM) && canImport(MLXLMCommon) && canImport(Tokenizers) && !MUREKKEP_PLAIN
        try gate.enter()
        defer { gate.leave() }
        let host = BrainHost.shared
        await host.acquire()
        do {
            try await host.generate(request, directory: directory, gate: gate, update: update)
            await host.release()
        } catch {
            await host.release()
            throw error
        }
        #else
        throw LocalAIError(Loc.t("Bu derlemede indirilebilir model motoru (MLX) yok. Yeni derlemede gelir."))
        #endif
    }
}

/// Keeps the GPU out of the background: an answer may not start while the app is away, and going
/// away waits (briefly) for the running one to stop.
final class BrainGate: @unchecked Sendable {
    private let lock = NSLock()
    private var paused = false
    private var running = 0

    var isPaused: Bool {
        lock.lock()
        defer { lock.unlock() }
        return paused
    }

    func enter() throws {
        lock.lock()
        defer { lock.unlock() }
        if paused {
            throw LocalAIError(Loc.t("Uygulama arka plandayken model çalışmaz. Tekrar sor."))
        }
        running += 1
    }

    func leave() {
        lock.lock()
        running -= 1
        lock.unlock()
    }

    func pause() {
        lock.lock()
        paused = true
        lock.unlock()
        let deadline = Date().addingTimeInterval(0.8)
        while Date() < deadline {
            lock.lock()
            let busy = running > 0
            lock.unlock()
            if !busy { return }
            usleep(10_000)
        }
    }

    func resume() {
        lock.lock()
        paused = false
        lock.unlock()
    }
}

#if canImport(MLX) && canImport(MLXLLM) && canImport(MLXLMCommon) && canImport(Tokenizers) && !MUREKKEP_PLAIN

/// The model stays loaded between answers (loading takes seconds) and answers one at a time.
private actor BrainHost {
    static let shared = BrainHost()

    private var container: ModelContainer?
    private var directory: URL?
    private var busy = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        if busy {
            await withCheckedContinuation { waiting.append($0) }
        }
        busy = true
    }

    func release() {
        if waiting.isEmpty {
            busy = false
        } else {
            waiting.removeFirst().resume()
        }
    }

    func unload(force: Bool) {
        guard force || !busy else { return }
        container = nil
        directory = nil
        Memory.clearCache()
    }

    private func load(_ directory: URL) async throws -> ModelContainer {
        if let container, self.directory == directory { return container }
        container = nil
        self.directory = nil
        Memory.clearCache()
        // Loading more than iOS lets the app hold would end the app; say so instead.
        let weights = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "safetensors" }
            .reduce(Int64(0)) { $0 + max(0, BrainFetcher.fileSize($1)) } ?? 0
        // The weights stay as they are (4-bit); room is made around them instead.
        let need = BrainMemory.need(weights: weights)
        var free = Int64(os_proc_available_memory())
        if free > 0, free < need {
            await MainActor.run { NotificationCenter.default.post(name: BrainRuntime.needsMemory, object: nil) }
            try? await Task.sleep(nanoseconds: 200_000_000)
            free = Int64(os_proc_available_memory())
        }
        if free > 0, free < need {
            throw LocalAIError(Loc.t("Model için bellek yetmiyor. Açık uygulamaları kapatıp tekrar dene."))
        }
        Memory.cacheLimit = 64 * 1024 * 1024
        let configuration = ModelConfiguration(directory: directory, extraEOSTokens: ["<|im_end|>"])
        let loaded = try await LLMModelFactory.shared.loadContainer(
            from: LocalFilesOnly(), using: TransformersTokenizerLoader(), configuration: configuration)
        // Buffers left over from reading the files are not needed again.
        Memory.clearCache()
        container = loaded
        self.directory = directory
        return loaded
    }

    func generate(_ request: BrainRuntime.Request, directory: URL, gate: BrainGate,
                  update: @escaping (String) -> Void) async throws {
        let container = try await load(directory)
        try Task.checkCancellation()
        var components = GenerationComponents()
        var maxTokens = request.maxAnswerTokens
        if let budget = request.thinking {
            let (reasoning, tokenizer) = await container.perform { context in
                (context.configuration.reasoningConfig, context.tokenizer)
            }
            if let reasoning {
                // Qwen's own words for "time is up, answer now" when the model declares none.
                let transition = reasoning.budgetTransition ?? QwenReasoningProtocol.qwen3.budgetTransition
                let limit = try ThinkingBudgetConfiguration(maximumTokenCount: budget,
                                                            minimumAnswerTokenCount: min(256, request.maxAnswerTokens),
                                                            transitionOverride: transition)
                components = try components.applyingThinkingBudget(limit, reasoning: reasoning, tokenizer: tokenizer)
            }
            maxTokens += budget + 160
        }
        let parameters = GenerateParameters(maxTokens: maxTokens, temperature: request.temperature,
                                            topP: request.thinking == nil ? 0.8 : 0.95, topK: 20)
        let session = ChatSession(container, instructions: request.system, generateParameters: parameters,
                                  components: components,
                                  additionalContext: ["enable_thinking": request.thinking != nil])
        var raw = ""
        for try await chunk in session.streamResponse(to: request.prompt) {
            if gate.isPaused {
                // Give the generation a moment to see the stream end before the app is suspended.
                try? await Task.sleep(nanoseconds: 80_000_000)
                throw LocalAIError(Loc.t("Uygulama arka plana geçtiği için yanıt durdu. Tekrar sor."))
            }
            try Task.checkCancellation()
            raw += chunk
            update(raw)
        }
    }
}

/// The weights are on disk already (the app downloads them itself).
private struct LocalFilesOnly: MLXLMCommon.Downloader {
    func download(id: String, revision: String?, matching patterns: [String], useLatest: Bool,
                  progressHandler: @Sendable @escaping (Progress) -> Void) async throws -> URL {
        throw LocalAIError(Loc.t("Model dosyaları bulunamadı. Ayarlar'dan modeli yeniden indir."))
    }
}

/// Hugging Face's tokenizers (swift-transformers) for MLX.
private struct TransformersTokenizerLoader: MLXLMCommon.TokenizerLoader {
    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        let upstream = try await Tokenizers.AutoTokenizer.from(modelFolder: directory, strict: false)
        return TokenizerBridge(upstream: upstream)
    }
}

private struct TokenizerBridge: MLXLMCommon.Tokenizer {
    let upstream: any Tokenizers.Tokenizer

    func encode(text: String, addSpecialTokens: Bool) -> [Int] {
        upstream.encode(text: text, addSpecialTokens: addSpecialTokens)
    }

    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
        upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
    }

    func convertTokenToId(_ token: String) -> Int? {
        upstream.convertTokenToId(token)
    }

    func convertIdToToken(_ id: Int) -> String? {
        upstream.convertIdToToken(id)
    }

    var bosToken: String? { upstream.bosToken }
    var eosToken: String? { upstream.eosToken }
    var unknownToken: String? { upstream.unknownToken }

    func applyChatTemplate(messages: [[String: any Sendable]], tools: [[String: any Sendable]]?,
                           additionalContext: [String: any Sendable]?) throws -> [Int] {
        do {
            return try upstream.applyChatTemplate(messages: messages, tools: tools, additionalContext: additionalContext)
        } catch Tokenizers.TokenizerError.missingChatTemplate {
            throw MLXLMCommon.TokenizerError.missingChatTemplate
        }
    }
}
#endif
