import SwiftUI

/// The bubbles on screen: the field, the clock and the score. The field is stepped from the
/// animation timeline; the published values change only when a number on screen does. The best
/// score of each difficulty is the progress store's.
final class BubbleGameModel: ObservableObject {
    @Published private(set) var score = 0
    @Published private(set) var secondsLeft = Int(BubbleField.round)
    @Published private(set) var isOver = false
    @Published private(set) var popped = 0
    private(set) var field: BubbleField
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
        let left = Int(field.timeLeft.rounded(.up))
        if left != secondsLeft { secondsLeft = left }
        if field.isOver { isOver = true }
    }

    func pause() {
        last = nil
    }

    func pop(at point: CGPoint) {
        guard !isOver, field.pop(at: point) != nil else { return }
        score = field.score
        popped += 1
    }

    /// A fresh round at `difficulty`.
    func restart(difficulty: GameDifficulty) {
        field = Self.newField(size: field.size, difficulty: difficulty)
        last = nil
        score = 0
        popped = 0
        secondsLeft = Int(BubbleField.round)
        isOver = false
    }
}

/// Ink bubbles: they rise and sway for sixty seconds; a tap or a touch of the pencil pops the one
/// under it with a little splash. Small bubbles are worth two, big ones one; the pace picks up,
/// and Kolay / Orta / Zor set how fast it all goes.
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
            HStack {
                stat(Loc.t("Puan"), value: "\(model.score)")
                Spacer()
                Text(GameCorner.clock(model.secondsLeft))
                    .font(.title3.monospacedDigit().weight(.semibold))
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
                if model.isOver {
                    endCard
                }
            }
            .background(Theme.paper, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 0.6))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
    }

    private var endCard: some View {
        VStack(spacing: 8) {
            Text(Loc.t("Süre doldu"))
                .font(Theme.display(.title3))
            Text(Loc.t("Puan: {0}", "\(model.score)"))
                .font(.headline)
            if newBest {
                Text(Loc.t("Yeni rekor!"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
            } else {
                Text(Loc.t("En iyi: {0}", "\(best)"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Button {
                newBest = false
                model.restart(difficulty: difficulty)
            } label: {
                Label(Loc.t("Tekrar"), systemImage: "arrow.counterclockwise")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.ink)
        }
        .padding(18)
        .glassCard(radius: 18)
        .transition(reduceMotion ? .opacity : .scale(scale: 0.9).combined(with: .opacity))
    }

    private func stat(_ title: String, value: String) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.headline.monospacedDigit())
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 56)
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize) {
        for bubble in model.field.bubbles {
            let rect = CGRect(x: bubble.x - bubble.radius, y: bubble.y - bubble.radius, width: 2 * bubble.radius, height: 2 * bubble.radius)
            let tint = Color(hue: bubble.hue, saturation: 0.7, brightness: 0.95)
            let centre = CGPoint(x: bubble.x, y: bubble.y)
            let fill = GraphicsContext.Shading.radialGradient(Gradient(colors: [tint.opacity(0.12), tint.opacity(0.38)]),
                                                              center: centre, startRadius: 0, endRadius: CGFloat(bubble.radius))
            context.fill(Path(ellipseIn: rect), with: fill)
            context.stroke(Path(ellipseIn: rect), with: .color(tint.opacity(0.85)), lineWidth: 1.4)
            // A glint at the top left.
            let glint = CGRect(x: bubble.x - bubble.radius * 0.55, y: bubble.y - bubble.radius * 0.62,
                               width: bubble.radius * 0.36, height: bubble.radius * 0.22)
            context.fill(Path(ellipseIn: glint), with: .color(.white.opacity(0.55)))
        }
        for splash in model.field.splashes {
            let t = splash.age / Splash.life
            let fade = 1 - t
            let tint = Color(hue: splash.hue, saturation: 0.7, brightness: 0.95)
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
    }
}
