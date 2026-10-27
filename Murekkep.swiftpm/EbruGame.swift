import SwiftUI

/// The ebru tray's six pigments, by their traditional names, and the water they float on.
enum EbruColors {
    /// Çivit mavisi, lal kırmızısı, zırnık sarısı, yeşil, toprak, beyaz.
    private static let rgb: [(red: Double, green: Double, blue: Double)] = [
        (0.169, 0.247, 0.494), (0.659, 0.196, 0.176), (0.890, 0.698, 0.235),
        (0.247, 0.490, 0.306), (0.541, 0.353, 0.231), (0.961, 0.945, 0.902),
    ]
    static let pigments: [Color] = rgb.map { Color(red: $0.red, green: $0.green, blue: $0.blue) }
    /// Each pigment a little darker, for the fine edge ebru paint dries with.
    static let rims: [Color] = rgb.map { Color(red: $0.red * 0.72, green: $0.green * 0.72, blue: $0.blue * 0.72) }
    /// Water thickened with kitre: a warm grey, the same by day and by night, so white paint shows on it.
    static let water = Color(red: 0.902, green: 0.878, blue: 0.824)

    static var names: [String] {
        [Loc.t("Çivit mavisi"), Loc.t("Lal kırmızısı"), Loc.t("Zırnık sarısı"), Loc.t("Yeşil"), Loc.t("Toprak"), Loc.t("Beyaz")]
    }

    static func pigment(_ index: Int) -> Color { pigments[min(max(index, 0), pigments.count - 1)] }
    static func rim(_ index: Int) -> Color { rims[min(max(index, 0), rims.count - 1)] }
}

extension EbruPattern {
    var title: String {
        switch self {
        case .gelgit: return Loc.t("Gelgit")
        case .tarakli: return Loc.t("Taraklı")
        case .sal: return Loc.t("Şal")
        case .bulbul: return Loc.t("Bülbül yuvası")
        }
    }
}

/// The tray on screen. It is stepped by the animation timeline only while a drop spreads under the
/// pencil or a sprinkle or a pattern plays; `revision` changes with every change, to redraw it.
final class EbruModel: ObservableObject {
    @Published private(set) var revision = 0
    /// Counts the drops a touch has made, for the little tap a drop gives.
    @Published private(set) var drops = 0
    @Published var tool: EbruTool = .drop
    @Published var pigment = 1
    private(set) var tray: EbruTray?
    private var last: Date?

    var isMoving: Bool { tray?.isPlaying == true || tray?.isSpreading == true }
    var canUndo: Bool { tray?.canUndo == true }
    var isEmpty: Bool { tray?.paints.isEmpty ?? true }

    /// Builds the tray for the first size the board has; the drawing scales to later sizes.
    func start(size: CGSize) {
        guard tray == nil, size.width > 0, size.height > 0 else { return }
        tray = EbruTray(size: size, seed: UInt64(max(0, Date().timeIntervalSinceReferenceDate * 1000)))
        changed()
    }

    /// The tray's scale and its offset in a board of `size`, the tray centred in it.
    func fit(in size: CGSize) -> (scale: Double, dx: Double, dy: Double) {
        guard let tray, tray.size.width > 0, tray.size.height > 0 else { return (1, 0, 0) }
        let width = Double(tray.size.width)
        let height = Double(tray.size.height)
        let scale = min(Double(size.width) / width, Double(size.height) / height)
        return (scale, (Double(size.width) - width * scale) / 2, (Double(size.height) - height * scale) / 2)
    }

    /// A point of the board in the tray's own points, kept on the tray (a larger card leaves bands
    /// beside it).
    func trayPoint(_ point: CGPoint, in size: CGSize) -> CGPoint {
        let f = fit(in: size)
        let width = Double(tray?.size.width ?? size.width)
        let height = Double(tray?.size.height ?? size.height)
        return CGPoint(x: min(max((Double(point.x) - f.dx) / f.scale, 0), width), y: min(max((Double(point.y) - f.dy) / f.scale, 0), height))
    }

    func began(at point: CGPoint) {
        last = nil
        tray?.touchBegan(at: point, tool: tool, pigment: pigment)
        if tool == .drop { drops += 1 }
        changed()
    }

    func moved(to point: CGPoint) {
        let before = tray?.paints.count
        tray?.touchMoved(to: point)
        if tool == .drop, tray?.paints.count != before { drops += 1 }
        changed()
    }

    func ended() {
        tray?.touchEnded()
        last = nil
        changed()
    }

    /// Battal: a sprinkle of the chosen colour; at once with Reduce Motion.
    func sprinkle(instantly: Bool) {
        tray?.sprinkle(pigment: pigment)
        if instantly { tray?.finish() }
        last = nil
        changed()
    }

    func play(_ pattern: EbruPattern, instantly: Bool) {
        tray?.play(pattern)
        if instantly { tray?.finish() }
        last = nil
        changed()
    }

    func undo() {
        tray?.undo()
        last = nil
        changed()
    }

    func pause() {
        last = nil
    }

