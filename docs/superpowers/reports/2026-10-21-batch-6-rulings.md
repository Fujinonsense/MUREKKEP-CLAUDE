# Batch 6 — rulings (downloadable brain and new look, build 21)

Branch: `murekkep-6-device-brain`, cut from `murekkep-5-study-tools`. It is not merged into `main`.

## What changed

**Downloadable model.** The iPad downloads an open model once and runs it itself on its GPU (MLX). Nothing goes to a computer or a server.
- Which model is decided by the iPad's memory:
  - 16 GB: Qwen3.5 9B (6.0 GB download)
  - 8 GB: Qwen3.5 4B (3.1 GB)
  - 6 GB: Qwen3.5 2B (1.7 GB)
- Settings > AI brain downloads it. The assistant also offers it until it is on the iPad.
- The download resumes where it stopped (HTTP Range), is kept out of the iCloud backup, and checks free space first.
- The Auto engine picks, in order: the downloaded model, Apple Intelligence, the offline core.
- The computer's server is no longer part of Auto. It sits under Settings > Advanced, and "find my computer" is gone.

**Solving.**
- The downloaded model thinks before it answers: up to 2,048 tokens on arithmetic, 768 on reading questions, 1,536 for "check my solution".
- It ends each answer with "Cevap: X", and the app reads that line for the choice.
- Textbook exercises go one whole exercise at a time.
- Apple's model now answers a multiple-choice question up to three times and the majority wins. The third answer is asked only when the first two disagree.

**Study tools.** Flashcards, quizzes, mind maps and guides can be written by the downloaded model, from the same JSON prompt as Claude. Video and audio overviews stayed with Apple's model in this build; build 23 gives them to the downloaded model too (see below).

**Look.** The palette comes from the name: blue-black ink on cool notebook paper.
- The library sits on faint ruled paper.
- Titles use the New York serif.
- Cards have ink hairlines and ink-tinted shadows.
- Flashcards are index cards.
- Assistant answers read as notes marked in the margin, and the student's own messages are in their ink.
- The accent is lighter at night (contrast 4.6:1 on the dark paper, was 3.4:1).

**Build.** The workflow builds in three tiers, each tried only if the one before fails:
1. Full build: voices, Apple's model and MLX (mlx-swift 0.32.3, mlx-swift-lm 3.32.3, swift-transformers 1.3.5, pinned exactly).
2. Without MLX: voices and Apple's model kept.
3. Plain build.

The Metal toolchain is installed first when missing.

## Checks run here

- Pure parts in Python twins and Windows Swift: `BrainCatalog` (memory → model, file filter, thinking split, choice reading, budget), 16 Swift checks.
- `pytest tests` passes: 180 passed, 4 skipped.
- `balance.ps1` passes on every changed file.
- The workflow's project generation was simulated: the full project has the four products, the no-MLX project has none.
- The MLX calls were written against mlx-swift-lm 3.32.3's own source: `ModelConfiguration(directory:)`, `LLMModelFactory.loadContainer(from:using:configuration:)`, `ChatSession(…components:additionalContext:)`, `GenerationComponents.applyingThinkingBudget`, `Memory.cacheLimit`. They have not been compiled.

## Rulings

- **Qwen3.5 over Gemma 4 E4B.** Qwen3.5 4B scores far higher on reasoning (MMLU-Pro 79, GPQA 76) and is a 3.1 GB download, against 5.2 GB for Gemma 4 E4B. It covers 200+ languages, Turkish among them, and mlx-swift-lm supports it. Cost if wrong: Gemma's Turkish prose might read more naturally in long answers.
- **The 9B needs 7.2 GB free for the app at launch, besides 11.5 GiB of memory.** Without the increased-memory entitlement (an unsigned IPA cannot carry one), iOS may stop an app that holds too much. Loading also checks free memory and refuses with a message instead of crashing. Cost if wrong: a 16 GB iPad may be offered the 4B.
- **The app downloads the files itself instead of using swift-huggingface.** That means one less package, no macros, a resumable Range download and a known folder. Cost if wrong: our own code for one HTTP request type.
- **Thinking is capped with Qwen's own early-stop phrase.** Qwen3.5 declares no budget transition, so the one Qwen3 was trained with is used. Cost if wrong: an answer cut short could lean on half-finished thinking. The thinking text's last paragraph is the fallback answer.
- **The model stops when the app goes to the background.** The GPU may not be used there, and the app waits up to 0.8 s for the answer to stop. An idle model is unloaded on a memory warning or in the background. Cost if wrong: the first answer after coming back loads the model again (a few seconds).
- ~~**Video and audio overviews do not use the downloaded model.**~~ Reversed in build 23: the 15–20 minute estimate was wrong. The script is written without thinking: about 3,600 tokens for a standard (7-minute) Turkish overview, at most 7,000 for a long English one. At 20–40 tokens a second that is about 2–6 minutes; this has not been timed on an iPad.
- **If the downloaded model fails to start, Auto falls back to Apple's model for that answer.** A question is never left unanswered when another on-device brain is there. Cost if wrong: the fallback can hide a model problem. The answer says that it fell back, and why.
- **The serif is only for titles.** Body text, answers and controls stay in the system font for legibility. Cost if wrong: none for reading; the look is milder than a full serif.

