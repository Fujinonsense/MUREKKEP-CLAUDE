import SwiftUI

/// The break corner: a small icon at the bottom-left of the page opens a card of three calm games
/// (the ink mandala, the ink bubbles, XOX against the iPad). Free in every edition; nothing leaves
/// the iPad and nothing is kept but the bubbles' best score. The games' logic is in MiniGameLogic.
enum GameCorner {
    static let panelSize = CGSize(width: 340, height: 420)
    static let radius: CGFloat = 24

    /// The panel springs in and out; with Reduce Motion on it fades.
    static func animation(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.38, dampingFraction: 0.82)
    }

    static func transition(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .scale(scale: 0.86, anchor: .bottomLeading).combined(with: .opacity)
    }
}

/// The three games of the break corner.
enum MiniGame: String, CaseIterable, Identifiable {
    case mandala, bubbles, xox

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mandala: return Loc.t("Mürekkep mandalası")
        case .bubbles: return Loc.t("Mürekkep balonları")
        case .xox: return Loc.t("XOX")
        }
    }

    var hint: String {
        switch self {
        case .mandala: return Loc.t("Çiz; her çizgi sekiz kat açılır.")
        case .bubbles: return Loc.t("Yükselen balonlara dokun, patlat. 60 saniye.")
        case .xox: return Loc.t("iPad'e karşı; sen X'sin.")
        }
    }

    var symbol: String {
        switch self {
        case .mandala: return "circle.hexagongrid"
        case .bubbles: return "drop.circle"
        case .xox: return "squareshape.split.3x3"
        }
    }
}

/// The small glass circle in the bottom-left corner that opens and closes the break panel.
struct GameCornerButton: View {
    @Binding var isOpen: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            withAnimation(GameCorner.animation(reduceMotion: reduceMotion)) { isOpen.toggle() }
        } label: {
            Image(systemName: "gamecontroller")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isOpen ? Color.white : Color.secondary)
                .frame(width: 34, height: 34)
                .background(Circle().fill(isOpen ? AnyShapeStyle(Theme.ink) : AnyShapeStyle(Material.ultraThinMaterial)))
                .overlay(Circle().strokeBorder(Theme.hairline, lineWidth: 0.6))
                .opacity(isOpen ? 1 : 0.75)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isOpen ? Loc.t("Molayı kapat") : Loc.t("Mola: küçük oyunlar"))
    }
}

/// The break card: a header, the three games to pick from, the game itself. Every touch inside the
/// card stays in it, so no stroke reaches the page beneath; the pencil draws here like a finger.
struct GameCornerPanel: View {
    let onClose: () -> Void
    @State private var game: MiniGame?
    /// Counts the restarts; each one builds the game afresh.
    @State private var round = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 10)
                .frame(height: 48)
            Divider()
            Group {
                if let game {
                    gameView(game)
                        .id("\(game.id)-\(round)")
                } else {
                    picker
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: GameCorner.panelSize.width, height: GameCorner.panelSize.height)
        .glassCard(radius: GameCorner.radius)
        .contentShape(RoundedRectangle(cornerRadius: GameCorner.radius, style: .continuous))
        // The card keeps every touch to itself: nothing reaches the page beneath it.
        .onTapGesture {}
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: game)
    }

    private var header: some View {
        HStack(spacing: 6) {
            if game != nil {
                headerButton("chevron.left", label: Loc.t("Oyunlara dön")) {
                    game = nil
                }
            } else {
                Image(systemName: "cup.and.saucer")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 32, height: 32)
            }
            Text(game?.title ?? Loc.t("Mola"))
                .font(Theme.display(.headline))
                .lineLimit(1)
            Spacer(minLength: 4)
            if game != nil {
                headerButton("arrow.counterclockwise", label: Loc.t("Yeniden başlat")) {
                    round += 1
                }
            }
            headerButton("xmark", label: Loc.t("Kapat"), action: onClose)
        }
    }

    private func headerButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.primary)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.primary.opacity(0.06)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var picker: some View {
        VStack(spacing: 10) {
            Text(Loc.t("Kısa bir mola. Kalemle de parmakla da oynanır."))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(MiniGame.allCases) { item in
                Button {
                    game = item
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(Theme.ink)
                            .frame(width: 44, height: 44)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.ink.opacity(0.1)))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.primary)
                            Text(item.hint)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.primary.opacity(0.04)))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 0.6))
                    .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
                .accessibilityHint(item.hint)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func gameView(_ game: MiniGame) -> some View {
        switch game {
        case .mandala: InkMandalaGame()
        case .bubbles: InkBubblesGame()
        case .xox: XOXGame()
        }
    }
}
