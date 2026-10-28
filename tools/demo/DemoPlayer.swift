#if DEMO
import SwiftUI
import UIKit

/// The ad recordings (tools/demo). Only the recording build has this file and the DEMO flag; the
/// App Store edition never does. The simulator launches the app with `-DemoScene <name>`, and the
/// scene's steps (DemoScene-<name>.json, written by tools/demo/make_scenes.py) open a notebook,
/// pick pens, write strokes at the times a hand writes them, play the break corner's Ebru and
/// living ink, ask the assistant what a student would tap, and turn a page into text. The pen goes
/// through the canvas's own stroke path and the assistant answers on its own, so the recording
/// shows what the app itself draws and says.
@MainActor
final class DemoStage {
    static let shared = DemoStage()
    static let openNote = Notification.Name("DemoStage.openNote")
    static let games = Notification.Name("DemoStage.games")
    static let pickLayer = Notification.Name("DemoStage.pickLayer")
    static let pickGame = Notification.Name("DemoStage.pickGame")
    static let assistantPanel = Notification.Name("DemoStage.assistantPanel")
    static let library = Notification.Name("DemoStage.library")
    static let search = Notification.Name("DemoStage.search")
    static let openHit = Notification.Name("DemoStage.openHit")
    static let gameLevel = Notification.Name("DemoStage.gameLevel")
    static let dotsMove = Notification.Name("DemoStage.dotsMove")
    static let xoxMove = Notification.Name("DemoStage.xoxMove")
    static let sudokuNew = Notification.Name("DemoStage.sudokuNew")
    /// The check of scrolling (scene scroll3dold): build 235's display loop, which kept a page with
    /// moving ink at the ink's 30 fps while it scrolled.
    static var oldScrollLoop: Bool { UserDefaults.standard.bool(forKey: "DemoOldScrollLoop") }
    /// The check of dense pages (scene scrolldenseold): build 235's page meshes, made on the main
    /// thread as a page came near the screen, and shadow passes over every stroke. Read by the
    /// renderer, which is not tied to the main actor.
    nonisolated static var oldInkMesh: Bool { UserDefaults.standard.bool(forKey: "DemoOldInkMesh") }

    /// The games on screen, registered as they appear.
    weak var ebru: EbruModel?
    weak var pond: LivingInkModel?
    /// The open note's assistant, registered when its panel opens.
    weak var assistant: AssistantModel?
    weak var settings: AppSettings?
    /// True while the scene's pencil rests at the ends of its strokes (CanvasView's hold, without a touch).
    var holds = false
    private var player: DemoPlayer?

    func begin(store: LibraryStore, settings: AppSettings) {
        guard player == nil, let name = UserDefaults.standard.string(forKey: "DemoScene") else { return }
        self.settings = settings
        let player = DemoPlayer(name: name, store: store)
        self.player = player
        Task { await player.run() }
    }
}

/// How much slower than real time the break corner's games run in a recording: the scene's "clock".
/// The simulator's recorder keeps only some frames a second, so the pond and the tray move slower
/// and the edit speeds them up as much. 1 in every other scene.
enum DemoClock {
    static var rate: Double = 1
}

/// One step of a scene. Every field but `op` is optional; each step reads the ones it needs.
private struct DemoStep: Decodable {
    let op: String
    var title: String?
    var paper: String?
    var brush: String?
    var color: [Float]?
    var width: Float?
    var seconds: Double?
    var page: Int?
    /// Strokes of samples [seconds from the step's start, x, y, force]. On the page in page points;
    /// in Ebru and the pond in parts of the board's shorter side, from its centre.
    var strokes: [[[Double]]]?
    var open: Bool?
    var expanded: Bool?
    var name: String?
    var index: Int?
    /// What is typed into the assistant's box or the library's search.
    var text: String?
    /// The page's angle (Settings' page turn), in degrees.
    var degrees: Double?
    /// A photo as base64 JPEG, imported the way the Photos picker hands one over.
    var image: String?
    /// The pencil rests at the end of each stroke before it lifts.
    var hold: Bool?
    /// How far a scroll moves the page down (points; negative goes up).
    var by: Double?
    /// How many scribbled strokes a fill puts on the page.
    var count: Int?
    /// How much slower than a hand the strokes are played (the edit speeds them up as much); the
    /// samples' own timestamps stay a hand's.
    var pace: Double?
}

