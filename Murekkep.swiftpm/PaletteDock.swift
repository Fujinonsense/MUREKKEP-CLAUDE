import Foundation

/// The edges the notebook's pen bar can stand on (checked in tools/swiftcheck). The left edge holds the
/// drafting rail, so the bar never goes there.
enum PaletteEdge: String, CaseIterable {
    case top, bottom, trailing

    /// Down the right side the bar stands upright.
    var isVertical: Bool { self == .trailing }

    /// The edge a bar let go of at `x, y` in a canvas `width` × `height` goes to: the nearest of the three.
    /// A point by the left edge goes to the nearer of top and bottom; a tie keeps `current`.
    static func nearest(x: Double, y: Double, width: Double, height: Double, current: PaletteEdge) -> PaletteEdge {
        func distance(_ edge: PaletteEdge) -> Double {
            switch edge {
            case .top: return y
            case .bottom: return height - y
            case .trailing: return width - x
            }
        }
        let best = allCases.map(distance).min() ?? 0
        return distance(current) == best ? current : allCases.first { distance($0) == best } ?? current
    }
}
