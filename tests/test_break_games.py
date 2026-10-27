"""The break corner: a glass tile at the bottom-left of the page opens a compact card with two layers,
games to play (the ink bubbles, XOX against the iPad, the flying drop, the colour popper, Sudoku)
and things to make (ebru on water, the ink mandala), held in the source.

The tile stands above the writing sound's switch and goes away while a lecture is recorded; the
panel opens above that column, keeps its touches off the page, springs in and out (fades with Reduce
Motion), stands clear of the drafting rail and the pen bar, and grows one step at most (never more
than a quarter of the canvas). The games' logic is Foundation only and checked by tools/gamescheck;
what is kept (levels, stars, best scores, the chosen difficulty, a half-done Sudoku) lives in
UserDefaults under GameProgress.Keys."""
import re
from pathlib import Path

APP = Path(__file__).resolve().parent.parent / "Murekkep.swiftpm"
TOOLS = Path(__file__).resolve().parent.parent / "tools" / "gamescheck"
VIEWS = ("GameCorner.swift", "MandalaGame.swift", "BubblesGame.swift", "XOXGame.swift", "FlyerGame.swift", "ShooterGame.swift", "SudokuGame.swift",
         "EbruGame.swift", "LivingInkGame.swift")
LOGIC = ("MiniGameLogic.swift", "FlyerLogic.swift", "ShooterLogic.swift", "SudokuLogic.swift", "EbruLogic.swift", "LivingInkLogic.swift")


def src(name):
    return (APP / name).read_text(encoding="utf-8")


def test_the_tile_stands_above_the_sound_switch_in_the_corner():
    editor = src("EditorView.swift")
    column = editor[editor.index("VStack(alignment: .leading, spacing: 2) {"):][:500]
    # The game tile first (above), the sound switch last (it keeps the corner), in one column.
    assert column.index("GameCornerButton(isOpen: $showGames)") < column.index("PaperSoundCornerButton(settings: settings)")
    assert "HStack" not in column.split("PaperSoundCornerButton")[0]
    # Away while a lecture is recorded, and the panel closes when a recording starts.
    assert "if !lecture.isRecording {" in column
    assert re.search(r"onChange\(of: lecture\.isRecording\) \{ _, recording in\s*if recording \{ closeGames\(\) \}", editor)
    assert "@State private var showGames = false" in editor


def test_the_panel_opens_above_the_column_clear_of_the_rail_and_the_pen_bar_and_stays_small():
    editor = src("EditorView.swift")
    panel = editor[editor.index("if showGames {"):][:700]
    assert "GameCornerPanel(size: gamePanelSize, expanded: $gamesExpanded) { closeGames() }" in panel
    assert ".padding(.leading, gamePanelLeading)" in panel
    assert ".padding(.bottom, gamePanelBottom)" in panel
    assert "alignment: .bottomLeading" in panel
    assert ".transition(GameCorner.transition(reduceMotion: reduceMotion))" in panel
    # Past the drafting rail (12…62 pt) while it shows; above the 44 + 2 + 44 pt column; never off a narrow canvas.
    assert "paletteCollapsed ? 12 : 72" in editor
    assert "var gamePanelBottom: CGFloat { 104 + bottomClearance }" in editor
    assert "canvasSize.width - gamePanelSize.width - 12" in editor
    # One larger step at most, through the checked rule: at most 400×500 and a quarter of the canvas; no sheet, no cover.
    assert "guard gamesExpanded else { return GameCorner.panelSize }" in editor
    assert "GamePanelSize.larger(in: canvasSize" in editor
    logic = src("MiniGameLogic.swift")
    assert "static let compact = CGSize(width: 340, height: 420)" in logic
    assert "static let larger = CGSize(width: 400, height: 500)" in logic
    assert "let quarter = Double(canvas.width) * Double(canvas.height) / 4" in logic
    corner = src("GameCorner.swift")
    assert "static let panelSize = GamePanelSize.compact" in corner
    for forbidden in ("fullScreenCover", ".sheet(", "presentationDetents"):
        assert forbidden not in corner
    assert "@Environment(\\.accessibilityReduceMotion) private var reduceMotion" in editor


