# Mürekkep 3.0 Roadmap

> **For agentic workers:** This roadmap splits the work into four plans, one per subsystem. Use superpowers:executing-plans on each batch plan in order. Batch plans are written just before their batch starts, after reading the code they touch.

**Goal:** Fix every problem the user reported on 20 Oct 2026 (32 items, plus 2 requests from the Sci chat), and beat Notability, Notion and NotebookLM where Mürekkep is weaker.

**Architecture:** The app stays a SwiftUI + UIKit + Metal iPad app (`Murekkep.swiftpm`, iOS 17+). New native pieces join through the XcodeGen project the GitHub workflow builds: a Core ML handwriting model, sherpa-onnx/ONNX Runtime voices, and an optional MLX Swift vision-language model. All AI and speech run on the device; no feature asks for an API key.

**Tech Stack:** Swift 5 mode, SwiftUI, UIKit, Metal, Vision, PDFKit, AVFoundation, FoundationModels (iOS 26+, guarded), Core ML; PyTorch on the local RTX 5080 for training; GitHub Actions macOS 26 runner with Xcode 26.x for builds.

**Spec:** The user's message of 20 Oct 2026 (items 1–32) and the two Sci requests of 19 Oct 2026, recorded in this session's transcript. The baseline is commit `d319659` (2.9 + Sci's changes, rebuilt exactly by replaying Sci's operations).

## Global Constraints

- No API key anywhere in the product: remove the ElevenLabs/OpenAI key fields; Claude stays only as an optional setting the user already had.
- Turkish and English everywhere: UI already localized by Sci (`Loc.t`, `Translations.swift`); every new string goes through `Loc.t` and gets an English entry.
- The AI answers in the language of the question (item 8).
- Voices: female and male for Turkish and English, embedded in the app, never Siri voices.
- Pen sounds: quiet, per pen, and they never pause or duck music (`.ambient` + `.mixWithOthers`).
- `InkShaders.swift` is changed only for items 30 (lightning) and 31 (lava), nothing else in it.
- Zips for the iPad only through `make-zip.ps1` (forward slashes). IPA builds come from `.github/workflows/main.yml`.
- There is no Swift compiler on this PC: every batch ends with a CI build, and its errors are fixed before delivery.
- Algorithms that can be checked off-device (shape fitting, recognizer rules, text layout) get a Python test in `tests/` that ports the exact function.

## Batches

| Batch | Items | What the user gets |
|---|---|---|
| 1. Quick fixes | 4, 6 (go to page), 6 (text size, squeeze), 7, 8, 11, 13, 15, 16, 18, 20, 22, 23, 24, 25, 26, 27, 29, 30, 31 | PDF navigation (go to page, single-page mode, bookmarks, resume), correct shapes, no more circle→kidney, curves instead of arcs, handles that behave, cross-page lasso, Aa on the paper, auto page at the end, new pen picker, lightning/lava fixes |
| 2. Text pen | 1, 2, 3, 5, 10, Sci: math to text | Own handwriting model (TR+EN, ugly handwriting, punctuation, ş/ı/ğ, superscripts, ∫ Σ π √), correct word spacing and line layout, same quality for 3D pens |
| 3. AI, voices, video | 9, 12, 14, 21 (NotebookLM parts) | On-device AI that reads the page (Apple Foundation Models, optional MLX vision model), answers in the question's language; embedded TR/EN female/male voices; chapter-by-chapter video overviews; flashcards, quiz, mind map, report, slides, infographic, table |
| 4. Feel and speed | 17, 19, 28, 32, 21 (Notability parts) | Per-pen sounds that follow the hand without lag, smooth 3D pens on full pages, zoom-view writing, audio recording synced to ink, whole-app optimization, 3.0 delivery |

Batch 2's model training runs on the GPU in the background while Batch 1 is coded.

## Key decisions (made in this session)

- **Handwriting model:** CRNN (CNN + BiLSTM + CTC), ~8M parameters, input height 64 px. Trained from synthetic lines: OFL handwriting fonts (Google Fonts HANDWRITING category, messy ones weighted up), the app's own `StrokeFont` with jitter, Turkish/English Tatoeba sentences, generated math. Converted to Core ML on the macOS CI runner with coremltools. Vision stays as a second opinion; a Turkish/English dictionary and character LM pick the final text.
- **Voices:** English female/male = Kokoro-82M (Apache-2.0) through sherpa-onnx; Turkish female = FreyaTTS-small (Apache-2.0, 183M); Turkish male = Piper `tr_TR-fettah-medium` through sherpa-onnx. Models ship inside the app.
- **Local AI:** Apple Foundation Models is the default brain (needs the iOS 26 SDK, so CI moves to `macos-26` + Xcode 26.6; image input arrives with the iOS 27 SDK). A stronger optional brain, Qwen3-VL-4B (MLX, 4-bit, ~3 GB), downloads on request from Hugging Face without any key.
- **Competitor gaps to close** (from Notability's strings and NotebookLM's network capture): go to page, bookmarks, outline, thumbnails, single-page mode, zoom view, audio recording synced to ink, quick text boxes; flashcards, quiz, mind map, report, slides, infographic, data table, chat with citations.

## Review Focus

- A long PDF (1,400+ pages) opened at a remembered page: the page must be right and scrolling must stay smooth.
- Undo after moving a lasso selection to another page: both pages go back in one step.
- A shape or curve drawn with a thick 3D pen: corners stay where the user put them.
- Turkish text with ı/İ, ş, ğ, apostrophes and quotes written fast: no letter swapped for its Latin twin.
- English UI language with a Turkish document: answers follow the document's question, not the UI.
