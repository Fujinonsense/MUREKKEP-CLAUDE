import SwiftUI
import UIKit

/// The backgrounds behind the library: plain colours for everyone, and in Mürekkep Pro artwork made
/// for the app with Higgsfield — Turkish ebru, indigo ink in water, gold leaf, a watercolour wash,
/// Iznik tiles, the northern lights, cherry blossom, the Aegean, the Bosphorus at dawn and cotton
/// paper — plus the ruled notebook. Each artwork comes full size for the library and as a small
/// thumbnail ("-thumb") for Settings, so the picker does not decode ten large images.
enum AppBackground: String, CaseIterable, Identifiable, Codable {
    case paper
    case ivory
    case sand
    case sage
    case lavender
    case night
    case ruled
    case ebru
    case ink
    case goldLeaf
    case watercolor
    case iznik
    case aurora
    case sakura
    case aegean
    case bosphorus
    case cotton

    var id: String { rawValue }

    var isPremium: Bool {
        switch self {
        case .paper, .ivory, .sand, .sage, .lavender, .night: return false
        default: return true
        }
    }

    var title: String {
        switch self {
        case .paper: return Loc.t("Kâğıt")
        case .ivory: return Loc.t("Fildişi")
        case .sand: return Loc.t("Kum")
        case .sage: return Loc.t("Adaçayı")
        case .lavender: return Loc.t("Lavanta")
        case .night: return Loc.t("Gece")
        case .ruled: return Loc.t("Defter")
        case .ebru: return Loc.t("Ebru")
        case .ink: return Loc.t("Mürekkep")
        case .goldLeaf: return Loc.t("Altın varak")
        case .watercolor: return Loc.t("Sulu boya")
        case .iznik: return Loc.t("İznik çinisi")
        case .aurora: return Loc.t("Kuzey ışıkları")
        case .sakura: return "Sakura"
        case .aegean: return Loc.t("Ege")
        case .bosphorus: return Loc.t("Boğaz")
        case .cotton: return Loc.t("Pamuk kâğıt")
        }
    }

    /// The artwork in Assets.xcassets ("bg-ebru", thumbnail "bg-ebru-thumb"); nil for colours and
    /// the ruled paper.
    var imageName: String? {
        switch self {
        case .paper, .ivory, .sand, .sage, .lavender, .night, .ruled: return nil
        case .goldLeaf: return "bg-goldleaf"
        default: return "bg-" + rawValue
        }
    }

    /// Dark backgrounds turn the library's text and controls light; light artwork keeps them dark.
    var isDark: Bool {
        switch self {
        case .night, .ink, .goldLeaf, .aurora: return true
        default: return false
        }
    }

    /// How much paper (or, on dark artwork, night) lies over the artwork so the library reads on it.
    var wash: Double {
        switch self {
        case .ebru: return 0.38
        case .iznik: return 0.45
        case .aegean: return 0.22
        case .watercolor, .sakura, .bosphorus: return 0.12
        case .ink, .goldLeaf, .aurora: return 0.22
        default: return 0
        }
    }

    /// Choices from earlier test builds, mapped to today's.
    static func migrated(_ raw: String) -> AppBackground? {
        if let kind = AppBackground(rawValue: raw) { return kind }
        switch raw {
        case "inkFlow": return .ink
        case "starlight": return .aurora
        case "sea": return .aegean
        default: return nil
        }
    }

    /// The backgrounds this build has: artwork whose image is missing is left out.
    static var available: [AppBackground] {
        allCases.filter { kind in kind.imageName.map { UIImage(named: $0 + "-thumb") != nil } ?? true }
    }
}

/// One background, drawn to fill its space. `preview` draws a small tile (the thumbnail, and the
/// ruled paper's lines close together).
struct AppBackgroundView: View {
    let kind: AppBackground
    var preview = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Group {
            switch kind {
            case .paper: Theme.paper
            case .ivory: Self.solid(light: (0.984, 0.965, 0.918), dark: (0.118, 0.106, 0.086))
            case .sand: Self.solid(light: (0.937, 0.902, 0.831), dark: (0.165, 0.141, 0.106))
            case .sage: Self.solid(light: (0.890, 0.922, 0.882), dark: (0.094, 0.133, 0.110))
            case .lavender: Self.solid(light: (0.925, 0.910, 0.961), dark: (0.114, 0.102, 0.169))
            case .night: Color(red: 0.055, green: 0.082, blue: 0.157)
            case .ruled: preview ? RuledPaper(spacing: 11, top: 9) : RuledPaper()
            default: artwork
            }
        }
        .accessibilityHidden(true)
    }

    /// The bath colour takes the space it is given and the artwork fills it from an overlay, so a
    /// square image never makes the view larger than its frame.
    private var artwork: some View {
        (kind.isDark ? Color(red: 0.05, green: 0.07, blue: 0.13) : Theme.paperWarm)
            .overlay {
                if let name = kind.imageName {
                    Image(preview ? name + "-thumb" : name)
                        .resizable()
                        .scaledToFill()
                }
            }
            .overlay((kind.isDark ? Color.black : Theme.paperWarm).opacity(preview ? 0 : kind.wash))
            .clipped()
    }

    private static func solid(light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
        Color(uiColor: UIColor { trait in
            let c = trait.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
        })
    }
}

/// The chosen background behind the library, with the text colours that read on it: light text on
/// dark artwork, dark text on light artwork, the system's choice on plain colours. A Pro background
/// shows as paper while Pro is locked.
struct LibraryBackdrop: ViewModifier {
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject private var pro = ProStore.shared
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let kind = settings.shownBackground(locked: pro.locks)
        let textScheme: ColorScheme = kind.isDark ? .dark : (kind.imageName != nil ? .light : scheme)
        content
            .environment(\.colorScheme, textScheme)
            .background {
                AppBackgroundView(kind: kind)
                    .ignoresSafeArea()
            }
    }
}

/// The background tiles in Settings: plain colours for everyone, the artwork marked Pro until Pro.
struct AppBackgroundPicker: View {
    @Binding var selection: AppBackground
    @ObservedObject private var pro = ProStore.shared
    private let columns = [GridItem(.adaptive(minimum: 112, maximum: 150), spacing: 14)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
            ForEach(AppBackground.available) { kind in
                tile(kind)
            }
        }
    }

    private func tile(_ kind: AppBackground) -> some View {
        let chosen = selection == kind
        let locked = kind.isPremium && pro.locks
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return Button {
            if locked {
                _ = pro.unlock(.premiumBackground)
            } else {
                selection = kind
            }
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                AppBackgroundView(kind: kind, preview: true)
                    .frame(height: 84)
                    .clipShape(shape)
                    .overlay(shape.strokeBorder(chosen ? Theme.ink : Theme.hairline, lineWidth: chosen ? 2.5 : 0.6))
                    .overlay(alignment: .topTrailing) {
                        if locked {
                            ProBadge()
                                .padding(7)
                        } else if chosen {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.callout)
                                .foregroundStyle(Color.white, Theme.ink)
                                .padding(6)
                        }
                    }
                    .shadow(color: Theme.shadow.opacity(chosen ? 0.18 : 0.08), radius: chosen ? 8 : 4, y: 2)
                Text(kind.title)
                    .font(.caption.weight(chosen ? .semibold : .regular))
                    .foregroundStyle(chosen ? Color.primary : Color.secondary)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(kind.title)
        .accessibilityHint(locked ? Loc.t("Mürekkep Pro'da") : "")
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}
