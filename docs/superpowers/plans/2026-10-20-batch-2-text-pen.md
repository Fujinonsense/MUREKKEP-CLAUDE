# Batch 2 — Text Pen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The text pen reads ugly Turkish and English handwriting (ı/İ, ş, ğ, ç, ö, ü, quotes, commas, math, superscripts) with Mürekkep's own model, places the typed words where they belong, has a text size option, and works the same with 3D pens.

**Architecture:** A CRNN-CTC line recognizer (~2.4 M parameters) is trained on the local RTX 5080 from synthetic lines: skeletons of 380 OFL handwriting fonts plus the app's own `StrokeFont`, made "ugly" by augmentation. On the iPad the strokes of a line are redrawn at a fixed thickness (so every brush, 3D or not, looks the same to the model), run through a pure-Swift Accelerate implementation of the network (weights in `Assets.xcassets/hwmodel.dataset`), decoded with CTC beam search, and Apple Vision's readings are rescored with the model's CTC likelihood and the dictionary. Every Swift algorithm has a Python/numpy twin in `tests/` or `ml/handwriting/`; the numpy twin of the network is checked against PyTorch.

**Tech Stack:** Swift 5 mode, Accelerate (`vDSP_mmul`), Vision, Core Graphics; Python 3.12, PyTorch 2.11 + CUDA 12.8 (`C:/Users/orsyu/mrk-ml/.venv`), numpy, Pillow, scikit-image, fontTools.

**Spec:** The user's message of 20 Oct 2026, items 1, 2, 3, 4 (done), 5, 6 (text size), 10, and Sci's "handwriting/math to text" request; roadmap `docs/superpowers/plans/2026-10-20-murekkep-3-roadmap.md` (Batch 2 row, key decisions).

## Global Constraints

- No API keys; nothing leaves the device. Claude stays only as the existing optional setting (`handwritingAccess`).
- Every new UI string through `Loc.t` with an English entry in `Translations.swift` part9.
- `InkShaders.swift` is not touched in this batch.
- Model weights ship as an asset catalog data set (`NSDataAsset(name: "hwmodel")`), like `kagit-*.dataset`; when the asset is missing or unreadable the text pen falls back to today's Vision path.
- Training data and runs stay outside the repo: data `C:/Users/orsyu/mrk-ml/data`, cache `C:/Users/orsyu/mrk-ml/cache`, runs `C:/Users/orsyu/mrk-ml/runs`. Only code and the exported `hwmodel.bin` are committed.
- Default tests: `uv run --quiet --with pytest --with numpy --with pillow pytest tests -q`. Torch tests (`pytest.importorskip("torch")`) run with `C:/Users/orsyu/mrk-ml/.venv/Scripts/python.exe -m pytest tests -q`.
- No Swift compiler here: `tools/balance.ps1` on every changed Swift file; CI is the compile check.

## Shared definitions (used by several tasks)

- **Charset** (`ml/handwriting/charset.py: CHARSET`, index 0 is the CTC blank, then these characters in this order):
  `" abcdefghijklmnopqrstuvwxyzçğıöşüABCDEFGHIJKLMNOPQRSTUVWXYZÇĞİÖŞÜ0123456789.,;:!?'\"()[]{}-_/\\%&+=*<>#@$€°^|×÷±√π≈≠≤≥∞→∫Σ∏∂Δαβγδθλμσφωε"`
  The charset travels inside `hwmodel.bin`; Swift never hard-codes it.
- **Line image** (`InkLine.render` in Swift, `ml/handwriting/ink_render.py: render_line` in Python): height 48 px; core band = 5th…95th percentile of all point y; scale = 30 / max(coreHeight, 1) points→px; core top drawn at y = 9; x starts at 4 px; width = ceil(inkWidth·scale) + 8 rounded up to a multiple of 4, at least 16, at most 1600; ink 1.0 on 0.0; line width 2.4 px, round caps, antialiased; the brush and its width are ignored.
- **Network** (`ml/handwriting/model.py: CRNN`): conv3×3(1→32)+BN+ReLU, maxpool 2×2; conv(32→64)+BN+ReLU, maxpool 2×2; conv(64→128)+BN+ReLU; conv(128→128)+BN+ReLU; maxpool (2,1); conv(128→192)+BN+ReLU; conv(192→192)+BN+ReLU; maxpool (2,1) → 3×(W/4)×192 → per column 576 features (channel-major: c·3 + h); BiLSTM(576→160); BiLSTM(320→160); Linear(320→len(CHARSET)+1); log-softmax. Gate order i, f, g, o (PyTorch).
- **hwmodel.bin**: `b"MRKHW1\0\0"`, u32 version = 1, u32 charset byte count, UTF-8 charset, u32 tensor count, then per tensor: u32 rank, u32 dims…, fp16 little-endian values. Tensor order: for each conv (BN folded) weight [out,in,3,3], bias [out]; for each LSTM layer and direction (forward, backward) W_ih [640,in], W_hh [640,160], bias [640] (= b_ih + b_hh); linear weight [C,320], bias [C].

