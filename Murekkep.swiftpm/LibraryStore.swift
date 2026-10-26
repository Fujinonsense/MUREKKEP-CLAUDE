import Combine
import Foundation
import UIKit

enum LibraryError: LocalizedError {
    case unreadablePDF
    case unreadablePhoto

    var errorDescription: String? {
        switch self {
        case .unreadablePDF: return Loc.t("PDF açılamadı. Dosya bozuk ya da şifreli olabilir.")
        case .unreadablePhoto: return Loc.t("Fotoğraf okunamadı.")
        }
    }
}

/// The days the user worked in a note (for the week strip in the sidebar).
enum ActivityLog {
    private static let key = "activity.days"

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static var days: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }

    static func record(_ date: Date = Date()) {
        let day = formatter.string(from: date)
        var days = UserDefaults.standard.stringArray(forKey: key) ?? []
        guard days.last != day else { return }
        days.append(day)
        UserDefaults.standard.set(Array(days.suffix(120)), forKey: key)
    }

    static func worked(on date: Date) -> Bool {
        days.contains(formatter.string(from: date))
    }

    /// Days in a row up to today (or up to yesterday, when today has nothing yet).
    static var streak: Int {
        let all = days
        let cal = Calendar.current
        var day = Date()
        if !all.contains(formatter.string(from: day)) { day = cal.date(byAdding: .day, value: -1, to: day) ?? day }
        var count = 0
        while all.contains(formatter.string(from: day)), count < 365 {
            count += 1
            day = cal.date(byAdding: .day, value: -1, to: day) ?? day
        }
        return count
    }
}

/// All notes on disk: Documents/Murekkep/<id>/{source.pdf, ink.mrk, thumb.jpg} plus index.json.
final class LibraryStore: ObservableObject {
    @Published private(set) var notes: [NoteMeta] = []
    @Published private(set) var sections: [NoteSection] = []
    @Published private(set) var thumbnailVersions: [UUID: Int] = [:]

    let root: URL
    private let thumbQueue = DispatchQueue(label: "murekkep.thumbnails", qos: .utility)

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        root = docs.appendingPathComponent("Murekkep", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        load()
    }

    // MARK: Paths

    private var indexURL: URL { root.appendingPathComponent("index.json") }

    func folder(for id: UUID) -> URL {
        root.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    func pdfURL(for id: UUID) -> URL {
        folder(for: id).appendingPathComponent("source.pdf")
    }

    func inkURL(for id: UUID) -> URL {
        folder(for: id).appendingPathComponent("ink.mrk")
    }

    func stickersURL(for id: UUID) -> URL {
        folder(for: id).appendingPathComponent("stickers.json")
    }

    func thumbnailURL(for id: UUID) -> URL {
        folder(for: id).appendingPathComponent("thumb.jpg")
    }

    func note(_ id: UUID) -> NoteMeta? {
        notes.first { $0.id == id }
    }

    // MARK: Index

    private var sectionsURL: URL { root.appendingPathComponent("sections.json") }

    /// Entries of index.json and sections.json this build could not read (written by a newer
    /// Mürekkep, or damaged), as they are in the file: written back with the rest, so one bad
    /// entry never empties a list.
    private var unreadableNotes: [Any] = []
    private var unreadableSections: [Any] = []

    private func load() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // Each list is read entry by entry; a file that is not a list at all is copied aside
        // before the next save replaces it.
        if let data = try? Data(contentsOf: sectionsURL) {
            if let read = LenientList.decode(NoteSection.self, from: data, decoder: decoder) {
                sections = read.items
                unreadableSections = read.unreadable
            } else {
                FileBackup.keep(sectionsURL)
            }
        }
        guard let data = try? Data(contentsOf: indexURL) else { return }
        if let read = LenientList.decode(NoteMeta.self, from: data, decoder: decoder) {
            notes = read.items.sorted { $0.modified > $1.modified }
            unreadableNotes = read.unreadable
        } else {
            FileBackup.keep(indexURL)
        }
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? LenientList.encode(notes, unreadable: unreadableNotes, encoder: encoder) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    private func persistSections() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? LenientList.encode(sections, unreadable: unreadableSections, encoder: encoder) else { return }
        try? data.write(to: sectionsURL, options: .atomic)
    }

    // MARK: Sections

    @discardableResult
    func createSection(name: String, symbol: String, colorIndex: Int) -> NoteSection {
        let section = NoteSection(name: name, symbol: symbol, colorIndex: colorIndex)
        sections.append(section)
        persistSections()
        return section
    }

