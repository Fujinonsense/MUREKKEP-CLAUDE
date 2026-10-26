import SwiftUI
import UIKit

/// Uçan damla: the level map, then a level in flight.
struct FlyerGame: View {
    @ObservedObject var store: GameProgressStore
    @State private var level: Int?

    var body: some View {
        if let level {
            FlyerPlay(level: level, difficulty: store[.flyer].difficulty, store: store) {
                self.level = nil
            } onNext: {
                self.level = min(FlyerWorld.levels, level + 1)
            }
            .id(level)
        } else {
            LevelMap(game: .flyer, store: store) { level = $0 }
        }
    }
}

/// The world on screen: stepped from the animation timeline; the published numbers change only
/// when the ones on screen do.
final class FlyerModel: ObservableObject {
    @Published private(set) var phase: FlyerWorld.Phase = .ready
    @Published private(set) var passed = 0
    @Published private(set) var lives = FlyerWorld.lives
    private(set) var world: FlyerWorld?
    private var last: Date?

    /// Builds the level for the first size the field has; the drawing scales to later sizes.
    func start(size: CGSize, level: Int, difficulty: GameDifficulty) {
        guard world == nil, size.width > 0, size.height > 0 else { return }
        world = FlyerWorld(size: size, level: level, difficulty: difficulty, seed: Self.seed())
        sync()
    }

    func restart(level: Int, difficulty: GameDifficulty) {
        guard let size = world?.size else { return }
        world = FlyerWorld(size: size, level: level, difficulty: difficulty, seed: Self.seed())
        last = nil
        sync()
    }

    func flap() {
        world?.flap()
        sync()
    }

    func pause() {
        last = nil
    }

    func advance(to now: Date) {
        guard var flying = world, flying.phase == .flying else { return }
        let dt = last.map { now.timeIntervalSince($0) } ?? 0
        last = now
        flying.advance(by: dt)
        world = flying
        sync()
    }

    private func sync() {
        guard let w = world else { return }
        if w.phase != phase { phase = w.phase }
        if w.passed != passed { passed = w.passed }
        if w.lives != lives { lives = w.lives }
    }

    private static func seed() -> UInt64 {
        UInt64(max(0, Date().timeIntervalSinceReferenceDate * 1000))
    }
}

/// Space and ↑ on a connected keyboard flap while the level is on screen: a tiny controller that
/// takes those keys as first responder when it appears and lets them go when it leaves, so the
/// notebook's text and shortcuts keep their keys whenever the flyer is not showing.
private struct FlapKeys: UIViewControllerRepresentable {
    let onFlap: () -> Void

    func makeUIViewController(context: Context) -> FlapKeyController {
        let controller = FlapKeyController()
        controller.onFlap = onFlap
        return controller
    }

    func updateUIViewController(_ controller: FlapKeyController, context: Context) {
        controller.onFlap = onFlap
    }
}

final class FlapKeyController: UIViewController {
    var onFlap: () -> Void = {}

    override var canBecomeFirstResponder: Bool { true }

