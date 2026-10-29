import SwiftUI
import UniformTypeIdentifiers

// MARK: - Shared

/// The big title at the top of a pane, with the sidebar's toggle when the sidebar is away and the
/// pane's buttons on the right.
struct PaneHeader<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    let showToggle: Bool
    let actions: LibraryActions
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if showToggle {
                SidebarToggle(actions: actions)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Theme.display(.largeTitle))
                    .kerning(-0.8)
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 10)
            ProCornerButton()
            trailing()
        }
        .padding(.top, 24)
    }
}

/// Shows the sidebar again when it is hidden.
struct SidebarToggle: View {
    let actions: LibraryActions

    var body: some View {
        Button(action: actions.toggleSidebar) {
            Image(systemName: "sidebar.left")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Theme.text2)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Loc.t("Kenar çubuğunu göster"))
    }
}

/// A pane's page (the notes, a course, the search): its header (title, buttons, filter and sort) on
/// the theme's picture, then what it holds on the notes' wash (NotesWash), which runs the pane's
/// full width from just above the first row to the bottom of the pane and scrolls with the notes.
struct PaneScroll<Header: View, Content: View>: View {
    @ViewBuilder var header: () -> Header
    @ViewBuilder var content: () -> Content

    var body: some View {
        GeometryReader { pane in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 24) {
                        header()
                    }
                    .padding(.horizontal, 40)
                    VStack(alignment: .leading, spacing: 24) {
                        content()
                    }
                    .padding(.horizontal, 40)
                    .padding(.top, 24)
                    .padding(.bottom, 40)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .modifier(NotesWash(reach: pane.size.height))
                }
            }
        }
    }
}

/// The library's buttons: quiet (a hairline on paper) or filled (ink on paper), 40 points tall
/// with a 44-point touch.
struct LibraryButton: View {
    let title: String
    var filled = false
    let action: () -> Void

    init(_ title: String, filled: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.filled = filled
        self.action = action
    }

    private static let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(filled ? Theme.paper : Theme.text)
                .lineLimit(1)
                .padding(.horizontal, 16)
                .frame(height: 40)
                .background(filled ? Theme.text : Theme.paper2, in: Self.shape)
                .overlay(Self.shape.strokeBorder(filled ? Color.clear : Theme.hairline, lineWidth: 1))
                .padding(.vertical, 2)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }
}

struct SectionTitle: View {
    let title: String
    var action: (title: String, run: () -> Void)? = nil

    var body: some View {
        HStack {
            Text(title)
                .font(Theme.display(.title3, weight: .semibold))
                .foregroundStyle(Theme.text)
            Spacer()
            if let action {
                Button(action.title, action: action.run)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
            }
        }
    }
}

/// Grid of notes with their context menu: four across on an iPad in landscape.
struct NoteGrid: View {
    @EnvironmentObject private var store: LibraryStore
    let notes: [NoteMeta]
    let actions: LibraryActions

    private let columns = [GridItem(.adaptive(minimum: 190, maximum: 260), spacing: 28)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 32) {
            ForEach(notes) { note in
                Button {
                    actions.open(note.id)
                } label: {
                    NoteCard(note: note)
                }
                .buttonStyle(PressableStyle())
                .contextMenu {
                    NoteMenu(note: note, store: store, actions: actions)
                }
            }
        }
    }
}

struct NoteMenu: View {
    let note: NoteMeta
    let store: LibraryStore
    let actions: LibraryActions

