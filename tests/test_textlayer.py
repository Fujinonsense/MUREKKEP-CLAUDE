"""Which PDF pages can be read from their text layer, repairing broken ligatures, and which pages the
Studio reads from a long book."""
from pathlib import Path

from ports.textlayer import is_usable, repair_ligatures, sample_pages

WORDS = set((Path(__file__).parent / "fixtures" / "ligature_words.txt").read_text(encoding="utf-8").split())


def is_word(w):
    return w.lower() in WORDS


def test_scan_text_is_not_usable():
    assert not is_usable("")
    assert not is_usable("   12  \n 7 ")
    assert not is_usable("Unit 3 page 41")  # 12 letters: a scanned page's stray footer


def test_placeholder_math_is_usable_text():
    page = ("If ⬚ is the inverse of ⬚, then the graph of the inverse function is the reflection of the graph "
            "of the function across the line y = x. Find the domain and the range of each function.")
    assert is_usable(page)


def test_garbage_glyphs_are_not_usable():
    assert not is_usable("��� Bu sayfa ��� bozuk ��� kodlanmış �� metin ��")


def test_ligatures_repaired():
    text = "Key terms are de_ned when _rst used. The coXee shop is diXerent. Modi_cation of work."
    assert repair_ligatures(text, is_word) == (
        "Key terms are defined when first used. The coffee shop is different. Modification of work.")


def test_unknown_words_left_alone():
    assert repair_ligatures("x_1 and MAX_SIZE stay; eXtra too", is_word) == "x_1 and MAX_SIZE stay; eXtra too"


def test_page_sample_spreads_over_book():
    pages = sample_pages(245, 60)
    assert len(pages) == 60 and pages[0] == 0 and pages[-1] == 244
    gaps = {b - a for a, b in zip(pages, pages[1:])}
    assert max(gaps) - min(gaps) <= 1
    assert sample_pages(30, 60) == list(range(30))
