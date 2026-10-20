import AVFoundation
import Foundation
import UIKit

/// The sound of writing on paper.
///
/// Real recordings of a pencil and a pen on paper live in the asset catalog as data sets named
/// "kagit-1", "kagit-2"… (the bundled ones: "Pencil #1, #3, #4" by Joseph Sardin, BigSoundBank,
/// CC0). Their quiet parts are cut out, and while the pencil moves, two voices play
/// short overlapping grains of them (power-complementary sine windows), each grain from a random
/// recording at a random place and a slightly different speed. Nothing is ever looped, so the sound
/// has no audible period. Loudness and brightness follow the pencil's speed, pressure and brush.
/// Without recordings a filtered-noise model stands in.
///
/// The ambient audio category keeps music and videos playing (nothing is paused or ducked) and the
/// silent switch mutes it.
final class PaperSound: @unchecked Sendable {
    static let shared = PaperSound()

    /// Shared with the audio thread (single floats, so a torn read is harmless):
    /// 0 target gain, 1 current gain, 2 tone (low-pass coefficient), 3 playback speed,
    /// 4 crackle (noise model), 5–6 filter memory, 7 high-pass memory.
    private let params: UnsafeMutablePointer<Float>
    /// Two grain voices × (position, age, length, speed, amplitude), in samples.
    private let voices: UnsafeMutablePointer<Double>
    private let random: UnsafeMutablePointer<UInt32>
    /// Sine window, 1024 steps.
    private let window: UnsafeMutablePointer<Float>
    private let engine = AVAudioEngine()
    private var source: AVAudioSourceNode?
    private var bank: SampleBank?
    private var running = false
    private var failed = false
    private var stopWork: DispatchWorkItem?

    private init() {
        params = UnsafeMutablePointer<Float>.allocate(capacity: 8)
        params.initialize(repeating: 0, count: 8)
        params[2] = 0.5
        params[3] = 1
        voices = UnsafeMutablePointer<Double>.allocate(capacity: 10)
        voices.initialize(repeating: 0, count: 10)
        random = UnsafeMutablePointer<UInt32>.allocate(capacity: 1)
        random.initialize(to: 0x9E37_79B9)
        window = UnsafeMutablePointer<Float>.allocate(capacity: 1024)
        for i in 0..<1024 {
            window[i] = sinf(Float.pi * Float(i) / 1023)
        }
    }

    /// Called while the pencil moves. `speed` in view points per second, `pressure` 0…~4.
    func write(speed: CGFloat, pressure: CGFloat, brush: Brush?, level: Double) {
        guard !failed, level > 0 else { return }
        startIfNeeded()
        stopWork?.cancel()
        let motion = Float(min(max(speed / 900, 0), 1))
        let press = Float(min(max(pressure, 0.2), 2.5))
        if bank != nil {
            params[0] = Float(level) * 0.38 * powf(motion, 0.6) * (0.6 + 0.2 * press)
            params[3] = 0.88 + 0.28 * motion
        } else {
            // The noise model: very quiet on purpose, a whisper under the music.
            params[0] = Float(level) * 0.055 * powf(motion, 0.7) * (0.55 + 0.25 * press)
        }
        switch brush {
        case .pencil?:
            params[2] = 0.85
            params[4] = 0.35
        case .highlighter?, .wave?, .sea?, .watercolor?:
            // Felt and wet brushes: a soft, dull rub.
            params[2] = 0.3
            params[4] = 0
            params[3] *= 0.85
        case nil:
            // Eraser.
            params[2] = 0.28
            params[4] = 0.1
            params[3] *= 0.75
        default:
            params[2] = 0.62
            params[4] = 0.05
        }
    }

    /// Pencil lifted: fade out, and stop the engine after a pause to save battery.
    func lift() {
        params[0] = 0
        guard running else { return }
        stopWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.stop() }
        stopWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: work)
    }

    private func startIfNeeded() {
        // A phone call or a route change can stop the engine behind our back.
        guard !(running && engine.isRunning) else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try session.setActive(true, options: [])
            if source == nil {
                let rate = session.sampleRate > 0 ? session.sampleRate : 44_100
                guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1) else {
                    failed = true
                    return
                }
                bank = SampleBank.load(sampleRate: rate)
                let node = makeNode(format: format, sampleRate: rate)
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
        let data = bank?.data
        let starts = bank?.starts
        let lengths = bank?.lengths
        let count = bank?.count ?? 0
        let grain = sampleRate * 0.11
        // Voice 0 starts a grain at once; voice 1 waits half a grain, silent, so the two stay half
        // a grain apart and their windows always add up to an even level.
        v[0] = 0
        v[1] = grain
        v[2] = grain
        v[3] = 1
        v[4] = 0
        v[5] = 0
        v[6] = 0
        v[7] = grain / 2
        v[8] = 0
        v[9] = 0

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
            var gain = p[1]
            let target = p[0]
            let tone = p[2]
            let speed = Double(p[3])
            let crackle = p[4]
            var low = p[5]
            var low2 = p[6]
            var dc = p[7]
            // Recordings already sound like paper; plain noise needs its rumble taken out harder.
            let highPass: Float = count > 0 ? 0.003 : 0.04
            for i in 0..<Int(frameCount) {
                var x: Float = 0
                if let data, let starts, let lengths, count > 0 {
                    for k in 0..<2 {
                        let b = k * 5
                        if v[b + 1] >= v[b + 2] {
                            // A new grain: as long as the other voice still needs, so the two stay
                            // half a grain apart; random recording, place and speed.
                            let o = (1 - k) * 5
                            let remaining = max(v[o + 2] - v[o + 1], 1)
                            let length = min(max(2 * remaining, grain * 0.5), grain * 1.6)
                            let pick = Int(next() % UInt32(count))
                            let rate = speed * (0.92 + 0.16 * uniform())
                            let span = length * rate + 4
                            let room = max(Double(lengths[pick]) - span, 1)
                            v[b] = Double(starts[pick]) + uniform() * room
                            v[b + 1] = 0
                            v[b + 2] = length
                            v[b + 3] = rate
                            v[b + 4] = 1
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
                gain += (target - gain) * 0.0015
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

    private func stop() {
        guard running else { return }
        engine.pause()
        running = false
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }
}

/// The recordings, decoded once to mono floats at the engine's rate, with their pauses removed,
/// evened out in loudness and laid end to end (a few silent samples after each one).
private final class SampleBank: @unchecked Sendable {
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

    /// nil when the app has no recordings (the noise model plays then).
    static func load(sampleRate: Double) -> SampleBank? {
        var clips: [[Float]] = []
        for i in 1...16 {
            guard let asset = NSDataAsset(name: "kagit-\(i)"), let samples = decode(asset, sampleRate: sampleRate) else { continue }
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
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("murekkep-kagit-\(UUID().uuidString).\(ext)")
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