private struct DemoScene: Decodable {
    let steps: [DemoStep]
    var clock: Double?
}

@MainActor
private final class DemoPlayer {
    private let name: String
    private let store: LibraryStore
    /// Where the pen was, for the edit's zoom: [wall-clock seconds, window x, window y, 1 while down].
    private var track: [[Double]] = []
    /// The notebooks the scene opened, in order.
    private var opened: [UUID] = []
    /// What each scroll of the scene measured: frames a second, and the CPU and GPU time of a frame.
    private var frameReports: [[String: Double]] = []

    init(name: String, store: LibraryStore) {
        self.name = name
        self.store = store
    }

    func run() async {
        guard let url = Bundle.main.url(forResource: "DemoScene-" + name, withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            finish(error: "no scene file for \(name)")
            return
        }
        let scene: DemoScene
        do {
            scene = try JSONDecoder().decode(DemoScene.self, from: data)
        } catch {
            finish(error: "scene \(name): \(error)")
            return
        }
        DemoClock.rate = max(scene.clock ?? 1, 0.1)
        for step in scene.steps {
            await perform(step)
        }
        finish(error: nil)
    }

    private func perform(_ step: DemoStep) async {
        let stage = DemoStage.shared
        switch step.op {
        case "note":
            await openNote(step)
        case "pen":
            pickPen(step, textPen: false)
        case "textpen":
            pickPen(step, textPen: true)
        case "write":
            await write(step)
        case "wait":
            await pause(step.seconds ?? 1)
        case "games":
            NotificationCenter.default.post(name: DemoStage.games, object: nil,
                                            userInfo: ["open": step.open ?? true, "expanded": step.expanded ?? false])
        case "layer":
            NotificationCenter.default.post(name: DemoStage.pickLayer, object: step.name)
        case "game":
            NotificationCenter.default.post(name: DemoStage.pickGame, object: step.name)
        case "ebru.tool":
            if let tool = EbruTool(rawValue: step.name ?? "") { stage.ebru?.tool = tool }
        case "ebru.pigment":
            stage.ebru?.pigment = step.index ?? 0
        case "ebru.touch":
            await touchEbru(step)
        case "ebru.sprinkle":
            stage.ebru?.sprinkle(instantly: false)
        case "ebru.pattern":
            if let pattern = EbruPattern(rawValue: step.name ?? "") { stage.ebru?.play(pattern, instantly: false) }
        case "pond.ink":
            stage.pond?.ink = step.index ?? 0
        case "pond.touch":
            await touchPond(step)
        case "pond.feed":
            stage.pond?.feed()
        case "assistant":
            NotificationCenter.default.post(name: DemoStage.assistantPanel, object: step.open ?? true)
        case "assistant.ask":
            if let action = QuickAction(rawValue: step.name ?? "") { stage.assistant?.run(action) }
        case "assistant.type":
            await typeQuestion(step.text ?? "", seconds: step.seconds ?? 1.5)
        case "assistant.wait":
            await waitForAnswer(then: step.seconds ?? 1)
        case "convert":
            await canvas?.model.convertHandwriting(page: step.page ?? 0)
        case "suggest.pick":
            // A tap on one of the pictures the menu around a held drawing offers.
            if let editor = canvas?.model, let suggestion = editor.suggestion, !suggestion.stickers.isEmpty {
                let stickers = suggestion.stickers
                editor.applySuggestion(sticker: stickers[min(max(step.index ?? 0, 0), stickers.count - 1)])
            }
        case "angle":
            stage.settings?.pageAngle = step.degrees ?? 0
        case "photos":
            await importPhoto(step)
        case "library":
            NotificationCenter.default.post(name: DemoStage.library, object: nil)
        case "ink.read":
            await waitForInkText(limit: step.seconds ?? 90)
        case "search":
            await typeSearch(step.text ?? "", seconds: step.seconds ?? 1.5)
        case "open.hit":
            NotificationCenter.default.post(name: DemoStage.openHit, object: nil)
        case "game.level":
            NotificationCenter.default.post(name: DemoStage.gameLevel, object: step.name)
        case "dots.move":
            NotificationCenter.default.post(name: DemoStage.dotsMove, object: nil)
        case "xox.move":
            NotificationCenter.default.post(name: DemoStage.xoxMove, object: nil)
        case "sudoku.new":
            NotificationCenter.default.post(name: DemoStage.sudokuNew, object: nil)
        case "scroll":
            let seconds = step.seconds ?? 2
            DemoFrames.shared.begin()
            canvas?.demoScroll(by: CGFloat(step.by ?? 300), over: seconds)
            await pause(seconds)
            frameReports.append(DemoFrames.shared.end())
        case "fill":
            fillPage(step)
        default:
            print("Mürekkep demo: unknown step \(step.op)")
        }
    }

