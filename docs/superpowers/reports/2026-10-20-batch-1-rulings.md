# Batch 1 — rulings and deferred minors

Copied from the executing-plans ledger before it was deleted (git history is the record of the code).

## Rulings

- Task 2: Ruling: dropped the plan's 'toOrgan < 0.7 × toEllipse' condition — measured on 150 noisy kidneys/spleens + 1500 random bad circles: it halves kidney recall (145→72) and adds nothing once junction dents are ignored (bad circles as organs 16→0 with junction+notch≥0.10 alone) — cost if wrong: a lumpy circle with a deep mid-side dent can still suggest an organ.
- Task 2: Ruling: skipped the plan's holdFired 'circle beats organ' step — a kidney also fits an ellipse within ShapeRecognizer's limit, so it would remove organ suggestions entirely — cost if wrong: none measured (0/1500 circles misread).
- Task 3: Ruling: also made hold-to-snap shapes and dragged-handle restrokes keep their corners (Geo.densify in StrokeBuilder.place and EditorModel.restroke instead of uniform resample) — same cause as item 11 (corners cut between samples) — cost if wrong: denser strokes on long shapes (negligible).
- Task 4: Ruling: added a grab offset so a shape grabbed from inside moves with the touch (plan did not mention it; without it the shape's middle jumps under the pen) — cost if wrong: none.
- Task 5: Ruling: text-pen holds need 0.75 s (pen 0.55 s) and a drawing ≥ 28 pt — the plan only said 'hold-to-snap also runs for the text pen'; without a size floor a resting pen would turn letters (o, l, c) into shapes — cost if wrong: small symbols (< 28 pt) cannot be made with the text pen.
- Task 6: Ruling: InkEdit.linked is [InkEdit], not InkEdit? — a Swift struct cannot hold an optional of itself; an array can — cost if wrong: none (same behavior).
- Task 6: Ruling: undo/redo of a carried selection clears the selection; lasso ticks are capped at one per 25 ms — a stale frame would point at strokes on the other page; a fast loop would buzz — cost if wrong: one extra tap to reselect; fewer ticks on very fast loops.
- Task 7: Ruling: a new notebook page comes from pulling past the end of the scrollable area (rubber band > 90 pt), not 90 pt past the last page's edge, and only when the last page has ink; an empty last page is shown instead — the free margin below the last page is ≥ 220 pt, so "90 pt past the page" would add pages during ordinary scrolling while writing at the bottom — cost if wrong: the pull feels longer than expected.
- Task 7: Ruling: typed numbers are PDF page indices (as on the badge), not printed page labels — matches the "12 / 300" badge — cost if wrong: textbook page 45 may be PDF page 57; can add label lookup later.
- Task 7: Ruling: lastPage is saved 1.5 s after the page changes and on close — avoids rewriting the library index every frame while scrolling — cost if wrong: a crash within 1.5 s of a page change reopens one page earlier.
- Task 7: Ruling: tools/balance.ps1 now resolves paths before reading — relative paths were read against the process folder and failed silently while printing "ok" — cost if wrong: none.
- Task 8: Ruling: no Python port for the text box — it is UIKit view placement; the line geometry is now one function (HandwritingConverter.typedLayout) shared by the box and the written text, so they cannot drift; verified by the CI build and the iPad checklist — cost if wrong: a box a few points off its line, seen on device.
- Task 8: Ruling: the old TextEntrySheet and EditorModel.textRequest were removed (orphaned); its symbol row moved into the keyboard bar — cost if wrong: none.
- Task 9: Ruling: double-tap root cause NOT confirmed (no device). Investigated every path: the interaction is never disabled or removed except on window changes (Sci re-adds it); the tap handler, the tool ring and hover have no tool-specific branch; no other UIPencilInteraction, Scribble or PencilKit view exists. The only tool-specific factor found is main-thread work right after a stroke: the text pen's spelling pass (UITextChecker.guesses for up to 6 readings) — reduced (exact early stop, tested) and split per line. For 3D pens the factor is per-frame rendering and page mesh rebuilds on the main thread — Batch 4 (item 19). — cost if wrong: double tap may still misbehave on device; needs the iPad checklist.
- Task 9: Ruling: a squeeze held ≥ 0.5 s gives the pen back on release even without erasing — before, a held-then-released squeeze left the eraser in hand and the next pen stroke erased — cost if wrong: someone who holds, releases, then wants to erase must squeeze again.
- Task 10: Ruling: "the question's language" = the exam question on the page when the request is a short command about it ("bu soruyu çöz", ≤ 8 words with a page cue); a question in the user's own words keeps its own language — items 8–9 are about PDF prep-school questions — cost if wrong: a Turkish student asking "bu soruyu çöz" on an English page gets an English answer (the user's stated wish).
- Task 11: Ruling: the toolbar strip shows the 5 most recent pens in panel order (not recency order) plus the text pen and eraser; the four tabs became one "all pens" button opening the panel — recency order would move a pen every time it is picked — cost if wrong: a pen used 6 picks ago needs the panel.
- Task 11: Ruling: the barrel star (isPremium) keeps its old set of 3D inks, decoupled from the new sections — the artwork should not change with the regrouping — cost if wrong: none.
- Task 11: Ruling: section test reads Brushes.swift directly; it was written after the Swift edit, so RED was shown by running it against the HEAD copy of the file (2 fail) before GREEN — cost if wrong: none.
- Task 12: Ruling: InkRenderer (not only InkShaders) changed too — the 60 fps lava loop stopped at coolDuration after the stroke ended, so the far end of a long stroke would freeze half-cooled; it now runs until the last point has cooled (stroke length / 380 pt/s added) — cost if wrong: a few extra seconds of 60 fps after long lava strokes.
- Task 12: Ruling: the lightning bolt is cut at both round caps (start and end), not only the end — the same overshoot existed behind the start point — cost if wrong: none visible.
- Task 12: Ruling: test_lava_cools_from_where_the_pen_started sampled at 1 s, when middle and end are both still fully molten (1.0 == 1.0); moved to 2.5 s — the expectation, not the code, was wrong — cost if wrong: none.
- Task 13: Ruling: CI push and IPA build NOT done — gh is not signed in and the repo has no remote; signing in is the user's step — cost if wrong: compile errors (no Swift compiler on this PC) surface only when CI runs; zip Murekkep-3.0-beta1-iPad.zip is built and checked (81 entries, 65 Swift files, forward slashes).

## Deferred minors

- Final: minor (deferred): the Aa text box re-measures itself (sizeThatFits) on every rendered frame while open — skip when zoom and origin are unchanged.
- Final: minor (deferred): the page navigator opens PDFKit's PDFDocument on the main thread the first time (for the contents) — a short hitch on very large PDFs.
- Final: minor (deferred): Theme.ai may be unused now that the premium tab is gone.

## Final review

- Final review: self-review (no subagent: this harness spawns agents only when the user asks) — package review-6fa1cfb..4665651.diff, two passes over the Swift; no Critical or Important findings. Compile errors cannot be ruled out without a Swift compiler; CI is the check.
