import AVFoundation
import SwiftUI
import UIKit

// MARK: - Audio timeline

enum OverviewAudio {
    /// Every spoken segment placed at its start time, with silence between them.
    static func composition(_ overview: Overview, folder: URL) async throws -> AVMutableComposition {
        let comp = AVMutableComposition()
        try await addNarration(overview, folder: folder, to: comp)
        return comp
    }

    /// Adds an audio track with the narration to `comp`.
    static func addNarration(_ overview: Overview, folder: URL, to comp: AVMutableComposition) async throws {
        guard let track = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw SpeechError.silent
        }
        let timeline = overview.timeline
        var placed = 0
        for (i, name) in overview.audioFiles.enumerated() where !name.isEmpty && timeline.starts.indices.contains(i) {
            let url = folder.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let asset = AVURLAsset(url: url)
            guard let source = try await asset.loadTracks(withMediaType: .audio).first else { continue }
            let duration = try await asset.load(.duration)
            let wanted = CMTime(seconds: timeline.starts[i], preferredTimescale: 600)
            let end = track.timeRange.end.isValid ? track.timeRange.end : .zero
            if CMTimeCompare(wanted, end) > 0 {
                track.insertEmptyTimeRange(CMTimeRange(start: end, end: wanted))
            }
            let at = CMTimeCompare(wanted, end) > 0 ? wanted : end
            try track.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: source, at: at)
            placed += 1
        }
        if placed == 0 { throw SpeechError.silent }
    }
}

// MARK: - Playback

/// The playhead, observed only by the scrubber and the slide canvas, so the rest of the player
/// screen is not rebuilt 20 times a second.
final class PlaybackClock: ObservableObject {
    @Published fileprivate(set) var time: Double = 0
}

final class OverviewPlayback: ObservableObject {
    let overview: Overview
    let folder: URL
    let timeline: OverviewTimeline
    let chapters: [OverviewChapter]
    let clock = PlaybackClock()

    @Published private(set) var ready = false
    @Published private(set) var failure: String?
    @Published private(set) var isPlaying = false
    /// Changes only when the playhead enters another segment.
    @Published private(set) var segment = 0
    private(set) var time: Double = 0 {
        didSet {
            clock.time = time
            let now = timeline.segment(at: time)
            if now != segment { segment = now }
        }
    }
    @Published private(set) var assets: SlideAssets?
    @Published var captions = true
    @Published var rate: Float = 1 {
        didSet { if isPlaying { player?.rate = rate } }
    }

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var ended = false

    init(overview: Overview, folder: URL) {
        self.overview = overview
        self.folder = folder
        timeline = overview.timeline
        chapters = overview.chapters
    }

    var total: Double { timeline.total }

