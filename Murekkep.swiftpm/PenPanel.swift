import SwiftUI

/// Every pen in one scrolling panel: the ones used last, then writing, paint, nature and shine.
/// Each section is a tray the pens stand in, with their names below; the pen in hand stands raised.
struct PenPanel: View {
    @ObservedObject var editor: EditorModel
    @EnvironmentObject private var settings: AppSettings
    let done: () -> Void

    private static let slotWidth: CGFloat = 54

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
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
                HStack(alignment: .top, spacing: 4) {
                    ForEach(brushes) { brush in
                        slot(brush)
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }

    private func slot(_ brush: Brush) -> some View {
        let selected = editor.tool == .brush(brush)
        return Button {
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
    }
}
