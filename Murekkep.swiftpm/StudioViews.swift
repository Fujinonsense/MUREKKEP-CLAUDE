import SwiftUI
import UIKit

// MARK: - Create

/// Choices for a new overview (like NotebookLM's customise sheet, with more knobs).
struct StudioCreateSheet: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var studio: StudioStore
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var voices = VoiceSettings.shared
    let request: StudioRequest
    @State private var options: OverviewOptions
    @State private var selected: Set<UUID>
    @State private var engine: StudioEngine
    @State private var showVoices = false
    @State private var chapters: [BookChapter] = []
    /// Chosen chapters (by `BookChapter.id`); none = the whole book in one video.
    @State private var chosenChapters: Set<Int> = []
    /// 0…1 while the chapters are being found.
    @State private var chapterProgress: Double?
    @State private var chaptersFor: UUID?
    /// Whether the sources that are not chosen are listed.
    @State private var showAllSources = false

    private static let lastKey = "studio.lastOptions"

    init(request: StudioRequest, engine: StudioEngine) {
        self.request = request
        var o = OverviewOptions()
        if let data = UserDefaults.standard.data(forKey: Self.lastKey),
           let saved = try? JSONDecoder().decode(OverviewOptions.self, from: data) {
            o = saved
            o.focus = ""
        }
        o.kind = request.kind
        if !OverviewFormat.options(for: o.kind).contains(o.format) { o.format = .explainer }
        _options = State(initialValue: o)
        _selected = State(initialValue: Set(request.preselected))
        _engine = State(initialValue: engine)
    }

    private var candidates: [NoteMeta] {
        let notes = request.sectionID.map { id in library.notes.filter { $0.sectionID == id } } ?? library.notes
        return notes.sorted { a, b in
            if a.kind != b.kind { return a.kind == .pdf }
            return a.modified > b.modified
        }
    }

    private var courseName: String? {
        library.sections.first { $0.id == request.sectionID }?.name
    }

    /// From this width the sheet shows two columns: how it is told on the left, what it is about on the right.
    private static let twoColumnWidth: CGFloat = 860

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                if geo.size.width >= Self.twoColumnWidth {
                    HStack(spacing: 0) {
                        Form {
                            kindSection
                            essentialsSection
                            formatSection
                            themeSection
                            voiceSection
                            engineSection
                        }
                        Divider()
                        Form {
                            sourcesSection
                            if bookSource != nil {
                                chapterSection
                            }
                            focusSection
                        }
                        .frame(width: max(360, geo.size.width * 0.42))
                    }
                } else {
                    // The choices that shape the result come first; the long lists come after them.
                    Form {
                        kindSection
                        essentialsSection
                        sourcesSection
                        if bookSource != nil {
                            chapterSection
                        }
                        formatSection
                        themeSection
                        focusSection
                        voiceSection
                        engineSection
                    }
                }
            }
            .navigationTitle(courseName.map { "\(options.kind.title) · \($0)" } ?? options.kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Loc.t("Vazgeç")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(Loc.t("Oluştur")) { create() }
                        .fontWeight(.bold)
                        .disabled(selected.isEmpty || !engine.isAvailable(settings: settings))
                }
            }
            .sheet(isPresented: $showVoices) {
                VoiceSettingsView()
            }
            .task(id: bookSource?.id) {
                await loadChapters()
            }
            .onAppear {
                if selected.isEmpty {
                    let pdfs = candidates.filter { $0.kind == .pdf }
                    let pick = pdfs.isEmpty ? Array(candidates.prefix(3)) : Array(pdfs.prefix(request.sectionID == nil ? 1 : 6))
                    selected = Set(pick.map(\.id))
                }
            }
        }
    }

    private func kindCard(_ kind: OverviewKind) -> some View {
        let on = options.kind == kind
        return Button {
            options.kind = kind
            if !OverviewFormat.options(for: kind).contains(options.format) { options.format = .explainer }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: kind.symbol)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(on ? .white : Theme.aiStart)
                    .frame(width: 46, height: 46)
                    .background(on ? AnyShapeStyle(Theme.ai) : AnyShapeStyle(Theme.aiStart.opacity(0.12)),
                                in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                Text(kind.title)
                    .font(.headline)
                Text(kind.blurb)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(on ? Theme.aiStart.opacity(0.08) : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(on ? Theme.aiStart : Color.primary.opacity(0.1), lineWidth: on ? 2 : 1))
        }
        .buttonStyle(.plain)
    }

    private var kindSection: some View {
        Section {
            HStack(spacing: 12) {
                ForEach(OverviewKind.allCases) { kind in
                    kindCard(kind)
                }
            }
            .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
        }
    }

    /// Language, length and level: what the result most depends on, each with its name over it.
    private var essentialsSection: some View {
        Section {
            essential(Loc.t("Dil")) {
                Picker(Loc.t("Dil"), selection: $options.language) {
                    ForEach(OverviewLanguage.allCases) { l in
                        Text(l.title).tag(l)
                    }
                }
            }
            essential(Loc.t("Süre")) {
                Picker(Loc.t("Süre"), selection: $options.length) {
                    ForEach(OverviewLength.allCases) { l in
                        Text(Loc.t("{0} · ~{1} dk", "\(l.title)", "\(l.minutes)")).tag(l)
                    }
                }
            }
            essential(Loc.t("Seviye")) {
                Picker(Loc.t("Seviye"), selection: $options.level) {
                    ForEach(OverviewLevel.allCases) { l in
                        Text(l.title).tag(l)
                    }
                }
            }
        } header: {
            Text(Loc.t("Temel ayarlar"))
        } footer: {
            Text(engine == .offline
                 ? Loc.t("Çevrimdışı yazar çeviri yapamaz: kaynak başka bir dildeyse özet kaynağın dilinde hazırlanır.")
                 : Loc.t("Başlıklar, anlatım ve ses baştan sona bu dilde olur; kaynak başka bir dildeyse çevrilerek anlatılır."))
        }
    }

    private func essential<Content: View>(_ title: String, @ViewBuilder picker: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            picker()
                .pickerStyle(.segmented)
                .labelsHidden()
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var themeSection: some View {
        if options.kind == .video {
            Section(Loc.t("Görünüm")) {
                // Every look in view at once, no sideways scrolling.
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 176), spacing: 14)], alignment: .leading, spacing: 14) {
                    ForEach(SlideTheme.allCases) { theme in
                        Button {
                            options.theme = theme
                        } label: {
                            ThemePreview(theme: theme, selected: options.theme == theme)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 6)
            }
        }
    }

    private var focusSection: some View {
        Section {
            TextField(Loc.t("ör. sınavda çıkabilecek mekanizmalar, klinik önemi, 3. hafta konuları…"), text: $options.focus, axis: .vertical)
                .lineLimit(2...5)
        } header: {
            Text(Loc.t("Odak (isteğe bağlı)"))
        } footer: {
            Text(Loc.t("Neye ağırlık verilsin, kime göre anlatılsın, neyi atlasın; serbestçe yaz."))
        }
    }

    /// The chosen sources stay in view; the rest of the library opens on request instead of pushing
    /// every other setting far down.
    private var sourcesSection: some View {
        Section {
            if candidates.isEmpty {
                Text(request.sectionID == nil ? Loc.t("Kütüphanede kaynak yok. Önce bir PDF ekle.") : Loc.t("Bu derste kaynak yok. Önce derse PDF ekle."))
                    .foregroundStyle(.secondary)
            }
            ForEach(candidates.filter { selected.contains($0.id) }) { note in
                sourceRow(note)
            }
            let others = candidates.filter { !selected.contains($0.id) }
            if !others.isEmpty {
                DisclosureGroup(isExpanded: $showAllSources) {
                    ForEach(others) { note in
                        sourceRow(note)
                    }
                } label: {
                    Label(Loc.t("Başka kaynak ekle ({0})", "\(others.count)"), systemImage: "plus.circle")
                        .foregroundStyle(Theme.ink)
                }
            }
        } header: {
            Text(Loc.t("Kaynaklar · {0} seçili", "\(selected.count)"))
        } footer: {
            Text(Loc.t("En fazla 10 kaynak. El yazısı defterler cihazda okunup metin olarak eklenir."))
        }
    }

    private func sourceRow(_ note: NoteMeta) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                if selected.contains(note.id) { selected.remove(note.id) } else if selected.count < 10 { selected.insert(note.id) }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: selected.contains(note.id) ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected.contains(note.id) ? Theme.ink : Color.secondary)
                Image(systemName: note.kind == .pdf ? "doc.richtext" : "book.closed")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(note.title)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(note.kind == .pdf ? Loc.t("PDF · {0} sayfa", "\(note.pageCount)") : Loc.t("El yazısı defter · {0} sayfa", "\(note.pageCount)"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var formatSection: some View {
        Section(Loc.t("Biçim")) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(OverviewFormat.options(for: options.kind)) { format in
                    let on = options.format == format
                    Button {
                        options.format = format
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: format.symbol)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(on ? Theme.ink : Color.secondary)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(format.title(for: options.kind))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text(format.detail(for: options.kind))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(on ? Theme.ink.opacity(0.1) : Color.primary.opacity(0.04)))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(on ? Theme.ink : Color.clear, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var voiceSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: EmbeddedVoices.isAvailable ? "person.wave.2.fill" : "speaker.slash.fill")
                    .foregroundStyle(Theme.ai)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(voiceSummary)
                        .font(.subheadline.weight(.semibold))
                    Text(voiceHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(Loc.t("Ayarla")) { showVoices = true }
                    .buttonStyle(.bordered)
            }
        } header: {
            Text(Loc.t("Seslendirme"))
        }
        .id(voices.revision)
    }

    private var voiceSummary: String {
        let first = voices.gender(host: 0).title
        if options.kind == .audio { return first + " & " + voices.gender(host: 1).title }
        return first
    }

    private var voiceHint: String {
        EmbeddedVoices.isAvailable ? Loc.t("Gömülü ses · iPad'de, internetsiz") : Loc.t("Bu derlemede gömülü sesler yok.")
    }

    private var engineSection: some View {
        Section {
            Picker(Loc.t("Senaryoyu yazan"), selection: $engine) {
                ForEach(StudioEngine.allCases) { e in
                    Label(e.title + (e.isAvailable(settings: settings) ? "" : Loc.t(" (kullanılamıyor)")), systemImage: e.symbol).tag(e)
                }
            }
        } header: {
            Text(Loc.t("Yapay zekâ"))
        } footer: {
            if engine == .claude && !settings.hasAPIKey {
                Text(Loc.t("Claude için Ayarlar › İsteğe bağlı bulut bölümünden API anahtarı ekle."))
            } else if engine == .onDevice && !OnDeviceAI.isAvailable {
                Text(OnDeviceAI.unavailableReason ?? "")
            } else {
                Text(engine.detail + (engine == .claude ? Loc.t(" Model: {0}.", "\(settings.model.title)") : ""))
            }
        }
    }

    private func create() {
        let chosen = candidates.filter { selected.contains($0.id) }
        guard !chosen.isEmpty else { return }
        if let data = try? JSONEncoder().encode(options) {
            UserDefaults.standard.set(data, forKey: Self.lastKey)
        }
        let picked = bookSource == nil ? [] : chapters.filter { chosenChapters.contains($0.id) }
        if picked.isEmpty {
            studio.start(options: options, sources: chosen, sectionID: request.sectionID, engine: engine,
                         library: library, settings: settings)
        } else {
            // One video per chapter, made one after another.
            for chapter in picked {
                studio.start(options: options, sources: chosen, sectionID: request.sectionID, engine: engine,
                             library: library, settings: settings, chapter: chapter)
            }
        }
        dismiss()
    }

    // MARK: Chapters

    /// The one long PDF chosen: its chapters can become separate videos.
    private var bookSource: NoteMeta? {
        let chosen = candidates.filter { selected.contains($0.id) }
        guard chosen.count == 1, let note = chosen.first, note.kind == .pdf, note.pageCount >= 40 else { return nil }
        return note
    }

    private var chapterSection: some View {
        Section {
            if let progress = chapterProgress {
                VStack(alignment: .leading, spacing: 6) {
                    Text(Loc.t("Bölümler bulunuyor…"))
                        .font(.subheadline)
                    ProgressView(value: progress)
                }
            } else if chapters.isEmpty {
                Text(Loc.t("Bu kitapta bölüm bulunamadı; video tüm kitaptan hazırlanır."))
                    .foregroundStyle(.secondary)
            } else {
                Button {
                    chosenChapters.removeAll()
                } label: {
                    chapterRow(title: Loc.t("Tüm kitap (tek video)"), detail: nil, on: chosenChapters.isEmpty)
                }
                .buttonStyle(.plain)
                ForEach(chapters) { chapter in
                    Button {
                        if chosenChapters.contains(chapter.id) { chosenChapters.remove(chapter.id) } else { chosenChapters.insert(chapter.id) }
                    } label: {
                        chapterRow(title: "\(chapter.number) · \(chapter.title)",
                                   detail: Loc.t("s. {0}–{1} · {2} alt başlık", "\(chapter.startPage + 1)", "\(chapter.endPage + 1)",
                                                 "\(chapter.sections.count)"),
                                   on: chosenChapters.contains(chapter.id))
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            Text(chosenChapters.isEmpty ? Loc.t("Bölümler") : Loc.t("Bölümler · {0} video", "\(chosenChapters.count)"))
        } footer: {
            Text(Loc.t("Seçtiğin her bölüm için ayrı bir video hazırlanır; sırayla, biri bitince öbürü."))
        }
    }

    private func chapterRow(title: String, detail: String?, on: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: on ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(on ? Theme.ink : Color.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    /// Finds the chosen book's chapters (once per book; kept on disk).
    private func loadChapters() async {
        guard let note = bookSource else {
            chaptersFor = nil
            chapters = []
            chosenChapters = []
            return
        }
        guard chaptersFor != note.id else { return }
        chaptersFor = note.id
        chapters = []
        chosenChapters = []
        if let known = BookIndex.cached(note: note.id) {
            chapters = known
            return
        }
        chapterProgress = 0
        let found = await BookIndex.chapters(pdf: library.pdfURL(for: note.id), note: note.id) { done, total in
            Task { @MainActor in
                chapterProgress = Double(done + 1) / Double(max(total, 1))
            }
        }
        guard chaptersFor == note.id else { return }
        chapters = found
        chapterProgress = nil
    }
}

extension View {
    /// A sheet the size of a page on iPad (iPadOS 18+) rather than a narrow form, so the create
    /// sheet's choices have room.
    @ViewBuilder
    func pageSizedSheet() -> some View {
        if #available(iOS 18.0, *) {
            presentationSizing(.page)
        } else {
            presentationDetents([.large])
        }
    }
}

/// A small title slide in each look.
struct ThemePreview: View {
    let theme: SlideTheme
    let selected: Bool
    @State private var image: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.secondary.opacity(0.1))
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(16 / 9, contentMode: .fit)
                }
            }
            .frame(width: 176, height: 99)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(selected ? Theme.ink : Color.primary.opacity(0.1), lineWidth: selected ? 3 : 1))
            Text(theme.title)
                .font(.caption.weight(.semibold))
            Text(theme.detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .task {
            image = await Self.render(theme)
        }
    }

    private static let cache = NSCache<NSString, UIImage>()

    static func render(_ theme: SlideTheme) async -> UIImage {
        if let cached = cache.object(forKey: theme.rawValue as NSString) { return cached }
        let image = await Task.detached(priority: .userInitiated) { () -> UIImage in
            var options = OverviewOptions()
            options.theme = theme
            var scene = OverviewScene(layout: .title, title: Loc.t("Kalbin İletim Sistemi"), subtitle: Loc.t("Video özeti"),
                                      narration: Loc.t("Örnek"), art: "art:heart")
            if theme == .explainer {
                // The look's own slide: a numbered section card.
                scene = OverviewScene(layout: .section, title: Loc.t("Limit ve Yaklaşım"), subtitle: Loc.t("Sıfıra bölmeyi aşmak"),
                                      narration: Loc.t("Örnek"))
                scene.number = 2
            }
            let sample = Overview(title: Loc.t("Örnek"), sectionID: nil, sourceIDs: [], sourceTitles: [Loc.t("Kardiyoloji")], options: options,
                                  language: .turkish, hosts: OverviewLanguage.turkish.hostNames, scenes: [scene])
            let size = CGSize(width: 352, height: 198)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 2
            return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
                SlideRenderer.poster(sample, size: size, in: ctx.cgContext)
            }
        }.value
        cache.setObject(image, forKey: theme.rawValue as NSString)
        return image
    }
}