## Not verified here

- Nothing in this batch has been compiled yet.
  - If the MLX packages fail in CI, the workflow falls back to the build without MLX. The IPA then has the old brains, and Settings says MLX is missing from that build.
  - The new look can only be judged on the iPad.

## Build 22: the text pen checked end to end

**What was wrong.** The line finder treated any letter-size stroke outside a line's middle band as the start of a new line. Letters drawn in several strokes made spurious lines:
- a y's tail drawn on its own
- the top bowl of a B
- a piece of an ascender

On held-out handwriting fonts written as real pen strokes (`tools/textpencheck/gen_cases.py`, 531 writings, level and turned pages, one and two lines), the right number of lines came out in 217. This is the "Neler" + "l" + "oyor?" failure the user saw.

**Fix** (Python twin first, with failing tests, then `InkLine.swift`):
- A stroke above or below every band joins the line it stands beside, within 1.2 band heights.
- Lines split while reading are joined again.
- The slope is capped at 5°, because the ink is levelled first.
- Boxes come from the points, not from the pen's radius.

**Result:**
- Right line count: 515/531.
- Exact readings: 361/531 (was 156).
- Two stacked lines kept apart better than before at every spacing tried, down to 1.1 line heights (143/165, against 46 for the old finder).
- `tools/split_stress.py`: 0 wrong in 1,274 one-line and 130 two-line cases.

**Checked in the app's own Swift.** `tools/textpencheck/run.ps1` compiles the real `InkLine.swift`, `HandwritingModel.swift` and `InkDeskew.swift` with Windows Swift (stand-ins for `vDSP_mmul` and the CoreGraphics bitmap context) and compares them with the Python twins:
- Same lines in all 531 cases.
- The network's log-probabilities on the same image differ by at most 0.015, and the beam gives the same text.
- The renderer differs from PIL by 0.016 per pixel on average.
- A 2.6 pt pen radius changes nothing.

### Rulings

- **Boxes without the pen's radius.** A 3D ink's radius made dots and accents look like letters. The Python twin never had the radius, so its measurements now describe the app. Cost if wrong: none found; the radius carries no information about the writing.
- **Slope at most 5° instead of 12°.** The text pen levels the ink with `InkDeskew` before it looks for lines, and a slope fitted from pieces of letters swung up to ±12° and moved the band 20 pt at the line's start. Cost if wrong: a line whose own baseline drifts more than 5° from the page's levelled direction may lose its last letters to a second line; the existing 8° tilted-line test still passes.
- **Lines whose letters sit within a bigger line's reach are merged.** Two real lines closer than about 1.45 x-heights could be merged. Cost if wrong: such tight lines read as one.
- **The test cases use font skeletons chained into pen strokes.** Real hands differ. On the iPad, Apple Vision's readings and the system dictionary also compete with the model; here the dictionary was approximated with word frequency lists (exact readings 369/531).

## Build 23: handwriting-font data, a pen-motion reader, overviews by the downloaded model

**Handwriting-font generator.**
- `fetch_handfonts.py` downloads the twelve families asked for from google/fonts (16 files):
  - Shantell Sans, Playpen Sans, Caveat, Mynerve, Delicious Handrawn, Patrick Hand, Kalam, Shadows Into Light Two
  - English only: Reenie Beanie, Cedarville Cursive, Gloria Hallelujah, Indie Flower
- All but Reenie Beanie cover ç ğ ı İ ö ş ü. Turkish text only goes to the fonts that do.
- `wordlists.py` writes Turkish (30,000 words, 83 % with a Turkish letter; 60,000 phrases) and English (20,690 words; 60,000 phrases) lists.
- `font_lines.py` draws a line whole:
  - a random font and size
  - random letter spacing
  - a wandering, wavy baseline and a shear
  - an elastic field (SciPy, smoothed noise)
- Then it redraws the line as the app draws ink, so the model sees what it sees on the iPad.
- 30 % of training lines come from it.
- Fine-tuned from main5 for 30,000 steps:
  - validation CER 3.18 % → 3.08 %
  - text pen cases read exactly in the app's own Swift: 361 → 376 of 531

**Pen-motion reader (online HTR).** The text pen now also reads how the pen moved, not only the picture.
- Input: for each point every 0.1 line heights along the strokes, in drawing order:
  - the move (dx, dy) in line heights
  - its direction (sin θ, cos θ)
  - whether the pen came down there
