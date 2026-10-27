import Combine
import Foundation
import PDFKit
import UIKit

enum ToolKind: Equatable {
    case brush(Brush)
    case eraser
    /// Select strokes by drawing around them; move, resize, recolor, convert to text.
    case lasso
    /// Lines, arrows, rectangles, circles… drawn with the last brush.
    case shape
    /// A compass: set the center and radius, then draw arcs.
    case compass
    /// Tap to type text in the single-line font with the last brush.
    case text
    /// Write by hand; after a short pause the writing becomes neat text on the template's lines,
    /// in the last brush's ink and color.
    case textPen

    var selectedBrush: Brush? {
        if case let .brush(b) = self { return b }
        return nil
    }

    /// Tools that lay down ink with the pencil.
    var inks: Bool {
        switch self {
        case .brush, .textPen: return true
        default: return false
        }
    }

    var title: String {
        switch self {
        case let .brush(b): return b.title
        case .eraser: return Loc.t("Silgi")
        case .lasso: return Loc.t("Kement (seçim)")
        case .shape: return Loc.t("Şekil")
        case .compass: return Loc.t("Pergel")
        case .text: return Loc.t("Metin")
        case .textPen: return Loc.t("Metin kalemi")
        }
    }
}

/// The floating palette opened by an Apple Pencil squeeze or double tap.
struct PaletteRequest: Equatable {
    enum Mode: Equatable {
        case tools
        case colors
    }

    /// Canvas-view coordinates of the pencil tip (or the view center).
    var location: CGPoint
    var mode: Mode
    let id = UUID()
}

enum CanvasHaptic {
    case selection
    case alignment
    case completed
}

/// One undoable change on a page.
struct InkEdit {
    let page: Int
    let before: [Stroke]
    let after: [Stroke]
    /// The page's stickers before and after, when the edit touched them.
    var stickersBefore: [Sticker]? = nil
    var stickersAfter: [Sticker]? = nil
    /// Changes on other pages made in the same step (a selection carried to another page): undone
    /// and redone together with this one.
    var linked: [InkEdit] = []
}

/// Ink, tools, undo and persistence for one open note.
final class EditorModel: ObservableObject {
    @Published private(set) var meta: NoteMeta
    @Published var tool: ToolKind = .brush(.pen) {
        didSet {
            guard oldValue != tool else { return }
            // Another tool ends what was still being adjusted.
            if shapeEdit != nil { finishShapeEdit() }
            if placingSticker != nil { finishPlacing() }
            previousTool = oldValue
            if case let .brush(b) = tool {
                lastBrush = b
                settings.rememberBrush(b)
            }
            if tool != .eraser { eraserReturn = nil }
            // Leaving the text pen sets what was written (a quick erase in between does not).
            if oldValue == .textPen && tool != .eraser { convertTextBatch() }
            if tool != .compass { compass = nil }
            if tool != .lasso && selection != nil { selection = nil }
        }
    }
    /// Tool before the last change (Apple Pencil "switch to previous tool").
    private(set) var previousTool: ToolKind = .eraser
    /// The brush that shapes, the compass and typed text use: the last pen picked.
    @Published private(set) var lastBrush: Brush = .pen
    /// Set while the eraser is only borrowed (Pencil squeeze or double tap): the tool to return to.
    private(set) var eraserReturn: ToolKind?

    // Drafting tools
    // The canvas draws instruments, the compass and the selection frame in its overlay; a change
    // asks it for a new frame.
    @Published var instrument: Instrument? {
        didSet { if oldValue != instrument { onInkChange?() } }
    }
    @Published var shapeKind: ShapeKind = .line
    @Published var shapeDashed = false
    @Published var polygonSides = 6
    @Published var compass: CompassState? {
        didSet { if oldValue != compass { onInkChange?() } }
    }
    @Published var selection: InkSelection? {
        didSet { if oldValue != selection { onInkChange?() } }
    }
    /// The selection while it is dragged or resized. Kept out of SwiftUI until the drag ends, so
    /// the toolbar is not rebuilt every frame.
    private(set) var liveSelection: InkSelection?
    /// What the canvas draws and hit-tests.
    var displayedSelection: InkSelection? { liveSelection ?? selection }
    /// Short confirmation shown over the canvas ("3 satır yazıya çevrildi").
    @Published var banner: String?
    @Published private(set) var isConverting = false
    /// The text pen's writing is being read.
    @Published private(set) var isTypesetting = false
    /// Text-pen strokes waiting for the pause that turns them into text.
    private var textBatch: (page: Int, ids: [Int])?
    private var textWork: DispatchWorkItem?
    /// Where the text pen last wrote text, for the dots and accents that come after a word.
    private var lastTypeset: (page: Int, rect: CGRect, time: Date)?
    /// The text typed or typeset last (Aa box or text pen): typing from a keyboard goes on under it.
    private(set) var lastTyped: (page: Int, rect: CGRect)?
    /// Where the text pen's last word ended: the next words on that line follow it with one space.
    private var lastTextEnd: (page: Int, end: TextEnd)?
    /// The handwriting the text pen read last and the text that replaced it: writing that goes on
    /// along that line is read again together with it (TextPenBatch), moved from where it was
    /// written along the typed words to where it falls in that handwriting (`anchors`).
    private var lastTextRead: (page: Int, strokes: [Stroke], typeset: Set<Int>, ink: CGRect, time: Date, before: TextEnd?,
                               anchors: [TextPenBatch.Anchor])?
    /// What the canvas shows in its middle (for placing plots and calculator results).
    var viewCenter: (page: Int, point: CGPoint)?
    private var selectionSnapshot: (strokes: [Stroke], ids: Set<Int>, stickers: [Sticker])?
    /// Picture versions of a held drawing (a heart, a face), shown as a radial menu.
    @Published var suggestion: SketchSuggestion?
    /// A shape just recognized from a held stroke: its corners have handles until the next touch
    /// somewhere else.
    @Published private(set) var shapeEdit: ShapeEditState? {
        didSet { if oldValue != shapeEdit { onInkChange?() } }
    }
    private var shapeEditSnapshot: [Stroke]?
    /// A sticker just placed: it keeps a box (move, resize, turn, flip) until the next touch
    /// somewhere else, then it becomes part of the page.
    @Published private(set) var placingSticker: UUID? {
        didSet { if oldValue != placingSticker { onInkChange?() } }
    }
    @Published var palette: PaletteRequest?
    /// Set when an Apple Pencil Pro barrel roll was seen.
    @Published var pencilProDetected = false
    @Published private(set) var colors: [Brush: InkColor] = [:]
    @Published private(set) var widths: [Brush: Float] = [:]
    @Published var eraserMode: EraserMode = .stroke
    @Published var eraserSize: Float = 18
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    @Published var currentPage = 0 {
        didSet { if oldValue != currentPage { scheduleLastPageSave() } }
    }
    /// One page at a time: a drag settles on a page and the zoom shows all of it.
    @Published var singlePage = false {
        didSet {
            guard oldValue != singlePage else { return }
            meta.pageMode = singlePage ? "single" : nil
            store.update(meta)
        }
    }
    /// The zoom window's panel is open (writing large lands small in a box on the page).
    @Published var zoomWindowOn = false
    @Published private(set) var pageCount: Int
    @Published private(set) var loadError: String?
    /// The ink file could not be read (damaged, or written by a newer Mürekkep): the note opens
    /// without it and nothing is written over it, so edits are refused with a word in the banner.
    @Published private(set) var inkReadOnly = false

    let store: LibraryStore
    let settings: AppSettings
    let pdfURL: URL?
    private(set) var layout: DocumentLayout
    private(set) var pages: [PageInk]

    var onInkChange: (() -> Void)?
    var onLayoutChange: (() -> Void)?
    /// Set while lecture takes can be played: a finger tap on ink passes that ink's moment (its birth).
    var onInkTap: ((Double) -> Void)?
    /// Strokes hidden while a lecture take replays (they appear as the playhead reaches them).
    private(set) var replayHidden: Set<Int> = []
    private var replayRevision = 0
    /// Asks the canvas to show a page (the page navigator, a bookmark, the contents).
    var onScrollRequest: ((Int) -> Void)?
    /// Plays haptics on the canvas (routed to Apple Pencil Pro when it is the active input).
    var onHaptic: ((CanvasHaptic) -> Void)?