## Review Focus

- A batch that is a single letter or mark ("ı", "a", ",", ".", "?") — must become that character, joined to the previous word without a space when it is punctuation, never a random word. → Task 6 test `test_lone_marks_stay_marks`.
- All-caps and mixed-language lines ("İSTANBUL'DA NASA", "Ödev: read p. 42") — İ must not become I, the apostrophe must survive. → Task 3 test `test_caps_and_apostrophes_sampled`, Task 6 test `test_caps_reading_kept`.
- A line written uphill or downhill (5–10°) — one line, not two, and the normalization still centres it. → Task 2 test `test_tilted_line_is_one_line`.
- Very big (cap 60 pt) and very small (cap 6 pt) writing — same image size and core height. → Task 1 test `test_size_does_not_matter`.
- The model asset missing in a Swift Playgrounds build — the text pen still works through Vision, no crash. → Task 5 step "missing asset" and Task 6 test `test_vision_only_when_model_missing`.

---

### Task 1: Line image and 3D-pen independence (items 1, 5)

**Files:**
- Create: `ml/handwriting/charset.py`, `ml/handwriting/ink_render.py`, `Murekkep.swiftpm/InkLine.swift`
- Test: `tests/test_ink_render.py`

**Interfaces:**
- Produces (Python): `render_line(strokes: list[list[tuple[float, float]]]) -> np.ndarray` (float32, 48×W); `line_transform(strokes) -> (scale, dx, dy)`.
- Produces (Swift): `struct InkLineImage { let width: Int; let pixels: [Float] /* row-major 48×width */; let scale: CGFloat; let origin: CGPoint }`, `enum InkLine { static func render(_ strokes: [Stroke]) -> InkLineImage? }` (CGContext DeviceGray 8-bit, same constants as Shared definitions).

- [ ] **Step 1: Failing tests** — `test_core_band_is_30px_from_y9` (core of a synthetic line maps to rows 9…39 ±1); `test_size_does_not_matter` (the same word at cap 6 pt and 60 pt → same width ±4 px and same core rows); `test_pen_width_is_ignored` (identical points drawn as lava width 7 and pen width 2.2 → identical arrays); `test_width_is_multiple_of_4_and_clamped` (16 ≤ W ≤ 1600).
- [ ] **Step 2: Run** `uv run --quiet --with pytest --with numpy --with pillow pytest tests/test_ink_render.py -q` — Expected: FAIL (module missing).
- [ ] **Step 3: Implement** `render_line` with Pillow at 4× supersampling (line width 9.6 px) and box downsampling; `charset.py` with `CHARSET` and `encode(text) -> list[int]` (+1 offset for blank).
- [ ] **Step 4: Run** — Expected: PASS.
- [ ] **Step 5: Implement** `InkLine.render` in Swift with the same constants (percentiles over all points, scale, offsets, width rule, 2.4 px line). Balance check.
- [ ] **Step 6: Commit** `feat: one line image for every pen (the model's input)`.

### Task 2: Lines, dots and superscripts from strokes (items 2, 10)

**Files:**
- Create: `tests/ports/inkline.py`, `tests/test_line_segmentation.py`
- Modify: `Murekkep.swiftpm/InkLine.swift`

**Interfaces:**
- Produces (Swift): `static func lines(_ strokes: [Stroke]) -> [[Stroke]]` (top to bottom); `static func splitRaised(_ line: [Stroke]) -> (base: [Stroke], raised: [(strokes: [Stroke], x: CGFloat)])`.
- Algorithm (port both): a stroke's core = its y-extent; strokes whose height < 0.35 × median letter height are *marks*. Non-mark strokes join a line when their vertical overlap with the line's core band ≥ 40 % of the smaller height (band follows the line's slope: fit y = a·x + b over member centres once ≥ 3 members). Marks join the line whose band (extended 0.8 × core height up and down) contains them and that overlaps them horizontally; if none, the nearest line. A *raised* group: strokes of a line whose bottom < coreTop + 0.3·coreHeight, whose height < 0.65·coreHeight, that start right of some base ink, and that are not a dot/accent over a letter (a dot is a mark lying horizontally inside a base stroke's x-extent).

