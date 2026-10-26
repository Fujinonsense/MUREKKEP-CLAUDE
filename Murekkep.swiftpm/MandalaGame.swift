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
    @State private var live: [CGPoint] = []
    @State private var liveHue = 0.0

    /// The slate the ink glows on, night paper in both modes.
    private static let board = Color(red: 0.055, green: 0.082, blue: 0.157)
    private static let glow = StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round)
    private static let core = StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                Canvas { context, size in
                    draw(&context, size: size)
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
                    live = []
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
                .disabled(petals.isEmpty && live.isEmpty)
            }
        }
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize) {
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        // Faint rings to draw around.
        for fraction in [0.18, 0.36] {
            let radius = min(size.width, size.height) * CGFloat(fraction)
            let rect = CGRect(x: centre.x - radius, y: centre.y - radius, width: 2 * radius, height: 2 * radius)
            context.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(0.05)), lineWidth: 0.7)
        }
        let livePaths = MandalaPetals.paths(for: live, around: centre)
        let liveColor = MandalaPetals.color(hue: liveHue)
        // The glow: the strokes blurred under themselves.
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 5))
            for petal in petals {
                for path in petal.paths {
                    layer.stroke(path, with: .color(petal.color.opacity(0.6)), style: Self.glow)
                }
            }
            for path in livePaths {
                layer.stroke(path, with: .color(liveColor.opacity(0.6)), style: Self.glow)
            }
        }
        for petal in petals {
            for path in petal.paths {
                context.stroke(path, with: .color(petal.color), style: Self.core)
            }
        }
        for path in livePaths {
            context.stroke(path, with: .color(liveColor), style: Self.core)
        }
    }

    private func finish(centre: CGPoint) {
        guard !live.isEmpty else { return }
        petals.append(MandalaPetals(paths: MandalaPetals.paths(for: live, around: centre), color: MandalaPetals.color(hue: liveHue)))
        live = []
    }
}