    private var undoStack: [InkEdit] = []
    private var redoStack: [InkEdit] = []
    private var eraseSnapshot: (page: Int, strokes: [Stroke], stickers: [Sticker])?
    private var dirty = false
    private var saveWork: DispatchWorkItem?
    private var pageSaveWork: DispatchWorkItem?
    private let saveQueue = DispatchQueue(label: "murekkep.save", qos: .utility)
    private var pdfKitDocumentStorage: PDFDocument?
    private var cgDocumentStorage: CGPDFDocument?

    var isPDF: Bool { meta.kind == .pdf }
    var title: String { meta.title }

    init(meta: NoteMeta, store: LibraryStore, settings: AppSettings) {
        self.meta = meta
        self.store = store
        self.settings = settings

        var sizes: [CGSize] = []
        var url: URL?
        var error: String?
        var cgDoc: CGPDFDocument?
        if meta.kind == .pdf {
            let u = store.pdfURL(for: meta.id)
            url = u
            if let doc = PDFGeometry.openDocument(at: u) {
                cgDoc = doc
                for i in 0..<doc.numberOfPages {
                    if let page = doc.page(at: i + 1) {
                        sizes.append(PDFGeometry.displaySize(of: page))
                    } else {
                        sizes.append(NoteMeta.a4)
                    }
                }
            } else {
                error = Loc.t("PDF açılamadı. Dosya bozuk ya da şifreli olabilir.")
            }
        }

        var loaded: [[Stroke]] = []
        var inkError: String?
        var readOnly = false
        let inkURL = store.inkURL(for: meta.id)
        if let data = try? Data(contentsOf: inkURL) {
            do {
                loaded = try InkCodec.decode(data)
            } catch {
                // The file stays as it is: the note opens read-only, so no save replaces ink a newer
                // build (or a repair) could still read. A damaged file also gets a copy next to it.
                readOnly = true
                if InkCodec.isNewerFormat(data) {
                    inkError = Loc.t("Bu not daha yeni bir Mürekkep sürümüyle kaydedilmiş; bu sürüm onu açamıyor. Yazılar dosyada duruyor; görmek için uygulamayı güncelle.")
                } else {
                    FileBackup.keep(inkURL)
                    inkError = Loc.t("Bu notun mürekkep dosyası okunamadı. Dosya olduğu gibi saklandı ve yanına bir kopyası alındı; not salt okunur açıldı.")
                }
            }
        }
        if meta.kind == .notebook {
            let count = max(1, meta.pageCount, loaded.count)
            sizes = Array(repeating: NoteMeta.a4, count: count)
        }
        if sizes.isEmpty {
            sizes = [NoteMeta.a4]
        }

        pdfURL = url
        cgDocumentStorage = cgDoc
        layout = DocumentLayout(pageSizes: sizes)
        pageCount = sizes.count
        pages = (0..<sizes.count).map { i in
            PageInk(strokes: i < loaded.count ? loaded[i] : [], version: 1)
        }
        let problems = [error, inkError].compactMap { $0 }
        loadError = problems.isEmpty ? nil : problems.joined(separator: "\n\n")
        inkReadOnly = readOnly

        var c: [Brush: InkColor] = [:]
        var w: [Brush: Float] = [:]
        for b in Brush.allCases {
            c[b] = settings.color(for: b) ?? b.palette[0]
            let width = settings.width(for: b) ?? b.defaultWidth
            w[b] = min(max(width, b.widthRange.lowerBound), b.widthRange.upperBound)
        }
        colors = c
        widths = w
        singlePage = meta.pageMode == "single"

        if let data = try? Data(contentsOf: store.stickersURL(for: meta.id)),
           let saved = try? JSONDecoder().decode([[Sticker]].self, from: data) {
            for (i, list) in saved.enumerated() where i < pages.count {
                pages[i].stickers = list
            }
        }
    }

    // MARK: Tools

    func color(for brush: Brush) -> InkColor {
        colors[brush] ?? brush.palette[0]
    }

    func width(for brush: Brush) -> Float {
        widths[brush] ?? brush.defaultWidth
    }

    func setColor(_ color: InkColor, for brush: Brush) {
        colors[brush] = color
        settings.setColor(color, for: brush)
    }

    /// Picks a tool from the palette and confirms it with a haptic tick.
    func select(_ newTool: ToolKind) {
        // The 3D inks are Mürekkep Pro's in the App Store edition.
        if case let .brush(brush) = newTool, brush.isPremium,
           !MainActor.assumeIsolated({ ProStore.shared.unlock(.premiumInk) }) {
            return
        }
        // The nature pens draw while their trial ink lasts.
        if case let .brush(brush) = newTool, brush.isTrialInk,
           !MainActor.assumeIsolated({ ProStore.shared.allowsTrialInk() }) {
            return
        }
        tool = newTool
        onHaptic?(.selection)
    }

    func switchToPrevious() {
        select(previousTool == tool ? .brush(.pen) : previousTool)
    }

    func toggleEraser() {
        if tool == .eraser {
            leaveEraser()
        } else {
            select(.eraser)
        }
    }

    /// Brush the color and width controls apply to (the last brush while another tool is active).
    var activeBrush: Brush {
        tool.selectedBrush ?? lastBrush
    }

    /// Pencil squeeze or double tap: erase now, and go back to the current tool when done.
    func beginTemporaryEraser() {
        guard tool != .eraser else { return }
        let back = tool
        select(.eraser)
        eraserReturn = back
    }

    var isTemporaryEraser: Bool { eraserReturn != nil && tool == .eraser }

    /// Back to the tool the eraser was borrowed from (the pen, the highlighter, …).
    func endTemporaryEraser() {
        guard let back = eraserReturn else { return }
        eraserReturn = nil
        if tool == .eraser { select(back) }
    }

    /// Leaves the eraser, borrowed or picked: back to the tool before it (the last pen when the
    /// eraser was all there was).
    func leaveEraser() {
        guard tool == .eraser else { return }
        if eraserReturn != nil {
            endTemporaryEraser()
        } else {
            select(previousTool == .eraser ? .brush(lastBrush) : previousTool)
        }
    }

    func setWidth(_ width: Float, for brush: Brush) {
        widths[brush] = width
        settings.setWidth(width, for: brush)
    }

    // MARK: Editing

    /// False, with a word to the user, while the note is read-only; the canvas is then redrawn from
    /// the pages, without what it just drew.
    private func allowsEdit() -> Bool {
        guard inkReadOnly else { return true }
        banner = Loc.t("Not salt okunur: yeni yazılar kaydedilmez.")
        onInkChange?()
        return false
    }

    func addStroke(_ stroke: Stroke, toPage page: Int) {
        guard pages.indices.contains(page), allowsEdit() else { return }
        let before = pages[page].strokes
        pages[page].strokes.append(stroke)
        record(InkEdit(page: page, before: before, after: pages[page].strokes))
        if stroke.brush.isTrialInk {
            spendTrialInk(stroke)
        }
    }

    /// A nature-pen stroke uses up trial ink by its length; once the trial is gone the pen goes back
    /// to the plain pen (the Pro page is already open).
    private func spendTrialInk(_ stroke: Stroke) {
        let points = stroke.points
        var length: Float = 0
        for i in points.indices.dropFirst() {
            let dx = points[i].x - points[i - 1].x
            let dy = points[i].y - points[i - 1].y
            length += (dx * dx + dy * dy).squareRoot()
        }
        let spent = Double(length)
        let empty = MainActor.assumeIsolated { () -> Bool in
            ProStore.shared.spendTrialInk(points: spent)
            return ProStore.shared.trialInkLeft == 0
        }
        if empty, case let .brush(brush) = tool, brush.isTrialInk {
            tool = .brush(.pen)
        }
    }

    func strokes(on page: Int) -> [Stroke] {
        pages.indices.contains(page) ? pages[page].strokes : []
    }

    /// Removes and adds strokes on a page as one undoable step.
    func replaceStrokes(page: Int, removing ids: Set<Int>, adding new: [Stroke]) {
        guard pages.indices.contains(page), !(ids.isEmpty && new.isEmpty), allowsEdit() else { return }
        let before = pages[page].strokes
        pages[page].strokes = before.filter { !ids.contains($0.id) } + new
        record(InkEdit(page: page, before: before, after: pages[page].strokes))
    }

