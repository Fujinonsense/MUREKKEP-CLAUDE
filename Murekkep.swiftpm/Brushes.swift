import Foundation

/// The sections of the pen panel.
enum BrushGroup: String, CaseIterable, Identifiable {
    case writing
    case paint
    case nature
    case shine

    var id: String { rawValue }

    var title: String {
        switch self {
        case .writing: return Loc.t("Yazı")
        case .paint: return Loc.t("Boya")
        case .nature: return Loc.t("Doğa")
        case .shine: return Loc.t("Işıltı")
        }
    }

    var brushes: [Brush] {
        Brush.paletteOrder.filter { $0.group == self }
    }
}

/// Raw values are stored in ink files, so existing ones never change. Older versions of the app
/// read unknown brushes as the plain pen.
enum Brush: UInt8, CaseIterable, Identifiable, Codable {
    case pen = 0
    case wet = 1
    case wave = 2
    case highlighter = 3
    case pencil = 4
    case calligraphy = 5
    case watercolor = 6
    case neon = 7
    case rainbow = 8
    case glitter = 9
    case grass = 10
    case sea = 11
    case lava = 12
    case fountain = 13
    case gold = 14
    case chrome = 15
    case ice = 16
    case jelly = 17
    case galaxy = 18
    case lightning = 19
    case pearl = 20
    case impasto = 21

    var id: UInt8 { rawValue }

    /// Order in the pen panel and the toolbar.
    static let paletteOrder: [Brush] = [
        .pen, .pencil, .fountain, .calligraphy, .highlighter,
        .watercolor, .impasto, .wet, .neon, .rainbow, .glitter,
        .sea, .wave, .grass, .lava, .ice, .lightning, .galaxy,
        .gold, .chrome, .pearl, .jelly,
    ]

    var group: BrushGroup {
        switch self {
        case .pen, .pencil, .fountain, .calligraphy, .highlighter: return .writing
        case .watercolor, .impasto, .wet, .neon, .rainbow, .glitter: return .paint
        case .sea, .wave, .grass, .lava, .ice, .lightning, .galaxy: return .nature
        case .gold, .chrome, .pearl, .jelly: return .shine
        }
    }

    /// The nature pens: free to try with a trial amount of ink in the App Store edition (ProPlan).
    var isTrialInk: Bool {
        switch self {
        case .sea, .wave, .grass: return true
        default: return false
        }
    }

    /// The 3D inks, marked with a star on the pen's barrel.
    var isPremium: Bool {
        switch self {
        case .lava, .fountain, .gold, .chrome, .ice, .jelly, .galaxy, .lightning, .pearl, .impasto: return true
        default: return false
        }
    }

    var title: String {
        switch self {
        case .pen: return Loc.t("Kalem")
        case .wet: return Loc.t("Islak mürekkep")
        case .wave: return Loc.t("Okyanus")
        case .highlighter: return Loc.t("Fosforlu")
        case .pencil: return Loc.t("Kurşun kalem")
        case .calligraphy: return Loc.t("Hat kalemi")
        case .watercolor: return Loc.t("Sulu boya")
        case .neon: return "Neon"
        case .rainbow: return Loc.t("Gökkuşağı")
        case .glitter: return Loc.t("Simli")
        case .grass: return Loc.t("Çim ve çiçek")
        case .sea: return Loc.t("Deniz dalgası")
        case .lava: return Loc.t("Lav")
        case .fountain: return Loc.t("Dolma kalem 3B")
        case .gold: return Loc.t("Sıvı altın")
        case .chrome: return Loc.t("Krom")
        case .ice: return Loc.t("Buz kristali")
        case .jelly: return Loc.t("Jöle")
        case .galaxy: return Loc.t("Galaksi")
        case .lightning: return Loc.t("Şimşek")
        case .pearl: return Loc.t("İnci dizisi")
        case .impasto: return Loc.t("Yağlı boya")
        }
    }

