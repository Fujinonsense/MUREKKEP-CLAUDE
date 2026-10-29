import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Where the library is: a list in the sidebar or a course.
enum LibraryPlace: Hashable {
    /// All notes.
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
    /// Opens a note at a page (a search hit).
    var openAt: (UUID, Int) -> Void
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

/// How far photos picked together have come on their way into one PDF.
struct PhotoImportProgress: Equatable {
    var done: Int
    var total: Int
}

/// The library: the sidebar (the lists, the courses, the Studio, voices and Settings) beside the
/// notes, each shown as its own first page. In black and white it is plain paper; a Pro theme lays
/// its picture behind it.
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
    @State private var askImportSource = false
    @State private var showPhotoPicker = false
    @State private var pickedPhotos: [PhotosPickerItem] = []
    @State private var photoProgress: PhotoImportProgress?
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
                        .frame(width: 288)
                        .transition(.move(edge: .leading))
                    Rectangle()
                        .fill(Theme.hairline)
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
                            .frame(width: 288)
                            .transition(.move(edge: .leading))
                    }
                }
            }
            .overlay(alignment: .bottom) {
                VStack(spacing: 10) {
                    photoProgressBanner
                    finishedBanner
                }
            }
            .modifier(LibraryBackdrop())
            // The editor's back button reads "‹ Notlar".
            .navigationTitle(Loc.t("Notlar"))
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: UUID.self) { id in
                if let note = store.note(id) {
                    EditorScreen(meta: note, store: store, settings: settings)
                        .toolbar(.visible, for: .navigationBar)
                } else {
                    Text(Loc.t("Not bulunamadı"))
                }
            }
            #if DEMO
            // The ad recordings (tools/demo) open their notebook and play their scene.
            .onReceive(NotificationCenter.default.publisher(for: DemoStage.openNote)) { note in
                if let id = note.object as? UUID { path = [id] }
            }
            // They go back to the library and type into its search field.
            .onReceive(NotificationCenter.default.publisher(for: DemoStage.library)) { _ in
                path = []
            }
            .onReceive(NotificationCenter.default.publisher(for: DemoStage.search)) { note in
                query = note.object as? String ?? ""
            }
            .task { await DemoStage.shared.begin(store: store, settings: settings) }
            #endif
            .confirmationDialog(Loc.t("PDF ya da fotoğraf ekle"), isPresented: $askImportSource, titleVisibility: .visible) {
                Button(Loc.t("Dosyalar'dan (PDF ya da fotoğraf)")) { showImporter = true }
                Button(Loc.t("Fotoğraflar'dan")) { showPhotoPicker = true }
                Button(Loc.t("Vazgeç"), role: .cancel) {}
            } message: {
                Text(Loc.t("Fotoğraflar tek bir PDF olur, her fotoğraf bir sayfa."))
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.pdf, .image], allowsMultipleSelection: true) { result in
                importFiles(result)
            }
            .photosPicker(isPresented: $showPhotoPicker, selection: $pickedPhotos, maxSelectionCount: 30, matching: .images)
            .onChange(of: pickedPhotos) { _, items in
                guard !items.isEmpty else { return }
                pickedPhotos = []
                importPicked(items)
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
            openAt: { id, page in
                if var meta = store.note(id) {
                    meta.lastPage = page
                    store.update(meta)
                }
                path.append(id)
            },
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
                askImportSource = true
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
            case .home, .recent, .favorites, .notebooks, .pdfs:
                NotesPane(place: place, actions: actions, showToggle: showToggle)
            case .studio:
                StudioPane(actions: actions, showToggle: showToggle)
            case let .course(id):
                if let section = store.sections.first(where: { $0.id == id }) {
                    CoursePane(section: section, actions: actions, showToggle: showToggle)
                        .id(section.id)
                } else {
                    NotesPane(place: .home, actions: actions, showToggle: showToggle)
                }
            }
        }
    }

    @ViewBuilder
    private var finishedBanner: some View {
        if let id = studio.justFinished, let overview = studio.overview(id) {
            HStack(spacing: 14) {
                Image(systemName: overview.kind.symbol)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(Loc.t("{0} hazır", "\(overview.kind.title)"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.text)
                    Text(overview.title)
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 10)
                Button(Loc.t("Oynat")) {
                    studio.justFinished = nil
                    playing = overview
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.ink)
                Button {
                    studio.justFinished = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.muted)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Loc.t("Kapat"))
            }
            .padding(14)
            .frame(maxWidth: 520)
            .glassCard(radius: 16, floating: true)
            .padding(.bottom, 24)
            .padding(.horizontal, 16)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .task(id: id) {
                try? await Task.sleep(nanoseconds: 9_000_000_000)
                if studio.justFinished == id { studio.justFinished = nil }
            }
        }
    }

    /// Photos becoming a PDF: the count, so thirty photos do not look like a hang.
    @ViewBuilder
    private var photoProgressBanner: some View {
        if let p = photoProgress {
            HStack(spacing: 14) {
                ProgressView()
                VStack(alignment: .leading, spacing: 6) {
                    Text(Loc.t("Fotoğraflar PDF'e dönüştürülüyor ({0}/{1})", "\(p.done)", "\(p.total)"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.text)
                    ProgressView(value: Double(p.done), total: Double(max(p.total, 1)))
                        .tint(Theme.ink)
                }
            }
            .padding(14)
            .frame(maxWidth: 520)
            .glassCard(radius: 16, floating: true)
            .padding(.bottom, 24)
            .padding(.horizontal, 16)
            .transition(.move(edge: .bottom).combined(with: .opacity))
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
            var added: [UUID] = []
            let target = importTarget
            // Photos picked together become one PDF; PDFs come in as they are.
            let photos = urls.filter { Self.isPhoto($0) }
            for url in urls where !Self.isPhoto(url) {
                do {
                    added.append(try store.importPDF(from: url, section: target).id)
                } catch {
                    failed.append(url.lastPathComponent)
                }
            }
            guard !photos.isEmpty else {
                finishImport(added: added, failed: failed, section: target)
                return
            }
            let title = LibraryStore.photoTitle(fileName: photos[0].lastPathComponent)
            let pdfsAdded = added
            let pdfsFailed = failed
            showPhotoProgress(PhotoImportProgress(done: 0, total: photos.count))
            Task { @MainActor in
                // The files are read off the main thread too: thirty photos are many megabytes.
                let data = await Task.detached(priority: .userInitiated) {
                    photos.compactMap { url -> Data? in
                        let scoped = url.startAccessingSecurityScopedResource()
                        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                        return try? Data(contentsOf: url)
                    }
                }.value
                var added = pdfsAdded
                var failed = pdfsFailed
                do {
                    added.append(try await convertPhotos(data, title: title, section: target).id)
                } catch {
                    failed += photos.map(\.lastPathComponent)
                }
                finishImport(added: added, failed: failed, section: target)
            }
        case let .failure(error):
            errorText = error.localizedDescription
        }
    }

    /// After an import: the files that failed, or straight into the one note that came in.
    private func finishImport(added: [UUID], failed: [String], section: UUID?) {
        if !failed.isEmpty {
            errorText = Loc.t("Şu dosyalar açılamadı: ") + failed.joined(separator: ", ")
        } else if added.count == 1, section == nil {
            path.append(added[0])
        }
    }

    private static func isPhoto(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .image)
    }

    /// Photos picked from the Photos library, as one PDF.
    private func importPicked(_ items: [PhotosPickerItem]) {
        let section = importTarget
        showPhotoProgress(PhotoImportProgress(done: 0, total: items.count))
        Task { @MainActor in
            var photos: [Data] = []
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self) { photos.append(data) }
            }
            do {
                let note = try await convertPhotos(photos, title: LibraryStore.photoTitle(fileName: nil), section: section)
                if section == nil { path.append(note.id) }
            } catch {
                errorText = error.localizedDescription
            }
        }
    }

    /// Photos picked together, as one PDF: the store writes it off the main thread while the count
    /// shows over the library; the note is added here, on the main actor, when they are done.
    @MainActor
    private func convertPhotos(_ photos: [Data], title: String, section: UUID?) async throws -> NoteMeta {
        showPhotoProgress(PhotoImportProgress(done: 0, total: photos.count))
        defer { showPhotoProgress(nil) }
        return try await store.importPhotos(photos, title: title, section: section) { done, total in
            photoProgress = PhotoImportProgress(done: done, total: total)
        }
    }

    private func showPhotoProgress(_ progress: PhotoImportProgress?) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { photoProgress = progress }
    }

    /// PDFs and photos dragged in from Files, Photos or another app (photos dropped together become
    /// one PDF).
    private func handleDrop(_ providers: [NSItemProvider], section: UUID?) -> Bool {
        let pdfs = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) }
        let photos = providers.filter {
            !$0.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) && $0.hasItemConformingToTypeIdentifier(UTType.image.identifier)
        }
        guard !pdfs.isEmpty || !photos.isEmpty else { return false }
        let library = store
        if !photos.isEmpty {
            let group = DispatchGroup()
            let lock = NSLock()
            var loaded: [Int: Data] = [:]
            for (i, provider) in photos.enumerated() {
                group.enter()
                _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    if let data {
                        lock.lock()
                        loaded[i] = data
                        lock.unlock()
                    }
                    group.leave()
                }
            }
            let name = photos[0].suggestedName
            group.notify(queue: .main) {
                let data = loaded.keys.sorted().compactMap { loaded[$0] }
                Task { @MainActor in
                    _ = try? await convertPhotos(data, title: LibraryStore.photoTitle(fileName: name), section: section)
                }
            }
        }
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

