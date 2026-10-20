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

// MARK: - Text the voice reads

/// Numbers and math written out as words (twin of tests/ports/speech.py): the voice reads English
/// digits well but misreads Turkish numbers, and drops math symbols in both languages.
extension SpeechText {
    private static let units = ["", "bir", "iki", "üç", "dört", "beş", "altı", "yedi", "sekiz", "dokuz"]
    private static let tens = ["", "on", "yirmi", "otuz", "kırk", "elli", "altmış", "yetmiş", "seksen", "doksan"]
    private static let ordinals: [String: String] = [
        "bir": "birinci", "iki": "ikinci", "üç": "üçüncü", "dört": "dördüncü", "beş": "beşinci", "altı": "altıncı",
        "yedi": "yedinci", "sekiz": "sekizinci", "dokuz": "dokuzuncu", "on": "onuncu", "yirmi": "yirminci",
        "otuz": "otuzuncu", "kırk": "kırkıncı", "elli": "ellinci", "altmış": "altmışıncı", "yetmiş": "yetmişinci",
        "seksen": "sekseninci", "doksan": "doksanıncı", "yüz": "yüzüncü", "bin": "bininci", "milyon": "milyonuncu",
        "milyar": "milyarıncı", "sıfır": "sıfırıncı",
    ]
    private static let letters: [String: String] = [
        "a": "a", "b": "be", "c": "ce", "d": "de", "e": "e", "f": "fe", "g": "ge", "h": "he", "i": "i", "j": "je",
        "k": "ke", "l": "le", "m": "me", "n": "ne", "o": "o", "p": "pe", "q": "kü", "r": "re", "s": "se", "t": "te",
        "u": "u", "v": "ve", "w": "çift ve", "x": "iks", "y": "ye", "z": "ze",
    ]

    static func turkishNumber(_ value: Int) -> String {
        if value == 0 { return "sıfır" }
        var n = value
        var parts: [String] = []
        for (scale, name) in [(1_000_000_000, "milyar"), (1_000_000, "milyon"), (1_000, "bin")] where n >= scale {
            let head = n / scale
            n %= scale
            if !(scale == 1_000 && head == 1) { parts.append(turkishNumber(head)) }  // "bin", not "bir bin"
            parts.append(name)
        }
        if n >= 100 {
            if n / 100 > 1 { parts.append(units[n / 100]) }
            parts.append("yüz")
            n %= 100
        }
        if n >= 10 {
            parts.append(tens[n / 10])
            n %= 10
        }
        if n > 0 { parts.append(units[n]) }
        return parts.joined(separator: " ")
    }

    static func turkishOrdinal(_ n: Int) -> String {
        var words = turkishNumber(n).split(separator: " ").map(String.init)
        if let last = words.last { words[words.count - 1] = ordinals[last] ?? last }
        return words.joined(separator: " ")
    }

    /// A fraction part: digit by digit when it starts with 0 ("05" → "sıfır beş"), else as a number.
    private static func fraction(_ s: String) -> String {
        if s.hasPrefix("0") { return s.compactMap { Int(String($0)) }.map { turkishNumber($0) }.joined(separator: " ") }
        return turkishNumber(Int(s) ?? 0)
    }

    private static func letter(_ s: String, english: Bool) -> String {
        english ? s : (letters[s.lowercased()] ?? s)
    }

