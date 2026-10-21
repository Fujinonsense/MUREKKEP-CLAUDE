import AVFoundation
import Foundation
import UIKit

/// The sound of a brush: which recordings it plays and how they are shaped. Families that share
/// recordings share one bank (a metal nib is the fountain pen's recording played a little faster and
/// brighter).
enum SoundFamily: Int, CaseIterable {
    case pencil
    case eraser
    case pen
    case nib
    case metal
    case felt
    case brush
    case gel
    case water
    case lava
    case grass
    case spark
    case ice
    case sparkle

    /// The bank names, in slot order: the asset catalog has "<bank>-1", "<bank>-2"… for each.
    static let banks = ["kagit", "ses-pen", "ses-nib", "ses-felt", "ses-brush", "ses-water", "ses-lava", "ses-grass",
                        "ses-spark", "ses-ice", "ses-sparkle"]

    var bank: String {
        switch self {
        case .pencil, .eraser: return "kagit"
        case .pen: return "ses-pen"
        case .nib, .metal: return "ses-nib"
        case .felt: return "ses-felt"
        case .brush, .gel: return "ses-brush"
        case .water: return "ses-water"
        case .lava: return "ses-lava"
        case .grass: return "ses-grass"
        case .spark: return "ses-spark"
        case .ice: return "ses-ice"
        case .sparkle: return "ses-sparkle"
        }
    }

    var slot: Int { Self.banks.firstIndex(of: bank) ?? 0 }

    /// Loudness next to a pencil: the magic pens are a shade quieter, only a hint of their world.
    var level: Float {
        switch self {
        case .pencil: return 1
        case .eraser: return 0.8
        case .pen: return 0.95
        case .nib: return 0.9
        case .metal: return 0.85
        case .felt: return 0.85
        case .brush: return 0.8
        case .gel: return 0.7
        case .water: return 0.55
        case .lava: return 0.65
        case .grass: return 0.6
        case .spark: return 0.45
        case .ice: return 0.55
        case .sparkle: return 0.45
        }
    }

    /// Playback speed at rest and how much faster at full motion.
    var speed: (base: Float, span: Float) {
        switch self {
        case .pencil: return (0.88, 0.28)
        case .eraser: return (0.66, 0.2)
        case .pen: return (0.9, 0.25)
        case .nib: return (0.92, 0.25)
        case .metal: return (1.06, 0.25)
        case .felt, .brush: return (0.9, 0.2)
        case .gel: return (0.75, 0.15)
        case .water, .lava: return (0.92, 0.1)
        case .grass, .spark, .sparkle: return (0.97, 0.12)
        case .ice: return (1, 0.2)
        }
    }

    /// Low-pass coefficient (1 = open; 0.3 ≈ a soft 2.5 kHz).
    var tone: Float {
        switch self {
        case .pencil, .nib, .spark, .ice: return 0.85
        case .eraser: return 0.28
        case .pen, .grass: return 0.75
        case .metal, .sparkle: return 0.9
        case .felt, .water: return 0.6
        case .brush: return 0.55
        case .gel: return 0.4
        case .lava: return 0.5
        }
    }
}

extension Brush {
    var soundFamily: SoundFamily {
        switch self {
        case .pencil: return .pencil
        case .pen: return .pen
        case .fountain, .calligraphy: return .nib
        case .gold, .chrome, .pearl: return .metal
        case .highlighter, .neon: return .felt
        case .watercolor, .wet, .impasto, .rainbow: return .brush
        case .jelly: return .gel
        case .sea, .wave: return .water
        case .lava: return .lava
        case .grass: return .grass
        case .lightning: return .spark
        case .ice: return .ice
        case .glitter, .galaxy: return .sparkle
        }
    }
}

/// The sound of writing: every pen its own quiet timbre, following the hand.
///
/// Recordings live in the asset catalog (`SoundFamily.banks`; the pencil's are "Pencil #1, #3, #4" by
/// Joseph Sardin, BigSoundBank, the others CC0 recordings from Freesound and two synthesized sparkles;
/// see docs/superpowers/reports/2026-10-21-batch-4-sounds.md). A family's recordings are decoded the
/// first time its pen touches the paper, off the main thread. While the pencil moves, two voices play
/// short overlapping grains of them (power-complementary sine windows), each from a random recording,
/// place and slightly different speed, so the sound never loops. How loud it is comes from
/// `PenSoundEnvelope` (speed, the turns of the letters, pressure); the audio thread glides there within
/// about 12 ms. Without recordings a filtered-noise model stands in.
///
/// The engine starts when the pencil touches down (not when it first moves) on its own queue, with a
/// 5 ms buffer, and stays warm for 30 s after the last stroke, so a line is heard from its first
/// millimetre. The ambient category keeps music and videos playing (nothing is paused or ducked) and the
/// silent switch mutes it. While a lecture is being recorded it stays silent.
final class PaperSound: @unchecked Sendable {
    static let shared = PaperSound()
    /// The recordings and the voice run at this rate (the engine's mixer converts to the hardware's),
    /// which is also the rate `PenSoundEnvelope`'s glide factors are made for.
    static let rate: Double = 44_100