    @MainActor
    func prepare(library: LibraryStore) async {
        guard player == nil, failure == nil else { return }
        guard overview.isVoiced else {
            failure = Loc.t("Bu özetin sesi yok. Menüden \"Yeniden seslendir\"i seç.")
            return
        }
        if overview.kind == .video {
            assets = await SlideAssets.load(for: overview, library: library, folder: folder)
        }
        do {
            let comp = try await OverviewAudio.composition(overview, folder: folder)
            let item = AVPlayerItem(asset: comp)
            // Faster playback keeps the voice's pitch.
            item.audioTimePitchAlgorithm = .timeDomain
            let p = AVPlayer(playerItem: item)
            timeObserver = p.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 20), queue: .main) { [weak self] t in
                self?.tick(t.seconds)
            }
            endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item,
                                                                 queue: .main) { [weak self] _ in
                self?.reachedEnd()
            }
            player = p
            ready = true
        } catch {
            failure = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func tick(_ seconds: Double) {
        guard seconds.isFinite, !ended else { return }
        time = min(max(seconds, 0), total)
    }

    private func reachedEnd() {
        ended = true
        isPlaying = false
        time = total
    }

    /// The precise time for drawing (smoother than the published one).
    func liveTime() -> Double {
        if ended { return total }
        guard let player, isPlaying else { return time }
        let s = player.currentTime().seconds
        return s.isFinite ? min(max(s, 0), total) : time
    }

    func play() {
        guard let player else { return }
        StudioAudioSession.activate()
        if ended || time >= total - 0.05 { seek(to: 0) }
        player.playImmediately(atRate: rate)
        isPlaying = true
    }

    func pause() {
        let now = liveTime()
        player?.pause()
        isPlaying = false
        if !ended { time = now }
    }

    func toggle() {
        isPlaying ? pause() : play()
    }

    func seek(to t: Double) {
        let target = min(max(t, 0), total)
        ended = false
        time = target
        player?.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func skip(_ seconds: Double) {
        seek(to: liveTime() + seconds)
    }

    func seek(segment: Int) {
        guard timeline.starts.indices.contains(segment) else { return }
        seek(to: overview.kind == .video ? timeline.sceneStart(segment) : max(0, timeline.starts[segment] - 0.1))
    }

    func nextChapter() {
        let now = timeline.segment(at: liveTime())
        if let next = chapters.first(where: { $0.segment > now }) {
            seek(segment: next.segment)
        }
    }

    func previousChapter() {
        let now = timeline.segment(at: liveTime())
        guard let current = chapters.lastIndex(where: { $0.segment <= now }) else { return seek(to: 0) }
        // Within the first seconds of a chapter, go to the one before.
        let start = timeline.starts.indices.contains(chapters[current].segment) ? timeline.starts[chapters[current].segment] : 0
        if liveTime() - start < 3, current > 0 {
            seek(segment: chapters[current - 1].segment)
        } else {
            seek(segment: chapters[current].segment)
        }
    }

    func stop() {
        player?.pause()
        isPlaying = false
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        timeObserver = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        player = nil
        StudioAudioSession.deactivate()
    }

    deinit {
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
    }
}

// MARK: - Slide canvas (video)

final class SlideCanvasView: UIView {
    var overview: Overview?
    var timeline: OverviewTimeline?
    var assets: SlideAssets?
    var captions = true
    var timeSource: (() -> Double)?
    var animating = false {
        didSet { if animating != oldValue { updateLink() } }
    }
    private var link: CADisplayLink?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = true
        backgroundColor = .black
        contentMode = .redraw
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    private func updateLink() {
        if animating && window != nil {
            guard link == nil else { return }
            let l = CADisplayLink(target: self, selector: #selector(step))
            l.preferredFrameRateRange = CAFrameRateRange(minimum: 24, maximum: 60, preferred: 30)
            l.add(to: .main, forMode: .common)
            link = l
        } else {
            link?.invalidate()
            link = nil
        }
    }

    @objc private func step() {
        setNeedsDisplay()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateLink()
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext(), let overview, let timeline else { return }
        SlideRenderer.drawFrame(overview, timeline: timeline, time: timeSource?() ?? 0, assets: assets,
                                captions: captions, size: bounds.size, in: ctx)
    }
}

struct SlideCanvas: UIViewRepresentable {
    @ObservedObject var playback: OverviewPlayback
    /// Observed so a seek while paused redraws the slide.
    @ObservedObject var clock: PlaybackClock

    func makeUIView(context: Context) -> SlideCanvasView {
        let view = SlideCanvasView()
        let p = playback
        view.timeSource = { [weak p] in p?.liveTime() ?? 0 }
        return view
    }

    func updateUIView(_ view: SlideCanvasView, context: Context) {
        view.overview = playback.overview
        view.timeline = playback.timeline
        view.assets = playback.assets
        view.captions = playback.captions
        view.animating = playback.isPlaying
        // While playing, the display link already redraws every frame.
        if !view.animating { view.setNeedsDisplay() }
    }
}

// MARK: - Audio stage

private struct AudioStage: View {
    @ObservedObject var playback: OverviewPlayback

    private let colors: [Color] = [Theme.aiStart, Theme.aiEnd]

    var body: some View {
        let overview = playback.overview
        let current = min(playback.segment, max(overview.lines.count - 1, 0))
        let speaking = overview.lines.indices.contains(current) ? overview.lines[current].host : 0
        VStack(spacing: 18) {
            HStack(spacing: 28) {
                ForEach(0..<2, id: \.self) { host in
                    hostBadge(host, name: overview.hosts.indices.contains(host) ? overview.hosts[host] : "?",
                              active: playback.isPlaying && speaking == host)
                }
            }
            .padding(.top, 8)
            waves(active: playback.isPlaying)
                .frame(height: 64)
                .padding(.horizontal, 30)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(overview.lines.indices, id: \.self) { i in
                            let line = overview.lines[i]
                            VStack(alignment: .leading, spacing: 6) {
                                if let chapter = line.chapter, !chapter.isEmpty {
                                    Text(chapter.uppercased())
                                        .font(.caption.weight(.heavy))
                                        .foregroundStyle(.white.opacity(0.55))
                                        .padding(.top, 10)
                                }
                                HStack(alignment: .top, spacing: 10) {
                                    Circle()
                                        .fill(colors[line.host % 2])
                                        .frame(width: 10, height: 10)
                                        .padding(.top, 7)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(overview.hosts.indices.contains(line.host) ? overview.hosts[line.host] : "")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(colors[line.host % 2])
                                        Text(line.text)
                                            .font(.body)
                                            .foregroundStyle(.white.opacity(i == current ? 1 : 0.55))
                                    }
                                }
                            }
                            .id(line.id)
                            .contentShape(Rectangle())
                            .onTapGesture { playback.seek(segment: i) }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                }
                .onChange(of: current) { _, value in
                    guard overview.lines.indices.contains(value) else { return }
                    withAnimation(.easeInOut(duration: 0.35)) {
                        proxy.scrollTo(overview.lines[value].id, anchor: .center)
                    }
                }
            }
        }
    }

    private func hostBadge(_ host: Int, name: String, active: Bool) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(colors[host].opacity(active ? 0.35 : 0.12))
                    .frame(width: 104, height: 104)
                    .scaleEffect(active ? 1.12 : 1)
                    .animation(active ? .easeInOut(duration: 0.6).repeatForever(autoreverses: true) : .default, value: active)
                Circle()
                    .fill(LinearGradient(colors: [colors[host], colors[(host + 1) % 2]], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 80, height: 80)
                Text(String(name.prefix(1)))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            Text(name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(active ? 1 : 0.7))
        }
    }

    private func waves(active: Bool) -> some View {
        TimelineView(.animation(paused: !active)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let bars = 48
                let w = size.width / CGFloat(bars)
                for i in 0..<bars {
                    let x: CGFloat = CGFloat(i) * w
                    let phase: Double = Double(i) * 0.45
                    let swing: Double = abs(sin(t * 3.1 + phase) * cos(t * 1.7 + phase * 0.5))
                    let amp: Double = active ? 0.35 + 0.65 * swing : 0.12
                    let h: CGFloat = max(4, size.height * CGFloat(amp))
                    let rect = CGRect(x: x + w * 0.2, y: (size.height - h) / 2, width: w * 0.6, height: h)
                    ctx.fill(Path(roundedRect: rect, cornerRadius: w * 0.3),
                             with: .color(i % 2 == 0 ? Theme.aiStart.opacity(0.9) : Theme.aiEnd.opacity(0.9)))
                }
            }
        }
    }
}