    func addStrokes(_ new: [Stroke], toPage page: Int) {
        replaceStrokes(page: page, removing: [], adding: new)
    }

    // MARK: Selection (lasso)

    /// Selects the strokes of `page` that lie mostly inside the lasso (page-local polygon).
    func selectStrokes(page: Int, lasso polygon: [CGPoint]) {
        guard pages.indices.contains(page), polygon.count >= 3 else {
            clearSelection()
            return
        }
        let path = CGMutablePath()
        path.addLines(between: polygon)
        path.closeSubpath()
        var ids = Set<Int>()
        for s in pages[page].strokes {
            let pts = s.points
            guard !pts.isEmpty else { continue }
            let step = max(1, pts.count / 24)
            var inside = 0
            var total = 0
            var i = 0
            while i < pts.count {
                total += 1
                if path.contains(CGPoint(x: CGFloat(pts[i].x), y: CGFloat(pts[i].y))) { inside += 1 }
                i += step
            }
            if inside * 2 >= total { ids.insert(s.id) }
        }
        // A sticker that was settled on the page is part of it now: the lasso leaves it alone.
        let stickerIDs = Set(pages[page].stickers.filter { !$0.isEmbedded && path.contains(CGPoint(x: $0.rect.midX, y: $0.rect.midY)) }.map(\.id))
        updateSelection(page: page, ids: ids, stickers: stickerIDs)
        if !ids.isEmpty || !stickerIDs.isEmpty { onHaptic?(.selection) }
    }

    func clearSelection() {
        liveSelection = nil
        selection = nil
    }

    // MARK: Instruments

    /// Lays the ruler (set square, protractor) where the user is looking, or puts it away (`nil`).
    func showInstrument(_ kind: InstrumentKind?) {
        guard let kind else {
            instrument = nil
            return
        }
        if var current = instrument {
            current.kind = kind
            instrument = current
            return
        }
        var center = CGPoint(x: layout.contentSize.width / 2, y: 320)
        if let c = viewCenter, layout.pageRects.indices.contains(c.page) {
            let o = layout.pageRects[c.page].origin
            center = CGPoint(x: o.x + c.point.x, y: o.y + c.point.y)
        }
        instrument = Instrument(kind: kind, center: center, angle: 0)
        onHaptic?(.selection)
    }

    /// Turns the instrument to a round angle (degrees, counterclockwise like on paper).
    func setInstrumentAngle(_ degrees: Double) {
        guard var i = instrument else { return }
        i.angle = -CGFloat(degrees) * .pi / 180
        instrument = i
    }

    private func updateSelection(page: Int, ids: Set<Int>, stickers stickerIDs: Set<UUID> = []) {
        guard let s = makeSelection(page: page, ids: ids, stickers: stickerIDs) else {
            clearSelection()
            return
        }
        selection = s
    }

    private func makeSelection(page: Int, ids: Set<Int>, stickers stickerIDs: Set<UUID>) -> InkSelection? {
        guard !(ids.isEmpty && stickerIDs.isEmpty), pages.indices.contains(page) else { return nil }
        var box = CGRect.null
        for s in pages[page].strokes where ids.contains(s.id) && !s.bounds.isEmpty {
            box = box.union(CGRect(ink: s.bounds))
        }
        for s in pages[page].stickers where stickerIDs.contains(s.id) {
            box = box.union(s.frame)
        }
        guard !box.isNull else { return nil }
        return InkSelection(page: page, ids: ids, bounds: box, stickers: stickerIDs)
    }

    func beginSelectionEdit() {
        guard let sel = selection, pages.indices.contains(sel.page), allowsEdit() else { return }
        selectionSnapshot = (strokes: pages[sel.page].strokes, ids: sel.ids, stickers: pages[sel.page].stickers)
    }

    /// Selects the one stroke or sticker under a lasso tap. False when nothing is there.
    @discardableResult
    func selectItem(page: Int, at point: CGPoint, tolerance: CGFloat) -> Bool {
        guard pages.indices.contains(page) else { return false }
        if let sticker = pages[page].stickers.last(where: { !$0.isEmbedded && $0.frame.insetBy(dx: -tolerance, dy: -tolerance).contains(point) }) {
            updateSelection(page: page, ids: [], stickers: [sticker.id])
            onHaptic?(.selection)
            return true
        }
        let p = SIMD2<Float>(Float(point.x), Float(point.y))
        let t = Float(tolerance)
        for s in pages[page].strokes.reversed() {
            let b = s.bounds
            guard p.x >= b.minX - s.maxRadius - t, p.x <= b.maxX + s.maxRadius + t,
                  p.y >= b.minY - s.maxRadius - t, p.y <= b.maxY + s.maxRadius + t else { continue }
            if InkEraser.hits(s, from: p, to: p, radius: t) {
                updateSelection(page: page, ids: [s.id])
                onHaptic?(.selection)
                return true
            }
        }
        return false
    }

    /// Moves the selection by `offset`, scales it around `anchor` and turns it by `rotation` radians
    /// around `anchor`, relative to where the edit began.
    func transformSelection(offset: CGVector, scale: CGFloat, anchor: CGPoint, rotation: CGFloat = 0) {
        guard let sel = selection, let snap = selectionSnapshot, pages.indices.contains(sel.page) else { return }
        let kc = min(max(scale, 0.05), 20)
        let k = Float(kc)
        let cosR = cos(rotation)
        let sinR = sin(rotation)
        func map(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            let u = (x - anchor.x) * kc
            let v = (y - anchor.y) * kc
            return CGPoint(x: anchor.x + u * cosR - v * sinR + offset.dx, y: anchor.y + u * sinR + v * cosR + offset.dy)
        }
        var ids = Set<Int>()
        let moved = snap.strokes.map { s -> Stroke in
            guard snap.ids.contains(s.id) else { return s }
            let pts = s.points.map { p -> InkPoint in
                let q = map(CGFloat(p.x), CGFloat(p.y))
                return InkPoint(x: Float(q.x), y: Float(q.y), r: p.r * k, ink: p.ink)
            }
            let copy = Stroke(brush: s.brush, color: s.color, width: s.width * k, birth: s.birth, seed: s.seed,
                              points: pts, duration: s.duration)
            ids.insert(copy.id)
            return copy
        }
        let movedStickers = snap.stickers.map { st -> Sticker in
            guard sel.stickers.contains(st.id) else { return st }
            var copy = st
            let center = map(st.rect.midX, st.rect.midY)
            let w = st.rect.width * kc
            let h = st.rect.height * kc
            copy.rect = CGRect(x: center.x - w / 2, y: center.y - h / 2, width: w, height: h)
            copy.angle = (st.angle ?? 0) + Double(rotation)
            return copy
        }
        pages[sel.page].strokes = moved
        pages[sel.page].stickers = movedStickers
        pages[sel.page].version += 1
        liveSelection = makeSelection(page: sel.page, ids: ids, stickers: sel.stickers)
        onInkChange?()
    }

    func endSelectionEdit() {
        if let live = liveSelection {
            liveSelection = nil
            selection = live
        }
        guard let sel = selection, let snap = selectionSnapshot, pages.indices.contains(sel.page) else { return }
        selectionSnapshot = nil
        if let target = dropPage(for: sel) {
            carrySelection(sel, from: snap, to: target)
            return
        }
        let after = pages[sel.page].strokes
        let stickersAfter = pages[sel.page].stickers
        let stickersChanged = stickersAfter != snap.stickers
        guard after.map(\.id) != snap.strokes.map(\.id) || stickersChanged else { return }
        undoStack.append(InkEdit(page: sel.page, before: snap.strokes, after: after,
                                 stickersBefore: stickersChanged ? snap.stickers : nil,
                                 stickersAfter: stickersChanged ? stickersAfter : nil))
        trimUndo()
        redoStack.removeAll()
        updateUndoFlags()
        markDirty()
    }

    /// The page a selection belongs to once dropped with its middle over another page.
    private func dropPage(for sel: InkSelection) -> Int? {
        guard layout.pageRects.indices.contains(sel.page) else { return nil }
        let o = layout.pageRects[sel.page].origin
        let center = CGPoint(x: o.x + sel.bounds.midX, y: o.y + sel.bounds.midY)
        guard let target = layout.page(containing: center), target != sel.page, pages.indices.contains(target) else {
            return nil
        }
        return target
    }

