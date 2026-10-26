import SwiftUI

/// The break corner: a small tile at the bottom-left of the page opens a card of six calm games
/// (the ink mandala, the ink bubbles, XOX against the iPad, the flying drop, the colour popper,
/// Sudoku). Free in every edition; nothing leaves the iPad, and what is kept (levels, stars, best
/// scores, a half-done Sudoku) lives in UserDefaults under `GameProgress.Keys`. The games' logic is
/// in MiniGameLogic, FlyerLogic, ShooterLogic and SudokuLogic.
enum GameCorner {
    static let panelSize = GamePanelSize.compact
    static let radius: CGFloat = 24

    /// The panel springs in and out; with Reduce Motion on it fades.
    static func animation(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.38, dampingFraction: 0.82)
    }

    static func transition(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .scale(scale: 0.86, anchor: .bottomLeading).combined(with: .opacity)
    }

    /// The ink colours of the games' pieces: lacivert, turquoise, magenta, amber, green.
    static let inks: [Color] = [
        Color(hue: 0.63, saturation: 0.72, brightness: 0.86),
        Color(hue: 0.50, saturation: 0.70, brightness: 0.78),
        Color(hue: 0.88, saturation: 0.62, brightness: 0.84),
        Color(hue: 0.10, saturation: 0.78, brightness: 0.92),
        Color(hue: 0.36, saturation: 0.62, brightness: 0.70),
    ]

    static func ink(_ index: Int) -> Color { inks[max(0, index) % inks.count] }

    static func clock(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

extension GameDifficulty {
    var title: String {
        switch self {
        case .easy: return Loc.t("Kolay")
        case .medium: return Loc.t("Orta")
        case .hard: return Loc.t("Zor")
        }
    }
}

/// The six games of the break corner.
enum MiniGame: String, CaseIterable, Identifiable {
    case mandala, bubbles, xox, flyer, shooter, sudoku

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mandala: return Loc.t("Mürekkep mandalası")
        case .bubbles: return Loc.t("Mürekkep balonları")
        case .xox: return Loc.t("XOX")
        case .flyer: return Loc.t("Uçan damla")
        case .shooter: return Loc.t("Renk patlat")
        case .sudoku: return Loc.t("Sudoku")
        }
    }

    var hint: String {
        switch self {
        case .mandala: return Loc.t("Çiz; her çizgi sekiz kat açılır.")
        case .bubbles: return Loc.t("Yükselen balonlara dokun, patlat. 60 saniye.")
        case .xox: return Loc.t("iPad'e karşı; sen X'sin.")
        case .flyer: return Loc.t("Dokun, damla yükselsin; kalemlerin arasından geç.")
        case .shooter: return Loc.t("Nişan al, aynı renkten üçünü patlat.")
        case .sudoku: return Loc.t("Her satır, sütun ve kutuda 1–9.")
        }
    }

    var symbol: String {
        switch self {
        case .mandala: return "circle.hexagongrid"
        case .bubbles: return "drop.circle"
        case .xox: return "squareshape.split.3x3"
        case .flyer: return "paperplane"
        case .shooter: return "paintpalette"
        case .sudoku: return "number.square"
        }
    }

    /// How many levels a levelled game has; nil for the open-ended ones.
    var levels: Int? {
        switch self {
        case .flyer: return FlyerWorld.levels
        case .shooter: return ShooterLevels.count
        default: return nil
        }
    }
}

/// What the player keeps of every game, read from and written to UserDefaults.
final class GameProgressStore: ObservableObject {
    @Published private(set) var progress: [MiniGame: GameProgress] = [:]
    private let defaults = UserDefaults.standard

    init() {
        for game in MiniGame.allCases {
            progress[game] = load(game)
        }
    }

    subscript(game: MiniGame) -> GameProgress {
        progress[game] ?? GameProgress()
    }

    func setDifficulty(_ difficulty: GameDifficulty, for game: MiniGame) {
        var kept = self[game]
        guard kept.difficulty != difficulty else { return }
        kept.difficulty = difficulty
        progress[game] = kept
        defaults.set(difficulty.rawValue, forKey: GameProgress.Keys.difficulty(game.id))
    }

    /// A level played to its end.
    func complete(_ game: MiniGame, level: Int, stars: Int) {
        guard let levels = game.levels else { return }
        var kept = self[game]
        kept.complete(level: level, stars: stars, levels: levels)
        progress[game] = kept
        defaults.set(kept.unlockedLevel, forKey: GameProgress.Keys.unlocked(game.id))
        var starsByLevel: [String: Int] = [:]
        for (level, stars) in kept.stars { starsByLevel[String(level)] = stars }
        defaults.set(starsByLevel, forKey: GameProgress.Keys.stars(game.id))
    }

