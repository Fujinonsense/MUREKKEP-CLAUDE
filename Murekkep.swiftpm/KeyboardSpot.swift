import Foundation

/// Where typing from a keyboard begins on the page in view (the Aa tool or the text pen, with a
/// keyboard case), in page points. The point goes to HandwritingConverter.typedLayout, which writes on
/// the first ruled line at or below it, so a point a fifth of a line under some ink writes on the line
/// after that ink.
///
/// Under the lowest ink in view, when a line still fits above the bottom of the view: at the left of
/// the last typed text when that is the lowest ink (typing goes on under it), else at the margin.
/// When the ink runs to the bottom of the view, the first free line in view; with none, the top line.
enum KeyboardSpot {
    static func start(lastTyped: CGRect?, ink: [CGRect], viewTop: CGFloat, viewBottom: CGFloat,
                      left: CGFloat, spacing: CGFloat) -> CGPoint {
        let inView = ink.filter { $0.maxY > viewTop && $0.minY < viewBottom }
        guard let bottom = inView.map(\.maxY).max() else {
            return CGPoint(x: left, y: viewTop + spacing)
        }
        if bottom + 2 * spacing <= viewBottom {
            let underTyped = lastTyped.map { abs($0.maxY - bottom) < 0.5 } ?? false
            return CGPoint(x: underTyped ? lastTyped!.minX : left, y: bottom + 0.2 * spacing)
        }
        var y = viewTop + 0.2 * spacing
        while y + spacing <= viewBottom {
            if !inView.contains(where: { $0.minY < y + spacing && $0.maxY > y }) {
                return CGPoint(x: left, y: y)
            }
            y += spacing / 4
        }
        return CGPoint(x: left, y: viewTop + spacing)
    }
}
