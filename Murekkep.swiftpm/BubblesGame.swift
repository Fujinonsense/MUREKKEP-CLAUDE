import SwiftUI

/// The bubbles on screen: the field, the clock, the score and the row. The field is stepped from
/// the animation timeline; the published values change only when a number on screen does. The best
/// score of each difficulty is the progress store's.
final class BubbleGameModel: ObservableObject {
    /// A few words that float up from a pop: "+6 ×2", "−5".
    struct Floater {
        let x: Double
        let y: Double
        let text: String
        let blot: Bool
        let at: TimeInterval

        static let life: TimeInterval = 0.8
    }

    @Published private(set) var score = 0
    @Published private(set) var secondsLeft = Int(BubbleField.round)
    @Published private(set) var isOver = false
    @Published private(set) var popped = 0
    @Published private(set) var combo = 1
    @Published private(set) var blotsHit = 0
    private(set) var field: BubbleField
    private(set) var floaters: [Floater] = []
    private var last: Date?

    init() {
        field = Self.newField(size: CGSize(width: 316, height: 300), difficulty: .medium)
    }

    private static func newField(size: CGSize, difficulty: GameDifficulty) -> BubbleField {
        BubbleField(size: size, seed: UInt64(max(0, Date().timeIntervalSinceReferenceDate * 1000)), difficulty: difficulty)
    }

    func resize(_ size: CGSize) {
        guard size.width > 0, size.height > 0, size != field.size else { return }
        field.size = size
    }

    /// Steps the field on to `now`; the first step after a pause starts the clock again.
    func advance(to now: Date) {
        guard !isOver else { return }
        let dt = last.map { now.timeIntervalSince($0) } ?? 0
        last = now
        field.advance(by: dt)
        floaters.removeAll { field.elapsed - $0.at > Floater.life }
        let left = Int(field.timeLeft.rounded(.up))
        if left != secondsLeft { secondsLeft = left }
        if field.combo != combo { combo = field.combo }
        if field.isOver { isOver = true }
    }

    func pause() {
        last = nil
    }

    func pop(at point: CGPoint) {
        guard !isOver else { return }
        switch field.pop(at: point) {
        case .popped(let points, let row):
            score = field.score
            popped += 1
            if row != combo { combo = row }
            floaters.append(Floater(x: Double(point.x), y: Double(point.y), text: row > 1 ? "+\(points) ×\(row)" : "+\(points)", blot: false, at: field.elapsed))
        case .blot(let points, let seconds):
            score = field.score
            blotsHit += 1
            if combo != 1 { combo = 1 }
            floaters.append(Floater(x: Double(point.x), y: Double(point.y), text: "−\(points) · −\(seconds) sn", blot: true, at: field.elapsed))
        case .miss:
            if combo != 1 { combo = 1 }
        }
    }

    /// A fresh round at `difficulty`.
    func restart(difficulty: GameDifficulty) {
        field = Self.newField(size: field.size, difficulty: difficulty)
        floaters = []
        last = nil
        score = 0
        popped = 0
        combo = 1
        blotsHit = 0
        secondsLeft = Int(BubbleField.round)
        isOver = false
    }
}

/// Ink bubbles: they rise and sway for sixty seconds, faster and smaller as the clock runs; a tap or
/// a touch of the pencil pops the one under it. Quick pops in a row multiply the points; the dark
/// blots must be left alone (a touch costs points and seconds). Kolay / Orta / Zor set the pace,
/// the reach of a touch and the blots.
struct InkBubblesGame: View {
    @ObservedObject var store: GameProgressStore
    @StateObject private var model = BubbleGameModel()
    @State private var newBest = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var difficulty: GameDifficulty { store[.bubbles].difficulty }
    private var best: Int { store[.bubbles].best[difficulty] ?? 0 }
    private var paused: Bool { model.isOver || scenePhase != .active }

