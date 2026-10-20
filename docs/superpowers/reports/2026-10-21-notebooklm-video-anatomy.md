# How NotebookLM's video overviews are built

Measured on the two videos the user made from the Precalculus 2e book (21 Oct 2026): a Turkish one on
chapter 12 ("Anın Gücü: Kalkülüse Giriş") and an English one on section 1.1 ("Explainer: Functions").
Tools: `C:/Users/orsyu/mrk-ml/tools/video_probe.py` (PyAV scene cuts at 4 fps, Whisper large-v3 on the
RTX 5080). Keyframes and transcripts: `C:/Users/orsyu/mrk-ml/re/notebooklm/videos/{tr,en}/`.

| | Turkish (ch. 12) | English (1.1) |
|---|---|---|
| Length | 6 min 43 s | 7 min 51 s |
| Format | 1280×720, 24 fps, mono AAC 44.1 kHz | same |
| Narration | 993 words, 148 words/min | 1,458 words, 186 words/min |
| Scenes | 18 | 20 |
| Voice | one narrator | one narrator |

## The shape (both videos)

1. **Title** (14–22 s): a hand-drawn illustration and the title; the narrator greets and names the topic.
2. **Hook question** (23–36 s): one big question with 1–3 words on a yellow marker, a doodle around it;
   the narration opens it with a concrete example (a runner's instantaneous speed; a reliable relationship).
3. **Roadmap** (5–14 s): five numbered tiles; the narration reads them as a list.
4. **Five sections**, each opened by a **section card** (3–5 s: a big numeral on an accent-colour panel,
   a title and a 2–4 word subtitle, doodle icons; one short sentence "Section two, the rule of one") and
   followed by 1–3 content scenes of 20–70 s: a concept card (term + one-line definition), a definition
   with the key word highlighted, two side-by-side panels (compare), a table, numbered steps, a formula
   with highlighted words, or a large illustration.
5. **Closing question** (35–50 s): back to the hook ("How would you use … around you?"), then the logo.

One accent colour per video (orange for the Turkish one, blue for the English one) on a light grid-paper
background; every illustration is in the same sketchy hand-drawn style.

## What Mürekkep does with it (Batch 3)

- `VideoOutline.assemble` builds exactly this order (Task 5); writers give it the hook, the sections and
  their scenes. A long book becomes one such video per chapter (Task 4).
- The `.explainer` slide theme draws the grid paper, the accent colour, the section numerals, the
  roadmap tiles and the highlighted questions; Apple's on-device image generator draws sketch
  illustrations when the iPad has Apple Intelligence (Task 6).
- Narration pace: NotebookLM's Turkish narrator speaks about 148 words/min; Mürekkep's script budget
  stays at 112 words/min of Turkish so the embedded voice (Task 7) is never rushed.