/// The sidebar: the wordmark, search, the lists with their counts, the courses, and pinned at the
/// bottom the Studio, the voices and Settings. One even surface for its full height, under the
/// status bar and the home indicator too: paper-2 in black and white (and on the ruled paper), an
/// even frosted panel on a Pro theme's picture.
struct LibrarySidebar: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var studio: StudioStore
    @Environment(\.onPicture) private var onPicture
    let place: LibraryPlace
    @Binding var query: String
    let actions: LibraryActions
    let onSettings: () -> Void
    let onVoices: () -> Void
    @State private var dropTarget: UUID?

    private static let rowShape = RoundedRectangle(cornerRadius: 10, style: .continuous)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    brand
                    searchField
                    VStack(alignment: .leading, spacing: 2) {
                        row(.home, Loc.t("Tüm notlar"), "square.grid.2x2", count: store.notes.count)
                        row(.recent, Loc.t("Son açılanlar"), "clock", count: nil)
                        row(.favorites, Loc.t("Favoriler"), "star", count: nil)
                        row(.notebooks, Loc.t("Defterler"), "book.closed", count: store.notes.filter { $0.kind == .notebook }.count)
                        row(.pdfs, Loc.t("PDF'ler"), "doc.text", count: store.notes.filter { $0.kind == .pdf }.count)
                    }
                    courses
                }
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 16)
            }
            Rectangle()
                .fill(Theme.hairline)
                .frame(height: 1)
            VStack(alignment: .leading, spacing: 2) {
                tool(Loc.t("Stüdyo"), "play.rectangle", active: place == .studio) { actions.go(.studio) }
                tool(Loc.t("Sesler"), "person.wave.2", active: false, action: onVoices)
                tool(Loc.t("Ayarlar"), "gearshape", active: false, action: onSettings)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background {
            Group {
                if onPicture {
                    // Frosted evenly: paper-2 at 0.80 over the thinnest material, so the picture
                    // shows only as a faint blur and no band of it reads darker or lighter, the
                    // bottom block included.
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .overlay(Theme.paper2.opacity(0.80))
                } else {
                    Theme.paper2
                }
            }
            .ignoresSafeArea()
        }
    }

    private var brand: some View {
        HStack(spacing: 8) {
            Text(Loc.t("Mürekkep"))
                .font(.title2.weight(.bold))
                .kerning(-0.4)
                .foregroundStyle(Theme.text)
                .lineLimit(1)
            Spacer(minLength: 0)
            Button(action: actions.toggleSidebar) {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.text2)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Loc.t("Kenar çubuğunu gizle"))
        }
        .frame(height: 44)
        .padding(.leading, 8)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.muted)
            TextField(Loc.t("Ara"), text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(Theme.text)
                .accessibilityLabel(Loc.t("Notlarda ve özetlerde ara"))
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.muted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Loc.t("Aramayı temizle"))
            }
        }
        .font(.body)
        .padding(.horizontal, 11)
        .frame(height: 38)
        .background(Theme.paper, in: Self.rowShape)
        .overlay(Self.rowShape.strokeBorder(Theme.hairline, lineWidth: 1))
    }

    private var currentCourse: UUID? {
        if case let .course(id) = place { return id }
        return nil
    }

    /// One line of the sidebar: an icon, the name, and on the right a count.
    private func line(_ title: String, _ symbol: String, count: Int?, on: Bool, tint: Color? = nil) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(tint ?? (on ? Theme.text : Theme.text2))
                .frame(width: 22)
            Text(title)
                .font(.body.weight(on ? .semibold : .regular))
                .foregroundStyle(on ? Theme.text : Theme.text2)
                .lineLimit(1)
            Spacer(minLength: 0)
            if let count, count > 0 {
                Text("\(count)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Theme.muted)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 40)
        .background(on ? Theme.paper3 : Color.clear, in: Self.rowShape)
        .contentShape(Rectangle())
    }

    private func row(_ target: LibraryPlace, _ title: String, _ symbol: String, count: Int?) -> some View {
        let on = place == target
        return Button {
            actions.go(target)
        } label: {
            line(title, symbol, count: count, on: on)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func tool(_ title: String, _ symbol: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            line(title, symbol, count: nil, on: active)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private var courses: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(Loc.t("Kurslar"))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.muted)
                Spacer()
                Button(action: actions.newCourse) {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.text2)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Loc.t("Yeni ders"))
            }
            .padding(.leading, 10)
            .frame(height: 36)
            if store.sections.isEmpty {
                Button(action: actions.newCourse) {
                    Text(Loc.t("İlk dersini ekle"))
                        .font(.body)
                        .foregroundStyle(Theme.muted)
                        .padding(.horizontal, 10)
                        .frame(height: 40)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
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
            line(section.name, section.symbol, count: count, on: on || targeted, tint: section.color)
                .overlay(Self.rowShape.strokeBorder(targeted ? Theme.ink : Color.clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
        .onDrop(of: [.pdf, .image], isTargeted: Binding(get: { dropTarget == section.id },
                                                set: { dropTarget = $0 ? section.id : (dropTarget == section.id ? nil : dropTarget) })) { providers in
            actions.drop(providers, section.id)
        }
        .contextMenu {
            Button {
                actions.importPDF(section.id)
            } label: {
                Label(Loc.t("PDF ya da fotoğraf ekle"), systemImage: "doc.badge.plus")
            }
            Button {
                actions.newNotebook(section.id)
            } label: {
                Label(Loc.t("Yeni defter"), systemImage: "square.and.pencil")
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

/// A note in the library: its first page as the cover, its name, and "3 sayfa, dün" under it. On a
/// Pro theme's picture the three stand on a plate of their own (PicturePlate); in black and white
/// they lie straight on the paper.
struct NoteCard: View {
    let note: NoteMeta
    @EnvironmentObject private var store: LibraryStore
    @State private var image: UIImage?

    private static let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)

    var body: some View {
        let version = store.thumbnailVersions[note.id] ?? 0
        // A card scrolling back into view shows its cached cover at once, without a placeholder flash.
        let cover = image ?? store.cachedThumbnail(note.id, version: version)
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                // The page is paper, white at night too.
                Self.shape
                    .fill(Color.white)
                if let image = cover {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .clipShape(Self.shape)
                } else {
                    Image(systemName: note.kind == .pdf ? "doc.text" : "note.text")
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(Theme.muted)
                }
            }
            .aspectRatio(0.75, contentMode: .fit)
            .clipped()
            .overlay(Self.shape.strokeBorder(Theme.hairline, lineWidth: 1))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(note.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    if note.starred {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(Theme.muted)
                            .accessibilityLabel(Loc.t("Favori"))
                    }
                }
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
        }
        .picturePlate()
        .contentShape(Rectangle())
        .task(id: version) {
            image = await store.loadThumbnail(note.id, version: version)
        }
    }

    /// "3 sayfa, dün"; a PDF says so first: "PDF, 204 sayfa, 1 saat önce". A fixed text: the live
    /// ".relative" style would redraw every card each second.
    private var detail: String {
        let pages = Loc.t("{0} sayfa", "\(note.pageCount)")
        let when = note.modified.formatted(.relative(presentation: .named))
        return (note.kind == .pdf ? "PDF, " : "") + pages + ", " + when
    }
}