    // MARK: Dense pages

    /// Covers a page with rows of scribbled strokes in one go, like a page of quick notes: the scroll
    /// checks need full pages, and writing them at a hand's pace would take minutes.
    private func fillPage(_ step: DemoStep) {
        guard let editor = canvas?.model,
              let brush = Brush.allCases.first(where: { "\($0)" == step.brush }) else { return }
        let page = step.page ?? 0
        for _ in 0..<max(0, page + 1 - editor.pages.count) {
            editor.addPage()
        }
        guard editor.pages.indices.contains(page), editor.layout.pageSizes.indices.contains(page) else { return }
        let c = step.color ?? [0.12, 0.13, 0.18]
        let color = InkColor(c[0], c[1], c[2], c.count > 3 ? c[3] : 1)
        let radius = (step.width ?? brush.defaultWidth) / 2
        let spacing = max(0.6, radius * 0.4)
        let cell = max(10, radius * 7)
        let size = editor.layout.pageSizes[page]
        let columns = max(1, Int((Float(size.width) - 100) / cell))
        let rows = max(1, Int((Float(size.height) - 160) / (cell * 1.5)))
        var seed = UInt64(truncatingIfNeeded: (step.index ?? 1) * 7919 + page * 104_729)
        func random() -> Float {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Float(seed >> 40) / Float(1 << 24)
        }
        let birth = Date().timeIntervalSinceReferenceDate
        var strokes: [Stroke] = []
        for k in 0..<min(step.count ?? 600, columns * rows) {
            let x0 = 50 + Float(k % columns) * cell
            let y0 = 100 + Float(k / columns) * cell * 1.5
            var p = SIMD2<Float>(x0 + random() * cell * 0.3, y0 + random() * cell)
            var angle = random() * 6.283
            var points: [InkPoint] = []
            for _ in 0..<Int(cell * 2.2 / spacing) {
                angle += (random() - 0.5) * 0.9
                p += SIMD2<Float>(cos(angle), sin(angle)) * spacing
                p = SIMD2<Float>(min(max(p.x, x0), x0 + cell), min(max(p.y, y0), y0 + cell))
                points.append(InkPoint(x: p.x, y: p.y, r: radius * (0.85 + 0.3 * random()), ink: random()))
            }
            strokes.append(Stroke(brush: brush, color: color, width: radius * 2, birth: birth, seed: random(), points: points))
        }
        editor.addStrokes(strokes, toPage: page)
    }

    // MARK: The library

