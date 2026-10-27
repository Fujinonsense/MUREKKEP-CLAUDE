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

/// A bubble popping, falling, or settling into its cell, for a moment.
struct ShooterEffect {
    enum Kind {
        case pop, fall, settle
    }

    let kind: Kind
    let colour: Int
    let started: Date
    let origin: CGPoint
    /// Which way a falling bubble drifts.
    let drift: Double

    var life: TimeInterval {
        switch kind {
        case .pop: return 0.4
        case .fall: return 0.6
        case .settle: return 0.2
        }
    }
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
    /// Ink blots earned and colours swapped, for the taps that answer them.
    @Published private(set) var blots = 0
    @Published private(set) var swaps = 0
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

    static let speed = 1000.0

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

    /// Lays the honeycomb out for the field: as wide as the field allows, or as tall as the rows
    /// down to the dead line plus the pen's room.
    func layout(size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let penRoom = 44.0
        let rows = Double(ShooterBoard.deadRow)
        let radius = min(Double(size.width) / Double(2 * ShooterBoard.cols), (Double(size.height) - penRoom) / (2 + rows * 3.0.squareRoot()))
        grid = HexGrid(cols: ShooterBoard.cols, radius: max(6, radius))
        areaSize = size
        origin = CGPoint(x: grid.width / 2, y: Double(size.height) - 26)
    }

    /// Where the board's left edge stands in the field: centred.
    var boardOffset: CGPoint { CGPoint(x: (Double(areaSize.width) - grid.width) / 2, y: 0) }

