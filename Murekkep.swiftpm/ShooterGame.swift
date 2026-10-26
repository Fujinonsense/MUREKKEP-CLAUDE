import SwiftUI

/// Renk patlat: the level map, then a level at the pen.
struct ShooterGame: View {
    @ObservedObject var store: GameProgressStore
    @State private var level: Int?

    var body: some View {
        if let level {
            ShooterPlay(level: level, difficulty: store[.shooter].difficulty, store: store) {
                self.level = nil
            } onNext: {
                self.level = min(ShooterLevels.count, level + 1)
            }
            .id(level)
        } else {
            LevelMap(game: .shooter, store: store) { level = $0 }
        }
    }
}

/// A bubble on its way from the pen.
struct ShooterFlight {
    let path: [CGPoint]
    let colour: Int
    let started: Date
    let length: Double
    let result: ShotResult
}

/// A bubble popping or falling, for half a second.
struct ShooterEffect {
    enum Kind {
        case pop, fall
    }

    let kind: Kind
    let colour: Int
    let started: Date
    let origin: CGPoint

    static let life: TimeInterval = 0.55
}

/// The board on screen: the honeycomb laid out for the field's size, the bubble in flight, the
/// pops and falls, the aim. The board itself (ShooterBoard) answers each shot at once; the screen
/// shows the answer when the bubble gets there.
final class ShooterModel: ObservableObject {
    @Published private(set) var shown: [ShooterCell: Int] = [:]
    @Published private(set) var shotsLeft = 0
    @Published private(set) var score = 0
    @Published private(set) var loaded = 0
    @Published private(set) var next = 0
    @Published private(set) var phase: ShooterBoard.Phase = .playing
    @Published private(set) var animating = false
    /// The aim while the pencil drags: a unit direction, pointing up.
    @Published private(set) var aim: CGPoint?
    private(set) var board: ShooterBoard?
    private(set) var grid = HexGrid(cols: ShooterBoard.cols, radius: 12)
    private(set) var areaSize = CGSize.zero
    /// The pen's mouth, in the board's points.
    private(set) var origin = CGPoint.zero
    private(set) var flight: ShooterFlight?
    private(set) var effects: [ShooterEffect] = []
    private var level: ShooterLevel?

    static let speed = 900.0

    var stars: Int { board?.stars ?? 0 }
    var par: Int { board?.par ?? 0 }

    func start(level: ShooterLevel, difficulty: GameDifficulty) {
        guard board == nil else { return }
        self.level = level
        board = ShooterBoard(level: level, difficulty: difficulty, seed: Self.seed())
        sync()
    }

    func restart(difficulty: GameDifficulty) {
        guard let level else { return }
        board = ShooterBoard(level: level, difficulty: difficulty, seed: Self.seed())
        flight = nil
        effects = []
        aim = nil
        animating = false
        sync()
    }

    /// Lays the honeycomb out for the field: as wide as the field allows, or as tall, with room for the pen.
    func layout(size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let penRoom = 64.0
        let rows = Double(ShooterBoard.deadRow)
        let radius = min(Double(size.width) / Double(2 * ShooterBoard.cols), (Double(size.height) - penRoom) / (2 + rows * 3.0.squareRoot()))
        grid = HexGrid(cols: ShooterBoard.cols, radius: max(6, radius))
        areaSize = size
        origin = CGPoint(x: grid.width / 2, y: Double(size.height) - 30)
    }

    /// Where the board's left edge stands in the field: centred.
    var boardOffset: CGPoint { CGPoint(x: (Double(areaSize.width) - grid.width) / 2, y: 0) }