    /// A photographed page, the way the Photos picker hands one over: the app's own import makes it a
    /// PDF (PhotoPDF), and it opens like any note.
    private func importPhoto(_ step: DemoStep) async {
        guard let data = Data(base64Encoded: step.image ?? ""),
              let note = try? await store.importPhotos([data], title: step.title ?? "Photo") else {
            print("Mürekkep demo: the photo did not import")
            return
        }
        NotificationCenter.default.post(name: DemoStage.openNote, object: note.id)
        for _ in 0..<80 where canvas == nil {
            await pause(0.1)
        }
        await pause(step.seconds ?? 1)
    }

    /// Waits until the app has read the handwriting of every notebook the scene wrote (InkTextCache,
    /// filled off the main thread once a note closes), so the search sees what is on their pages.
    private func waitForInkText(limit: Double) async {
        let start = Date()
        while Date().timeIntervalSince(start) < limit,
              opened.contains(where: { InkTextCache.pages(note: $0).isEmpty }) {
            await pause(0.25)
        }
    }

    /// Types into the library's search field, a letter at a time.
    private func typeSearch(_ text: String, seconds: Double) async {
        guard !text.isEmpty else { return }
        let each = max(seconds, 0.1) / Double(text.count)
        var typed = ""
        for character in text {
            typed.append(character)
            NotificationCenter.default.post(name: DemoStage.search, object: typed)
            await pause(each)
        }
    }

    // MARK: The assistant

    /// Types a question into the assistant's box the way a person does, then sends it.
    private func typeQuestion(_ text: String, seconds: Double) async {
        guard let assistant = DemoStage.shared.assistant, !text.isEmpty else { return }
        assistant.draft = ""
        let each = max(seconds, 0.1) / Double(text.count)
        for character in text {
            assistant.draft.append(character)
            await pause(each)
        }
        await pause(0.35)
        assistant.send()
    }

    /// Waits while the assistant reads the page and answers (at the app's own speed), then a while more.
    private func waitForAnswer(then seconds: Double) async {
        await pause(0.3)
        for _ in 0..<1200 where DemoStage.shared.assistant?.isBusy == true {
            await pause(0.1)
        }
        await pause(seconds)
    }

    // MARK: The notebook

    private func openNote(_ step: DemoStep) async {
        // A note already open: back to the library first, as a hand does. Swapping the path's note
        // would keep the open editor (and its note); going back closes it, and its ink is read.
        if canvas != nil {
            NotificationCenter.default.post(name: DemoStage.library, object: nil)
            for _ in 0..<50 where canvas != nil {
                await pause(0.1)
            }
            await pause(0.6)
        }
        let paper = PaperStyle(rawValue: step.paper ?? "") ?? .lined
        let note = store.createNotebook(paper: paper)
        if let title = step.title { store.rename(note.id, to: title) }
        opened.append(note.id)
        NotificationCenter.default.post(name: DemoStage.openNote, object: note.id)
        // The editor builds its canvas after the push.
        for _ in 0..<80 where canvas == nil {
            await pause(0.1)
        }
        await pause(step.seconds ?? 0.8)
    }

    private func pickPen(_ step: DemoStep, textPen: Bool) {
        guard let editor = canvas?.model,
              let brush = Brush.allCases.first(where: { "\($0)" == step.brush }) else { return }
        if let c = step.color, c.count >= 3 {
            editor.setColor(InkColor(c[0], c[1], c[2], c.count > 3 ? c[3] : 1), for: brush)
        }
        if let width = step.width { editor.setWidth(width, for: brush) }
        editor.tool = .brush(brush)
        if textPen { editor.tool = .textPen }
    }

    private func write(_ step: DemoStep) async {
        guard let canvas, let strokes = step.strokes else { return }
        let page = step.page ?? 0
        let pace = max(step.pace ?? 1, 0.1)
        DemoStage.shared.holds = step.hold ?? false
        await play(strokes) { [weak self] phase, samples, start in
            let inputs = samples.map { s -> InputSample in
                var input = InputSample(location: CGPoint(x: s.x, y: s.y), force: CGFloat(s.force), timestamp: start + s.t / pace)
                input.isPencil = true
                input.altitude = 0.95
                input.azimuth = 0.8
                return input
            }
            switch phase {
            case .down:
                if let first = inputs.first { canvas.demoPenDown(page: page, first) }
            case .moved:
                canvas.demoPenMoved(inputs)
            case .up:
                canvas.demoPenUp(inputs)
            }
            if let last = samples.last {
                let p = canvas.demoWindowPoint(page: page, CGPoint(x: last.x, y: last.y))
                self?.track.append([Date().timeIntervalSince1970, Double(p.x), Double(p.y), phase == .up ? 0 : 1])
            }
        }
    }

