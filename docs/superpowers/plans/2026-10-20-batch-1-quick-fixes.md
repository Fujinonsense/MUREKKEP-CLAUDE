# Batch 1: Quick Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the 20 Batch 1 items from the roadmap so the editor, shapes, PDF navigation and pen picker behave the way the user expects.

**Architecture:** Changes stay inside the existing files of `Murekkep.swiftpm`; one new file, `PageNavigator.swift`, holds the page navigation sheet. Recognizer and geometry changes get Python ports in `tests/` so their rules are checked on this PC; everything else is checked by the CI build plus the iPad checklist at the end.

**Tech Stack:** Swift 5 mode, SwiftUI, UIKit, Metal; Python 3 + pytest for the geometry tests.

**Spec:** `docs/superpowers/plans/2026-10-20-murekkep-3-roadmap.md` (Batch 1 row) and the user's items 4, 6, 7, 8, 11, 13, 15, 16, 18, 20, 22–27, 29–31.

## Global Constraints

- New UI strings use `Loc.t(...)` and get an English entry in `Translations.swift`.
- `InkShaders.swift`: only the lightning (item 30) and lava (item 31) code may change.
- `NoteMeta` stays decodable from 2.9 files: every new field is optional.
- One undo step per user action, including a lasso move to another page.

## Review Focus

- Pencil writing right next to a shape whose handles are showing: the pencil writes; it does not grab a handle unless it starts on one.
- A notebook scrolled past its last page by accident while reading: a page is added only after a deliberate pull (more than 90 pt) and a haptic confirms it.
- Bookmarks and the remembered page in a PDF whose page count changed (file replaced): out-of-range pages are dropped, not crashed on.
- A curve fitted to a nearly straight stroke: it stays a line (the line test runs first).
- The text box (Aa) on a page turned by −15°: the box and the text it writes are level with the page, not the screen.

---

### Task 1: Dense shape and text strokes (item 11)

**Files:**
- Modify: `Murekkep.swiftpm/StrokeFont.swift` (`StrokeText.strokes`)
- Test: `tests/test_dense_paths.py`

**Interfaces:**
- Produces: `StrokeText.strokes(_:style:flowerLevel:birth:)`, same signature; every returned stroke has points no more than `max(0.6, r * 0.5)` apart along each straight piece.

- [ ] Write `test_dense_paths.py`: ports `densify` and `RibbonBuilder.smoothed` (Catmull-Rom, exact constants from `RibbonBuilder.swift`); asserts that an octagon of radius 60 densified then smoothed stays within 0.6 pt of the true polygon, and that the old sparse octagon deviates by more than 3 pt (proves the bug).
- [ ] Run `uv run --with pytest pytest tests/test_dense_paths.py -q`; the new-path assertion fails before the Swift port matches.
- [ ] In `StrokeText.strokes`, densify each path linearly at spacing `max(0.6, r * 0.5)` before making `InkPoint`s (vertices kept).
- [ ] Run the test; it passes.
- [ ] Commit `fix: shapes and typed text keep their corners (dense stroke paths)`.

### Task 2: A wobbly circle stays a circle (item 13)

**Files:**
- Modify: `Murekkep.swiftpm/SketchRecognizer.swift` (`recognize`, `concavities`)
- Modify: `Murekkep.swiftpm/CanvasView.swift` (`holdFired`)
- Test: `tests/test_sketch_rules.py`

**Interfaces:**
- Produces: `SketchRecognizer.concavities(_ pts: [CGPoint], ignoringJunction: Bool) -> [CGFloat]`.

- [ ] Test: a circle of radius 50 with ±4 % noise whose end overlaps the start inward by 9 % yields no notch ≥ 0.10 once the junction (12 % of the loop on each side of index 0) is ignored; the kidney template keeps its hilum notch ≥ 0.12.
- [ ] Organs need a notch ≥ 0.10 away from the junction and `toKidney` (or `toSpleen`) `< 0.7 * toEllipse`.
- [ ] `holdFired`: when `ShapeRecognizer.recognize` returns a circle or ellipse and the sketch is not a heart, the shape wins.
- [ ] Commit `fix: hand-drawn circles no longer become a kidney or spleen`.

### Task 3: Curves replace arcs (item 27)

