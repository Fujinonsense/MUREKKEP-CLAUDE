import SwiftUI
import UIKit

/// The app's look: black ink on plain paper, greys with no colour in them, and the brand's ink blue
/// only where something is chosen or in focus. Everything is set in the system font. Surfaces lie
/// flat with a one-point hairline; a shadow falls only from what floats (the pen bar, a popover, a
/// menu), and a small one from the plates on a Pro theme's picture. The values are the zen spec's
/// (docs/superpowers/specs/2026-10-29-zen-arayuz-design.md); a Pro theme lays its picture behind the
/// library and may use a material over it.
enum Theme {
    /// Wet ink, the accent of every control: #2457D6, lighter at night (#4D7BEA) so it still reads on
    /// the dark paper (contrast 6.2 by day, 4.6 at night).
    static let ink = dynamic(light: UIColor(red: 0.141, green: 0.341, blue: 0.839, alpha: 1),
                             dark: UIColor(red: 0.302, green: 0.482, blue: 0.918, alpha: 1))
    /// The assistant, the Studio, PDFs: once an indigo-to-turquoise gradient, flat ink now. The two
    /// ends are the same colour, so everything drawn with them is a plain fill.
    static let aiStart = ink
    static let aiEnd = ink
    static let ai = LinearGradient(colors: [ink, ink], startPoint: .topLeading, endPoint: .bottomTrailing)
    /// The warm bath under the Pro themes' pictures.
    static let paperWarm = Color(red: 0.99, green: 0.98, blue: 0.96)

    // MARK: Paper

    /// Surfaces: the library, the pen bar, cards and popovers (#FDFDFC; #2A2B2E at night).
    static let paper = dynamic(light: grey(0xFD, 0xFD, 0xFC), dark: grey(0x2A, 0x2B, 0x2E))
    /// Bars and the sidebar (#F6F6F4; #202124).
    static let paper2 = dynamic(light: grey(0xF6, 0xF6, 0xF4), dark: grey(0x20, 0x21, 0x24))
    /// The ground under the page, and a chosen row (#EDEDEA; #151618).
    static let paper3 = dynamic(light: grey(0xED, 0xED, 0xEA), dark: grey(0x15, 0x16, 0x18))

    // MARK: Text

    /// Titles and text (#141414; #F2F3F5).
    static let text = dynamic(light: grey(0x14, 0x14, 0x14), dark: grey(0xF2, 0xF3, 0xF5))
    /// Body text and icons (#2E2E2E; #D7D9DC).
    static let text2 = dynamic(light: grey(0x2E, 0x2E, 0x2E), dark: grey(0xD7, 0xD9, 0xDC))
    /// Secondary text (#565656; #A9ACB1). A plain colour, not the vibrant `.secondary`: over a
    /// material `.secondary` is drawn against what lies behind, and inside the break panel's clipped
    /// game area there was nothing, so the games' grey lines were not drawn at all.
    static let muted = dynamic(light: grey(0x56, 0x56, 0x56), dark: grey(0xA9, 0xAC, 0xB1))
    /// Writing laid over the page itself (the page counter); the page stays white at night too.
    static let onPage = Color(red: 0.337, green: 0.337, blue: 0.337)

    // MARK: Lines and shadows

    /// The thin edge of every surface (#DFDFDC; #43454A).
    static let hairline = dynamic(light: grey(0xDF, 0xDF, 0xDC), dark: grey(0x43, 0x45, 0x4A))
    /// The ruled lines of the notebook paper (the Pro "Defter" theme).
    static let rule = dynamic(light: UIColor(white: 0, alpha: 0.08), dark: UIColor(white: 1, alpha: 0.07))
    /// Shadows are plain black, thinned by each use.
    static let shadow = Color.black
    /// What floats casts this: 0 12 32 at 12 % with an edge of 0 1 2 at 8 %, deeper at night.
    static let floatShadow = dynamic(light: UIColor(white: 0, alpha: 0.12), dark: UIColor(white: 0, alpha: 0.45))
    static let floatShadowEdge = dynamic(light: UIColor(white: 0, alpha: 0.08), dark: UIColor(white: 0, alpha: 0.30))