def test_the_tile_and_the_panel():
    corner = src("GameCorner.swift")
    # A 38 pt rounded glass tile with a filled, hierarchical 16 pt glyph; solid ink with a white glyph while open; hit area 44.
    assert 'Image(systemName: "gamecontroller.fill")' in corner
    assert ".font(.system(size: 16, weight: .semibold))" in corner
    assert ".symbolRenderingMode(.hierarchical)" in corner
    assert ".frame(width: 38, height: 38)" in corner and ".frame(width: 44, height: 44)" in corner
    assert "RoundedRectangle(cornerRadius: 11, style: .continuous)" in corner
    assert "Self.shape.fill(Theme.ink)" in corner and ".foregroundStyle(isOpen ? Color.white : Theme.ink)" in corner
    assert "LinearGradient(colors: [Theme.ink.opacity(0.2), Theme.ink.opacity(0.04)]" in corner
    assert "Self.shape.strokeBorder(Theme.hairline, lineWidth: 0.6)" in corner
    assert 'accessibilityLabel(isOpen ? Loc.t("Molayı kapat") : Loc.t("Mola: küçük oyunlar"))' in corner
    # Spring in and out, a fade with Reduce Motion.
    assert "reduceMotion ? .easeInOut(duration: 0.15) : .spring(" in corner
    assert "reduceMotion ? .opacity : .scale(scale: 0.86, anchor: .bottomLeading)" in corner
    # The card keeps every touch to itself: nothing reaches the ink canvas beneath.
    assert re.search(r"\.glassCard\(radius: GameCorner\.radius\)\s*\.contentShape\(RoundedRectangle[^\n]*\n[^\n]*\n\s*\.onTapGesture \{\}", corner)
    # Header: title, close, back, restart, the one larger step.
    assert 'Loc.t("Mola")' in corner and 'Loc.t("Kapat")' in corner
    assert 'headerButton("chevron.left", label: Loc.t("Oyunlara dön"))' in corner
    assert 'headerButton("arrow.counterclockwise", label: Loc.t("Yeniden başlat"))' in corner
    assert 'label: expanded ? Loc.t("Küçült") : Loc.t("Büyüt")' in corner
    # The tiles of the layer on show, with icons and names, in a grid.
    assert "ForEach(MiniGame.allCases.filter { $0.layer == layer })" in corner and "Image(systemName: item.symbol)" in corner and "Text(item.title)" in corner
    assert "case ebru, creatures, mandala, bubbles, xox, flyer, shooter, sudoku" in corner
    for line in ("case .ebru: EbruGame()", "case .creatures: LivingInkGame()", "case .mandala: InkMandalaGame()", "case .bubbles: InkBubblesGame(store: store)", "case .xox: XOXGame(store: store)",
                 "case .flyer: FlyerGame(store: store)", "case .shooter: ShooterGame(store: store)", "case .sudoku: SudokuGame(store: store)"):
        assert line in corner, line
    # Not Pro-gated, no network, no assets.
    for name in VIEWS + LOGIC:
        text = src(name)
        for forbidden in ("ProPlan", "URLSession", "import Network", "Image(\"", "Bundle.main.url"):
            assert forbidden not in text, (name, forbidden)


