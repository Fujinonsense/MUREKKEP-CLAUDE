import SwiftUI
import UIKit

/// The backgrounds behind the library: plain colours for everyone, and in Mürekkep Pro creative ones
/// made from the app's world — Turkish paper marbling (ebru), school ink running into turquoise, a
/// night sky, the sea, the northern lights, cherry blossom, gold leaf and the ruled notebook. The
/// moving ones move only in the library and stand still with Low Power Mode, Reduce Motion or the
/// app's animations off.
enum AppBackground: String, CaseIterable, Identifiable, Codable {
    case paper
    case ivory
    case sand
    case sage
    case lavender
    case night
    case ruled
    case ebru
    case inkFlow
    case starlight
    case sea
    case aurora
    case sakura
    case goldLeaf

    var id: String { rawValue }

    var isPremium: Bool {
        switch self {
        case .paper, .ivory, .sand, .sage, .lavender, .night: return false
        default: return true
        }
    }

    var title: String {
        switch self {
        case .paper: return Loc.t("Kâğıt")
        case .ivory: return Loc.t("Fildişi")
        case .sand: return Loc.t("Kum")
        case .sage: return Loc.t("Adaçayı")
        case .lavender: return Loc.t("Lavanta")
        case .night: return Loc.t("Gece")
        case .ruled: return Loc.t("Defter")
        case .ebru: return Loc.t("Ebru")
        case .inkFlow: return Loc.t("Mürekkep akışı")
        case .starlight: return Loc.t("Yıldız ışığı")
        case .sea: return Loc.t("Deniz")
        case .aurora: return Loc.t("Kuzey ışıkları")
        case .sakura: return "Sakura"
        case .goldLeaf: return Loc.t("Altın varak")
        }
    }

    var moves: Bool {
        switch self {
        case .inkFlow, .starlight, .sea, .aurora, .sakura: return true
        default: return false
        }
    }

    /// Dark backgrounds turn the library's text and controls light.
    var isDark: Bool {
        switch self {
        case .night, .inkFlow, .starlight, .aurora, .goldLeaf: return true
        default: return false
        }
    }

    static var free: [AppBackground] { allCases.filter { !$0.isPremium } }
    static var premium: [AppBackground] { allCases.filter(\.isPremium) }
}

/// One background, drawn to fill its space. `animated` is false outside the library; `preview` draws
/// the ruled paper's lines close together for a small tile.
struct AppBackgroundView: View {
    let kind: AppBackground
    var animated = true
    var preview = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var moving: Bool {
        animated && kind.moves && !reduceMotion && !ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    var body: some View {
        Group {
            switch kind {
            case .paper: Theme.paper
            case .ivory: Self.solid(light: (0.984, 0.965, 0.918), dark: (0.118, 0.106, 0.086))
            case .sand: Self.solid(light: (0.937, 0.902, 0.831), dark: (0.165, 0.141, 0.106))
            case .sage: Self.solid(light: (0.890, 0.922, 0.882), dark: (0.094, 0.133, 0.110))
            case .lavender: Self.solid(light: (0.925, 0.910, 0.961), dark: (0.114, 0.102, 0.169))
            case .night: Color(red: 0.055, green: 0.082, blue: 0.157)
            case .ruled: preview ? RuledPaper(spacing: 11, top: 9) : RuledPaper()
            case .ebru: EbruBackground()
            case .inkFlow: InkFlowBackground(moving: moving)
            case .starlight: StarlightBackground(moving: moving)
            case .sea: SeaBackground(moving: moving)
            case .aurora: AuroraBackground(moving: moving)
            case .sakura: SakuraBackground(moving: moving)
            case .goldLeaf: GoldLeafBackground()
            }
        }
        .accessibilityHidden(true)
    }

    private static func solid(light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
        Color(uiColor: UIColor { trait in
            let c = trait.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
        })
    }
}

/// The chosen background behind the library, with light text over the dark ones. A Pro background
/// shows as paper while Pro is locked; the moving ones stand still with the app's animations off or
/// battery saving on.
struct LibraryBackdrop: ViewModifier {
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject private var pro = ProStore.shared
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let kind = settings.shownBackground(locked: pro.locks)
        content
            .environment(\.colorScheme, kind.isDark ? .dark : scheme)
            .background {
                AppBackgroundView(kind: kind, animated: settings.animations && !settings.batterySaver)
                    .ignoresSafeArea()
            }
    }
}