- [ ] **Step 1: Failing tests** — `test_two_lines`; `test_i_dots_and_cedillas_stay_on_their_line` (ı/i dots, ş cedilla, ğ breve, ü dots); `test_tilted_line_is_one_line` (8° uphill sentence); `test_superscript_detected` ("x" then a small raised "2" → raised group with x after the x); `test_i_dot_is_not_a_superscript`.
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement** the port, then the Swift twin with the same thresholds.
- [ ] **Step 4: Run** — Expected: PASS. Balance check.
- [ ] **Step 5: Commit** `feat: handwriting lines, dots and superscripts found from the strokes`.

### Task 3: Synthetic ugly handwriting (items 1, 2)

**Files:**
- Create: `ml/handwriting/strokefont.py`, `ml/handwriting/glyphs.py`, `ml/handwriting/texts.py`, `ml/handwriting/synth.py`
- Test: `tests/test_synth.py`

**Interfaces:**
- `strokefont.glyphs() -> dict[str, (advance, paths)]` parsed straight from `Murekkep.swiftpm/StrokeFont.swift` (`source` table, same arc rules).
- `glyphs.font_glyphs(ttf_path, chars) -> dict[str, list[np.ndarray]]` — skeleton point sets of each glyph rendered at 128 px (skimage `skeletonize`), cached as `.npz` in `C:/Users/orsyu/mrk-ml/cache/glyphs/`; Turkish letters a font lacks are composed: ş/ç = s/c + cedilla hook, ğ = g + breve, ö/ü = o/u + two dots, ı = i without its topmost small component, İ = I + dot (and capitals likewise).
- `texts.sample(rng) -> str` mixing 45 % Turkish Tatoeba fragments (1–8 words), 35 % English, 10 % math (generated: `x + 3 = 5`, `∫ f(x) dx`, `√2 ≈ 1,41`, `a ≤ b`, `Σ aᵢ` without the subscript, `f(x) = 2x - 1`), 10 % short items (single words, numbers, dates, `"alıntı"`, `İSTANBUL'DA`, `p. 42`, `?!`, `...`).
- `synth.make_line(rng, font_pool) -> (np.ndarray image, str text)`: 70 % handwriting-font glyphs, 30 % StrokeFont; per-character scale 0.85–1.15, rotation ±6°, baseline jitter ±8 % x-height, slant −15°…+25°, spacing −15 %…+40 % of the advance, dot/accent offset ±15 % x-height, 5 % small breaks, 20 % cursive joins between lowercase letters, sine warp along x; then `render_line` with line width drawn from 1.6–3.4 px instead of 2.4.
- Fonts: sorted file list; every 9th font is held out for validation (`synth.split_fonts()`).

