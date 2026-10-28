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

    /// The games on screen, registered as they appear.
    weak var ebru: EbruModel?
    weak var pond: LivingInkModel?
    /// The open note's assistant, registered when its panel opens.
    weak var assistant: AssistantModel?
    private var player: DemoPlayer?

    func begin(store: LibraryStore, settings: AppSettings) {
        guard player == nil, let name = UserDefaults.standard.string(forKey: "DemoScene") else { return }
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
    /// What is typed into the assistant's box.
    var text: String?
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
        default:
            print("Mürekkep demo: unknown step \(step.op)")
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
        let paper = PaperStyle(rawValue: step.paper ?? "") ?? .lined
        let note = store.createNotebook(paper: paper)
        if let title = step.title { store.rename(note.id, to: title) }
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
                                  "screen": [Double(screen.bounds.width), Double(screen.bounds.height), Double(screen.scale)]]
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
#endif