    var body: some View {
        Button {
            store.toggleFavorite(note.id)
        } label: {
            Label(note.starred ? Loc.t("Favorilerden çıkar") : Loc.t("Favorilere ekle"), systemImage: note.starred ? "star.slash" : "star")
        }
        Button {
            actions.rename(note)
        } label: {
            Label(Loc.t("Yeniden adlandır"), systemImage: "pencil")
        }
        Menu {
            ForEach(store.sections) { section in
                Button {
                    store.move(note.id, to: section.id)
                } label: {
                    Label(section.name, systemImage: note.sectionID == section.id ? "checkmark" : section.symbol)
                }
            }
            if note.sectionID != nil {
                Divider()
                Button {
                    store.move(note.id, to: nil)
                } label: {
                    Label(Loc.t("Dersten çıkar"), systemImage: "tray")
                }
            }
            Divider()
            Button {
                actions.newCourse()
            } label: {
                Label(Loc.t("Yeni ders…"), systemImage: "plus")
            }
        } label: {
            Label(Loc.t("Derse taşı"), systemImage: "folder")
        }
        Menu {
            Button {
                actions.makeOverview(note.sectionID, .video, [note.id])
            } label: {
                Label(Loc.t("Video özeti"), systemImage: OverviewKind.video.symbol)
            }
            Button {
                actions.makeOverview(note.sectionID, .audio, [note.id])
            } label: {
                Label(Loc.t("Sesli özet"), systemImage: OverviewKind.audio.symbol)
            }
        } label: {
            Label(Loc.t("Bundan özet yap"), systemImage: "sparkles")
        }
        Divider()
        Button(role: .destructive) {
            actions.delete(note)
        } label: {
            Label(Loc.t("Sil"), systemImage: "trash")
        }
    }
}

/// A dashed box to drop PDFs on, with a button for the file picker.
struct DropZone: View {
    let title: String
    let detail: String
    let isTargeted: Bool
    let onPick: () -> Void

    private static let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: isTargeted ? "arrow.down.doc.fill" : "doc.badge.plus")
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(isTargeted ? Theme.ink : Theme.text2)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(isTargeted ? Loc.t("Bırak, ekleyelim") : title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.text)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 10)
            LibraryButton(Loc.t("Dosya seç"), action: onPick)
        }
        .padding(16)
        .background(Self.shape.fill(isTargeted ? Theme.ink.opacity(0.06) : Theme.paper2))
        .overlay(Self.shape.strokeBorder(isTargeted ? Theme.ink : Theme.hairline, style: StrokeStyle(lineWidth: 1, dash: [6, 4])))
        .animation(.easeInOut(duration: 0.2), value: isTargeted)
    }
}

/// The "Yeni" menu of the Studio pane: new notebook, PDF, course or overview.
struct NewMenu: View {
    let actions: LibraryActions
    let section: UUID?

    private static let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)

    var body: some View {
        Menu {
            Button {
                actions.newNotebook(section)
            } label: {
                Label(Loc.t("Yeni defter"), systemImage: "square.and.pencil")
            }
            Button {
                actions.importPDF(section)
            } label: {
                Label(Loc.t("PDF içe aktar"), systemImage: "doc.badge.plus")
            }
            Button {
                actions.newCourse()
            } label: {
                Label(Loc.t("Yeni ders"), systemImage: "folder.badge.plus")
            }
            Divider()
            Button {
                actions.makeOverview(section, .video, [])
            } label: {
                Label(Loc.t("Video özeti"), systemImage: OverviewKind.video.symbol)
            }
            Button {
                actions.makeOverview(section, .audio, [])
            } label: {
                Label(Loc.t("Sesli özet"), systemImage: OverviewKind.audio.symbol)
            }
        } label: {
            Label(Loc.t("Yeni"), systemImage: "plus")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 16)
                .frame(height: 40)
                .background(Theme.paper2, in: Self.shape)
                .overlay(Self.shape.strokeBorder(Theme.hairline, lineWidth: 1))
                .padding(.vertical, 2)
                .contentShape(Rectangle())
        }
    }
}

// MARK: - Notes

/// The notes: all of them (with the Hepsi / Defterler / PDF'ler filter), the recent ones, the
/// favourites, the notebooks or the PDFs, sorted by the last edit or by name, each shown as its
/// first page.
struct NotesPane: View {
    @EnvironmentObject private var store: LibraryStore
    let place: LibraryPlace
    let actions: LibraryActions
    let showToggle: Bool
    @AppStorage("library.filter") private var filterRaw = NoteFilter.all.rawValue
    @AppStorage("library.sort") private var sortRaw = NoteSort.modified.rawValue
    @State private var dropping = false