/// The background tiles in Settings: plain colours for everyone, the creative ones with a lock until
/// Pro.
struct AppBackgroundPicker: View {
    @Binding var selection: AppBackground
    @ObservedObject private var pro = ProStore.shared
    private let columns = [GridItem(.adaptive(minimum: 104, maximum: 140), spacing: 12)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
            ForEach(AppBackground.allCases) { kind in
                tile(kind)
            }
        }
    }

    private func tile(_ kind: AppBackground) -> some View {
        let chosen = selection == kind
        let locked = kind.isPremium && pro.locks
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return Button {
            if locked {
                _ = pro.unlock(.premiumBackground)
            } else {
                selection = kind
            }
        } label: {
            VStack(spacing: 6) {
                AppBackgroundView(kind: kind, animated: false, preview: true)
                    .frame(height: 68)
                    .clipShape(shape)
                    .overlay(shape.strokeBorder(chosen ? Theme.ink : Theme.hairline, lineWidth: chosen ? 2.5 : 0.6))
                    .overlay(alignment: .topTrailing) {
                        if locked {
                            ProLockBadge()
                                .padding(6)
                        } else if chosen {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.callout)
                                .foregroundStyle(Color.white, Theme.ink)
                                .padding(5)
                        }
                    }
                Text(kind.title)
                    .font(.caption)
                    .foregroundStyle(chosen ? Color.primary : Color.secondary)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(kind.title)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}

/// The small lock on Pro-only pens, templates and backgrounds.
struct ProLockBadge: View {
    var body: some View {
        Image(systemName: "lock.fill")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(Color.white)
            .frame(width: 18, height: 18)
            .background(Theme.ink, in: Circle())
            .overlay(Circle().strokeBorder(Color.white.opacity(0.9), lineWidth: 1))
            .accessibilityLabel(Text(verbatim: "Mürekkep Pro"))
    }
}

// MARK: - Ebru

/// Turkish paper marbling (battal and gel-git ebru), made once and kept in Caches: on a cream bath
/// rings of ochre, indigo, crimson, turquoise and cream are dropped one into another at 25 places,
/// then the bath is combed back and forth across and gently along. Each pixel is traced back through
/// the combs and the drops to the colour that landed there (Jaffer's mathematical marbling). A thin
/// wash of paper keeps text on it readable.
struct EbruBackground: View {
    @Environment(\.colorScheme) private var scheme
    @State private var image: UIImage? = Ebru.cached

    var body: some View {
        // The bath colour takes the space it is given; the sheet fills it from an overlay, so a
        // square image never makes the view taller than its frame.
        Color(red: 0.945, green: 0.910, blue: 0.847)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
            }
            .overlay(scheme == .dark ? Color.black.opacity(0.45) : Theme.paperWarm.opacity(0.42))
            .clipped()
            .task {
                if image == nil { image = await Ebru.make() }
            }
    }
}

enum Ebru {
    @MainActor static var cached: UIImage?

    /// Indigo, cream, ochre, ink, cream, turquoise and crimson, dropped in this order.
    private static let palette: [(Double, Double, Double)] = [
        (0.165, 0.231, 0.561), (0.953, 0.922, 0.867), (0.784, 0.576, 0.169), (0.118, 0.165, 0.353),
        (0.953, 0.922, 0.867), (0.090, 0.494, 0.573), (0.620, 0.169, 0.145),
    ]
    private static let bath = (0.945, 0.910, 0.847)
    private static let grid = 5
    private static let rings = 12
    private static let radius = 0.045

    private struct Drop {
        var x: Double
        var y: Double
        var colour: (Double, Double, Double)
    }

    /// A comb drawn back and forth: the bath moves along (dx, dy) by a sine of the distance across.
    private struct Wave {
        var dx: Double
        var dy: Double
        var spacing: Double
        var amplitude: Double
        var phase: Double
    }