    func updateSection(_ section: NoteSection) {
        guard let i = sections.firstIndex(where: { $0.id == section.id }) else { return }
        sections[i] = section
        persistSections()
    }

    /// Removes the section; its notes stay in the library without a section.
    func deleteSection(_ id: UUID) {
        sections.removeAll { $0.id == id }
        for i in notes.indices where notes[i].sectionID == id {
            notes[i].sectionID = nil
        }
        persistSections()
        persist()
    }

    func move(_ noteID: UUID, to sectionID: UUID?) {
        guard let i = notes.firstIndex(where: { $0.id == noteID }) else { return }
        notes[i].sectionID = sectionID
        persist()
    }

    func toggleFavorite(_ noteID: UUID) {
        guard let i = notes.firstIndex(where: { $0.id == noteID }) else { return }
        notes[i].isFavorite = !notes[i].starred
        persist()
    }

    /// Notes of a course (nil = every note).
    func notes(in sectionID: UUID?) -> [NoteMeta] {
        guard let sectionID else { return notes }
        return notes.filter { $0.sectionID == sectionID }
    }

    /// Keeps the Claude Files API id of a PDF uploaded outside the editor (the studio).
    func setClaudeFile(_ noteID: UUID, id: String?) {
        guard let i = notes.firstIndex(where: { $0.id == noteID }) else { return }
        notes[i].claudeFileID = id
        notes[i].claudeFileUploaded = id == nil ? nil : Date()
        persist()
    }

    // MARK: Changes

