import Foundation
#if canImport(SherpaOnnxC)
import SherpaOnnxC
#endif

/// The app's own voices: Supertonic 3 (one model, 31 languages, five women's and five men's voices)
/// run by sherpa-onnx on the iPad's CPU. No network, no key. The model is bundled by the build
/// (AppVoices/supertonic3); a build without it has no voices.
enum EmbeddedVoices {
    /// Speaker ids, measured on 21 Oct 2026 with Whisper large-v3 on Turkish and English test sentences
    /// (0 % character errors for every voice; median pitch 171–190 Hz for 0–4, 89–134 Hz for 5–9).
    static let women: [Int32] = [0, 1, 2, 3, 4]
    static let men: [Int32] = [5, 6, 7, 8, 9]
    /// Flow-matching steps per sentence (the model's recommended setting).
    static let steps: Int32 = 8
    /// Silence between the pieces of a long text, in seconds.
    static let pause = 0.25

    static var modelFolder: URL? {
        guard let root = Bundle.main.url(forResource: "AppVoices", withExtension: nil) else { return nil }
        let folder = root.appendingPathComponent("supertonic3", isDirectory: true)
        return FileManager.default.fileExists(atPath: folder.appendingPathComponent("voice.bin").path) ? folder : nil
    }

    static var isAvailable: Bool {
        #if canImport(SherpaOnnxC)
        return modelFolder != nil
        #else
        return false
        #endif
    }

    /// One synthesis at a time, off the main thread; the engine is loaded on first use.
    private static let queue = DispatchQueue(label: "murekkep.voices", qos: .userInitiated)

    /// Speaks `text` with speaker `sid` into a 16-bit WAV file at `url`; returns its length in seconds.
    static func speak(_ text: String, language: OverviewLanguage, sid: Int32, speed: Float, to url: URL) async throws -> Double {
        let spoken = SpeechText.spokenMath(SpeechText.clean(text, language: language), english: language.isEnglish)
        let pieces = SpeechText.chunks(spoken, maxChars: 260)
        guard !pieces.isEmpty else { throw SpeechError.silent }
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Double, Error>) in
            queue.async {
                #if canImport(SherpaOnnxC)
                guard let engine = Engine.shared else {
                    cont.resume(throwing: SpeechError.unavailable)
                    return
                }
                var samples: [Float] = []
                var rate = 44_100
                for piece in pieces {
                    guard let audio = engine.generate(piece, sid: sid, language: language.isEnglish ? "en" : "tr", speed: speed) else { continue }
                    rate = audio.rate
                    if !samples.isEmpty {
                        samples += [Float](repeating: 0, count: Int(Double(rate) * pause))
                    }
                    samples += audio.samples
                }
                guard !samples.isEmpty else {
                    cont.resume(throwing: SpeechError.silent)
                    return
                }
                let ok = url.path.withCString { path in
                    SherpaOnnxWriteWave(samples, Int32(samples.count), Int32(rate), path)
                }
                if ok == 1 {
                    cont.resume(returning: Double(samples.count) / Double(rate))
                } else {
                    cont.resume(throwing: SpeechError.silent)
                }
                #else
                cont.resume(throwing: SpeechError.unavailable)
                #endif
            }
        }
    }

    #if canImport(SherpaOnnxC)
    /// The loaded Supertonic model. Used only on `queue`.
    private final class Engine {
        static let shared: Engine? = Engine()

        private let tts: OpaquePointer

        private init?() {
            guard let folder = EmbeddedVoices.modelFolder else { return nil }
            var owned: [UnsafeMutablePointer<CChar>] = []
            func c(_ s: String) -> UnsafePointer<CChar>? {
                guard let p = strdup(s) else { return nil }
                owned.append(p)
                return UnsafePointer(p)
            }
            defer { owned.forEach { free($0) } }
            func file(_ name: String) -> UnsafePointer<CChar>? { c(folder.appendingPathComponent(name).path) }
            var config = SherpaOnnxOfflineTtsConfig()
            config.model.supertonic.duration_predictor = file("duration_predictor.int8.onnx")
            config.model.supertonic.text_encoder = file("text_encoder.int8.onnx")
            config.model.supertonic.vector_estimator = file("vector_estimator.int8.onnx")
            config.model.supertonic.vocoder = file("vocoder.int8.onnx")
            config.model.supertonic.tts_json = file("tts.json")
            config.model.supertonic.unicode_indexer = file("unicode_indexer.bin")
            config.model.supertonic.voice_style = file("voice.bin")
            // Two threads: fast enough, and the rest of the iPad stays smooth.
            config.model.num_threads = 2
            config.model.debug = 0
            config.model.provider = c("cpu")
            config.max_num_sentences = 2
            config.silence_scale = 0.2
            guard let made = SherpaOnnxCreateOfflineTts(&config) else { return nil }
            tts = made
        }

        deinit {
            SherpaOnnxDestroyOfflineTts(tts)
        }

        func generate(_ text: String, sid: Int32, language: String, speed: Float) -> (samples: [Float], rate: Int)? {
            var cfg = SherpaOnnxGenerationConfig()
            cfg.sid = sid
            cfg.speed = speed
            cfg.num_steps = EmbeddedVoices.steps
            cfg.silence_scale = 0.2
            let extra = "{\"lang\": \"\(language)\"}"
            return text.withCString { ctext -> (samples: [Float], rate: Int)? in
                extra.withCString { cextra -> (samples: [Float], rate: Int)? in
                    cfg.extra = cextra
                    guard let audio = SherpaOnnxOfflineTtsGenerateWithConfig(tts, ctext, &cfg, nil, nil) else { return nil }
                    defer { SherpaOnnxDestroyOfflineTtsGeneratedAudio(audio) }
                    let n = Int(audio.pointee.n)
                    guard n > 0, let samples = audio.pointee.samples else { return nil }
                    return (samples: Array(UnsafeBufferPointer(start: samples, count: n)), rate: Int(audio.pointee.sample_rate))
                }
            }
        }
    }
    #endif
}
