# Batch 5 — Study Tools Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build the NotebookLM parts that were deferred from Batch 3, generated from the same sources as the video overviews: flashcards with spaced repetition, a quiz, a mind map and a study guide.

**Architecture:**
- **Models and pure logic:** Foundation-only files, compiled and tested with Windows Swift (`tools/swiftcheck`):
  - `StudyModels.swift`
  - `SpacedRepetition.swift`, an Anki-like scheduler
  - `StudyOffline.swift`, the keyless generator
  - `MindMapLayout.swift`
- **Generation:**
  - `StudyWriter.swift` gathers the material the way the Studio does.
  - It then writes with the on-device model (`@Generable` drafts, language-checked like the video scripts), with Claude (JSON, optional) or offline.
- **Storage and screens:**
  - `StudyStore.swift` keeps the sets and runs one job at a time.
  - `StudyViews.swift` holds the create sheet, the cards in the library and the four players.

**Spec:** the roadmap's Batch 3 line ("flashcards, quiz, mind map, report"), deferred in `docs/superpowers/plans/2026-10-21-batch-3-ai-video-voices.md`. Item 21 asks to beat NotebookLM wherever Mürekkep is weaker.

## Global Constraints

- No API key in the product; Claude stays optional.
- Turkish and English. Every string goes through `Loc.t` with an English entry, and each set is in one language (chosen, never automatic).
- Nothing blocks the main thread: reading, writing and layout run off it.

## Tasks

1. **SpacedRepetition**
   - Learning steps of 1 min and 10 min.
   - "Good" twice graduates a card to 1 day; "easy" to 4 days.
   - In review: "again" relearns after 10 min with half the interval and 0.2 less ease (never below 1.3); "hard" ×1.2; "good" ×ease; "easy" ×ease×1.3 with 0.15 more ease.
   - swiftcheck cases cover each of these.
2. **StudyOffline**
   - Definitions (TR "… denir / adı verilir / olarak tanımlanır", EN "is defined as / refers to / means", "Term: definition" lines) become cards.
   - Key sentences become cloze cards and multiple-choice questions, with the other key terms as distractors.
   - Headings become the branches of the mind map; key sentences, terms and questions make the guide.
   - swiftcheck cases on Turkish and English samples.
3. **MindMapLayout**
   - A tidy tree from left to right: children one column right of their parent, the parent centred on them, no overlap.
   - A collapsed node hides its subtree.
   - swiftcheck cases.
4. **StudyWriter + StudyStore**: on-device drafts, the Claude JSON path, the offline path; persistence and jobs.
5. **Screens**
   - A create sheet (kind, sources, language, count, writer).
   - Flashcards: flip, rate with the next intervals shown, a due count.
   - Quiz: answer, explanation, score, retry the wrong ones.
   - Mind map: pinch zoom, tap to fold.
   - Guide: share as text.
   - Library entry points sit next to the video and audio cards.
6. **Delivery**: build 18, zip, rulings.