    override var keyCommands: [UIKeyCommand]? {
        let commands = [UIKeyCommand(input: " ", modifierFlags: [], action: #selector(flap)),
                        UIKeyCommand(input: UIKeyCommand.inputUpArrow, modifierFlags: [], action: #selector(flap))]
        for command in commands {
            command.wantsPriorityOverSystemBehavior = true
        }
        return commands
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        _ = becomeFirstResponder()
    }

    override func viewWillDisappear(_ animated: Bool) {
        _ = resignFirstResponder()
        super.viewWillDisappear(animated)
    }

    @objc private func flap() {
        onFlap()
    }
}

/// One level: tap, touch with the pencil or press Space to lift the drop; pass the pencils and
/// rulers to the flag.
private struct FlyerPlay: View {
    let level: Int
    let difficulty: GameDifficulty
    @ObservedObject var store: GameProgressStore
    let onLevels: () -> Void
    let onNext: () -> Void
    @StateObject private var model = FlyerModel()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var touching = false

    private var over: Bool { model.phase == .complete || model.phase == .failed }
    private var paused: Bool { scenePhase != .active || over }
    private var goal: Int { FlyerWorld.goal(level: level) }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Text(Loc.t("Seviye {0}", "\(level)"))
                    .font(.subheadline.weight(.semibold))
                ProgressView(value: Double(model.passed), total: Double(goal))
                    .tint(Theme.ink)
                Text("\(model.passed)/\(goal)")
                    .font(.system(.caption, design: .rounded).monospacedDigit())
                    .foregroundStyle(.secondary)
                HStack(spacing: 2) {
                    ForEach(0..<FlyerWorld.lives, id: \.self) { i in
                        Image(systemName: i < model.lives ? "drop.fill" : "drop")
                            .font(.system(size: 11))
                            .foregroundStyle(i < model.lives ? Theme.ink : Color.secondary.opacity(0.4))
                    }
                }
                .accessibilityLabel(Loc.t("{0} damla kaldı", "\(model.lives)"))
            }
            ZStack {
                GeometryReader { geo in
                    TimelineView(.animation(paused: paused)) { timeline in
                        Canvas { context, size in
                            draw(&context, size: size, time: timeline.date)
                        }
                        .onChange(of: timeline.date) { _, now in
                            model.advance(to: now)
                        }
                    }
                    .onChange(of: geo.size, initial: true) { _, size in
                        model.start(size: size, level: level, difficulty: difficulty)
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .local)
                        .onChanged { _ in
                            if !touching {
                                touching = true
                                model.flap()
                            }
                        }
                        .onEnded { _ in touching = false }
                )
                .background(FlapKeys { model.flap() }.frame(width: 0, height: 0))
                .accessibilityLabel(Loc.t("Uçuş alanı: dokun, damla yükselsin"))
                if model.phase == .ready {
                    Label(Loc.t("Dokun ya da boşluk tuşu: damla yükselsin"), systemImage: "hand.tap")
                        .font(.footnote.weight(.medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .glassCapsule()
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 14)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
                if over {
                    LevelResultCard(won: model.phase == .complete, stars: model.world?.stars ?? 0,
                                    detail: Loc.t("{0} engel geçildi", "\(model.passed)"), hasNext: level < FlyerWorld.levels,
                                    onLevels: onLevels, onRetry: { model.restart(level: level, difficulty: difficulty) }, onNext: onNext)
                }
            }
            .gameBoard()
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.85), value: over)
            .animation(.easeInOut(duration: 0.2), value: model.phase == .ready)
        }
        .onChange(of: paused) { _, stopped in
            if stopped { model.pause() }
        }
        .onChange(of: model.phase) { _, phase in
            if phase == .complete {
                store.complete(.flyer, level: level, stars: model.world?.stars ?? 0)
            } else if phase == .failed {
                store.complete(.flyer, level: level, stars: 0)
            }
        }
        .sensoryFeedback(.impact(weight: .light, intensity: 0.5), trigger: model.passed)
        .sensoryFeedback(.warning, trigger: model.lives) { old, new in new < old }
        .sensoryFeedback(.success, trigger: model.phase) { _, new in new == .complete }
    }

    // MARK: Drawing, in the world's own points scaled to the field

    private func draw(_ context: inout GraphicsContext, size: CGSize, time: Date) {
        guard let w = model.world else { return }
        let scale = min(size.width / w.size.width, size.height / w.size.height)
        context.translateBy(x: (size.width - w.size.width * scale) / 2, y: (size.height - w.size.height * scale) / 2)
        context.scaleBy(x: scale, y: scale)
        let width = Double(w.size.width)
        let height = Double(w.size.height)
        // Ruled paper, and a red margin line scrolling by.
        var rules = Path()
        var y = 28.0
        while y < height {
            rules.move(to: CGPoint(x: 0, y: y))
            rules.addLine(to: CGPoint(x: width, y: y))
            y += 28
        }
        context.stroke(rules, with: .color(Theme.rule), lineWidth: 0.7)
        let marginSpan = width + 400
        var marginX = (260 - w.distance * 0.6).truncatingRemainder(dividingBy: marginSpan)
        if marginX < 0 { marginX += marginSpan }
        var margin = Path()
        margin.move(to: CGPoint(x: marginX - 200, y: 0))
        margin.addLine(to: CGPoint(x: marginX - 200, y: height))
        context.stroke(margin, with: .color(Color.red.opacity(0.12)), lineWidth: 1)
        // Ink-wash clouds drifting by, slower than the pencils.
        for (i, base) in [40.0, 170.0, 290.0].enumerated() {
            let span = width + 140
            let wrapped = (base - w.distance * (0.25 + 0.1 * Double(i))).truncatingRemainder(dividingBy: span)
            let cx = (wrapped < 0 ? wrapped + span : wrapped) - 70
            let cloud = CGRect(x: cx, y: 24 + Double(i) * 34, width: 70 + Double(i) * 12, height: 22)
            context.fill(Path(ellipseIn: cloud), with: .color(Theme.ink.opacity(0.05)))
        }
        for obstacle in w.obstacles where obstacle.x > -40 && obstacle.x < width + 40 {
            switch obstacle.kind {
            case .pencilBelow:
                pencil(&context, x: obstacle.x, base: height, tip: obstacle.bottom)
                ruler(&context, x: obstacle.x, top: 0, bottom: obstacle.top)
            case .pencilAbove:
                pencil(&context, x: obstacle.x, base: 0, tip: obstacle.top)
                ruler(&context, x: obstacle.x, top: obstacle.bottom, bottom: height)
            }
        }
        if w.flagX < width + 20 {
            flag(&context, x: w.flagX, height: height)
        }
        drop(&context, w, time: time)
    }

