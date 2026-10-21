import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Where the library is: a list in the sidebar or a course.
enum LibraryPlace: Hashable {
    case home
    case recent
    case favorites
    case notebooks
    case pdfs
    case studio
    case course(UUID)

    var raw: String {
        switch self {
        case .home: return "home"
        case .recent: return "recent"
        case .favorites: return "favorites"
        case .notebooks: return "notebooks"
        case .pdfs: return "pdfs"
        case .studio: return "studio"
        case let .course(id): return "course:" + id.uuidString
        }
    }

    init(raw: String) {
        switch raw {
        case "recent": self = .recent
        case "favorites": self = .favorites
        case "notebooks": self = .notebooks
        case "pdfs": self = .pdfs
        case "studio": self = .studio
        default:
            if raw.hasPrefix("course:"), let id = UUID(uuidString: String(raw.dropFirst(7))) {
                self = .course(id)
            } else {
                self = .home
            }
        }
    }
}

/// What the panes can ask the library to do.
struct LibraryActions {
    var open: (UUID) -> Void
    var go: (LibraryPlace) -> Void
    var toggleSidebar: () -> Void
    var newNotebook: (UUID?) -> Void
    var createNotebook: (PaperStyle, UUID?) -> Void
    var importPDF: (UUID?) -> Void
    var newCourse: () -> Void
    var editCourse: (NoteSection) -> Void
    var deleteCourse: (NoteSection) -> Void
    var rename: (NoteMeta) -> Void
    var delete: (NoteMeta) -> Void
    var makeOverview: (UUID?, OverviewKind, [UUID]) -> Void
    var play: (Overview) -> Void
    var makeStudy: (UUID?, StudyKind) -> Void
    var openStudy: (StudySet) -> Void
    var drop: ([NSItemProvider], UUID?) -> Bool
}

struct StudioRequest: Identifiable {
    let id = UUID()
    let sectionID: UUID?
    let kind: OverviewKind
    let preselected: [UUID]
}

