import SwiftUI

/// The break corner: a small tile at the bottom-left of the page opens a card with two layers:
/// games to play (the ink bubbles, XOX and kare kapmaca against the iPad, the flying drop, the colour
/// popper, Sudoku)
/// and things to make (ebru, living ink, the ink mandala). Free in every edition; nothing leaves the
/// iPad, and what is kept (levels, stars, best scores, a half-done Sudoku, the layer last open) lives
/// in UserDefaults under `GameProgress.Keys`. The logic is in MiniGameLogic, FlyerLogic,
/// ShooterLogic, SudokuLogic, EbruLogic and LivingInkLogic.
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

    /// How the panel's pages change: the next slides in from the right as the old fades; a fade
    /// alone with Reduce Motion.
    static func pageTransition(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity)
    }

    /// The inks of the games' pieces: lacivert, turquoise, magenta, amber, green.
    static let inkHues: [(hue: Double, saturation: Double, brightness: Double)] = [
        (0.63, 0.72, 0.86), (0.50, 0.70, 0.78), (0.88, 0.62, 0.84), (0.10, 0.78, 0.92), (0.36, 0.62, 0.70),
    ]

    static func ink(_ index: Int) -> Color { shade(index, light: 0) }

    /// A lighter (`light` > 0) or darker (`light` < 0) shade of an ink, for gloss and rims; 1 and −1 are the ends.
    static func shade(_ index: Int, light: Double) -> Color {
        let ink = inkHues[max(0, index) % inkHues.count]
        let saturation = max(0, min(1, ink.saturation - max(0, light) * 0.55))
        let brightness = max(0, min(1, ink.brightness + light * 0.3))
        return Color(hue: ink.hue, saturation: saturation, brightness: brightness)
    }

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

/// The two layers of the break card: games to play, and things to make.
enum BreakLayer: String, CaseIterable, Identifiable {
    case games, creative

    var id: String { rawValue }

    var title: String {
        switch self {
        case .games: return Loc.t("Oyunlar")
        case .creative: return Loc.t("Yaratıcılık")
        }
    }
}

/// The games and the makings of the break corner, in the order their tiles stand.
enum MiniGame: String, CaseIterable, Identifiable {
    case ebru, creatures, mandala, bubbles, xox, dots, flyer, shooter, sudoku

    var id: String { rawValue }

    var layer: BreakLayer {
        switch self {
        case .ebru, .creatures, .mandala: return .creative
        case .bubbles, .xox, .dots, .flyer, .shooter, .sudoku: return .games
        }
    }

    var title: String {
        switch self {
        case .ebru: return Loc.t("Ebru")
        case .creatures: return Loc.t("Canlı mürekkep")
        case .mandala: return Loc.t("Mürekkep mandalası")
        case .bubbles: return Loc.t("Mürekkep balonları")
        case .xox: return Loc.t("XOX")
        case .dots: return Loc.t("Kare kapmaca")
        case .flyer: return Loc.t("Uçan damla")
        case .shooter: return Loc.t("Renk patlat")
        case .sudoku: return Loc.t("Sudoku")
        }
    }

    var hint: String {
        switch self {
        case .ebru: return Loc.t("Suya boya damlat; bizle, tarakla desen çek.")
        case .creatures: return Loc.t("Çiz; kalemi kaldırınca canlanıp yüzer.")
        case .mandala: return Loc.t("Çiz; her çizgi sekiz kat açılır.")
        case .bubbles: return Loc.t("Balonları patlat, lekelere dokunma. 60 saniye.")
        case .xox: return Loc.t("iPad'e karşı; sen X'sin.")
        case .dots: return Loc.t("Noktaları birleştir; kareyi kapatan alır, bir daha oynar.")
        case .flyer: return Loc.t("Dokun, damla yükselsin; kalemlerin arasından geç.")
        case .shooter: return Loc.t("Nişan al, aynı renkten üçünü patlat.")
        case .sudoku: return Loc.t("Her satır, sütun ve kutuda 1–9.")
        }
    }