    /// Carries the selected strokes and stickers from their page to `target`, where they stay at the
    /// same place on the document. One undo step puts both pages back.
    private func carrySelection(_ sel: InkSelection, from snap: (strokes: [Stroke], ids: Set<Int>, stickers: [Sticker]),
                                to target: Int) {
        let from = layout.pageRects[sel.page].origin
        let to = layout.pageRects[target].origin
        let dx = from.x - to.x
        let dy = from.y - to.y
        let fx = Float(dx)
        let fy = Float(dy)
        let carried = pages[sel.page].strokes.filter { sel.ids.contains($0.id) }.map { s in
            Stroke(brush: s.brush, color: s.color, width: s.width, birth: s.birth, seed: s.seed,
                   points: s.points.map { InkPoint(x: $0.x + fx, y: $0.y + fy, r: $0.r, ink: $0.ink) },
                   duration: s.duration)
        }
        let carriedStickers = pages[sel.page].stickers.filter { sel.stickers.contains($0.id) }.map { st -> Sticker in
            var copy = st
            copy.rect = st.rect.offsetBy(dx: dx, dy: dy)
            return copy
        }
        let targetBefore = pages[target]
        pages[sel.page].strokes.removeAll { sel.ids.contains($0.id) }
        pages[sel.page].stickers.removeAll { sel.stickers.contains($0.id) }
        pages[target].strokes.append(contentsOf: carried)
        pages[target].stickers.append(contentsOf: carriedStickers)
        pages[target].version += 1
        var edit = InkEdit(page: sel.page, before: snap.strokes, after: pages[sel.page].strokes,
                           stickersBefore: snap.stickers, stickersAfter: pages[sel.page].stickers)
        edit.linked = [InkEdit(page: target, before: targetBefore.strokes, after: pages[target].strokes,
                               stickersBefore: targetBefore.stickers, stickersAfter: pages[target].stickers)]
        record(edit)
        updateSelection(page: target, ids: Set(carried.map(\.id)), stickers: Set(carriedStickers.map(\.id)))
    }

    func deleteSelection() {
        guard let sel = selection else { return }
        change(page: sel.page) { page in
            page.strokes.removeAll { sel.ids.contains($0.id) }
            page.stickers.removeAll { sel.stickers.contains($0.id) }
        }
        clearSelection()
    }

    func duplicateSelection() {
        guard let sel = selection, pages.indices.contains(sel.page) else { return }
        let copies = strokes(on: sel.page).filter { sel.ids.contains($0.id) }.map { s in
            Stroke(brush: s.brush, color: s.color, width: s.width, birth: s.birth, seed: s.seed,
                   points: s.points.map { InkPoint(x: $0.x + 18, y: $0.y + 18, r: $0.r, ink: $0.ink) }, duration: s.duration)
        }
        let stickerCopies = pages[sel.page].stickers.filter { sel.stickers.contains($0.id) }.map { s in
            Sticker(symbol: s.symbol, rect: s.rect.offsetBy(dx: 18, dy: 18), angle: s.angle, mirrored: s.mirrored)
        }
        change(page: sel.page) { page in
            page.strokes.append(contentsOf: copies)
            page.stickers.append(contentsOf: stickerCopies)
        }
        updateSelection(page: sel.page, ids: Set(copies.map(\.id)), stickers: Set(stickerCopies.map(\.id)))
    }

    /// Applies `body` to a page as one undoable step (strokes and stickers).
    private func change(page: Int, _ body: (inout PageInk) -> Void) {
        guard pages.indices.contains(page), allowsEdit() else { return }
        let before = pages[page]
        body(&pages[page])
        let after = pages[page]
        let stickersChanged = before.stickers != after.stickers
        guard before.strokes.map(\.id) != after.strokes.map(\.id) || stickersChanged else { return }
        record(InkEdit(page: page, before: before.strokes, after: after.strokes,
                       stickersBefore: stickersChanged ? before.stickers : nil,
                       stickersAfter: stickersChanged ? after.stickers : nil))
    }

    // MARK: Stickers and sketch suggestions

    /// Replaces the held drawing with a picture of the same size.
    func applySuggestion(sticker symbol: String) {
        guard let s = suggestion else { return }
        suggestion = nil
        let side = max(s.bounds.width, s.bounds.height, 40)
        let rect = CGRect(x: s.bounds.midX - side / 2, y: s.bounds.midY - side / 2, width: side, height: side)
        let sticker = Sticker(symbol: symbol, rect: rect)
        change(page: s.page) { page in
            page.strokes.removeAll { s.strokeIDs.contains($0.id) }
            page.stickers.append(sticker)
        }
        beginPlacing(sticker.id, page: s.page)
        onHaptic?(.completed)
    }

    /// Redraws the held heart as a neat heart in the same ink.
    func applySuggestionCleanHeart() {
        guard let s = suggestion, pages.indices.contains(s.page) else { return }
        suggestion = nil
        guard let original = pages[s.page].strokes.last(where: { s.strokeIDs.contains($0.id) }), !original.points.isEmpty else { return }
        let n = Float(original.points.count)
        let r = original.points.reduce(Float(0)) { $0 + $1.r } / n
        let ink = original.points.reduce(Float(0)) { $0 + $1.ink } / n
        let path = Geo.resample(SketchRecognizer.heartPath(in: s.bounds), spacing: CGFloat(max(1.5, r * 0.7)))
        let heart = Stroke(brush: original.brush, color: original.color, width: original.width, birth: original.birth,
                           seed: original.seed, points: path.map { InkPoint(x: Float($0.x), y: Float($0.y), r: r, ink: ink) })
        change(page: s.page) { page in
            page.strokes.removeAll { s.strokeIDs.contains($0.id) }
            page.strokes.append(heart)
        }
        onHaptic?(.completed)
    }

    /// Redraws the held star as a neat star in the same ink, point up, in the drawing's place.
    func applySuggestionCleanStar(crossing: Bool) {
        guard let s = suggestion, pages.indices.contains(s.page) else { return }
        suggestion = nil
        guard let original = pages[s.page].strokes.last(where: { s.strokeIDs.contains($0.id) }), !original.points.isEmpty else { return }
        let n = Float(original.points.count)
        let r = original.points.reduce(Float(0)) { $0 + $1.r } / n
        let ink = original.points.reduce(Float(0)) { $0 + $1.ink } / n
        let path = Geo.resample(SketchRecognizer.starPath(in: s.bounds, crossing: crossing), spacing: CGFloat(max(1.5, r * 0.7)))
        let star = Stroke(brush: original.brush, color: original.color, width: original.width, birth: original.birth,
                          seed: original.seed, points: path.map { InkPoint(x: Float($0.x), y: Float($0.y), r: r, ink: ink) })
        change(page: s.page) { page in
            page.strokes.removeAll { s.strokeIDs.contains($0.id) }
            page.strokes.append(star)
        }
        onHaptic?(.completed)
    }

    /// Places a sticker in the middle of the screen.
    func placeSticker(_ symbol: String) {
        guard let c = viewCenter else { return }
        let side: CGFloat = 120
        let rect = CGRect(x: c.point.x - side / 2, y: c.point.y - side / 2, width: side, height: side)
        let sticker = Sticker(symbol: symbol, rect: rect)
        change(page: c.page) { page in
            page.stickers.append(sticker)
        }
        beginPlacing(sticker.id, page: c.page)
        banner = Loc.t("Kutudan taşı, köşeden büyüt, üstteki tutamaçla döndür. Bitince sayfada başka bir yere dokun.")
    }

    // MARK: Placing a sticker

    /// The new sticker gets its box: the selection frame, whatever tool is in the hand.
    private func beginPlacing(_ id: UUID, page: Int) {
        if shapeEdit != nil { finishShapeEdit() }
        placingSticker = id
        updateSelection(page: page, ids: [], stickers: [id])
    }

    /// The box goes away and the sticker becomes part of the page: it can still be erased and
    /// written over, but it no longer moves or changes size.
    func finishPlacing() {
        guard let id = placingSticker else { return }
        placingSticker = nil
        liveSelection = nil
        selectionSnapshot = nil
        for p in pages.indices {
            guard let i = pages[p].stickers.firstIndex(where: { $0.id == id }) else { continue }
            pages[p].stickers[i].embedded = true
            pages[p].version += 1
            markDirty()
            break
        }
        selection = nil
        onInkChange?()
    }

