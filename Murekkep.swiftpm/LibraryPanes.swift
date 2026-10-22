import SwiftUI
import UniformTypeIdentifiers

// MARK: - Shared

/// The big title at the top of a pane.
struct PaneHeader<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    let showToggle: Bool
    let actions: LibraryActions
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            if showToggle {
                Button(action: actions.toggleSidebar) {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 42, height: 42)
                        .background(Color.primary.opacity(0.06), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Loc.t("Kenar çubuğunu göster"))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Theme.display(.largeTitle))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 10)
            ProCornerButton()
            trailing()
        }
        .padding(.top, 18)
    }
}

struct SectionTitle: View {
    let title: String
    var action: (title: String, run: () -> Void)? = nil

    var body: some View {
        HStack {
            Text(title)
                .font(Theme.display(.title3))
            Spacer()
            if let action {
                Button(action.title, action: action.run)
                    .font(.subheadline.weight(.semibold))
            }
        }
    }
}

/// Grid of notes with their context menu.
struct NoteGrid: View {
    @EnvironmentObject private var store: LibraryStore
    let notes: [NoteMeta]
    let actions: LibraryActions

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 210), spacing: 22)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 26) {
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
    let tint: Color
    let isTargeted: Bool
    let onPick: () -> Void

    var body: some View {
        HStack(spacing: 18) {
            Image(systemName: isTargeted ? "arrow.down.doc.fill" : "doc.badge.plus")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 64, height: 64)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(isTargeted ? Loc.t("Bırak, ekleyelim") : title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 10)
            Button(action: onPick) {
                Label(Loc.t("Dosya seç"), systemImage: "folder")
            }
            .buttonStyle(.borderedProminent)
            .tint(tint)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(tint.opacity(isTargeted ? 0.14 : 0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(tint.opacity(isTargeted ? 0.9 : 0.35), style: StrokeStyle(lineWidth: 1.6, dash: [7, 5]))
        )
        .animation(.easeInOut(duration: 0.2), value: isTargeted)
    }
}

private struct StatTile: View {
    let value: Int
    let label: String
    let symbol: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: 42, height: 42)
                    .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(value)")
                        .font(Theme.display(.title2).monospacedDigit())
                    Text(label)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .glassCard(radius: 18)
        }
        .buttonStyle(PressableStyle())
        .foregroundStyle(.primary)
    }
}

struct CourseCard: View {
    let section: NoteSection
    let notes: Int
    let pdfs: Int
    let overviews: Int

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LinearGradient(colors: [section.color, section.color.opacity(0.72)], startPoint: .topLeading, endPoint: .bottomTrailing))
            Image(systemName: section.symbol)
                .font(.system(size: 84, weight: .bold))
                .foregroundStyle(.white.opacity(0.16))
                .rotationEffect(.degrees(-12))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.top, 8)
                .padding(.trailing, 6)
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: section.symbol)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(section.color)
                    .frame(width: 36, height: 36)
                    .background(.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                Spacer(minLength: 0)
                Text(section.name)
                    .font(Theme.display(.title3))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(Loc.t("{0} PDF · {1} defter · {2} özet", "\(pdfs)", "\(notes - pdfs)", "\(overviews)"))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(16)
        }
        .frame(height: 150)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: section.color.opacity(0.35), radius: 12, y: 6)
    }
}

// MARK: - Home

