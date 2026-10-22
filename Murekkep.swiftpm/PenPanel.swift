import SwiftUI

/// Every pen, one shelf at a time (PenShelf), like a brush library: each pen in its own row with its
/// whole name and a sample of the ink it lays down, in the colour it will draw. The panel is only as
/// tall as the shelf's pens. The nature pens show what is left of their trial ink; a Pro-only pen,
/// or a nature pen whose trial is over, opens the Pro page right over the panel. One tap on a pen's
/// heart makes it a favourite: favourites always stand in the notebook's pen bar.
struct PenPanel: View {
    @ObservedObject var editor: EditorModel
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject private var pro = ProStore.shared
    let done: () -> Void

    @AppStorage("penPanelShelf") private var savedShelf = ""
    @State private var shelf: PenShelf?
    @State private var focused: Brush?

    private static let panelWidth: CGFloat = 548
    private static let rowHeight: CGFloat = 76
    private static let spacing: CGFloat = 10
    private static let maxRows = 5
    private let columns = [GridItem(.flexible(), spacing: PenPanel.spacing), GridItem(.flexible(), spacing: PenPanel.spacing)]

    private var current: PenShelf {
        shelf ?? PenShelf.opening(saved: savedShelf, favorites: settings.favoriteBrushes, current: editor.activeBrush)
    }

    private var shelfBinding: Binding<PenShelf> {
        Binding(get: { current }, set: { item in
            shelf = item
            savedShelf = item.rawValue
        })
    }

