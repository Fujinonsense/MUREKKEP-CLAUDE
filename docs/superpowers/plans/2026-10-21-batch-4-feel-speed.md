# Batch 4 — Feel and Speed Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Writing with 3D pens on a full page stays smooth, every pen has its own quiet sound that follows the hand without lag, lectures can be recorded in sync with the ink, a zoom window lets small writing land on the page, and the app gets faster without losing quality.

**Architecture:**
- **3D ink speed:**
  - The renderer appends a new stroke's mesh to the page buffers instead of rebuilding the page.
  - While the pencil is down, the committed ink is rendered into an offscreen layer at the content's own animation rate. Each display frame only composites that layer and draws the live stroke.
- **Pen sounds:** keep the granular engine, but give every brush a sound family with its own recordings or synthesized grains. Warm the engine at pen-down, use a 5 ms IO buffer and a quick attack.
- **Recording:** an `AVAudioRecorder` file per take, with its start date. Ink written during a take replays with the audio, and tapping ink seeks to it.
- **Zoom window:** a second Metal view shows a magnified box of the page. The pencil writes there and the canvas commits the strokes at page scale.

**Tech Stack:** Swift 5 mode, UIKit + SwiftUI, Metal, AVFoundation. Python twins in `tests/ports`. Windows Swift (`tools/swiftcheck`) for Foundation-only files. Asset tooling in `C:/Users/orsyu/mrk-ml`.

**Spec:** the user's items 17, 19, 21 (Notability parts), 28 and 32 in `C:/Users/orsyu/mrk-ml/re/long_prompt.txt`; roadmap `docs/superpowers/plans/2026-10-20-murekkep-3-roadmap.md`.

## Global Constraints

- `InkShaders.swift` is not changed in this batch. New Metal code lives in its own source string.
- Pen sounds use `.ambient` + `.mixWithOthers`: music is never paused or ducked. They are quiet, only a timbre.
- Sound files are CC0 or made here. Each license and source is listed in `docs/superpowers/reports/2026-10-21-batch-4-sounds.md`.
- Every new UI string goes through `Loc.t` and gets an English entry; `tests/test_translations.py` guards this.
- Zips only through `tools/make-zip.ps1 -ContentsOnly` (app + workflow). Build number 17.

## Review Focus

- A page with 400+ strokes of galaxy/glitter ink: writing a new stroke must not make the rest of the page flicker or change. The layer path must give the same pixels as the direct path.
- Erasing, lasso moves and undo while the pencil is down: the layer must re-render whenever a page's version changes.
- First stroke after opening a note: the sound starts with the line, not after it.
- Recording while the pen sound is on: the pen sound must not end up in the recording.
- Turning the iPad or zooming while the zoom window is open: the box stays on the same page spot.

---

### Task 1: Append new strokes to the page mesh

**Files:**
- Create: `Murekkep.swiftpm/InkMeshPlan.swift` (Foundation-only)
- Modify: `Murekkep.swiftpm/InkRenderer.swift` (`PageGPU`, `cached`, `rebuild`)
- Test: `tools/swiftcheck/main.swift`, `tools/swiftcheck/run.ps1`

**Interfaces:**
- Produces: `enum InkMeshPlan { case same, append(from: Int), rebuild }`.
- Produces: `static func plan(old: [Int], new: [(id: Int, highlighter: Bool, grass: Bool)]) -> InkMeshPlan`, where `old` is the stroke ids in buffer order.

Steps:
- [ ] Add swiftcheck cases:
  - same ids → `.same`
  - old + 2 new pen strokes → `.append(from: old.count)`
  - a new highlighter, a new grass stroke, a removed id or a reordered id → `.rebuild`
- [ ] Run swiftcheck and watch it fail to compile, since the type is missing.
- [ ] Implement `InkMeshPlan`.
- [ ] Buffers get 50 % headroom. `PageGPU` keeps the counts and the buffer order. `.append` writes the new meshes, infos and runs past the old ends. A full buffer falls back to `.rebuild`.
- [ ] Run swiftcheck and balance.ps1, then commit.

### Task 2: Ink layer while the pencil is down

**Files:**
- Modify: `Murekkep.swiftpm/InkRenderer.swift`
- Create: `Murekkep.swiftpm/InkLayer.swift` (the composite shader source and the reuse rule)

**Interfaces:**
- Produces: `struct InkLayerKey: Equatable` holding the transform, the drawable size, the visible pages and their versions, `animateWaves`, and the dry and cool durations.
- Produces: `static func InkLayer.reuse(key:old:contentFPS:age:) -> Bool`.

Steps:
- [ ] Add swiftcheck cases for `reuse`:
  - same key with static content → true
  - a different key → false
  - content at 30 fps with age 0.02 s → true, with age 0.04 s → false
  - no layer yet → false
- [ ] Watch the cases fail, then implement them.
- [ ] Split `drawStrokes` into an "under ink" part (highlighters, then the active highlighter and active shadow) and an "ink" part (shadows, inks and decor). The direct path draws exactly as before.
- [ ] Layer path, used only when an active stroke exists:
  1. Pass 1 renders the ink parts into a private bgra8 texture cleared to transparent.
  2. The main pass draws the backgrounds, stickers and under-ink parts.
  3. It then composites the layer with a premultiplied full-screen triangle that reads texels exactly.
  4. Last come the active ink and the active grass.