    /// Flips the sticker being placed left to right (one undo step).
    func mirrorPlacingSticker() {
        guard let id = placingSticker, let sel = selection else { return }
        change(page: sel.page) { page in
            guard let i = page.stickers.firstIndex(where: { $0.id == id }) else { return }
            page.stickers[i].mirrored = !page.stickers[i].isMirrored
        }
        onHaptic?(.selection)
    }

    /// Removes the sticker being placed.
    func deletePlacingSticker() {
        guard placingSticker != nil else { return }
        placingSticker = nil
        deleteSelection()
    }

    // MARK: Adjusting a recognized shape

    /// Shows the handles of a shape the held pencil just drew.
    func startShapeEdit(page: Int, strokeID: Int, shape: EditableShape) {
        guard pages.indices.contains(page), pages[page].strokes.contains(where: { $0.id == strokeID }) else { return }
        if placingSticker != nil { finishPlacing() }
        shapeEdit = ShapeEditState(page: page, strokeID: strokeID, shape: shape)
    }

    /// Hides the handles; the shape stays as it is.
    func finishShapeEdit() {
        if shapeEditSnapshot != nil { endShapeHandleDrag() }
        shapeEdit = nil
    }

    func beginShapeHandleDrag() {
        guard let e = shapeEdit, pages.indices.contains(e.page) else { return }
        shapeEditSnapshot = pages[e.page].strokes
    }

    /// Moves a handle (page space) and redraws the shape's stroke in place.
    func moveShapeHandle(_ index: Int, to point: CGPoint, snap: CGFloat) -> ShapeHandleFeedback? {
        guard var e = shapeEdit, pages.indices.contains(e.page),
              let i = pages[e.page].strokes.firstIndex(where: { $0.id == e.strokeID }) else { return nil }
        let feedback = e.shape.move(handle: index, to: point, snap: snap)
        let redrawn = Self.restroke(pages[e.page].strokes[i], along: e.shape.path())
        pages[e.page].strokes[i] = redrawn
        pages[e.page].version += 1
        e.strokeID = redrawn.id
        shapeEdit = e
        onInkChange?()
        return feedback
    }

    /// One undo step for the whole drag.
    func endShapeHandleDrag() {
        guard let before = shapeEditSnapshot else { return }
        shapeEditSnapshot = nil
        guard let e = shapeEdit, pages.indices.contains(e.page) else { return }
        let after = pages[e.page].strokes
        guard after.map(\.id) != before.map(\.id) else { return }
        undoStack.append(InkEdit(page: e.page, before: before, after: after))
        trimUndo()
        redoStack.removeAll()
        updateUndoFlags()
        markDirty()
    }

    /// The same stroke (brush, color, width, average pressure and ink) drawn along `path`.
    private static func restroke(_ s: Stroke, along path: [CGPoint]) -> Stroke {
        let n = Float(max(s.points.count, 1))
        let r = s.points.reduce(Float(0)) { $0 + $1.r } / n
        let ink = s.points.reduce(Float(0)) { $0 + $1.ink } / n
        let dense = path.count >= 2 ? Geo.densify(path, spacing: CGFloat(max(1.5, r * 0.7))) : path
        return Stroke(brush: s.brush, color: s.color, width: s.width, birth: s.birth, seed: s.seed,
                      points: dense.map { InkPoint(x: Float($0.x), y: Float($0.y), r: r, ink: ink) }, duration: s.duration)
    }

    /// The eraser's path from `a` to `b` touches the middle part of a sticker.
    private static func segment(from a: SIMD2<Float>, to b: SIMD2<Float>, radius: Float, hits rect: CGRect) -> Bool {
        let box = rect.insetBy(dx: rect.width * 0.12 - CGFloat(radius), dy: rect.height * 0.12 - CGFloat(radius))
        let length = vlength(b - a)
        let steps = max(1, Int(length / max(radius * 0.5, 1)))
        for i in 0...steps {
            let p = a + (b - a) * (Float(i) / Float(steps))
            if box.contains(CGPoint(x: CGFloat(p.x), y: CGFloat(p.y))) { return true }
        }
        return false
    }

    /// Gives the selected strokes the current brush and color (3D inks included).
    func restyleSelection() {
        guard let sel = selection else { return }
        let brush = activeBrush
        let c = color(for: brush)
        let now = Date().timeIntervalSinceReferenceDate
        let restyled = strokes(on: sel.page).filter { sel.ids.contains($0.id) }.map { s -> Stroke in
            let seed = brush == .grass ? GrassGenerator.seed(level: settings.flowerLevel, random: Float.random(in: 0..<1)) : s.seed
            return Stroke(brush: brush, color: c, width: s.width, birth: now, seed: seed, points: s.points)
        }
        replaceStrokes(page: sel.page, removing: sel.ids, adding: restyled)
        updateSelection(page: sel.page, ids: Set(restyled.map(\.id)))
    }

    // MARK: Text

    /// Reads the handwriting (the selection, or the whole page) and writes it again as neat text on
    /// the template's lines, keeping every word's brush and color. One undo step.
    @MainActor
    func convertHandwriting(page: Int) async {
        guard pages.indices.contains(page), !isConverting else { return }
        let onlyIDs: Set<Int>? = selection?.page == page ? selection?.ids : nil
        let source = pages[page].strokes.filter { onlyIDs?.contains($0.id) ?? true }
        guard !source.isEmpty else {
            banner = Loc.t("Bu sayfada yazıya çevrilecek el yazısı yok.")
            return
        }
        isConverting = true
        defer { isConverting = false }
        let paper = isPDF ? PaperStyle.plain : meta.paper
        guard let result = await HandwritingConverter.convert(strokes: source, paper: paper, pageSize: layout.pageSizes[page],
                                                              flowerLevel: settings.flowerLevel, ai: handwritingAccess,
                                                              textScale: settings.textPenScale) else {
            banner = Loc.t("El yazısını okuyamadım. Biraz daha net yazıp tekrar dene.")
            return
        }
        replaceStrokes(page: page, removing: result.removed, adding: result.added)
        selection = nil
        banner = Loc.t("{0} satır yazıya çevrildi. Geri al ile eski haline dönebilirsin.", "\(result.lineCount)")
    }

    // MARK: Text pen

    /// The text pen touched the page again: the word is not finished yet.
    func textPenTouched() {
        textWork?.cancel()
        textWork = nil
    }