    var body: some View {
        let brushes = current.brushes(favorites: settings.favoriteBrushes)
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 12)
            Picker(Loc.t("Raf"), selection: shelfBinding) {
                ForEach(PenShelf.allCases) { item in
                    Text(item.shortTitle).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.bottom, 14)
            Divider().opacity(0.6)
            if brushes.isEmpty {
                emptyFavorites
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: Self.spacing) {
                        ForEach(brushes) { brush in
                            row(brush)
                        }
                    }
                    .padding(16)
                }
                .frame(height: Self.gridHeight(count: brushes.count))
                .scrollDisabled(brushes.count <= 2 * Self.maxRows)
            }
            Divider().opacity(0.6)
            footer
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
        }
        .frame(width: Self.panelWidth)
        .presentationCompactAdaptation(.popover)
        .animation(.snappy(duration: 0.22), value: current)
        .animation(.snappy(duration: 0.22), value: settings.favoriteBrushes)
    }

    /// Two pens a row, up to five rows; a longer favourites shelf scrolls.
    private static func gridHeight(count: Int) -> CGFloat {
        let rows = CGFloat(min(maxRows, (count + 1) / 2))
        return rows * rowHeight + (rows - 1) * spacing + 32
    }

    // MARK: Parts

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(Loc.t("Kalemler"))
                .font(Theme.display(.title2, weight: .bold))
            Label(Loc.t("Kalbe dokun: o kalem defterin kalem çubuğunda hep durur."), systemImage: "heart")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func row(_ brush: Brush) -> some View {
        let selected = editor.tool == .brush(brush)
        let locked = brush.isPremium && pro.locks
        let trialOver = brush.isTrialInk && pro.locks && pro.trialInkLeft == 0
        let starred = settings.favoriteBrushes.contains(brush)
        let ink = editor.color(for: brush).swiftUIColor
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return Button {
            focused = brush
            if locked {
                // The Pro page opens over the panel; the panel stays for when it closes.
                _ = pro.unlock(.premiumInk)
            } else if trialOver {
                _ = pro.allowsTrialInk()
            } else {
                editor.select(.brush(brush))
                done()
            }
        } label: {
            HStack(spacing: 10) {
                PenBodyView(brush: brush, ink: ink, selected: selected)
                    .frame(width: 34, height: 60, alignment: .top)
                    .clipped()
                    // The pen's lower end sinks into the row.
                    .mask {
                        LinearGradient(stops: [.init(color: .black, location: 0.72), .init(color: .clear, location: 1)],
                                       startPoint: .top, endPoint: .bottom)
                    }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(brush.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        if locked && current != .threeD {
                            ProBadge()
                        }
                        Spacer(minLength: 30)
                    }
                    StrokePreview(brush: brush, color: ink, width: CGFloat(min(editor.width(for: brush), 9)))
                        .frame(height: 28)
                        .opacity(trialOver ? 0.35 : 1)
                    if brush.isTrialInk && pro.locks {
                        TrialInkGauge(left: pro.trialInkLeft)
                    }
                }
            }
            .padding(.leading, 10)
            .padding(.trailing, 12)
            .frame(height: Self.rowHeight)
            .background(shape.fill(selected ? Theme.ink.opacity(0.13) : Color.primary.opacity(0.045)))
            .overlay(shape.strokeBorder(selected ? Theme.ink : Color.primary.opacity(0.07), lineWidth: selected ? 1.5 : 0.5))
            .contentShape(shape)
        }
        .buttonStyle(PressableStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(brush.title)
        .accessibilityHint(locked || trialOver ? Loc.t("Mürekkep Pro'da") : brush.detail)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .overlay(alignment: .topTrailing) {
            heart(brush, starred: starred)
        }
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
    }

    /// One tap makes the pen a favourite (or not): its own button beside the row, so it never
    /// picks the pen or closes the panel.
    private func heart(_ brush: Brush, starred: Bool) -> some View {
        Button {
            settings.toggleFavorite(brush)
        } label: {
            Image(systemName: starred ? "heart.fill" : "heart")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(starred ? Color.pink : Color.secondary.opacity(0.55))
                .symbolEffect(.bounce, value: starred)
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: starred)
        .accessibilityLabel(starred ? Loc.t("{0}: favorilerden çıkar", brush.title) : Loc.t("{0}: favorilere ekle", brush.title))
    }

    /// What the pen under the finger (or in hand) does; without Pro, the way to it where it matters.
    private var footer: some View {
        let brush = focused ?? editor.activeBrush
        let locked = brush.isPremium && pro.locks
        let onTrial = brush.isTrialInk && pro.locks
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(brush.title)
                        .font(.subheadline.weight(.semibold))
                    if locked {
                        ProBadge()
                    }
                }
                Text(onTrial
                     ? Loc.t("Deneme mürekkebi: %{0} kaldı. Pro ile sınırsız.", "\(Int((pro.trialInkLeft * 100).rounded()))")
                     : brush.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if pro.locks && (current == .threeD || locked || onTrial) {
                Button {
                    Paywall.present(reason: onTrial ? .trialInk : .premiumInk)
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
        .frame(minHeight: 46, alignment: .leading)
    }

    private var emptyFavorites: some View {
        VStack(spacing: 8) {
            Image(systemName: "heart")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.secondary)
            Text(Loc.t("Henüz favori kalem yok"))
                .font(.headline)
            Text(Loc.t("Bir kalemin yanındaki kalbe dokun; o kalem burada ve defterin kalem çubuğunda hep durur."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(Loc.t("Kalemlere göz at")) {
                shelf = .writing
            }
            .font(.subheadline.weight(.semibold))
            .padding(.top, 2)
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
    }
}

/// How much of the nature pens' trial ink is left: a thin gauge in the ink gradient.
struct TrialInkGauge: View {
    let left: Double

    var body: some View {
        HStack(spacing: 6) {
            GeometryReader { proxy in
                Capsule()
                    .fill(Color.primary.opacity(0.08))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(Theme.ai)
                            .frame(width: max(4, proxy.size.width * min(max(left, 0), 1)))
                    }
            }
            .frame(height: 4)
            Text(left > 0 ? "%\(Int((left * 100).rounded()))" : Loc.t("Bitti"))
                .font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Loc.t("Deneme mürekkebi"))
        .accessibilityValue(left > 0 ? "%\(Int((left * 100).rounded()))" : Loc.t("Bitti"))
    }
}
