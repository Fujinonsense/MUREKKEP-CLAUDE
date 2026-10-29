import SwiftUI
import UIKit

/// The app's themes. "Siyah beyaz" (black and white) is free and the default: plain paper that
/// follows the system's light or dark look, no picture. The ultra premium themes are Mürekkep Pro's:
/// each one a picture made for the app with Higgsfield (the ruled notebook, and material and light:
/// liquid glass, silk, molten gold, paper waves, reeded glass, magnetic fluid, holographic foil,
/// glass orbs, light trails and mother of pearl) laid behind the library. Each picture comes full
/// size for the library and as a small thumbnail ("-thumb") for Settings, so the picker does not
/// decode ten large images.
///
/// To add a Pro theme: a case here, its name in `title`, its picture in Assets.xcassets/Backgrounds
/// as "bg-<case, lowercased>" with a "-thumb" twin, whether it is dark in `isDark`, its wash, and
/// its place in `proThemes`.
enum AppBackground: String, CaseIterable, Identifiable, Codable {
    case paper
    /// The coloured free papers of earlier builds. Black and white took their place; the cases stay
    /// only so a saved choice still decodes (`shown` turns them into paper).
    case ivory
    case sand
    case sage
    case lavender
    case night
    case ruled
    case glass
    case silk
    case molten
    case paperWave
    case reeded
    case ferro
    case holo
    case orbs
    case lightPaint
    case pearl

    var id: String { rawValue }

    /// Black and white: the free theme, and the default.
    static let free: AppBackground = .paper

    /// The ultra premium themes, in the order Settings and the Pro page show them.
    static let proThemes: [AppBackground] = [.ruled, .glass, .silk, .molten, .paperWave, .reeded, .ferro, .holo, .orbs, .lightPaint, .pearl]

    /// A coloured paper of an earlier build, shown as black and white now.
    var isRetired: Bool {
        switch self {
        case .ivory, .sand, .sage, .lavender, .night: return true
        default: return false
        }
    }

    var isPremium: Bool {
        switch self {
        case .paper, .ivory, .sand, .sage, .lavender, .night: return false
        default: return true
        }
    }

    /// What this choice draws: a retired colour is black and white.
    var shown: AppBackground { isRetired ? .paper : self }

    var title: String {
        switch self {
        case .paper: return Loc.t("Siyah beyaz")
        case .ivory: return Loc.t("Fildişi")
        case .sand: return Loc.t("Kum")
        case .sage: return Loc.t("Adaçayı")
        case .lavender: return Loc.t("Lavanta")
        case .night: return Loc.t("Gece")
        case .ruled: return Loc.t("Defter")
        case .glass: return Loc.t("Sıvı cam")
        case .silk: return Loc.t("İpek")
        case .molten: return Loc.t("Erimiş altın")
        case .paperWave: return Loc.t("Kâğıt dalga")
        case .reeded: return Loc.t("Buzlu cam")
        case .ferro: return Loc.t("Manyetik sıvı")
        case .holo: return Loc.t("Hologram")
        case .orbs: return Loc.t("Cam küreler")
        case .lightPaint: return Loc.t("Işık izi")
        case .pearl: return Loc.t("Sedef")
        }
    }

    /// The picture in Assets.xcassets ("bg-paperwave", thumbnail "bg-paperwave-thumb"); nil for
    /// black and white and the ruled paper.
    var imageName: String? {
        switch self {
        case .paper, .ivory, .sand, .sage, .lavender, .night, .ruled: return nil
        default: return "bg-" + rawValue.lowercased()
        }
    }

    /// Dark pictures turn the library's text and controls light; light pictures keep them dark.
    var isDark: Bool {
        switch self {
        case .molten, .reeded, .ferro, .lightPaint: return true
        default: return false
        }
    }

    /// How much paper (or, on a dark picture, night) lies over the picture so the library reads on
    /// it. The bright reeded glass takes the most, so light text stays clear on its orange and pink.
    var wash: Double {
        switch self {
        case .reeded: return 0.28
        case .molten: return 0.18
        case .silk: return 0.16
        case .ferro: return 0.15
        case .lightPaint: return 0.12
        case .glass, .paperWave, .holo, .pearl: return 0.10
        case .orbs: return 0.08
        default: return 0
        }
    }

    /// Choices from earlier builds, mapped to today's: each old picture to the new one closest in
    /// light and colour, the retired colours to black and white.
    static func migrated(_ raw: String) -> AppBackground? {
        if let kind = AppBackground(rawValue: raw) { return kind.shown }
        switch raw {
        case "ebru": return .holo
        case "ink", "inkFlow": return .ferro
        case "goldLeaf": return .molten
        case "watercolor": return .orbs
        case "iznik": return .paperWave
        case "aurora", "starlight": return .lightPaint
        case "sakura": return .pearl
        case "aegean", "sea": return .glass
        case "bosphorus": return .reeded
        case "cotton": return .silk
        default: return nil
        }
    }

    /// The themes this build has: black and white, then the Pro themes whose picture is present.
    static var available: [AppBackground] {
        [free] + proThemes.filter { kind in kind.imageName.map { UIImage(named: $0 + "-thumb") != nil } ?? true }
    }
}

/// One theme's backdrop, drawn to fill its space. `preview` draws a small tile (the thumbnail, and
/// the ruled paper's lines close together).
struct AppBackgroundView: View {
    let kind: AppBackground
    var preview = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Group {
            switch kind.shown {
            case .paper, .ivory, .sand, .sage, .lavender, .night: Theme.paper
            case .ruled: preview ? RuledPaper(spacing: 11, top: 9) : RuledPaper()
            default: artwork
            }
        }
        .accessibilityHidden(true)
    }

    /// The bath colour takes the space it is given and the picture fills it from an overlay, so a
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
}

/// The chosen theme behind the library, with the text colours that read on it: light text on a
/// dark picture, dark text on a light one, the system's choice in black and white. A Pro theme
/// shows as black and white while Pro is locked.
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

/// Settings › Görünüm › Tema: black and white first, then the Pro themes' previews. A locked one
/// opens the Pro page.
struct AppBackgroundPicker: View {
    @Binding var selection: AppBackground
    @ObservedObject private var pro = ProStore.shared
    private let columns = [GridItem(.adaptive(minimum: 112, maximum: 150), spacing: 14)]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(Loc.t("Tema"))
                Spacer()
                Text(selection.shown.title)
                    .foregroundStyle(Theme.muted)
            }
            LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                ForEach(AppBackground.available) { kind in
                    tile(kind)
                }
            }
        }
    }

    private func tile(_ kind: AppBackground) -> some View {
        let chosen = selection.shown == kind
        let locked = kind.isPremium && pro.locks
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
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
                    .overlay(shape.strokeBorder(chosen ? Theme.ink : Theme.hairline, lineWidth: chosen ? 2 : 1))
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
                Text(kind.title)
                    .font(.caption.weight(chosen ? .semibold : .regular))
                    .foregroundStyle(chosen ? Theme.text : Theme.muted)
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
