import Foundation

/// The zoom window's box: the part of a page the magnified writing panel shows (page points). Writing
/// large in the panel lands small in the box; when the writing reaches the box's right side the box
/// moves on along the line, and at the right margin it wraps to the next line, like Notability's zoom.
struct ZoomBox: Equatable {
    var page: Int
    var rect: CGRect

    /// How far the box moves on: three quarters of its width, so the last word stays in view.
    static let step: CGFloat = 0.75
    /// A new line starts this many box heights lower (lines a little closer than the box is tall).
    static let lineStep: CGFloat = 0.85

    /// The first box on a page: 40 % of the page wide, as tall as the panel's shape asks, at the
    /// top-left margin.
    static func initial(page: Int, pageSize: CGSize, margin: CGFloat, aspect: CGFloat) -> ZoomBox {
        let width = (pageSize.width * 0.4).rounded()
        let height = (width / max(aspect, 1)).rounded()
        return ZoomBox(page: page, rect: CGRect(x: margin, y: margin * 2, width: width, height: height))
    }

    /// Moved on after the writing reached the right side: along the line, to the right margin, or
    /// to the start of the next line; it stays when the page has no room below.
    func advanced(pageSize: CGSize, margin: CGFloat) -> ZoomBox {
        let right = pageSize.width - margin
        var next = self
        if rect.maxX + rect.width * Self.step <= right + 0.5 {
            next.rect.origin.x += rect.width * Self.step
        } else if rect.maxX < right - 0.5 {
            next.rect.origin.x = right - rect.width
        } else {
            return newLine(pageSize: pageSize, margin: margin)
        }
        return next
    }

    /// Back along the line, not past the left margin.
    func back(margin: CGFloat) -> ZoomBox {
        var next = self
        next.rect.origin.x = max(margin, rect.minX - rect.width * Self.step)
        return next
    }

    /// The start of the next line; it stays when the page has no room below.
    func newLine(pageSize: CGSize, margin: CGFloat) -> ZoomBox {
        let y = rect.minY + rect.height * Self.lineStep
        guard y + rect.height <= pageSize.height - margin + 0.5 else { return self }
        var next = self
        next.rect.origin = CGPoint(x: margin, y: y)
        return next
    }
}