    // MARK: On a Pro theme's picture

    /// The plate under what would sit straight on a Pro theme's picture in the library (PicturePlate):
    /// paper at 0.92, so the picture stays clear around it.
    static let plate: Color = paper.opacity(0.92)
    /// The plate's small soft shadow, 0 2 12 (radius 6, y 2): black at 12 %, 30 % at night.
    static let plateShadow = dynamic(light: UIColor(white: 0, alpha: 0.12), dark: UIColor(white: 0, alpha: 0.30))

    /// Behind the library: plain paper (a Pro theme's picture comes from AppBackgroundView instead).
    static var libraryBackground: some View { paper }

    /// A title: the system font, bold and tight. No serif.
    static func display(_ style: Font.TextStyle, weight: Font.Weight = .bold) -> Font {
        .system(style, design: .default, weight: weight)
    }

    private static func grey(_ r: Int, _ g: Int, _ b: Int) -> UIColor {
        UIColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
    }

    private static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
}

/// Faint notebook lines on paper, drawn once (static, so they cost nothing while scrolling): the
/// Pro "Defter" theme.
struct RuledPaper: View {
    var spacing: CGFloat = 34
    /// Where the first line runs (below a title).
    var top: CGFloat = 92

    var body: some View {
        Theme.paper
            .overlay {
                Canvas { context, size in
                    var lines = Path()
                    var y = top
                    while y < size.height {
                        lines.move(to: CGPoint(x: 0, y: y))
                        lines.addLine(to: CGPoint(x: size.width, y: y))
                        y += spacing
                    }
                    context.stroke(lines, with: .color(Theme.rule), lineWidth: 0.7)
                }
            }
            .accessibilityHidden(true)
    }
}

/// A capsule that floats over the page (a bar, a banner): paper, a hairline and the floating shadow.
private struct GlassCapsule: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Theme.paper, in: Capsule(style: .continuous))
            .overlay(Capsule(style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
            .floatingShadow()
    }
}

/// A card: paper with a hairline. Resting on a surface it casts no shadow; `floating` (a panel over
/// the page, a banner) it casts the floating shadow.
private struct GlassCard: ViewModifier {
    var radius: CGFloat
    var floating: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return content
            .background(Theme.paper, in: shape)
            .overlay(shape.strokeBorder(Theme.hairline, lineWidth: 1))
            .shadow(color: floating ? Theme.floatShadow : Color.clear, radius: floating ? 16 : 0, y: floating ? 12 : 0)
            .shadow(color: floating ? Theme.floatShadowEdge : Color.clear, radius: floating ? 1 : 0, y: floating ? 1 : 0)
    }
}

extension View {
    func glassCapsule() -> some View {
        modifier(GlassCapsule())
    }

    func glassCard(radius: CGFloat = 22, floating: Bool = false) -> some View {
        modifier(GlassCard(radius: radius, floating: floating))
    }

    /// A rounded panel that floats over the page (the pen bar, a popover's card).
    func floatingPanel(radius: CGFloat = 18) -> some View {
        modifier(GlassCard(radius: radius, floating: true))
    }

    /// The shadow of what floats: 0 12 32 black at 12 % and an edge of 0 1 2 at 8 %.
    func floatingShadow() -> some View {
        shadow(color: Theme.floatShadow, radius: 16, y: 12)
            .shadow(color: Theme.floatShadowEdge, radius: 1, y: 1)
    }

    /// The small soft shadow of a plate on a Pro theme's picture: 0 2 12 (radius 6, y 2), black at
    /// 12 % (30 % at night).
    func plateShadow() -> some View {
        shadow(color: Theme.plateShadow, radius: 6, y: 2)
    }
}

/// Small rounded label used for status chips.
struct Chip: View {
    let text: String
    let symbol: String
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
            Text(text)
                .lineLimit(1)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(tint.opacity(0.12), in: Capsule())
    }
}