// MARK: - Progress and results

struct JobRow: View {
    @ObservedObject var job: StudioJob
    @EnvironmentObject private var studio: StudioStore

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.1), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: CGFloat(max(0.02, job.progress)))
                    .stroke(Theme.ai, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.3), value: job.progress)
                Image(systemName: job.error == nil ? job.kind.symbol : "exclamationmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(job.error == nil ? Theme.aiStart : Color.red)
            }
            .frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(job.kind.title) · \(job.title)")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(job.error ?? job.phase)
                    .font(.caption)
                    .foregroundStyle(job.error == nil ? Color.secondary : Color.red)
                    .lineLimit(3)
            }
            Spacer(minLength: 8)
            if job.error == nil {
                Text("%\(Int(job.progress * 100))")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Button {
                studio.dismiss(job)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(job.error == nil ? Loc.t("İptal et") : Loc.t("Kapat"))
        }
        .padding(14)
        .glassCard(radius: 18)
    }
}

struct OverviewCard: View {
    let overview: Overview
    @EnvironmentObject private var studio: StudioStore
    @State private var image: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Theme.ai)
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
                Image(systemName: "play.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(.black.opacity(0.45), in: Circle())
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                HStack(spacing: 5) {
                    Image(systemName: overview.kind.symbol)
                    Text(OverviewFormatting.duration(overview.timeline.total))
                }
                .font(.caption2.weight(.bold).monospacedDigit())
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.black.opacity(0.55), in: Capsule())
                .padding(8)
            }
            .shadow(color: Theme.shadow.opacity(0.14), radius: 10, y: 5)
            Text(overview.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Text("\(overview.options.format.title(for: overview.kind)) · \(overview.created.formatted(date: .abbreviated, time: .omitted))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
        .task(id: overview.voiceSignature + overview.id.uuidString) {
            image = await LibraryStore.loadImage(at: studio.thumbnailURL(for: overview.id))
        }
    }
}

