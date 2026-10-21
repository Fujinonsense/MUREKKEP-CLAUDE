import SwiftUI
import UIKit

/// The app's look, taken from its name: blue-black ink on cool notebook paper. Titles are set in a
/// serif like a textbook's headings; everything else stays in the system font. The AI's colour is the
/// ink family too: indigo running into turquoise, Turkey's classic school ink.
enum Theme {
    /// Wet ink, the accent of every control: #2457D6, lighter at night (#4D7BEA) so it still reads on
    /// the dark paper (contrast 6.2 by day, 4.6 at night).
    static let ink = dynamic(light: UIColor(red: 0.141, green: 0.341, blue: 0.839, alpha: 1),
                             dark: UIColor(red: 0.302, green: 0.482, blue: 0.918, alpha: 1))
    /// Indigo ink (#4B3FD6) and turquoise ink (#177E92): the assistant, the Studio, PDFs. White text
    /// stays above 4.5:1 on both.
    static let aiStart = Color(red: 0.29, green: 0.25, blue: 0.84)
    static let aiEnd = Color(red: 0.09, green: 0.494, blue: 0.573)
    static let ai = LinearGradient(colors: [aiStart, aiEnd], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let paperWarm = Color(red: 0.99, green: 0.98, blue: 0.96)

    /// Notebook paper: cool grey-blue by day (#F3F5F8), deep ink by night (#0E1528).
    static let paper = dynamic(light: UIColor(red: 0.953, green: 0.961, blue: 0.973, alpha: 1),
                               dark: UIColor(red: 0.055, green: 0.082, blue: 0.157, alpha: 1))
    /// The ruled lines of the paper.
    static let rule = dynamic(light: UIColor(red: 0.14, green: 0.34, blue: 0.84, alpha: 0.075),
                              dark: UIColor(white: 1, alpha: 0.045))
    /// Thin edge of cards and panels: ink by day, light by night.
    static let hairline = dynamic(light: UIColor(red: 0.086, green: 0.13, blue: 0.24, alpha: 0.09),
                                  dark: UIColor(white: 1, alpha: 0.10))
    /// Shadows are blue-black ink, not grey.
    static let shadow = Color(red: 0.086, green: 0.13, blue: 0.24)

    /// The ruled paper behind the library.
    static var libraryBackground: some View { RuledPaper() }

    /// A title in the textbook serif (New York).
    static func display(_ style: Font.TextStyle, weight: Font.Weight = .semibold) -> Font {
        .system(style, design: .serif, weight: weight)
    }

    private static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
}

/// Faint notebook lines, drawn once (static, so they cost nothing while scrolling).
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

private struct GlassCapsule: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.regularMaterial, in: Capsule(style: .continuous))
            .overlay(Capsule(style: .continuous).strokeBorder(Theme.hairline, lineWidth: 0.6))
            .shadow(color: Theme.shadow.opacity(0.14), radius: 18, y: 8)
    }
}

private struct GlassCard: ViewModifier {
    var radius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 0.6))
            .shadow(color: Theme.shadow.opacity(0.08), radius: 14, y: 6)
    }
}

extension View {
    func glassCapsule() -> some View {
        modifier(GlassCapsule())
    }

    func glassCard(radius: CGFloat = 22) -> some View {
        modifier(GlassCard(radius: radius))
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