struct LibraryView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var studio: StudioStore
    @EnvironmentObject private var study: StudyStore
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var path: [UUID] = []
    @AppStorage("library.place") private var placeRaw = "home"
    @State private var sidebarShown = true
    @State private var drawerShown = false
    @State private var query = ""
    @State private var showImporter = false
    @State private var importTarget: UUID?
    @State private var showSettings = false
    @State private var showVoices = false
    @State private var showTemplates = false
    @State private var templateTarget: UUID?
    @State private var renaming: NoteMeta?
    @State private var renameText = ""
    @State private var deleting: NoteMeta?
    @State private var creatingSection = false
    @State private var editingSection: NoteSection?
    @State private var deletingSection: NoteSection?
    @State private var errorText: String?
    @State private var studioRequest: StudioRequest?
    @State private var playing: Overview?
    @State private var studyRequest: StudyRequest?
    @State private var openedStudy: StudySet?

    private var isRegular: Bool { sizeClass != .compact }

    private var place: LibraryPlace {
        let p = LibraryPlace(raw: placeRaw)
        if case let .course(id) = p, !store.sections.contains(where: { $0.id == id }) { return .home }
        return p
    }

    var body: some View {
        NavigationStack(path: $path) {
            HStack(spacing: 0) {
                if isRegular && sidebarShown {
                    sidebar
                        .frame(width: 300)
                        .transition(.move(edge: .leading))
                    Rectangle()
                        .fill(Color.primary.opacity(0.06))
                        .frame(width: 1)
                        .ignoresSafeArea()
                }
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .overlay(alignment: .leading) {
                if !isRegular && drawerShown {
                    ZStack(alignment: .leading) {
                        Color.black.opacity(0.3)
                            .ignoresSafeArea()
                            .onTapGesture { withAnimation(.spring(response: 0.3)) { drawerShown = false } }
                        sidebar
                            .frame(width: 300)
                            .background(Color(uiColor: .systemBackground))
                            .transition(.move(edge: .leading))
                    }
                }
            }
            .overlay(alignment: .bottom) { finishedBanner }
            .background(Theme.libraryBackground.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: UUID.self) { id in
                if let note = store.note(id) {
                    EditorScreen(meta: note, store: store, settings: settings)
                        .toolbar(.visible, for: .navigationBar)
                } else {
                    Text(Loc.t("Not bulunamadı"))
                }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.pdf], allowsMultipleSelection: true) { result in
                importFiles(result)
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    .environmentObject(settings)
            }
            .sheet(isPresented: $showVoices) {
                VoiceSettingsView()
            }
            .sheet(isPresented: $showTemplates) {
                TemplateGallery(title: Loc.t("Yeni defter")) { style in
                    let target = templateTarget
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        createNotebook(style, section: target)
                    }
                }
            }
            .sheet(item: $studioRequest) { request in
                StudioCreateSheet(request: request, engine: StudioEngine.preferred(settings: settings))
                    .environmentObject(store)
                    .environmentObject(studio)
                    .environmentObject(settings)
                    .pageSizedSheet()
            }
            .sheet(item: $studyRequest) { request in
                StudyCreateSheet(request: request, engine: StudioEngine.preferred(settings: settings))
                    .environmentObject(store)
                    .environmentObject(study)
                    .environmentObject(settings)
                    .pageSizedSheet()
            }
            .fullScreenCover(item: $openedStudy) { set in
                StudySetView(setID: set.id)
                    .environmentObject(study)
            }
            .fullScreenCover(item: $playing) { overview in
                OverviewPlayerView(overview: overview, folder: studio.folder(for: overview.id))
                    .environmentObject(store)
                    .environmentObject(studio)
                    .environmentObject(settings)
            }
            .sheet(isPresented: $creatingSection) {
                SectionEditor(name: "", symbol: NoteSection.symbols[0], colorIndex: store.sections.count % NoteSection.colors.count,
                              isNew: true) { name, symbol, color in
                    let section = store.createSection(name: name, symbol: symbol, colorIndex: color)
                    placeRaw = LibraryPlace.course(section.id).raw
                }
            }
            .sheet(item: $editingSection) { section in
                SectionEditor(name: section.name, symbol: section.symbol, colorIndex: section.colorIndex, isNew: false) { name, symbol, color in
                    var updated = section
                    updated.name = name
                    updated.symbol = symbol
                    updated.colorIndex = color
                    store.updateSection(updated)
                }
            }
            .alert(Loc.t("Yeniden adlandır"), isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField(Loc.t("Ad"), text: $renameText)
                Button(Loc.t("Kaydet")) {
                    if let note = renaming { store.rename(note.id, to: renameText) }
                    renaming = nil
                }
                Button(Loc.t("Vazgeç"), role: .cancel) { renaming = nil }
            }
            .confirmationDialog(Loc.t("Bu not silinsin mi?"), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                                titleVisibility: .visible) {
                Button(Loc.t("Sil"), role: .destructive) {
                    if let note = deleting { store.delete(note.id, apiKey: settings.apiKey) }
                    deleting = nil
                }
                Button(Loc.t("Vazgeç"), role: .cancel) { deleting = nil }
            } message: {
                Text(Loc.t("Not ve üzerindeki tüm yazılar kalıcı olarak silinir."))
            }
            .confirmationDialog(Loc.t("Ders silinsin mi?"), isPresented: Binding(get: { deletingSection != nil }, set: { if !$0 { deletingSection = nil } }),
                                titleVisibility: .visible) {
                Button(Loc.t("Dersi sil"), role: .destructive) {
                    if let s = deletingSection {
                        store.deleteSection(s.id)
                        studio.detachSection(s.id)
                        study.detachSection(s.id)
                        if place == .course(s.id) { placeRaw = LibraryPlace.home.raw }
                    }
                    deletingSection = nil
                }
                Button(Loc.t("Vazgeç"), role: .cancel) { deletingSection = nil }
            } message: {
                Text(Loc.t("Yalnızca ders klasörü kaldırılır; içindeki defterler, PDF'ler ve özetler kütüphanede kalır."))
            }
            .alert(Loc.t("Hata"), isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
                Button(Loc.t("Tamam"), role: .cancel) { errorText = nil }
            } message: {
                Text(errorText ?? "")
            }
        }
    }

    // MARK: Parts

    private var actions: LibraryActions {
        LibraryActions(
            open: { id in path.append(id) },
            go: { p in
                placeRaw = p.raw
                query = ""
                if !isRegular { withAnimation(.spring(response: 0.3)) { drawerShown = false } }
            },
            toggleSidebar: {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                    if isRegular { sidebarShown.toggle() } else { drawerShown.toggle() }
                }
            },
            newNotebook: { section in
                templateTarget = section
                showTemplates = true
            },
            createNotebook: { style, section in createNotebook(style, section: section) },
            importPDF: { section in
                importTarget = section
                showImporter = true
            },
            newCourse: { creatingSection = true },
            editCourse: { editingSection = $0 },
            deleteCourse: { deletingSection = $0 },
            rename: { note in
                renameText = note.title
                renaming = note
            },
            delete: { deleting = $0 },
            makeOverview: { section, kind, ids in
                studioRequest = StudioRequest(sectionID: section, kind: kind, preselected: ids)
            },
            play: { playing = $0 },
            makeStudy: { section, kind in studyRequest = StudyRequest(sectionID: section, kind: kind) },
            openStudy: { openedStudy = $0 },
            drop: { providers, section in handleDrop(providers, section: section) }
        )
    }

    private var sidebar: some View {
        LibrarySidebar(place: place, query: $query, actions: actions,
                       onSettings: { showSettings = true }, onVoices: { showVoices = true })
    }

    @ViewBuilder
    private var detail: some View {
        let showToggle = !(isRegular && sidebarShown)
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty {
            SearchPane(query: q, actions: actions, showToggle: showToggle)
        } else {
            switch place {
            case .home:
                HomePane(actions: actions, showToggle: showToggle)
            case .recent, .favorites, .notebooks, .pdfs:
                NotesPane(place: place, actions: actions, showToggle: showToggle)
            case .studio:
                StudioPane(actions: actions, showToggle: showToggle)
            case let .course(id):
                if let section = store.sections.first(where: { $0.id == id }) {
                    CoursePane(section: section, actions: actions, showToggle: showToggle)
                        .id(section.id)
                } else {
                    HomePane(actions: actions, showToggle: showToggle)
                }
            }
        }
    }

    @ViewBuilder
    private var finishedBanner: some View {
        if let id = studio.justFinished, let overview = studio.overview(id) {
            HStack(spacing: 14) {
                Image(systemName: overview.kind.symbol)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(Theme.ai, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(Loc.t("{0} hazır", "\(overview.kind.title)"))
                        .font(.subheadline.weight(.bold))
                    Text(overview.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 10)
                Button(Loc.t("Oynat")) {
                    studio.justFinished = nil
                    playing = overview
                }
                .buttonStyle(.borderedProminent)
                Button {
                    studio.justFinished = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: 520)
            .glassCard(radius: 22)
            .padding(.bottom, 24)
            .padding(.horizontal, 16)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .task(id: id) {
                try? await Task.sleep(nanoseconds: 9_000_000_000)
                if studio.justFinished == id { studio.justFinished = nil }
            }
        }
    }

    // MARK: Actions

    private func createNotebook(_ style: PaperStyle, section: UUID?) {
        let note = store.createNotebook(paper: style, section: section)
        path.append(note.id)
    }

    private func importFiles(_ result: Result<[URL], Error>) {
        switch result {
        case let .success(urls):
            var failed: [String] = []
            var lastID: UUID?
            for url in urls {
                do {
                    lastID = try store.importPDF(from: url, section: importTarget).id
                } catch {
                    failed.append(url.lastPathComponent)
                }
            }
            if !failed.isEmpty {
                errorText = Loc.t("Şu dosyalar açılamadı: ") + failed.joined(separator: ", ")
            } else if urls.count == 1, importTarget == nil, let lastID {
                path.append(lastID)
            }
        case let .failure(error):
            errorText = error.localizedDescription
        }
    }

    /// PDFs dragged in from Files or another app.
    private func handleDrop(_ providers: [NSItemProvider], section: UUID?) -> Bool {
        let pdfs = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) }
        guard !pdfs.isEmpty else { return false }
        let library = store
        for provider in pdfs {
            _ = provider.loadFileRepresentation(forTypeIdentifier: UTType.pdf.identifier) { url, _ in
                guard let url else { return }
                // The file is only there during this call: keep a copy with its own name.
                let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let copy = dir.appendingPathComponent(url.lastPathComponent)
                guard (try? FileManager.default.copyItem(at: url, to: copy)) != nil else { return }
                DispatchQueue.main.async {
                    _ = try? library.importPDF(from: copy, section: section)
                    try? FileManager.default.removeItem(at: dir)
                }
            }
        }
        return true
    }
}