    /// Shared with the audio thread (single floats, so a torn read is harmless):
    /// 0 target gain, 1 current gain, 2 tone (low-pass coefficient), 3 playback speed,
    /// 4 crackle (noise model), 5–6 filter memory, 7 high-pass memory, 8 bank slot of the pen.
    private let params: UnsafeMutablePointer<Float>
    /// Two grain voices × (position, age, length, speed, amplitude, slot), in samples.
    private let voices: UnsafeMutablePointer<Double>
    private let random: UnsafeMutablePointer<UInt32>
    /// Sine window, 1024 steps.
    private let window: UnsafeMutablePointer<Float>
    /// Per bank slot, published once its recordings are decoded (count and tables first, the samples
    /// last); the audio thread uses a slot only when all four are there.
    private let bankData: UnsafeMutablePointer<UnsafeMutablePointer<Float>?>
    private let bankStarts: UnsafeMutablePointer<UnsafeMutablePointer<Int>?>
    private let bankLengths: UnsafeMutablePointer<UnsafeMutablePointer<Int>?>
    private let bankCounts: UnsafeMutablePointer<Int>
    /// Kept so the decoded samples live as long as the app.
    private var loadedBanks: [Int: SampleBank] = [:]
    /// Slots being decoded or decoded (main thread).
    private var requested = Set<Int>()
    /// Slots that have no recordings in this build.
    private var missing = Set<Int>()

    private let engine = AVAudioEngine()
    private let audioQueue = DispatchQueue(label: "murekkep.papersound", qos: .userInteractive)
    private let loadQueue = DispatchQueue(label: "murekkep.papersound.load", qos: .userInitiated)
    /// Engine state, only touched on `audioQueue`.
    private var source: AVAudioSourceNode?
    private var running = false
    private var failed = false
    private var stopWork: DispatchWorkItem?

    /// Main thread: the hand's loudness and the pen in use.
    private var envelope = PenSoundEnvelope()
    private var family: SoundFamily = .pencil
    /// Set while a lecture is recorded: the pen must not end up on the recording.
    var isSuppressed = false {
        didSet { if isSuppressed { params[0] = 0 } }
    }

    private init() {
        params = UnsafeMutablePointer<Float>.allocate(capacity: 9)
        params.initialize(repeating: 0, count: 9)
        params[2] = 0.5
        params[3] = 1
        voices = UnsafeMutablePointer<Double>.allocate(capacity: 12)
        voices.initialize(repeating: 0, count: 12)
        random = UnsafeMutablePointer<UInt32>.allocate(capacity: 1)
        random.initialize(to: 0x9E37_79B9)
        window = UnsafeMutablePointer<Float>.allocate(capacity: 1024)
        for i in 0..<1024 {
            window[i] = sinf(Float.pi * Float(i) / 1023)
        }
        let n = SoundFamily.banks.count
        bankData = .allocate(capacity: n)
        bankData.initialize(repeating: nil, count: n)
        bankStarts = .allocate(capacity: n)
        bankStarts.initialize(repeating: nil, count: n)
        bankLengths = .allocate(capacity: n)
        bankLengths.initialize(repeating: nil, count: n)
        bankCounts = .allocate(capacity: n)
        bankCounts.initialize(repeating: 0, count: n)
    }

    /// Pencil down (main thread): wakes the engine and readies this pen's recordings, so the line is
    /// heard from its start. `brush` nil = the eraser.
    func prepare(brush: Brush?, level: Double) {
        guard level > 0, !isSuppressed else { return }
        family = brush?.soundFamily ?? .eraser
        envelope.reset()
        params[0] = 0
        load(family.slot)
        params[8] = Float(family.slot)
        audioQueue.async { [self] in
            stopWork?.cancel()
            startIfNeeded()
        }
    }