    func toBoard(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x - boardOffset.x, y: point.y - boardOffset.y)
    }

    /// The small well beside the pen that holds the next colour, in the board's points.
    var well: (centre: CGPoint, radius: Double) {
        let radius = grid.radius * 0.85
        return (CGPoint(x: grid.width - radius - 2, y: Double(origin.y)), radius)
    }

    /// True for a point of the field on the well (with room for a finger around it).
    func inWell(_ point: CGPoint) -> Bool {
        let p = toBoard(point)
        let dx = Double(p.x) - Double(well.centre.x)
        let dy = Double(p.y) - Double(well.centre.y)
        let reach = well.radius + 10
        return dx * dx + dy * dy <= reach * reach
    }

    /// The colour in the pen and the next change places.
    func swapLoaded() {
        guard var playing = board, playing.phase == .playing, flight == nil else { return }
        playing.swapLoaded()
        board = playing
        swaps += 1
        sync()
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

    /// The guide: the way the loaded bubble would take, and where it would come to rest.
    func guide() -> (path: [CGPoint], landing: ShooterCell)? {
        guard let aim, let board, flight == nil else { return nil }
        return board.flight(from: origin, direction: aim, grid: grid)
    }

    /// Lands the bubble when it gets there; lets the pops and falls fade.
    func tick(_ now: Date) {
        if let flight, now.timeIntervalSince(flight.started) * Self.speed >= flight.length {
            land(flight, now: now)
        }
        if !effects.isEmpty {
            effects.removeAll { now.timeIntervalSince($0.started) > $0.life }
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

    /// How far a settling bubble is from its final size, 1 → 0.
    func settling(_ cell: ShooterCell, now: Date) -> Double {
        guard let effect = effects.first(where: { $0.kind == .settle && $0.origin == grid.centre(cell) }) else { return 0 }
        return max(0, 1 - now.timeIntervalSince(effect.started) / effect.life)
    }

    private func land(_ flight: ShooterFlight, now: Date) {
        self.flight = nil
        for (i, cell) in flight.result.popped.enumerated() {
            effects.append(ShooterEffect(kind: .pop, colour: shown[cell] ?? flight.colour, started: now, origin: grid.centre(cell), drift: Double(i % 3) - 1))
        }
        for (i, cell) in flight.result.fell.enumerated() {
            effects.append(ShooterEffect(kind: .fall, colour: shown[cell] ?? flight.colour, started: now, origin: grid.centre(cell), drift: Double(i % 5) - 2))
        }
        if flight.result.popped.isEmpty {
            effects.append(ShooterEffect(kind: .settle, colour: flight.colour, started: now, origin: grid.centre(flight.result.landed), drift: 0))
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
        blots = board.blotsEarned
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

/// One level: drag the pencil to aim (a dotted line shows the way, one bounce off a wall, a ring
/// where the bubble will rest), let go to shoot; three of a colour pop, and bubbles left hanging
/// on nothing fall for more. A tap on the well beside the pen swaps the colours; a big pop earns
/// an ink blot.
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
                    .font(.system(.subheadline, design: .rounded).monospacedDigit().weight(.semibold))
                    .foregroundStyle(model.shotsLeft <= 2 ? Color.red : Color.primary)
                    .accessibilityLabel(Loc.t("{0} atış kaldı", "\(model.shotsLeft)"))
                Spacer()
                Text(Loc.t("Puan: {0}", "\(model.score)"))
                    .font(.system(.subheadline, design: .rounded).monospacedDigit())
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
                        .onChanged { value in
                            if !model.inWell(value.startLocation) { model.updateAim(to: value.location) }
                        }
                        .onEnded { value in
                            if model.inWell(value.startLocation) {
                                if model.inWell(value.location) { model.swapLoaded() }
                            } else {
                                model.fire(at: value.location, now: Date())
                            }
                        }
                )
                .accessibilityLabel(Loc.t("Balon tahtası: sürükleyerek nişan al, bırakınca atar"))
                .accessibilityAction(named: Text(Loc.t("Rengi değiştir"))) { model.swapLoaded() }
                if over {
                    LevelResultCard(won: model.phase == .won, stars: model.stars,
                                    detail: Loc.t("Puan: {0}", "\(model.score)") + (model.phase == .won ? "" : " · " + Loc.t("Balonlar kaldı")),
                                    hasNext: level < ShooterLevels.count,
                                    onLevels: onLevels, onRetry: { model.restart(difficulty: difficulty) }, onNext: onNext)
                }
            }
            .gameBoard()
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.85), value: over)
        }
        .onChange(of: over) { _, done in
            guard done else { return }
            store.complete(.shooter, level: level, stars: model.phase == .won ? model.stars : 0)
        }
        .sensoryFeedback(.impact(weight: .light, intensity: 0.5), trigger: model.score)
        .sensoryFeedback(.success, trigger: over) { _, done in done && model.phase == .won }
        .sensoryFeedback(.impact(weight: .heavy, intensity: 0.7), trigger: model.blots) { old, new in new > old }
        .sensoryFeedback(.selection, trigger: model.swaps)
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize, now: Date) {
        let grid = model.grid
        context.translateBy(x: model.boardOffset.x, y: model.boardOffset.y)
        // The ceiling the bubbles hang from, and the line a bubble must not reach.
        var ceiling = Path()
        ceiling.move(to: CGPoint(x: 0, y: 1))
        ceiling.addLine(to: CGPoint(x: grid.width, y: 1))
        context.stroke(ceiling, with: .color(Theme.ink.opacity(0.35)), lineWidth: 2)
        let deadY = Double(grid.centre(ShooterCell(ShooterBoard.deadRow, 0)).y) - grid.radius
        var dead = Path()
        dead.move(to: CGPoint(x: 0, y: deadY))
        dead.addLine(to: CGPoint(x: grid.width, y: deadY))
        context.stroke(dead, with: .color(Color.red.opacity(0.3)), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
        for (cell, colour) in model.shown {
            let swell = model.settling(cell, now: now)
            bubble(&context, at: grid.centre(cell), radius: grid.radius * (1 + 0.18 * swell), colour: colour)
        }
        for effect in model.effects {
            let t = min(1, now.timeIntervalSince(effect.started) / effect.life)
            var fading = context
            fading.opacity = 1 - t
            switch effect.kind {
            case .pop:
                let r = grid.radius * (1 + 1.3 * t)
                fading.stroke(Path(ellipseIn: CGRect(x: Double(effect.origin.x) - r, y: Double(effect.origin.y) - r, width: 2 * r, height: 2 * r)),
                              with: .color(GameCorner.shade(effect.colour, light: 0.6)), lineWidth: 2.5 * (1 - t) + 0.5)
                bubble(&fading, at: effect.origin, radius: grid.radius * (1 - t), colour: effect.colour)
                let reach = grid.radius * (0.5 + 1.8 * t)
                for k in 0..<6 {
                    let angle = Double(k) * .pi / 3 + effect.drift
                    let drop = CGRect(x: Double(effect.origin.x) + cos(angle) * reach - 2.5, y: Double(effect.origin.y) + sin(angle) * reach - 2.5, width: 5, height: 5)
                    fading.fill(Path(ellipseIn: drop), with: .color(GameCorner.ink(effect.colour)))
                }
            case .fall:
                let fallen = CGPoint(x: Double(effect.origin.x) + effect.drift * 18 * t, y: Double(effect.origin.y) + 900 * t * t)
                bubble(&fading, at: fallen, radius: grid.radius, colour: effect.colour)
            case .settle:
                break
            }
        }
        if let flight = model.flight {
            piece(&context, at: model.position(of: flight, now: now), radius: grid.radius, colour: flight.colour)
        }
        if let guide = model.guide() {
            var dots = Path()
            var left = 10.0
            var count = 0
            for (a, b) in zip(guide.path, guide.path.dropFirst()) {
                let dx = Double(b.x - a.x)
                let dy = Double(b.y - a.y)
                let step = (dx * dx + dy * dy).squareRoot()
                var along = left
                while along < step {
                    let p = CGPoint(x: Double(a.x) + dx * along / step, y: Double(a.y) + dy * along / step)
                    let r = max(1.2, 2.4 - Double(count) * 0.04)
                    dots.addEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
                    along += 12
                    count += 1
                }
                left = along - step
            }
            context.fill(dots, with: .color(Theme.ink.opacity(0.45)))
            let rest = grid.centre(guide.landing)
            let ring = CGRect(x: Double(rest.x) - grid.radius + 1, y: Double(rest.y) - grid.radius + 1, width: 2 * grid.radius - 2, height: 2 * grid.radius - 2)
            let ringColour = model.loaded == ShooterBoard.blot ? Color.primary : GameCorner.ink(model.loaded)
            context.stroke(Path(ellipseIn: ring), with: .color(ringColour.opacity(0.7)), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
        }
        pen(&context)
        // The colour after this one, in a small well beside the pen; a tap there swaps the two.
        let wellRadius = model.well.radius
        let well = model.well.centre
        context.fill(Path(ellipseIn: CGRect(x: Double(well.x) - wellRadius, y: Double(well.y) - wellRadius, width: 2 * wellRadius, height: 2 * wellRadius)),
                     with: .color(Color.primary.opacity(0.05)))
        context.stroke(Path(ellipseIn: CGRect(x: Double(well.x) - wellRadius, y: Double(well.y) - wellRadius, width: 2 * wellRadius, height: 2 * wellRadius)),
                       with: .color(Theme.hairline), lineWidth: 0.8)
        piece(&context, at: well, radius: grid.radius * 0.55, colour: model.next)
        context.draw(Text(Loc.t("Sonraki")).font(.caption2).foregroundStyle(.secondary), at: CGPoint(x: well.x, y: Double(well.y) - wellRadius - 7), anchor: .center)
        context.draw(Text(Image(systemName: "arrow.left.arrow.right")).font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary),
                     at: CGPoint(x: Double(well.x) - wellRadius - 9, y: Double(well.y)), anchor: .center)
    }

    /// A bubble, or the ink blot.
    private func piece(_ c: inout GraphicsContext, at centre: CGPoint, radius: Double, colour: Int) {
        if colour == ShooterBoard.blot {
            blot(&c, at: centre, radius: radius)
        } else {
            bubble(&c, at: centre, radius: radius, colour: colour)
        }
    }

    /// The ink blot: an uneven splash of near-black ink with a light rim (so it shows on night
    /// paper too), two flecks beside it and a wet glint.
    private func blot(_ c: inout GraphicsContext, at centre: CGPoint, radius: Double) {
        guard radius > 0.5 else { return }
        var splash = Path()
        for i in 0...48 {
            let a = Double(i) / 48 * 2 * .pi
            let r = radius * (0.9 + 0.12 * sin(9 * a) + 0.05 * sin(3 * a + 1))
            let p = CGPoint(x: Double(centre.x) + r * cos(a), y: Double(centre.y) + r * sin(a))
            if i == 0 { splash.move(to: p) } else { splash.addLine(to: p) }
        }
        splash.closeSubpath()
        let ink = Color(red: 0.08, green: 0.1, blue: 0.2)
        c.fill(splash, with: .color(ink))
        c.stroke(splash, with: .color(.white.opacity(0.5)), lineWidth: 1)
        for (dx, dy, size) in [(1.05, -0.75, 0.22), (-1.0, 0.8, 0.16)] {
            let fleck = CGRect(x: Double(centre.x) + dx * radius - size * radius / 2, y: Double(centre.y) + dy * radius - size * radius / 2,
                               width: size * radius, height: size * radius)
            c.fill(Path(ellipseIn: fleck), with: .color(ink))
        }
        let glint = CGRect(x: Double(centre.x) - radius * 0.5, y: Double(centre.y) - radius * 0.55, width: radius * 0.38, height: radius * 0.22)
        c.fill(Path(ellipseIn: glint), with: .color(.white.opacity(0.5)))
    }

    /// A glossy ink bubble: a gradient lit from the top left, a darker rim, a glint.
    private func bubble(_ c: inout GraphicsContext, at centre: CGPoint, radius: Double, colour: Int) {
        guard radius > 0.5 else { return }
        let rect = CGRect(x: Double(centre.x) - radius, y: Double(centre.y) - radius, width: 2 * radius, height: 2 * radius)
        let light = GameCorner.shade(colour, light: 1)
        let mid = GameCorner.ink(colour)
        let dark = GameCorner.shade(colour, light: -1)
        let focus = CGPoint(x: Double(centre.x) - radius * 0.3, y: Double(centre.y) - radius * 0.35)
        c.fill(Path(ellipseIn: rect), with: .radialGradient(Gradient(colors: [light, mid, dark]), center: focus, startRadius: 0, endRadius: CGFloat(radius * 1.35)))
        c.stroke(Path(ellipseIn: rect.insetBy(dx: 0.6, dy: 0.6)), with: .color(dark.opacity(0.55)), lineWidth: 1)
        let glint = CGRect(x: Double(centre.x) - radius * 0.62, y: Double(centre.y) - radius * 0.7, width: radius * 0.42, height: radius * 0.26)
        c.fill(Path(ellipseIn: glint), with: .color(.white.opacity(0.65)))
        let speck = CGRect(x: Double(centre.x) + radius * 0.25, y: Double(centre.y) + radius * 0.35, width: radius * 0.16, height: radius * 0.12)
        c.fill(Path(ellipseIn: speck), with: .color(.white.opacity(0.25)))
    }

    /// The pen at the bottom, turned toward the aim, its loaded bubble at the mouth.
    private func pen(_ c: inout GraphicsContext) {
        let r = model.grid.radius
        let angle = model.aim.map { atan2(Double($0.y), Double($0.x)) + .pi / 2 } ?? 0
        var turned = c
        turned.translateBy(x: model.origin.x, y: model.origin.y)
        turned.rotate(by: .radians(angle))
        let barrel = Path(roundedRect: CGRect(x: -r * 0.75, y: r * 0.3, width: r * 1.5, height: r * 2.2), cornerRadius: r * 0.45)
        turned.fill(barrel, with: .color(Color.primary.opacity(0.09)))
        turned.stroke(barrel, with: .color(Theme.hairline), lineWidth: 0.8)
        var nib = Path()
        nib.move(to: CGPoint(x: -r * 0.75, y: r * 0.3))
        nib.addLine(to: CGPoint(x: 0, y: -r * 0.4))
        nib.addLine(to: CGPoint(x: r * 0.75, y: r * 0.3))
        nib.closeSubpath()
        turned.fill(nib, with: .color(Theme.ink.opacity(0.55)))
        turned.fill(Path(CGRect(x: -r * 0.75, y: r * 1.2, width: r * 1.5, height: r * 0.25)), with: .color(Theme.ink.opacity(0.35)))
        if model.flight == nil, model.phase == .playing {
            piece(&c, at: model.origin, radius: r, colour: model.loaded)
        }
    }
}
