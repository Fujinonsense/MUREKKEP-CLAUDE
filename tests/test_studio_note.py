"""Studio takes a note to the AI (2026-10-26): how the student wants the video, the cards or the quiz.
The note reaches every writer that reads prompts (Claude, the downloaded model, Apple's model)."""
import re
from pathlib import Path

APP = Path(__file__).resolve().parent.parent / "Murekkep.swiftpm"


def src(name):
    return (APP / name).read_text(encoding="utf-8")


def test_study_sets_take_a_note():
    views = src("StudyViews.swift")
    sheet = views[views.index("struct StudyCreateSheet"):views.index("// MARK: - Open a set")]
    assert "@State private var note = \"\"" in sheet
    assert "TextField(kind.noteExample, text: $note, axis: .vertical)" in sheet
    assert 'Loc.t("Yapay zekâya not (isteğe bağlı)")' in sheet
    assert "StudyOptions(kind: kind, english: english, count: count, note: note)" in sheet
    # Every kind has its own example of a note.
    example = views[views.index("var noteExample: String"):]
    for kind in ("flashcards", "quiz", "mindMap", "guide"):
        assert f"case .{kind}: return Loc.t(" in example[:900]


def test_the_note_reaches_the_study_writers():
    writer = src("StudyWriter.swift")
    assert 'var note = ""' in writer
    assert "Öğrencinin notu (kaynaklara bağlı kalarak buna uy)" in writer
    prompt = writer[writer.index("private static func jsonPrompt"):writer.index("private static func jsonObject")]
    assert "options.noteLine" in prompt  # Claude and the downloaded model
    on_device = writer[writer.index("private static func onDevice"):]
    assert re.search(r"let instructions = .*\n\s*\+ \(options\.noteLine\.isEmpty", on_device)  # Apple's model


def test_overviews_ask_for_the_note_up_front():
    views = src("StudioViews.swift")
    focus = views[views.index("private var focusSection"):]
    assert 'Loc.t("Yapay zekâya not (isteğe bağlı)")' in focus[:800]
    # On a narrow sheet the note comes right after the sources, before the look of the slides.
    narrow = views[views.index("// The choices that shape the result come first"):]
    assert narrow.index("focusSection") < narrow.index("formatSection")
    writer = src("StudioWriter.swift")
    assert "Öğrencinin notu (kaynaklara bağlı kalarak buna uy)" in writer
    assert "- Öğrencinin notu:" in writer
    assert "Odak:" not in writer


def test_note_texts_are_translated():
    table = src("Translations.swift")
    for key in ("Yapay zekâya not (isteğe bağlı)",
                "Nasıl anlatılsın, neye ağırlık verilsin, neyi atlasın; serbestçe yaz. Yapay zekâ buna göre hazırlar.",
                "Nasıl hazırlansın, neye ağırlık verilsin, neyi atlasın; serbestçe yaz. Yapay zekâ buna göre hazırlar."):
        assert f'"{key}":' in table