struct HomePane: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var studio: StudioStore
    @EnvironmentObject private var settings: AppSettings
    let actions: LibraryActions
    let showToggle: Bool
    @State private var dropping = false

    private static let quickTemplates: [PaperStyle] = [.lined, .grid, .dotted, .cornell, .weekly, .todo, .music]
    private let courseColumns = [GridItem(.adaptive(minimum: 230, maximum: 340), spacing: 18)]

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: return Loc.t("Günaydın")
        case 12..<18: return Loc.t("İyi çalışmalar")
        default: return Loc.t("İyi akşamlar")
        }
    }

    private var recent: [NoteMeta] {
        Array(store.notes.sorted { $0.modified > $1.modified }.prefix(10))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                PaneHeader(title: greeting, subtitle: Loc.t("Bugün ne çalışıyoruz? Bir ders aç, PDF bırak ya da yeni bir deftere başla."),
                           showToggle: showToggle, actions: actions) {
                    NewMenu(actions: actions, section: nil)
                }
                stats
                if !recent.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionTitle(title: Loc.t("Kaldığın yerden devam et"), action: (title: Loc.t("Tümü"), run: { actions.go(.recent) }))
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: 20) {
                                ForEach(recent) { note in
                                    Button {
                                        actions.open(note.id)
                                    } label: {
                                        NoteCard(note: note)
                                            .frame(width: 140)
                                    }
                                    .buttonStyle(PressableStyle())
                                    .contextMenu { NoteMenu(note: note, store: store, actions: actions) }
                                }
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 4)
                        }
                    }
                }
                courses
                studioBlock
                templates
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 40)
        }
        .onDrop(of: [.pdf], isTargeted: $dropping) { providers in actions.drop(providers, nil) }
        .overlay {
            if dropping {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(Theme.ink, style: StrokeStyle(lineWidth: 3, dash: [10, 8]))
                    .background(Theme.ink.opacity(0.06), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .overlay(Label(Loc.t("PDF'leri kütüphaneye bırak"), systemImage: "arrow.down.doc").font(.title3.weight(.bold)).foregroundStyle(Theme.ink))
                    .padding(16)
                    .allowsHitTesting(false)
            }
        }
    }

    private var stats: some View {
        let notebooks = store.notes.filter { $0.kind == .notebook }.count
        let pdfs = store.notes.count - notebooks
        return HStack(spacing: 14) {
            StatTile(value: notebooks, label: Loc.t("Defter"), symbol: "book.closed.fill", tint: Theme.ink) { actions.go(.notebooks) }
            StatTile(value: pdfs, label: "PDF", symbol: "doc.richtext.fill", tint: Theme.aiStart) { actions.go(.pdfs) }
            StatTile(value: store.sections.count, label: Loc.t("Ders"), symbol: "folder.fill", tint: Color(red: 0.92, green: 0.55, blue: 0.10)) {
                if let first = store.sections.first { actions.go(.course(first.id)) } else { actions.newCourse() }
            }
            StatTile(value: studio.overviews.count, label: Loc.t("Özet"), symbol: "sparkles.tv.fill", tint: Theme.aiEnd) { actions.go(.studio) }
        }
    }

    private var courses: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(title: Loc.t("Derslerin"))
            LazyVGrid(columns: courseColumns, alignment: .leading, spacing: 18) {
                ForEach(store.sections) { section in
                    let notes = store.notes.filter { $0.sectionID == section.id }
                    Button {
                        actions.go(.course(section.id))
                    } label: {
                        CourseCard(section: section, notes: notes.count, pdfs: notes.filter { $0.kind == .pdf }.count,
                                   overviews: studio.overviews(in: section.id).count)
                    }
                    .buttonStyle(PressableStyle())
                    .onDrop(of: [.pdf], isTargeted: nil) { providers in actions.drop(providers, section.id) }
                    .contextMenu {
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
                Button(action: actions.newCourse) {
                    VStack(spacing: 10) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 28, weight: .semibold))
                        Text(store.sections.isEmpty ? Loc.t("İlk dersini ekle") : Loc.t("Yeni ders"))
                            .font(.headline)
                        Text(Loc.t("PDF'ler, defterler ve özetler tek klasörde"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 150)
                    .background(RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Theme.ink.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [7, 5])))
                }
                .buttonStyle(PressableStyle())
            }
        }
    }

    @ViewBuilder
    private var studioBlock: some View {
        if studio.overviews.isEmpty && studio.jobs.isEmpty {
            StudioPromo(actions: actions, sectionID: nil)
        } else {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle(title: Loc.t("Son özetler"), action: (title: Loc.t("Stüdyo"), run: { actions.go(.studio) }))
                ForEach(studio.jobs) { job in
                    JobRow(job: job)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 18) {
                        ForEach(studio.overviews.prefix(8)) { overview in
                            Button {
                                actions.play(overview)
                            } label: {
                                OverviewCard(overview: overview)
                                    .frame(width: 270)
                            }
                            .buttonStyle(PressableStyle())
                        }
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 4)
                }
            }
        }
    }

    private var templates: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(title: Loc.t("Yeni defter"), action: (title: Loc.t("{0} şablonun tümü", "\(PaperStyle.allCases.count)"), run: { actions.newNotebook(nil) }))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(Self.quickTemplates) { style in
                        Button {
                            actions.createNotebook(style, nil)
                        } label: {
                            VStack(spacing: 8) {
                                PaperPreview(style: style)
                                    .frame(width: 92, height: 130)
                                Text(style.title)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                            }
                            .frame(width: 96)
                        }
                        .buttonStyle(PressableStyle())
                        .accessibilityLabel(Loc.t("Yeni defter: {0}", "\(style.title)"))
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 2)
            }
        }
    }
}