    var symbol: String {
        switch self {
        case .ebru: return "paintbrush.pointed"
        case .creatures: return "fish"
        case .mandala: return "circle.hexagongrid"
        case .bubbles: return "drop.circle"
        case .xox: return "squareshape.split.3x3"
        case .dots: return "circle.grid.3x3"
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

    var hasDifficulty: Bool { layer == .games }
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

    /// One line about a game for its tile: its stars and open level, its best, its wins, its time.
    func summary(of game: MiniGame) -> String {
        let kept = self[game]
        switch game {
        case .ebru:
            return Loc.t("Battal, gelgit, bülbül yuvası.")
        case .creatures:
            return Loc.t("Çizdiğin canlanır.")
        case .mandala:
            return Loc.t("Puan yok, sadece akış.")
        case .flyer, .shooter:
            return Loc.t("{0} yıldız", "\(kept.totalStars)") + " · " + Loc.t("Seviye {0}", "\(kept.unlockedLevel)")
        case .bubbles:
            return Loc.t("En iyi: {0}", "\(kept.best[kept.difficulty] ?? 0)") + " · " + kept.difficulty.title
        case .xox, .dots:
            return Loc.t("Galibiyet: {0}", "\(kept.best[kept.difficulty] ?? 0)") + " · " + kept.difficulty.title
        case .sudoku:
            if let best = kept.best[kept.difficulty] {
                return Loc.t("En iyi süre: {0}", GameCorner.clock(best)) + " · " + kept.difficulty.title
            }
            return kept.difficulty.title
        }
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

/// The break card: a header, the two layers with their tiles to pick from, the game itself. Every
/// touch inside the card stays in it, so no stroke reaches the page beneath; the pencil draws here
/// like a finger. One step larger on request, never more than a quarter of the canvas.
struct GameCornerPanel: View {
    let size: CGSize
    @Binding var expanded: Bool
    let onClose: () -> Void
    @StateObject private var store = GameProgressStore()
    @State private var game: MiniGame?
    /// The layer last open; games the first time, as the corner's tile is a game controller.
    @AppStorage(GameProgress.Keys.layer) private var layer: BreakLayer = .games
    /// Counts the restarts; each one builds the game afresh.
    @State private var round = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 12)
                .frame(height: 56)
            Divider()
                .overlay(Theme.hairline)
            ZStack {
                if let game {
                    gameView(game)
                        .id("\(game.id)-\(round)")
                        .transition(GameCorner.pageTransition(reduceMotion: reduceMotion))
                } else {
                    picker
                        .transition(GameCorner.pageTransition(reduceMotion: reduceMotion))
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
        .frame(width: size.width, height: size.height)
        .glassCard(radius: GameCorner.radius, floating: true)
        .contentShape(RoundedRectangle(cornerRadius: GameCorner.radius, style: .continuous))
        // The card keeps every touch to itself: nothing reaches the page beneath it.
        .onTapGesture {}
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: game)
        #if DEMO
        // The ad recordings (tools/demo) pick the layer and the game.
        .onReceive(NotificationCenter.default.publisher(for: DemoStage.pickLayer)) { note in
            if let raw = note.object as? String, let picked = BreakLayer(rawValue: raw) { layer = picked }
        }
        .onReceive(NotificationCenter.default.publisher(for: DemoStage.pickGame)) { note in
            if let raw = note.object as? String, let picked = MiniGame(rawValue: raw) {
                layer = picked.layer
                game = picked
            } else {
                game = nil
            }
        }
        #endif
    }

    private var subtitle: String {
        guard let game else { return Loc.t("Kısa bir mola; kalemle de parmakla da.") }
        return game.hasDifficulty ? store.summary(of: game) : game.hint
    }

    private var header: some View {
        HStack(spacing: 8) {
            if game != nil {
                headerButton("chevron.left", label: Loc.t("Oyunlara dön")) {
                    game = nil
                }
            } else {
                Image(systemName: "cup.and.saucer.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Theme.ink)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Theme.ink.opacity(0.1)))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(game?.title ?? Loc.t("Mola"))
                    .font(Theme.display(.title3))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
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
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.primary.opacity(0.8))
                .frame(width: 30, height: 30)
                .background(Circle().fill(Material.ultraThinMaterial))
                .overlay(Circle().strokeBorder(Theme.hairline, lineWidth: 0.6))
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
    }

    private var picker: some View {
        VStack(spacing: 10) {
            Picker(Loc.t("Katman"), selection: $layer) {
                ForEach(BreakLayer.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel(Loc.t("Katman"))
            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(MiniGame.allCases.filter { $0.layer == layer }) { item in
                        gameTile(item)
                    }
                }
                .padding(.vertical, 2)
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: layer)
        }
    }

    private func gameTile(_ item: MiniGame) -> some View {
        Button {
            game = item
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: item.symbol)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 40, height: 40)
                    .background(Theme.ink.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(store.summary(of: item))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(radius: 16)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(item.title)
        .accessibilityHint(item.hint)
    }

    @ViewBuilder
    private func gameView(_ game: MiniGame) -> some View {
        switch game {
        case .ebru: EbruGame()
        case .creatures: LivingInkGame()
        case .mandala: InkMandalaGame()
        case .bubbles: InkBubblesGame(store: store)
        case .xox: XOXGame(store: store)
        case .dots: DotsGame(store: store)
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

/// The frame every game's field stands in: paper, a hairline, continuous corners.
struct GameBoardFrame: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Theme.paper, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 0.6))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

extension View {
    func gameBoard() -> some View {
        modifier(GameBoardFrame())
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

/// A thing to do at the end of a round or a level.
struct ResultAction: Identifiable {
    let title: String
    var prominent = false
    let action: () -> Void

    var id: String { title }

    init(_ title: String, prominent: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.prominent = prominent
        self.action = action
    }
}

/// The card at the end of a round or a level: a serif title, the stars, a line or two, the buttons.
struct ResultCard: View {
    let title: String
    var stars: Int?
    var lines: [String] = []
    var highlight: String?
    let actions: [ResultAction]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 10) {
            Text(title)
                .font(Theme.display(.title3))
                .multilineTextAlignment(.center)
            if let stars {
                StarRow(stars: stars, size: 20)
            }
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if let highlight {
                Text(highlight)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
            }
            HStack(spacing: 8) {
                ForEach(actions) { item in
                    if item.prominent {
                        Button(item.title, action: item.action)
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.ink)
                    } else {
                        Button(item.title, action: item.action)
                            .buttonStyle(.bordered)
                    }
                }
            }
            .font(.subheadline.weight(.semibold))
            .padding(.top, 2)
        }
        .padding(18)
        .frame(maxWidth: 290)
        .glassCard(radius: 20)
        .transition(reduceMotion ? .opacity : .scale(scale: 0.92).combined(with: .opacity))
    }
}

/// The level map of a levelled game: the difficulty, then the levels as tiles; locked ones wait,
/// the next one to play is ringed in ink.
struct LevelMap: View {
    let game: MiniGame
    @ObservedObject var store: GameProgressStore
    let onStart: (Int) -> Void

    var body: some View {
        let kept = store[game]
        VStack(spacing: 10) {
            DifficultyPicker(difficulty: Binding(get: { store[game].difficulty }, set: { store.setDifficulty($0, for: game) }))
            HStack {
                Label(Loc.t("Toplam {0} yıldız", "\(kept.totalStars)"), systemImage: "star.fill")
                Spacer()
                Text(Loc.t("Seviye {0} açık", "\(kept.unlockedLevel)"))
            }
            .font(.caption)
            .foregroundStyle(Theme.muted)
            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    ForEach(1...(game.levels ?? 1), id: \.self) { level in
                        levelTile(level, kept)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func levelTile(_ level: Int, _ kept: GameProgress) -> some View {
        let open = kept.isUnlocked(level)
        let next = level == kept.unlockedLevel
        return Button {
            onStart(level)
        } label: {
            VStack(spacing: 4) {
                if open {
                    Text("\(level)")
                        .font(.system(.headline, design: .rounded).monospacedDigit())
                        .foregroundStyle(next ? Theme.ink : Color.primary)
                } else {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                StarRow(stars: kept.stars(at: level), size: 8)
                    .opacity(open ? 1 : 0.35)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(open ? Theme.ink.opacity(0.08) : Color.primary.opacity(0.035)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(next ? Theme.ink.opacity(0.7) : Theme.hairline, lineWidth: next ? 1.4 : 0.6))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(PressableStyle())
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

    var body: some View {
        var actions = [ResultAction(Loc.t("Seviyeler"), action: onLevels),
                       ResultAction(Loc.t("Tekrar"), prominent: !(won && hasNext), action: onRetry)]
        if won && hasNext {
            actions.append(ResultAction(Loc.t("Sonraki"), prominent: true, action: onNext))
        }
        return ResultCard(title: won ? Loc.t("Seviye tamam!") : Loc.t("Bu sefer olmadı."), stars: won ? stars : nil, lines: [detail], actions: actions)
    }
}