    /// A pencil from `base` (the floor or the top edge) to its tip at `tip`.
    private func pencil(_ c: inout GraphicsContext, x: Double, base: Double, tip: Double) {
        let half = FlyerObstacle.width / 2
        let width = FlyerObstacle.width
        let tipUp = tip < base
        let toward: Double = tipUp ? -1 : 1
        let woodEnd = tip - toward * 22
        let wood = CGRect(x: x - half, y: min(base, woodEnd), width: width, height: abs(base - woodEnd))
        c.fill(Path(wood), with: .color(Color(red: 0.95, green: 0.74, blue: 0.25)))
        c.fill(Path(CGRect(x: x + half - 6, y: wood.minY, width: 6, height: wood.height)), with: .color(.black.opacity(0.08)))
        c.fill(Path(CGRect(x: x - half, y: wood.minY, width: 4, height: wood.height)), with: .color(.white.opacity(0.18)))
        var cone = Path()
        cone.move(to: CGPoint(x: x - half, y: woodEnd))
        cone.addLine(to: CGPoint(x: x + half, y: woodEnd))
        cone.addLine(to: CGPoint(x: x, y: tip))
        cone.closeSubpath()
        c.fill(cone, with: .color(Color(red: 0.87, green: 0.76, blue: 0.6)))
        var lead = Path()
        let leadBase = tip - toward * 7
        lead.move(to: CGPoint(x: x - 4, y: leadBase))
        lead.addLine(to: CGPoint(x: x + 4, y: leadBase))
        lead.addLine(to: CGPoint(x: x, y: tip))
        lead.closeSubpath()
        c.fill(lead, with: .color(Color(white: 0.25)))
        let bandY = tipUp ? base - 14 : base
        c.fill(Path(CGRect(x: x - half, y: bandY, width: width, height: 14)), with: .color(Color(red: 0.93, green: 0.6, blue: 0.62)))
        c.fill(Path(CGRect(x: x - half, y: tipUp ? base - 20 : base + 14, width: width, height: 6)), with: .color(Color(white: 0.75)))
    }

    /// A ruler from `top` to `bottom`, its ticks along the left edge.
    private func ruler(_ c: inout GraphicsContext, x: Double, top: Double, bottom: Double) {
        guard bottom > top else { return }
        let half = FlyerObstacle.width / 2
        let rect = CGRect(x: x - half, y: top, width: FlyerObstacle.width, height: bottom - top)
        c.fill(Path(rect), with: .color(Color(red: 0.93, green: 0.87, blue: 0.72)))
        c.stroke(Path(rect), with: .color(Color(red: 0.55, green: 0.42, blue: 0.25).opacity(0.6)), lineWidth: 1)
        var ticks = Path()
        var y = top + 6
        var n = 0
        while y < bottom - 2 {
            ticks.move(to: CGPoint(x: x - half, y: y))
            ticks.addLine(to: CGPoint(x: x - half + (n % 5 == 0 ? 12 : 6), y: y))
            y += 6
            n += 1
        }
        c.stroke(ticks, with: .color(.black.opacity(0.35)), lineWidth: 0.8)
    }

    private func flag(_ c: inout GraphicsContext, x: Double, height: Double) {
        let poleTop = height * 0.35
        var pole = Path()
        pole.move(to: CGPoint(x: x, y: height))
        pole.addLine(to: CGPoint(x: x, y: poleTop))
        c.stroke(pole, with: .color(Color(white: 0.45)), lineWidth: 2)
        var cloth = Path()
        cloth.move(to: CGPoint(x: x, y: poleTop))
        cloth.addLine(to: CGPoint(x: x + 30, y: poleTop + 10))
        cloth.addLine(to: CGPoint(x: x, y: poleTop + 20))
        cloth.closeSubpath()
        c.fill(cloth, with: .color(Theme.ink))
    }

    /// The ink drop, tilted by its speed, blinking while it is safe after a hit.
    private func drop(_ c: inout GraphicsContext, _ w: FlyerWorld, time: Date) {
        let r = FlyerWorld.dropRadius
        let bob = w.phase == .ready ? sin(time.timeIntervalSinceReferenceDate * 2.2) * 5 : 0
        let tilt = max(-0.5, min(0.9, w.velocity / 420))
        let blink = w.graceLeft > 0 && Int(w.elapsed * 10) % 2 == 0
        var ink = c
        ink.opacity = blink ? 0.45 : 1
        ink.translateBy(x: w.dropX, y: w.dropY + bob)
        ink.rotate(by: .radians(tilt))
        var shape = Path(ellipseIn: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r))
        shape.move(to: CGPoint(x: -r * 0.2, y: -r * 0.9))
        shape.addLine(to: CGPoint(x: -r * 2.1, y: -r * 0.2))
        shape.addLine(to: CGPoint(x: -r * 0.3, y: r * 0.8))
        shape.closeSubpath()
        ink.fill(shape, with: .color(Theme.ink))
        ink.fill(Path(ellipseIn: CGRect(x: -r * 0.55, y: -r * 0.65, width: r * 0.5, height: r * 0.32)), with: .color(.white.opacity(0.6)))
    }
}