    /// Called while the pencil moves: `point` in view points, `time` the touch's timestamp, `force` 0…~4.
    func write(point: CGPoint, time: TimeInterval, force: CGFloat, brush: Brush?, level: Double) {
        guard level > 0, !isSuppressed else { return }
        let f = brush?.soundFamily ?? .eraser
        if f != family {
            family = f
            load(f.slot)
            params[8] = Float(f.slot)
        }
        let loudness = envelope.update(x: Double(point.x), y: Double(point.y), time: time, force: Double(force))
        let hasBank = bankCounts[f.slot] > 0 || bankCounts[SoundFamily.pencil.slot] > 0
        // The noise model is much quieter on purpose: a whisper under the music.
        let master: Float = hasBank ? 0.32 : 0.05
        params[0] = Float(level) * master * f.level * Float(loudness)
        let motion = Float(min(loudness / 0.6, 1))
        params[3] = f.speed.base + f.speed.span * motion
        params[2] = f.tone
        params[4] = f == .pencil ? 0.35 : (f == .eraser ? 0.1 : 0.05)
    }

    /// Pencil lifted: fade out, and stop the engine after 30 s of quiet to save battery.
    func lift() {
        params[0] = 0
        envelope.reset()
        audioQueue.async { [self] in
            guard running else { return }
            stopWork?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.stop() }
            stopWork = work
            audioQueue.asyncAfter(deadline: .now() + 30, execute: work)
        }
    }

    /// Decodes a bank's recordings once, off the main thread, then publishes them to the audio thread.
    private func load(_ slot: Int) {
        guard !requested.contains(slot), !missing.contains(slot) else { return }
        requested.insert(slot)
        let name = SoundFamily.banks[slot]
        loadQueue.async { [weak self] in
            let bank = SampleBank.load(prefix: name, sampleRate: Self.rate)
            DispatchQueue.main.async {
                guard let self else { return }
                guard let bank else {
                    self.missing.insert(slot)
                    return
                }
                self.loadedBanks[slot] = bank
                self.bankCounts[slot] = bank.count
                self.bankStarts[slot] = bank.starts
                self.bankLengths[slot] = bank.lengths
                self.bankData[slot] = bank.data
            }
        }
    }

    /// `audioQueue` only.
    private func startIfNeeded() {
        // A phone call or a route change can stop the engine behind our back.
        guard !failed, !(running && engine.isRunning) else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            // A short buffer: the sound answers the pencil within a few milliseconds.
            try? session.setPreferredIOBufferDuration(0.005)
            try session.setActive(true, options: [])
            if source == nil {
                guard let format = AVAudioFormat(standardFormatWithSampleRate: Self.rate, channels: 1) else {
                    failed = true
                    return
                }
                let node = makeNode(format: format, sampleRate: Self.rate)
                engine.attach(node)
                engine.connect(node, to: engine.mainMixerNode, format: format)
                source = node
            }
            engine.prepare()
            try engine.start()
            running = true
        } catch {
            // No sound is fine; never retry in a loop.
            failed = true
        }
    }

    private func makeNode(format: AVAudioFormat, sampleRate: Double) -> AVAudioSourceNode {
        let p = params
        let v = voices
        let r = random
        let w = window
        let datas = bankData
        let startsTable = bankStarts
        let lengthsTable = bankLengths
        let counts = bankCounts
        let pencilSlot = SoundFamily.pencil.slot
        let slotCount = SoundFamily.banks.count
        let attack = Float(PenSoundEnvelope.attack)
        let release = Float(PenSoundEnvelope.release)
        let grain = sampleRate * 0.11
        // Voice 0 starts a grain at once; voice 1 waits half a grain, silent, so the two stay half
        // a grain apart and their windows always add up to an even level.
        v[0] = 0
        v[1] = grain
        v[2] = grain
        v[3] = 1
        v[4] = 0
        v[5] = -1
        v[6] = 0
        v[7] = grain / 2
        v[8] = grain
        v[9] = 1
        v[10] = 0
        v[11] = -1

        return AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard let first = buffers.first, let raw = first.mData else { return noErr }
            let out = raw.assumingMemoryBound(to: Float.self)
            var seed = r.pointee
            @inline(__always) func next() -> UInt32 {
                seed ^= seed << 13
                seed ^= seed >> 17
                seed ^= seed << 5
                return seed
            }
            @inline(__always) func uniform() -> Double {
                Double(next() & 0xFF_FFFF) / Double(0xFF_FFFF)
            }
            /// A slot whose recordings are all published, or -1.
            @inline(__always) func ready(_ s: Int) -> Int {
                guard s >= 0, s < slotCount, datas[s] != nil, startsTable[s] != nil, lengthsTable[s] != nil, counts[s] > 0 else { return -1 }
                return s
            }
            var gain = p[1]
            let target = p[0]
            let tone = p[2]
            let speed = Double(p[3])
            let crackle = p[4]
            var low = p[5]
            var low2 = p[6]
            var dc = p[7]
            var wanted = ready(Int(p[8]))
            if wanted < 0 { wanted = ready(pencilSlot) }
            // Recordings already sound like paper; plain noise needs its rumble taken out harder.
            let highPass: Float = wanted >= 0 ? 0.003 : 0.04
            for i in 0..<Int(frameCount) {
                var x: Float = 0
                if wanted >= 0 {
                    for k in 0..<2 {
                        let b = k * 6
                        if v[b + 1] >= v[b + 2] {
                            // A new grain: as long as the other voice still needs, so the two stay
                            // half a grain apart; this pen's recordings, random place and speed.
                            let o = (1 - k) * 6
                            let remaining = max(v[o + 2] - v[o + 1], 1)
                            let length = min(max(2 * remaining, grain * 0.5), grain * 1.6)
                            let s = wanted
                            guard let lengths = lengthsTable[s], let starts = startsTable[s] else { continue }
                            let pick = Int(next() % UInt32(max(counts[s], 1)))
                            let rate = speed * (0.92 + 0.16 * uniform())
                            let span = length * rate + 4
                            let room = max(Double(lengths[pick]) - span, 1)
                            v[b] = Double(starts[pick]) + uniform() * room
                            v[b + 1] = 0
                            v[b + 2] = length
                            v[b + 3] = rate
                            v[b + 4] = 1
                            v[b + 5] = Double(s)
                        }
                        let s = Int(v[b + 5])
                        guard s >= 0, let data = datas[s] else {
                            v[b + 1] += 1
                            continue
                        }
                        let age = v[b + 1]
                        let length = v[b + 2]
                        let position = v[b]
                        let index = Int(position)
                        let frac = Float(position - Double(index))
                        let sample = data[index] * (1 - frac) + data[index + 1] * frac
                        let windowIndex = min(1023, Int(age / length * 1023))
                        x += sample * w[windowIndex] * Float(v[b + 4])
                        v[b] = position + v[b + 3]
                        v[b + 1] = age + 1
                    }
                } else {
                    // Noise model: filtered white noise with an occasional graphite crackle.
                    var white = Float(next() % 20_001) / 10_000 - 1
                    if crackle > 0, next() % 997 < 6 {
                        white *= 1 + crackle * 6
                    }
                    x = white * 0.5
                }
                gain += (target - gain) * (target > gain ? attack : release)
                // Tone: two gentle low-passes, then the rumble taken out.
                low += (x - low) * tone
                low2 += (low - low2) * tone
                dc += (low2 - dc) * highPass
                out[i] = (low2 - dc) * gain
            }
            for b in buffers.dropFirst() {
                if let d = b.mData {
                    d.copyMemory(from: raw, byteCount: Int(b.mDataByteSize))
                }
            }
            r.pointee = seed
            p[1] = gain
            p[5] = low
            p[6] = low2
            p[7] = dc
            return noErr
        }
    }

    /// `audioQueue` only.
    private func stop() {
        guard running else { return }
        engine.pause()
        running = false
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }
}