def test_the_games_draw_with_the_pencil_keep_their_touches_and_pause():
    mandala = src("MandalaGame.swift")
    assert "MandalaSymmetry.copies(of:" in mandala and "layer.addFilter(.blur(radius: 5))" in mandala and 'Button(Loc.t("Temizle"))' in mandala
    bubbles = src("BubblesGame.swift")
    assert "TimelineView(.animation(paused: paused))" in bubbles and "model.isOver || scenePhase != .active" in bubbles
    assert ".onChanged { value in model.pop(at: value.location) }" in bubbles and "if stopped { model.pause() }" in bubbles
    xox = src("XOXGame.swift")
    assert "game.move(for: Self.device, difficulty: difficulty, rng: &random)" in xox and "value.startLocation" in xox
    assert ".task(id: pendingReply)" in xox and ".trim(from: 0, to:" in xox
    flyer = src("FlyerGame.swift")
    assert "TimelineView(.animation(paused: paused))" in flyer and "scenePhase != .active || over" in flyer
    assert "model.flap()" in flyer and "DragGesture(minimumDistance: 0, coordinateSpace: .local)" in flyer
    assert "context.scaleBy(x: scale, y: scale)" in flyer  # the world is drawn scaled to the field
    shooter = src("ShooterGame.swift")
    assert "TimelineView(.animation(paused: paused))" in shooter and "scenePhase != .active || !model.animating" in shooter
    # A drag aims and its end shoots, unless it began on the well beside the pen: a tap there swaps the colours.
    assert "if !model.inWell(value.startLocation) { model.updateAim(to: value.location) }" in shooter
    assert re.search(r"if model\.inWell\(value\.startLocation\) \{\s*if model\.inWell\(value\.location\) \{ model\.swapLoaded\(\) \}\s*\} else \{\s*model\.fire\(at: value\.location, now: Date\(\)\)", shooter)
    assert '.accessibilityAction(named: Text(Loc.t("Rengi değiştir"))) { model.swapLoaded() }' in shooter
    assert "if let guide = model.guide()" in shooter  # the dotted line
    sudoku = src("SudokuGame.swift")
    assert "TimelineView(.periodic(from: .now, by: 1))" in sudoku and "if scenePhase == .active { model.tick() }" in sudoku
    assert "Task.detached(priority: .userInitiated)" in sudoku and "Sudoku.generate(difficulty: difficulty, seed: seed)" in sudoku
    assert "ForEach(1...9, id: \\.self)" in sudoku and 'Loc.t("Notlar")' in sudoku and 'Loc.t("Sil")' in sudoku
    assert "conflicts.contains(i) { tint = Color.red.opacity(0.16) }" in sudoku
    ebru = src("EbruGame.swift")
    assert "TimelineView(.animation(paused: paused))" in ebru and "scenePhase != .active || !model.isMoving" in ebru
    assert "model.advance(to: now)" in ebru and "if stopped { model.pause() }" in ebru
    # A touch that starts somewhere else is a new one, even after a touch cancelled without ending.
    assert "if touchStart == value.startLocation {" in ebru and "model.trayPoint(value.location, in: geo.size)" in ebru
    living = src("LivingInkGame.swift")
    assert "TimelineView(.animation(paused: paused))" in living and "scenePhase != .active || !model.isMoving" in living
    assert "if touchStart == value.startLocation {" in living and "model.pondPoint(value.location, in: geo.size)" in living
    # The drawing wakes once the pencil has stayed off the pond: every stroke begun or ended restarts the wait.
    assert ".task(id: model.strokes)" in living and "UInt64(InkPond.wakeDelay * 1_000_000_000)" in living
    assert re.search(r"guard !Task\.isCancelled else \{ return \}\s*model\.wake\(\)", living)
    assert "guard !isDrawing, !drawing.isEmpty else { return }" in living
    for name in VIEWS:
        text = src(name)
        assert "DragGesture(minimumDistance: 0" in text or name == "GameCorner.swift", name
        assert "contentShape(" in text, name


