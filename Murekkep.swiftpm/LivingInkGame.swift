import SwiftUI

/// The pond on screen. It is stepped by the animation timeline while anything in it moves;
/// `revision` changes with every change, to redraw it.
final class LivingInkModel: ObservableObject {
    @Published private(set) var revision = 0
    /// Counts the strokes begun and ended: each one starts the wait before the drawing wakes afresh.
    @Published private(set) var strokes = 0
    /// For the little taps: a creature woke, a crumb was eaten.
    @Published private(set) var woken = 0
    @Published private(set) var meals = 0
    @Published var ink = 0
    /// The strokes drawn since the last creature woke, in pond points.
    private(set) var drawing: [[CGPoint]] = []
    private(set) var pond: InkPond?
    private(set) var isDrawing = false
    private var last: Date?

    var isMoving: Bool { pond.map { !$0.isStill } ?? false }
    var isEmpty: Bool { (pond?.creatures.isEmpty ?? true) && drawing.isEmpty }

    /// Builds the pond for the first size the board has; the drawing scales to later sizes.
    func start(size: CGSize) {
        guard pond == nil, size.width > 0, size.height > 0 else { return }
        pond = InkPond(size: size, seed: UInt64(max(0, Date().timeIntervalSinceReferenceDate * 1000)))
        changed()
    }

    /// The pond's scale and its offset in a board of `size`, the pond centred in it.
    func fit(in size: CGSize) -> (scale: Double, dx: Double, dy: Double) {
        guard let pond, pond.size.width > 0, pond.size.height > 0 else { return (1, 0, 0) }
        let width = Double(pond.size.width)
        let height = Double(pond.size.height)
        let scale = min(Double(size.width) / width, Double(size.height) / height)
        return (scale, (Double(size.width) - width * scale) / 2, (Double(size.height) - height * scale) / 2)
    }

    /// A point of the board in the pond's own points.
    func pondPoint(_ point: CGPoint, in size: CGSize) -> CGPoint {
        let f = fit(in: size)
        return CGPoint(x: (Double(point.x) - f.dx) / f.scale, y: (Double(point.y) - f.dy) / f.scale)
    }

    func began(at point: CGPoint) {
        isDrawing = true
        drawing.append([point])
        strokes += 1
        changed()
    }

    func moved(to point: CGPoint) {
        guard isDrawing, !drawing.isEmpty else { return }
        drawing[drawing.count - 1].append(point)
        changed()
    }

    /// The pencil lifts. A tap on a creature pokes it instead of leaving a dot.
    func ended() {
        isDrawing = false
        if let stroke = drawing.last, let first = stroke.first,
           stroke.allSatisfy({ InkPond.distance($0, first) < 6 }), pond?.poke(at: first) == true {
            drawing.removeLast()
        }
        strokes += 1
        changed()
    }

    /// The drawing wakes as a creature in the chosen ink (once the pencil has stayed off the pond).
    func wake() {
        guard !isDrawing, !drawing.isEmpty else { return }
        if pond?.wake(drawing, ink: ink) != nil { woken += 1 }
        drawing = []
        changed()
    }

    func feed() {
        pond?.feed()
        last = nil
        changed()
    }

    func pause() {
        last = nil
    }

    func advance(to now: Date) {
        let dt = last.map { now.timeIntervalSince($0) } ?? 0
        last = now
        guard dt > 0, isMoving else { return }
        pond?.advance(by: dt)
        if let eaten = pond?.meals, eaten != meals { meals = eaten }
        changed()
    }

    private func changed() {
        revision &+= 1
    }
}

/// Canlı mürekkep: whatever is drawn on the pond wakes up a moment after the pencil lifts, exactly
/// where it was drawn, shakes itself and swims off; it turns round at the walls, chases food and
/// dashes away when poked. The pencil draws here like a finger.
struct LivingInkGame: View {
    @StateObject private var model = LivingInkModel()
    @Environment(\.scenePhase) private var scenePhase
    /// Where the touch under way began: a touch from somewhere else is a new one, even when the last
    /// one was cancelled without ending.
    @State private var touchStart: CGPoint?