/// The "+" menu: new notebook, PDF or course.
struct NewMenu: View {
    let actions: LibraryActions
    let section: UUID?

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
                .font(.subheadline.weight(.bold))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Theme.ink, in: Capsule())
                .foregroundStyle(.white)
        }
    }
}

// MARK: - Lists

struct NotesPane: View {
    @EnvironmentObject private var store: LibraryStore
    let place: LibraryPlace
    let actions: LibraryActions
    let showToggle: Bool
    @State private var dropping = false

    private var title: String {
        switch place {
        case .recent: return Loc.t("Son çalışılanlar")
        case .favorites: return Loc.t("Favoriler")
        case .notebooks: return Loc.t("Defterler")
        case .pdfs: return Loc.t("PDF'ler")
        default: return Loc.t("Notlar")
        }
    }

    private var notes: [NoteMeta] {
        switch place {
        case .recent: return Array(store.notes.sorted { $0.modified > $1.modified }.prefix(40))
        case .favorites: return store.notes.filter(\.starred)
        case .notebooks: return store.notes.filter { $0.kind == .notebook }
        case .pdfs: return store.notes.filter { $0.kind == .pdf }
        default: return store.notes
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PaneHeader(title: title, subtitle: Loc.t("{0} not", "\(notes.count)"), showToggle: showToggle, actions: actions) {
                    NewMenu(actions: actions, section: nil)
                }
                if place == .pdfs {
                    DropZone(title: Loc.t("PDF'leri buraya sürükle"), detail: Loc.t("Dosyalar'dan ya da başka bir uygulamadan bırakabilirsin."),
                             tint: Theme.aiStart, isTargeted: dropping) { actions.importPDF(nil) }
                }
                if notes.isEmpty {
                    empty
                        .frame(maxWidth: .infinity)
                        .padding(.top, 30)
                } else {
                    NoteGrid(notes: notes, actions: actions)
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 40)
        }
        .onDrop(of: [.pdf], isTargeted: $dropping) { providers in actions.drop(providers, nil) }
    }

