# Batch 3 — On-device AI, OCR, Chapter Videos, Embedded Voices Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Apple's on-device model is finally in the app and solves the page's questions one by one; every page (scans too) is readable for the assistant and the Studio; a long book becomes one NotebookLM-style video per chapter; every video and answer is spoken by embedded Turkish/English female/male voices with no API key.

**Architecture:** CI moves to the `macos-26` runner with Xcode 26.6 (iOS 26.5 SDK), so the existing `#if canImport(FoundationModels)` code compiles in. sherpa-onnx 1.13.8 is built in CI as a static `SherpaOnnxC` framework (module map, so Swift guards it with `#if canImport(SherpaOnnxC)`), and the Supertonic 3 TTS model (31 languages, 10 preset voices, int8) is bundled as a folder resource; a second, plain build runs if the first fails, so an IPA always comes out. Every rule that can be checked off-device (question splitting, ligature repair, chapter finding, video outline, highlight markup, speech text) has a Python twin in `tests/`.

**Tech Stack:** Swift 5 mode, FoundationModels (iOS 26), Vision, PDFKit, ImagePlayground (`ImageCreator`, iOS 18.4+), sherpa-onnx C API (Supertonic), AVFoundation; Python 3.12 + pytest; PyYAML for the workflow test; EasyOCR/pdfium only for building fixtures.

**Spec:** The user's 20 Oct 2026 request (`C:/Users/orsyu/mrk-ml/re/long_prompt.txt`), items 8, 9, 12, 14, 21 (NotebookLM parts); `docs/superpowers/plans/2026-10-20-murekkep-3-roadmap.md` (Batch 3 row); `docs/superpowers/reports/2026-10-20-ai-studio-findings.md`; the two NotebookLM videos the user sent on 21 Oct (analysis in `docs/superpowers/reports/2026-10-21-notebooklm-video-anatomy.md`).

## Global Constraints