- [ ] **Step 1: Failing tests** — `test_strokefont_parse_matches_swift` (glyph count = number of keys in the Swift `source` table; "A" advance 7); `test_every_charset_char_drawable` (for 20 fonts, every CHARSET character gets ≥ 1 point set, composed or native); `test_caps_and_apostrophes_sampled` (10,000 samples contain İ, ı, ', ", ş, ğ, ∫, √); `test_make_line_shape` (48 rows; text encodes); `test_heldout_fonts_disjoint`.
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement** the four modules.
- [ ] **Step 4: Run** (default env plus `--with scikit-image --with fonttools`) — Expected: PASS; save 64 sample images to `C:/Users/orsyu/mrk-ml/runs/samples/` and look at them.
- [ ] **Step 5: Commit** `feat: synthetic ugly Turkish/English handwriting for training`.

### Task 4: Model, training and export (item 1)

**Files:**
- Create: `ml/handwriting/model.py`, `ml/handwriting/train.py`, `ml/handwriting/export.py`, `ml/handwriting/infer_np.py`
- Test: `tests/test_model_export.py` (torch; skipped without it)

**Interfaces:**
- `CRNN(num_classes)` as in Shared definitions; `export.write(model, path)` folds BN and writes `hwmodel.bin`; `infer_np.load(path) -> Weights`, `infer_np.log_probs(weights, image) -> np.ndarray [T, C]` doing exactly what Task 5's Swift does (im2col conv, ReLU, max pool, LSTM i/f/g/o, backward direction over reversed time, concat, linear, log-softmax).
- `train.py`: AdamW lr 1e-3, cosine to 1e-5, batch 48, bf16 autocast, CTC loss (`zero_infinity=True`), 12 data workers, width buckets, checkpoint every 2,000 steps to `C:/Users/orsyu/mrk-ml/runs/<date>/`, validation every 2,000 steps on 2,000 held-out-font lines: CER and Turkish-letter accuracy (ı ş ğ ç ö ü İ).

- [ ] **Step 1: Failing tests** — `test_numpy_matches_torch` (random-init model in eval, fp16-rounded weights; random 48×64 and 48×400 images → max |Δ log-prob| < 2e-3); `test_export_roundtrip` (header, charset, tensor count 2·6 + 3·4 + 2 = 26).
- [ ] **Step 2: Run** with the venv — Expected: FAIL.
- [ ] **Step 3: Implement** model, export, numpy reference.
- [ ] **Step 4: Run** — Expected: PASS.
- [ ] **Step 5: Train** in the background (`train.py --steps 120000`); continue with Tasks 5–8 meanwhile. Stop criterion: held-out CER ≤ 4 % and Turkish-letter accuracy ≥ 97 %, or 120,000 steps; take the best checkpoint.
- [ ] **Step 6: Export** the best checkpoint to `Murekkep.swiftpm/Assets.xcassets/hwmodel.dataset/hwmodel.bin` (+ `Contents.json` like `kagit-1.dataset`); size ≤ 6 MB; record CER in the ledger.
- [ ] **Step 7: Commit** `feat: Mürekkep's own handwriting model (CER <x> % on unseen fonts)`.

### Task 5: Swift network and CTC decoding (items 1, 2)

**Files:**
- Create: `Murekkep.swiftpm/HandwritingModel.swift`, `tests/ports/ctc.py`, `tests/test_ctc.py`

**Interfaces:**
- `final class HandwritingModel { static let shared: HandwritingModel?  /* nil when the asset is missing or bad */; let charset: [Character]; func logProbs(_ image: InkLineImage) -> [[Float]] }` — transcription of `infer_np.log_probs` with `vDSP_mmul`; runs off the main thread.
- `enum CTC { static func beam(_ lp: [[Float]], charset: [Character], width: Int = 8) -> [(text: String, score: Float)]; static func score(_ text: String, _ lp: [[Float]], charset: [Character]) -> Float? /* log P(text) by the forward algorithm; nil for characters outside the charset */; static func alignment(_ lp: [[Float]]) -> [Int] /* best-path frame per output character */ }`.

- [ ] **Step 1: Failing tests** (port) — `test_beam_finds_best_path` (hand-built lp where greedy ≠ beam); `test_repeated_letters_need_blank` ("ll", "ss"); `test_forward_score_matches_bruteforce` (all paths of a 5-frame, 3-class toy); `test_unknown_char_scores_none`.
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement** `tests/ports/ctc.py`, then the Swift twin; Swift network transcribed from `infer_np.py`. Missing asset: `shared` is nil, logged once.
- [ ] **Step 4: Run** — Expected: PASS. Balance check.
- [ ] **Step 5: Commit** `feat: the handwriting model runs on the iPad (Accelerate)`.

### Task 6: Reading a batch: model + Vision + dictionary (items 1, 2, 10, math)

**Files:**
- Create: `tests/ports/reading.py`, `tests/test_reading.py`
- Modify: `Murekkep.swiftpm/HandwritingConverter.swift` (`convert`), `Murekkep.swiftpm/Spelling.swift` (expose `score`)

**Interfaces:**
- `enum Reading { static func choose(model: [(text: String, score: Float)], vision: [(text: String, score: Float?)], length: Int, dictionary: (String) -> Double) -> String }` — each candidate's value = score / max(length, 1) + 0.6 × dictionary(text); Vision readings carry the model's `CTC.score` (nil → they compete on dictionary only with −∞ model part, so they win only when the model is missing); math lines (`PageOCR.mathScore ≥ 2` or `=`) use the model score alone.
- `convert` per line from `InkLine.lines`: base strokes → model beam + Vision lines overlapping the line → `Reading.choose`; raised groups → recognized alone, turned into StrokeFont superscript characters (`²`, `ⁿ`, …; a character without a superscript form becomes `^` + text) and inserted after the base character whose `CTC.alignment` x is nearest to the group's x; word boxes from the alignment.

- [ ] **Step 1: Failing tests** — `test_dictionary_breaks_ties` ("kucuk" vs "küçük"); `test_model_wins_on_math`; `test_lone_marks_stay_marks` ("," joined to the previous word, "ı" stays "ı"); `test_caps_reading_kept` ("İSTANBUL'DA" not lowercased or split); `test_superscript_inserted` ("x+y" with raised "2" after x → "x²+y"); `test_vision_only_when_model_missing`.
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement** the port, then `Reading` in Swift and the new `convert` path (the Claude path stays first when enabled; the model path replaces Vision-first; Vision-only when `HandwritingModel.shared == nil`).
- [ ] **Step 4: Run** — Expected: PASS. Balance check.
- [ ] **Step 5: Commit** `feat: the text pen reads with its own model, Vision and the dictionary`.

### Task 7: Where typed words go (item 3)

**Files:**
- Create: `Murekkep.swiftpm/TextPlacement.swift`, `tests/ports/placement.py`, `tests/test_text_placement.py`
- Modify: `Murekkep.swiftpm/HandwritingConverter.swift` (word loop), `Murekkep.swiftpm/EditorModel.swift` (`convertTextBatch` passes obstacles)

**Interfaces:**
- `enum TextPlacement { static func place(widths: [CGFloat], start: CGPoint, ruling: Ruling, space: CGFloat, obstacles: [CGRect]) -> [(x: CGFloat, line: Int)] }`. Obstacles = bounds of the page's other strokes in the line band [baseline − 1.25·cap, baseline + 0.35·cap].
- Rules: start on the line nearest the handwriting's baseline; if other ink on that line ends at most 3 caps left of the handwriting's start, start one space after it (the hand meant to go on); a word overlapping an obstacle moves to its right edge + one space; past `ruling.right` it wraps to the next line's left margin and is checked again; never above where it was written.

- [ ] **Step 1: Failing tests** — `test_no_overlap_with_existing_text`; `test_small_gap_closes_to_one_space`; `test_far_gap_is_kept` (≥ 3 caps: stays where written); `test_wraps_at_right_margin`; `test_wrap_skips_occupied_start`.
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement** the port, `TextPlacement`, and use it in `convert` (replacing the `continueFrom`-only rule; `continueFrom` becomes one more obstacle edge); `EditorModel.convertTextBatch` passes the page's other stroke bounds.
- [ ] **Step 4: Run** — Expected: PASS. Balance check.
- [ ] **Step 5: Commit** `fix: typed words never overlap and keep one space`.

### Task 8: Text size and 3D thresholds (items 5, 6)

**Files:**
- Modify: `Murekkep.swiftpm/AppSettings.swift` (`textPenScale`), `Murekkep.swiftpm/ToolPalette.swift` (`TextPenInspector`), `Murekkep.swiftpm/HandwritingConverter.swift` (`typedLayout`, `convert`), `Murekkep.swiftpm/CanvasView.swift` (`textPenSymbolSize`), `Murekkep.swiftpm/EditorModel.swift` (`isSmall` mark size), `Murekkep.swiftpm/Translations.swift`
- Create: `tests/test_text_size.py`

**Interfaces:**
- `AppSettings.textPenScale: Double` (UserDefaults "textPenScale", default 1.0; choices 0.8 "Küçük", 1.0 "Normal", 1.25 "Büyük", 1.5 "Çok büyük").
- `HandwritingConverter.capHeight(ruling: Ruling, scale: Double) -> CGFloat` = min(ruling.capHeight × scale, ruling.spacing × 0.72); used by the text pen and the Aa box.
- 3D: the hold-to-symbol size becomes max(28, 4 × pen width) and the late-mark size max(14, 3 × pen width), so thick pens' letters stay letters and their dots stay dots.

- [ ] **Step 1: Failing tests** — `test_scale_changes_cap`; `test_cap_fits_between_ruled_lines` (lined paper, 1.5 → ≤ 20.16); `test_thick_pen_thresholds` (lava 7 → 28 and 21).
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement** setting, inspector segmented picker "Punto" (Küçük / Normal / Büyük / Çok büyük), capHeight use, thresholds; English strings.
- [ ] **Step 4: Run** — Expected: PASS. Balance check.
- [ ] **Step 5: Commit** `feat: text pen size; thick 3D pens keep letters and dots`.

### Task 9: Deliver beta 2

- [ ] Version 3.0 build 14 (`Package.swift`, workflow); balance check of every Swift file; `Murekkep-3.0-beta2-iPad.zip` via `make-zip.ps1` (contains `hwmodel.dataset`); full test suites (default + venv); ledger; iPad checklist: ugly Turkish sentence with ı/ş/ğ, quotes and commas; "İSTANBUL'DA"; x² and ∫ f(x) dx; a word written right after typed text (one space, no overlap); text size Büyük; writing with lava, grass and galaxy; Swift Playgrounds build without the model still reads (Vision).
- [ ] Commit `chore: Mürekkep 3.0 beta 2 (build 14)`.
