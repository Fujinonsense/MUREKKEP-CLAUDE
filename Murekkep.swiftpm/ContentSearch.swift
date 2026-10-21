import Foundation
import PDFKit

/// The handwriting of each note's pages as text, so notes can be searched by what is written in
/// them. Read when a note is closed, only for the pages whose ink changed, off the main thread;
/// kept in Application Support/Murekkep/InkText/<note>.json.
enum InkTextCache {
    private struct Entry: Codable {
        var key: String
        var text: String
    }

    private static var root: URL? {
        guard let support = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                         appropriateFor: nil, create: true) else { return nil }
        return support.appendingPathComponent("Murekkep/InkText", isDirectory: true)
    }

    private static func url(_ note: UUID) -> URL? {
        root?.appendingPathComponent("\(note.uuidString).json")
    }

    private static func load(_ note: UUID) -> [String: Entry] {
        guard let u = url(note), let data = try? Data(contentsOf: u),
              let saved = try? JSONDecoder().decode([String: Entry].self, from: data) else { return [:] }
        return saved
    }

    /// What a page's ink is, cheaply: stroke ids are new every session, births and points are not.
    private static func fingerprint(_ strokes: [Stroke]) -> String {
        let births = strokes.reduce(0.0) { $0 + $1.birth }
        let points = strokes.reduce(0) { $0 + $1.points.count }
        return "\(strokes.count)-\(Int64((births * 1000).truncatingRemainder(dividingBy: 9e15)))-\(points)"
    }

    /// Page index → the text read from its handwriting.
    static func pages(note: UUID) -> [Int: String] {
        var out: [Int: String] = [:]
        for (k, v) in load(note) {
            if let page = Int(k), !v.text.isEmpty { out[page] = v.text }
        }
        return out
    }

    /// Reads the handwriting of the pages that changed since the last time (call off the main thread).
    static func refresh(note: UUID, pages: [[Stroke]]) async {
        var entries = load(note)
        var changed = false
        for (i, strokes) in pages.enumerated() {
            let key = String(i)
            let ink = strokes.filter { $0.brush != .highlighter }
            guard !ink.isEmpty else {
                if entries.removeValue(forKey: key) != nil { changed = true }
                continue
            }
            let mark = fingerprint(ink)
            if entries[key]?.key == mark { continue }
            var text = ""
            if let raster = InkRaster.render(ink) {
                text = await PageOCR.lines(in: raster).map(\.text).joined(separator: "\n")
            }
            entries[key] = Entry(key: mark, text: text)
            changed = true
        }
        for key in entries.keys where (Int(key) ?? -1) >= pages.count {
            entries.removeValue(forKey: key)
            changed = true
        }
        guard changed, let u = url(note) else { return }
        try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: u, options: .atomic)
        }
    }
}

/// A word found in a note: which note, which page and the text around it.
struct ContentHit: Identifiable {
    let id = UUID()
    let note: UUID
    let title: String
    let page: Int
    let hit: TextSearch.Hit
}

/// Searches inside every note: a PDF's text layer (or the reading of a scanned page, when the Studio
/// or the assistant already read it) and the handwriting on any page. A book's text is gathered once
/// per session and kept in memory.
actor ContentIndex {
    static let shared = ContentIndex()

    private var pdfText: [UUID: (modified: Date, pages: [Int: String])] = [:]

    private func pdfPages(_ note: NoteMeta, url: URL) -> [Int: String] {
        if let known = pdfText[note.id], known.modified == note.modified { return known.pages }
        var pages: [Int: String] = [:]
        if let doc = PDFDocument(url: url) {
            for i in 0..<doc.pageCount {
                if let cached = PageTextCache.load(note: note.id, page: i) {
                    if !cached.text.isEmpty { pages[i] = cached.text }
                } else if let s = doc.page(at: i)?.string, !s.isEmpty {
                    pages[i] = s
                }
            }
        }
        pdfText[note.id] = (note.modified, pages)
        return pages
    }

    /// Up to `limit` hits, at most three per page, notes in the order given.
    func search(_ query: String, notes: [NoteMeta], pdfURLs: [UUID: URL], limit: Int = 60) -> [ContentHit] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { return [] }
        var out: [ContentHit] = []
        for note in notes {
            if Task.isCancelled || out.count >= limit { break }
            var pages = InkTextCache.pages(note: note.id)
            if note.kind == .pdf, let url = pdfURLs[note.id] {
                for (i, text) in pdfPages(note, url: url) {
                    pages[i] = pages[i].map { text + "\n" + $0 } ?? text
                }
            }
            for page in pages.keys.sorted() {
                guard let text = pages[page], out.count < limit else { continue }
                for hit in TextSearch.hits(query: q, in: text, limit: 3) {
                    out.append(ContentHit(note: note.id, title: note.title, page: page, hit: hit))
                }
            }
        }
        return Array(out.prefix(limit))
    }
}
