# Batch 2 — rulings and deferred minors

Copied from the executing-plans ledger before it was deleted (git history is the record of the code).

## Rulings

- Task 8: Ruling (pre-flight): convert uses a ruling copy with capHeight = capHeight(ruling:scale:) so placement, widths and glyphs all follow the chosen size — cost if wrong: none.
- Task 3: Ruling: glyphs are stored as skeleton segments, not point sets — points fall apart into dots when a lone mark ("." "ı" "-") is enlarged to the 30 px core — cost if wrong: none.
- Task 3: Ruling: 56 "Playwrite … Guides" fonts (practice guide lines under letters) and fonts with capitals over 3.5× the ink of small letters (calligraphy) are left out; all-caps lines use only fonts with plain capitals (≤ 2.2×) or StrokeFont — seen on the sample sheet: underlined letters and unreadable ornate caps — cost if wrong: less style variety (280 training fonts remain).
- Task 3: Ruling: the synthetic generator also scales units to page points (cap 10–22 pt) before rendering, so the 1-pt floor of the line transform behaves as in the app — cost if wrong: none.
- Task 5: Ruling: half floats are decoded by hand instead of Swift's Float16 — Float16 is missing on some build targets (Intel simulators) — cost if wrong: none.
- Task 5: Ruling: the Swift network itself cannot run here; its correctness rests on being a line-by-line transcription of infer_np.py (checked against PyTorch, Δ < 0.002) — cost if wrong: wrong readings on device, caught by the iPad checklist; the Vision path stays as a fallback.
- Task 6: Ruling: candidate value = log P / (characters of the model's best reading) + 0.6 × dictionary share, with the dictionary case-insensitive — per-frame normalization would let the dictionary overrule a confident model on names; case-sensitive lookup would lowercase "İSTANBUL'DA" — cost if wrong: a non-word the model is unsure of may be "corrected" to a dictionary word.
- Task 6: Ruling: a raised group that reads as punctuation (' " ` , .) is inserted as itself, not as an exponent — an apostrophe written high after a capital looks like an exponent geometrically — cost if wrong: none.
- Task 6: Ruling: Spelling.score was already internal; nothing to expose — cost if wrong: none.
- Task 7: Ruling: TextPlacement.place takes startX + startLine (not a CGPoint) and a joinGap — the line index is already decided by convert (never above nextLine) and punctuation needs a hairline instead of a space — cost if wrong: none (plan interface refined).
- Task 7: Ruling: underlines (wider than 4 caps, flatter than 0.4 cap) and drawings taller than two lines are not obstacles — otherwise an underline or a frame around the writing would push every word away — cost if wrong: typed text may touch a long flat stroke.
- Task 7: Ruling: on paper without printed lines the grid is aligned to the text pen's previous baseline (top = baseline mod spacing) — replaces the old continueFrom snap — cost if wrong: none on lined paper (not applied there).
- Task 8: Ruling: the size option also applies to the Aa text box and lasso convert-to-text — one 'punto' for all typed text — cost if wrong: none.
- Task 4: Ruling: composed dots enlarged (0.2 → 0.5 units) and all-caps fragments raised from 5 % to 12 %; training resumed from the step-12,000 weights (runs/main2) — the line image hides absolute letter size, so case must be learned from shape and context — cost if wrong: an hour of GPU time.
- Task 9: Ruling: CI build and iPad test NOT done — GitHub sign-in is still the user's step; Murekkep-3.0-beta2-iPad.zip built (88 entries, 69 Swift files, hwmodel.bin inside, 6.2 MB) — cost if wrong: compile errors appear only in CI.

## Model results

- Task 4: first run stopped at step 12,000 (CER 4.1 %, Turkish letters 92.6 % on unseen fonts); its mistakes were missed umlaut dots and all-caps lines read as lowercase.
- Task 4: exported runs/main2/best.pt (step 22,000 of the resumed run): held-out CER 2.28 %, Turkish letters 97.07 %; hwmodel.bin 4.79 MB; numpy twin from the file = torch on 20/20 real lines; 16/20 lines exact; 55 ms/line in numpy.

## Final review

- Final review: self-review (no subagent: this session spawns agents only when the user asks). Package review-620f268..cf230d0.diff, Swift files read in full (HandwritingModel, InkLine, Reading, TextPlacement, HandwritingConverter/EditorModel/CanvasView/StrokeFont/AppSettings/ToolPalette diffs); every signature they use checked against its declaration. No Critical or Important finding.
- Final: minor (deferred): StrokeFont.raisedForms picks between two raised forms of the same base in dictionary order (nondeterministic if the table ever holds both).
- Final: minor (deferred): readWithModel always runs Vision on the batch as well (about 0.1–0.3 s), even when the model's reading is certain — could skip Vision when the best beam is far ahead.
- Final: minor (deferred): the convolution unrolls the image into a temporary buffer of up to ~22 MB for the longest line (1600 px) — fine on iPad, could be tiled.
