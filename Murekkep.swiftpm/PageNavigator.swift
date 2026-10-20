import PDFKit
import SwiftUI
import UIKit

/// What the page badge opens: type a page number to go there, bookmark the page, switch between one
/// page at a time and continuous scrolling, and find a page among all of them, the bookmarked ones
/// or the PDF's contents.
struct PageNavigator: View {
    @ObservedObject var editor: EditorModel
    let done: () -> Void
    @StateObject private var thumbnails: PageThumbnails
    @State private var number = ""
    @State private var tab: Tab = .pages
    @State private var outline: [OutlineEntry] = []
    @FocusState private var typing: Bool

    private enum Tab: Hashable {
        case pages, bookmarks, contents
    }

    init(editor: EditorModel, done: @escaping () -> Void) {
        self.editor = editor
        self.done = done
        _thumbnails = StateObject(wrappedValue: PageThumbnails(pdfURL: editor.pdfURL, paper: editor.meta.paper))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 12)
            Picker("", selection: $tab) {
                Text(Loc.t("Sayfalar")).tag(Tab.pages)
                Text(Loc.t("Yer imleri")).tag(Tab.bookmarks)
                if editor.isPDF {
                    Text(Loc.t("İçindekiler")).tag(Tab.contents)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 18)
            .padding(.bottom, 10)
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            Toggle(Loc.t("Tek sayfa görünümü"), isOn: $editor.singlePage)
                .tint(Theme.ink)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
        }
        .frame(width: 400, height: 580)
        .presentationCompactAdaptation(.popover)
        .onAppear {
            if editor.isPDF {
                outline = OutlineEntry.entries(of: editor.pdfKitDocument)
            }
        }
    }

    // MARK: Header

    /// The current page number is the field: typing replaces it and "Git" goes there.
    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    TextField(String(editor.currentPage + 1), text: $number)
                        .font(.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit())
                        .keyboardType(.numberPad)
                        .focused($typing)
                        .frame(width: 104, alignment: .leading)
                        .onSubmit(goToTyped)
                        .accessibilityLabel(Loc.t("Sayfaya git"))
                    Text("/ \(editor.pageCount)")
                        .font(.title3.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Text(Loc.t("Sayfa numarasını yazıp git"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if typedPage != nil {
                Button(Loc.t("Git"), action: goToTyped)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.ink)
                    .transition(.scale.combined(with: .opacity))
            }
            ribbonButton
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: typedPage != nil)
    }

    private var ribbonButton: some View {
        let marked = editor.isBookmarked(editor.currentPage)
        return Button {
            editor.toggleBookmark(editor.currentPage)
        } label: {
            Image(systemName: marked ? "bookmark.fill" : "bookmark")
                .font(.title2)
                .foregroundStyle(marked ? Color.red : Color.secondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(marked ? Loc.t("İşareti kaldır") : Loc.t("Bu sayfayı işaretle"))
    }

    private var typedPage: Int? {
        Self.pageIndex(number, count: editor.pageCount)
    }

    /// The page (0-based) for a typed page number; a number past the end means the last page.
    static func pageIndex(_ text: String, count: Int) -> Int? {
        guard count > 0, let n = Int(text.trimmingCharacters(in: .whitespaces)) else { return nil }
        return min(max(n, 1), count) - 1
    }

    private func goToTyped() {
        go(typedPage)
    }

    private func go(_ page: Int?) {
        guard let page else { return }
        editor.requestScroll(to: page)
        done()
    }

    // MARK: Lists

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .pages:
            grid(Array(0..<editor.pageCount))
        case .bookmarks:
            if editor.bookmarks.isEmpty {
                hint(Loc.t("Henüz yer imi yok. Sağ üstteki kurdeleye dokunarak bu sayfayı işaretle."))
            } else {
                grid(editor.bookmarks)
            }
        case .contents:
            if outline.isEmpty {
                hint(Loc.t("Bu PDF'te içindekiler bölümü yok."))
            } else {
                List(outline, children: \.children) { entry in
                    Button {
                        go(entry.page)
                    } label: {
                        HStack {
                            Text(entry.title)
                                .lineLimit(2)
                            Spacer(minLength: 8)
                            if let page = entry.page {
                                Text("\(page + 1)")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .disabled(entry.page == nil)
                }
                .listStyle(.plain)
            }
        }
    }

    private func grid(_ indices: [Int]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 14)], spacing: 16) {
                    ForEach(indices, id: \.self) { i in
                        Button {
                            go(i)
                        } label: {
                            PageTile(index: i, image: thumbnails.images[i], aspect: aspect(of: i),
                                     current: i == editor.currentPage, bookmarked: editor.isBookmarked(i))
                        }
                        .buttonStyle(.plain)
                        .id(i)
                        .onAppear { requestThumbnail(i) }
                    }
                }
                .padding(18)
            }
            .onAppear { proxy.scrollTo(editor.currentPage, anchor: .center) }
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func aspect(of page: Int) -> CGFloat {
        let sizes = editor.layout.pageSizes
        guard sizes.indices.contains(page) else { return NoteMeta.a4.width / NoteMeta.a4.height }
        return sizes[page].width / max(sizes[page].height, 1)
    }

    private func requestThumbnail(_ page: Int) {
        guard editor.pages.indices.contains(page) else { return }
        thumbnails.request(page, strokes: editor.pages[page].strokes, stickers: editor.pages[page].stickers)
    }
}

