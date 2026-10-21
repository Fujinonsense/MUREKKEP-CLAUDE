# Batch 4 — rulings (feel and speed, build 17)

Plan: `docs/superpowers/plans/2026-10-21-batch-4-feel-speed.md`.
Branch: `murekkep-4-feel-speed`, cut from `murekkep-3-fix-textpen-ai` (beta 4, build 16).
Neither branch is merged into `main`.

## What changed

- **3D ink speed (item 19):**
  - A new stroke's mesh is appended to its page's buffers. The buffers keep 50 % spare room; only removed, reordered, highlighter or grass strokes rebuild the page.
  - While the pencil writes, the committed ink is drawn once into a layer. That layer is redrawn only when the view or a page changes, or at the ink's own animation rate. Each display frame copies the layer and shades only the live stroke.
- **Pen sounds (items 17 and 28):**
  - 14 families over 11 banks of CC0 recordings (license-checked page by page; see `2026-10-21-batch-4-sounds.md`), plus two synthesized sparkles.
  - The engine wakes at pencil-down on its own queue, uses a 5 ms buffer and stays warm for 30 s.
  - Loudness follows speed, the turns of the letters and pressure, reached within ~12 ms (`PenSoundEnvelope`).
  - Music is never paused or ducked, and the pen is silent while a lecture is being recorded.
- **Lecture recording (Notability):**
  - The mic button opens a bar: record, then play each take with a scrubber, 1–2× speed and "ink follows the sound".
  - A finger tap on ink plays from 1.5 s before it was written.
- **Zoom window (Notability):**
  - A panel along the bottom shows a box on the page magnified. The pencil writes large there and the ink lands at page size in the box.
  - The box moves on along the line, then to the next line and the next page.
- **Speed pass (item 32):**
  - The canvas overlay repaints only when what it shows changes.
  - OCR cached by earlier builds (read across both columns of a page) is dropped once.
  - The assistant shares the Studio's disk cache of scanned pages.

## Rulings

- **Glass ink under the live shadow.** On the layered path, the live 3D stroke's soft shadow is drawn under the committed ink. Under see-through committed ink (ice, jelly, neon, lava, lightning), it can show faintly while the pencil is down; the direct path hides it there. It is right again the moment the pencil lifts. Cost if wrong: a faint shadow under glassy ink for the length of one stroke.
- **The layer is only used while the pencil is down.** Scrolling and idle animation draw directly, as before, so the layer cannot affect them. Cost if wrong: none for scrolling; idle animated pages are as fast as in build 16.
- **Lava recording left out.** Freesound 870749 was measured as a single pitched drone, not lava, and was dropped. Cost if wrong: one fewer lava variation.
- **Recordings are evened out with a soft limiter.** Spiky recordings (grass, ice) keep their crackle but lose their loudest snaps. Cost if wrong: crackles a little softer than recorded.
- **Takes play in the spoken-audio category.** Playing a take pauses the user's music (closing the bar lets it resume), while recording mixes with it. Cost if wrong: music stops while a lecture plays back.
- **Only inkless scanned pages share the disk cache.** The assistant reads pages with ink together with the ink, so those are not cached on disk. Cost if wrong: a page with notes on it is read again after relaunching.
- **The zoom window takes only pens, the text pen and the eraser.** Lasso, shapes, compass and text work on the page itself. Cost if wrong: switching to the page for those tools.

## Not verified here

- No Mac or iPad was available. The pure parts are tested in Python twins and compiled with Swift 6.4 on Windows: `InkMeshPlan`, `InkLayer`, `PenSoundEnvelope`, `RecordingSync` and `ZoomBox`. The Metal, AVFoundation and UIKit parts are checked against Apple's documentation and read line by line.
- The first full build is the GitHub macOS 26 workflow.
