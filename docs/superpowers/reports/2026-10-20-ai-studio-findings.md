# Embedded AI, Studio, Notability and NotebookLM — findings for Batch 3

## Why the embedded AI fails (item 9) and the video overview says "no readable text" (item 14)

1. **The on-device language model is not in the app.** `OnDeviceAI.swift` and the on-device Studio writer are
   wrapped in `#if canImport(FoundationModels)`. CI builds on `macos-15` (Xcode 16, iOS 18 SDK), where that
   framework does not exist, so the code is compiled out. On the iPad "Otomatik" therefore falls back to
   `OfflineBrain` — a rule-based extractor (summaries by sentence ranking, keyword search, fill-in-the-blank) that
   cannot reason about a question. That is the "90 % unreadable, never solves verbal questions" behaviour.
2. **Two of the three sample books have no text layer.** `high-note-3 student book.pdf` (204 pages) and
   `Reading Strategies for Intermediate Level.pdf` (245 pages) are scans: 0 characters of text on every page.
   `precalculus-2e` (1,411 pages) has text, but math variables are in fonts without Unicode mapping and come out
   empty ("if ⬚ is the inverse of ⬚"); it has no PDF outline.
3. **Studio never OCRs.** `StudioWriter` builds its material from the PDF text layer only and throws
   `.noText` ("Seçilen kaynaklarda okunabilir metin bulunamadı. Taranmış PDF'ler için Claude'u seç.") for scans.
   The assistant panel does OCR scanned pages (`recognizedScan`), Studio does not.
4. **Voices** still carry the ElevenLabs/OpenAI key path (`Voices.swift`); item 12 asks for embedded voices only.

## Notability (from its IPA: 4,100 English interface texts, `C:/Users/orsyu/mrk-ml/re/notability/`)

- Audio recordings linked to handwriting: "During playback, tap a word, sketch, or photo to hear what was said at
  that moment"; voice amplification; live transcription; AI summaries in real time; YouTube link → note.
- Notability AI: chat with all notes in the library; AI quizzes and flashcards with spaced repetition ("Flip a card
  and rate it by difficulty"); study time per note.
- Handwriting: recognition with chosen languages, convert to text box, **handwritten math → LaTeX**, photo of paper
  notes → editable ink, handwriting search.
- Pages: Go to page, titled bookmarks, outline (headings added automatically), Page Manager, continuous/horizontal.
- Zoom View for writing small; Presentation mode with laser pointer to an external display.
- Tools: Tape (cover, tap to reveal — a study tool), calligraphy pen with tip angle, ruler with measuring, stickers
  from a selection, Apple Pencil Pro squeeze palette, hover preview.
- Templates: planners, Cornell notes, custom templates.

## NotebookLM Studio (from the HAR: 368 requests, interface texts of its scripts, `…/re/notebooklm/studio.txt`)

- **Audio Overview:** two AI hosts; formats deep dive / brief / critique / debate; "What should the AI hosts focus
  on?", language, length; **Interactive mode** — interrupt the hosts with a spoken question; download.
- **Video Overview:** customize focus and **visual style** (Auto-select, Classic, Whiteboard, Watercolor, Retro
  print, Heritage, Paper-craft, Anime, Kawaii); Short and Cinematic variants; English only for now.
- **Slide Deck:** outline review before generating, per-slide edit by prompt, custom visual style.
- **Mind Map** (interactive: a node opens a question), **Data Table**, **Infographic**, **Reports** (briefing doc,
  study guide with quiz, custom structure and tone), **Interactive Report** (a generated web page), quiz, flashcards.

## What Batch 3 must therefore do

1. Build with the iOS 26 SDK (CI `macos-26`, Xcode 26) so Apple's on-device model is actually in the app; keep the
   rule-based core only as the last fallback and say which brain answered.
2. Read every page the AI or Studio uses: text layer when it is real, otherwise Vision OCR (TR + EN), and for math
   pages also OCR (lost variables). Cache per page.
3. A stronger on-device brain for hard questions: an optional download (MLX, Qwen3-VL class, vision + reasoning)
   that reads the page image itself — the only way verbal and visual prep-school questions get solved locally.
4. Studio from scanned books: OCR the chosen pages; split long books into chapters (outline when present, else
   headings like "Unit 3" / "Chapter 2" / "1.2 …" found in the text) and offer one video per chapter.
5. Embedded voices only (Kokoro EN, Turkish female/male), no key fields.
6. Studio parity: audio formats + focus + length, video styles, slide outline review, mind map, quiz/flashcards with
   spaced repetition, report formats.