/// A page in the navigator's grid: the paper with its ink, its number, a ribbon when bookmarked.
private struct PageTile: View {
    let index: Int
    let image: UIImage?
    let aspect: CGFloat
    let current: Bool
    let bookmarked: Bool

    var body: some View {
        VStack(spacing: 6) {
            paper
                .aspectRatio(aspect, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .overlay {
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(current ? Theme.ink : Color.black.opacity(0.12), lineWidth: current ? 2.5 : 0.5)
                }
                .overlay(alignment: .topTrailing) {
                    if bookmarked {
                        Ribbon()
                            .fill(Color.red)
                            .frame(width: 10, height: 18)
                            .padding(.trailing, 8)
                            .offset(y: -2)
                    }
                }
                .shadow(color: .black.opacity(current ? 0.18 : 0.08), radius: current ? 6 : 2, y: 1)
            Text("\(index + 1)")
                .font(.caption.monospacedDigit().weight(current ? .bold : .regular))
                .foregroundStyle(current ? Theme.ink : Color.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Loc.t("Sayfa {0}", "\(index + 1)"))
    }

    @ViewBuilder
    private var paper: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
        } else {
            Color.white
        }
    }
}

/// A bookmark ribbon hanging over the top edge of a page.
private struct Ribbon: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.midX, y: r.maxY - r.width * 0.45))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

/// One heading of a PDF's table of contents.
struct OutlineEntry: Identifiable {
    let id = UUID()
    let title: String
    /// 0-based page the heading points at (nil when it points nowhere in this file).
    let page: Int?
    let children: [OutlineEntry]?

    static func entries(of document: PDFDocument?) -> [OutlineEntry] {
        guard let document, let root = document.outlineRoot else { return [] }
        return entries(under: root, in: document, depth: 0)
    }

    private static func entries(under node: PDFOutline, in document: PDFDocument, depth: Int) -> [OutlineEntry] {
        var result: [OutlineEntry] = []
        for i in 0..<node.numberOfChildren {
            guard let child = node.child(at: i) else { continue }
            let destination = child.destination ?? (child.action as? PDFActionGoTo)?.destination
            var page: Int?
            if let target = destination?.page {
                let index = document.index(for: target)
                if index != NSNotFound { page = index }
            }
            let kids = depth < 8 ? entries(under: child, in: document, depth: depth + 1) : []
            let title = (child.label ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            result.append(OutlineEntry(title: title.isEmpty ? "—" : title, page: page, children: kids.isEmpty ? nil : kids))
        }
        return result
    }
}

/// Small pictures of pages (the paper or PDF page, its pictures and ink), drawn off the main thread.
final class PageThumbnails: ObservableObject {
    @Published private(set) var images: [Int: UIImage] = [:]
    private var requested = Set<Int>()
    private let queue = DispatchQueue(label: "murekkep.page-thumbnails", qos: .userInitiated)
    private let pdfURL: URL?
    private let paper: PaperStyle
    /// Opened on `queue` the first time a PDF page is drawn; only used there.
    private var document: CGPDFDocument?

    /// Width of a thumbnail in points.
    static let width: CGFloat = 120

    init(pdfURL: URL?, paper: PaperStyle) {
        self.pdfURL = pdfURL
        self.paper = paper
    }

    func request(_ page: Int, strokes: [Stroke], stickers: [Sticker]) {
        guard requested.insert(page).inserted else { return }
        let url = pdfURL
        let paper = self.paper
        queue.async { [weak self] in
            guard let self else { return }
            if self.document == nil, let url {
                self.document = PDFGeometry.openDocument(at: url)
            }
            var size = NoteMeta.a4
            var pdfPage: CGPDFPage?
            if let doc = self.document, let p = doc.page(at: page + 1) {
                pdfPage = p
                size = PDFGeometry.displaySize(of: p)
            }
            let scale = PageThumbnails.width / max(size.width, 1)
            let pixelSize = CGSize(width: PageThumbnails.width, height: (size.height * scale).rounded())
            let format = UIGraphicsImageRendererFormat()
            format.opaque = true
            let image = UIGraphicsImageRenderer(size: pixelSize, format: format).image { ctx in
                let cg = ctx.cgContext
                cg.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
                cg.fill(CGRect(origin: .zero, size: pixelSize))
                cg.scaleBy(x: scale, y: scale)
                if let pdfPage {
                    PDFGeometry.draw(page: pdfPage, in: cg)
                } else {
                    PaperDrawer.draw(paper, size: size, in: cg)
                }
                StickerArt.drawAll(stickers, in: cg)
                FlatInk.draw(strokes, in: cg)
            }
            DispatchQueue.main.async {
                self.images[page] = image
            }
        }
    }
}