    @discardableResult
    func importPDF(from url: URL, section: UUID? = nil) throws -> NoteMeta {
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped { url.stopAccessingSecurityScopedResource() }
        }
        let id = UUID()
        let dir = folder(for: id)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = pdfURL(for: id)
        do {
            try FileManager.default.copyItem(at: url, to: dest)
        } catch {
            try? FileManager.default.removeItem(at: dir)
            throw error
        }
        guard let doc = PDFGeometry.openDocument(at: dest), doc.numberOfPages > 0 else {
            try? FileManager.default.removeItem(at: dir)
            throw LibraryError.unreadablePDF
        }
        let now = Date()
        let title = url.deletingPathExtension().lastPathComponent
        let meta = NoteMeta(id: id, title: title.isEmpty ? "PDF" : title, kind: .pdf, created: now, modified: now,
                            pageCount: doc.numberOfPages, paper: .plain, claudeFileID: nil, claudeFileUploaded: nil,
                            sectionID: section)
        notes.insert(meta, at: 0)
        persist()
        makeThumbnail(for: meta, strokes: [])
        return meta
    }

    /// Photos (image file data) as one PDF, a page per photo, titled `title`. The PDF is written
    /// off the main thread (`progress` gets each photo's count and the total, on the main thread);
    /// the note is added here, on the main actor.
    @MainActor
    @discardableResult
    func importPhotos(_ photos: [Data], title: String, section: UUID? = nil,
                      progress: @escaping (Int, Int) -> Void = { _, _ in }) async throws -> NoteMeta {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent(PhotoPDF.fileName(title)).appendingPathExtension("pdf")
        let pages = try await Task.detached(priority: .userInitiated) {
            try PhotoPDF.write(photos, to: url) { done, total in
                DispatchQueue.main.async { progress(done, total) }
            }
        }.value
        guard pages > 0 else { throw LibraryError.unreadablePhoto }
        return try importPDF(from: url, section: section)
    }

    /// The title for photos added together: the first file's name, or "Fotoğraf" and the time.
    static func photoTitle(fileName: String?) -> String {
        if let name = fileName.map({ ($0 as NSString).deletingPathExtension }), !name.isEmpty { return name }
        return Loc.t("Fotoğraf") + " " + Date().formatted(date: .abbreviated, time: .shortened)
    }

    @discardableResult
    func createNotebook(paper: PaperStyle, section: UUID? = nil) -> NoteMeta {
        let now = Date()
        let id = UUID()
        try? FileManager.default.createDirectory(at: folder(for: id), withIntermediateDirectories: true)
        let prefix = sections.first { $0.id == section }?.name ?? Loc.t("Not")
        let title = prefix + " " + now.formatted(date: .abbreviated, time: .shortened)
        let meta = NoteMeta(id: id, title: title, kind: .notebook, created: now, modified: now,
                            pageCount: 1, paper: paper, claudeFileID: nil, claudeFileUploaded: nil,
                            sectionID: section)
        notes.insert(meta, at: 0)
        persist()
        makeThumbnail(for: meta, strokes: [])
        return meta
    }

    func update(_ meta: NoteMeta) {
        guard let i = notes.firstIndex(where: { $0.id == meta.id }) else { return }
        var updated = meta
        updated.modified = max(meta.modified, notes[i].modified)
        // The library owns the name, the section and the star; an open editor may hold an older copy.
        updated.title = notes[i].title
        updated.sectionID = notes[i].sectionID
        updated.isFavorite = notes[i].isFavorite
        // The studio may have uploaded the PDF to Claude after the editor opened: keep the newest.
        if (notes[i].claudeFileUploaded ?? .distantPast) > (updated.claudeFileUploaded ?? .distantPast) {
            updated.claudeFileID = notes[i].claudeFileID
            updated.claudeFileUploaded = notes[i].claudeFileUploaded
        }
        notes[i] = updated
        persist()
        ActivityLog.record()
    }

    func rename(_ id: UUID, to title: String) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, let i = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[i].title = t
        persist()
    }

    func touch(_ id: UUID) {
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return }
        var meta = notes.remove(at: i)
        meta.modified = Date()
        notes.insert(meta, at: 0)
        persist()
        ActivityLog.record()
    }

    func delete(_ id: UUID, apiKey: String?) {
        if let meta = note(id), let fileID = meta.claudeFileID, let apiKey {
            ClaudeClient.deleteFile(id: fileID, apiKey: apiKey)
        }
        try? FileManager.default.removeItem(at: folder(for: id))
        notes.removeAll { $0.id == id }
        thumbnailVersions[id] = nil
        persist()
    }

    // MARK: Thumbnails

    /// Decoded thumbnails, so cards scrolling back into view don't read and decode the file again.
    private let thumbnailCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 48 * 1024 * 1024
        return cache
    }()

    private func thumbnailKey(_ id: UUID, _ version: Int) -> NSString {
        "\(id.uuidString)#\(version)" as NSString
    }

    func cachedThumbnail(_ id: UUID, version: Int) -> UIImage? {
        thumbnailCache.object(forKey: thumbnailKey(id, version))
    }

    /// `version` is `thumbnailVersions[id]`, read by the caller on the main thread.
    func loadThumbnail(_ id: UUID, version: Int) async -> UIImage? {
        let key = thumbnailKey(id, version)
        if let hit = thumbnailCache.object(forKey: key) { return hit }
        guard let image = await Self.loadImage(at: thumbnailURL(for: id)) else { return nil }
        let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
        thumbnailCache.setObject(image, forKey: key, cost: cost)
        return image
    }

    static func loadImage(at url: URL) async -> UIImage? {
        let path = url.path
        return await Task.detached(priority: .utility) {
            guard let image = UIImage(contentsOfFile: path) else { return nil }
            // Decode here instead of on the main thread at the first draw.
            return image.preparingForDisplay() ?? image
        }.value
    }

    /// Renders the first page (with its ink) into a small JPEG on a background queue.
    func makeThumbnail(for meta: NoteMeta, strokes: [Stroke], stickers: [Sticker] = []) {
        let url = thumbnailURL(for: meta.id)
        let pdf = meta.kind == .pdf ? pdfURL(for: meta.id) : nil
        let paper = meta.paper
        let id = meta.id
        thumbQueue.async { [weak self] in
            var size = NoteMeta.a4
            var page: CGPDFPage?
            var document: CGPDFDocument?
            if let pdf, let doc = PDFGeometry.openDocument(at: pdf), let first = doc.page(at: 1) {
                document = doc
                page = first
                size = PDFGeometry.displaySize(of: first)
            }
            let targetWidth: CGFloat = 360
            let scale = targetWidth / max(size.width, 1)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = true
            let pixelSize = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
            let image = UIGraphicsImageRenderer(size: pixelSize, format: format).image { ctx in
                let cg = ctx.cgContext
                cg.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
                cg.fill(CGRect(origin: .zero, size: pixelSize))
                cg.scaleBy(x: scale, y: scale)
                if let page {
                    PDFGeometry.draw(page: page, in: cg)
                } else {
                    PaperDrawer.draw(paper, size: size, in: cg)
                }
                StickerArt.drawAll(stickers, in: cg)
                FlatInk.draw(strokes, in: cg)
            }
            _ = document
            if let data = image.jpegData(compressionQuality: 0.8) {
                try? data.write(to: url, options: .atomic)
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.thumbnailVersions[id, default: 0] += 1
            }
        }
    }
}