def test_difficulty_levels_and_progression():
    corner = src("GameCorner.swift")
    assert "struct DifficultyPicker: View" in corner and ".pickerStyle(.segmented)" in corner
    assert "struct LevelMap: View" in corner and "struct LevelResultCard: View" in corner and "struct StarRow: View" in corner
    assert 'Loc.t("Seviye {0}, kilitli"' in corner and 'Loc.t("Sonraki")' in corner and 'Loc.t("Seviyeler")' in corner
    assert "final class GameProgressStore: ObservableObject" in corner
    for name in ("BubblesGame.swift", "XOXGame.swift", "SudokuGame.swift"):
        assert "DifficultyPicker(difficulty: Binding(get: { store[" in src(name), name
    for name in ("FlyerGame.swift", "ShooterGame.swift"):
        text = src(name)
        assert "LevelMap(game: ." in text and "LevelResultCard(" in text, name
    # The store writes under the checked keys; the bubbles' old best is read once.
    assert "GameProgress.Keys.unlocked(game.id)" in corner and "GameProgress.Keys.stars(game.id)" in corner
    assert "GameProgress.Keys.best(game.id, difficulty)" in corner and "GameProgress.Keys.difficulty(game.id)" in corner
    assert "GameProgress.Keys.legacyBubblesBest" in corner
    assert 'GameProgress.Keys.saved("sudoku")' in src("SudokuGame.swift")
    logic = src("MiniGameLogic.swift")
    assert '"break.\\(game).unlocked"' in logic and '"break.\\(game).stars"' in logic
    assert '"break.\\(game).best.\\(difficulty.rawValue)"' in logic and '"break.\\(game).difficulty"' in logic and '"break.\\(game).saved"' in logic
    assert 'static let legacyBubblesBest = "breakBubblesBest"' in logic
    # The games record: bubbles a score per difficulty, XOX its wins, Sudoku its shortest time, the levelled ones their stars.
    assert "store.record(.bubbles, score: model.score, at: difficulty)" in src("BubblesGame.swift")
    assert "store.record(.xox, score: wins + 1, at: difficulty)" in src("XOXGame.swift")
    assert "store.record(.sudoku, score: kept.elapsed, at: kept.difficulty, lowerIsBetter: true)" in src("SudokuGame.swift")
    assert "store.complete(.flyer, level: level, stars:" in src("FlyerGame.swift")
    assert "store.complete(.shooter, level: level, stars:" in src("ShooterGame.swift")
    # Difficulty in the logic: bubbles' pace, XOX's three minds, the flyer's settings, the shooter's colours and shots, Sudoku's clues.
    assert "static func pace(_ difficulty: GameDifficulty) -> Double" in logic
    assert "func move<R: RandomNumberGenerator>(for mark: Mark, difficulty: GameDifficulty, rng: inout R) -> Int?" in logic
    assert "func perfectMoves(for mark: Mark) -> [Int]" in logic
    assert "static func settings(difficulty: GameDifficulty, level: Int) -> FlyerSettings" in src("FlyerLogic.swift")
    shooter = src("ShooterLogic.swift")
    assert "static func colours(_ difficulty: GameDifficulty) -> Int" in shooter and "static func shots(_ base: Int, _ difficulty: GameDifficulty) -> Int" in shooter
    assert len(re.findall(r"ShooterLevel\(rows: \[", shooter)) >= 12
    assert "static func clues(_ difficulty: GameDifficulty) -> Int" in src("SudokuLogic.swift")