    private static let waves = [
        Wave(dx: 0, dy: 1, spacing: 0.12, amplitude: 0.09, phase: 0),
        Wave(dx: 1, dy: 0, spacing: 0.25, amplitude: 0.05, phase: 1.2),
    ]

    private static var file: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("ebru-v1.png")
    }

    @MainActor
    static func make(size: Int = 1024) async -> UIImage? {
        if let cached { return cached }
        let made = await Task.detached(priority: .utility) { () -> UIImage? in
            let url = Ebru.file
            if let url, let saved = UIImage(contentsOfFile: url.path) { return saved }
            guard let image = Ebru.render(size: size) else { return nil }
            if let url { try? image.pngData()?.write(to: url, options: .atomic) }
            return image
        }.value
        cached = made
        return made
    }

    private static func drops() -> [Drop] {
        var seed: UInt64 = 0x9E3779B97F4A7C15
        func random() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 11) / Double(UInt64(1) << 53)
        }
        let step = 1 / Double(grid - 1)
        var out: [Drop] = []
        for gy in 0..<grid {
            for gx in 0..<grid {
                let cx = (Double(gx) + 0.5 * Double(gy % 2)) * step + (random() - 0.5) * step * 0.4 - step * 0.25
                let cy = Double(gy) * step + (random() - 0.5) * step * 0.4
                for k in 0..<rings {
                    out.append(Drop(x: cx, y: cy, colour: palette[(k + gx * 2 + gy) % palette.count]))
                }
            }
        }
        return out
    }

    /// The colour that ends up at (x, y) on the sheet.
    private static func colour(x startX: Double, y startY: Double, drops: [Drop]) -> (Double, Double, Double) {
        var x = startX
        var y = startY
        // Back through the combs, last first. The pull runs along the comb and depends only on the
        // distance across it, so undoing it is exact.
        for wave in waves.reversed() {
            let across = x * wave.dy - y * wave.dx
            let z = wave.amplitude * sin(Double.pi * across / wave.spacing + wave.phase)
            x -= z * wave.dx
            y -= z * wave.dy
        }
        // Back through the drops, the last one on top: a drop pushes what was there outward.
        let r2 = radius * radius
        for drop in drops.reversed() {
            let ex = x - drop.x
            let ey = y - drop.y
            let d2 = ex * ex + ey * ey
            if d2 < r2 { return drop.colour }
            let k = (1 - r2 / d2).squareRoot()
            x = drop.x + ex * k
            y = drop.y + ey * k
        }
        return bath
    }

    private static func render(size: Int) -> UIImage? {
        let drops = drops()
        var pixels = [UInt8](repeating: 255, count: size * size * 4)
        // Rows on every core: each writes only its own row.
        pixels.withUnsafeMutableBufferPointer { buffer in
            guard let out = buffer.baseAddress else { return }
            DispatchQueue.concurrentPerform(iterations: size) { py in
                for px in 0..<size {
                    let c = colour(x: (Double(px) + 0.5) / Double(size), y: (Double(py) + 0.5) / Double(size), drops: drops)
                    let i = (py * size + px) * 4
                    out[i] = UInt8(c.0 * 255)
                    out[i + 1] = UInt8(c.1 * 255)
                    out[i + 2] = UInt8(c.2 * 255)
                }
            }
        }
        let data = Data(pixels) as CFData
        guard let provider = CGDataProvider(data: data),
              let cg = CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: size * 4,
                               space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                               provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

// MARK: - Moving backgrounds

/// School ink running into turquoise, slowly (a mesh gradient on iPadOS 18, a still blend before).
struct InkFlowBackground: View {
    var moving: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: !moving)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            if #available(iOS 18.0, *) {
                MeshGradient(width: 3, height: 3, points: Self.points(t), colors: [
                    Color(red: 0.05, green: 0.07, blue: 0.20), Color(red: 0.16, green: 0.20, blue: 0.62), Color(red: 0.05, green: 0.10, blue: 0.24),
                    Color(red: 0.20, green: 0.16, blue: 0.62), Color(red: 0.09, green: 0.45, blue: 0.55), Color(red: 0.12, green: 0.25, blue: 0.70),
                    Color(red: 0.04, green: 0.08, blue: 0.18), Color(red: 0.07, green: 0.36, blue: 0.45), Color(red: 0.06, green: 0.09, blue: 0.22),
                ])
            } else {
                LinearGradient(colors: [Color(red: 0.05, green: 0.07, blue: 0.20), Theme.aiStart, Theme.aiEnd],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
    }

    private static func points(_ t: Double) -> [SIMD2<Float>] {
        let a = Float(sin(t * 0.21) * 0.12)
        let b = Float(cos(t * 0.17) * 0.12)
        return [
            [0, 0], [0.5, 0], [1, 0],
            [0, 0.5 + b], [0.5 + a, 0.5 - b], [1, 0.5 + a],
            [0, 1], [0.5 - a, 1], [1, 1],
        ]
    }
}

