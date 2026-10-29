import SwiftUI
import UIKit

/// The app's themes. "Siyah beyaz" (black and white) is free and the default: plain paper that
/// follows the system's light or dark look, no picture. The ultra premium themes are Mürekkep Pro's:
/// each one a picture made for the app with Higgsfield laid behind the library: the zen set (ebru
/// marbling, an inkwell, lapis, glaze, gold leaf, ink wash), the ruled notebook, and material and
/// light (liquid glass, silk, molten gold, paper waves, reeded glass, magnetic fluid, holographic
/// foil, glass orbs, light trails and mother of pearl). Each picture comes full size for the
/// library and as a small thumbnail ("-thumb") for Settings, so the picker does not decode the
/// large images. The pictures are made with tools/make_backgrounds.py.
///
/// To add a Pro theme: a case here (its raw value is its asset name), its name in `title`, its
/// picture in Assets.xcassets/Backgrounds as "bg-<case, lowercased>" with a "-thumb" twin, whether
/// it is dark in `isDark`, its wash, its accent, and its place in `proThemes`.
enum AppBackground: String, CaseIterable, Identifiable, Codable {
    case paper
    /// The coloured free papers of earlier builds. Black and white took their place; the cases stay
    /// only so a saved choice still decodes (`shown` turns them into paper).
    case ivory
    case sand
    case sage
    case lavender
    case night
    /// The zen set (2026-10-29), already mirrored so each picture's calm side lies behind the
    /// sidebar and the title.
    case ebru
    case hokka
    case lapis
    case cini
    case varak
    case lavi
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

    /// The ultra premium themes, in the order Settings and the Pro page show them: the zen set first.
    static let proThemes: [AppBackground] = [.ebru, .hokka, .lapis, .cini, .varak, .lavi, .ruled, .glass, .silk, .molten, .paperWave,
                                             .reeded, .ferro, .holo, .orbs, .lightPaint, .pearl]

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
        // "Ebru" is the break corner's game too, which keeps its name in English.
        case .ebru: return Loc.named("Ebru", kind: "tema")
        case .hokka: return Loc.t("Hokka")
        case .lapis: return Loc.t("Lapis")
        case .cini: return Loc.t("Çini")
        case .varak: return Loc.t("Varak")
        case .lavi: return Loc.t("Lavi")
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
        case .ebru, .lapis, .varak, .molten, .reeded, .ferro, .lightPaint: return true
        default: return false
        }
    }

    /// How much paper (or, on a dark picture, night) lies over the picture so the library reads on
    /// it: with these, light text (#F2F3F5) or ink (#141414) reaches 4.5:1 over the darkest or
    /// brightest part of the sidebar and the title area. The bright reeded glass takes the most, so
    /// light text stays clear on its orange and pink.
    var wash: Double {
        switch self {
        case .reeded: return 0.28
        case .ebru: return 0.20
        case .molten: return 0.18
        case .silk: return 0.16
        case .ferro: return 0.15
        case .lightPaint, .lavi: return 0.12
        case .glass, .paperWave, .holo, .pearl, .hokka, .lapis, .cini, .varak: return 0.10
        case .orbs: return 0.08
        default: return 0
        }
    }

    /// The notes' own wash (NotesWash): warm paper at 0.88 on a light picture, night at 0.65 on a
    /// dark one, under the covers, their captions and the empty state. Measured over every pixel of
    /// each picture, so whatever the crop: the grey captions ("3 sayfa, dün") keep at least 5.5:1 on
    /// the light pictures and 4.5:1 on at least 96 % of each dark one, down to 3.5:1 on the
    /// brightest gold and light (night at 0.72 would keep 4.5:1 everywhere). None without a
    /// picture: black and white and the ruled paper are paper already.
    var notesWash: Double {
        guard imageName != nil else { return 0 }
        return isDark ? 0.65 : 0.88
    }

    /// The theme's own accent, from its palette: gold on the dark pictures of the zen set, the
    /// picture's ink on the light ones, the brand ink elsewhere. The chrome still draws its chosen
    /// states with Theme.ink; this stands ready for the day the palettes are wired in.
    var accent: Color {
        switch self {
        case .ebru: return Self.rgb(0xD4A84F)
        case .hokka: return Self.rgb(0x234B7A)
        case .lapis: return Self.rgb(0xD2B062)
        case .cini: return Self.rgb(0x1F4FB5)
        case .varak: return Self.rgb(0xD5A65A)
        case .lavi: return Self.rgb(0xA8322D)
        default: return Theme.ink
        }
    }

    private static func rgb(_ hex: UInt32) -> Color {
        Color(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }

    /// Choices from earlier builds, mapped to today's: each old picture to the new one closest in
    /// light and colour, the retired colours to black and white. ("ebru" is a theme again and
    /// decodes by itself.)
    static func migrated(_ raw: String) -> AppBackground? {
        if let kind = AppBackground(rawValue: raw) { return kind.shown }
        switch raw {
        case "ink", "inkFlow": return .hokka
        case "goldLeaf": return .varak
        case "watercolor": return .orbs
        case "iznik": return .cini
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

/// The wash the notes lie on over a Pro theme's picture (`notesWash`). The picture stays clear
/// behind the sidebar and the pane's header; the wash lies behind the view it modifies (PaneScroll
/// gives that the pane's full width) and fades in over its top 40 points. `reach` is twice the
/// pane's height: the wash runs that far past the notes, so it reaches the bottom of the pane when
/// there are only a few, even while a short page is pulled up past its end (the scroll view clips
/// the rest).
struct NotesWash: ViewModifier {
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject private var pro = ProStore.shared
    let reach: CGFloat

    func body(content: Content) -> some View {
        let kind = settings.shownBackground(locked: pro.locks)
        let tone: Color = (kind.isDark ? Color.black : Theme.paperWarm).opacity(kind.notesWash)
        content
            .background(alignment: .top) {
                if kind.notesWash > 0 {
                    VStack(spacing: 0) {
                        LinearGradient(colors: [tone.opacity(0), tone], startPoint: .top, endPoint: .bottom)
                            .frame(height: 40)
                        tone
                    }
                    .padding(.bottom, -reach)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
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