    private static let line = StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round)
    /// Clear water by day and by night, so every ink shows.
    private static let waterTop = Color(red: 0.93, green: 0.97, blue: 0.98)
    private static let waterBottom = Color(red: 0.80, green: 0.90, blue: 0.94)
    private static let weed = Color(red: 0.24, green: 0.50, blue: 0.40)
    private static let crumb = Color(red: 0.67, green: 0.47, blue: 0.24)
    private static let bubble = Color(red: 0.36, green: 0.55, blue: 0.64)

    private var paused: Bool { scenePhase != .active || !model.isMoving }

    var body: some View {
        VStack(spacing: 8) {
            board
            HStack(spacing: 4) {
                ForEach(GameCorner.inkHues.indices, id: \.self) { i in
                    Button {
                        model.ink = i
                    } label: {
                        Circle()
                            .fill(GameCorner.ink(i))
                            .frame(width: 26, height: 26)
                            .padding(3)
                            .overlay(Circle().strokeBorder(model.ink == i ? Theme.ink : Color.clear, lineWidth: 2))
                            .frame(width: 40, height: 40)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Self.inkNames[i])
                    .accessibilityAddTraits(model.ink == i ? .isSelected : [])
                }
                Spacer(minLength: 4)
                Button(Loc.t("Yem ver")) {
                    model.feed()
                }
                .buttonStyle(.bordered)
                .tint(Theme.ink)
                .font(.subheadline.weight(.semibold))
                .disabled(model.pond?.creatures.isEmpty ?? true)
            }
        }
        .task(id: model.strokes) {
            try? await Task.sleep(nanoseconds: UInt64(InkPond.wakeDelay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            model.wake()
        }
        .onChange(of: paused) { _, stopped in
            if stopped { model.pause() }
        }
        .sensoryFeedback(.impact(weight: .light, intensity: 0.6), trigger: model.woken)
        .sensoryFeedback(.selection, trigger: model.meals)
    }

    private static var inkNames: [String] {
        [Loc.t("Lacivert"), Loc.t("Turkuaz"), Loc.t("Macenta"), Loc.t("Kehribar"), Loc.t("Yeşil")]
    }

    private var board: some View {
        ZStack {
            GeometryReader { geo in
                TimelineView(.animation(paused: paused)) { timeline in
                    Canvas { context, size in
                        draw(&context, size: size, time: timeline.date.timeIntervalSinceReferenceDate)
                    }
                    .onChange(of: timeline.date) { _, now in
                        model.advance(to: now)
                    }
                }
                .onChange(of: geo.size, initial: true) { _, size in
                    model.start(size: size)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .local)
                        .onChanged { value in
                            let point = model.pondPoint(value.location, in: geo.size)
                            if touchStart == value.startLocation {
                                model.moved(to: point)
                            } else {
                                touchStart = value.startLocation
                                model.began(at: point)
                            }
                        }
                        .onEnded { _ in
                            touchStart = nil
                            model.ended()
                        }
                )
            }
            .accessibilityLabel(Loc.t("Canlı mürekkep havuzu"))
            if model.isEmpty {
                Text(Loc.t("Bir balık, bir kuş, ne istersen çiz; kalemi kaldırınca canlanır."))
                    .font(.footnote.weight(.medium))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .glassCapsule()
                    .padding(.horizontal, 16)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .gameBoard()
        .animation(.easeInOut(duration: 0.2), value: model.isEmpty)
    }

    /// The water and its weeds, the crumbs and the bubbles, the creatures as they swim, and the
    /// drawing still waiting to wake.
    private func draw(_ context: inout GraphicsContext, size: CGSize, time: Double) {
        let rect = CGRect(origin: .zero, size: size)
        context.fill(Path(rect), with: .linearGradient(Gradient(colors: [Self.waterTop, Self.waterBottom]),
                                                       startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
        guard let pond = model.pond else { return }
        let f = model.fit(in: size)
        context.translateBy(x: CGFloat(f.dx), y: CGFloat(f.dy))
        context.scaleBy(x: CGFloat(f.scale), y: CGFloat(f.scale))
        let width = Double(pond.size.width)
        let height = Double(pond.size.height)
        // Weeds swaying on the bottom.
        for (i, base) in [0.12, 0.3, 0.71, 0.88].enumerated() {
            let x = width * base
            let tall = height * (0.16 + 0.05 * Double(i % 2))
            let sway = 6 * sin(time * 0.8 + Double(i) * 1.7)
            var weed = Path()
            weed.move(to: CGPoint(x: x, y: height))
            weed.addQuadCurve(to: CGPoint(x: x + sway, y: height - tall), control: CGPoint(x: x - sway * 0.6, y: height - tall * 0.5))
            context.stroke(weed, with: .color(Self.weed.opacity(0.3)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        }
        for crumb in pond.crumbs {
            let p = crumb.position
            context.fill(Path(ellipseIn: CGRect(x: Double(p.x) - 2.5, y: Double(p.y) - 2.5, width: 5, height: 5)), with: .color(Self.crumb))
        }
        for bubble in pond.bubbles {
            let p = bubble.position
            let r = bubble.radius
            context.stroke(Path(ellipseIn: CGRect(x: Double(p.x) - r, y: Double(p.y) - r, width: 2 * r, height: 2 * r)),
                           with: .color(Self.bubble.opacity(max(0, 0.7 - bubble.age * 0.2))), lineWidth: 0.8)
        }
        for creature in pond.creatures {
            var ink = context
            ink.opacity = max(0, min(1, creature.fade ?? 1))
            ink.stroke(Self.path(InkPond.pose(creature)), with: .color(GameCorner.ink(creature.ink)), style: Self.line)
        }
        context.stroke(Self.path(model.drawing), with: .color(GameCorner.ink(model.ink)), style: Self.line)
    }

    /// Strokes as one path; a lone point is a dot.
    private static func path(_ strokes: [[CGPoint]]) -> Path {
        var path = Path()
        for stroke in strokes {
            guard let first = stroke.first else { continue }
            path.move(to: first)
            if stroke.count == 1 {
                path.addLine(to: CGPoint(x: Double(first.x) + 0.1, y: Double(first.y)))
            } else {
                for p in stroke.dropFirst() {
                    path.addLine(to: p)
                }
            }
        }
        return path
    }
}