/// The northern lights over a dark sky.
struct AuroraBackground: View {
    var moving: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: !moving)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            if #available(iOS 18.0, *) {
                let a = Float(sin(t * 0.13) * 0.15)
                let b = Float(cos(t * 0.11) * 0.12)
                MeshGradient(width: 3, height: 3, points: [
                    [0, 0], [0.5, 0], [1, 0],
                    [0, 0.45 + b], [0.5 + a, 0.4], [1, 0.5 - b],
                    [0, 1], [0.5, 1], [1, 1],
                ], colors: [
                    Color(red: 0.02, green: 0.05, blue: 0.10), Color(red: 0.04, green: 0.10, blue: 0.16), Color(red: 0.03, green: 0.05, blue: 0.12),
                    Color(red: 0.10, green: 0.65, blue: 0.45), Color(red: 0.30, green: 0.85, blue: 0.60), Color(red: 0.45, green: 0.25, blue: 0.70),
                    Color(red: 0.02, green: 0.06, blue: 0.10), Color(red: 0.05, green: 0.12, blue: 0.18), Color(red: 0.08, green: 0.05, blue: 0.16),
                ])
            } else {
                LinearGradient(colors: [Color(red: 0.02, green: 0.05, blue: 0.10), Color(red: 0.10, green: 0.55, blue: 0.40),
                                        Color(red: 0.08, green: 0.05, blue: 0.16)],
                               startPoint: .top, endPoint: .bottom)
            }
        }
    }
}

/// A deep ink sky whose stars breathe; the stars stay where they are, so the sky is the same each time.
struct StarlightBackground: View {
    var moving: Bool

    private static let stars: [(x: Double, y: Double, r: Double, phase: Double)] = {
        var seed: UInt64 = 42
        func random() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 11) / Double(1 << 53)
        }
        return (0..<220).map { _ in (x: random(), y: random(), r: 0.4 + random() * 1.4, phase: random() * 6.28) }
    }()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 15, paused: !moving)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .linearGradient(Gradient(colors: [Color(red: 0.03, green: 0.05, blue: 0.14), Color(red: 0.10, green: 0.14, blue: 0.32)]),
                                               startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
                for star in Self.stars {
                    let glow: Double = 0.55 + 0.45 * sin(t * 0.8 + star.phase)
                    let x = CGFloat(star.x) * size.width
                    let y = CGFloat(star.y) * size.height
                    let r = CGFloat(star.r)
                    ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)),
                             with: .color(.white.opacity(glow * 0.9)))
                }
            }
        }
    }
}