- [ ] Commit.

### Task 3: Pen sounds that follow the hand, one per pen

**Files:**
- Modify: `Murekkep.swiftpm/PaperSound.swift`, `Murekkep.swiftpm/CanvasView.swift` (`touchBegan`)
- Add: `Murekkep.swiftpm/Assets.xcassets/ses-*.dataset`
- Create: `tests/ports/pen_sound.py`, `tests/test_pen_sound.py`; asset tool `C:/Users/orsyu/mrk-ml/tools/pen_sounds.py`

**Interfaces:**
- Produces: `enum SoundFamily { pencil, pen, nib, felt, brush, water, lava, grass, spark, glass, metal }` and `Brush.soundFamily`.
- Produces: `PaperSound.prepare()` (called at pen-down), and `write(...)` / `lift()` as before.

Steps:
- [ ] Port the envelope (target gain from speed, pressure and turning) to Python. Tests:
  - the gain reaches 90 % within 12 ms of motion and falls to 10 % within 25 ms of a stop
  - a straight 1 s line at constant speed keeps a steady level
  - a quick letter loop changes the level more than a straight line does
- [ ] Watch the tests fail, then implement the port and write the Swift twin.
- [ ] Find CC0 recordings for each family (BigSoundBank first) and record their sources. Families with no fitting recording get synthesized grains.
  - `pen_sounds.py` trims the active parts, evens the loudness, makes 4–6 s mono clips and writes 64 kbps MP3.
  - A test checks each asset's length and loudness.
- [ ] Engine changes:
  - `prepare()` at touch-down starts the engine on a utility queue and asks for a 5 ms IO buffer.
  - It stops after 30 s of silence instead of 2.5 s.
  - Each family's bank loads lazily off the main thread.
  - The levels sit at about -30 dBFS under the music.
- [ ] Commit.

### Task 4: Lecture recording synced to the ink

**Files:**
- Create: `Murekkep.swiftpm/Recordings.swift` (store, recorder, player, sync rule), `Murekkep.swiftpm/RecordingBar.swift` (UI)
- Modify: `EditorModel.swift` (filtered pages during replay), `EditorView.swift` (mic button and bar), `CanvasView.swift` (a tap on ink seeks), `PaperSound.swift` (silent while recording)
- Create: `tests/ports/recording_sync.py`, `tests/test_recording_sync.py`

**Interfaces:**
- Produces: `struct Recording: Codable { id: UUID; start: Double; duration: Double; title: String }`, stored in `recordings.json` with `rec-<id>.m4a` in the note folder.
- Produces: `RecordingSync.visible(strokes births:, recording:, time:) -> Set<Int>`.
- Produces: `RecordingSync.seek(birth:, recordings:) -> (recording: UUID, time: Double)?`.

Steps:
- [ ] Tests:
  - strokes born before the take are always visible
  - strokes born during the take are visible once the time passes their birth
  - strokes born after the take are always visible
  - a tap on a stroke born at take start + 12 s seeks to 12 s minus 1 s of lead-in
  - a stroke outside every take gives nil
- [ ] Watch the tests fail, then implement the port and the Swift twin; add them to swiftcheck.
- [ ] Recorder:
  - `.playAndRecord` with `.mixWithOthers` and `.defaultToSpeaker`, 44.1 kHz AAC mono at 64 kbps
  - the pen sound is off while recording
  - the microphone permission text goes in `AppInfo.plist`
- [ ] Bar: record/stop, a list of takes, play/pause, a scrubber and speed 1×/1.5×/2×. During replay, ink born after the playhead is hidden. A finger tap on ink seeks.
- [ ] Commit.

### Task 5: Zoom window

**Files:**
- Create: `Murekkep.swiftpm/ZoomWindow.swift`
- Modify: `CanvasView.swift` (the stroke input API used by the window; the box overlay), `EditorView.swift` (toggle)

**Interfaces:**
- Produces: `ZoomBox` (page, rect in page points, magnification) and `ZoomBox.advance(after:lineHeight:pageWidth:margin:) -> ZoomBox`.
- Produces: the CanvasView methods `beginStroke(page:sample:)`, `extendStroke(samples:)`, `endStroke()`.

Steps:
- [ ] swiftcheck cases for `advance`:
  - the box moves right by its width minus a quarter overlap
  - at the margin it wraps to the next line's start
  - at the page bottom it stays put
- [ ] Watch them fail, then implement.
- [ ] Window: a bottom panel 1/3 of the screen tall. A second `MTKView` with its own `InkRenderer` draws the box's region. Pencil touches map to page points and go through the canvas's stroke pipeline. Ink near the right edge moves the box on.
- [ ] Commit.

### Task 6: Speed pass and delivery

Steps:
- [ ] Measure each change with a Python twin where possible, otherwise by reading the code.
  - The assistant's scan OCR uses `PageTextCache` (a deferred minor from Batch 3).
  - Library thumbnails decode off the main thread.
  - PDF page textures for pages far from view are released.
- [ ] Run the default suite, the venv suite, swiftcheck and balance.ps1 on every Swift file.
- [ ] Build 17, make the zip, write the rulings report and a Turkish summary for the user.