**Files:**
- Modify: `Murekkep.swiftpm/ShapeRecognizer.swift` (`openShape`, `ShapeMatch`, `Fit`)
- Modify: `Murekkep.swiftpm/ShapeEditing.swift`
- Test: `tests/test_curve_fit.py`

**Interfaces:**
- Produces: `ShapeMatch.Kind.curve`; `ShapeMatch.curve: (start: CGPoint, control: CGPoint, end: CGPoint)?`; `Fit.quadraticBezier(_ pts: [CGPoint]) -> (control: CGPoint, rms: CGFloat)?` (endpoints fixed to the first and last point, chord-length parameters); `EditableShape.Kind.curve(start:control:end:)` with handles `[start, onCurveMid, end, middle]`, where dragging `onCurveMid` (B(0.5)) sets `control = 2·M − (start + end)/2`.
- [ ] Test: points sampled from a known quadratic Bézier plus 1 pt noise recover the control point within 2 pt.
- [ ] Remove the arc candidate; the parabola candidate becomes the curve (`Loc.t("Eğri")`, English "Curve"); no arrowhead.
- [ ] Commit `feat: curves with a drag handle instead of arcs`.

### Task 4: Handles behave (items 24, 26)

**Files:**
- Modify: `Murekkep.swiftpm/CanvasView.swift` (`touchBegan`, `shapeHandle(at:in:zoom:reach:)`, new finger tap recognizer)

**Interfaces:**
- Consumes: `model.finishShapeEdit()`, `model.finishPlacing()`.
- [ ] A one-finger tap anywhere that is not a handle or the sticker box ends the shape edit and the placement (also in pencil-only mode).
- [ ] Pencil reach for vertex handles drops from 26 pt to 16 pt; a pencil touch elsewhere ends the edit and draws.
- [ ] A touch inside a closed shape's outline (or within 14 screen pt of an open shape's path) that misses the vertex handles grabs the move handle.
- [ ] Commit `fix: shape handles close on a finger tap and move from anywhere inside`.

### Task 5: Symbols with the text pen (item 4)

**Files:**
- Modify: `Murekkep.swiftpm/CanvasView.swift` (`touchBegan`, `touchMoved`, `touchEnded`)

- [ ] Hold-to-snap (`trackHold`) also runs for the text pen.
- [ ] A text-pen stroke that became a shape or a sketch suggestion is not queued for text; it stays ink.
- [ ] Commit `feat: text pen keeps hearts, circles and other held shapes as drawings`.

### Task 6: Lasso across pages and lasso haptics (items 23, 25)

**Files:**
- Modify: `Murekkep.swiftpm/EditorModel.swift` (`endSelectionEdit`, undo/redo)
- Modify: `Murekkep.swiftpm/CanvasView.swift` (`lassoMoved`, `lassoEnded`)

