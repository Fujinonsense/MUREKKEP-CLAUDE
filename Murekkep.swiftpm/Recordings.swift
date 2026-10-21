import AVFoundation
import Foundation

/// Lecture recording for one note (like Notability's audio sync): takes are saved next to the ink
/// ("recordings.json" and "rec-<id>.m4a" in the note's folder); while a take plays, the ink written
/// during it appears as the playhead reaches it, and a finger tap on ink plays from that moment.
/// The writing sound stays silent while recording, so it never ends up on the take. Used on the main
/// thread; the system's callbacks hop there.
final class LectureAudio: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var takes: [Recording] = []
    @Published private(set) var isRecording = false
    /// Seconds recorded so far in the take being recorded.
    @Published private(set) var elapsed: Double = 0
    /// The take the player is on.
    @Published private(set) var current: Recording?
    @Published private(set) var isPlaying = false
    /// The playhead, seconds into `current`.
    @Published private(set) var time: Double = 0
    @Published var rate: Float = 1 {
        didSet { player?.rate = rate }
    }
    /// Hide the take's ink until the playhead reaches it.
    @Published var replayInk = true {
        didSet { updateReplay() }
    }
    @Published var message: String?

    private let folder: URL
    private weak var editor: EditorModel?
    private var recorder: AVAudioRecorder?
    private var recordingID: UUID?
    private var recordingStart: Double = 0
    private var player: AVAudioPlayer?
    private var timer: Timer?
    private var interruption: NSObjectProtocol?

    init(folder: URL, editor: EditorModel) {
        self.folder = folder
        self.editor = editor
        super.init()
        load()
        interruption = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil,
                                                              queue: .main) { [weak self] note in
            // A phone call: the take so far is kept.
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
            self?.stopRecording()
            self?.pause()
        }
    }

    deinit {
        if let interruption { NotificationCenter.default.removeObserver(interruption) }
        timer?.invalidate()
    }

    private var indexURL: URL { folder.appendingPathComponent("recordings.json") }

    func audioURL(_ id: UUID) -> URL { folder.appendingPathComponent("rec-\(id.uuidString).m4a") }

    private func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let saved = try? JSONDecoder().decode([Recording].self, from: data) else { return }
        takes = saved.filter { FileManager.default.fileExists(atPath: audioURL($0.id).path) }
        current = takes.last
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(takes) else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? data.write(to: indexURL, options: .atomic)
    }

    // MARK: Recording

    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        stopPlayback()
        AVAudioApplication.requestRecordPermission { granted in
            DispatchQueue.main.async {
                if granted {
                    self.beginRecording()
                } else {
                    self.message = Loc.t("Mikrofon izni yok. Ayarlar > Mürekkep bölümünden mikrofonu aç.")
                }
            }
        }
    }

    private func beginRecording() {
        guard !isRecording else { return }
        PaperSound.shared.isSuppressed = true
        do {
            let session = AVAudioSession.sharedInstance()
            // Music may keep playing; the take is the microphone.
            try session.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers, .defaultToSpeaker, .allowBluetoothA2DP])
            try session.setActive(true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let id = UUID()
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 64_000,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            ]
            let r = try AVAudioRecorder(url: audioURL(id), settings: settings)
            guard r.record() else {
                throw NSError(domain: "Murekkep", code: 1)
            }
            recorder = r
            recordingID = id
            recordingStart = Date().timeIntervalSinceReferenceDate
            elapsed = 0
            isRecording = true
            updateTimer()
        } catch {
            PaperSound.shared.isSuppressed = false
            message = Loc.t("Kayıt başlatılamadı.")
        }
    }

    func stopRecording() {
        guard let r = recorder, let id = recordingID else { return }
        let duration = r.currentTime
        r.stop()
        recorder = nil
        recordingID = nil
        isRecording = false
        PaperSound.shared.isSuppressed = false
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        if duration > 0.5 {
            let take = Recording(id: id, start: recordingStart, duration: duration,
                                 title: Loc.t("Kayıt {0}", "\(takes.count + 1)"))
            takes.append(take)
            save()
            current = take
            time = 0
        } else {
            try? FileManager.default.removeItem(at: audioURL(id))
        }
        updateTimer()
    }

    // MARK: Playback

    func select(_ take: Recording) {
        stopPlayback()
        current = take
        time = 0
        updateReplay()
    }

    func togglePlay() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func play() {
        guard !isRecording, let take = current ?? takes.last else { return }
        if player == nil || current?.id != take.id {
            current = take
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, mode: .spokenAudio, options: [])
                try session.setActive(true)
                let p = try AVAudioPlayer(contentsOf: audioURL(take.id))
                p.enableRate = true
                p.delegate = self
                p.prepareToPlay()
                player = p
            } catch {
                message = Loc.t("Kayıt çalınamadı.")
                return
            }
        }
        guard let p = player else { return }
        if time >= take.duration - 0.05 { time = 0 }
        p.currentTime = time
        p.rate = rate
        p.play()
        isPlaying = true
        updateTimer()
        updateReplay()
    }

    func pause() {
        guard let p = player else { return }
        p.pause()
        time = p.currentTime
        isPlaying = false
        updateTimer()
        updateReplay()
    }

    func seek(to seconds: Double) {
        let duration = current?.duration ?? 0
        time = min(max(seconds, 0), duration)
        player?.currentTime = time
        updateReplay()
    }

    /// A tap on ink: plays its take from a little before it was written. False when the ink was not
    /// written during a take.
    @discardableResult
    func seek(birth: Double) -> Bool {
        guard !isRecording, let target = RecordingSync.seek(birth: birth, recordings: takes),
              let take = takes.first(where: { $0.id == target.id }) else { return false }
        if current?.id != take.id {
            select(take)
        }
        seek(to: target.time)
        if !isPlaying { play() }
        return true
    }

    func delete(_ take: Recording) {
        if current?.id == take.id {
            stopPlayback()
            current = nil
        }
        takes.removeAll { $0.id == take.id }
        try? FileManager.default.removeItem(at: audioURL(take.id))
        save()
        if current == nil { current = takes.last }
        updateReplay()
    }

    func stopPlayback() {
        player?.stop()
        player = nil
        isPlaying = false
        updateTimer()
        updateReplay()
    }

    /// The bar is closed: playback stops, all ink shows, taps on ink write again. A recording goes on.
    func closePlayback() {
        stopPlayback()
        time = 0
        editor?.setReplayHidden([])
        editor?.onInkTap = nil
        if !isRecording {
            // Music that a take paused may go on.
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        }
    }

    /// The bar is open: taps on ink seek.
    func openPlayback() {
        editor?.onInkTap = { [weak self] birth in self?.seek(birth: birth) }
    }

    /// The note is closing.
    func finish() {
        stopRecording()
        closePlayback()
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.isPlaying = false
            self.time = self.current?.duration ?? 0
            self.updateTimer()
            self.updateReplay()
        }
    }

    // MARK: Ticks

    /// 20 ticks a second while recording or playing (also during scrolling), none otherwise.
    private func updateTimer() {
        let needed = isRecording || isPlaying
        if needed, timer == nil {
            let t = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in self?.tick() }
            RunLoop.main.add(t, forMode: .common)
            timer = t
        } else if !needed {
            timer?.invalidate()
            timer = nil
        }
    }

    private func tick() {
        if let r = recorder {
            elapsed = r.currentTime
        }
        if let p = player, isPlaying {
            time = p.currentTime
            updateReplay()
        }
    }

    private func updateReplay() {
        guard let editor else { return }
        guard replayInk, !isRecording, let take = current, isPlaying || time > 0 else {
            editor.setReplayHidden([])
            return
        }
        editor.setReplayHidden(RecordingSync.hidden(births: editor.strokeBirths, recording: take, time: time))
    }
}