    var detail: String {
        switch self {
        case .pen: return Loc.t("Basınca duyarlı, keskin tükenmez kalem.")
        case .wet: return Loc.t("Parlak ve kabarık başlar, birkaç saniyede kurur.")
        case .wave: return Loc.t("Kuşbakışı 3B deniz: içinde dalgalar ve ışık oyunları.")
        case .highlighter: return Loc.t("Metnin altını boyar, yazıyı kapatmaz.")
        case .pencil: return Loc.t("Kâğıt dokulu grafit. Pencil'ı yatırınca geniş ve yumuşak tarar.")
        case .calligraphy: return Loc.t("Yassı uç: yöne göre incelir, kalınlaşır. Pencil Pro'yu döndürünce uç da döner.")
        case .watercolor: return Loc.t("Saydam, kenarları koyulaşan boya lekeleri.")
        case .neon: return Loc.t("Parlayan ışık tüpü.")
        case .rainbow: return Loc.t("Çizdikçe renk değiştirir.")
        case .glitter: return Loc.t("Işıkta pırıldayan sim.")
        case .grass: return Loc.t("Kısa 3B çim biter, küçük yazıda da okunur. 1–2 saniye sonra çiçekler açar.")
        case .sea: return Loc.t("Çizgi boyunca akan deniz: turkuaz sığlıklar, suyun altında kayan ışık ağları, iki kıyıda köpüren dalgalar.")
        case .lava: return Loc.t("Akan, parlayan lav. Birkaç saniyede soğur, çatlaklarında kor yanmaya devam eder.")
        case .fountain: return Loc.t("Kabarık, parlak dolma kalem mürekkebi. Bastırdıkça uç açılır, çizgi kalınlaşır.")
        case .gold: return Loc.t("Işığı yansıtan kabartma metal: altın, gümüş, bakır.")
        case .chrome: return Loc.t("Gökyüzünü yansıtan, ayna gibi sıvı metal.")
        case .ice: return Loc.t("Saydam, buğulu buz. İçinde çatlaklar ve pırıltılar var.")
        case .jelly: return Loc.t("Işık geçiren, hafifçe sallanan şeker jöle.")
        case .galaxy: return Loc.t("İçinde bulutsular süzülen, yıldızları göz kırpan uzay.")
        case .lightning: return Loc.t("Çıtırdayan, parlayan elektrik arkı.")
        case .pearl: return Loc.t("Çizgi boyunca dizilen sedef parıltılı inciler.")
        case .impasto: return Loc.t("Fırça izleri görünen kalın, kabarık yağlı boya.")
        }
    }

    var symbol: String {
        switch self {
        case .pen: return "pencil.tip"
        case .wet: return "drop.fill"
        case .wave: return "drop.circle.fill"
        case .highlighter: return "highlighter"
        case .pencil: return "pencil"
        case .calligraphy: return "paintbrush.pointed.fill"
        case .watercolor: return "paintbrush.fill"
        case .neon: return "lightbulb.fill"
        case .rainbow: return "rainbow"
        case .glitter: return "sparkles"
        case .grass: return "camera.macro"
        case .sea: return "water.waves"
        case .lava: return "flame.fill"
        case .fountain: return "pencil.and.outline"
        case .gold: return "crown.fill"
        case .chrome: return "circle.lefthalf.filled"
        case .ice: return "snowflake"
        case .jelly: return "drop.halffull"
        case .galaxy: return "moon.stars.fill"
        case .lightning: return "bolt.fill"
        case .pearl: return "circle.grid.2x1.fill"
        case .impasto: return "paintpalette.fill"
        }
    }

    /// Stroke width in page points.
    var defaultWidth: Float {
        switch self {
        case .pen: return 2.2
        case .wet: return 3.8
        case .wave: return 12
        case .highlighter: return 16
        case .pencil: return 2.6
        case .calligraphy: return 7
        case .watercolor: return 16
        case .neon: return 4
        case .rainbow: return 6
        case .glitter: return 6
        case .grass: return 10
        case .sea: return 8
        case .lava: return 7
        case .fountain: return 3.2
        case .gold: return 5
        case .chrome: return 6
        case .ice: return 7
        case .jelly: return 8
        case .galaxy: return 8
        case .lightning: return 4
        case .pearl: return 7
        case .impasto: return 12
        }
    }

    var widthRange: ClosedRange<Float> {
        switch self {
        case .pen: return 0.8...8
        case .wet: return 1.5...14
        case .wave: return 4...40
        case .highlighter: return 6...40
        case .pencil: return 1...12
        case .calligraphy: return 2...24
        case .watercolor: return 4...48
        case .neon: return 1.5...14
        case .rainbow: return 2...30
        case .glitter: return 2...24
        case .grass: return 3...40
        case .sea: return 2...36
        case .lava: return 2...36
        case .fountain: return 1...14
        case .gold: return 1.5...24
        case .chrome: return 2...30
        case .ice: return 2...32
        case .jelly: return 2...36
        case .galaxy: return 2...40
        case .lightning: return 1.5...16
        case .pearl: return 3...30
        case .impasto: return 3...48
        }
    }

    /// 0 = width ignores pressure, 1 = width follows pressure strongly.
    var pressureSensitivity: Float {
        switch self {
        case .pen: return 0.45
        case .wet: return 0.65
        case .wave: return 0.3
        case .highlighter: return 0
        case .pencil: return 0.35
        case .calligraphy: return 0.3
        case .watercolor: return 0.55
        case .neon: return 0.15
        case .rainbow: return 0.4
        case .glitter: return 0.35
        case .grass: return 0.3
        case .sea: return 0.3
        case .lava: return 0.4
        case .fountain: return 0.9
        case .gold: return 0.45
        case .chrome: return 0.35
        case .ice: return 0.35
        case .jelly: return 0.4
        case .galaxy: return 0.35
        case .lightning: return 0.2
        case .pearl: return 0.25
        case .impasto: return 0.5
        }
    }

    /// Drawn every frame while the animation setting is on.
    var isAnimated: Bool {
        switch self {
        case .wave, .glitter, .grass, .sea, .lava, .ice, .jelly, .galaxy, .lightning: return true
        default: return false
        }
    }

