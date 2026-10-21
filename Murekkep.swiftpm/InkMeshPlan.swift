import Foundation

/// How a page's GPU geometry follows a change of its strokes. The buffers hold the highlighters
/// first, then every other stroke in page order, so writing a new line (the common change) only
/// needs its own mesh copied after the others; the whole page is rebuilt only when strokes were
/// removed, reordered, or when the new one is a highlighter or grass (both live elsewhere in the
/// buffers).
enum InkMeshPlan: Equatable {
    /// The same strokes: keep everything.
    case same
    /// The strokes from this buffer position on are new and go after the existing ones.
    case append(from: Int)
    case rebuild

    /// `old` is the stroke ids in buffer order; `new` the page's strokes in page order.
    static func plan(old: [Int], new: [(id: Int, highlighter: Bool, grass: Bool)]) -> InkMeshPlan {
        guard !old.isEmpty else { return .rebuild }
        let order = new.filter(\.highlighter).map(\.id) + new.filter { !$0.highlighter }.map(\.id)
        if order == old { return .same }
        guard order.count > old.count, order[..<old.count].elementsEqual(old) else { return .rebuild }
        // Linear in the page's strokes: this runs on every lift of the pencil.
        let added = Set(order[old.count...])
        guard !new.contains(where: { added.contains($0.id) && ($0.highlighter || $0.grass) }) else { return .rebuild }
        return .append(from: old.count)
    }
}