// MARK: - Sidebar

struct LibrarySidebar: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var studio: StudioStore
    let place: LibraryPlace
    @Binding var query: String
    let actions: LibraryActions
    let onSettings: () -> Void
    let onVoices: () -> Void
    @State private var dropTarget: UUID?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    brand
                    searchField
                    quickCreate
                    WeekCard()
                    group(Loc.t("KÜTÜPHANE")) {
                        row(.home, Loc.t("Ana sayfa"), "house", "house.fill", count: nil)
                        row(.recent, Loc.t("Son çalışılanlar"), "clock", "clock.fill", count: nil)
                        row(.favorites, Loc.t("Favoriler"), "star", "star.fill", count: store.notes.filter(\.starred).count)
                        row(.notebooks, Loc.t("Defterler"), "book.closed", "book.closed.fill", count: store.notes.filter { $0.kind == .notebook }.count)
                        row(.pdfs, Loc.t("PDF'ler"), "doc.richtext", "doc.richtext.fill", count: store.notes.filter { $0.kind == .pdf }.count)
                        row(.studio, Loc.t("Stüdyo"), "sparkles.tv", "sparkles.tv.fill", count: studio.overviews.count + studio.jobs.count)
                    }
                    courses
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 20)
            }
            Divider()
            HStack(spacing: 8) {
                bottomButton(Loc.t("Sesler"), "person.wave.2", action: onVoices)
                bottomButton(Loc.t("Ayarlar"), "gearshape", action: onSettings)
            }
            .padding(12)
        }
        .background(.regularMaterial)
    }

    private var brand: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.ai)
                .frame(width: 44, height: 44)
                .overlay(Image(systemName: "pencil.and.scribble").font(.system(size: 20, weight: .bold)).foregroundStyle(.white))
                .shadow(color: Theme.aiStart.opacity(0.35), radius: 8, y: 4)
            VStack(alignment: .leading, spacing: 1) {
                Text(Loc.t("Mürekkep"))
                    .font(.title3.weight(.bold))
                    .fontDesign(.rounded)
                HStack(spacing: 4) {
                    Circle()
                        .fill(engineReady ? Color.green : Color.orange)
                        .frame(width: 6, height: 6)
                    Text(engineLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Button(action: actions.toggleSidebar) {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Loc.t("Kenar çubuğunu gizle"))
        }
    }

    private var engineLabel: String {
        if settings.engine == .claude { return "Claude · \(settings.model.title.replacingOccurrences(of: "Claude ", with: ""))" }
        if OnDeviceAI.isAvailable { return Loc.t("Cihazda yapay zekâ") }
        if !settings.serverURL.isEmpty { return Loc.t("Yerel sunucu") }
        return Loc.t("Çevrimdışı asistan")
    }

    private var engineReady: Bool {
        settings.engine == .claude ? settings.hasAPIKey : true
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(Loc.t("Notlarda ve özetlerde ara"), text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .font(.subheadline)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var quickCreate: some View {
        HStack(spacing: 10) {
            quickTile(Loc.t("Defter"), "square.and.pencil", AnyShapeStyle(Theme.ink.gradient)) { actions.newNotebook(currentCourse) }
            quickTile("PDF", "doc.badge.plus", AnyShapeStyle(Theme.ai)) { actions.importPDF(currentCourse) }
            quickTile(Loc.t("Ders"), "folder.badge.plus", AnyShapeStyle(Color(red: 0.92, green: 0.55, blue: 0.10).gradient)) { actions.newCourse() }
        }
    }

    private var currentCourse: UUID? {
        if case let .course(id) = place { return id }
        return nil
    }

    private func quickTile(_ title: String, _ symbol: String, _ fill: AnyShapeStyle, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .semibold))
                Text(title)
                    .font(.caption.weight(.bold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 62)
            .background(fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(Loc.t("Yeni {0}", "\(title)"))
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.heavy))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.bottom, 4)
            content()
        }
    }

    private func row(_ target: LibraryPlace, _ title: String, _ symbol: String, _ filled: String, count: Int?) -> some View {
        let on = place == target
        return Button {
            actions.go(target)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: on ? filled : symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 22)
                Text(title)
                    .font(.subheadline.weight(on ? .semibold : .regular))
                Spacer(minLength: 0)
                if let count, count > 0 {
                    Text("\(count)")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(on ? Theme.ink : Color.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(on ? Theme.ink.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var courses: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(Loc.t("DERSLER"))
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: actions.newCourse) {
                    Image(systemName: "plus")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 24, height: 24)
                        .background(Theme.ink.opacity(0.1), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Loc.t("Yeni ders"))
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 4)
            if store.sections.isEmpty {
                Button(action: actions.newCourse) {
                    HStack(spacing: 10) {
                        Image(systemName: "folder.badge.plus")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Loc.t("İlk dersini ekle"))
                                .font(.subheadline.weight(.semibold))
                            Text(Loc.t("Anatomi, Calculus… her dersin PDF'leri, defterleri ve özetleri bir arada."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    .foregroundStyle(Theme.ink)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Theme.ink.opacity(0.35), style: StrokeStyle(lineWidth: 1.2, dash: [5, 4])))
                }
                .buttonStyle(.plain)
            }
            ForEach(store.sections) { section in
                courseRow(section)
            }
        }
    }

    private func courseRow(_ section: NoteSection) -> some View {
        let on = place == .course(section.id)
        let count = store.notes.filter { $0.sectionID == section.id }.count
        let targeted = dropTarget == section.id
        return Button {
            actions.go(.course(section.id))
        } label: {
            HStack(spacing: 12) {
                Image(systemName: section.symbol)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(section.color.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                Text(section.name)
                    .font(.subheadline.weight(on ? .semibold : .regular))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if count > 0 {
                    Text("\(count)")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(on ? section.color : Color.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(on || targeted ? section.color.opacity(targeted ? 0.25 : 0.13) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onDrop(of: [.pdf], isTargeted: Binding(get: { dropTarget == section.id },
                                                set: { dropTarget = $0 ? section.id : (dropTarget == section.id ? nil : dropTarget) })) { providers in
            actions.drop(providers, section.id)
        }
        .contextMenu {
            Button {
                actions.importPDF(section.id)
            } label: {
                Label(Loc.t("PDF ekle"), systemImage: "doc.badge.plus")
            }
            Button {
                actions.makeOverview(section.id, .video, [])
            } label: {
                Label(Loc.t("Video özeti yap"), systemImage: "play.rectangle")
            }
            Button {
                actions.editCourse(section)
            } label: {
                Label(Loc.t("Düzenle"), systemImage: "pencil")
            }
            Button(role: .destructive) {
                actions.deleteCourse(section)
            } label: {
                Label(Loc.t("Dersi sil (içindekiler kalır)"), systemImage: "trash")
            }
        }
    }

    private func bottomButton(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// This week's working days and the streak.
private struct WeekCard: View {
    @EnvironmentObject private var store: LibraryStore

    private var days: [Date] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let weekday = (cal.component(.weekday, from: today) + 5) % 7 // Monday = 0
        let monday = cal.date(byAdding: .day, value: -weekday, to: today) ?? today
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: monday) }
    }

    var body: some View {
        let streak = ActivityLog.streak
        let today = store.notes.filter { Calendar.current.isDateInToday($0.modified) }.count
        let letters = [Loc.t("Pt"), Loc.t("Sa"), Loc.t("Ça"), Loc.t("Pe"), Loc.t("Cu"), Loc.t("Ct"), Loc.t("Pz")]
        let week = days
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if streak > 1 {
                    Label(Loc.t("{0} gün", "\(streak)"), systemImage: "flame.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.orange)
                }
            }
            HStack(spacing: 0) {
                ForEach(week.indices, id: \.self) { i in
                    let day = week[i]
                    let worked = ActivityLog.worked(on: day)
                    let isToday = Calendar.current.isDateInToday(day)
                    VStack(spacing: 4) {
                        Text(letters[i % 7])
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Circle()
                            .fill(worked ? AnyShapeStyle(Theme.ai) : AnyShapeStyle(Color.primary.opacity(0.08)))
                            .frame(width: 22, height: 22)
                            .overlay {
                                Circle().strokeBorder(Theme.ink, lineWidth: isToday ? 2 : 0)
                            }
                            .overlay {
                                if worked {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 9, weight: .heavy))
                                        .foregroundStyle(.white)
                                }
                            }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            Text(today == 0 ? Loc.t("Bugün henüz bir şey yazmadın.") : Loc.t("Bugün {0} not üzerinde çalıştın.", "\(today)"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Shared pieces

/// Slight press-down feedback for cards.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct NoteCard: View {
    let note: NoteMeta
    @EnvironmentObject private var store: LibraryStore
    @State private var image: UIImage?

    var body: some View {
        let version = store.thumbnailVersions[note.id] ?? 0
        // A card scrolling back into view shows its cached cover at once, without a placeholder flash.
        let cover = image ?? store.cachedThumbnail(note.id, version: version)
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                // A small stack of sheets behind the cover.
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white)
                    .rotationEffect(.degrees(3))
                    .offset(x: 4, y: 3)
                    .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white)
                if let image = cover {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    Image(systemName: note.kind == .pdf ? "doc.richtext" : "note.text")
                        .font(.system(size: 34))
                        .foregroundStyle(.secondary)
                }
            }
            .aspectRatio(0.76, contentMode: .fit)
            .overlay(alignment: .topTrailing) {
                Text(note.kind == .pdf ? "PDF" : Loc.t("DEFTER"))
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(note.kind == .pdf ? AnyShapeStyle(Theme.ai) : AnyShapeStyle(Theme.ink), in: Capsule())
                    .padding(8)
            }
            .overlay(alignment: .topLeading) {
                if note.starred {
                    Image(systemName: "star.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.yellow)
                        .padding(6)
                        .background(.black.opacity(0.35), in: Circle())
                        .padding(7)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.14), radius: 10, y: 6)

            VStack(alignment: .leading, spacing: 3) {
                Text(note.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .foregroundStyle(.primary)
                HStack(spacing: 4) {
                    Text(Loc.t("{0} sayfa", "\(note.pageCount)"))
                    Text("·")
                    // A fixed label: the live ".relative" style redraws every card each second.
                    Text(note.modified.formatted(.relative(presentation: .named)))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
        .contentShape(Rectangle())
        .task(id: version) {
            image = await store.loadThumbnail(note.id, version: version)
        }
    }
}