    enum NoteFilter: String, CaseIterable, Identifiable {
        case all
        case notebooks
        case pdfs

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: return Loc.t("Hepsi")
            case .notebooks: return Loc.t("Defterler")
            case .pdfs: return Loc.t("PDF'ler")
            }
        }
    }

    enum NoteSort: String, CaseIterable, Identifiable {
        case modified
        case title

        var id: String { rawValue }

        var title: String {
            switch self {
            case .modified: return Loc.t("Son düzenlenen")
            case .title: return Loc.t("Ada göre")
            }
        }
    }

    private var filter: NoteFilter { NoteFilter(rawValue: filterRaw) ?? .all }
    private var sort: NoteSort { NoteSort(rawValue: sortRaw) ?? .modified }

    private var title: String {
        switch place {
        case .home: return Loc.t("Tüm notlar")
        case .recent: return Loc.t("Son açılanlar")
        case .favorites: return Loc.t("Favoriler")
        case .notebooks: return Loc.t("Defterler")
        case .pdfs: return Loc.t("PDF'ler")
        default: return Loc.t("Notlar")
        }
    }

    private var notes: [NoteMeta] {
        let list: [NoteMeta]
        switch place {
        case .recent: return Array(store.notes.sorted { $0.modified > $1.modified }.prefix(40))
        case .favorites: list = store.notes.filter(\.starred)
        case .notebooks: list = store.notes.filter { $0.kind == .notebook }
        case .pdfs: list = store.notes.filter { $0.kind == .pdf }
        default:
            switch filter {
            case .all: list = store.notes
            case .notebooks: list = store.notes.filter { $0.kind == .notebook }
            case .pdfs: list = store.notes.filter { $0.kind == .pdf }
            }
        }
        switch sort {
        case .modified: return list.sorted { $0.modified > $1.modified }
        case .title: return list.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }
    }

    var body: some View {
        PaneScroll {
            PaneHeader(title: title, showToggle: showToggle, actions: actions) {
                LibraryButton(Loc.t("PDF içe aktar")) { actions.importPDF(nil) }
                LibraryButton(Loc.t("Yeni not"), filled: true) { actions.newNotebook(nil) }
            }
            HStack(spacing: 12) {
                if place == .home {
                    Picker(Loc.t("Göster"), selection: $filterRaw) {
                        ForEach(NoteFilter.allCases) { f in
                            Text(f.title).tag(f.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 320)
                }
                Spacer(minLength: 0)
                if place != .recent {
                    sortMenu
                }
            }
        } content: {
            if place == .pdfs {
                DropZone(title: Loc.t("PDF'leri buraya sürükle"), detail: Loc.t("Dosyalar'dan ya da başka bir uygulamadan bırakabilirsin."),
                         isTargeted: dropping) { actions.importPDF(nil) }
            }
            if notes.isEmpty {
                empty
                    .frame(maxWidth: .infinity)
                    .padding(.top, 30)
            } else {
                NoteGrid(notes: notes, actions: actions)
            }
        }
        .onDrop(of: [.pdf, .image], isTargeted: $dropping) { providers in actions.drop(providers, nil) }
        .overlay {
            if dropping && place != .pdfs {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Theme.ink, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                    .background(Theme.ink.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(Label(Loc.t("PDF'leri kütüphaneye bırak"), systemImage: "arrow.down.doc").font(.headline).foregroundStyle(Theme.ink))
                    .padding(16)
                    .allowsHitTesting(false)
            }
        }
    }

    /// "Son düzenlenen ⌄": the order of the notes.
    private var sortMenu: some View {
        Menu {
            Picker(Loc.t("Sıralama"), selection: $sortRaw) {
                ForEach(NoteSort.allCases) { s in
                    Text(s.title).tag(s.rawValue)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(sort.title)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
            }
            .font(.subheadline)
            .foregroundStyle(Theme.text2)
            .padding(.horizontal, 10)
            .frame(height: 36)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(Loc.t("Sıralama"))
    }

    @ViewBuilder
    private var empty: some View {
        switch place {
        case .favorites:
            ContentUnavailableView(Loc.t("Favori yok"), systemImage: "star",
                                   description: Text(Loc.t("Bir notu basılı tutup \"Favorilere ekle\"yi seç.")))
        case .notebooks:
            ContentUnavailableView(Loc.t("Defter yok"), systemImage: "book.closed",
                                   description: Text(Loc.t("Sağ üstteki \"Yeni not\" ile bir şablon seç.")))
        case .pdfs:
            ContentUnavailableView(Loc.t("PDF yok"), systemImage: "doc.text",
                                   description: Text(Loc.t("Ders notlarını, kitap bölümlerini ve makaleleri buraya ekle.")))
        default:
            ContentUnavailableView(Loc.t("Henüz not yok"), systemImage: "square.and.pencil",
                                   description: Text(Loc.t("Yeni bir defter aç ya da PDF içe aktar.")))
        }
    }
}

struct SearchPane: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var studio: StudioStore
    let query: String
    let actions: LibraryActions
    let showToggle: Bool
    /// Words found inside the notes (PDF text, read pages, handwriting).
    @State private var hits: [ContentHit] = []
    @State private var searching = false

    var body: some View {
        let notes = store.notes.filter { note in
            note.title.localizedCaseInsensitiveContains(query)
                || (store.sections.first { $0.id == note.sectionID }?.name.localizedCaseInsensitiveContains(query) ?? false)
        }
        let overviews = studio.overviews.filter { $0.title.localizedCaseInsensitiveContains(query) }
        let courses = store.sections.filter { $0.name.localizedCaseInsensitiveContains(query) }
        PaneScroll {
            // Every row below counts, the places found inside the notes too.
            PaneHeader(title: "“\(query)”", subtitle: Loc.t("{0} sonuç", "\(notes.count + overviews.count + courses.count + hits.count)"),
                       showToggle: showToggle, actions: actions) {
                EmptyView()
            }
        } content: {
            if notes.isEmpty && overviews.isEmpty && courses.isEmpty && hits.isEmpty && !searching {
                ContentUnavailableView.search(text: query)
                    .frame(maxWidth: .infinity)
            }
            if !courses.isEmpty {
                SectionTitle(title: Loc.t("Dersler"))
                HStack(spacing: 12) {
                    ForEach(courses) { section in
                        Button {
                            actions.go(.course(section.id))
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: section.symbol)
                                    .foregroundStyle(section.color)
                                Text(section.name)
                                    .foregroundStyle(Theme.text)
                            }
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14)
                            .frame(height: 40)
                            .background(Theme.paper2, in: Capsule())
                            .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
                            .padding(.vertical, 2)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if !notes.isEmpty {
                SectionTitle(title: Loc.t("Notlar"))
                NoteGrid(notes: notes, actions: actions)
            }
            if !overviews.isEmpty {
                SectionTitle(title: Loc.t("Özetler"))
                OverviewGrid(overviews: overviews, actions: actions)
            }
            if searching || !hits.isEmpty {
                HStack(spacing: 10) {
                    SectionTitle(title: Loc.t("Notların içinde"))
                    if searching { ProgressView() }
                }
                VStack(spacing: 8) {
                    ForEach(hits) { h in
                        Button {
                            actions.openAt(h.note, h.page)
                        } label: {
                            hitRow(h)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .task(id: query) {
            hits = []
            searching = false
            guard query.count >= 2 else { return }
            searching = true
            // Typing on: only the last query is searched.
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            let all = store.notes
            let urls = Dictionary(uniqueKeysWithValues: all.filter { $0.kind == .pdf }.map { ($0.id, store.pdfURL(for: $0.id)) })
            let found = await ContentIndex.shared.search(query, notes: all, pdfURLs: urls)
            guard !Task.isCancelled else { return }
            hits = found
            searching = false
        }
        #if DEMO
        // The ad recordings (tools/demo) open the first hit, as a tap on it does.
        .onReceive(NotificationCenter.default.publisher(for: DemoStage.openHit)) { _ in
            if let h = hits.first { actions.openAt(h.note, h.page) }
        }
        #endif
    }

    private func hitRow(_ h: ContentHit) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "text.magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.text2)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(h.title) · \(Loc.t("s. {0}", "\(h.page + 1)"))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                (Text(h.hit.before) + Text(h.hit.match).bold().foregroundStyle(Theme.ink) + Text(h.hit.after))
                    .font(.subheadline)
                    .foregroundStyle(Theme.text2)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: 12)
    }
}

// MARK: - Course

struct CoursePane: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var studio: StudioStore
    let section: NoteSection
    let actions: LibraryActions
    let showToggle: Bool
    @AppStorage("course.tab") private var tabRaw = CourseTab.sources.rawValue
    @State private var dropping = false

    enum CourseTab: String, CaseIterable, Identifiable {
        case sources
        case notebooks
        case studio

        var id: String { rawValue }

        var title: String {
            switch self {
            case .sources: return Loc.t("Kaynaklar")
            case .notebooks: return Loc.t("Defterler")
            case .studio: return Loc.t("Stüdyo")
            }
        }
    }

    private var tab: CourseTab { CourseTab(rawValue: tabRaw) ?? .sources }

    var body: some View {
        let notes = store.notes.filter { $0.sectionID == section.id }
        let pdfs = notes.filter { $0.kind == .pdf }
        let notebooks = notes.filter { $0.kind == .notebook }
        PaneScroll {
            header(pdfs: pdfs.count, notebooks: notebooks.count)
            Picker(Loc.t("Bölüm"), selection: $tabRaw) {
                ForEach(CourseTab.allCases) { t in
                    Text(t.title).tag(t.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 460)
        } content: {
            switch tab {
            case .sources:
                DropZone(title: Loc.t("Bu dersin PDF'lerini buraya sürükle"),
                         detail: Loc.t("Ders notları, slaytlar, kitap bölümleri. Asistan ve stüdyo hepsinden birlikte yararlanır."),
                         isTargeted: dropping) { actions.importPDF(section.id) }
                if pdfs.isEmpty {
                    Text(Loc.t("Henüz kaynak yok. PDF ekleyince buradan video ve sesli özet çıkarabilirsin."))
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                } else {
                    NoteGrid(notes: pdfs, actions: actions)
                }
            case .notebooks:
                HStack {
                    Text(notebooks.isEmpty ? Loc.t("Bu derste henüz defter yok.") : Loc.t("{0} defter", "\(notebooks.count)"))
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                    Spacer()
                    LibraryButton(Loc.t("Yeni defter")) { actions.newNotebook(section.id) }
                }
                NoteGrid(notes: notebooks, actions: actions)
            case .studio:
                StudioSection(sectionID: section.id, tint: section.color, actions: actions)
            }
        }
        .onDrop(of: [.pdf, .image], isTargeted: $dropping) { providers in
            tabRaw = CourseTab.sources.rawValue
            return actions.drop(providers, section.id)
        }
    }

    /// The course's name with its symbol, what it holds, and its buttons; the rest is in "Diğer".
    private func header(pdfs: Int, notebooks: Int) -> some View {
        let overviews = studio.overviews(in: section.id).count
        return HStack(alignment: .center, spacing: 12) {
            if showToggle {
                SidebarToggle(actions: actions)
            }
            Image(systemName: section.symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(section.color)
                .frame(width: 44, height: 44)
                .background(Theme.paper2, in: Circle())
                .overlay(Circle().strokeBorder(Theme.hairline, lineWidth: 1))
            VStack(alignment: .leading, spacing: 3) {
                Text(section.name)
                    .font(Theme.display(.largeTitle))
                    .kerning(-0.8)
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(Loc.t("{0} kaynak · {1} defter · {2} özet", "\(pdfs)", "\(notebooks)", "\(overviews)"))
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 10)
            ProCornerButton()
            LibraryButton(Loc.t("PDF ya da fotoğraf ekle")) { actions.importPDF(section.id) }
            LibraryButton(Loc.t("Yeni not"), filled: true) { actions.newNotebook(section.id) }
            Menu {
                Button {
                    actions.makeOverview(section.id, .video, [])
                } label: {
                    Label(Loc.t("Video özeti"), systemImage: OverviewKind.video.symbol)
                }
                Button {
                    actions.makeOverview(section.id, .audio, [])
                } label: {
                    Label(Loc.t("Sesli özet"), systemImage: OverviewKind.audio.symbol)
                }
                Divider()
                Button {
                    actions.editCourse(section)
                } label: {
                    Label(Loc.t("Dersi düzenle"), systemImage: "pencil")
                }
                Button(role: .destructive) {
                    actions.deleteCourse(section)
                } label: {
                    Label(Loc.t("Dersi sil (içindekiler kalır)"), systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Theme.text2)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(Loc.t("Diğer"))
        }
        .padding(.top, 24)
    }
}