    // MARK: The break corner

    private func touchEbru(_ step: DemoStep) async {
        for _ in 0..<60 where DemoStage.shared.ebru?.tray == nil {
            await pause(0.1)
        }
        guard let model = DemoStage.shared.ebru, let size = model.tray?.size, let strokes = step.strokes else { return }
        await play(strokes) { phase, samples, _ in
            let points = samples.map { Self.board($0, size) }
            switch phase {
            case .down:
                if let first = points.first { model.began(at: first) }
            case .moved:
                points.forEach { model.moved(to: $0) }
            case .up:
                points.forEach { model.moved(to: $0) }
                model.ended()
            }
        }
    }

    private func touchPond(_ step: DemoStep) async {
        for _ in 0..<60 where DemoStage.shared.pond?.pond == nil {
            await pause(0.1)
        }
        guard let model = DemoStage.shared.pond, let size = model.pond?.size, let strokes = step.strokes else { return }
        await play(strokes) { phase, samples, _ in
            let points = samples.map { Self.board($0, size) }
            switch phase {
            case .down:
                if let first = points.first { model.began(at: first) }
            case .moved:
                points.forEach { model.moved(to: $0) }
            case .up:
                points.forEach { model.moved(to: $0) }
                model.ended()
            }
        }
    }

    /// A scene point (parts of the shorter side, from the centre) on a board of `size`, kept on it.
    private static func board(_ s: DemoPen.Sample, _ size: CGSize) -> CGPoint {
        let side = Double(min(size.width, size.height))
        let x = Double(size.width) / 2 + (s.x - 0.5) * side
        let y = Double(size.height) / 2 + (s.y - 0.5) * side
        return CGPoint(x: min(max(x, 0), Double(size.width)), y: min(max(y, 0), Double(size.height)))
    }

    // MARK: Running

    private func play(_ strokes: [[[Double]]], _ handle: @escaping (DemoPen.Phase, [DemoPen.Sample], CFTimeInterval) -> Void) async {
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            DemoPen(strokes: strokes, handle: handle) { done.resume() }.run()
        }
    }

    private func pause(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
    }

    private var canvas: CanvasView? {
        for scene in UIApplication.shared.connectedScenes {
            guard let windows = (scene as? UIWindowScene)?.windows else { continue }
            for window in windows {
                if let found = Self.find(in: window) { return found }
            }
        }
        return nil
    }

    private static func find(in view: UIView) -> CanvasView? {
        if let canvas = view as? CanvasView { return canvas }
        for sub in view.subviews {
            if let canvas = find(in: sub) { return canvas }
        }
        return nil
    }

    /// Tells the recording script the scene is over, with the pen's track for the edit.
    private func finish(error: String?) {
        if let error { print("Mürekkep demo: \(error)") }
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let screen = UIScreen.main
        let out: [String: Any] = ["scene": name, "error": error ?? "", "track": track,
                                  "screen": [Double(screen.bounds.width), Double(screen.bounds.height), Double(screen.scale)],
                                  "frames": frameReports]
        if let data = try? JSONSerialization.data(withJSONObject: out) {
            try? data.write(to: folder.appendingPathComponent("demo-done-\(name).json"))
        }
    }
}

/// Plays strokes in step with the screen: every frame hands on the samples whose time has come, the
/// way a pencil's coalesced touches arrive.
@MainActor
private final class DemoPen: NSObject {
    enum Phase { case down, moved, up }
    typealias Sample = (t: Double, x: Double, y: Double, force: Double)

