import SwiftUI
import UIKit

/// Shared look: ink blue accent, an indigo→teal gradient for the assistant, frosted glass surfaces.
enum Theme {
    static let ink = Color(red: 0.10, green: 0.33, blue: 0.80)
    static let aiStart = Color(red: 0.45, green: 0.30, blue: 0.96)
    static let aiEnd = Color(red: 0.07, green: 0.64, blue: 0.84)
    static let ai = LinearGradient(colors: [aiStart, aiEnd], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let paperWarm = Color(red: 0.99, green: 0.98, blue: 0.96)

    static let libraryBackground = LinearGradient(
        colors: [Color(uiColor: .systemGroupedBackground), Color(uiColor: .secondarySystemGroupedBackground)],
        startPoint: .top, endPoint: .bottom)
}

private struct GlassCapsule: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.regularMaterial, in: Capsule(style: .continuous))
            .overlay(Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.35), lineWidth: 0.6))
            .shadow(color: .black.opacity(0.14), radius: 18, y: 8)
    }
}

private struct GlassCard: ViewModifier {
    var radius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Color.white.opacity(0.3), lineWidth: 0.6))
            .shadow(color: .black.opacity(0.10), radius: 14, y: 6)
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