- No API key anywhere for voices or the on-device brain. ElevenLabs and OpenAI voice code and key fields are removed. Claude stays only as the existing optional engine.
- Voices: Turkish and English, a woman's and a man's, embedded in the app (Supertonic 3 via sherpa-onnx), never the system/Siri voices.
- The AI answers in the language of the question (item 8, `AnswerLanguage.forAnswer`, unchanged).
- Every new UI string through `Loc.t` with an English entry in `Translations.swift` (part 9).
- `InkShaders.swift` is not touched.
- Never at the cost of quality, and nothing may stutter (the user, 21 Oct): OCR, speech synthesis, model calls, chapter finding and illustration run off the main thread (detached tasks or a serial background queue, `.utility`/`.userInitiated`), report progress, are cancellable, and cache their results on disk; speech uses 2 CPU threads so drawing stays smooth.
- CI: `runs-on: macos-26`, Xcode `/Applications/Xcode_26.6.app`, sherpa-onnx tag `v1.13.8`, onnxruntime static xcframework `1.28.2`, model package `sherpa-onnx-supertonic-3-tts-int8-2026-05-11`.
- Zips only through `tools/make-zip.ps1`; no file in the zip over 25 MB (the user uploads through GitHub's web page). Models are fetched by CI, never committed.
- No Swift compiler here: `tools/balance.ps1` on every changed Swift file; Apple API names are checked against Apple's documentation JSON (`developer.apple.com/tutorials/data/documentation/...`) before use.
- Default tests: `uv run --quiet --with pytest --with numpy --with pillow --with pyyaml pytest tests -q`.

## Review Focus

- A whole scanned book (245 pages) chosen without picking chapters: the video is still made from OCR'd pages spread over the book, never "okunabilir metin bulunamadı". → Task 3 test `test_page_sample_spreads_over_book`.
- A chapter followed by an answer key or index: the chapter ends before the back matter. → Task 4 test `test_back_matter_is_not_a_chapter`.
- OCR that glued two options on one line ("A) 12 B) 15 C) 18") or read "1." as "l." → the question still has five options. → Task 2 test `test_glued_options_split`.
- Turkish narration with digits, %, x², f(x), π → read aloud as words, not skipped. → Task 7 test `test_turkish_math_is_spoken`.
- A chapter with 9 sections → the agenda shows at most 6 tiles (small sections merged), numbers stay in order. → Task 5 test `test_agenda_caps_at_six`.

---

### Task 1: CI on macOS 26 with sherpa-onnx and Supertonic (items 9, 12)

**Files:**
- Modify: `.github/workflows/main.yml`
- Create: `tests/test_workflow.py`

**Interfaces:**
- Produces: in the built app, `import SherpaOnnxC` works (framework module), the bundle has a folder `AppVoices/supertonic3/` with `duration_predictor.int8.onnx, text_encoder.int8.onnx, vector_estimator.int8.onnx, vocoder.int8.onnx, tts.json, unicode_indexer.bin, voice.bin`; `#if canImport(FoundationModels)` is true.

- [ ] **Step 1: Failing test** `tests/test_workflow.py`: loads the YAML; `test_runs_on_macos_26` (`runs-on == "macos-26"`, a step runs `sudo xcode-select -s /Applications/Xcode_26.6.app`); `test_sherpa_built_and_cached` (a step uses `actions/cache@v4` with a key containing `1.13.8` and `1.28.2`; a step clones `--branch v1.13.8` and runs cmake with `-DPLATFORM=OS64` and `-DSHERPA_ONNX_ENABLE_C_API=ON`; the framework gets `Modules/module.modulemap` declaring `SherpaOnnxC`); `test_voices_bundled` (the model tarball URL above; project.yml text has `path: AppVoices`, `type: folder`, `buildPhase: resources`); `test_frameworks_linked` (project.yml has both xcframeworks with `embed: false` and `OTHER_LDFLAGS` containing `-lc++`); `test_fallback_build` (a second build step runs only `if: steps.build.outcome == 'failure'` with a project spec without the frameworks and voices, and emits `::warning::`); `test_liquid_glass_off` (Info.plist has `UIDesignRequiresCompatibility` `<true/>`).
- [ ] **Step 2: Run** `uv run --quiet --with pytest --with pyyaml pytest tests/test_workflow.py -q` — Expected: FAIL.
- [ ] **Step 3: Rewrite the workflow** — order: checkout → Xcode 26.6 → cache restore (`sherpa-out`, key `sherpa-onnx-1.13.8-ort-1.28.2-os64-v1`) → if miss: build sherpa (os64 only, the commands of upstream `build-ios.sh` for OS64 plus its `libtool` merge and `create_framework`, then `xcodebuild -create-xcframework -framework …/SherpaOnnxC.framework`), copy `onnxruntime.xcframework` with `cp -RL` → voices (curl + tar into `AppSource/AppVoices/supertonic3`, cached under the same cache) → prepare sources (today's step) → Info.plist (+ `UIDesignRequiresCompatibility`) → project.yml (frameworks, folder resource, `-lc++ -framework CoreML -framework Accelerate`) → `id: build` xcodebuild with `continue-on-error: true` → fallback build (plain project.yml, `rm -rf AppSource/AppVoices`) → package whichever app exists → upload.
- [ ] **Step 4: Run** the test — Expected: PASS.
- [ ] **Step 5: FoundationModels check** — compare `OnDeviceAI.swift` and `StudioWriter.swift` calls with Apple's documentation JSON (`init(model:tools:instructions:)` String overload, `respond(to:options:)` String overload, `respond(to:generating:)`, `GenerationOptions(sampling:temperature:maximumResponseTokens:)`, `Tool` with `Output: PromptRepresentable`, `UnavailableReason` cases). Fix any mismatch; ledger the evidence.
- [ ] **Step 6: Commit** `ci: macOS 26 and Xcode 26.6 (Apple's on-device model compiles in), sherpa-onnx + Supertonic voices, fallback build`.

### Task 2: The on-device model solves the page's questions one by one (items 8, 9)

**Files:**
- Create: `Murekkep.swiftpm/Questions.swift`, `tests/ports/questions.py`, `tests/test_questions.py`
- Modify: `Murekkep.swiftpm/AssistantModel.swift` (solve path for `.onDevice` and `.localServer`), `Murekkep.swiftpm/OnDeviceAI.swift` (guided answer), `Murekkep.swiftpm/Translations.swift`

**Interfaces:**
- Produces: `struct PageQuestion: Equatable { var number: Int; var stem: String; var options: [(letter: Character, text: String)]; var passage: String? }` (options as a struct `QuestionOption { letter: Character; text: String }` to keep Equatable), `enum QuestionSplitter { static func split(_ text: String) -> [PageQuestion] }`; `OnDeviceAI.solve(_ q: PageQuestion, language: AnswerLanguage) async throws -> SolvedQuestion` with `struct SolvedQuestion { var answer: String; var reasoning: String }` (from a `@Generable` draft).
- Rules: a question starts at a line `^\s*(\d{1,2})\s*[.)]\s+\S` (OCR's `l.`/`I.` before a digit-less line counts as `1.` only when the next number is 2); options at `(?<![A-Za-z])([A-Ea-e])\s*[).]\s+` — several on one line are split; a passage is the text before the first question, or the text after a directive `(\d+)\s*[.\-–]\s*(\d+)\.?\s*soruları` / `Questions\s+(\d+)\s*[-–]\s*(\d+)` and before the first question it names, attached to every question in that range; numbers must increase; fewer than 2 options → not a multiple-choice question (stem only).

- [ ] **Step 1: Failing tests** — `test_numbered_questions_with_five_options` (Turkish YKS-like page of 3 questions → 3 items, 5 options each, letters A–E); `test_glued_options_split` ("A) 12 B) 15 C) 18 D) 21 E) 24" on one line → 5 options); `test_passage_attached_to_range` ("3. - 5. soruları aşağıdaki parçaya göre cevaplayınız." + paragraph + questions 3, 4, 5 → each has the paragraph as passage, question 6 has none); `test_english_questions_range` ("Questions 1-2 refer to the following passage."); `test_ocr_l_as_one` ("l. Which…" followed by "2. …" → numbers 1, 2); `test_open_question_has_no_options`.
- [ ] **Step 2: Run** `uv run --quiet --with pytest pytest tests/test_questions.py -q` — Expected: FAIL.
- [ ] **Step 3: Implement** `tests/ports/questions.py` (the rules above). Run — Expected: PASS.
- [ ] **Step 4: Swift twin** `QuestionSplitter` in `Questions.swift` (NSRegularExpression, same rules); `@Generable struct SolvedDraft { @Guide("Kısa gerekçe, en fazla 3 cümle") var reasoning: String; @Guide("Yalnızca doğru şıkkın harfi (A-E) ya da kısa cevap") var answer: String }` under `#if canImport(FoundationModels)`; `OnDeviceAI.solve` builds a prompt of passage + stem + options and the answer-language directive, temperature 0.2, max 400 tokens, falls back to the plain text path on `exceededContextWindowSize` by cutting the passage to 3 000 characters.
- [ ] **Step 5: Wire** `AssistantModel`: for `QuickAction.solve` (and page commands like "soruları çöz") with ≥ 2 split questions, the on-device engine answers each in turn, streaming "**3)** C — gerekçe" lines with status "Soru 3/8 çözülüyor…"; the local server engine does the same with its text API; the offline engine says it cannot solve questions and names the engines that can (Loc.t strings).
- [ ] **Step 6: Balance check, commit** `feat: the on-device model solves a page's questions one at a time`.

### Task 3: Every page readable for the Studio (item 14)

**Files:**
- Create: `Murekkep.swiftpm/PageReading.swift`, `tests/ports/textlayer.py`, `tests/test_textlayer.py`, `tests/fixtures/ligature_words.txt`
- Modify: `Murekkep.swiftpm/Sections.swift` (`SectionReader.pages`), `Murekkep.swiftpm/StudioWriter.swift` (`StudioMaterial.gather`, `.noText` text), `Murekkep.swiftpm/Translations.swift`

**Interfaces:**
- Produces: `enum TextLayer { static func isUsable(_ text: String) -> Bool; static func repairLigatures(_ text: String, isWord: (String) -> Bool) -> String }`; `enum PageSample { static func pages(count: Int, limit: Int) -> [Int] }` (evenly spread, first and last included); `SectionReader.pages(pdf: URL?, ink: URL, noteID: UUID, range: ClosedRange<Int>?, maxPages: Int, progress: (@Sendable (Int, Int) -> Void)?) async -> [Page]` — text layer when usable (after ligature repair), else Vision OCR of the page rendered at 2 000 px long edge (`PageOCR.recognize`), cached as UTF-8 files `Application Support/Murekkep/PageText/<noteID>/<page>.txt`.
- Values: usable = at least 25 letters and at most 2 % of characters in {U+FFFD, U+FFFE, private use, U+2B1A}; ligature repair tries, for a word containing `_` or an `X` between lowercase letters, the replacements `fi, fl, ff, ffi, ffl` and keeps the first that `isWord` accepts.

- [ ] **Step 1: Failing tests** — `test_scan_text_is_not_usable` (""/12 letters → false); `test_placeholder_math_is_usable_text` (precalculus-like page with a few "⬚" → true); `test_ligatures_repaired` ("de_ned _rst coXee diXerent modi_cation" → "defined first coffee different modification" with the fixture word list); `test_unknown_words_left_alone` ("x_1" and "MAX_SIZE" unchanged); `test_page_sample_spreads_over_book` (count 245, limit 60 → 60 pages, first 0, last 244, gaps differ by ≤ 1).
- [ ] **Step 2: Run** — Expected: FAIL. **Step 3:** implement the port — Expected: PASS.
- [ ] **Step 4: Swift twin** in `PageReading.swift` (`isWord` = `UITextChecker` for "en" plus `Spelling` for "tr", on the main actor, cached per word); `SectionReader.pages` reads `range ?? 0…pageCount-1`, takes `PageSample.pages` when the range has more pages than `maxPages`, repairs/OCRs/caches as above, reports progress; `StudioMaterial.gather(_:library:range:progress:)` passes them on; `.noText` reads "Seçilen sayfalarda okunabilir metin yok (boş ya da çok soluk sayfalar)."
- [ ] **Step 5: Balance check, commit** `feat: Studio reads scanned pages with OCR and repairs broken ligatures`.

### Task 4: Chapters of a long book (item 14)

**Files:**
- Create: `Murekkep.swiftpm/Chapters.swift`, `tests/ports/chapters.py`, `tests/test_chapters.py`, `tests/fixtures/heads_precalculus.json`, `tests/fixtures/heads_highnote3.json`, `tests/fixtures/heads_reading.json` (first 4 lines per page, from `C:/Users/orsyu/mrk-ml/tools/page_heads.py`)
- Modify: `Murekkep.swiftpm/StudioViews.swift` (chapter list), `Murekkep.swiftpm/Studio.swift` (`StudioStore.start` per chapter), `Murekkep.swiftpm/Translations.swift`

**Interfaces:**
- Produces: `struct BookSection: Codable, Hashable { var number: String; var title: String; var page: Int }`, `struct BookChapter: Codable, Hashable, Identifiable { var number: Int; var title: String; var startPage: Int; var endPage: Int; var sections: [BookSection]; var id: Int { startPage } }`, `struct PageHead { var page: Int; var lines: [String] }`, `enum ChapterFinder { static func find(outline: [(title: String, level: Int, page: Int)], heads: [PageHead], pageCount: Int) -> [BookChapter] }`, `enum BookIndex { static func chapters(for note: NoteMeta, library: LibraryStore, progress: …) async -> [BookChapter] }` (heads from PDFKit text or Vision OCR of the top third; result cached as JSON next to the page texts).
- Rules, first that yields ≥ 2 chapters: (1) outline level-0 items; (2) chapter openers: a page whose head has section numbers `N.k` that all share one `N` and include `N.1`, or a line `^(chapter|unit|module|part|lesson|bölüm|ünite|kısım)\s+(\d+|[IVXLC]+)\b` (case-insensitive) — pages with section numbers of ≥ 2 different chapters (contents pages) are skipped, numbers must increase, the first page per number wins; (3) none → no chapters (the UI offers page ranges). Titles: a contents line `^N\s+Title\s+\d+$` when found, else the text after the unit/chapter word, else the first section's title. Back matter starts at the first page after the last opener whose head starts with `Answer Key|Index|Cevap Anahtarı|Dizin|Glossary|Appendix|Ek`; the last chapter ends before it. Sections: head lines `^N\.k\s+Title` inside the chapter, first page per k.

- [ ] **Step 1: Failing tests** — `test_precalculus_has_12_chapters` (starts `[16, 168, 254, 406, 544, 624, 684, 774, 904, 1018, 1098, 1184]`, chapter 12 title "Introduction to Calculus", chapter 1 sections start with "1.1 Functions and Function Notation"); `test_back_matter_is_not_a_chapter` (last chapter's `endPage` is the page before the "Answer Key" page); `test_contents_pages_skipped`; `test_highnote_units` and `test_reading_units` (expected values written after inspecting the OCR fixtures, recorded in the ledger); `test_outline_wins`.
- [ ] **Step 2: Run** — Expected: FAIL. **Step 3:** implement the port — Expected: PASS.
- [ ] **Step 4: Swift twin** `ChapterFinder` + `BookIndex`; Studio create sheet: when exactly one PDF of ≥ 40 pages is chosen, a "Bölümler" section lists its chapters (found with a progress row the first time) with toggles and "Tüm kitap"; `create()` starts one job per chosen chapter (`StudioStore.start(…, pages: ClosedRange<Int>?, titleHint: String?)`), titled "Bölüm 12 · Introduction to Calculus".
- [ ] **Step 5: Balance check, commit** `feat: long books split into chapters, one video per chapter`.

### Task 5: Videos built like NotebookLM's (items 14, 21)

**Files:**
- Create: `Murekkep.swiftpm/VideoOutline.swift`, `tests/ports/outline.py`, `tests/test_outline.py`, `docs/superpowers/reports/2026-10-21-notebooklm-video-anatomy.md`
- Modify: `Murekkep.swiftpm/Studio.swift` (`SceneLayout` + `.question`, `.agenda`, `.section`; `OverviewScene.number: Int?`), `Murekkep.swiftpm/StudioWriter.swift` (on-device plan + sections, offline, Claude prompt, parser)

**Interfaces:**
- Produces: `struct OutlineSection { var title: String; var subtitle: String; var scenes: [OverviewScene] }`, `enum VideoOutline { static func assemble(title: String, hook: String, hookNarration: String, sections: [OutlineSection], closing: String, language: OverviewLanguage) -> [OverviewScene]; static func ordinal(_ n: Int, language: OverviewLanguage) -> String }`.
- Shape (from the two videos): title scene (greeting + topic, ~30 words) → `.question` hook (one question, key words in `**…**`, narration = a concrete example, 60–90 words) → `.agenda` (bullets = section titles, narration "İşte yol haritamız: Birinci, …") → per section: `.section` card (`number`, title, subtitle; narration "Birinci bölümümüz: X." / "Section one: X.", ≤ 12 words) + 1–3 content scenes (bullets/definition/compare/steps/figure, 50–180 words each) → `.summary` recap → `.question` closing (a question that sends the viewer back to the hook). At most 6 sections: extra ones are merged into their neighbours.
- On-device writer: `@Generable VideoPlanDraft { title; hook (≤ 12 words, 1–3 words in **); hookNarration; sections: [SectionPlanDraft { title (≤ 5 words); subtitle (≤ 6 words) }] (3–6); closing }` from the chapter's section titles + a 2 000-character sample, then per section `StudioSceneDraft` plus `layout` (`@Guide(.anyOf(["bullets","definition","compare","steps"]))`) from that section's pages; offline writer: sections = chapter sections (or `TextChunks.heading`), hook = "**{topic}** nedir, neden önemlidir?" / "What is **{topic}**, and why does it matter?".

- [ ] **Step 1: Failing tests** — `test_shape_title_hook_agenda_sections_recap_closing`; `test_section_cards_numbered_in_order` (numbers 1…n, ordinal narration "Birinci bölümümüz" … "Beşinci"); `test_agenda_caps_at_six` (9 sections → 6, scenes kept); `test_english_ordinals` ("Section one" … "Section five").
- [ ] **Step 2: Run** — FAIL. **Step 3:** port — PASS.
- [ ] **Step 4: Swift** — `VideoOutline`; new layouts in `SceneLayout` (old overviews still decode: `number` optional); writers and `StudioScriptParser` map `"question"`, `"agenda"`, `"section"`; Claude video prompt asks for this structure. The anatomy report records the timings and scene shapes measured from the two videos.
- [ ] **Step 5: Balance check, commit** `feat: video overviews with hook, roadmap, numbered sections and a closing question`.

### Task 6: The explainer look and sketch illustrations (items 14, 21)

**Files:**
- Create: `tests/ports/highlight.py`, `tests/test_highlight.py`
- Modify: `Murekkep.swiftpm/SlideRenderer.swift` (theme `.explainer`, `drawQuestion`, `drawAgenda`, `drawSectionCard`), `Murekkep.swiftpm/Studio.swift` (`SlideTheme.explainer`, default for new videos), `Murekkep.swiftpm/StudioWriter.swift` or new `Murekkep.swiftpm/StudioIllustrator.swift`, `Murekkep.swiftpm/Translations.swift`

**Interfaces:**
- Produces: `enum Highlight { static func parse(_ s: String) -> (text: String, ranges: [NSRange]) }` (`**…**` pairs, unmatched `**` dropped, ranges in UTF-16); `enum StudioIllustrator { static func illustrate(_ overview: inout Overview, folder: URL) async }` (ImageCreator `.sketch` when available, else `.illustration`; title + hook + section cards, at most 8 images; `scene.art = "file:art-<id>.png"`; does nothing when ImagePlayground is unavailable).
- Look (`.explainer`): background #F7F8FA with a 28-pt grid in #E6E9EF; one accent per overview picked from [#F28C28, #1A73E8, #0F9D58, #8E44AD] by a stable hash of the title; section card = left 38 % accent panel with the numeral (220 pt, white with dark outline) and a white rounded card with title (54 pt) and subtitle; agenda = rounded tiles (number top-left in accent, title) in rows of 3; question = centred 60 pt text with a #FFE58A marker behind highlighted ranges.

- [ ] **Step 1: Failing tests** — `test_highlight_ranges_utf16` ("Şampiyonun **anlık hızını** nasıl buluruz?" → text without stars, one range covering "anlık hızını"); `test_unmatched_markers_dropped`; `test_accent_is_stable` (same title → same colour).
- [ ] **Step 2–3:** FAIL → port → PASS.
- [ ] **Step 4: Swift** — drawing functions, `SlideAssets` loads `file:` art from the overview folder; `StudioIllustrator` (API names checked against Apple's documentation JSON) runs after writing, before voicing, with job phase "Çizimler hazırlanıyor…".
- [ ] **Step 5: Balance check, commit** `feat: NotebookLM-style explainer slides with on-device sketch illustrations`.

### Task 7: Embedded Turkish and English voices (item 12)

**Files:**
- Create: `Murekkep.swiftpm/EmbeddedVoices.swift`, `tests/ports/speech.py`, `tests/test_speech.py`
- Modify: `Murekkep.swiftpm/Voices.swift` (remove ElevenLabs/OpenAI, keys and their UI; voicer and `LiveSpeaker` use the embedded engine; WAV files), `Murekkep.swiftpm/Studio.swift` (no key guard), `Murekkep.swiftpm/StudioViews.swift` (voice row), `Murekkep.swiftpm/Translations.swift`

**Interfaces:**
- Produces: `enum EmbeddedVoices { static var isAvailable: Bool; static func speak(_ text: String, language: OverviewLanguage, gender: VoiceSettings.Gender, speed: Float, to url: URL) throws -> Double }` (a serial queue, one Supertonic instance loaded lazily from `Bundle.main.url(forResource: "AppVoices", withExtension: nil)/supertonic3`, `num_threads` 2, `num_steps` from the voice evaluation, `extra` `{"lang":"tr"}` / `{"lang":"en"}`, written with `SherpaOnnxWriteWave`); `VoiceSettings.speed` (0.85…1.3, default 1.0); `SpeechText.chunks(_ text: String, maxChars: Int) -> [String]` (sentence boundaries, never splitting a word); `SpeechText.spokenMath(_ text: String, language:)` (digits, %, ², ³, √, π, f(x), =, +, −, ×, ÷ → words; Turkish numbers by the rules of `spell_number` in FreyaTTS's pipeline, decimals with "virgül").
- Voice ids: the speaker id per language and gender is chosen by `C:/Users/orsyu/mrk-ml/tools/voice_eval.py` (lowest Whisper CER among voices whose median F0 is in the gender's range) and written as constants with the measurement in a comment.

- [ ] **Step 1: Failing tests** — `test_turkish_math_is_spoken` ("x² + 3x = 10, %25, π" → "x kare artı üç x eşittir on, yüzde yirmi beş, pi"); `test_english_math_is_spoken`; `test_turkish_numbers` (0, 11, 105, 1 250, 2 000 000 → "sıfır", "on bir", "yüz beş", "bin iki yüz elli", "iki milyon"); `test_chunks_keep_words_and_sentences` (no chunk over 260 chars, joined text equals input modulo whitespace).
- [ ] **Step 2–3:** FAIL → port → PASS.
- [ ] **Step 4: Swift** — `EmbeddedVoices` under `#if canImport(SherpaOnnxC)` (C strings kept alive with `strdup`/`free`, config zero-initialised with `SherpaOnnxOfflineTtsConfig()`), chunks synthesised in order and joined with 0.25 s silence; `StudioVoicer.voice` speaks segments one at a time (`.wav`), `voiceSignature` "supertonic3:<sid>:<speed>"; without the framework (fallback build) videos are saved silent with "Bu derlemede gömülü sesler yok." Voice settings screen: gender, speed, samples; key sections removed.
- [ ] **Step 5: Balance check, commit** `feat: embedded Turkish and English voices (Supertonic 3), no API keys`.

### Task 8: Version 3.0 build 15 and delivery

**Files:** Modify `Murekkep.swiftpm/Package.swift`, `.github/workflows/main.yml`.

- [ ] **Step 1:** `bundleVersion` and `CURRENT_PROJECT_VERSION` → "15".
- [ ] **Step 2:** `tools/balance.ps1` on every Swift file — Expected: all ok.
- [ ] **Step 3:** `Murekkep-3.0-beta3-iPad.zip` via `tools/make-zip.ps1`; check no entry is over 25 MB.
- [ ] **Step 4:** default suite + venv suite green.
- [ ] **Step 5:** Commit `chore: Mürekkep 3.0 beta 3 (build 15)`.

Out of this batch (next): the optional downloadable MLX vision model (Qwen3-VL class) for hard questions, iOS 27 image input to Apple's model (needs the Xcode 27 runner image, still a preview), flashcards with spaced repetition, mind map, reports.
