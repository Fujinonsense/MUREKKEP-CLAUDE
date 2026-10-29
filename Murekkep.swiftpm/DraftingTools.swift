import SwiftUI
import UIKit

extension ToolKind {
    var symbol: String {
        switch self {
        case let .brush(b): return b.symbol
        case .eraser: return "eraser"
        case .lasso: return "lasso"
        case .shape: return "square.on.circle"
        case .compass: return "compass.drawing"
        case .text: return "textformat"
        case .textPen: return "pencil.and.scribble"
        }
    }
}

// MARK: - Shapes

struct ShapePicker: View {
    @ObservedObject var editor: EditorModel
    @Environment(\.dismiss) private var dismiss
    private let columns = [GridItem(.adaptive(minimum: 78), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(Loc.t("Şekiller"), systemImage: "square.on.circle")
                .font(.headline)
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(ShapeKind.allCases) { kind in
                    let selected = editor.shapeKind == kind
                    Button {
                        editor.shapeKind = kind
                        if editor.tool != .shape { editor.select(.shape) }
                        dismiss()
                    } label: {
                        VStack(spacing: 5) {
                            Image(systemName: kind.symbol)
                                .font(.system(size: 20, weight: .medium))
                                .frame(height: 24)
                            Text(kind.title)
                                .font(.caption2)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                        }
                        .foregroundStyle(selected ? Color.white : Color.primary)
                        .frame(maxWidth: .infinity, minHeight: 64)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(selected ? AnyShapeStyle(Theme.ink) : AnyShapeStyle(Color.primary.opacity(0.06))))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            Toggle(isOn: $editor.shapeDashed) {
                Label(Loc.t("Kesikli çizgi"), systemImage: "line.3.horizontal")
            }
            if editor.shapeKind == .polygon {
                Stepper(Loc.t("Kenar sayısı: {0}", "\(editor.polygonSides)"), value: $editor.polygonSides, in: 3...12)
            }
            Text(Loc.t("Kalemle sürükle. Doğrular 15°'lerde, kare ve daireler eşit kenarda tık diye oturur; ölçü kalemin yanında görünür. Şekil son seçtiğin mürekkeple çizilir."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(width: 360)
    }
}

// MARK: - Page angle

struct PageAnglePanel: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(Loc.t("Sayfa açısı: {0}°", "\(Int(settings.pageAngle.rounded()))"), systemImage: "rotate.right")
                .font(.headline)
                .monospacedDigit()
            Slider(value: $settings.pageAngle, in: -90...90, step: 1)
            HStack(spacing: 6) {
                ForEach([-30, -15, 0, 15, 30], id: \.self) { d in
                    Button {
                        settings.pageAngle = Double(d)
                    } label: {
                        // One line always: a wrapped "−30°" dropped its last digit below the rest.
                        Text(d < 0 ? "−\(-d)°" : "\(d)°")
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(Int(settings.pageAngle.rounded()) == d ? Theme.ink : .secondary)
                }
            }
            Toggle(isOn: $settings.pageAngleLocked) {
                Label(Loc.t("Açıyı kilitle"), systemImage: settings.pageAngleLocked ? "lock.fill" : "lock.open")
            }
            Text(Loc.t("Elini rahat koyacağın açıyı seç ve kilitle; yazdıkların sayfaya göre düz kalır. Kilit açıkken iki parmakla çevirerek de döndürebilirsin, 15°'lerde tık diye oturur."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(width: 360)
    }
}

// MARK: - Selection

/// Actions for strokes picked with the lasso.
struct SelectionBar: View {
    @ObservedObject var editor: EditorModel

    var body: some View {
        HStack(spacing: 4) {
            item(Loc.t("Sil"), "trash", role: .destructive) { editor.deleteSelection() }
            item(Loc.t("Çoğalt"), "plus.square.on.square") { editor.duplicateSelection() }
            item(Loc.t("Mürekkebi uygula"), "paintbrush.pointed") { editor.restyleSelection() }
            item(Loc.t("Yazıya çevir"), "text.viewfinder") {
                guard let page = editor.selection?.page else { return }
                Task { await editor.convertHandwriting(page: page) }
            }
            .disabled(editor.isConverting)
            Divider().frame(height: 26)
            item(Loc.t("Bitti"), "checkmark") { editor.clearSelection() }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .glassCapsule()
    }

    private func item(_ title: String, _ symbol: String, role: ButtonRole? = nil, action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) {
            VStack(spacing: 2) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .medium))
                Text(title)
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
            }
            .foregroundStyle(role == .destructive ? Color.red : Color.primary)
            .padding(.horizontal, 8)
            .frame(minWidth: 52, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Shown while a sticker still has its box: flip it, remove it, or settle it on the page.
struct StickerPlacementBar: View {
    @ObservedObject var editor: EditorModel

    var body: some View {
        HStack(spacing: 4) {
            item(Loc.t("Sil"), "trash", role: .destructive) { editor.deletePlacingSticker() }
            item(Loc.t("Ayna"), "arrow.left.and.right.righttriangle.left.righttriangle.right") { editor.mirrorPlacingSticker() }
            Divider().frame(height: 26)
            item(Loc.t("Bitti"), "checkmark") { editor.finishPlacing() }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .glassCapsule()
    }

    private func item(_ title: String, _ symbol: String, role: ButtonRole? = nil, action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) {
            VStack(spacing: 2) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .medium))
                Text(title)
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
            }
            .foregroundStyle(role == .destructive ? Color.red : Color.primary)
            .padding(.horizontal, 8)
            .frame(minWidth: 52, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The writing sound's switch: a faint speaker in a corner of the page, easy to find but out of
/// the way of the writing hand.
struct PaperSoundCornerButton: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Button {
            settings.paperSound.toggle()
        } label: {
            Image(systemName: settings.paperSound ? "speaker.wave.2.fill" : "speaker.slash")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(settings.paperSound ? Theme.ink : Color.secondary)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Theme.paper))
                .overlay(Circle().strokeBorder(Theme.hairline, lineWidth: 1))
                .opacity(settings.paperSound ? 0.9 : 0.55)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(settings.paperSound ? Loc.t("Yazı sesini kapat") : Loc.t("Yazı sesini aç"))
    }
}

// MARK: - Banner

/// A short confirmation over the canvas that hides itself.
struct CanvasBanner: View {
    @ObservedObject var editor: EditorModel

    var body: some View {
        if let text = editor.banner {
            Text(text)
                .font(.subheadline.weight(.medium))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .glassCapsule()
                .transition(.move(edge: .top).combined(with: .opacity))
                .onTapGesture { editor.banner = nil }
                .task(id: text) {
                    try? await Task.sleep(nanoseconds: 3_200_000_000)
                    if editor.banner == text {
                        withAnimation(.easeInOut(duration: 0.25)) { editor.banner = nil }
                    }
                }
        }
    }
}