    /// A round played to its end; true when it is a record.
    @discardableResult
    func record(_ game: MiniGame, score: Int, at difficulty: GameDifficulty, lowerIsBetter: Bool = false) -> Bool {
        var kept = self[game]
        let best = kept.record(score: score, at: difficulty, lowerIsBetter: lowerIsBetter)
        progress[game] = kept
        if best { defaults.set(score, forKey: GameProgress.Keys.best(game.id, difficulty)) }
        return best
    }

    private func load(_ game: MiniGame) -> GameProgress {
        var kept = GameProgress()
        kept.unlockedLevel = max(1, defaults.integer(forKey: GameProgress.Keys.unlocked(game.id)))
        if let stars = defaults.dictionary(forKey: GameProgress.Keys.stars(game.id)) {
            for (key, value) in stars {
                if let level = Int(key), let count = value as? Int { kept.stars[level] = count }
            }
        }
        for difficulty in GameDifficulty.allCases {
            if let best = defaults.object(forKey: GameProgress.Keys.best(game.id, difficulty)) as? Int { kept.best[difficulty] = best }
        }
        if game == .bubbles, kept.best[.medium] == nil {
            let old = defaults.integer(forKey: GameProgress.Keys.legacyBubblesBest)
            if old > 0 { kept.best[.medium] = old }
        }
        if let raw = defaults.string(forKey: GameProgress.Keys.difficulty(game.id)), let difficulty = GameDifficulty(rawValue: raw) {
            kept.difficulty = difficulty
        }
        return kept
    }
}

/// The glass tile in the bottom-left corner, above the writing sound's switch, that opens and closes
/// the break panel: a rounded square with the game controller in ink, solid ink while the panel is open.
struct GameCornerButton: View {
    @Binding var isOpen: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)

    var body: some View {
        Button {
            withAnimation(GameCorner.animation(reduceMotion: reduceMotion)) { isOpen.toggle() }
        } label: {
            Image(systemName: "gamecontroller.fill")
                .font(.system(size: 16, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isOpen ? Color.white : Theme.ink)
                .frame(width: 38, height: 38)
                .background {
                    if isOpen {
                        Self.shape.fill(Theme.ink)
                    } else {
                        ZStack {
                            Self.shape.fill(Material.ultraThinMaterial)
                            Self.shape.fill(LinearGradient(colors: [Theme.ink.opacity(0.2), Theme.ink.opacity(0.04)],
                                                           startPoint: .topLeading, endPoint: .bottomTrailing))
                        }
                    }
                }
                .overlay(Self.shape.strokeBorder(Theme.hairline, lineWidth: 0.6))
                .shadow(color: Theme.shadow.opacity(isOpen ? 0.18 : 0.08), radius: 6, y: 3)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isOpen ? Loc.t("Molayı kapat") : Loc.t("Mola: küçük oyunlar"))
    }
}

/// The break card: a header, the six games to pick from, the game itself. Every touch inside the
/// card stays in it, so no stroke reaches the page beneath; the pencil draws here like a finger.
/// One step larger on request, never more than a quarter of the canvas.
struct GameCornerPanel: View {
    let size: CGSize
    @Binding var expanded: Bool
    let onClose: () -> Void
    @StateObject private var store = GameProgressStore()
    @State private var game: MiniGame?
    /// Counts the restarts; each one builds the game afresh.
    @State private var round = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 10)
                .frame(height: 48)
            Divider()
            Group {
                if let game {
                    gameView(game)
                        .id("\(game.id)-\(round)")
                } else {
                    picker
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: size.width, height: size.height)
        .glassCard(radius: GameCorner.radius)
        .contentShape(RoundedRectangle(cornerRadius: GameCorner.radius, style: .continuous))
        // The card keeps every touch to itself: nothing reaches the page beneath it.
        .onTapGesture {}
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: game)
    }

    private var header: some View {
        HStack(spacing: 6) {
            if game != nil {
                headerButton("chevron.left", label: Loc.t("Oyunlara dön")) {
                    game = nil
                }
            } else {
                Image(systemName: "cup.and.saucer")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 32, height: 32)
            }
            Text(game?.title ?? Loc.t("Mola"))
                .font(Theme.display(.headline))
                .lineLimit(1)
            Spacer(minLength: 4)
            if game != nil {
                headerButton("arrow.counterclockwise", label: Loc.t("Yeniden başlat")) {
                    round += 1
                }
            }
            headerButton(expanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                         label: expanded ? Loc.t("Küçült") : Loc.t("Büyüt")) {
                withAnimation(GameCorner.animation(reduceMotion: reduceMotion)) { expanded.toggle() }
            }
            headerButton("xmark", label: Loc.t("Kapat"), action: onClose)
        }
    }

    private func headerButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.primary)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.primary.opacity(0.06)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var picker: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 10) {
                Text(Loc.t("Kısa bir mola. Kalemle de parmakla da oynanır."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(MiniGame.allCases) { item in
                        gameTile(item)
                    }
                }
            }
        }
    }

    private func gameTile(_ item: MiniGame) -> some View {
        let kept = store[item]
        return Button {
            game = item
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: item.symbol)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 38, height: 38)
                    .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Theme.ink.opacity(0.1)))
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if item.levels != nil {
                    HStack(spacing: 3) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9))
                        Text("\(kept.totalStars)")
                            .monospacedDigit()
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                } else {
                    Text(item == .mandala ? Loc.t("Puan yok, sadece akış.") : kept.difficulty.title)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.primary.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 0.6))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
        .accessibilityHint(item.hint)
    }

    @ViewBuilder
    private func gameView(_ game: MiniGame) -> some View {
        switch game {
        case .mandala: InkMandalaGame()
        case .bubbles: InkBubblesGame(store: store)
        case .xox: XOXGame(store: store)
        case .flyer: FlyerGame(store: store)
        case .shooter: ShooterGame(store: store)
        case .sudoku: SudokuGame(store: store)
        }
    }
}

