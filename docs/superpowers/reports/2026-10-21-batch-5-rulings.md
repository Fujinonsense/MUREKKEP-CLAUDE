# Batch 5 — rulings (study tools, build 18)

Plan: `docs/superpowers/plans/2026-10-21-batch-5-study-tools.md`.
Branch: `murekkep-5-study-tools`, cut from `murekkep-4-feel-speed`. It is not merged into `main`.

## What changed

Four study tools sit next to the video and audio overviews. They are made from the chosen sources, in the background and one at a time:

- **Flashcards** with Anki-like spaced repetition:
  - Learning steps of 1 and 10 minutes, graduation to 1 or 4 days.
  - Each rating button shows when the card comes back.
  - Cards in a learning step come back in the same session.
- **Quiz:** four choices, the right answer with its reason, the best score kept, the wrong answers asked again.
- **Mind map:** a tidy tree, pinch to zoom, tap to fold, each branch in its own colour.
- **Study guide:** the gist, each part's main points, terms and questions; shared as text.

Writers:
- The on-device model writes part by part in structured drafts, and each draft is checked for its language.
- Claude writes one JSON reply (optional; needs a key).
- The keyless writer fills whatever a model leaves empty.

The pure parts are compiled and checked with Windows Swift: `SpacedRepetition` (11 checks), `StudyOffline` (9) and `MindMapLayout` (5).

## Rulings

- **SM-2 with learning steps rather than FSRS.** It is predictable and well known, and needs no history to fit. Cost if wrong: a few more reviews than FSRS would ask.
- **The keyless writer only keeps bare nouns as key words.** Turkish verb forms and possessive/genitive endings are dropped, because "kullanılır" or "fonksiyonun" make poor blanks. The bare genitive "-in/-ın" is kept, since excluding it would also drop nouns like "protein". Cost if wrong: a few blanks on inflected forms ("türevin").
- **No downloadable MLX model in this batch.** It adds a large native package that cannot be compiled here. If the CI build broke, the fallback build would also lose the voices and the Apple model. The stronger brain stays the user's own computer (Ollama / LM Studio, already supported). Cost if wrong: no offline brain stronger than Apple's on the iPad yet.
- **The study tools have their own store (Documents/Murekkep/Study/sets.json).** The Overview model is left untouched, so no video or audio code path changes. Cost if wrong: two lists to keep in step if the Studio is reorganized later.

## Not verified here

- The SwiftUI screens and the FoundationModels drafts are written against the documented APIs (`@Guide` with `.count`, `.range`, `.maximumCount`), but they have not been compiled.
- The first full build is the GitHub workflow.