    func toBoard(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x - boardOffset.x, y: point.y - boardOffset.y)
    }

    func updateAim(to point: CGPoint) {
        guard board?.phase == .playing, flight == nil else { return }
        aim = direction(to: toBoard(point))
    }

    func fire(at point: CGPoint, now: Date) {
        aim = nil
        guard var shooting = board, shooting.phase == .playing, flight == nil, let direction = direction(to: toBoard(point)) else { return }
        let colour = shooting.loaded
        guard let result = shooting.shoot(from: origin, direction: direction, grid: grid) else { return }
        board = shooting
        flight = ShooterFlight(path: result.path, colour: colour, started: now, length: Self.length(result.path), result: result)
        animating = true
    }

    /// The guide: the way the loaded bubble would take.
    func guide() -> [CGPoint]? {
        guard let aim, let board, flight == nil else { return nil }
        return board.flight(from: origin, direction: aim, grid: grid).path
    }

    /// Lands the bubble when it gets there; lets the pops and falls fade.
    func tick(_ now: Date) {
        if let flight, now.timeIntervalSince(flight.started) * Self.speed >= flight.length {
            land(flight, now: now)
        }
        if !effects.isEmpty {
            effects.removeAll { now.timeIntervalSince($0.started) > ShooterEffect.life }
        }
        if flight == nil, effects.isEmpty, animating {
            animating = false
        }
    }

    func position(of flight: ShooterFlight, now: Date) -> CGPoint {
        var left = now.timeIntervalSince(flight.started) * Self.speed
        for (a, b) in zip(flight.path, flight.path.dropFirst()) {
            let dx = Double(b.x - a.x)
            let dy = Double(b.y - a.y)
            let step = (dx * dx + dy * dy).squareRoot()
            if left <= step, step > 0 {
                let t = left / step
                return CGPoint(x: Double(a.x) + dx * t, y: Double(a.y) + dy * t)
            }
            left -= step
        }
        return flight.path.last ?? origin
    }

    private func land(_ flight: ShooterFlight, now: Date) {
        self.flight = nil
        for cell in flight.result.popped {
            effects.append(ShooterEffect(kind: .pop, colour: shown[cell] ?? flight.colour, started: now, origin: grid.centre(cell)))
        }
        for cell in flight.result.fell {
            effects.append(ShooterEffect(kind: .fall, colour: shown[cell] ?? flight.colour, started: now, origin: grid.centre(cell)))
        }
        sync()
    }

    private func direction(to point: CGPoint) -> CGPoint? {
        let dx = Double(point.x - origin.x)
        let dy = Double(point.y - origin.y)
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 8, dy < 0 else { return nil }
        var ux = dx / length
        var uy = dy / length
        // Never flatter than about 80° from straight up.
        let minimumUp = 0.17
        if -uy < minimumUp {
            uy = -minimumUp
            ux = (ux < 0 ? -1 : 1) * (1 - minimumUp * minimumUp).squareRoot()
        }
        return CGPoint(x: ux, y: uy)
    }

    private func sync() {
        guard let board else { return }
        shown = board.cells
        shotsLeft = board.shotsLeft
        score = board.score
        loaded = board.loaded
        next = board.next
        phase = board.phase
    }

    private static func length(_ path: [CGPoint]) -> Double {
        zip(path, path.dropFirst()).reduce(0) { total, pair in
            let dx = Double(pair.1.x - pair.0.x)
            let dy = Double(pair.1.y - pair.0.y)
            return total + (dx * dx + dy * dy).squareRoot()
        }
    }

    private static func seed() -> UInt64 {
        UInt64(max(0, Date().timeIntervalSinceReferenceDate * 1000))
    }
}