// MARK: - Shared pieces of the games

/// Kolay / Orta / Zor.
struct DifficultyPicker: View {
    @Binding var difficulty: GameDifficulty

    var body: some View {
        Picker(Loc.t("Zorluk"), selection: $difficulty) {
            ForEach(GameDifficulty.allCases) { level in
                Text(level.title).tag(level)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel(Loc.t("Zorluk"))
    }
}

/// Three stars, `stars` of them filled in ink.
struct StarRow: View {
    let stars: Int
    var size: CGFloat = 12

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { i in
                Image(systemName: i < stars ? "star.fill" : "star")
                    .font(.system(size: size))
                    .foregroundStyle(i < stars ? Theme.ink : Color.secondary.opacity(0.4))
            }
        }
        .accessibilityLabel(Loc.t("{0} yıldız", "\(stars)"))
    }
}

/// The level map of a levelled game: the difficulty, then the levels as tiles; locked ones wait.
struct LevelMap: View {
    let game: MiniGame
    @ObservedObject var store: GameProgressStore
    let onStart: (Int) -> Void

    var body: some View {
        let kept = store[game]
        VStack(spacing: 10) {
            DifficultyPicker(difficulty: Binding(get: { store[game].difficulty }, set: { store.setDifficulty($0, for: game) }))
            HStack {
                Text(Loc.t("Toplam {0} yıldız", "\(kept.totalStars)"))
                Spacer()
                Text(Loc.t("Seviye {0} açık", "\(kept.unlockedLevel)"))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    ForEach(1...(game.levels ?? 1), id: \.self) { level in
                        levelTile(level, kept)
                    }
                }
            }
        }
    }

    private func levelTile(_ level: Int, _ kept: GameProgress) -> some View {
        let open = kept.isUnlocked(level)
        return Button {
            onStart(level)
        } label: {
            VStack(spacing: 4) {
                if open {
                    Text("\(level)")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(Color.primary)
                } else {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                StarRow(stars: kept.stars(at: level), size: 8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(open ? Theme.ink.opacity(0.1) : Color.primary.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 0.6))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!open)
        .accessibilityLabel(open ? Loc.t("Seviye {0}", "\(level)") : Loc.t("Seviye {0}, kilitli", "\(level)"))
    }
}

/// The end of a level: stars, a line of detail, and what to do next.
struct LevelResultCard: View {
    let won: Bool
    let stars: Int
    let detail: String
    let hasNext: Bool
    let onLevels: () -> Void
    let onRetry: () -> Void
    let onNext: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 10) {
            Text(won ? Loc.t("Seviye tamam!") : Loc.t("Bu sefer olmadı."))
                .font(Theme.display(.title3))
            if won {
                StarRow(stars: stars, size: 18)
            }
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button(Loc.t("Seviyeler"), action: onLevels)
                    .buttonStyle(.bordered)
                Button(Loc.t("Tekrar"), action: onRetry)
                    .buttonStyle(.bordered)
                if won && hasNext {
                    Button(Loc.t("Sonraki"), action: onNext)
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.ink)
                }
            }
            .font(.subheadline.weight(.semibold))
        }
        .padding(16)
        .glassCard(radius: 18)
        .transition(reduceMotion ? .opacity : .scale(scale: 0.9).combined(with: .opacity))
    }
}
