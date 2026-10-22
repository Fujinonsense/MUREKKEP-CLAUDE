import Foundation

/// The pen panel shows one shelf at a time (checked in tools/swiftcheck): the favourites, writing,
/// paint and nature pens, and the ten 3D inks together on their own shelf (Mürekkep Pro's in the
/// App Store edition). Every pen stands on exactly one shelf besides the favourites.
enum PenShelf: String, CaseIterable, Identifiable {
    case favorites
    case writing
    case paint
    case nature
    case threeD

    var id: String { rawValue }

    var title: String {
        switch self {
        case .favorites: return Loc.t("Favoriler")
        case .writing: return Loc.t("Yazı")
        case .paint: return Loc.t("Boya")
        case .nature: return Loc.t("Doğa")
        case .threeD: return Loc.t("3B mürekkep")
        }
    }

    /// The name in the panel's segmented control, short enough to never be cut.
    var shortTitle: String {
        switch self {
        case .threeD: return "3B"
        default: return title
        }
    }

    func brushes(favorites: [Brush]) -> [Brush] {
        switch self {
        case .favorites: return Brush.paletteOrder.filter { favorites.contains($0) }
        case .threeD: return Brush.paletteOrder.filter(\.isPremium)
        case .writing: return Brush.paletteOrder.filter { !$0.isPremium && $0.group == .writing }
        case .paint: return Brush.paletteOrder.filter { !$0.isPremium && $0.group == .paint }
        case .nature: return Brush.paletteOrder.filter { !$0.isPremium && ($0.group == .nature || $0.group == .shine) }
        }
    }

    /// The shelf a pen stands on (never the favourites).
    static func shelf(of brush: Brush) -> PenShelf {
        if brush.isPremium { return .threeD }
        switch brush.group {
        case .writing: return .writing
        case .paint: return .paint
        case .nature, .shine: return .nature
        }
    }

    /// The shelf the panel opens on: the one used last, else the favourites when there are any,
    /// else the shelf of the pen in hand.
    static func opening(saved: String, favorites: [Brush], current: Brush) -> PenShelf {
        if let shelf = PenShelf(rawValue: saved), shelf != .favorites || !favorites.isEmpty {
            return shelf
        }
        return favorites.isEmpty ? shelf(of: current) : .favorites
    }
}