    private let strokes: [[Sample]]
    private let handle: (Phase, [Sample], CFTimeInterval) -> Void
    private let finished: () -> Void
    private var link: CADisplayLink?
    /// CACurrentMediaTime when the first frame came; sample times count from it.
    private var origin: CFTimeInterval = 0
    private var stroke = 0
    private var next = 0
    private var down = false

    init(strokes: [[[Double]]], handle: @escaping (Phase, [Sample], CFTimeInterval) -> Void, finished: @escaping () -> Void) {
        var kept: [[Sample]] = []
        for raw in strokes {
            var samples: [Sample] = []
            for v in raw where v.count >= 3 {
                samples.append((t: v[0], x: v[1], y: v[2], force: v.count > 3 ? v[3] : 1))
            }
            if !samples.isEmpty { kept.append(samples) }
        }
        self.strokes = kept
        self.handle = handle
        self.finished = finished
    }

    func run() {
        guard !strokes.isEmpty else {
            finished()
            return
        }
        origin = CACurrentMediaTime()
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func tick() {
        let now = CACurrentMediaTime() - origin
        while stroke < strokes.count {
            let samples = strokes[stroke]
            var batch: [Sample] = []
            while next < samples.count, samples[next].t <= now {
                batch.append(samples[next])
                next += 1
            }
            if batch.isEmpty { break }
            if !down {
                handle(.down, [batch.removeFirst()], origin)
                down = true
            }
            if next >= samples.count {
                handle(.up, batch, origin)
                down = false
                stroke += 1
                next = 0
                continue
            }
            if !batch.isEmpty { handle(.moved, batch, origin) }
            break
        }
        if stroke >= strokes.count {
            link?.invalidate()
            link = nil
            finished()
        }
    }
}
/// Frames drawn while a scene's scroll runs, with each frame's CPU time (the canvas's drawFrame, main
/// thread) and GPU time (its command buffer). The GPU times come in on Metal's own thread.
final class DemoFrames: @unchecked Sendable {
    static let shared = DemoFrames()
    private let lock = NSLock()
    private var counting = false
    private var start: CFTimeInterval = 0
    private var cpu: [Double] = []
    private var gpu: [Double] = []

    func begin() {
        lock.lock()
        counting = true
        start = CACurrentMediaTime()
        cpu = []
        gpu = []
        lock.unlock()
    }

    func frame(cpu ms: Double) {
        lock.lock()
        if counting { cpu.append(ms) }
        lock.unlock()
    }

    func gpu(_ ms: Double) {
        lock.lock()
        if counting { gpu.append(ms) }
        lock.unlock()
    }

    /// Frames a second, and the mean, 95th percentile and worst of each time (ms).
    func end() -> [String: Double] {
        lock.lock()
        defer { lock.unlock() }
        counting = false
        let seconds = max(CACurrentMediaTime() - start, 0.001)
        func stats(_ values: [Double], _ key: String) -> [String: Double] {
            guard !values.isEmpty else { return [:] }
            let sorted = values.sorted()
            let p95 = sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]
            return [key + "Mean": values.reduce(0, +) / Double(values.count), key + "P95": p95, key + "Max": sorted.last ?? 0]
        }
        var out: [String: Double] = ["seconds": seconds, "frames": Double(cpu.count), "fps": Double(cpu.count) / seconds]
        out.merge(stats(cpu, "cpu")) { a, _ in a }
        out.merge(stats(gpu, "gpu")) { a, _ in a }
        return out
    }
}

/// Runs `tick` on every screen frame until it returns false.
final class DemoTicker: NSObject {
    private let tick: () -> Bool
    private var link: CADisplayLink?

    init(_ tick: @escaping () -> Bool) {
        self.tick = tick
    }

    func start() {
        let link = CADisplayLink(target: self, selector: #selector(step))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func step() {
        if !tick() {
            link?.invalidate()
            link = nil
        }
    }
}
#endif