/// The recordings, decoded once to mono floats at the engine's rate, with their pauses removed,
/// evened out in loudness and laid end to end (a few silent samples after each one).
final class SampleBank: @unchecked Sendable {
    let data: UnsafeMutablePointer<Float>
    let starts: UnsafeMutablePointer<Int>
    let lengths: UnsafeMutablePointer<Int>
    let count: Int

    private init(_ clips: [[Float]]) {
        count = clips.count
        let total = clips.reduce(0) { $0 + $1.count + 8 }
        data = UnsafeMutablePointer<Float>.allocate(capacity: total)
        data.initialize(repeating: 0, count: total)
        starts = UnsafeMutablePointer<Int>.allocate(capacity: count)
        lengths = UnsafeMutablePointer<Int>.allocate(capacity: count)
        var offset = 0
        for (i, clip) in clips.enumerated() {
            starts[i] = offset
            lengths[i] = clip.count
            clip.withUnsafeBufferPointer { buffer in
                if let base = buffer.baseAddress {
                    (data + offset).update(from: base, count: clip.count)
                }
            }
            offset += clip.count + 8
        }
    }

    /// nil when the app has no recordings named "<prefix>-1"… (the noise model plays then).
    static func load(prefix: String, sampleRate: Double) -> SampleBank? {
        var clips: [[Float]] = []
        for i in 1...16 {
            guard let asset = NSDataAsset(name: "\(prefix)-\(i)"), let samples = decode(asset, sampleRate: sampleRate) else { continue }
            let active = activeParts(samples, sampleRate: sampleRate)
            // Shorter than a few grains: not worth keeping.
            guard active.count > Int(sampleRate * 0.4) else { continue }
            clips.append(normalized(active))
        }
        return clips.isEmpty ? nil : SampleBank(clips)
    }

