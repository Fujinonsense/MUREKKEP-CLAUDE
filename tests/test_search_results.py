"""The library search's count (LibraryPanes.SearchPane). Every row the page shows counts, the places
found inside the notes too (handwriting, a PDF's text, a read page). Run 6ae226b3 filmed
"0 results" right above a handwriting hit."""
from pathlib import Path

APP = Path(__file__).resolve().parent.parent / "Murekkep.swiftpm"


def src(name):
    return (APP / name).read_text(encoding="utf-8")


def test_the_count_includes_the_matches_inside_the_notes():
    pane = src("LibraryPanes.swift").split("struct SearchPane")[1]
    header = pane.split("PaneHeader(")[1].split("showToggle:")[0]
    for part in ("notes.count", "overviews.count", "courses.count", "hits.count"):
        assert part in header, part


def test_one_result_is_singular_in_english():
    assert '"{0} sonuç": "{0} {0|result|results}"' in src("Translations.swift")