struct OverviewGrid: View {
    @EnvironmentObject private var studio: StudioStore
    @EnvironmentObject private var library: LibraryStore
    let overviews: [Overview]
    let actions: LibraryActions
    @State private var renaming: Overview?
    @State private var renameText = ""
    @State private var deleting: Overview?

    private let columns = [GridItem(.adaptive(minimum: 240, maximum: 330), spacing: 20)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
            ForEach(overviews) { overview in
                Button {
                    actions.play(overview)
                } label: {
                    OverviewCard(overview: overview)
                }
                .buttonStyle(PressableStyle())
                .contextMenu {
                    Button {
                        actions.play(overview)
                    } label: {
                        Label(Loc.t("Oynat"), systemImage: "play.fill")
                    }
                    Button {
                        renameText = overview.title
                        renaming = overview
                    } label: {
                        Label(Loc.t("Yeniden adlandır"), systemImage: "pencil")
                    }
                    Button {
                        studio.revoice(overview, library: library)
                    } label: {
                        Label(Loc.t("Seçili seslerle yeniden seslendir"), systemImage: "person.wave.2")
                    }
                    Divider()
                    Button(role: .destructive) {
                        deleting = overview
                    } label: {
                        Label(Loc.t("Sil"), systemImage: "trash")
                    }
                }
            }
        }
        .alert(Loc.t("Yeniden adlandır"), isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField(Loc.t("Ad"), text: $renameText)
            Button(Loc.t("Kaydet")) {
                if let o = renaming { studio.rename(o.id, to: renameText) }
                renaming = nil
            }
            Button(Loc.t("Vazgeç"), role: .cancel) { renaming = nil }
        }
        .confirmationDialog(Loc.t("Bu özet silinsin mi?"), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button(Loc.t("Sil"), role: .destructive) {
                if let o = deleting { studio.delete(o.id) }
                deleting = nil
            }
            Button(Loc.t("Vazgeç"), role: .cancel) { deleting = nil }
        }
    }
}