/// Layers of sea rolling slowly under a pale sky.
struct SeaBackground: View {
    var moving: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 24, paused: !moving)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .linearGradient(Gradient(colors: [Color(red: 0.86, green: 0.93, blue: 0.97), Color(red: 0.62, green: 0.82, blue: 0.90)]),
                                               startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
                let layers: [(level: Double, amp: Double, len: Double, speed: Double, colour: Color)] = [
                    (0.55, 18, 520, 0.25, Color(red: 0.34, green: 0.65, blue: 0.80).opacity(0.55)),
                    (0.65, 22, 430, -0.32, Color(red: 0.16, green: 0.50, blue: 0.68).opacity(0.65)),
                    (0.76, 16, 360, 0.40, Color(red: 0.07, green: 0.36, blue: 0.55).opacity(0.75)),
                    (0.87, 12, 300, -0.5, Color(red: 0.04, green: 0.25, blue: 0.42).opacity(0.85)),
                ]
                for layer in layers {
                    var wave = Path()
                    let base = Double(size.height) * layer.level
                    wave.move(to: CGPoint(x: 0, y: size.height))
                    var x: Double = 0
                    while x <= Double(size.width) + 8 {
                        let phase: Double = x / layer.len * 2 * Double.pi + t * layer.speed
                        let y: Double = base + layer.amp * sin(phase)
                        wave.addLine(to: CGPoint(x: x, y: y))
                        x += 8
                    }
                    wave.addLine(to: CGPoint(x: size.width, y: size.height))
                    wave.closeSubpath()
                    ctx.fill(wave, with: .color(layer.colour))
                }
            }
        }
    }
}

/// Cherry blossom drifting over warm paper.
struct SakuraBackground: View {
    var moving: Bool

    private static let petals: [(x: Double, speed: Double, size: Double, sway: Double, phase: Double)] = {
        var seed: UInt64 = 7
        func random() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 11) / Double(1 << 53)
        }
        return (0..<36).map { _ in
            (x: random(), speed: 0.015 + random() * 0.025, size: 5 + random() * 6, sway: 20 + random() * 30, phase: random())
        }
    }()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 24, paused: !moving)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .linearGradient(Gradient(colors: [Color(red: 0.99, green: 0.96, blue: 0.95), Color(red: 0.98, green: 0.88, blue: 0.90)]),
                                               startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)))
                for petal in Self.petals {
                    let fall: Double = (petal.phase + t * petal.speed).truncatingRemainder(dividingBy: 1)
                    let y: Double = fall * (Double(size.height) + 40) - 20
                    let x: Double = petal.x * Double(size.width) + petal.sway * sin(t * 0.6 + petal.phase * 6.28)
                    let angle: Double = t * 0.5 + petal.phase * 6.28
                    var shape = Path(ellipseIn: CGRect(x: -petal.size, y: -petal.size * 0.6, width: 2 * petal.size, height: 1.2 * petal.size))
                    shape = shape.applying(CGAffineTransform(rotationAngle: CGFloat(angle)))
                        .applying(CGAffineTransform(translationX: CGFloat(x), y: CGFloat(y)))
                    ctx.fill(shape, with: .color(Color(red: 0.96, green: 0.62, blue: 0.70).opacity(0.75)))
                }
            }
        }
    }
}

// MARK: - Still backgrounds

/// Flakes of gold leaf on dark ink paper.
struct GoldLeafBackground: View {
    private static let flakes: [(x: Double, y: Double, s: Double, a: Double)] = {
        var seed: UInt64 = 1453
        func random() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 11) / Double(1 << 53)
        }
        return (0..<90).map { _ in (x: random(), y: random(), s: 2 + random() * 9, a: random() * 3.14) }
    }()

    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.06, green: 0.08, blue: 0.14)))
            let gold = Gradient(colors: [Color(red: 0.98, green: 0.84, blue: 0.47), Color(red: 0.72, green: 0.52, blue: 0.18)])
            for flake in Self.flakes {
                let cx = flake.x * Double(size.width)
                let cy = flake.y * Double(size.height)
                var p = Path()
                for k in 0..<5 {
                    let angle: Double = flake.a + Double(k) * 1.256 + (k % 2 == 0 ? 0.2 : -0.15)
                    let r: Double = flake.s * (k % 2 == 0 ? 1 : 0.6)
                    let pt = CGPoint(x: cx + r * cos(angle), y: cy + r * sin(angle))
                    if k == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                }
                p.closeSubpath()
                ctx.fill(p, with: .linearGradient(gold, startPoint: CGPoint(x: cx - flake.s, y: cy - flake.s),
                                                  endPoint: CGPoint(x: cx + flake.s, y: cy + flake.s)))
            }
        }
    }
}
