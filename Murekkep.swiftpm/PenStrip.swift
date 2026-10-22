import Foundation

/// Which pens stand in the notebook's pen bar (checked in tools/swiftcheck): the favourites always,
/// then the pens used last, so the bar holds five. Next to many favourites two recent pens still
/// stay. Each group keeps the panel's order, so a pen keeps its place when it is picked.
enum PenStrip {
    static let count = 5
    static let recentBesideFavorites = 2

    static func pens<Pen: Hashable>(favorites: [Pen], recent: [Pen], order: [Pen]) -> (favorites: [Pen], recent: [Pen]) {
        let starred = Set(favorites)
        let room = favorites.isEmpty ? count : max(recentBesideFavorites, count - starred.count)
        let lately = Set(recent.filter { !starred.contains($0) }.prefix(room))
        return (order.filter { starred.contains($0) }, order.filter { lately.contains($0) })
    }

    /// Stars a pen, or takes its star away.
    static func toggled<Pen: Equatable>(_ pen: Pen, in favorites: [Pen]) -> [Pen] {
        favorites.contains(pen) ? favorites.filter { $0 != pen } : favorites + [pen]
    }
}
