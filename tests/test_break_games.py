"""The break corner: a glass tile at the bottom-left of the page opens a compact card of six calm
games (the ink mandala, the ink bubbles, XOX against the iPad, the flying drop, the colour popper,
Sudoku), held in the source.

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
VIEWS = ("GameCorner.swift", "MandalaGame.swift", "BubblesGame.swift", "XOXGame.swift", "FlyerGame.swift", "ShooterGame.swift", "SudokuGame.swift")
LOGIC = ("MiniGameLogic.swift", "FlyerLogic.swift", "ShooterLogic.swift", "SudokuLogic.swift")


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
    # The six games, with icons and names, in a grid.
    assert "ForEach(MiniGame.allCases)" in corner and "Image(systemName: item.symbol)" in corner and "Text(item.title)" in corner
    assert "case mandala, bubbles, xox, flyer, shooter, sudoku" in corner
    for line in ("case .mandala: InkMandalaGame()", "case .bubbles: InkBubblesGame(store: store)", "case .xox: XOXGame(store: store)",
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
    assert ".onChanged { value in model.updateAim(to: value.location) }" in shooter
    assert ".onEnded { value in model.fire(at: value.location, now: Date()) }" in shooter
    assert "if let guide = model.guide()" in shooter  # the dotted line
    sudoku = src("SudokuGame.swift")
    assert "TimelineView(.periodic(from: .now, by: 1))" in sudoku and "if scenePhase == .active { model.tick() }" in sudoku
    assert "Task.detached(priority: .userInitiated)" in sudoku and "Sudoku.generate(difficulty: difficulty, seed: seed)" in sudoku
    assert "ForEach(1...9, id: \\.self)" in sudoku and 'Loc.t("Notlar")' in sudoku and 'Loc.t("Sil")' in sudoku
    assert "conflicts.contains(i) { tint = Color.red.opacity(0.16) }" in sudoku
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
    run = (TOOLS / "run.ps1").read_text(encoding="utf-8")
    for name in LOGIC:
        assert name in run, name
    main = (TOOLS / "main.swift").read_text(encoding="utf-8")
    for needle in ("MandalaSymmetry.copies", "BubbleField(size:", "TicTacToe", "xox trap", "xox zor: never loses", "GameProgress()",
                   "GamePanelSize.larger", "autopilot(level:", "ShooterLevels.all.enumerated()", "Sudoku.generate(difficulty:", "SudokuSave.decode"):
        assert needle in main, needle


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