    /// Needs 60 fps (fast motion) rather than 30.
    var isFastAnimated: Bool { self == .wave || self == .sea || self == .lightning }
    /// Fresh strokes are wet and dry over a few seconds.
    var dries: Bool { self == .wet }
    /// Draws the multiply pass under the ink.
    var isHighlighter: Bool { self == .highlighter }
    /// Raised ink that casts a soft shadow.
    var castsShadow: Bool {
        switch self {
        case .pen, .pencil, .calligraphy, .highlighter, .watercolor, .neon, .rainbow, .lightning: return false
        default: return true
        }
    }
    /// Uses Apple Pencil tilt for shading.
    var usesTilt: Bool { self == .pencil || self == .watercolor }
    /// Parts of the ink are see-through (glass, gel, glow), so where the stroke folds over itself in a
    /// tight turn it gets a depth pass first and is blended only once.
    var blendsOnce: Bool {
        switch self {
        case .neon, .ice, .jelly, .lava, .lightning: return true
        default: return false
        }
    }
    /// Thick, shaded ink bends smoothly through sharp corners instead of creasing like a pipe joint.
    var relaxesCorners: Bool {
        switch self {
        case .pen, .pencil, .calligraphy, .highlighter, .watercolor: return false
        default: return true
        }
    }

    var palette: [InkColor] {
        func p(_ hexes: [UInt32]) -> [InkColor] { hexes.map { InkColor(hex: $0) } }
        switch self {
        case .pen: return p([0x1C1C1E, 0x1E4FD8, 0xD93025, 0x1E8E3E, 0x7B3FD0, 0xE8710A])
        case .wet: return p([0x122B94, 0x111318, 0x7A1530, 0x0B6E4F, 0x6B3E1F, 0x4B1C8C])
        case .wave: return p([0x0D61B8, 0x0A9396, 0x065A82, 0x1BA3C6, 0x5B3FD1, 0xE0566B])
        case .highlighter: return p([0xFFE74C, 0xA6F28A, 0xFFA3D1, 0x9CD8FF, 0xFFC26B, 0xD5B3FF])
        case .pencil: return p([0x2B2B2E, 0x5C5F66, 0x2F5DA8, 0xB3362F, 0x2E7D4F, 0x7A4A2A])
        case .calligraphy: return p([0x111111, 0x8C1C13, 0x1B3A6B, 0xA77B12, 0x2F4F2F, 0x5B2A86])
        case .watercolor: return p([0x3A7BD5, 0xE4572E, 0x29A36A, 0xF2B134, 0x8E44AD, 0xE76F99])
        case .neon: return p([0xFF2E88, 0x00D9FF, 0x39FF14, 0xFFE600, 0xB026FF, 0xFF6B00])
        case .rainbow: return p([0xF23030, 0xFFA8C5, 0x8C1A1A, 0xFF7A00, 0x9B5CFF, 0x22C1C3])
        case .glitter: return p([0xD4AF37, 0xB8BCC6, 0xE0115F, 0x1E90FF, 0x2FBF71, 0x9966CC])
        case .grass: return p([0x3F9B2F, 0x2E7D32, 0x7CB342, 0x8D9E2B, 0xC28E2B, 0x1B5E20])
        case .sea: return p([0x0B5FA5, 0x0A8F9E, 0x1C3F94, 0x2BB0D6, 0x2E8B57, 0x5B3FD1])
        case .lava: return p([0xFF5A1F, 0xFF2D2D, 0xFFB020, 0x7A3CFF, 0x23C7FF, 0x3DFF7A])
        case .fountain: return p([0x1F3FBF, 0x15161A, 0x7B1230, 0x0E6B4E, 0x6B4423, 0x4B2A9C])
        case .gold: return p([0xD4A537, 0xE0A090, 0xC9CED6, 0xC0703A, 0x9C7A3C, 0xE5E4E2])
        case .chrome: return p([0xC8D0DA, 0x3A3F47, 0x5A8BD6, 0xE58FB0, 0xE8C66A, 0x9FE3D9])
        case .ice: return p([0x9FE6FF, 0xE6FBFF, 0x7FD3D9, 0xB7B4FF, 0x9EF0C8, 0xFFB3D1])
        case .jelly: return p([0xFF3B6B, 0xFF9F1C, 0x42D96B, 0x3AA0FF, 0xB45CFF, 0xFFE14D])
        case .galaxy: return p([0x6A2CFF, 0x1E3CFF, 0xFF3CAC, 0x00C2C7, 0xFF7A3C, 0x9AA0B5])
        case .lightning: return p([0x7FD4FF, 0xC08BFF, 0xFFE45C, 0x6BFF9E, 0xFF6BD0, 0xFFFFFF])
        case .pearl: return p([0xF4EFE6, 0xF2D0D9, 0x2C2F3A, 0xE8D59E, 0xBFD7EA, 0xD8C8F0])
        case .impasto: return p([0xD7263D, 0x1B998B, 0xF46036, 0x2E294E, 0xF2C14E, 0x3D5A80])
        }
    }
}