// MARK: - Scrubber

private struct Scrubber: View {
    @ObservedObject var clock: PlaybackClock
    let playback: OverviewPlayback
    let chapterTitle: String?

    var body: some View {
        let total = playback.total
        let time = clock.time
        let progress = CGFloat(total > 0 ? min(max(time / total, 0), 1) : 0)
        VStack(spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.15)).frame(height: 6)
                    Capsule().fill(Theme.ai)
                        .frame(width: geo.size.width * progress, height: 6)
                    ForEach(playback.chapters) { chapter in
                        if playback.timeline.starts.indices.contains(chapter.segment), total > 0 {
                            Capsule().fill(.white.opacity(0.5))
                                .frame(width: 2, height: 12)
                                .offset(x: geo.size.width * CGFloat(playback.timeline.starts[chapter.segment] / total))
                        }
                    }
                    Circle().fill(.white)
                        .frame(width: 16, height: 16)
                        .offset(x: geo.size.width * progress - 8)
                }
                .frame(height: 22)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    let f = min(max(value.location.x / max(geo.size.width, 1), 0), 1)
                    playback.seek(to: Double(f) * total)
                })
            }
            .frame(height: 22)
            HStack {
                Text(OverviewFormatting.duration(time))
                Spacer()
                if let chapterTitle {
                    Text(chapterTitle)
                        .lineLimit(1)
                }
                Spacer()
                Text("-" + OverviewFormatting.duration(max(0, total - time)))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.white.opacity(0.6))
        }
    }
}

