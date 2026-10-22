import SwiftUI

/// Every pen, one shelf at a time (PenShelf): the favourites, writing, paint, nature and the 3D inks.
/// Each pen stands in its own well with its whole name; the one in hand is raised and ringed in ink.
/// The line at the bottom says what the pen under the finger does. "Favorileri düzenle" puts a heart
/// on every pen: hearted pens always stand in the notebook's pen bar. A Pro-only pen opens the Pro
/// page right over the panel, every time it is touched.
struct PenPanel: View {
    @ObservedObject var editor: EditorModel
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject private var pro = ProStore.shared
    let done: () -> Void

    @AppStorage("penPanelShelf") private var savedShelf = ""
    @State private var shelf: PenShelf?
    @State private var editing = false
    @State private var focused: Brush?

    private static let cellWidth: CGFloat = 104
    private static let cellHeight: CGFloat = 118
    private static let spacing: CGFloat = 10
    private static let gridHeight: CGFloat = 3 * cellHeight + 2 * spacing + 32
    private let columns = Array(repeating: GridItem(.fixed(PenPanel.cellWidth), spacing: PenPanel.spacing), count: 4)

    private var current: PenShelf {
        shelf ?? PenShelf.opening(saved: savedShelf, favorites: settings.favoriteBrushes, current: editor.activeBrush)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 12)
            shelves
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            Divider().opacity(0.6)
            ScrollView {
                let brushes = current.brushes(favorites: settings.favoriteBrushes)
                if brushes.isEmpty {
                    emptyFavorites
                } else {
                    LazyVGrid(columns: columns, spacing: Self.spacing) {
                        ForEach(brushes) { brush in
                            cell(brush)
                        }
                    }
                    .padding(16)
                }
            }
            .frame(height: Self.gridHeight)
            Divider().opacity(0.6)
            footer
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
        }
        .frame(width: 4 * Self.cellWidth + 3 * Self.spacing + 32)
        .presentationCompactAdaptation(.popover)
        .animation(.snappy(duration: 0.22), value: current)
        .animation(.snappy(duration: 0.22), value: editing)
    }

    // MARK: Parts

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(Loc.t("Kalemler"))
                .font(Theme.display(.title2, weight: .bold))
            Spacer(minLength: 12)
            Button {
                editing.toggle()
            } label: {
                Label(editing ? Loc.t("Bitti") : Loc.t("Favorileri düzenle"), systemImage: editing ? "checkmark" : "heart")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(editing ? Theme.ink : Color.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private var shelves: some View {
        HStack(spacing: 6) {
            ForEach(PenShelf.allCases) { item in
                shelfButton(item)
            }
        }
    }

    private func shelfButton(_ item: PenShelf) -> some View {
        let chosen = item == current
        let fill: AnyShapeStyle = chosen
            ? (item == .threeD ? AnyShapeStyle(Theme.ai) : AnyShapeStyle(Theme.ink))
            : AnyShapeStyle(Color.primary.opacity(0.06))
        return Button {
            shelf = item
            savedShelf = item.rawValue
        } label: {
            HStack(spacing: 5) {
                if item == .favorites {
                    Image(systemName: chosen ? "heart.fill" : "heart")
                }
                if item == .threeD {
                    Image(systemName: "sparkles")
                }
                Text(item.title)
                    .lineLimit(1)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(chosen ? Color.white : Color.primary.opacity(0.75))
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(Capsule().fill(fill))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    private func cell(_ brush: Brush) -> some View {
        let selected = editor.tool == .brush(brush)
        let locked = brush.isPremium && pro.locks
        let starred = settings.favoriteBrushes.contains(brush)
        let well = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return Button {
            focused = brush
            if editing {
                settings.toggleFavorite(brush)
            } else if locked {
                // The Pro page opens over the panel; the panel stays for when it closes.
                _ = pro.unlock(.premiumInk)
            } else {
                editor.select(.brush(brush))
                done()
            }
        } label: {
            VStack(spacing: 6) {
                PenBodyView(brush: brush, ink: editor.color(for: brush).swiftUIColor, selected: selected)
                    .scaleEffect(1.15, anchor: .top)
                    .frame(width: 60, height: 70, alignment: .top)
                    // The pen's lower end sinks into the well.
                    .mask {
                        LinearGradient(stops: [.init(color: .black, location: 0.7), .init(color: .clear, location: 1)],
                                       startPoint: .top, endPoint: .bottom)
                    }
                Text(brush.title)
                    .font(.footnote.weight(selected ? .semibold : .medium))
                    .foregroundStyle(selected ? Color.primary : Color.primary.opacity(0.78))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .frame(width: Self.cellWidth - 12, height: 32, alignment: .top)
            }
            .padding(.top, 6)
            .frame(width: Self.cellWidth, height: Self.cellHeight)
            .background(well.fill(selected ? Theme.ink.opacity(0.12) : Color.primary.opacity(0.045)))
            .overlay(well.strokeBorder(selected ? Theme.ink : Color.primary.opacity(0.07), lineWidth: selected ? 1.5 : 0.5))
            .overlay(alignment: .topTrailing) {
                if editing {
                    Image(systemName: starred ? "heart.fill" : "heart")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(starred ? Color.pink : Color.secondary)
                        .padding(8)
                        .transition(.scale.combined(with: .opacity))
                } else if locked && current != .threeD {
                    ProBadge()
                        .padding(6)
                } else if starred && current != .favorites {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.pink.opacity(0.85))
                        .padding(8)
                }
            }
            .contentShape(well)
        }
        .buttonStyle(PressableStyle())
        .onHover { inside in
            if inside { focused = brush }
        }
        .contextMenu {
            Button {
                settings.toggleFavorite(brush)
            } label: {
                Label(starred ? Loc.t("Favorilerden çıkar") : Loc.t("Favorilere ekle"), systemImage: starred ? "heart.slash" : "heart")
            }
        }
        .accessibilityLabel(editing
            ? (starred ? Loc.t("{0}: favorilerden çıkar", brush.title) : Loc.t("{0}: favorilere ekle", brush.title))
            : brush.title)
        .accessibilityHint(locked ? Loc.t("Mürekkep Pro'da") : "")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// What the pen under the finger (or in hand) does; on the 3D shelf without Pro, the way to it.
    private var footer: some View {
        let brush = focused ?? editor.activeBrush
        let locked = brush.isPremium && pro.locks
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(brush.title)
                        .font(.subheadline.weight(.semibold))
                    if locked {
                        ProBadge()
                    }
                }
                Text(brush.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if pro.locks && (current == .threeD || locked) {
                Button {
                    Paywall.present(reason: .premiumInk)
                } label: {
                    Text(Loc.t("Pro'yu aç"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 14)
                        .frame(height: 34)
                        .background(Theme.ai, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(minHeight: 50, alignment: .leading)
    }

    private var emptyFavorites: some View {
        VStack(spacing: 10) {
            Image(systemName: "heart")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.secondary)
            Text(Loc.t("Henüz favori kalem yok"))
                .font(.headline)
            Text(Loc.t("\"Favorileri düzenle\"ye bas ve sevdiğin kalemlerin kalbine dokun. Favoriler defterin kalem çubuğunda hep durur."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(Loc.t("Favorileri düzenle")) {
                editing = true
                shelf = .writing
            }
            .font(.subheadline.weight(.semibold))
            .padding(.top, 4)
        }
        .padding(.horizontal, 36)
        .frame(maxWidth: .infinity, minHeight: Self.gridHeight - 20)
    }
}
