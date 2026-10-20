import Foundation

// Brushes live in Brushes.swift, paper templates in Templates.swift.

// MARK: - Color

struct InkColor: Equatable, Hashable, Codable {
    var r: Float
    var g: Float
    var b: Float
    var a: Float

    init(_ r: Float, _ g: Float, _ b: Float, _ a: Float = 1) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    init(hex: UInt32, alpha: Float = 1) {
        r = Float((hex >> 16) & 0xFF) / 255
        g = Float((hex >> 8) & 0xFF) / 255
        b = Float(hex & 0xFF) / 255
        a = alpha
    }

    var simd: SIMD4<Float> { SIMD4<Float>(r, g, b, a) }
}

// MARK: - Geometry

struct InkPoint: Equatable {
    /// Page-local position in points (origin top-left, y down).
    var x: Float
    var y: Float
    /// Radius in points.
    var r: Float
    /// 0...1, how much ink pooled here (slow strokes pool more).
    var ink: Float

    var position: SIMD2<Float> { SIMD2<Float>(x, y) }
}

struct InkRect: Equatable {
    var minX: Float
    var minY: Float
    var maxX: Float
    var maxY: Float

    static let empty = InkRect(minX: .infinity, minY: .infinity, maxX: -.infinity, maxY: -.infinity)

    init(minX: Float, minY: Float, maxX: Float, maxY: Float) {
        self.minX = minX
        self.minY = minY
        self.maxX = maxX
        self.maxY = maxY
    }

    init(_ a: SIMD2<Float>, _ b: SIMD2<Float>) {
        minX = min(a.x, b.x)
        minY = min(a.y, b.y)
        maxX = max(a.x, b.x)
        maxY = max(a.y, b.y)
    }

    var isEmpty: Bool { minX > maxX || minY > maxY }

    func expanded(by d: Float) -> InkRect {
        InkRect(minX: minX - d, minY: minY - d, maxX: maxX + d, maxY: maxY + d)
    }

    func intersects(_ o: InkRect) -> Bool {
        !(isEmpty || o.isEmpty) && minX <= o.maxX && o.minX <= maxX && minY <= o.maxY && o.minY <= maxY
    }

    func intersects(_ r: CGRect) -> Bool {
        intersects(InkRect(minX: Float(r.minX), minY: Float(r.minY), maxX: Float(r.maxX), maxY: Float(r.maxY)))
    }

    mutating func include(_ p: InkPoint) {
        minX = min(minX, p.x - p.r)
        minY = min(minY, p.y - p.r)
        maxX = max(maxX, p.x + p.r)
        maxY = max(maxY, p.y + p.r)
    }
}

@inline(__always) func vdot(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float { (a * b).sum() }
@inline(__always) func vlength(_ v: SIMD2<Float>) -> Float { vdot(v, v).squareRoot() }
@inline(__always) func clampf(_ v: Float, _ lo: Float, _ hi: Float) -> Float { min(max(v, lo), hi) }

// MARK: - Strokes

enum StrokeIDs {
    private final class Counter: @unchecked Sendable {
        let lock = NSLock()
        var value = 0
    }

    private static let shared = Counter()

    static func next() -> Int {
        let c = shared
        c.lock.lock()
        defer { c.lock.unlock() }
        c.value += 1
        return c.value
    }
}

struct Stroke: Identifiable, Equatable {
    let id: Int
    var brush: Brush
    var color: InkColor
    var width: Float
    /// Seconds since reference date when the stroke was committed (drives drying, cooling, blooming).
    var birth: Double
    /// Random per-stroke value for shader variation. For grass the integer part is the flower level.
    var seed: Float
    /// How long the pencil took to draw it (only known in the session it was drawn; not saved).
    var duration: Double
    private(set) var points: [InkPoint]
    private(set) var bounds: InkRect
    private(set) var maxRadius: Float

    init(brush: Brush, color: InkColor, width: Float, birth: Double, seed: Float, points: [InkPoint], duration: Double = 0) {
        id = StrokeIDs.next()
        self.brush = brush
        self.color = color
        self.width = width
        self.birth = birth
        self.seed = seed
        self.duration = duration
        self.points = points
        var box = InkRect.empty
        var maxR: Float = 0
        for p in points {
            box.include(p)
            maxR = max(maxR, p.r)
        }
        bounds = box
        maxRadius = maxR
    }

    /// Same look, different geometry (used by the partial eraser).
    func withPoints(_ pts: [InkPoint]) -> Stroke {
        Stroke(brush: brush, color: color, width: width, birth: birth, seed: seed, points: pts, duration: duration)
    }
}

struct PageInk {
    var strokes: [Stroke] = []
    /// Bumped on every change so GPU caches know when to rebuild.
    var version: Int = 0
    /// Pictures under the ink (emoji and illustrations).
    var stickers: [Sticker] = []
}

// MARK: - Documents

enum NoteKind: String, Codable {
    case pdf
    case notebook
}

struct NoteMeta: Codable, Identifiable, Hashable {
    var id: UUID
    var title: String
    var kind: NoteKind
    var created: Date
    var modified: Date
    var pageCount: Int
    var paper: PaperStyle
    /// Claude Files API id of the uploaded PDF (reused for whole-document questions).
    var claudeFileID: String?
    var claudeFileUploaded: Date?
    /// The library section (course) the note is filed under.
    var sectionID: UUID? = nil
    /// Starred in the library (missing in older indexes = not starred).
    var isFavorite: Bool? = nil
    /// The page the note was left on (0-based; missing = the first page).
    var lastPage: Int? = nil
    /// Bookmarked pages (0-based).
    var bookmarks: [Int]? = nil
    /// "single" shows one page at a time; missing = pages scroll on continuously.
    var pageMode: String? = nil

    var starred: Bool { isFavorite ?? false }

    static let a4 = CGSize(width: 595.28, height: 841.89)
}
