import SwiftUI

/// A finished stroke of the mandala, its sixteen copies ready to draw.
private struct MandalaPetals {
    let paths: [Path]
    let color: Color

    /// The copies of a stroke of `points` around `centre`, one path each; a lone point becomes a dot.
    static func paths(for points: [CGPoint], around centre: CGPoint) -> [Path] {
        guard let first = points.first else { return [] }
        var paths = MandalaSymmetry.copies(of: first, around: centre).map { start -> Path in
            var path = Path()
            path.move(to: start)
            return path
        }
        for point in points.count == 1 ? points : Array(points.dropFirst()) {
            for (i, copy) in MandalaSymmetry.copies(of: point, around: centre).enumerated() {
                paths[i].addLine(to: copy)
            }
        }
        return paths
    }

    static func color(hue: Double) -> Color {
        Color(hue: hue, saturation: 0.55, brightness: 1)
    }
}

/// The ink mandala: draw with the pencil or a finger; every line opens eightfold around the centre
/// in a soft, glowing ink whose colour drifts slowly. No score, nothing to lose.
struct InkMandalaGame: View {
    @State private var petals: [MandalaPetals] = []
    /// Counts the changes to `petals`, so their layers redraw only then.
    @State private var revision = 0
    @State private var live: [CGPoint] = []
    @State private var liveHue = 0.0

    /// The slate the ink glows on, night paper in both modes.
    private static let board = Color(red: 0.055, green: 0.082, blue: 0.157)
    fileprivate static let glow = StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round)
    fileprivate static let core = StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                // Glows under lines, finished under live, as one picture. The finished petals redraw
                // only when one is added or the slate is cleared: redrawing every petal, blur and all,
                // on each touch grew heavier with every stroke until the panel froze.
                let livePaths = MandalaPetals.paths(for: live, around: CGPoint(x: geo.size.width / 2, y: geo.size.height / 2))
                let liveColor = MandalaPetals.color(hue: liveHue)
                ZStack {
                    MandalaLayer(petals: petals, revision: revision, part: .glow).equatable()
                    Canvas { context, _ in
                        MandalaLayer.glow(livePaths, color: liveColor, in: &context)
                    }
                    MandalaLayer(petals: petals, revision: revision, part: .core).equatable()
                    Canvas { context, _ in
                        MandalaLayer.core(livePaths, color: liveColor, in: &context)
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .local)
                        .onChanged { value in
                            if live.isEmpty {
                                liveHue = MandalaSymmetry.hue(at: Date().timeIntervalSinceReferenceDate)
                            }
                            live.append(value.location)
                        }
                        .onEnded { _ in
                            finish(centre: CGPoint(x: geo.size.width / 2, y: geo.size.height / 2))
                        }
                )
            }
            .background(Self.board, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityLabel(Loc.t("Mandala tuvali"))
            HStack {
                Text(Loc.t("Çiz; her çizgi sekiz kat açılır."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button(Loc.t("Temizle")) {
                    petals = []
                    revision += 1
                    live = []
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
                .disabled(petals.isEmpty && live.isEmpty)
            }
        }
    }

    private func finish(centre: CGPoint) {
        guard !live.isEmpty else { return }
        petals.append(MandalaPetals(paths: MandalaPetals.paths(for: live, around: centre), color: MandalaPetals.color(hue: liveHue)))
        revision += 1
        live = []
    }
}

/// The finished petals' glows (over the faint rings) or their lines, redrawn only when `revision` moves.
private struct MandalaLayer: View, Equatable {
    enum Part { case glow, core }

    let petals: [MandalaPetals]
    let revision: Int
    let part: Part

    static func == (a: MandalaLayer, b: MandalaLayer) -> Bool {
        a.revision == b.revision && a.part == b.part
    }

    var body: some View {
        Canvas { context, size in
            switch part {
            case .glow:
                // Faint rings to draw around.
                let centre = CGPoint(x: size.width / 2, y: size.height / 2)
                for fraction in [0.18, 0.36] {
                    let radius = min(size.width, size.height) * CGFloat(fraction)
                    let rect = CGRect(x: centre.x - radius, y: centre.y - radius, width: 2 * radius, height: 2 * radius)
                    context.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(0.05)), lineWidth: 0.7)
                }
                for petal in petals { Self.glow(petal.paths, color: petal.color, in: &context) }
            case .core:
                for petal in petals { Self.core(petal.paths, color: petal.color, in: &context) }
            }
        }
    }

    /// The glow: the strokes blurred under themselves.
    static func glow(_ paths: [Path], color: Color, in context: inout GraphicsContext) {
        guard !paths.isEmpty else { return }
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 5))
            for path in paths {
                layer.stroke(path, with: .color(color.opacity(0.6)), style: InkMandalaGame.glow)
            }
        }
    }

    static func core(_ paths: [Path], color: Color, in context: inout GraphicsContext) {
        for path in paths {
            context.stroke(path, with: .color(color), style: InkMandalaGame.core)
        }
    }
}