// MARK: - Player screen

private struct ShareTarget: Identifiable {
    let id = UUID()
    let url: URL
}

struct OverviewPlayerView: View {
    @StateObject private var playback: OverviewPlayback
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var studio: StudioStore
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @State private var showChapters = false
    @State private var asking = false
    @State private var exporting: Double?
    @State private var exportTask: Task<Void, Never>?
    @State private var share: ShareTarget?
    @State private var message: String?

    init(overview: Overview, folder: URL) {
        _playback = StateObject(wrappedValue: OverviewPlayback(overview: overview, folder: folder))
    }

    private var overview: Overview { playback.overview }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.05, green: 0.06, blue: 0.12), Color(red: 0.09, green: 0.08, blue: 0.20)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(spacing: 14) {
                topBar
                stage
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                controls
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 14)
            if let exporting {
                exportOverlay(exporting)
            }
        }
        .preferredColorScheme(.dark)
        .task {
            await playback.prepare(library: library)
            if playback.ready { playback.play() }
        }
        .onDisappear {
            exportTask?.cancel()
            playback.stop()
        }
        .sheet(isPresented: $asking) {
            AskSheet(overview: overview, segment: playback.segment) {
                asking = false
                playback.play()
            }
            .environmentObject(settings)
        }
        .sheet(item: $share) { item in
            ActivityView(items: [item.url])
        }
        .alert(Loc.t("Mürekkep"), isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button(Loc.t("Tamam"), role: .cancel) { message = nil }
        } message: {
            Text(message ?? "")
        }
    }

    private var topBar: some View {
        HStack(spacing: 14) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .frame(width: 40, height: 40)
                    .background(.white.opacity(0.12), in: Circle())
            }
            .accessibilityLabel(Loc.t("Kapat"))
            VStack(alignment: .leading, spacing: 2) {
                Text(overview.title)
                    .font(.headline)
                    .lineLimit(1)
                Text("\(overview.kind.title) · \(OverviewFormatting.duration(playback.total)) · \(overview.engine)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
            Spacer()
            Menu {
                if overview.kind == .video {
                    Button {
                        exportVideo()
                    } label: {
                        Label(Loc.t("Videoyu kaydet (MP4)"), systemImage: "film")
                    }
                }
                Button {
                    exportAudio()
                } label: {
                    Label(Loc.t("Sesi kaydet (M4A)"), systemImage: "waveform")
                }
                Button {
                    shareScript()
                } label: {
                    Label(Loc.t("Metni paylaş"), systemImage: "doc.text")
                }
                Divider()
                Button {
                    playback.stop()
                    studio.revoice(overview, library: library)
                    dismiss()
                } label: {
                    Label(Loc.t("Yeniden seslendir (seçili seslerle)"), systemImage: "person.wave.2")
                }
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .frame(width: 40, height: 40)
                    .background(.white.opacity(0.12), in: Circle())
            }
            .disabled(!playback.ready)
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private var stage: some View {
        if let failure = playback.failure {
            ContentUnavailableView(Loc.t("Oynatılamadı"), systemImage: "exclamationmark.triangle", description: Text(failure))
        } else if !playback.ready {
            ProgressView(Loc.t("Hazırlanıyor…"))
                .tint(.white)
        } else if overview.kind == .video {
            SlideCanvas(playback: playback, clock: playback.clock)
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: .black.opacity(0.5), radius: 30, y: 14)
                .onTapGesture { playback.toggle() }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            AudioStage(playback: playback)
                .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            scrubber
            HStack(spacing: 22) {
                Menu {
                    ForEach([0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { r in
                        Button {
                            playback.rate = Float(r)
                        } label: {
                            if abs(Double(playback.rate) - r) < 0.01 {
                                Label(OverviewFormatting.rate(r), systemImage: "checkmark")
                            } else {
                                Text(OverviewFormatting.rate(r))
                            }
                        }
                    }
                } label: {
                    Text(OverviewFormatting.rate(Double(playback.rate)))
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .frame(width: 54, height: 36)
                        .background(.white.opacity(0.12), in: Capsule())
                }
                Spacer()
                controlButton("backward.end.fill", size: 20) { playback.previousChapter() }
                controlButton("gobackward.10", size: 22) { playback.skip(-10) }
                Button {
                    playback.toggle()
                } label: {
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 68, height: 68)
                        .background(.white, in: Circle())
                }
                .accessibilityLabel(playback.isPlaying ? Loc.t("Duraklat") : Loc.t("Oynat"))
                controlButton("goforward.10", size: 22) { playback.skip(10) }
                controlButton("forward.end.fill", size: 20) { playback.nextChapter() }
                Spacer()
                HStack(spacing: 10) {
                    if overview.kind == .video {
                        toggleButton("captions.bubble", on: playback.captions) { playback.captions.toggle() }
                    }
                    toggleButton("list.bullet", on: showChapters) { showChapters.toggle() }
                        .popover(isPresented: $showChapters) { chapterList }
                    Button {
                        playback.pause()
                        asking = true
                    } label: {
                        Label(Loc.t("Sor"), systemImage: "bubble.left.and.text.bubble.right")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14)
                            .frame(height: 36)
                            .background(Theme.ai, in: Capsule())
                    }
                }
            }
            .disabled(!playback.ready)
        }
        .foregroundStyle(.white)
    }

    private var scrubber: some View {
        Scrubber(clock: playback.clock, playback: playback, chapterTitle: currentChapterTitle)
    }

    private var currentChapterTitle: String? {
        let now = playback.segment
        return playback.chapters.last(where: { $0.segment <= now })?.title
    }

    private var chapterList: some View {
        NavigationStack {
            List {
                ForEach(playback.chapters) { chapter in
                    Button {
                        playback.seek(segment: chapter.segment)
                        showChapters = false
                    } label: {
                        HStack {
                            Text(chapter.title)
                                .foregroundStyle(.primary)
                            Spacer()
                            if playback.timeline.starts.indices.contains(chapter.segment) {
                                Text(OverviewFormatting.duration(playback.timeline.starts[chapter.segment]))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle(Loc.t("Bölümler"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .frame(minWidth: 340, minHeight: 420)
    }

    private func controlButton(_ symbol: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .frame(width: 44, height: 44)
        }
    }

    private func toggleButton(_ symbol: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 40, height: 36)
                .background(.white.opacity(on ? 0.28 : 0.12), in: Capsule())
        }
    }

    private func exportOverlay(_ value: Double) -> some View {
        VStack(spacing: 16) {
            ProgressView(value: value)
                .tint(.white)
                .frame(width: 280)
            Text(overview.kind == .video ? Loc.t("Video hazırlanıyor… %{0}", "\(Int(value * 100))") : Loc.t("Ses hazırlanıyor…"))
                .font(.headline)
            Button(Loc.t("Vazgeç"), role: .cancel) {
                exportTask?.cancel()
                exporting = nil
            }
            .buttonStyle(.bordered)
        }
        .padding(30)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    // MARK: Export

    private func exportVideo() {
        playback.pause()
        exporting = 0
        let o = overview
        let folder = playback.folder
        let assets = playback.assets
        exportTask = Task { @MainActor in
            do {
                let url = try await OverviewExporter.video(o, folder: folder, assets: assets) { value in
                    exporting = value
                }
                exporting = nil
                share = ShareTarget(url: url)
            } catch is CancellationError {
                exporting = nil
            } catch {
                exporting = nil
                message = Loc.t("Video kaydedilemedi: ") + ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
        }
    }

    private func exportAudio() {
        playback.pause()
        exporting = 0.5
        let o = overview
        let folder = playback.folder
        exportTask = Task { @MainActor in
            do {
                let url = try await OverviewExporter.audio(o, folder: folder)
                exporting = nil
                share = ShareTarget(url: url)
            } catch is CancellationError {
                exporting = nil
            } catch {
                exporting = nil
                message = Loc.t("Ses kaydedilemedi: ") + ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
        }
    }

    private func shareScript() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(OverviewFormatting.fileName(overview.title) + ".txt")
        do {
            try (overview.title + "\n\n" + overview.scriptText).write(to: url, atomically: true, encoding: .utf8)
            share = ShareTarget(url: url)
        } catch {
            message = error.localizedDescription
        }
    }
}

enum OverviewFormatting {
    static func rate(_ r: Double) -> String {
        String(format: "%g×", r)
    }

    static func duration(_ seconds: Double) -> String {
        let s = Int(max(0, seconds.isFinite ? seconds : 0).rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    static func fileName(_ title: String) -> String {
        let forbidden = CharacterSet(charactersIn: "<>:\"|?*\\/").union(.controlCharacters)
        let cleaned = title.components(separatedBy: forbidden).joined(separator: "-").trimmingCharacters(in: .whitespaces)
        return String((cleaned.isEmpty ? Loc.t("Mürekkep özeti") : cleaned).prefix(80))
    }
}

// MARK: - Questions in the middle

private struct AskSheet: View {
    let overview: Overview
    let segment: Int
    let onResume: () -> Void
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var speaker = LiveSpeaker()
    @State private var question = ""
    @State private var answer: String?
    @State private var thinking = false
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text(overview.language.isEnglish ? "Ask the hosts anything about this part." : "Bu kısımla ilgili sunuculara istediğini sor.")
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    TextField(overview.language.isEnglish ? "Your question" : "Sorun", text: $question, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .focused($focused)
                        .lineLimit(1...4)
                        .onSubmit(ask)
                    Button(action: ask) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 32))
                    }
                    .disabled(question.trimmingCharacters(in: .whitespaces).isEmpty || thinking)
                }
                if thinking {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(overview.language.isEnglish ? "Thinking…" : "Düşünüyor…")
                            .foregroundStyle(.secondary)
                    }
                }
                if let answer {
                    ScrollView {
                        HStack(alignment: .top, spacing: 12) {
                            Circle()
                                .fill(Theme.ai)
                                .frame(width: 36, height: 36)
                                .overlay(Text(String((overview.hosts.first ?? "M").prefix(1))).font(.headline).foregroundStyle(.white))
                            Text(answer)
                                .font(.body)
                                .textSelection(.enabled)
                        }
                    }
                    HStack {
                        Button {
                            speaker.isSpeaking ? speaker.stop() : speaker.speak(answer, language: overview.language, host: 0)
                        } label: {
                            Label(speaker.isSpeaking ? Loc.t("Sustur") : Loc.t("Tekrar dinle"), systemImage: speaker.isSpeaking ? "speaker.slash" : "speaker.wave.2")
                        }
                        .buttonStyle(.bordered)
                        Spacer()
                    }
                }
                Spacer()
                Button {
                    speaker.stop()
                    onResume()
                } label: {
                    Label(overview.language.isEnglish ? "Continue" : "Kaldığı yerden devam et", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(24)
            .navigationTitle(overview.language.isEnglish ? "Ask" : "Soru sor")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { focused = true }
            .onDisappear { speaker.stop() }
        }
        .presentationDetents([.medium, .large])
    }

    private func ask() {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !thinking else { return }
        thinking = true
        answer = nil
        Task { @MainActor in
            let reply = await OverviewQuestions.answer(q, overview: overview, segment: segment, settings: settings)
            thinking = false
            answer = reply
            speaker.speak(reply, language: overview.language, host: 0)
        }
    }
}

enum OverviewQuestions {
    @MainActor
    static func answer(_ question: String, overview: Overview, segment: Int, settings: AppSettings) async -> String {
        let prompt = StudioPrompts.question(question, overview: overview, position: segment)
        let directive = StudioWriter.directive(overview.language)
        if let key = settings.apiKey, settings.engine == .claude || overview.engine.hasPrefix("Claude") || !OnDeviceAI.isAvailable {
            let request = ClaudeRequest(model: settings.model.rawValue, effort: "low", maxTokens: 2000,
                                        system: ClaudeRequest.tutorSystemPrompt + "\n" + directive,
                                        context: .text(String(overview.scriptText.prefix(200_000)), title: overview.title),
                                        contextNote: "Bu, kullanıcının dinlediği özetin metni.",
                                        turns: [ClaudeTurn(role: .user, text: prompt, imageJPEG: nil)])
            do {
                let text = try await ClaudeClient.collect(request, apiKey: key)
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return text }
            } catch {
                return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
        if OnDeviceAI.isAvailable {
            do {
                return try await OnDeviceAI.respond(instructions: "Sen bir ders asistanısın. Kısa ve net cevap ver. " + directive,
                                                    prompt: prompt, useWeb: settings.webSearch, collector: SourceCollector())
            } catch {
                if let friendly = OnDeviceAI.friendly(error) { return friendly }
            }
        }
        // Without a model: the closest sentences of the script.
        let words = Set(question.lowercased().split { !$0.isLetter }.map(String.init).filter { $0.count > 3 })
        let sentences = overview.segmentTexts.joined(separator: " ").components(separatedBy: ". ")
        let best = sentences.max { a, b in
            let wa = Set(a.lowercased().split { !$0.isLetter }.map(String.init))
            let wb = Set(b.lowercased().split { !$0.isLetter }.map(String.init))
            return wa.intersection(words).count < wb.intersection(words).count
        }
        if let best, !best.isEmpty {
            return (overview.language.isEnglish ? "Here's what the overview says: " : "Özette bununla ilgili şöyle geçiyor: ") + best + "."
        }
        if ProPlan.sells {  // The App Store edition has no Claude.
            return overview.language.isEnglish ? "The overview doesn't cover that. Ask the assistant on the page." : "Özette buna dair bir şey yok. Sayfadaki asistana sorabilirsin."
        }
        return overview.language.isEnglish ? "I need Claude or Apple Intelligence to answer that." : "Bunu yanıtlamak için Claude ya da Apple Intelligence gerekir."
    }
}

// MARK: - Thumbnails

enum OverviewThumbnail {
    static func make(for overview: Overview, folder: URL, library: LibraryStore) async {
        let url = folder.appendingPathComponent("thumb.jpg")
        let o = overview
        // The title slide's illustration, when one was drawn.
        var loaded: SlideAssets?
        if o.kind == .video {
            loaded = await SlideAssets.load(for: o, library: library, folder: folder)
        }
        let assets = loaded
        await Task.detached(priority: .utility) {
            let size = CGSize(width: 960, height: 540)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = true
            let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
                if o.kind == .video {
                    SlideRenderer.poster(o, size: size, assets: assets, in: ctx.cgContext)
                } else {
                    OverviewThumbnail.drawAudioCover(o, size: size, in: ctx.cgContext)
                }
            }
            if let data = image.jpegData(compressionQuality: 0.82) {
                try? data.write(to: url, options: .atomic)
            }
        }.value
    }

    static func drawAudioCover(_ o: Overview, size: CGSize, in ctx: CGContext) {
        let space = CGColorSpaceCreateDeviceRGB()
        let a = UIColor(red: 0.45, green: 0.30, blue: 0.96, alpha: 1)
        let b = UIColor(red: 0.07, green: 0.64, blue: 0.84, alpha: 1)
        if let g = CGGradient(colorsSpace: space, colors: [a.cgColor, b.cgColor] as CFArray, locations: [0, 1]) {
            ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
        }
        let bars = 36
        let w = size.width * 0.8 / CGFloat(bars)
        ctx.setFillColor(UIColor(white: 1, alpha: 0.85).cgColor)
        for i in 0..<bars {
            let swing: Double = abs(sin(Double(i) * 0.7) * cos(Double(i) * 0.31))
            let h: CGFloat = size.height * 0.08 + size.height * 0.28 * CGFloat(swing)
            let x: CGFloat = size.width * 0.1 + CGFloat(i) * w + w * 0.2
            let rect = CGRect(x: x, y: size.height * 0.36 - h / 2, width: w * 0.6, height: h)
            ctx.addPath(UIBezierPath(roundedRect: rect, cornerRadius: w * 0.3).cgPath)
        }
        ctx.fillPath()
        SlideRenderer.text(o.title, in: CGRect(x: 60, y: size.height * 0.6, width: size.width - 120, height: 130),
                           font: SlideRenderer.font(48, .bold, .modern), color: .white, align: .center, ctx: ctx)
        SlideRenderer.text(o.hosts.joined(separator: " & "), in: CGRect(x: 60, y: size.height * 0.84, width: size.width - 120, height: 40),
                           font: SlideRenderer.font(26, .semibold, .modern), color: UIColor(white: 1, alpha: 0.8), align: .center, ctx: ctx)
    }
}
