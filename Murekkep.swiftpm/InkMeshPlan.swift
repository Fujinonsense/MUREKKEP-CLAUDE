import Foundation

/// How a page's GPU geometry follows a change of its strokes. The buffers hold the highlighters
/// first, then every other stroke in page order, so writing a new line (the common change) only
/// needs its own mesh copied after the others. Erasing, cutting, moving or reordering strokes keeps
/// the other strokes' meshes where they are and only redraws the lists; the whole page is rebuilt
/// when new grass appears (its blades live elsewhere in the buffers) or the page was never built.
enum InkMeshPlan: Equatable {
    /// The same strokes: keep everything.
    case same
    /// The strokes from this buffer position on are new and go after the existing ones.
    case append(from: Int)
    /// Strokes went, came in between, or moved in the order: keep the meshes, redo the lists.
    case keep
    case rebuild

    /// `old` is the stroke ids in buffer order; `new` the page's strokes in page order.
    static func plan(old: [Int], new: [(id: Int, highlighter: Bool, grass: Bool)]) -> InkMeshPlan {
        guard !old.isEmpty else { return .rebuild }
        let order = new.filter(\.highlighter).map(\.id) + new.filter { !$0.highlighter }.map(\.id)
        if order == old { return .same }
        // Linear in the page's strokes: this runs on every lift of the pencil and every eraser step.
        let known = Set(old)
        let added = new.filter { !known.contains($0.id) }
        if added.contains(where: \.grass) { return .rebuild }
        if order.count > old.count, order[..<old.count].elementsEqual(old), !added.contains(where: \.highlighter) {
            return .append(from: old.count)
        }
        return .keep
    }
}
