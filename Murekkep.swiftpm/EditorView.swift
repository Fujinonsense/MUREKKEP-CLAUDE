import SwiftUI
import UIKit

/// Owns the models of one open note so they live exactly as long as the screen.
final class EditorSession: ObservableObject {
    let editor: EditorModel
    let assistant: AssistantModel

    init(meta: NoteMeta, store: LibraryStore, settings: AppSettings) {
        editor = EditorModel(meta: meta, store: store, settings: settings)
        assistant = AssistantModel(editor: editor, settings: settings)
    }
}

struct EditorScreen: View {
    @StateObject private var session: EditorSession

    init(meta: NoteMeta, store: LibraryStore, settings: AppSettings) {
        _session = StateObject(wrappedValue: EditorSession(meta: meta, store: store, settings: settings))
    }

    var body: some View {
        EditorContent(editor: session.editor, assistant: session.assistant)
    }
}

private struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct EditorContent: View {
    @ObservedObject var editor: EditorModel
    let assistant: AssistantModel
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var showAssistant = false
    @State private var showSettings = false
    @State private var shareItem: ShareItem?
    @State private var exportError: String?
    @State private var paletteCollapsed = false
    @State private var showTemplates = false
    @State private var showEngineering = false
    @State private var showAngle = false

    private var sidePanel: Bool { horizontalSizeClass == .regular }

    var body: some View {
        HStack(spacing: 0) {
            ZStack(alignment: .top) {
                CanvasRepresentable(editor: editor, pencilOnly: settings.pencilOnly,
                                    animations: settings.animations, batterySaver: settings.batterySaver,
                                    pageAngle: settings.pageAngle, pageAngleLocked: settings.pageAngleLocked)
                    .overlay {
                        GeometryReader { geo in
                            if let request = editor.palette {
                                ZStack {
                                    Color.black.opacity(0.001)
                                        .contentShape(Rectangle())
                                        .onTapGesture { editor.palette = nil }
                                    RadialPalette(editor: editor, request: request, container: geo.size)
                                        .id(request.id)
                                }
                                .transition(.opacity)
                            } else if let suggestion = editor.suggestion {
                                ZStack {
                                    Color.black.opacity(0.001)
                                        .contentShape(Rectangle())
                                        .onTapGesture { editor.suggestion = nil }
                                    SuggestionPalette(editor: editor, suggestion: suggestion, container: geo.size)
                                        .id(suggestion.id)
                                }
                                .transition(.opacity)
                            }
                        }
                    }
                    .ignoresSafeArea(.container, edges: .bottom)

                FloatingToolPalette(editor: editor, collapsed: $paletteCollapsed)
                    .padding(.top, 10)
                    .padding(.horizontal, 12)

                // The engineering rail hides with the palette for a clean page.
                if !paletteCollapsed {
                    HStack {
                        DraftingRail(editor: editor, showEngineering: $showEngineering)
                            .padding(.leading, 12)
                        Spacer(minLength: 0)
                    }
                    .frame(maxHeight: .infinity)
                    .padding(.top, 70)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                }

                VStack(spacing: 8) {
                    CanvasBanner(editor: editor)
                    if editor.isConverting || editor.isTypesetting {
                        Label(editor.isTypesetting ? Loc.t("Metne çevriliyor…") : Loc.t("El yazısı okunuyor…"), systemImage: "text.viewfinder")
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .glassCapsule()
                            .transition(.opacity)
                    }
                }
                .padding(.top, 88)
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: editor.banner)
                .animation(.easeInOut(duration: 0.2), value: editor.isConverting || editor.isTypesetting)

                VStack {
                    Spacer()
                    HStack(alignment: .bottom) {
                        if abs(settings.pageAngle) >= 0.5 {
                            rotationChip
                        }
                        Spacer(minLength: 8)
                        if editor.placingSticker != nil {
                            StickerPlacementBar(editor: editor)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        } else if editor.tool == .lasso, editor.selection != nil {
                            SelectionBar(editor: editor)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                        Spacer(minLength: 8)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 52)
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.85), value: editor.selection != nil)
                .animation(.spring(response: 0.3, dampingFraction: 0.85), value: editor.placingSticker != nil)

                // The writing sound's switch, tucked into the bottom-left corner (off by default).
                VStack {
                    Spacer()
                    HStack {
                        PaperSoundCornerButton(settings: settings)
                        Spacer()
                    }
                }
                .padding(.leading, 6)
                .padding(.bottom, 6)

                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Spacer()
                        if editor.pencilProDetected {
                            Chip(text: "Apple Pencil Pro", symbol: "applepencil", tint: Theme.ink)
                                .background(.ultraThinMaterial, in: Capsule())
                                .transition(.scale.combined(with: .opacity))
                        }
                        PageBadge(current: editor.currentPage + 1, total: editor.pageCount)
                    }
                    .padding(16)
                }
                .allowsHitTesting(false)

                if let error = editor.loadError {
                    Text(error)
                        .padding()
                        .glassCard(radius: 14)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(Color(uiColor: .systemGray6))
            if showAssistant && sidePanel {
                Divider()
                AssistantPanel(assistant: assistant, editor: editor) {
                    withAnimation(.easeInOut(duration: 0.22)) { showAssistant = false }
                }
                .frame(width: 400)
                .transition(.move(edge: .trailing))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: editor.pencilProDetected)
        .navigationTitle(editor.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    export()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel(Loc.t("PDF olarak paylaş"))
                Menu {
                    if !editor.isPDF {
                        Button {
                            showTemplates = true
                        } label: {
                            Label(Loc.t("Şablonu değiştir ({0})", "\(editor.meta.paper.title)"), systemImage: "square.grid.2x2")
                        }
                        Divider()
                    }
                    Toggle(isOn: $settings.pencilOnly) {
                        Label(Loc.t("Yalnızca Pencil ile çiz"), systemImage: "applepencil")
                    }
                    Toggle(isOn: $settings.straightLine) {
                        Label(Loc.t("Bekleyince şekli düzelt"), systemImage: "scribble.variable")
                    }
                    Toggle(isOn: $settings.animations) {
                        Label(Loc.t("Animasyonlar"), systemImage: "sparkles")
                    }
                    Toggle(isOn: $settings.batterySaver) {
                        Label(Loc.t("Pil tasarrufu"), systemImage: "battery.50")
                    }
                    Divider()
                    Button {
                        showSettings = true
                    } label: {
                        Label(Loc.t("Ayarlar"), systemImage: "gearshape")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) { showAssistant = true }
                    assistant.run(.solve)
                } label: {
                    Label(Loc.t("Çöz"), systemImage: "wand.and.stars")
                        .labelStyle(.titleAndIcon)
                        .font(.subheadline.weight(.semibold))
                }
                .accessibilityLabel(Loc.t("Bu sayfadaki soruları çöz"))
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) { showAssistant.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                        Text(Loc.t("Asistan"))
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Theme.ai, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Loc.t("Yapay zekâ asistanı"))
            }
        }
        .sheet(isPresented: Binding(get: { showAssistant && !sidePanel }, set: { showAssistant = $0 })) {
            AssistantPanel(assistant: assistant, editor: editor) {
                showAssistant = false
            }
            .environmentObject(settings)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $shareItem) { item in
            ActivityView(items: [item.url])
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(settings)
        }
        .sheet(isPresented: $showTemplates) {
            TemplateGallery(title: Loc.t("Şablonu değiştir"), current: editor.meta.paper) { style in
                editor.setPaper(style)
            }
        }
        .sheet(isPresented: $showEngineering) {
            EngineeringPanel(editor: editor)
                .environmentObject(settings)
        }
        .sheet(item: $editor.textRequest) { request in
            TextEntrySheet(editor: editor, request: request)
        }
        .alert(Loc.t("Dışa aktarılamadı"), isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button(Loc.t("Tamam"), role: .cancel) { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
        .onDisappear {
            assistant.cancel()
            editor.close()
        }
    }

    /// Shows the page angle while the page is turned; tap for the angle controls.
    private var rotationChip: some View {
        Button {
            showAngle = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: settings.pageAngleLocked ? "lock.fill" : "lock.open")
                Text(Loc.t("Sayfa {0}°", "\(Int(settings.pageAngle.rounded()))"))
                    .monospacedDigit()
            }
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.3), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Loc.t("Sayfa açısı {0} derece", "\(Int(settings.pageAngle.rounded()))"))
        .popover(isPresented: $showAngle) {
            PageAnglePanel()
                .environmentObject(settings)
                .presentationCompactAdaptation(.popover)
        }
    }

    private func export() {
        do {
            editor.saveNow()
            shareItem = ShareItem(url: try editor.exportPDF())
        } catch {
            exportError = error.localizedDescription
        }
    }
}

struct CanvasRepresentable: UIViewRepresentable {
    let editor: EditorModel
    let pencilOnly: Bool
    let animations: Bool
    let batterySaver: Bool
    let pageAngle: Double
    let pageAngleLocked: Bool

    func makeUIView(context: Context) -> CanvasView {
        CanvasView(model: editor)
    }

    func updateUIView(_ view: CanvasView, context: Context) {
        view.applyInputSettings(pencilOnly: pencilOnly)
        view.applyRenderSettings(animations: animations, batterySaver: batterySaver)
        view.applyRotation(degrees: pageAngle, locked: pageAngleLocked)
    }
}

struct PageBadge: View {
    let current: Int
    let total: Int

    var body: some View {
        Text("\(current) / \(total)")
            .font(.footnote.monospacedDigit().weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.3), lineWidth: 0.5))
            .allowsHitTesting(false)
    }
}

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