def test_the_quality_pass():
    # The flyer flaps on Space and ↑ from a connected keyboard, through a controller that is first
    # responder only while the level is on screen (UIKeyCommand, iOS 7+; wantsPriorityOverSystemBehavior, iOS 15+).
    flyer = src("FlyerGame.swift")
    assert "final class FlapKeyController: UIViewController" in flyer
    assert 'UIKeyCommand(input: " ", modifierFlags: [], action: #selector(flap))' in flyer
    assert "UIKeyCommand(input: UIKeyCommand.inputUpArrow, modifierFlags: [], action: #selector(flap))" in flyer
    assert "command.wantsPriorityOverSystemBehavior = true" in flyer
    assert "override var canBecomeFirstResponder: Bool { true }" in flyer
    assert re.search(r"viewDidAppear[^\n]*\n[^\n]*\n\s*_ = becomeFirstResponder\(\)", flyer)
    assert re.search(r"viewWillDisappear[^\n]*\n\s*_ = resignFirstResponder\(\)", flyer)
    assert ".background(FlapKeys { model.flap() }.frame(width: 0, height: 0))" in flyer
    assert 'Loc.t("Dokun ya da boşluk tuşu: damla yükselsin")' in flyer
    # The bubbles are a challenge now: blots, a row multiplier, shrinking and quickening bubbles, three tunings.
    logic = src("MiniGameLogic.swift")
    assert "enum PopResult: Equatable" in logic and "case blot(points: Int, seconds: Int)" in logic
    assert "static let comboWindow: TimeInterval = 0.9" in logic and "static let maxCombo = 4" in logic
    assert "static let blotPoints = 5" in logic and "static let blotSeconds = 3" in logic
    assert "var radiusRange: ClosedRange<Double>" in logic and "struct Tuning: Equatable" in logic
    bubbles = src("BubblesGame.swift")
    assert "case .blot(let points, let seconds):" in bubbles and 'Loc.t("Lekelere dokunma")' in bubbles
    assert ".sensoryFeedback(.warning, trigger: model.blotsHit)" in bubbles
    assert "private func blot(_ context: inout GraphicsContext, _ bubble: Bubble)" in bubbles
    # The shooter fills the compact panel's width with eight rows of play and glossy bubbles.
    assert "static let deadRow = 9" in src("ShooterLogic.swift")
    shooter = src("ShooterGame.swift")
    assert "GameCorner.shade(colour, light: 1)" in shooter and "GameCorner.shade(colour, light: -1)" in shooter
    assert "case pop, fall, settle" in shooter and "guide.landing" in shooter
    # One result card for every game, one frame for every board, pressable tiles, success haptics.
    corner = src("GameCorner.swift")
    assert "struct ResultCard: View" in corner and "struct GameBoardFrame: ViewModifier" in corner
    assert corner.count("PressableStyle()") >= 3 and "func pageTransition(reduceMotion: Bool)" in corner
    for name in ("BubblesGame.swift", "SudokuGame.swift"):
        assert "ResultCard(title:" in src(name), name
    for name in ("BubblesGame.swift", "FlyerGame.swift", "ShooterGame.swift", "XOXGame.swift"):
        assert ".gameBoard()" in src(name), name
    for name in ("FlyerGame.swift", "ShooterGame.swift", "SudokuGame.swift", "XOXGame.swift"):
        assert ".sensoryFeedback(.success" in src(name), name


def test_the_logic_is_foundation_only_and_checked():
    for name in LOGIC:
        logic = src(name)
        assert logic.startswith("import Foundation\n") and "import SwiftUI" not in logic and "import UIKit" not in logic, name
    logic = src("MiniGameLogic.swift")
    for name in ("MandalaSymmetry", "BubbleField", "TicTacToe", "GameRandom", "GameProgress", "GameDifficulty", "GamePanelSize"):
        assert f"enum {name}" in logic or f"struct {name}" in logic, name
    assert "struct FlyerWorld" in src("FlyerLogic.swift")
    assert "struct ShooterBoard" in src("ShooterLogic.swift") and "struct HexGrid" in src("ShooterLogic.swift")
    assert "enum Sudoku" in src("SudokuLogic.swift") and "struct SudokuSave: Codable" in src("SudokuLogic.swift")
    assert "struct EbruTray: Equatable" in src("EbruLogic.swift") and "enum EbruMove: Equatable" in src("EbruLogic.swift")
    assert "struct InkPond: Equatable" in src("LivingInkLogic.swift") and "struct InkCreature: Equatable" in src("LivingInkLogic.swift")
    run = (TOOLS / "run.ps1").read_text(encoding="utf-8")
    for name in LOGIC:
        assert name in run, name
    main = (TOOLS / "main.swift").read_text(encoding="utf-8")
    for needle in ("MandalaSymmetry.copies", "BubbleField(size:", "TicTacToe", "xox trap", "xox zor: never loses", "GameProgress()",
                   "GamePanelSize.larger", "autopilot(level:", "ShooterLevels.all.enumerated()", "Sudoku.generate(difficulty:", "SudokuSave.decode",
                   ".blot(points: 5, seconds: 3)", "combos == [1, 2, 3, 4, 4]", "ShooterBoard.deadRow == 9",
                   "EbruTray(size: traySize", "every colour keeps its area", "a held drop stops at 60 pt", "the needle leaves paint far from its path alone",
                   "the comb pulls only along its axis", "undo stops a pattern and brings the tray back",
                   "just woken, it is exactly the drawing", "they turn round at the walls", "the creature eats every crumb",
                   "a ninth sends the oldest fading", "a poke startles the creature"):
        assert needle in main, needle


