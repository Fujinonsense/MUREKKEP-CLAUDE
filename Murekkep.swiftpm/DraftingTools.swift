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

// MARK: - Side rail

/// The engineering rail on the leading edge of the canvas: selection, shapes, drafting instruments,
/// compass, typed text, handwriting to text, the engineering toolbox and the page angle.
struct DraftingRail: View {
    @ObservedObject var editor: EditorModel
    @EnvironmentObject private var settings: AppSettings
    @Binding var showEngineering: Bool
    @State private var showShapes = false
    @State private var showAngle = false
    @State private var showStickers = false

    var body: some View {
        VStack(spacing: 3) {
            toolButton(.lasso, title: Loc.t("Kement: seç, taşı, büyüt, yazıya çevir"))
            shapeButton
            instrumentMenu
            toolButton(.compass, title: Loc.t("Pergel: merkezi ve yarıçapı çiz, sonra yay çiz"))
            toolButton(.text, title: Loc.t("Metin: dokun ve klavyeyle yaz"))
            railButton("face.smiling", title: Loc.t("Çıkartmalar: kalp, akciğer, karaciğer, emojiler…"), active: false) {
                showStickers = true
            }
            .sheet(isPresented: $showStickers) {
                StickerLibrary(editor: editor)
            }
            Divider()
                .frame(width: 26)
                .padding(.vertical, 3)
            convertButton
            railButton("function", title: Loc.t("Mühendislik: hesap makinesi, birimler, formüller, grafik"), active: false) {
                showEngineering = true
            }
            angleButton
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 5)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.35), lineWidth: 0.6))
        .shadow(color: .black.opacity(0.14), radius: 18, y: 8)
    }

    private func icon(_ symbol: String, active: Bool) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(active ? Color.white : Color.primary)
            .frame(width: 40, height: 40)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(active ? AnyShapeStyle(Theme.ink) : AnyShapeStyle(Color.clear)))
            .contentShape(Rectangle())
    }

    private func railButton(_ symbol: String, title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            icon(symbol, active: active)
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    /// Tapping the active tool again goes back to the last pen.
    private func toolButton(_ tool: ToolKind, title: String) -> some View {
        let active = editor.tool == tool
        return railButton(tool.symbol, title: title, active: active) {
            editor.select(active ? .brush(editor.lastBrush) : tool)
        }
    }

    private var shapeButton: some View {
        railButton(editor.shapeKind.symbol, title: Loc.t("Şekil: {0}", "\(editor.shapeKind.title)"), active: editor.tool == .shape) {
            if editor.tool != .shape { editor.select(.shape) }
            showShapes = true
        }
        .popover(isPresented: $showShapes) {
            ShapePicker(editor: editor)
                .presentationCompactAdaptation(.popover)
        }
    }

    private var instrumentMenu: some View {
        Menu {
            ForEach(InstrumentKind.allCases) { kind in
                Button {
                    editor.showInstrument(kind)
                } label: {
                    Label(kind.title, systemImage: editor.instrument?.kind == kind ? "checkmark" : kind.symbol)
                }
            }
            if editor.instrument != nil {
                Divider()
                Menu {
                    ForEach([0, 15, 30, 45, 60, 75, 90, 120, 135, 150], id: \.self) { d in
                        Button("\(d)°") { editor.setInstrumentAngle(Double(d)) }
                    }
                } label: {
                    Label(Loc.t("Açıyı ayarla"), systemImage: "angle")
                }
                Button(role: .destructive) {
                    editor.showInstrument(nil)
                } label: {
                    Label(Loc.t("Kaldır"), systemImage: "xmark")
                }
            }
        } label: {
            icon(editor.instrument?.kind.symbol ?? "ruler", active: editor.instrument != nil)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .help(Loc.t("Cetvel, gönye ve iletki: parmakla taşı ve çevir, kalemle kenarına yasla"))
        .accessibilityLabel(Loc.t("Cetvel, gönye ve iletki"))
    }

    private var convertButton: some View {
        Button {
            let page = editor.selection?.page ?? editor.currentPage
            Task { await editor.convertHandwriting(page: page) }
        } label: {
            ZStack {
                if editor.isConverting {
                    ProgressView()
                } else {
                    icon("text.viewfinder", active: false)
                }
            }
            .frame(width: 40, height: 40)
        }
        .buttonStyle(.plain)
        .disabled(editor.isConverting)
        .help(Loc.t("El yazısını yazıya çevir (çizgilere hizalı, mürekkep ve renkler korunur)"))
        .accessibilityLabel(Loc.t("El yazısını yazıya çevir"))
    }

    private var angleButton: some View {
        railButton(settings.pageAngleLocked ? "rotate.right" : "rotate.right.fill",
                   title: Loc.t("Sayfa açısı"), active: abs(settings.pageAngle) >= 0.5) {
            showAngle = true
        }
        .popover(isPresented: $showAngle) {
            PageAnglePanel()
                .environmentObject(settings)
                .presentationCompactAdaptation(.popover)
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
                        Text(d < 0 ? "−\(-d)°" : "\(d)°")
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
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
        .frame(width: 330)
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
                .background(Circle().fill(.ultraThinMaterial))
                .opacity(settings.paperSound ? 0.9 : 0.45)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(settings.paperSound ? Loc.t("Yazı sesini kapat") : Loc.t("Yazı sesini aç"))
    }
}

// MARK: - Text entry

/// Typed text, written onto the page in the single-line font with the current ink.
struct TextEntrySheet: View {
    @ObservedObject var editor: EditorModel
    let request: TextRequest
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    private let symbols = ["×", "÷", "±", "√", "π", "≈", "≠", "≤", "≥", "∞", "°", "²", "³", "→", "∫", "Δ", "Σ",
                           "α", "β", "θ", "λ", "μ", "σ", "ω", "ρ", "τ", "φ", "ε", "Ω"]

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                TextEditor(text: $text)
                    .focused($focused)
                    .font(.title3)
                    .frame(minHeight: 140)
                    .padding(8)
                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(symbols, id: \.self) { s in
                            Button(s) { text += s }
                                .font(.title3)
                                .frame(minWidth: 36, minHeight: 36)
                                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .buttonStyle(.plain)
                        }
                    }
                }
                Label(Loc.t("Yazı, son seçtiğin kalemin mürekkebi ve rengiyle, şablonun çizgilerine oturtularak yazılır."),
                      systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding()
            .navigationTitle(Loc.t("Metin yaz"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Loc.t("Vazgeç")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(Loc.t("Sayfaya yaz")) {
                        editor.insertText(text, request: request)
                        dismiss()
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium, .large])
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