    private static func decode(_ asset: NSDataAsset, sampleRate: Double) -> [Float]? {
        let type = asset.typeIdentifier.lowercased()
        let ext: String
        if type.contains("mp3") {
            ext = "mp3"
        } else if type.contains("mpeg-4") || type.contains("m4a") || type.contains("aac") {
            ext = "m4a"
        } else if type.contains("aiff") {
            ext = "aiff"
        } else if type.contains("caf") {
            ext = "caf"
        } else {
            ext = "wav"
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("murekkep-ses-\(UUID().uuidString).\(ext)")
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            try asset.data.write(to: url)
            let file = try AVAudioFile(forReading: url)
            let inFormat = file.processingFormat
            let frames = AVAudioFrameCount(file.length)
            guard frames > 1000, let input = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: frames) else { return nil }
            try file.read(into: input)
            guard let outFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
                  let converter = AVAudioConverter(from: inFormat, to: outFormat) else { return nil }
            converter.downmix = true
            let capacity = AVAudioFrameCount(Double(frames) * sampleRate / max(inFormat.sampleRate, 1)) + 4096
            guard let output = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: capacity) else { return nil }
            var fed = false
            var error: NSError?
            let status = converter.convert(to: output, error: &error) { _, inputStatus in
                if fed {
                    inputStatus.pointee = .endOfStream
                    return nil
                }
                fed = true
                inputStatus.pointee = .haveData
                return input
            }
            guard status != .error, output.frameLength > 0, let channel = output.floatChannelData?[0] else { return nil }
            return Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
        } catch {
            return nil
        }
    }

    /// Keeps the stretches where the pencil is actually on the paper and joins them with short
    /// cross-fades, so no grain lands in a pause.
    private static func activeParts(_ x: [Float], sampleRate: Double) -> [Float] {
        let size = max(256, Int(sampleRate * 0.01))
        let n = x.count / size
        guard n > 8 else { return x }
        var rms = [Float](repeating: 0, count: n)
        for k in 0..<n {
            var s: Float = 0
            for i in (k * size)..<((k + 1) * size) {
                s += x[i] * x[i]
            }
            rms[k] = (s / Float(size)).squareRoot()
        }
        let loud = rms.sorted()[Int(Double(n - 1) * 0.9)]
        let threshold = loud * 0.25
        guard threshold > 0 else { return x }
        let fade = min(96, size / 2)
        var out: [Float] = []
        out.reserveCapacity(x.count)
        var k = 0
        while k < n {
            guard rms[k] >= threshold else {
                k += 1
                continue
            }
            var e = k
            while e < n, rms[e] >= threshold {
                e += 1
            }
            let chunk = Array(x[(k * size)..<(e * size)])
            if out.count >= fade, chunk.count > 2 * fade {
                let base = out.count - fade
                for j in 0..<fade {
                    let t = Float(j) / Float(fade)
                    out[base + j] = out[base + j] * (1 - t) + chunk[j] * t
                }
                out.append(contentsOf: chunk[fade...])
            } else {
                out.append(contentsOf: chunk)
            }
            k = e
        }
        return out
    }

    /// Every recording at the same loudness (and no peak above 0.9).
    private static func normalized(_ x: [Float]) -> [Float] {
        guard !x.isEmpty else { return x }
        var s: Float = 0
        var peak: Float = 0
        for v in x {
            s += v * v
            peak = max(peak, abs(v))
        }
        let rms = (s / Float(x.count)).squareRoot()
        guard rms > 1e-6 else { return x }
        let k = min(0.2 / rms, 0.9 / max(peak, 1e-6))
        return x.map { $0 * k }
    }
}