    /// Adds a text-pen stroke to the waiting batch; the batch turns into text after a pause.
    func queueTextStroke(_ id: Int, page: Int) {
        if let batch = textBatch, batch.page != page {
            convertTextBatch(now: true)
        }
        textBatch = (page, (textBatch?.ids ?? []) + [id])
        textWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.convertTextBatch() }
        textWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + settings.textPenDelay, execute: work)
    }

    /// The text pen drew a shape or a picture instead of letters: the words before it still turn
    /// into text after the pause (touching the page had stopped the wait).
    func resumeTextBatch() {
        guard textBatch != nil else { return }
        textWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.convertTextBatch() }
        textWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + settings.textPenDelay, execute: work)
    }

    /// Reads the waiting handwriting and replaces it with text on the lines (one undo step).
    /// `now`: the batch must go at once (the pen moved to another page).
    func convertTextBatch(now: Bool = false) {
        textWork?.cancel()
        textWork = nil
        guard let batch = textBatch else { return }
        // A reading still running: this writing waits for it, so it can join the line it typesets.
        if isTypesetting, !now {
            let work = DispatchWorkItem { [weak self] in self?.convertTextBatch() }
            textWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
            return
        }
        textBatch = nil
        let ids = Set(batch.ids)
        let source = strokes(on: batch.page).filter { ids.contains($0.id) }
        guard !source.isEmpty, layout.pageSizes.indices.contains(batch.page) else { return }
        let marks = source.map { CGRect(ink: $0.bounds) }.reduce(CGRect.null) { $0.union($1) }
        // Writing that goes on along the line just turned into text: the whole line is read again,
        // so its words keep their context and the spaces between them. Not when that text was
        // erased or changed since.
        var earlier: [Stroke] = []
        var replacing = Set<Int>()
        var previous = lastTextEnd?.page == batch.page ? lastTextEnd?.end : nil
        // The new writing as it sits next to the old handwriting, and the page strokes it stands for.
        var moved = source
        var onPage: [Int: Int] = [:]
        if let last = lastTextRead, last.page == batch.page {
            let hand = CGRect(x: TextPenBatch.handX(marks.minX, anchors: last.anchors), y: marks.minY,
                              width: TextPenBatch.handX(marks.maxX, anchors: last.anchors) - TextPenBatch.handX(marks.minX, anchors: last.anchors),
                              height: marks.height)
            if TextPenBatch.continues(last: last.ink, next: hand, elapsed: Date().timeIntervalSince(last.time)),
               last.typeset.isSubset(of: Set(strokes(on: batch.page).map(\.id))) {
                earlier = last.strokes
                replacing = last.typeset
                previous = last.before
                if !last.anchors.isEmpty {
                    moved = source.map { s in
                        let copy = s.withPoints(s.points.map { p in
                            var q = p
                            q.x = Float(TextPenBatch.handX(CGFloat(p.x), anchors: last.anchors))
                            return q
                        })
                        onPage[copy.id] = s.id
                        return copy
                    }
                }
            }
        }
        // Thick pens make bigger dots: the size of a lone mark grows with the pen.
        let penWidth = CGFloat(source.map(\.width).max() ?? 0)
        let isSmall = max(marks.width, marks.height) < max(14, 3 * penWidth)
        // A dot or an accent written after its word had already turned into text (and too late to
        // read the line again). Read alone it becomes a stray letter ("i" over "ı", "," under "ç");
        // the dictionary has already given the word its Turkish letters, so the mark is simply
        // dropped. A mark after the word (a full stop) is not over it and stays.
        if earlier.isEmpty, isSmall, let last = lastTypeset, last.page == batch.page, Date().timeIntervalSince(last.time) < 8,
           last.rect.insetBy(dx: -4, dy: -12).intersects(marks),
           marks.midX > last.rect.minX - 4, marks.midX < last.rect.maxX - 1 {
            let present = Set(strokes(on: batch.page).map(\.id))
            replaceStrokes(page: batch.page, removing: ids.intersection(present), adding: [])
            return
        }
        let paper = isPDF ? PaperStyle.plain : meta.paper
        let size = layout.pageSizes[batch.page]
        let flowers = settings.flowerLevel
        let access = handwritingAccess
        let start = previous
        let read = earlier + moved
        let pageIDs = onPage
        let rereading = !earlier.isEmpty
        let replaced = replacing
        // The page's other ink, which the typed words keep clear of (not the text being read again).
        let others = strokes(on: batch.page).filter { !ids.contains($0.id) && !replacing.contains($0.id) && !$0.points.isEmpty }
            .map { CGRect(ink: $0.bounds) }
        let scale = settings.textPenScale
        isTypesetting = true
        Task { @MainActor [weak self] in
            let converted = await HandwritingConverter.convert(strokes: read, paper: paper, pageSize: size,
                                                               flowerLevel: flowers, keepPosition: true,
                                                               ai: access, continueFrom: start, obstacles: others,
                                                               textScale: scale)
            guard let self else { return }
            self.isTypesetting = false
            // Small marks that read as nothing but punctuation stay as ink, quietly.
            if isSmall, !rereading, !(converted?.text.contains(where: { $0.isLetter || $0.isNumber }) ?? false) { return }
            guard let result = converted else {
                self.banner = Loc.t("Okunamadı, el yazısı olarak bıraktım.")
                return
            }
            // Strokes erased in the meantime stay erased; the text read again goes.
            let present = Set(self.strokes(on: batch.page).map(\.id))
            let readIDs = Set(result.removed.map { pageIDs[$0] ?? $0 })
            let removed = readIDs.intersection(present).union(replaced.intersection(present))
            guard !removed.isEmpty else { return }
            self.replaceStrokes(page: batch.page, removing: removed, adding: result.added)
            // The handwriting and the text that replaced it: late dots can land on either.
            let handwriting = read.filter { result.removed.contains($0.id) }
            let written = (handwriting + result.added)
                .map { CGRect(ink: $0.bounds) }.reduce(CGRect.null) { $0.union($1) }
            self.lastTypeset = (batch.page, written, Date())
            if !result.added.isEmpty {
                self.lastTyped = (batch.page, result.added.map { CGRect(ink: $0.bounds) }.reduce(CGRect.null) { $0.union($1) })
            }
            if let end = result.end {
                self.lastTextEnd = (batch.page, end)
            }
            let ink = handwriting.map { CGRect(ink: $0.bounds) }.reduce(CGRect.null) { $0.union($1) }
            self.lastTextRead = (batch.page, handwriting, Set(result.added.map(\.id)), ink, Date(), start, result.anchors)
            self.onHaptic?(.completed)
        }
    }

    /// Claude reads the handwriting when a key is saved and the setting is on (Haiku when the user
    /// chose the cheapest model, Sonnet otherwise).
    private var handwritingAccess: HandwritingAI.Access? {
        guard settings.handwritingAI, let key = settings.apiKey else { return nil }
        let model: ClaudeModel = settings.model == .haiku ? .haiku : .sonnet
        return HandwritingAI.Access(apiKey: key, model: model.rawValue)
    }

    /// Typed text in the single-line font with the current brush, on the template's lines.
    func insertText(_ text: String, request: TextRequest) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, pages.indices.contains(request.page) else { return }
        let brush = activeBrush
        let style = StrokeText.Style(brush: brush, color: color(for: brush), width: width(for: brush))
        let new = HandwritingConverter.typed(text, at: request.point, paper: isPDF ? .plain : meta.paper,
                                             pageSize: layout.pageSizes[request.page], style: style,
                                             flowerLevel: settings.flowerLevel, scale: settings.textPenScale)
        addStrokes(new, toPage: request.page)
        if !new.isEmpty {
            lastTyped = (request.page, new.map { CGRect(ink: $0.bounds) }.reduce(CGRect.null) { $0.union($1) })
        }
    }

    /// The lines typed text at `point` will sit on (for the Aa text box).
    func typedLayout(page: Int, at point: CGPoint) -> HandwritingConverter.TypedLayout? {
        guard layout.pageSizes.indices.contains(page) else { return nil }
        return HandwritingConverter.typedLayout(at: point, paper: isPDF ? .plain : meta.paper,
                                                pageSize: layout.pageSizes[page], scale: settings.textPenScale)
    }

    /// Color of the typed text (the brush it is written with).
    var typedColor: InkColor { color(for: activeBrush) }

    /// Writes `text` where the user is looking (calculator results, formulas, constants).
    func writeAtViewCenter(_ text: String) {
        guard let c = viewCenter else { return }
        insertText(text, request: TextRequest(page: c.page, point: CGPoint(x: max(40, c.point.x - 140), y: c.point.y)))
        banner = Loc.t("Sayfaya yazıldı.")
    }

    // MARK: Shapes and plots

    /// Pen paths of the current shape between two page-local points.
    func shapePaths(from a: CGPoint, to b: CGPoint) -> [[SIMD2<Float>]] {
        let paths = ShapeBuilder.paths(shapeKind, from: a, to: b, sides: polygonSides, labelHeight: 9)
        return shapeDashed ? ShapeBuilder.dashed(paths) : paths
    }

    func addShape(page: Int, from a: CGPoint, to b: CGPoint) {
        guard hypot(b.x - a.x, b.y - a.y) > 2 else { return }
        let brush = activeBrush
        let style = StrokeText.Style(brush: brush, color: color(for: brush), width: width(for: brush))
        let new = StrokeText.strokes(shapePaths(from: a, to: b), style: style, flowerLevel: settings.flowerLevel,
                                     birth: Date().timeIntervalSinceReferenceDate)
        addStrokes(new, toPage: page)
    }

    /// Draws y = f(x) in the middle of the view. Returns a message when it cannot.
    func plot(_ expression: String, xMin: Double, xMax: Double) -> String? {
        guard let c = viewCenter, layout.pageSizes.indices.contains(c.page) else { return Loc.t("Önce bir sayfaya bak.") }
        guard let e = MathParser.parse(expression) else { return Loc.t("İfade okunamadı. Örnek: x^2 - 3x + 1") }
        let vars = e.variables
        guard vars.count <= 1 else { return Loc.t("Tek değişkenli bir fonksiyon yaz (ör. sin(x) + x/2).") }
        let size = min(layout.pageSizes[c.page].width - 80, 380)
        guard let paths = ShapeBuilder.plot(e, variable: vars.first ?? "x", xMin: xMin, xMax: xMax,
                                            center: c.point, size: size, labelHeight: 11) else {
            return Loc.t("Bu aralıkta çizilecek değer yok.")
        }
        let brush = activeBrush
        let style = StrokeText.Style(brush: brush, color: color(for: brush), width: min(width(for: brush), 2.6))
        addStrokes(StrokeText.strokes(paths, style: style, flowerLevel: settings.flowerLevel,
                                      birth: Date().timeIntervalSinceReferenceDate), toPage: c.page)
        banner = Loc.t("Grafik çizildi.")
        return nil
    }

    /// Commits a compass arc (page-local points).
    func addArc(page: Int, points: [CGPoint]) {
        guard points.count >= 2 else { return }
        let brush = activeBrush
        let r = width(for: brush) * 0.5
        let pts = points.map { InkPoint(x: Float($0.x), y: Float($0.y), r: r, ink: 0.55) }
        let seed = brush == .grass ? GrassGenerator.seed(level: settings.flowerLevel, random: Float.random(in: 0..<1))
                                   : Float.random(in: 0..<1)
        addStroke(Stroke(brush: brush, color: color(for: brush), width: width(for: brush),
                         birth: Date().timeIntervalSinceReferenceDate, seed: seed, points: pts), toPage: page)
    }

    func beginErase(page: Int) {
        guard pages.indices.contains(page), allowsEdit() else { return }
        eraseSnapshot = (page, pages[page].strokes, pages[page].stickers)
    }

    func erase(page: Int, from a: SIMD2<Float>, to b: SIMD2<Float>) {
        guard pages.indices.contains(page), !inkReadOnly else { return }
        let radius = eraserSize / 2
        var changed = false
        var result: [Stroke] = []
        result.reserveCapacity(pages[page].strokes.count)
        for s in pages[page].strokes {
            switch eraserMode {
            case .stroke:
                if InkEraser.hits(s, from: a, to: b, radius: radius) {
                    changed = true
                } else {
                    result.append(s)
                }
            case .partial:
                if let pieces = InkEraser.erase(s, from: a, to: b, radius: radius) {
                    changed = true
                    result.append(contentsOf: pieces)
                } else {
                    result.append(s)
                }
            }
        }
        if changed {
            pages[page].strokes = result
        }
        if !pages[page].stickers.isEmpty {
            let before = pages[page].stickers.count
            pages[page].stickers.removeAll { Self.segment(from: a, to: b, radius: radius, hits: $0.rect) }
            if pages[page].stickers.count != before { changed = true }
        }
        if changed {
            pages[page].version += 1
            onInkChange?()
        }
    }

    func endErase() {
        guard let snap = eraseSnapshot else { return }
        eraseSnapshot = nil
        let after = pages[snap.page].strokes
        let stickersAfter = pages[snap.page].stickers
        let stickersChanged = stickersAfter != snap.stickers
        guard after.map(\.id) != snap.strokes.map(\.id) || stickersChanged else { return }
        undoStack.append(InkEdit(page: snap.page, before: snap.strokes, after: after,
                                 stickersBefore: stickersChanged ? snap.stickers : nil,
                                 stickersAfter: stickersChanged ? stickersAfter : nil))
        trimUndo()
        redoStack.removeAll()
        updateUndoFlags()
        markDirty()
    }

    /// Puts back what an interrupted eraser touch removed (a palm or a second finger cancelled it).
    func cancelErase() {
        guard let snap = eraseSnapshot else { return }
        eraseSnapshot = nil
        guard pages.indices.contains(snap.page),
              pages[snap.page].strokes.map(\.id) != snap.strokes.map(\.id) || pages[snap.page].stickers != snap.stickers
        else { return }
        pages[snap.page].strokes = snap.strokes
        pages[snap.page].stickers = snap.stickers
        pages[snap.page].version += 1
        onInkChange?()
    }

    func undo() {
        guard let edit = undoStack.popLast(), pages.indices.contains(edit.page) else { return }
        suggestion = nil
        // The text the pen would continue (or read again) may be gone now.
        lastTextEnd = nil
        lastTextRead = nil
        shapeEditSnapshot = nil
        shapeEdit = nil
        if placingSticker != nil {
            placingSticker = nil
            clearSelection()
        }
        restore(edit, before: true)
        redoStack.append(edit)
        updateUndoFlags()
        markDirty()
        onInkChange?()
    }

    func redo() {
        guard let edit = redoStack.popLast(), pages.indices.contains(edit.page) else { return }
        suggestion = nil
        lastTextRead = nil
        shapeEditSnapshot = nil
        shapeEdit = nil
        if placingSticker != nil {
            placingSticker = nil
            clearSelection()
        }
        restore(edit, before: false)
        undoStack.append(edit)
        updateUndoFlags()
        markDirty()
        onInkChange?()
    }

    /// Sets the edit's page, and the pages linked to it, as they were before or after the edit.
    private func restore(_ edit: InkEdit, before: Bool) {
        // A selection carried to another page would point at strokes that are not there now.
        if !edit.linked.isEmpty { clearSelection() }
        for e in [edit] + edit.linked where pages.indices.contains(e.page) {
            pages[e.page].strokes = before ? e.before : e.after
            if let s = before ? e.stickersBefore : e.stickersAfter { pages[e.page].stickers = s }
            pages[e.page].version += 1
        }
    }

    // MARK: Pages

    /// The page the note was left on, for opening it there again.
    var resumePage: Int { min(max(meta.lastPage ?? 0, 0), max(pageCount - 1, 0)) }

    func requestScroll(to page: Int) {
        guard pages.indices.contains(page) else { return }
        onScrollRequest?(page)
    }

    var bookmarks: [Int] { (meta.bookmarks ?? []).filter { pages.indices.contains($0) }.sorted() }

    func isBookmarked(_ page: Int) -> Bool {
        meta.bookmarks?.contains(page) ?? false
    }

    func toggleBookmark(_ page: Int) {
        guard pages.indices.contains(page) else { return }
        var list = meta.bookmarks ?? []
        if let i = list.firstIndex(of: page) {
            list.remove(at: i)
        } else {
            list.append(page)
        }
        meta.bookmarks = list.isEmpty ? nil : list.sorted()
        store.update(meta)
        onHaptic?(.selection)
    }

    /// True when the page has ink or pictures on it.
    func pageIsUsed(_ page: Int) -> Bool {
        pages.indices.contains(page) && !(pages[page].strokes.isEmpty && pages[page].stickers.isEmpty)
    }

    /// Remembers the page on screen a moment after it changes, so the note opens there next time.
    private func scheduleLastPageSave() {
        pageSaveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.saveLastPage()
        }
        pageSaveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    private func saveLastPage() {
        pageSaveWork?.cancel()
        pageSaveWork = nil
        guard (meta.lastPage ?? 0) != currentPage else { return }
        meta.lastPage = currentPage
        store.update(meta)
    }

    func addPage() {
        guard !isPDF, allowsEdit() else { return }
        var sizes = layout.pageSizes
        sizes.append(NoteMeta.a4)
        layout = DocumentLayout(pageSizes: sizes)
        pages.append(PageInk(strokes: [], version: 1))
        pageCount = sizes.count
        meta.pageCount = sizes.count
        store.update(meta)
        markDirty()
        onLayoutChange?()
    }

    /// Changes the template of every page of a notebook.
    func setPaper(_ style: PaperStyle) {
        guard !isPDF, meta.paper != style, allowsEdit() else { return }
        meta.paper = style
        store.update(meta)
        markDirty()
        onInkChange?()
    }

    func updateClaudeFile(id: String?) {
        meta.claudeFileID = id
        meta.claudeFileUploaded = id == nil ? nil : Date()
        store.update(meta)
    }

    private func record(_ edit: InkEdit) {
        pages[edit.page].version += 1
        undoStack.append(edit)
        trimUndo()
        redoStack.removeAll()
        updateUndoFlags()
        markDirty()
        onInkChange?()
    }

    private func trimUndo() {
        if undoStack.count > 300 {
            undoStack.removeFirst(undoStack.count - 300)
        }
    }

    private func updateUndoFlags() {
        if canUndo != !undoStack.isEmpty { canUndo = !undoStack.isEmpty }
        if canRedo != !redoStack.isEmpty { canRedo = !redoStack.isEmpty }
    }

    // MARK: Saving

    private func markDirty() {
        dirty = true
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.saveNow()
        }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }

    func saveNow() {
        saveWork?.cancel()
        saveWork = nil
        // A read-only note's files are never written: they hold ink this build could not read.
        guard dirty, !inkReadOnly else { return }
        dirty = false
        let snapshot = pages.map(\.strokes)
        let stickers = pages.map(\.stickers)
        let url = store.inkURL(for: meta.id)
        let stickersURL = store.stickersURL(for: meta.id)
        saveQueue.async {
            let data = InkCodec.encode(snapshot)
            try? data.write(to: url, options: .atomic)
            if stickers.contains(where: { !$0.isEmpty }) {
                if let json = try? JSONEncoder().encode(stickers) {
                    try? json.write(to: stickersURL, options: .atomic)
                }
            } else {
                try? FileManager.default.removeItem(at: stickersURL)
            }
        }
        store.touch(meta.id)
    }

    // MARK: Lecture replay

    /// Hides strokes while a take replays; an empty set shows all ink again.
    func setReplayHidden(_ ids: Set<Int>) {
        guard ids != replayHidden else { return }
        replayHidden = ids
        replayRevision += 1
        onInkChange?()
    }

    /// The pages as drawn: without the strokes a replay still hides. Each filtered state gets its own
    /// version (so the GPU follows it), and strokes appearing in writing order are appended, not rebuilt.
    var renderPages: [PageInk] {
        guard !replayHidden.isEmpty else { return pages }
        let shift = replayRevision << 32
        return pages.map { page in
            var shown = page
            shown.strokes = page.strokes.filter { !replayHidden.contains($0.id) }
            shown.version = page.version &+ shift
            return shown
        }
    }

    /// Every stroke's id and moment, for the replay.
    var strokeBirths: [(id: Int, birth: Double)] {
        pages.flatMap { page in page.strokes.map { (id: $0.id, birth: $0.birth) } }
    }

    /// The moment of the topmost stroke under a document point, within `reach` points of its line.
    func strokeBirth(near docPoint: CGPoint, reach: CGFloat) -> Double? {
        guard let index = layout.page(containing: docPoint, tolerance: reach), index < pages.count else { return nil }
        let o = layout.pageRects[index].origin
        let p = SIMD2<Float>(Float(docPoint.x - o.x), Float(docPoint.y - o.y))
        for s in pages[index].strokes.reversed() {
            let r = Float(reach) + s.maxRadius
            let b = s.bounds
            guard p.x >= b.minX - r, p.x <= b.maxX + r, p.y >= b.minY - r, p.y <= b.maxY + r else { continue }
            for q in s.points {
                let d = q.position - p
                if (d * d).sum() <= r * r { return s.birth }
            }
        }
        return nil
    }

    func close() {
        let wasDirty = dirty
        saveLastPage()
        saveNow()
        // A read-only note keeps its search text and thumbnail too: both would come out empty.
        guard !inkReadOnly else { return }
        // The handwriting becomes searchable text (only pages whose ink changed are read).
        let ink = pages.map(\.strokes)
        let noteID = meta.id
        Task.detached(priority: .utility) {
            await InkTextCache.refresh(note: noteID, pages: ink)
        }
        if wasDirty || meta.kind == .notebook {
            store.makeThumbnail(for: meta, strokes: pages.first?.strokes ?? [], stickers: pages.first?.stickers ?? [])
        }
    }

    // MARK: Content for Claude and export

    var pdfKitDocument: PDFDocument? {
        if pdfKitDocumentStorage == nil, let url = pdfURL {
            pdfKitDocumentStorage = PDFDocument(url: url)
        }
        return pdfKitDocumentStorage
    }

    var pdfFileSize: Int {
        guard let url = pdfURL,
              let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? NSNumber else { return 0 }
        return size.intValue
    }

    func pageRange(around page: Int, radius: Int) -> ClosedRange<Int> {
        let last = max(0, pageCount - 1)
        let p = min(max(page, 0), last)
        return max(0, p - radius)...min(last, p + radius)
    }

    /// Text of the given pages, each prefixed with its page number.
    func pageText(_ range: ClosedRange<Int>) -> String {
        guard let doc = pdfKitDocument else { return "" }
        var parts: [String] = []
        for i in range where i < doc.pageCount {
            let text = doc.page(at: i)?.string ?? ""
            parts.append("--- Sayfa \(i + 1) ---\n\(text)")
        }
        return parts.joined(separator: "\n\n")
    }

    /// A smaller PDF that only contains `range`.
    func subPDFData(_ range: ClosedRange<Int>) -> Data? {
        guard let doc = pdfKitDocument else { return nil }
        if range.lowerBound == 0, range.upperBound >= doc.pageCount - 1, let url = pdfURL {
            return try? Data(contentsOf: url)
        }
        let out = PDFDocument()
        var j = 0
        for i in range where i < doc.pageCount {
            if let page = doc.page(at: i)?.copy() as? PDFPage {
                out.insert(page, at: j)
                j += 1
            }
        }
        return j > 0 ? out.dataRepresentation() : nil
    }

    /// Text layer of one PDF page (empty for scanned pages and notebooks).
    func plainText(page index: Int) -> String {
        guard let doc = pdfKitDocument, index >= 0, index < doc.pageCount else { return "" }
        return doc.page(at: index)?.string ?? ""
    }

    /// One PDF page read from where its glyphs stand (PageGlyphs, PageLayout): typeset fractions,
    /// powers and the pieces PDFKit's reading order moves come back whole; nil without a text layer.
    func layoutText(page index: Int) -> String? {
        guard let doc = pdfKitDocument, index >= 0, index < doc.pageCount, let page = doc.page(at: index) else { return nil }
        return PageGlyphs.text(page)
    }

    /// The page with its ink as a JPEG (what the user sees, minus the 3D effects).
    func pageImageJPEG(_ index: Int, longEdge: CGFloat = 2000) -> Data? {
        pageImage(index, longEdge: longEdge)?.jpegData(compressionQuality: 0.82)
    }

    /// The page with its ink as an image (used for OCR and vision models). `plainInk` draws every
    /// stroke as an even dark line, which reads better than the decorated look.
    func pageImage(_ index: Int, longEdge: CGFloat = 2000, plainInk: Bool = false) -> UIImage? {
        guard layout.pageSizes.indices.contains(index) else { return nil }
        let size = layout.pageSizes[index]
        let scale = longEdge / max(size.width, size.height, 1)
        let pixelSize = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let strokes = pages[index].strokes
        let stickers = pages[index].stickers
        let page = cgDocumentStorage?.page(at: index + 1)
        let paper = meta.paper
        let image = UIGraphicsImageRenderer(size: pixelSize, format: format).image { ctx in
            let cg = ctx.cgContext
            cg.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            cg.fill(CGRect(origin: .zero, size: pixelSize))
            cg.scaleBy(x: scale, y: scale)
            if let page {
                PDFGeometry.draw(page: page, in: cg)
            } else if !plainInk {
                PaperDrawer.draw(paper, size: size, in: cg)
            }
            if !plainInk {
                StickerArt.drawAll(stickers, in: cg)
            }
            if plainInk {
                FlatInk.drawPlain(strokes, in: cg)
            } else {
                FlatInk.draw(strokes, in: cg)
            }
        }
        return image
    }

    /// Flattens the note (PDF + ink) into a new PDF file for sharing.
    func exportPDF() throws -> URL {
        let first = layout.pageSizes.first ?? NoteMeta.a4
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: first))
        let data = renderer.pdfData { ctx in
            for i in 0..<layout.count {
                let size = layout.pageSizes[i]
                ctx.beginPage(withBounds: CGRect(origin: .zero, size: size), pageInfo: [:])
                let cg = ctx.cgContext
                if isPDF, let page = cgDocumentStorage?.page(at: i + 1) {
                    PDFGeometry.draw(page: page, in: cg)
                } else {
                    PaperDrawer.draw(meta.paper, size: size, in: cg)
                }
                StickerArt.drawAll(pages[i].stickers, in: cg)
                FlatInk.draw(pages[i].strokes, in: cg)
            }
        }
        let safe = meta.title.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")).joined(separator: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent((safe.isEmpty ? Loc.t("Not") : safe) + ".pdf")
        try data.write(to: url, options: .atomic)
        return url
    }
}