- Training data has no fonts. The Kinematic Stroke Generator (`kinematic.py`) writes with the app's single-line font, whose strokes are in drawing order, made to run the way a hand runs them:
  - downstrokes from the top
  - crossbars from the left
  - loops anticlockwise
- It then makes the writing sloppy:
  - moved control points and a smooth random field
  - Catmull-Rom splines sampled with minimum-jerk timing
  - strokes now and then reversed or reordered, letters joined
- Dots, accents and cedillas (ç ğ ı İ ö ş ü, i, j, ! ? : ;) are pen-up strokes. They come right after their letter or, as often, once the word is done, and land a little off.
- A quarter of the training lines are handwriting-font skeletons chained into pen trails, so unusual stroke orders are seen too.
- Network: three 1-D convolutions, two bidirectional LSTM layers of 160, CTC. 2.3 MB as float16 (`hwonline.bin`).
- `OnlineReader.swift` is a line-by-line transcription. On the text pen cases:
  - its features match the Python twin within 0.00012
  - its log-probabilities match within 0.0007, and it reads the same text on all 583 lines
- Both readers propose readings and both score every candidate (`Reading.choose`):
  - The pen's say is `onlineWeight × log P / length`, measured from its best candidate.
  - It never goes below `onlineFloor`, so a reading the pen-motion reader cannot follow (three dots in a handful of points) is outvoted, not thrown out.
- Trained 60,000 steps (`runs/online1`). Best validation, step 56,000:
  - CER 0.24 % on generator lines from an unseen seed
  - CER 8.2 % on held-out font trails