    /// One frame: the next waiting move plays, and a drop under the pencil spreads by the time since
    /// the last frame.
    func advance(to now: Date) {
        guard tray != nil else { return }
        let dt = last.map { now.timeIntervalSince($0) } ?? 0
        last = now
        let played = tray?.advance() == true
        let spread = dt > 0 && tray?.hold(for: dt) == true
        if played || spread { changed() }
    }

    private func changed() {
        revision &+= 1
    }
}

/// Ebru: paint dropped on the water spreads and pushes the rest aside; the needle and the comb pull
/// it into lines; a traditional pattern can play over it. The pencil draws here like a finger.
struct EbruGame: View {
    @StateObject private var model = EbruModel()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Where the touch under way began: a touch from somewhere else is a new one, even when the last
    /// one was cancelled without ending.
    @State private var touchStart: CGPoint?
    /// True while a finger or the pencil is down; it falls back by itself when the system cancels the
    /// touch, which then lifts the tool as a lift would (a held drop stops spreading).
    @GestureState private var pressing = false

    private var paused: Bool { scenePhase != .active || !model.isMoving }

    var body: some View {
        VStack(spacing: 8) {
            board
            HStack(spacing: 4) {
                swatches
                Spacer(minLength: 0)
                Button {
                    model.undo()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(model.canUndo ? Theme.ink : Color.secondary.opacity(0.4))
                .disabled(!model.canUndo)
                .accessibilityLabel(Loc.t("Geri al"))
            }
            HStack(spacing: 8) {
                Picker(Loc.t("Araç"), selection: $model.tool) {
                    Text(Loc.t("Damla")).tag(EbruTool.drop)
                    Text(Loc.t("Biz")).tag(EbruTool.needle)
                    Text(Loc.t("Tarak")).tag(EbruTool.comb)
                }
                .pickerStyle(.segmented)
                .accessibilityLabel(Loc.t("Araç"))
                Button(Loc.t("Serp")) {
                    model.sprinkle(instantly: reduceMotion)
                }
                .buttonStyle(.bordered)
                .tint(Theme.ink)
                .accessibilityHint(Loc.t("Seçili renkten tablanın her yerine damlalar serper."))
                Menu {
                    ForEach(EbruPattern.allCases) { pattern in
                        Button(pattern.title) {
                            model.play(pattern, instantly: reduceMotion)
                        }
                    }
                } label: {
                    Text(Loc.t("Desen"))
                }
                .menuStyle(.button)
                .buttonStyle(.bordered)
                .tint(Theme.ink)
                .disabled(model.isEmpty)
            }
            .font(.subheadline.weight(.semibold))
        }
        .onChange(of: paused) { _, stopped in
            if stopped { model.pause() }
        }
        .sensoryFeedback(.impact(weight: .light, intensity: 0.45), trigger: model.drops)
    }

    private var board: some View {
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
                    model.start(size: size)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .local)
                        .updating($pressing) { _, down, _ in down = true }
                        .onChanged { value in
                            let point = model.trayPoint(value.location, in: geo.size)
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
                .onChange(of: pressing) { _, down in
                    if !down, touchStart != nil {
                        touchStart = nil
                        model.ended()
                    }
                }
            }
            .accessibilityLabel(Loc.t("Ebru teknesi"))
            if model.isEmpty {
                Text(Loc.t("Dokun, boya damlasın; basılı tut, yayılsın. Ya da Serp'e bas."))
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

    private var swatches: some View {
        HStack(spacing: 4) {
            ForEach(EbruColors.pigments.indices, id: \.self) { i in
                Button {
                    model.pigment = i
                    model.tool = .drop
                } label: {
                    Circle()
                        .fill(EbruColors.pigment(i))
                        .overlay(Circle().strokeBorder(EbruColors.rim(i).opacity(0.6), lineWidth: 0.8))
                        .frame(width: 26, height: 26)
                        .padding(3)
                        .overlay(Circle().strokeBorder(model.pigment == i ? Theme.ink : Color.clear, lineWidth: 2))
                        .frame(width: 40, height: 40)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(EbruColors.names[i])
                .accessibilityAddTraits(model.pigment == i ? .isSelected : [])
            }
        }
    }

    /// The water, then every colour as it lies on it, each with its fine edge.
    private func draw(_ context: inout GraphicsContext, size: CGSize) {
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(EbruColors.water))
        guard let tray = model.tray else { return }
        let f = model.fit(in: size)
        context.translateBy(x: CGFloat(f.dx), y: CGFloat(f.dy))
        context.scaleBy(x: CGFloat(f.scale), y: CGFloat(f.scale))
        context.clip(to: Path(CGRect(origin: .zero, size: tray.size)))
        for paint in tray.paints {
            var path = Path()
            path.addLines(paint.outline)
            path.closeSubpath()
            context.fill(path, with: .color(EbruColors.pigment(paint.pigment)))
            context.stroke(path, with: .color(EbruColors.rim(paint.pigment).opacity(0.55)), lineWidth: 0.6)
        }
    }
}