def test_the_levelled_games_grew():
    # Renk patlat: the pen's colour swaps with the next, and a big pop earns an ink blot that bursts
    # what it reaches; the blot is drawn as a splash, never as a bubble.
    logic = src("ShooterLogic.swift")
    assert "static let blot = -1" in logic and "static let blotPops = 6" in logic and "static let blotFalls = 4" in logic
    assert "mutating func swapLoaded()" in logic and "(loaded, next) = (next, loaded)" in logic
    assert "popped = grid.neighbours(of: landing).filter { cells[$0] != nil }" in logic
    shooter = src("ShooterGame.swift")
    assert "private func piece(_ c: inout GraphicsContext" in shooter and "private func blot(_ c: inout GraphicsContext" in shooter
    assert "piece(&context, at: well, radius: grid.radius * 0.55, colour: model.next)" in shooter
    assert "piece(&c, at: model.origin, radius: r, colour: model.loaded)" in shooter
    assert ".sensoryFeedback(.impact(weight: .heavy, intensity: 0.7), trigger: model.blots)" in shooter
    # Uçan damla: drifting gaps from level 5, the endless flight with its best, a page per stage.
    flyer = src("FlyerLogic.swift")
    assert "func driftedY(at time: TimeInterval) -> Double" in flyer and "let endless: Bool" in flyer
    assert "init(size: CGSize, level: Int, difficulty: GameDifficulty, seed: UInt64, endless: Bool = false)" in flyer
    assert "var speed: Double { endless ? settings.speed + min(70, 1.5 * Double(passed)) : settings.speed }" in flyer
    game = src("FlyerGame.swift")
    assert "FlyerPlay(level: 1, endless: true, difficulty: store[.flyer].difficulty, store: store)" in game
    assert 'Loc.t("Sonsuz uçuş")' in game and 'Loc.t("Uçuş bitti")' in game and 'Loc.t("Yeni rekor!")' in game
    assert "if phase == .failed { record = store.record(.flyer, score: model.passed, at: difficulty) }" in game
    assert "private var page: Int { endless ? (model.passed / 15) % 3 : min(2, max(0, (level - 1) / 4)) }" in game
    main = (TOOLS / "main.swift").read_text(encoding="utf-8")
    for needle in ("from level 5 every third gap drifts", "drifting gaps move and stay on the page", "flyer endless: the autopilot flies on and on",
                   "shooter: a swap trades the pen's colour for the next, free", "earns an ink blot as the next shot",
                   "the blot bursts the bubbles round it"):
        assert needle in main, needle