- The weight was chosen on two case sets (`tools/textpencheck/online_cases.py --grid`, then the app's Swift):

| Set | Picture alone | Pen motion alone | Both (weight 0.5, floor −4) |
|---|---|---|---|
| 531 held-out font skeletons (unnatural stroke order) | 376 | 199 | 376 |
| 400 sloppy generator lines (a hand's order, unseen seed) | 151 | 333 | 305 |

- Rule: the largest weight that keeps the font cases at or above the picture reader alone. Weight 0.75 gains 16 more generator lines but loses 2 font cases.

**Overviews.** Auto now gives video and audio overviews to the downloaded model as well (the ruling above is reversed).
- It writes the same script Claude writes, from excerpts of every source (about 14,000 characters).
- If it fails or answers in the other language, Apple's model and then the offline writer take over.

**Solving accuracy.** Qwen3.5 4B (the 8 GB iPad's model) answered 40 exam-style multiple-choice questions written for this, the way the app asks:
- The questions:
  - 24 YKS-style math in Turkish, keys checked with sympy
  - 16 YDS / prep-school English: grammar, vocabulary, a reading passage, restatement, dialogue, translation
- The app's settings:
  - its instructions
  - thinking up to 2,048 tokens on arithmetic and 768 otherwise
  - Qwen's "answer now" transition
  - temperature 0.6, top-p 0.95, top-k 20
  - at most 400 answer tokens
- Run in PyTorch bf16 instead of MLX 4-bit (`C:/Users/orsyu/mrk-ml/textpen/brain_eval`).
- Result: 39/40 right. The one miss was the reading of the answer, not the reasoning. The model went through every option ("D) 4: Doğru.") and ran out of answer tokens before "Cevap: D". The app now reads such a verdict list (`ThinkingText.choice`), which makes it 40/40 on the stored answers.
- Nearly every question used the whole thinking budget and still came out right.
- Word problems without operators (work, sequence, geometry) get the 768 budget and were right too.

Not covered by this:
- reading the questions off a page (the text layer, OCR and the question splitter)
- the 9B and 2B models
- harder exams

### Rulings

- **The pen-motion reader votes; it does not replace the picture reader.** Its training writing is synthetic: the app's own letters, moved about. Real hands are not in it, and no real online handwriting with a license that allows this use was at hand (BRUSH is non-commercial; IAM-OnDB needs registration). Cost if wrong: a hand far from the generator's gets little help from it, but the floor keeps it from overruling a sure picture reading.
- **The line height for pen features comes from points spaced along the ink, not from the pen's samples.** A slow pen gives many more samples where it lingers, which moved the 5th–95th percentile by about 3 %. Cost if wrong: none found; the spaced points describe the shape alone.
- **main6 replaces main5.** It is better on both measures: validation 3.08 % against 3.18 %, and 376 exact readings against 361. Cost if wrong: the 30 % of font-image lines trade some stroke-font accuracy for variety. On held-out stroke fonts it still came out ahead.
- **The option-by-option verdict is read only when no answer line is.** Exactly one option must be called right ("Doğru" / "Correct", not "doğru değil"). Cost if wrong: a reply that calls one option right in passing and never states its own choice could be shown that option.

### Checks run here (build 23)

- `pytest tests`: 238 passed, 1 skipped.
- `tools/swiftcheck/run.ps1`: all passed, with the six new choice vectors.
- `tools/textpencheck/run.ps1` with both models: all checks passed on the 531 cases and the 400 generator lines.
- `tools/balance.ps1` on every changed Swift file.
- Request audit (`C:/Users/orsyu/mrk-ml/textpen/audit.py`): evidence in code for 50 of 50 requests. The Turkish checklist is `2026-10-21-istek-kontrol-listesi.md`.

### Not verified here (build 23)

- No build since 15 has been compiled by CI. The calls into MLX, Vision and UIKit are checked only by reading their sources and docs.
- The text pen has not been tried with a real hand on the iPad. Both readers were measured on synthetic writing only.

## Build 24: the text pen measured on the user's own handwriting

Build 23 on the iPad read the user's writing badly. With the text pen:
- `"Aga naber?"` became `...Asanaber?`
- `Kardeşimin tableti kırıldı` became `Kardeş^TiminFablesikınıdı`

Every measurement so far had been on synthetic writing. The user then exported a page of 16 known sentences as a PDF. The app writes each stroke into the PDF as vector segments, in the order the strokes were written, so the real pen data came out exactly (`tests/fixtures/real_hand_user.json`).

**What was wrong, measured on those 16 lines** (`C:/Users/orsyu/mrk-ml/textpen/real`):

| Stage | Problem | Fix |
|---|---|---|
| Text pen batches | It turned writing into text after every 1.3 s pause, so a line written slowly was read a word at a time: "Aga" alone read "Asa", and the pieces were typeset without spaces. The same ink read at once was right. | When new writing goes on the line just read (same line, within 15 s), the whole line is read again together (`TextPenBatch`). |
| Exponents | 14 groups in lines without any exponent: dots and ticks beside letters, apostrophes, ğ's breve, typeset as `^D`, `⁽`, `¹`, `ⁱ`. | An exponent group needs a stroke drawn with at least 1.1 letter heights of pen. |
| Lines | 5 of 16 one-line writings were split, by a slope fitted from letter pieces and carried across wide word gaps, and by an "Ö" whose dots made its own band. | The slope is not carried past a letter beyond the recent letters; lines whose letters' middles are within half a letter are joined; a letter with its accents joins the line it ends in. 16/16 now, in Python and in the app's Swift. |
| Picture reader | CER 26.8 % on the user's hand (synthetic validation 3.1 %). | Fine-tuned on 11 of the lines (copies turned, sheared, bent), 25 % of each batch (`runs/user1`, step 1,500). |
| Pen-motion reader | CER 44.7 %; together with the fine-tuned picture reader it made things worse. | Fine-tuned on the same lines in their real stroke order (`runs/online-user1`). |

**Held-out lines** (4 PDF lines never trained on: "Kardeşimin tableti kırıldı.", '"Aga naber?" dedi, güldü.', "Yarın saat 9:30'da sınav var!", "Pack my box…"):

| Reader | Before | After |
|---|---|---|
| Picture reader | 17.6 % (6 held-out lines with the 2 screenshot lines) | 5.0 % |
| Pen-motion reader | 34.7 % | 12.4 % |
| Both (weight 0.5) | 7.4 % with the old pen reader | 4.1 % |

The app's dictionary repair (`Spelling.repair`: kardesimin → kardeşimin) is not in these numbers.

**Synthetic cases**, in the app's own Swift (`tools/textpencheck`, 531 held-out-font writings):

| | Build 23 | Build 24 |
|---|---|---|
| Picture reader alone, exact | 376 | 393 |
| Both readers, exact | 376 | 401 |
| Right line count | 515 | 518 |

The pen-motion reader matches Python on all 580 lines, and every parity check passed. On the 16 real lines (11 of them trained on, so optimistic), 11 now read exactly, against 0 before.

### Rulings

- **The readers are tuned to this user's hand.** Synthetic font cases read slightly worse with the tuned picture reader (401 → 391 exact before the pen reader joins). The app has one user, and on their writing the error fell by more than two thirds. Cost if wrong: another person's handwriting reads a little worse than with build 23's model.
- **Step 1,500 over step 3,750.** It is better on the held-out real lines (5.0 % against 6.3 %); the later one was better on synthetic fonts (395 against 391). Cost if wrong: one character in 160 either way; the held-out set is small.
- **Six held-out lines are few.** More pages from the user (a PDF export is enough) would make the measurement and the tuning stronger. Cost if wrong: the 4.1 % may not hold for words the lines do not contain.
- **Merging "a letter with its accents" costs one case in 165 of two lines stacked at 1.1 line heights** (142 against 143). Lines that close are nearly touching. Cost if wrong: such tight lines merge a little more often.
