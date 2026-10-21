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