def test_the_creative_layer():
    corner = src("GameCorner.swift")
    # Two layers in a segmented control, the last one open kept; games first, as the tile is a game controller.
    assert "enum BreakLayer: String, CaseIterable, Identifiable" in corner and "case games, creative" in corner
    assert 'Loc.t("Oyunlar")' in corner and 'Loc.t("Yaratıcılık")' in corner
    assert "@AppStorage(GameProgress.Keys.layer) private var layer: BreakLayer = .games" in corner
    assert 'static let layer = "break.layer"' in src("MiniGameLogic.swift")
    assert re.search(r'Picker\(Loc\.t\("Katman"\), selection: \$layer\)', corner) and ".pickerStyle(.segmented)" in corner
    assert "case .ebru, .creatures, .mandala: return .creative" in corner and "case .bubbles, .xox, .flyer, .shooter, .sudoku: return .games" in corner
    assert "var hasDifficulty: Bool { layer == .games }" in corner
    # Ebru: six traditional pigments, three tools, a sprinkle, four patterns, undo; at once with Reduce Motion.
    ebru = src("EbruGame.swift")
    for name in ("Çivit mavisi", "Lal kırmızısı", "Zırnık sarısı", "Yeşil", "Toprak", "Beyaz", "Gelgit", "Taraklı", "Şal", "Bülbül yuvası",
                 "Damla", "Biz", "Tarak", "Serp", "Desen", "Geri al"):
        assert f'Loc.t("{name}")' in ebru, name
    assert "model.sprinkle(instantly: reduceMotion)" in ebru and "model.play(pattern, instantly: reduceMotion)" in ebru
    assert "ForEach(EbruPattern.allCases)" in ebru and ".menuStyle(.button)" in ebru
    assert ".accessibilityAddTraits(model.pigment == i ? .isSelected : [])" in ebru and ".frame(width: 40, height: 40)" in ebru
    # The timeline runs only while paint moves; the tray is redrawn from a revision counter.
    assert "var isMoving: Bool { tray?.isPlaying == true || tray?.isSpreading == true }" in ebru
    assert "@Published private(set) var revision = 0" in ebru and "private(set) var tray: EbruTray?" in ebru
    logic = src("EbruLogic.swift")
    for case in ("case drop(centre: CGPoint, radius: Double, pigment: Int)", "case spread(centre: CGPoint, radius: Double)",
                 "case line(through:", "case comb(through:", "case wave(through:", "case swirl(centre:", "case needle(tip:", "case combStep(tip:"):
        assert case in logic, case
    assert "case gelgit" in logic and "case tarakli" in logic and "case sal" in logic and "case bulbul" in logic
    assert "static let budget = 60_000" in logic and "static let historyLimit = 10" in logic
    # Living ink: five game inks, food, at most eight creatures, a tap on one pokes it instead of leaving a dot.
    living = src("LivingInkGame.swift")
    for name in ("Lacivert", "Turkuaz", "Macenta", "Kehribar", "Yeşil", "Yem ver"):
        assert f'Loc.t("{name}")' in living, name
    assert "ForEach(GameCorner.inkHues.indices, id: \\.self)" in living and "model.feed()" in living
    assert "pond?.poke(at: first) == true" in living and "InkPond.pose(creature)" in living
    pond = src("LivingInkLogic.swift")
    assert "static let maxCreatures = 8" in pond and "static let wakeDelay = 0.8" in pond and "static let pointBudget = 600" in pond
    assert "static func facesRight(_ strokes: [[CGPoint]]) -> Bool" in pond and "static func pose(_ c: InkCreature) -> [[CGPoint]]" in pond


def test_every_text_of_the_corner_goes_through_loc():
    for name in VIEWS:
        text = src(name)
        for turkish in re.findall(r'Text\("([^"\\]+)"\)', text):
            assert not re.search(r"[A-Za-zÇĞİÖŞÜçğıöşü]", turkish), (name, turkish)
        for turkish in re.findall(r'accessibilityLabel\("([^"]+)"\)', text):
            assert False, (name, turkish)
    xox = src("XOXGame.swift")
    for key in ("Kazandın!", "iPad kazandı.", "Berabere.", "Sıra sende: X çiz.", "iPad düşünüyor…"):
        assert f'Loc.t("{key}")' in xox, key
