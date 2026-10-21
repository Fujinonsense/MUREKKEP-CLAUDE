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

**Study tools.** Flashcards, quizzes, mind maps and guides can be written by the downloaded model, from the same JSON prompt as Claude. Video and audio overviews stay with Apple's model.

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
- **Video and audio overviews do not use the downloaded model.** A 10-minute script runs to thousands of tokens, about 15–20 minutes at iPad speed. Cost if wrong: the overviews are only as strong as Apple's model.
- **If the downloaded model fails to start, Auto falls back to Apple's model for that answer.** A question is never left unanswered when another on-device brain is there. Cost if wrong: the fallback can hide a model problem. The answer says that it fell back, and why.
- **The serif is only for titles.** Body text, answers and controls stay in the system font for legibility. Cost if wrong: none for reading; the look is milder than a full serif.

## Not verified here

- Nothing in this batch has been compiled yet.
  - If the MLX packages fail in CI, the workflow falls back to the build without MLX. The IPA then has the old brains, and Settings says MLX is missing from that build.
  - The new look can only be judged on the iPad.
