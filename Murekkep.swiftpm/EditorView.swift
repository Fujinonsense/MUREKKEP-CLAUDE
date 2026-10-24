import SwiftUI
import UIKit

/// Owns the models of one open note so they live exactly as long as the screen.
final class EditorSession: ObservableObject {
    let editor: EditorModel
    let assistant: AssistantModel
    let lecture: LectureAudio

    init(meta: NoteMeta, store: LibraryStore, settings: AppSettings) {
        editor = EditorModel(meta: meta, store: store, settings: settings)
        assistant = AssistantModel(editor: editor, settings: settings)
        lecture = LectureAudio(folder: store.folder(for: meta.id), editor: editor)
    }
}

struct EditorScreen: View {
    @StateObject private var session: EditorSession

    init(meta: NoteMeta, store: LibraryStore, settings: AppSettings) {
        _session = StateObject(wrappedValue: EditorSession(meta: meta, store: store, settings: settings))
    }

    var body: some View {
        EditorContent(editor: session.editor, assistant: session.assistant, lecture: session.lecture)
    }
}

private struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct EditorContent: View {
    @ObservedObject var editor: EditorModel
    let assistant: AssistantModel
    @ObservedObject var lecture: LectureAudio
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var showAssistant = false
    @State private var showSettings = false
    @State private var shareItem: ShareItem?
    @State private var exportError: String?
    @State private var paletteCollapsed = false
    /// The pen bar on its grip: how far the finger has carried it, and the edge it would go to.
    @State private var paletteDrag: CGSize = .zero
    @State private var paletteTarget: PaletteEdge?
    @State private var canvasSize: CGSize = .zero
    @State private var showTemplates = false
    @State private var showEngineering = false
    @State private var showAngle = false
    @State private var showNavigator = false
    @State private var showLecture = false

    private var sidePanel: Bool { horizontalSizeClass == .regular }

    private var dock: PaletteEdge { settings.paletteEdge }
    /// What stands along the bottom (the page badge, the bars, the writing sound's switch) moves up over the pen bar.
    private var bottomClearance: CGFloat { dock == .bottom ? 76 : 0 }

    var body: some View {
        HStack(spacing: 0) {
            ZStack(alignment: .top) {
                CanvasRepresentable(editor: editor, pencilOnly: settings.pencilOnly,
                                    animations: settings.animations, batterySaver: settings.batterySaver,
                                    pageAngle: settings.pageAngle, pageAngleLocked: settings.pageAngleLocked,
                                    singlePage: editor.singlePage, zoomWindow: editor.zoomWindowOn,
                                    paletteClearance: UIEdgeInsets(top: 0, left: 0, bottom: bottomClearance,
                                                                   right: dock == .trailing ? 78 : 0))
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

                if let target = paletteTarget {
                    PaletteDockHint(edge: target)
                        .padding(paletteInsets(target))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: paletteAlignment(target))
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }

                FloatingToolPalette(editor: editor, collapsed: $paletteCollapsed, edge: dock,
                                    onGripMove: movePalette, onGripDrop: dropPalette)
                    .offset(paletteDrag)
                    .padding(paletteInsets(dock))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: paletteAlignment(dock))

                // The engineering rail hides with the palette for a clean page.
                if !paletteCollapsed {
                    HStack {
                        DraftingRail(editor: editor, showEngineering: $showEngineering)
                            .padding(.leading, 12)
                        Spacer(minLength: 0)
                    }
                    .frame(maxHeight: .infinity)
                    .padding(.top, dock == .top ? 70 : 10)
                    .padding(.bottom, bottomClearance)
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
                .padding(.top, dock == .top ? 88 : 18)
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: editor.banner)
                .animation(.easeInOut(duration: 0.2), value: editor.isConverting || editor.isTypesetting)

                VStack {
                    Spacer()
                    if showLecture {
                        LectureBar(lecture: lecture, keyboard: editor.tool != .text && editor.tool != .textPen) {
                            setLecturePlayer(false)
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
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
                    .padding(.bottom, 52 + bottomClearance)
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.85), value: editor.selection != nil)
                .animation(.spring(response: 0.3, dampingFraction: 0.85), value: showLecture)
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
                .padding(.bottom, 6 + bottomClearance)

                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Spacer()
                        if editor.pencilProDetected {
                            Chip(text: "Apple Pencil Pro", symbol: "applepencil", tint: Theme.ink)
                                .background(.ultraThinMaterial, in: Capsule())
                                .transition(.scale.combined(with: .opacity))
                                .allowsHitTesting(false)
                        }
                        Button {
                            showNavigator = true
                        } label: {
                            PageBadge(current: editor.currentPage + 1, total: editor.pageCount,
                                      bookmarked: editor.isBookmarked(editor.currentPage))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Loc.t("Sayfaya git"))
                        .popover(isPresented: $showNavigator, arrowEdge: .bottom) {
                            PageNavigator(editor: editor) { showNavigator = false }
                        }
                    }
                    .padding(16)
                    .padding(.bottom, bottomClearance)
                }

                if let error = editor.loadError {
                    Text(error)
                        .padding()
                        .glassCard(radius: 14)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(Color(uiColor: .systemGray6))
            .coordinateSpace(.named(FloatingToolPalette.space))
            .background(GeometryReader { geo in
                Color.clear
                    .onAppear { canvasSize = geo.size }
                    .onChange(of: geo.size) { _, size in canvasSize = size }
            })
            .animation(.spring(response: 0.38, dampingFraction: 0.82), value: dock)
            .animation(.easeInOut(duration: 0.18), value: paletteTarget)
            .sensoryFeedback(.selection, trigger: paletteTarget) { old, new in old != nil && new != nil }
            .sensoryFeedback(.impact(flexibility: .soft), trigger: dock)
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
                if !lecture.takes.isEmpty, !lecture.isRecording {
                    Button {
                        setLecturePlayer(!showLecture)
                    } label: {
                        Image(systemName: "waveform")
                            .foregroundStyle(showLecture ? Theme.ink : Color.accentColor)
                            .padding(4)
                            .background(Circle().fill(showLecture ? Theme.ink.opacity(0.15) : Color.clear))
                    }
                    .accessibilityLabel(showLecture ? Loc.t("Oynatıcıyı kapat") : Loc.t("Kayıtları dinle"))
                }
                // One tap starts the lecture recording, one tap stops it; the take then opens in the player.
                Button {
                    if lecture.isRecording {
                        let before = lecture.takes.count
                        lecture.stopRecording()
                        if lecture.takes.count > before {
                            setLecturePlayer(true)
                            editor.banner = Loc.t("Kaydedildi. Dinlerken mürekkebe dokun, o ana gider.")
                        }
                    } else {
                        setLecturePlayer(false)
                        lecture.toggleRecording()
                    }
                } label: {
                    if lecture.isRecording {
                        HStack(spacing: 5) {
                            Image(systemName: "stop.circle.fill")
                                .symbolEffect(.pulse, isActive: true)
                            Text(LectureBar.clock(lecture.elapsed))
                                .font(.subheadline.monospacedDigit().weight(.semibold))
                        }
                        .foregroundStyle(Color.red)
                    } else {
                        Image(systemName: "mic")
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .accessibilityLabel(lecture.isRecording ? Loc.t("Kaydı durdur") : Loc.t("Dersi kaydet"))
                Button {
                    editor.zoomWindowOn.toggle()
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                        .foregroundStyle(editor.zoomWindowOn ? Theme.ink : Color.accentColor)
                        .padding(4)
                        .background(Circle().fill(editor.zoomWindowOn ? Theme.ink.opacity(0.15) : Color.clear))
                }
                .accessibilityLabel(editor.zoomWindowOn ? Loc.t("Yakın yazmayı kapat") : Loc.t("Yakın yazma: büyük yaz, sayfaya küçük insin"))
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
        .alert(Loc.t("Dışa aktarılamadı"), isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button(Loc.t("Tamam"), role: .cancel) { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
        .alert(Loc.t("Ders kaydı"), isPresented: Binding(get: { lecture.message != nil }, set: { if !$0 { lecture.message = nil } })) {
            Button(Loc.t("Tamam"), role: .cancel) { lecture.message = nil }
        } message: {
            Text(lecture.message ?? "")
        }
        .onChange(of: lecture.takes.isEmpty) { _, empty in
            if empty { setLecturePlayer(false) }
        }
        .onDisappear {
            assistant.cancel()
            lecture.finish()
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
            .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Loc.t("Sayfa açısı {0} derece", "\(Int(settings.pageAngle.rounded()))"))
        .popover(isPresented: $showAngle) {
            PageAnglePanel()
                .environmentObject(settings)
                .presentationCompactAdaptation(.popover)
        }
    }

    /// Opens or closes the lecture player: open, a finger tap on ink plays from that moment; closed,
    /// all ink shows and taps write again.
    private func setLecturePlayer(_ open: Bool) {
        guard open != showLecture else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { showLecture = open }
        if open {
            lecture.openPlayback()
        } else {
            lecture.closePlayback()
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

private extension EditorContent {
    /// The pen bar's room along each edge; down the right side it keeps clear of the page badge.
    func paletteInsets(_ edge: PaletteEdge) -> EdgeInsets {
        switch edge {
        case .top: return EdgeInsets(top: 10, leading: 12, bottom: 0, trailing: 12)
        case .bottom: return EdgeInsets(top: 0, leading: 12, bottom: 10, trailing: 12)
        case .trailing: return EdgeInsets(top: 60, leading: 0, bottom: 60, trailing: 12)
        }
    }

    func paletteAlignment(_ edge: PaletteEdge) -> Alignment {
        switch edge {
        case .top: return .top
        case .bottom: return .bottom
        case .trailing: return .trailing
        }
    }

    /// The bar follows its grip; the edge it would go to shows beneath the finger.
    func movePalette(_ drag: DragGesture.Value) {
        paletteDrag = drag.translation
        paletteTarget = PaletteEdge.nearest(x: drag.location.x, y: drag.location.y, width: canvasSize.width,
                                            height: canvasSize.height, current: dock)
    }

    /// Where the finger lets go, the nearest of the top, the bottom and the right side takes the bar.
    func dropPalette(_ drag: DragGesture.Value) {
        let target = PaletteEdge.nearest(x: drag.location.x, y: drag.location.y, width: canvasSize.width,
                                         height: canvasSize.height, current: dock)
        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
            settings.paletteEdge = target
            paletteDrag = .zero
            paletteTarget = nil
        }
    }
}

/// Where the pen bar lands when the finger lets go of its grip.
private struct PaletteDockHint: View {
    let edge: PaletteEdge

    var body: some View {
        Capsule(style: .continuous)
            .fill(Theme.ink.opacity(0.08))
            .overlay(Capsule(style: .continuous).strokeBorder(Theme.ink.opacity(0.35), lineWidth: 1.5))
            .frame(width: edge.isVertical ? 66 : 420, height: edge.isVertical ? 360 : 66)
    }
}

struct CanvasRepresentable: UIViewRepresentable {
    let editor: EditorModel
    let pencilOnly: Bool
    let animations: Bool
    let batterySaver: Bool
    let pageAngle: Double
    let pageAngleLocked: Bool
    let singlePage: Bool
    let zoomWindow: Bool
    let paletteClearance: UIEdgeInsets

    func makeUIView(context: Context) -> CanvasView {
        CanvasView(model: editor)
    }

    func updateUIView(_ view: CanvasView, context: Context) {
        view.applyInputSettings(pencilOnly: pencilOnly)
        view.applyRenderSettings(animations: animations, batterySaver: batterySaver)
        view.applyRotation(degrees: pageAngle, locked: pageAngleLocked)
        view.applyPageMode(single: singlePage)
        view.applyZoomWindow(on: zoomWindow)
        view.applyPaletteClearance(paletteClearance)
    }
}

/// "12 / 300" in the corner; a tap opens the page navigator.
struct PageBadge: View {
    let current: Int
    let total: Int
    var bookmarked = false

    var body: some View {
        HStack(spacing: 5) {
            if bookmarked {
                Image(systemName: "bookmark.fill")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
            Text("\(current) / \(total)")
                .font(.footnote.monospacedDigit().weight(.semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 0.5))
        .contentShape(Capsule())
    }
}

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
