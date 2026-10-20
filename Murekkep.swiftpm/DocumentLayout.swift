import Foundation

/// Vertical stack of pages in "document space" (points, y down).
struct DocumentLayout {
    let pageSizes: [CGSize]
    let pageRects: [CGRect]
    let contentSize: CGSize

    static let margin: CGFloat = 28
    static let gap: CGFloat = 22

    init(pageSizes: [CGSize]) {
        self.pageSizes = pageSizes
        let maxW = pageSizes.map(\.width).max() ?? NoteMeta.a4.width
        var y = Self.margin
        var rects: [CGRect] = []
        rects.reserveCapacity(pageSizes.count)
        for s in pageSizes {
            rects.append(CGRect(x: Self.margin + (maxW - s.width) / 2, y: y, width: s.width, height: s.height))
            y += s.height + Self.gap
        }
        pageRects = rects
        let height = pageSizes.isEmpty ? Self.margin * 2 : y - Self.gap + Self.margin
        contentSize = CGSize(width: maxW + Self.margin * 2, height: height)
    }

    var count: Int { pageRects.count }

    /// Indices of pages intersecting `rect` (document space).
    func pages(intersecting rect: CGRect) -> [Int] {
        guard !pageRects.isEmpty, !rect.isNull, !rect.isEmpty else { return [] }
        // First page whose bottom is below the rect top.
        var lo = 0
        var hi = pageRects.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if pageRects[mid].maxY < rect.minY { lo = mid + 1 } else { hi = mid }
        }
        var result: [Int] = []
        var i = lo
        while i < pageRects.count, pageRects[i].minY <= rect.maxY {
            if pageRects[i].intersects(rect) { result.append(i) }
            i += 1
        }
        return result
    }

    func page(containing point: CGPoint, tolerance: CGFloat = 0) -> Int? {
        let probe = CGRect(x: point.x - tolerance, y: point.y - tolerance, width: tolerance * 2 + 0.001, height: tolerance * 2 + 0.001)
        for i in pages(intersecting: probe) where pageRects[i].insetBy(dx: -tolerance, dy: -tolerance).contains(point) {
            return i
        }
        return nil
    }

    /// Page with the largest visible area in `rect`, falling back to the closest one.
    func dominantPage(in rect: CGRect) -> Int {
        guard !pageRects.isEmpty else { return 0 }
        var best = -1
        var bestArea: CGFloat = 0
        for i in pages(intersecting: rect) {
            let r = pageRects[i].intersection(rect)
            let area = r.width * r.height
            if area > bestArea {
                bestArea = area
                best = i
            }
        }
        if best >= 0 { return best }
        let cy = rect.midY
        var closest = 0
        var dist = CGFloat.greatestFiniteMagnitude
        for (i, r) in pageRects.enumerated() {
            let d = abs(r.midY - cy)
            if d < dist {
                dist = d
                closest = i
            }
        }
        return closest
    }
}