    /// Replaces every match of `pattern` with `transform(groups)` (groups[0] is the whole match).
    private static func sub(_ text: String, _ pattern: String, _ transform: ([String]) -> String) -> String {
        guard let rx = try? NSRegularExpression(pattern: pattern) else { return text }
        let ns = text as NSString
        let matches = rx.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return text }
        var out = ""
        var last = 0
        for m in matches {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            let groups = (0..<m.numberOfRanges).map { i -> String in
                let r = m.range(at: i)
                return r.location == NSNotFound ? "" : ns.substring(with: r)
            }
            out += transform(groups)
            last = m.range.location + m.range.length
        }
        out += ns.substring(from: last)
        return out
    }

    static func spokenMath(_ text: String, english: Bool) -> String {
        var t = text
        t = sub(t, #"\b([A-Za-z])[(]([A-Za-z0-9]+)[)]"#) { g in
            let arg = g[2].count == 1 && g[2].first!.isLetter ? letter(g[2], english: english) : g[2]
            return "\(letter(g[1], english: english)) \(english ? "of " : "")\(arg)"
        }
        t = t.replacingOccurrences(of: "²", with: english ? " squared" : " kare")
        t = t.replacingOccurrences(of: "³", with: english ? " cubed" : " küp")
        t = sub(t, #"([\w)])\s*\^\s*(-?\w+)"#) { g in "\(g[1]) \(english ? "to the power of" : "üssü") \(g[2])" }
        if !english {
            t = sub(t, #"%\s?(\d+(?:[.,]\d+)?)"#) { g in "yüzde \(g[1])" }
            t = sub(t, #"(\d+(?:[.,]\d+)?)\s?%"#) { g in "yüzde \(g[1])" }
            t = sub(t, #"\b(\d{1,2}):(\d{2})\b"#) { g in "\(turkishNumber(Int(g[1]) ?? 0)) \(turkishNumber(Int(g[2]) ?? 0))" }
            t = sub(t, #"\b(\d{1,4})\.(?=\s+[a-zçğıöşü])"#) { g in turkishOrdinal(Int(g[1]) ?? 0) }
            t = sub(t, #"\b\d{1,3}(?:\.\d{3})+\b"#) { g in g[0].replacingOccurrences(of: ".", with: "") }
            t = sub(t, #"\b(\d+),(\d+)\b"#) { g in "\(turkishNumber(Int(g[1]) ?? 0)) virgül \(fraction(g[2]))" }
            t = sub(t, #"\b(\d+)\.(\d+)\b"#) { g in "\(turkishNumber(Int(g[1]) ?? 0)) nokta \(fraction(g[2]))" }
            t = sub(t, #"(?<![\w)])[-−](\d)"#) { g in "eksi \(g[1])" }
            t = sub(t, #"(\d+)'([a-zçğıöşü]+)"#) { g in turkishNumber(Int(g[1]) ?? 0) + g[2] }
        }
        t = sub(t, #"(\d)([A-Za-z])\b"#) { g in "\(g[1]) \(g[2])" }
        let minus = english ? " minus " : " eksi "
        t = sub(t, #"\s*=\s*"#) { _ in english ? " equals " : " eşittir " }
        t = sub(t, #"\s*\+\s*"#) { _ in english ? " plus " : " artı " }
        t = sub(t, #"\s*−\s*"#) { _ in minus }
        t = sub(t, #"(\d|\b[xyz])\s+-\s+(?=\d|[xyz]\b)"#) { g in g[1] + minus }
        t = sub(t, #"\s*×\s*"#) { _ in english ? " times " : " çarpı " }
        t = sub(t, #"\s*÷\s*"#) { _ in english ? " divided by " : " bölü " }
        t = sub(t, #"(?:(?<=[\dπ)])|(?<=\b[xyz]))\s*/\s*(?=[\dπ(]|[xyz]\b)"#) { _ in english ? " over " : " bölü " }
        t = t.replacingOccurrences(of: "π", with: " pi ")
        if !english {
            t = sub(t, #"\d+"#) { g in turkishNumber(Int(g[0]) ?? 0) }
            t = sub(t, #"\b([xyz])\b"#) { g in letters[g[1]] ?? g[1] }
        }
        t = sub(t, #"[ \t]{2,}"#) { _ in " " }
        t = sub(t, #" ([,.;:!?])"#) { g in g[1] }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The text in pieces of at most `maxChars`: whole sentences, a long sentence cut at commas, then
    /// between words. Joined with spaces they give the (whitespace-collapsed) text back.
    static func chunks(_ text: String, maxChars: Int) -> [String] {
        let clean = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !clean.isEmpty else { return [] }
        var out: [String] = []
        var current = ""
        func add(_ piece: String) {
            let candidate = current.isEmpty ? piece : current + " " + piece
            if candidate.count <= maxChars {
                current = candidate
            } else {
                if !current.isEmpty { out.append(current) }
                current = piece
            }
        }
        for sentence in split(clean, after: #"(?<=[.!?…])\s+"#) {
            if sentence.count <= maxChars {
                add(sentence)
                continue
            }
            for part in split(sentence, after: #"(?<=[,;:])\s+"#) {
                if part.count <= maxChars {
                    add(part)
                } else {
                    for word in part.split(separator: " ") { add(String(word)) }
                }
            }
        }
        if !current.isEmpty { out.append(current) }
        return out
    }

    /// `text` split where `pattern` matches (the matched separator is dropped).
    private static func split(_ text: String, after pattern: String) -> [String] {
        guard let rx = try? NSRegularExpression(pattern: pattern) else { return [text] }
        let ns = text as NSString
        var out: [String] = []
        var last = 0
        for m in rx.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            out.append(ns.substring(with: NSRange(location: last, length: m.range.location - last)))
            last = m.range.location + m.range.length
        }
        out.append(ns.substring(from: last))
        return out.filter { !$0.isEmpty }
    }
}