/// One level: drag the pencil to aim (a dotted line shows the way, one bounce off a wall), let go to
/// shoot; three of a colour pop, and bubbles left hanging on nothing fall for more.
private struct ShooterPlay: View {
    let level: Int
    let difficulty: GameDifficulty
    @ObservedObject var store: GameProgressStore
    let onLevels: () -> Void
    let onNext: () -> Void
    @StateObject private var model = ShooterModel()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var over: Bool { model.phase != .playing && !model.animating }
    private var paused: Bool { scenePhase != .active || !model.animating }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(Loc.t("Seviye {0}", "\(level)"))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Label("\(model.shotsLeft)", systemImage: "scope")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(model.shotsLeft <= 2 ? Color.red : Color.primary)
                    .accessibilityLabel(Loc.t("{0} atış kaldı", "\(model.shotsLeft)"))
                Spacer()
                Text(Loc.t("Puan: {0}", "\(model.score)"))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ZStack {
                GeometryReader { geo in
                    TimelineView(.animation(paused: paused)) { timeline in
                        Canvas { context, size in
                            draw(&context, size: size, now: timeline.date)
                        }
                        .onChange(of: timeline.date) { _, now in
                            model.tick(now)
                        }
                    }
                    .onChange(of: geo.size, initial: true) { _, size in
                        model.layout(size: size)
                        model.start(level: ShooterLevels.all[level - 1], difficulty: difficulty)
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .local)
                        .onChanged { value in model.updateAim(to: value.location) }
                        .onEnded { value in model.fire(at: value.location, now: Date()) }
                )
                .accessibilityLabel(Loc.t("Balon tahtası: sürükleyerek nişan al, bırakınca atar"))
                if over {
                    LevelResultCard(won: model.phase == .won, stars: model.stars,
                                    detail: Loc.t("Puan: {0}", "\(model.score)") + (model.phase == .won ? "" : " · " + Loc.t("Balonlar kaldı")),
                                    hasNext: level < ShooterLevels.count,
                                    onLevels: onLevels, onRetry: { model.restart(difficulty: difficulty) }, onNext: onNext)
                }
            }
            .background(Theme.paper, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 0.6))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.85), value: over)
        }
        .onChange(of: over) { _, done in
            guard done else { return }
            store.complete(.shooter, level: level, stars: model.phase == .won ? model.stars : 0)
        }
        .sensoryFeedback(.impact(weight: .light, intensity: 0.5), trigger: model.score)
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize, now: Date) {
        let grid = model.grid
        context.translateBy(x: model.boardOffset.x, y: model.boardOffset.y)
        // The line a bubble must not reach.
        let deadY = Double(grid.centre(ShooterCell(ShooterBoard.deadRow, 0)).y) - grid.radius
        var dead = Path()
        dead.move(to: CGPoint(x: 0, y: deadY))
        dead.addLine(to: CGPoint(x: grid.width, y: deadY))
        context.stroke(dead, with: .color(Theme.ink.opacity(0.25)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        for (cell, colour) in model.shown {
            bubble(&context, at: grid.centre(cell), radius: grid.radius, colour: colour)
        }
        for effect in model.effects {
            let t = min(1, now.timeIntervalSince(effect.started) / ShooterEffect.life)
            var fading = context
            fading.opacity = 1 - t
            switch effect.kind {
            case .pop:
                let r = grid.radius * (1 + 1.2 * t)
                fading.stroke(Path(ellipseIn: CGRect(x: Double(effect.origin.x) - r, y: Double(effect.origin.y) - r, width: 2 * r, height: 2 * r)),
                              with: .color(GameCorner.ink(effect.colour)), lineWidth: 2)
                bubble(&fading, at: effect.origin, radius: grid.radius * (1 - t), colour: effect.colour)
            case .fall:
                let fallen = CGPoint(x: Double(effect.origin.x), y: Double(effect.origin.y) + 700 * t * t)
                bubble(&fading, at: fallen, radius: grid.radius, colour: effect.colour)
            }
        }
        if let flight = model.flight {
            bubble(&context, at: model.position(of: flight, now: now), radius: grid.radius, colour: flight.colour)
        }
        if let guide = model.guide() {
            var dots = Path()
            var left = 10.0
            for (a, b) in zip(guide, guide.dropFirst()) {
                let dx = Double(b.x - a.x)
                let dy = Double(b.y - a.y)
                let step = (dx * dx + dy * dy).squareRoot()
                var along = left
                while along < step {
                    let p = CGPoint(x: Double(a.x) + dx * along / step, y: Double(a.y) + dy * along / step)
                    dots.addEllipse(in: CGRect(x: p.x - 2, y: p.y - 2, width: 4, height: 4))
                    along += 14
                }
                left = along - step
            }
            context.fill(dots, with: .color(Theme.ink.opacity(0.4)))
        }
        pen(&context)
        // The colour after this one, beside the pen.
        let nextAt = CGPoint(x: grid.width - grid.radius - 4, y: Double(model.origin.y))
        bubble(&context, at: nextAt, radius: grid.radius * 0.55, colour: model.next)
        context.draw(Text(Loc.t("Sonraki")).font(.caption2).foregroundStyle(.secondary), at: CGPoint(x: nextAt.x, y: nextAt.y - grid.radius * 0.55 - 8), anchor: .center)
    }

    /// An ink bubble: a soft gradient, a rim, a glint.
    private func bubble(_ c: inout GraphicsContext, at centre: CGPoint, radius: Double, colour: Int) {
        guard radius > 0.5 else { return }
        let tint = GameCorner.ink(colour)
        let rect = CGRect(x: Double(centre.x) - radius, y: Double(centre.y) - radius, width: 2 * radius, height: 2 * radius)
        c.fill(Path(ellipseIn: rect), with: .radialGradient(Gradient(colors: [tint.opacity(0.55), tint.opacity(0.95)]),
                                                            center: centre, startRadius: 0, endRadius: CGFloat(radius)))
        c.stroke(Path(ellipseIn: rect.insetBy(dx: 0.7, dy: 0.7)), with: .color(tint), lineWidth: 1)
        let glint = CGRect(x: Double(centre.x) - radius * 0.5, y: Double(centre.y) - radius * 0.62, width: radius * 0.4, height: radius * 0.24)
        c.fill(Path(ellipseIn: glint), with: .color(.white.opacity(0.5)))
    }

    /// The pen at the bottom, turned toward the aim, its loaded bubble at the mouth.
    private func pen(_ c: inout GraphicsContext) {
        let angle = model.aim.map { atan2(Double($0.y), Double($0.x)) + .pi / 2 } ?? 0
        var turned = c
        turned.translateBy(x: model.origin.x, y: model.origin.y)
        turned.rotate(by: .radians(angle))
        var nib = Path(roundedRect: CGRect(x: -8, y: 6, width: 16, height: 30), cornerRadius: 5)
        nib.move(to: CGPoint(x: -8, y: 6))
        nib.addLine(to: CGPoint(x: 0, y: -8))
        nib.addLine(to: CGPoint(x: 8, y: 6))
        nib.closeSubpath()
        turned.fill(nib, with: .color(Theme.ink.opacity(0.85)))
        turned.fill(Path(CGRect(x: -8, y: 20, width: 16, height: 4)), with: .color(.white.opacity(0.35)))
        if model.flight == nil, model.phase == .playing {
            bubble(&c, at: model.origin, radius: model.grid.radius, colour: model.loaded)
        }
    }
}