    var body: some View {
        VStack(spacing: 8) {
            DifficultyPicker(difficulty: Binding(get: { store[.bubbles].difficulty }, set: { store.setDifficulty($0, for: .bubbles) }))
            HStack(alignment: .firstTextBaseline) {
                stat(Loc.t("Puan"), value: "\(model.score)")
                Spacer()
                Text(GameCorner.clock(model.secondsLeft))
                    .font(.system(.title3, design: .rounded).monospacedDigit().weight(.semibold))
                    .foregroundStyle(model.secondsLeft <= 10 && !model.isOver ? Color.red : Color.primary)
                    .accessibilityLabel(Loc.t("Kalan süre {0} saniye", "\(model.secondsLeft)"))
                Spacer()
                stat(Loc.t("En iyi"), value: "\(best)")
            }
            ZStack {
                GeometryReader { geo in
                    TimelineView(.animation(paused: paused)) { timeline in
                        Canvas { context, size in
                            draw(&context, size: size)
                        }
                        .onChange(of: timeline.date) { _, now in
                            model.advance(to: now)
                        }
                    }
                    .onChange(of: geo.size, initial: true) { _, size in
                        model.resize(size)
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .local)
                        .onChanged { value in model.pop(at: value.location) }
                )
                .accessibilityLabel(Loc.t("Balon alanı"))
                VStack {
                    HStack {
                        Label(Loc.t("Lekelere dokunma"), systemImage: "hand.raised")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if model.combo > 1 {
                            Text("×\(model.combo)")
                                .font(.system(.caption, design: .rounded).weight(.bold).monospacedDigit())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Theme.ink, in: Capsule())
                                .transition(.scale.combined(with: .opacity))
                                .accessibilityLabel(Loc.t("Çarpan {0}", "\(model.combo)"))
                        }
                    }
                    .padding(8)
                    Spacer()
                }
                .allowsHitTesting(false)
                .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.7), value: model.combo)
                if model.isOver {
                    ResultCard(title: Loc.t("Süre doldu"),
                               lines: [Loc.t("Puan: {0}", "\(model.score)"), Loc.t("{0} balon · {1} leke", "\(model.popped)", "\(model.blotsHit)")],
                               highlight: newBest ? Loc.t("Yeni rekor!") : Loc.t("En iyi: {0}", "\(best)"),
                               actions: [ResultAction(Loc.t("Tekrar"), prominent: true) {
                                   newBest = false
                                   model.restart(difficulty: difficulty)
                               }])
                }
            }
            .gameBoard()
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.85), value: model.isOver)
        }
        .onChange(of: difficulty, initial: true) { _, level in
            newBest = false
            model.restart(difficulty: level)
        }
        .onChange(of: paused) { _, stopped in
            if stopped { model.pause() }
        }
        .onChange(of: model.isOver) { _, over in
            if over { newBest = store.record(.bubbles, score: model.score, at: difficulty) }
        }
        .sensoryFeedback(.impact(weight: .light, intensity: 0.6), trigger: model.popped)
        .sensoryFeedback(.warning, trigger: model.blotsHit)
    }

    private func stat(_ title: String, value: String) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(.headline, design: .rounded).monospacedDigit())
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 56)
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize) {
        for bubble in model.field.bubbles {
            switch bubble.kind {
            case .ink: inkBubble(&context, bubble)
            case .blot: blot(&context, bubble)
            }
        }
        for splash in model.field.splashes {
            let t = splash.age / Splash.life
            let fade = 1 - t
            let tint = splash.blot ? Color(hue: 0.64, saturation: 0.5, brightness: 0.3) : Color(hue: splash.hue, saturation: 0.7, brightness: 0.95)
            let r = splash.radius * (1 + 1.4 * t)
            let ring = CGRect(x: splash.x - r, y: splash.y - r, width: 2 * r, height: 2 * r)
            context.stroke(Path(ellipseIn: ring), with: .color(tint.opacity(0.7 * fade)), lineWidth: CGFloat(2 * fade + 0.5))
            // Six droplets flying out.
            let reach = splash.radius * (0.6 + 1.6 * t)
            for k in 0..<6 {
                let angle = Double(k) * .pi / 3 + splash.radius
                let drop = CGRect(x: splash.x + cos(angle) * reach - 2, y: splash.y + sin(angle) * reach - 2, width: 4, height: 4)
                context.fill(Path(ellipseIn: drop), with: .color(tint.opacity(0.8 * fade)))
            }
        }
        for floater in model.floaters {
            let t = (model.field.elapsed - floater.at) / BubbleGameModel.Floater.life
            let tint = floater.blot ? Color.red : Theme.ink
            context.draw(Text(floater.text).font(.system(.caption, design: .rounded).weight(.bold).monospacedDigit()).foregroundStyle(tint.opacity(1 - t)),
                         at: CGPoint(x: floater.x, y: floater.y - 14 - 28 * t), anchor: .center)
        }
    }

    /// A glossy ink bubble: a soft gradient, a rim, a glint.
    private func inkBubble(_ context: inout GraphicsContext, _ bubble: Bubble) {
        let rect = CGRect(x: bubble.x - bubble.radius, y: bubble.y - bubble.radius, width: 2 * bubble.radius, height: 2 * bubble.radius)
        let tint = Color(hue: bubble.hue, saturation: 0.7, brightness: 0.95)
        let centre = CGPoint(x: bubble.x, y: bubble.y)
        let fill = GraphicsContext.Shading.radialGradient(Gradient(colors: [tint.opacity(0.1), tint.opacity(0.4)]),
                                                          center: centre, startRadius: 0, endRadius: CGFloat(bubble.radius))
        context.fill(Path(ellipseIn: rect), with: fill)
        context.stroke(Path(ellipseIn: rect), with: .color(tint.opacity(0.85)), lineWidth: 1.4)
        let glint = CGRect(x: bubble.x - bubble.radius * 0.55, y: bubble.y - bubble.radius * 0.62,
                           width: bubble.radius * 0.36, height: bubble.radius * 0.22)
        context.fill(Path(ellipseIn: glint), with: .color(.white.opacity(0.55)))
    }

    /// A blot: a dark, uneven splatter of ink with a faint red rim, not to be touched.
    private func blot(_ context: inout GraphicsContext, _ bubble: Bubble) {
        var shape = Path()
        let points = 9
        for k in 0...points {
            let angle = Double(k % points) * 2 * .pi / Double(points) + bubble.age * 0.4
            let wobble = 0.78 + 0.22 * sin(Double(k % points) * 2.3 + Double(bubble.id))
            let r = bubble.radius * wobble
            let p = CGPoint(x: bubble.x + cos(angle) * r, y: bubble.y + sin(angle) * r)
            if k == 0 { shape.move(to: p) } else { shape.addLine(to: p) }
        }
        shape.closeSubpath()
        let dark = Color(hue: 0.64, saturation: 0.6, brightness: 0.22)
        context.fill(shape, with: .color(dark.opacity(0.92)))
        context.stroke(shape, with: .color(Color.red.opacity(0.45)), lineWidth: 1)
        // A few satellite drops.
        for k in 0..<3 {
            let angle = Double(k) * 2.1 + Double(bubble.id)
            let d = bubble.radius * 1.25
            let dot = CGRect(x: bubble.x + cos(angle) * d - 2, y: bubble.y + sin(angle) * d - 2, width: 4, height: 4)
            context.fill(Path(ellipseIn: dot), with: .color(dark.opacity(0.8)))
        }
    }
}
