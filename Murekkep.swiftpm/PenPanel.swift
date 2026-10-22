import SwiftUI

/// Every pen in one scrolling panel: the favourites, the ones used last, then writing, paint, nature
/// and shine. Each section is a tray the pens stand in, with their names below; the pen in hand stands
/// raised. The heart on a pen keeps it in the notebook's pen bar.
struct PenPanel: View {
    @ObservedObject var editor: EditorModel
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject private var pro = ProStore.shared
    let done: () -> Void

    private static let slotWidth: CGFloat = 54

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if settings.favoriteBrushes.isEmpty {
                    Label(Loc.t("Bir kalemin kalbine dokun: o kalem defterin kalem çubuğunda hep durur."), systemImage: "heart")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    tray(Loc.t("Favoriler"), brushes: Brush.paletteOrder.filter { settings.favoriteBrushes.contains($0) })
                }
                tray(Loc.t("Son kullanılanlar"), brushes: Array(settings.recentBrushes.prefix(6)))
                ForEach(BrushGroup.allCases) { group in
                    tray(group.title, brushes: group.brushes)
                }
            }
            .padding(18)
        }
        .frame(width: 452)
        .frame(maxHeight: 580)
        .presentationCompactAdaptation(.popover)
    }

    private func tray(_ title: String, brushes: [Brush]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            ZStack(alignment: .topLeading) {
                // The tray floor: the pens' lower ends disappear into it.
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
                    .frame(height: 30)
                    .offset(y: 38)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 4) {
                        ForEach(brushes) { brush in
                            slot(brush)
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .scrollDisabled(brushes.count <= 7)
                .scrollClipDisabled()
            }
        }
    }

    private func slot(_ brush: Brush) -> some View {
        let selected = editor.tool == .brush(brush)
        let starred = settings.favoriteBrushes.contains(brush)
        return Button {
            if brush.isPremium && pro.locks {
                // Close the panel first: the Pro page would go with it.
                done()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { Paywall.present(reason: .premiumInk) }
                return
            }
            editor.select(.brush(brush))
            done()
        } label: {
            VStack(spacing: 6) {
                PenBodyView(brush: brush, ink: editor.color(for: brush).swiftUIColor, selected: selected)
                    .frame(width: Self.slotWidth, height: 66, alignment: .top)
                    .clipped()
                Text(brush.title)
                    .font(.caption2.weight(selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(width: Self.slotWidth, height: 28, alignment: .top)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(brush.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .overlay(alignment: .topTrailing) {
            Button {
                settings.toggleFavorite(brush)
            } label: {
                Image(systemName: starred ? "heart.fill" : "heart")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(starred ? Color.pink : Color.secondary.opacity(0.6))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .offset(x: 5, y: -4)
            .accessibilityLabel(starred ? Loc.t("{0}: favorilerden çıkar", brush.title) : Loc.t("{0}: favorilere ekle", brush.title))
        }
        .overlay(alignment: .topLeading) {
            if brush.isPremium && pro.locks {
                ProLockBadge()
                    .offset(x: -2, y: -4)
            }
        }
        .contextMenu {
            Button {
                settings.toggleFavorite(brush)
            } label: {
                Label(starred ? Loc.t("Favorilerden çıkar") : Loc.t("Favorilere ekle"), systemImage: starred ? "heart.slash" : "heart")
            }
        }
    }
}