    @ViewBuilder
    private var empty: some View {
        switch place {
        case .favorites:
            ContentUnavailableView(Loc.t("Favori yok"), systemImage: "star",
                                   description: Text(Loc.t("Bir notu basılı tutup \"Favorilere ekle\"yi seç.")))
        case .notebooks:
            ContentUnavailableView(Loc.t("Defter yok"), systemImage: "book.closed",
                                   description: Text(Loc.t("Sol üstten \"Defter\"e dokunup bir şablon seç.")))
        case .pdfs:
            ContentUnavailableView(Loc.t("PDF yok"), systemImage: "doc.richtext",
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
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PaneHeader(title: "“\(query)”", subtitle: Loc.t("{0} sonuç", "\(notes.count + overviews.count + courses.count)"),
                           showToggle: showToggle, actions: actions) {
                    EmptyView()
                }
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
                                Label(section.name, systemImage: section.symbol)
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 9)
                                    .background(section.color.opacity(0.14), in: Capsule())
                                    .foregroundStyle(section.color)
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
            .padding(.horizontal, 28)
            .padding(.bottom, 40)
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
    }

    private func hitRow(_ h: ContentHit) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "text.magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .frame(width: 32, height: 32)
                .background(Theme.ink.opacity(0.1), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text("\(h.title) · \(Loc.t("s. {0}", "\(h.page + 1)"))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                (Text(h.hit.before) + Text(h.hit.match).bold().foregroundStyle(Theme.ink) + Text(h.hit.after))
                    .font(.subheadline)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: 14)
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
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                banner(pdfs: pdfs.count, notebooks: notebooks.count)
                Picker(Loc.t("Bölüm"), selection: $tabRaw) {
                    ForEach(CourseTab.allCases) { t in
                        Text(t.title).tag(t.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 460)
                switch tab {
                case .sources:
                    DropZone(title: Loc.t("Bu dersin PDF'lerini buraya sürükle"),
                             detail: Loc.t("Ders notları, slaytlar, kitap bölümleri. Asistan ve stüdyo hepsinden birlikte yararlanır."),
                             tint: section.color, isTargeted: dropping) { actions.importPDF(section.id) }
                    if pdfs.isEmpty {
                        Text(Loc.t("Henüz kaynak yok. PDF ekleyince buradan video ve sesli özet çıkarabilirsin."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        NoteGrid(notes: pdfs, actions: actions)
                    }
                case .notebooks:
                    HStack {
                        Text(notebooks.isEmpty ? Loc.t("Bu derste henüz defter yok.") : Loc.t("{0} defter", "\(notebooks.count)"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            actions.newNotebook(section.id)
                        } label: {
                            Label(Loc.t("Yeni defter"), systemImage: "square.and.pencil")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(section.color)
                    }
                    NoteGrid(notes: notebooks, actions: actions)
                case .studio:
                    StudioSection(sectionID: section.id, tint: section.color, actions: actions)
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 40)
        }
        .onDrop(of: [.pdf], isTargeted: $dropping) { providers in
            tabRaw = CourseTab.sources.rawValue
            return actions.drop(providers, section.id)
        }
    }

    private func banner(pdfs: Int, notebooks: Int) -> some View {
        let overviews = studio.overviews(in: section.id).count
        return VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                if showToggle {
                    Button(action: actions.toggleSidebar) {
                        Image(systemName: "sidebar.left")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(.white.opacity(0.18), in: Circle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Menu {
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
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(.white.opacity(0.18), in: Circle())
                }
            }
            HStack(alignment: .center, spacing: 18) {
                Image(systemName: section.symbol)
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(section.color)
                    .frame(width: 76, height: 76)
                    .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
                VStack(alignment: .leading, spacing: 4) {
                    Text(section.name)
                        .font(Theme.display(.largeTitle))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(Loc.t("{0} kaynak · {1} defter · {2} özet", "\(pdfs)", "\(notebooks)", "\(overviews)"))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    bannerButton(Loc.t("PDF ekle"), "doc.badge.plus") { actions.importPDF(section.id) }
                    bannerButton(Loc.t("Defter"), "square.and.pencil") { actions.newNotebook(section.id) }
                    bannerButton(Loc.t("Video özeti"), OverviewKind.video.symbol) { actions.makeOverview(section.id, .video, []) }
                    bannerButton(Loc.t("Sesli özet"), OverviewKind.audio.symbol) { actions.makeOverview(section.id, .audio, []) }
                }
            }
        }
        .padding(22)
        .background(
            ZStack {
                LinearGradient(colors: [section.color, section.color.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: section.symbol)
                    .font(.system(size: 220, weight: .bold))
                    .foregroundStyle(.white.opacity(0.10))
                    .rotationEffect(.degrees(-14))
                    .offset(x: 90, y: 20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: section.color.opacity(0.35), radius: 18, y: 8)
        .padding(.top, 14)
    }

    private func bannerButton(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(.white.opacity(0.2), in: Capsule())
                .foregroundStyle(.white)
        }
        .buttonStyle(PressableStyle())
    }
}
