import Foundation
import PDFKit
import Vision

/// The chapters of a PDF note, found once (text layer, or OCR of the top third of scanned pages) and
/// kept on disk next to its page texts. Runs off the main thread.
enum BookIndex {
    private static func cacheURL(_ note: UUID) -> URL? {
        PageTextCache.folder(note: note)?.appendingPathComponent("chapters-v1.json")
    }

    static func cached(note: UUID) -> [BookChapter]? {
        guard let url = cacheURL(note), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([BookChapter].self, from: data)
    }

    static func chapters(pdf: URL, note: UUID, progress: (@Sendable (Int, Int) -> Void)? = nil) async -> [BookChapter] {
        if let known = cached(note: note) { return known }
        let found = await Task.detached(priority: .userInitiated) { () async -> [BookChapter]? in
            guard let doc = PDFDocument(url: pdf), doc.pageCount > 0 else { return [] }
            var heads: [PageHead] = []
            var previousContents = false
            for i in 0..<doc.pageCount {
                if Task.isCancelled { return nil }
                progress?(i, doc.pageCount)
                let lines = await BookIndex.headLines(doc, page: i, note: note)
                let numbered = lines.filter { $0.range(of: #"\s\d{1,4}$"#, options: .regularExpression) != nil }.count
                let isContents = !lines.isEmpty
                    && (lines[0].range(of: #"^(contents|table of contents|içindekiler)\b"#, options: [.regularExpression, .caseInsensitive]) != nil
                        || (previousContents && numbered >= max(3, lines.count / 2)))
                previousContents = isContents
                heads.append(PageHead(page: i, lines: isContents ? lines : Array(lines.prefix(ChapterFinder.headLines))))
            }
            return ChapterFinder.find(outline: BookIndex.outline(doc), heads: heads, pageCount: doc.pageCount)
        }.value
        guard let found else { return [] }
        if let url = cacheURL(note), let data = try? JSONEncoder().encode(found) {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
        return found
    }

    private static func outline(_ doc: PDFDocument) -> [(title: String, level: Int, page: Int)] {
        guard let root = doc.outlineRoot else { return [] }
        var out: [(title: String, level: Int, page: Int)] = []
        for i in 0..<root.numberOfChildren {
            guard let item = root.child(at: i), let page = item.destination?.page else { continue }
            out.append((title: item.label ?? "", level: 0, page: doc.index(for: page)))
        }
        return out
    }

    /// The page's lines: its text layer when it has one, the full OCR when the Studio already read it,
    /// otherwise OCR of the top third (where headings are).
    private static func headLines(_ doc: PDFDocument, page i: Int, note: UUID) async -> [String] {
        func split(_ s: String) -> [String] {
            s.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        if let cached = PageTextCache.load(note: note, page: i) { return split(cached.text) }
        guard let page = doc.page(at: i) else { return [] }
        let text = page.string ?? ""
        if TextLayer.isUsable(text) { return split(text) }
        guard let image = PDFPageReader.render(page, longEdge: 1600),
              let top = image.cropping(to: CGRect(x: 0, y: 0, width: image.width, height: image.height / 3)) else { return [] }
        return await HeadOCR.lines(top)
    }
}

/// One accurate Vision pass over a page's top: lines in reading order, pieces on the same row joined.
enum HeadOCR {
    static func lines(_ image: CGImage) async -> [String] {
        await withCheckedContinuation { (cont: CheckedContinuation<[String], Never>) in
            DispatchQueue.global(qos: .utility).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                if let supported = try? request.supportedRecognitionLanguages() {
                    let wanted = ["tr-TR", "en-US"].filter { supported.contains($0) }
                    if !wanted.isEmpty { request.recognitionLanguages = wanted }
                }
                let handler = VNImageRequestHandler(cgImage: image, options: [:])
                try? handler.perform([request])
                let found = (request.results ?? []).compactMap { obs -> (box: CGRect, text: String)? in
                    guard let best = obs.topCandidates(1).first else { return nil }
                    return (box: obs.boundingBox, text: best.string)
                }
                // Vision's boxes start at the bottom: higher maxY first; pieces within 1.5 % of the
                // height form one row, left to right.
                let sorted = found.sorted { $0.box.maxY > $1.box.maxY }
                var rows: [(y: CGFloat, parts: [(x: CGFloat, text: String)])] = []
                for f in sorted {
                    if let k = rows.indices.last, abs(rows[k].y - f.box.maxY) < 0.015 {
                        rows[k].parts.append((x: f.box.minX, text: f.text))
                    } else {
                        rows.append((y: f.box.maxY, parts: [(x: f.box.minX, text: f.text)]))
                    }
                }
                cont.resume(returning: rows.map { row in row.parts.sorted { $0.x < $1.x }.map(\.text).joined(separator: " ") })
            }
        }
    }
}