/// The two big "make" cards.
struct StudioCreateCards: View {
    let sectionID: UUID?
    let actions: LibraryActions

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            overviewCards
            StudyCreateRow(sectionID: sectionID, actions: actions)
        }
    }

    private var overviewCards: some View {
        HStack(spacing: 16) {
            ForEach(OverviewKind.allCases) { kind in
                Button {
                    actions.makeOverview(sectionID, kind, [])
                } label: {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: kind.symbol)
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 54, height: 54)
                            .background(Theme.ai, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(kind.title)
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text(kind.blurb)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(Theme.aiStart)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity)
                    .glassCard(radius: 20)
                }
                .buttonStyle(PressableStyle())
            }
        }
    }
}

/// A banner for an empty studio.
struct StudioPromo: View {
    let actions: LibraryActions
    let sectionID: UUID?

    var body: some View {
        HStack(alignment: .center, spacing: 22) {
            VStack(alignment: .leading, spacing: 10) {
                Label(Loc.t("Stüdyo"), systemImage: "sparkles")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
                Text(Loc.t("PDF'lerinden video ve sesli özet"))
                    .font(Theme.display(.title2))
                    .foregroundStyle(.white)
                Text(Loc.t("Slaytlar, kaynaktaki şekiller, Türkçe ya da İngilizce doğal anlatım, altyazı ve ara sorular. Dinlerken durdurup soru da sorabilirsin."))
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    ForEach(OverviewKind.allCases) { kind in
                        Button {
                            actions.makeOverview(sectionID, kind, [])
                        } label: {
                            Label(kind.title, systemImage: kind.symbol)
                                .font(.subheadline.weight(.bold))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(.white, in: Capsule())
                                .foregroundStyle(Theme.aiStart)
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
                .padding(.top, 4)
            }
            Spacer(minLength: 0)
            Image(systemName: "play.rectangle.on.rectangle.fill")
                .font(.system(size: 96, weight: .bold))
                .foregroundStyle(.white.opacity(0.22))
        }
        .padding(24)
        .background(Theme.ai, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: Theme.aiStart.opacity(0.35), radius: 16, y: 8)
    }
}

/// The studio part of a course.
struct StudioSection: View {
    @EnvironmentObject private var studio: StudioStore
    let sectionID: UUID
    let tint: Color
    let actions: LibraryActions

    var body: some View {
        let overviews = studio.overviews(in: sectionID)
        let jobs = studio.jobs(in: sectionID)
        VStack(alignment: .leading, spacing: 20) {
            StudioCreateCards(sectionID: sectionID, actions: actions)
            ForEach(jobs) { job in
                JobRow(job: job)
            }
            if overviews.isEmpty && jobs.isEmpty {
                Text(Loc.t("Bu dersin kaynaklarından ilk özetini oluştur. Hazır olunca burada ve Stüdyo'da görünür."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if !overviews.isEmpty {
                SectionTitle(title: Loc.t("Özetler"))
                OverviewGrid(overviews: overviews, actions: actions)
            }
            StudyShelf(sectionID: sectionID, actions: actions)
        }
    }
}

/// Every overview, by course.
struct StudioPane: View {
    @EnvironmentObject private var studio: StudioStore
    @EnvironmentObject private var library: LibraryStore
    let actions: LibraryActions
    let showToggle: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                PaneHeader(title: Loc.t("Stüdyo"), subtitle: Loc.t("Kaynaklarından video ve sesli özetler"), showToggle: showToggle, actions: actions) {
                    NewMenu(actions: actions, section: nil)
                }
                StudioCreateCards(sectionID: nil, actions: actions)
                ForEach(studio.jobs) { job in
                    JobRow(job: job)
                }
                if studio.overviews.isEmpty && studio.jobs.isEmpty {
                    StudioPromo(actions: actions, sectionID: nil)
                }
                StudyShelf(sectionID: nil, actions: actions)
                ForEach(groups, id: \.key) { group in
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 10) {
                            if let section = group.section {
                                Image(systemName: section.symbol)
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 28, height: 28)
                                    .background(section.color.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            SectionTitle(title: group.section?.name ?? Loc.t("Ders dışı"))
                        }
                        OverviewGrid(overviews: group.overviews, actions: actions)
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 40)
        }
    }

    private struct CourseGroup {
        let key: String
        let section: NoteSection?
        let overviews: [Overview]
    }

    private var groups: [CourseGroup] {
        var out: [CourseGroup] = []
        for section in library.sections {
            let list = studio.overviews(in: section.id)
            if !list.isEmpty { out.append(CourseGroup(key: section.id.uuidString, section: section, overviews: list)) }
        }
        let known = Set(library.sections.map(\.id))
        let loose = studio.overviews.filter { o in o.sectionID.map { !known.contains($0) } ?? true }
        if !loose.isEmpty { out.append(CourseGroup(key: "loose", section: nil, overviews: loose)) }
        return out
    }
}
