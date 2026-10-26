"""The break corner: a small icon at the bottom-left of the page opens a card of three calm games
(the ink mandala, the ink bubbles, XOX against the iPad), held in the source.

The icon stands beside the writing sound's switch and goes away while a lecture is recorded; the
panel keeps its touches off the page, springs in and out (fades with Reduce Motion), and stands
clear of the drafting rail and the pen bar. The games' logic is Foundation only and checked by
tools/gamescheck; the bubbles' best score is the only thing kept, in UserDefaults."""
import re
from pathlib import Path

APP = Path(__file__).resolve().parent.parent / "Murekkep.swiftpm"
TOOLS = Path(__file__).resolve().parent.parent / "tools" / "gamescheck"


def src(name):
    return (APP / name).read_text(encoding="utf-8")


def test_the_icon_sits_in_the_bottom_left_corner_beside_the_sound_switch():
    editor = src("EditorView.swift")
    corner = editor[editor.index("PaperSoundCornerButton(settings: settings)"):][:400]
    assert "GameCornerButton(isOpen: $showGames)" in corner
    # Away while a lecture is recorded, and the panel closes when a recording starts.
    assert "if !lecture.isRecording {" in corner
    assert re.search(r"onChange\(of: lecture\.isRecording\) \{ _, recording in\s*if recording \{ closeGames\(\) \}", editor)
    assert "@State private var showGames = false" in editor


def test_the_panel_stands_above_the_icon_clear_of_the_rail_and_the_pen_bar():
    editor = src("EditorView.swift")
    panel = editor[editor.index("if showGames {"):][:600]
    assert "GameCornerPanel { closeGames() }" in panel
    assert ".padding(.leading, gamePanelLeading)" in panel
    assert ".padding(.bottom, 56 + bottomClearance)" in panel
    assert "alignment: .bottomLeading" in panel
    assert ".transition(GameCorner.transition(reduceMotion: reduceMotion))" in panel
    # Past the drafting rail (12…62 pt) while it shows; never off a narrow canvas.
    assert "paletteCollapsed ? 12 : 72" in editor
    assert "canvasSize.width - GameCorner.panelSize.width - 12" in editor
    assert "@Environment(\\.accessibilityReduceMotion) private var reduceMotion" in editor


def test_the_icon_and_the_panel():
    corner = src("GameCorner.swift")
    assert 'Image(systemName: "gamecontroller")' in corner
    assert ".frame(width: 34, height: 34)" in corner
    assert 'accessibilityLabel(isOpen ? Loc.t("Molayı kapat") : Loc.t("Mola: küçük oyunlar"))' in corner
    assert "static let panelSize = CGSize(width: 340, height: 420)" in corner
    # Spring in and out, a fade with Reduce Motion.
    assert "reduceMotion ? .easeInOut(duration: 0.15) : .spring(" in corner
    assert "reduceMotion ? .opacity : .scale(scale: 0.86, anchor: .bottomLeading)" in corner
    # The card keeps every touch to itself: nothing reaches the ink canvas beneath.
    assert re.search(r"\.glassCard\(radius: GameCorner\.radius\)\s*\.contentShape\(RoundedRectangle[^\n]*\n[^\n]*\n\s*\.onTapGesture \{\}", corner)
    # Header, close, picker with icons and names, back and restart.
    assert 'Loc.t("Mola")' in corner and 'Loc.t("Kapat")' in corner
    assert 'headerButton("chevron.left", label: Loc.t("Oyunlara dön"))' in corner
    assert 'headerButton("arrow.counterclockwise", label: Loc.t("Yeniden başlat"))' in corner
    assert "ForEach(MiniGame.allCases)" in corner and "Image(systemName: item.symbol)" in corner and "Text(item.title)" in corner
    assert "case .mandala: InkMandalaGame()" in corner
    assert "case .bubbles: InkBubblesGame()" in corner
    assert "case .xox: XOXGame()" in corner
    # Not Pro-gated, no network.
    for name in ("GameCorner.swift", "MandalaGame.swift", "BubblesGame.swift", "XOXGame.swift", "MiniGameLogic.swift"):
        text = src(name)
        assert "ProPlan" not in text and "URLSession" not in text and "import Network" not in text, name


def test_the_three_games_draw_with_the_pencil_and_keep_their_touches():
    mandala = src("MandalaGame.swift")
    assert "MandalaSymmetry.copies(of:" in mandala and "MandalaSymmetry.hue(at:" in mandala
    assert "DragGesture(minimumDistance: 0, coordinateSpace: .local)" in mandala
    assert "layer.addFilter(.blur(radius: 5))" in mandala
    assert 'Button(Loc.t("Temizle"))' in mandala
    bubbles = src("BubblesGame.swift")
    assert "TimelineView(.animation(paused: paused))" in bubbles
    assert "model.isOver || scenePhase != .active" in bubbles
    assert "DragGesture(minimumDistance: 0, coordinateSpace: .local)" in bubbles
    assert ".onChanged { value in model.pop(at: value.location) }" in bubbles
    assert "if stopped { model.pause() }" in bubbles
    xox = src("XOXGame.swift")
    assert "game.bestMove(for: Self.device, rng: &random)" in xox
    assert ".trim(from: 0, to:" in xox and 'Loc.t("Tekrar")' in xox
    assert "value.startLocation" in xox
    assert "try? await Task.sleep(nanoseconds: 550_000_000)" in xox
    assert ".task(id: pendingReply)" in xox


def test_the_bubbles_best_score_is_kept_in_user_defaults():
    logic = src("MiniGameLogic.swift")
    assert 'static let bestKey = "breakBubblesBest"' in logic
    assert "static let round: TimeInterval = 60" in logic
    bubbles = src("BubblesGame.swift")
    assert "UserDefaults.standard.integer(forKey: BubbleField.bestKey)" in bubbles
    assert "UserDefaults.standard.set(best, forKey: BubbleField.bestKey)" in bubbles
    assert 'Loc.t("Yeni rekor!")' in bubbles


def test_the_logic_is_foundation_only_and_checked():
    logic = src("MiniGameLogic.swift")
    assert logic.startswith("import Foundation\n") and "import SwiftUI" not in logic and "import UIKit" not in logic
    for name in ("MandalaSymmetry", "BubbleField", "TicTacToe", "GameRandom"):
        assert f"enum {name}" in logic or f"struct {name}" in logic, name
    run = (TOOLS / "run.ps1").read_text(encoding="utf-8")
    assert "MiniGameLogic.swift" in run
    main = (TOOLS / "main.swift").read_text(encoding="utf-8")
    assert "MandalaSymmetry.copies" in main and "BubbleField(size:" in main and "TicTacToe" in main
    assert "xox trap" in main  # the iPad can be beaten


def test_every_text_of_the_corner_goes_through_loc():
    for name in ("GameCorner.swift", "MandalaGame.swift", "BubblesGame.swift", "XOXGame.swift"):
        text = src(name)
        for turkish in re.findall(r'Text\("([^"]+)"\)', text):
            assert not re.search(r"[A-Za-zÇĞİÖŞÜçğıöşü]", turkish), (name, turkish)
        for turkish in re.findall(r'accessibilityLabel\("([^"]+)"\)', text):
            assert False, (name, turkish)
    xox = src("XOXGame.swift")
    for key in ("Kazandın!", "iPad kazandı.", "Berabere.", "Sıra sende: X çiz.", "iPad düşünüyor…"):
        assert f'Loc.t("{key}")' in xox, key