**Interfaces:**
- Produces: `InkEdit.linked: InkEdit?` (the other page's change, undone and redone together).
- [ ] When a move ends with the selection's center over another page, the strokes and stickers move to that page (page-local coordinates re-based), the selection follows, and one undo step restores both pages.
- [ ] While the lasso loop is drawn, a light alignment haptic fires every dash period of the lasso outline (read the dash pattern from `CanvasOverlay`), so the pencil ticks with the dashes.
- [ ] Commit `feat: move a lasso selection to another page; pencil ticks along the lasso`.

### Task 7: PDF and notebook navigation (items 6, 18, 20, 22)

**Files:**
- Create: `Murekkep.swiftpm/PageNavigator.swift`
- Modify: `Murekkep.swiftpm/InkModel.swift` (`NoteMeta.lastPage: Int?`, `NoteMeta.bookmarks: [Int]?`, `NoteMeta.pageMode: String?`)
- Modify: `Murekkep.swiftpm/EditorModel.swift` (`scrollRequest`, `toggleBookmark`, `isBookmarked`, `lastPage` save on close and on page change)
- Modify: `Murekkep.swiftpm/EditorView.swift` (`PageBadge` becomes a button)
- Modify: `Murekkep.swiftpm/CanvasView.swift` (observe `scrollRequest`, single-page snapping, pull-to-add-page, initial jump to `lastPage`)

**Interfaces:**
- Produces: `EditorModel.requestScroll(to page: Int)`, `var onScrollRequest: ((Int) -> Void)?`, `func toggleBookmark(_ page: Int)`, `var bookmarks: [Int]`, `@Published var singlePage: Bool`.
- [ ] Tapping the page badge opens `PageNavigator`: a number field ("Sayfaya git"), bookmark toggle for the current page, bookmarked pages, the PDF outline (`PDFDocument.outlineRoot`) and a thumbnail grid.
- [ ] Single-page mode: dragging ends on a page boundary (`scrollViewWillEndDragging` sets the target to the next/previous page top by velocity) and the zoom fits the whole page.
- [ ] Reopening a note scrolls to `lastPage`.
- [ ] Notebook: pulling more than 90 pt past the last page adds a page (haptic) and scrolls to it.
- [ ] Commit `feat: go to page, single-page mode, bookmarks, outline, resume where you left`.

### Task 8: Text box on the paper (item 16)

**Files:**
- Modify: `Murekkep.swiftpm/CanvasView.swift` (inline `UITextView` in `rotationHost`)
- Modify: `Murekkep.swiftpm/EditorView.swift` (remove the `textRequest` sheet)

- [ ] Tapping with the Aa tool opens a borderless text box at the tap point, sized and rotated with the page and following scroll and zoom; Return adds a line, tapping outside (or the ✓ in the keyboard bar) writes the text with `model.insertText` and closes it.
- [ ] Commit `feat: type straight onto the page`.

### Task 9: Pencil double tap and squeeze (items 6, 7)

**Files:**
- Modify: `Murekkep.swiftpm/CanvasView.swift` (pencil interaction, `finishErasing`)

- [ ] Find why double tap fails with the text pen and with some 3D pens (superpowers:systematic-debugging: list every path that disables or swallows `UIPencilInteraction` callbacks while those tools are active) and fix the cause.
- [ ] Squeeze: a short squeeze borrows the eraser for exactly one erase stroke, then the pen returns by itself; squeeze-and-hold erases until release.
- [ ] Commit `fix: double tap with every pen; squeeze erases once and comes back`.

### Task 10: Small UI fixes (items 8, 15)

**Files:**
- Modify: `Murekkep.swiftpm/DraftingTools.swift` (`PageAnglePanel`)
- Modify: `Murekkep.swiftpm/AIEngine.swift`, `Murekkep.swiftpm/AssistantModel.swift`

- [ ] Angle presets stay on one line (`lineLimit(1)`, `minimumScaleFactor(0.7)`, compact buttons; panel 360 pt).
- [ ] The answer language comes from the question and the page text (`NLLanguageRecognizer`), not from the UI language.
- [ ] Commit `fix: angle presets on one line; answers in the question's language`.

### Task 11: New pen picker (item 29)

**Files:**
- Modify: `Murekkep.swiftpm/Brushes.swift` (`BrushGroup`)
- Modify: `Murekkep.swiftpm/ToolPalette.swift`

- [ ] Use the frontend-design skill for the visual direction.
- [ ] One scrolling panel instead of four tabs: a "Son kullanılanlar" row, then sections Yazı (pen, pencil, fountain, calligraphy, highlighter), Boya (watercolor, impasto, wet, neon, rainbow, glitter), Doğa (sea, wave, grass, lava, ice, lightning, galaxy), Işıltı (gold, chrome, pearl, jelly).
- [ ] Commit `feat: one elegant pen panel with sections`.

### Task 12: Lightning and lava (items 30, 31)

**Files:**
- Modify: `Murekkep.swiftpm/InkShaders.swift` (lightning and lava functions only)

- [ ] Lightning: the thick bolt stops at the pen tip (no extension past the last point).
- [ ] Lava cools from the first point to the last: each point's cooling starts at `birth + arc / 380 pt·s⁻¹` (the drawing speed), then takes `coolDuration`.
- [ ] Commit `fix: lightning stays behind the tip; lava cools from where the pen started`.

### Task 13: Build and deliver beta 1

- [ ] Bump `Package.swift` and the workflow to 3.0 (build 13); run `balance.ps1`; package `Murekkep-3.0-beta1-iPad.zip`; push to the user's repo when they are signed in, read the CI log, fix errors.
- [ ] iPad checklist for the user: octagon with pen and lava; wobbly circle; curve handle; finger tap closes handles; heart with text pen; lasso to next page and undo; go to page 600; bookmark; reopen at the same page; pull past the last notebook page; Aa on a turned page; double tap with text pen and galaxy; lava cooling; new pen panel.
