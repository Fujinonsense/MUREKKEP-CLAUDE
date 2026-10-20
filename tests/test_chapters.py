"""Chapters of a long book from its outline or from the first lines of its pages (text layer or OCR),
checked on the three books the user works with."""
import json
from pathlib import Path

import pytest

from ports.chapters import PageHead, find

FIXTURES = Path(__file__).parent / "fixtures"


def load(name):
    d = json.loads((FIXTURES / f"heads_{name}.json").read_text(encoding="utf-8"))
    heads = [PageHead(i, lines) for i, lines in enumerate(d["pages"])]
    outline = [(o["title"], o["level"], o["page"]) for o in d["outline"]]
    return find(outline, heads, len(heads))


@pytest.fixture(scope="module")
def precalculus():
    return load("precalculus")


@pytest.fixture(scope="module")
def highnote():
    return load("highnote3")


@pytest.fixture(scope="module")
def reading():
    return load("reading")


def test_precalculus_has_12_chapters(precalculus):
    assert [c.start for c in precalculus] == [16, 168, 254, 406, 544, 624, 684, 774, 904, 1018, 1098, 1184]
    assert [c.number for c in precalculus] == list(range(1, 13))
    assert precalculus[0].title == "Functions"
    assert precalculus[11].title == "Introduction to Calculus"
    assert all(c.end == n.start - 1 for c, n in zip(precalculus, precalculus[1:]))
    one = precalculus[0].sections
    assert [(s.number, s.title, s.page) for s in one[:2]] == [
        ("1.1", "Functions and Function Notation", 16), ("1.2", "Domain and Range", 42)]
    assert len(one) == 7
    assert [s.number for s in precalculus[11].sections][:2] == ["12.1", "12.2"]


def test_back_matter_is_not_a_chapter(precalculus, highnote):
    assert precalculus[-1].end == 1249  # appendix A ("Basic Functions and Identities") starts on page 1250
    assert highnote[-1].end == 172      # "Grammar Reference and Practice" starts on page 173


def test_contents_pages_skipped(precalculus):
    assert all(c.start > 9 for c in precalculus)


def test_highnote_units(highnote):
    assert [c.start for c in highnote] == [5, 19, 35, 49, 65, 79, 95, 109, 125, 139]
    assert highnote[0].title == "Looking good"
    assert highnote[1].title == "The digital mind"
    assert {"1B", "1D"} <= {s.number for s in highnote[0].sections}


def test_reading_units(reading):
    assert [c.start for c in reading] == [0, 38, 74, 115, 157, 187, 216]
    assert [c.title for c in reading][:4] == ["Culture", "Health", "Trends", "Education and Career"]
    assert reading[-1].end == 244
    assert [(s.number, s.title) for s in reading[0].sections] == [
        ("Text 1", "Chinese Culture"), ("Text 2", "Whatis It About the Erasmus Program?"), ("Text 3", "A Universal Language")]


def test_outline_wins():
    heads = [PageHead(i, ["Unit 9 Noise"] if i == 3 else []) for i in range(40)]
    outline = [("Cover", 0, 0), ("Kinematics", 0, 2), ("Forces", 0, 12), ("Energy", 0, 25), ("Index", 0, 37),
               ("Speed", 1, 4)]
    chapters = find(outline, heads, 40)
    assert [(c.title, c.start, c.end) for c in chapters] == [
        ("Kinematics", 2, 11), ("Forces", 12, 24), ("Energy", 25, 36)]


def test_turkish_units():
    heads = [PageHead(i, []) for i in range(30)]
    heads[2] = PageHead(2, ["1. ÜNİTE", "SAYILAR VE İŞLEMLER"])
    heads[11] = PageHead(11, ["2. ÜNİTE: Cebirsel İfadeler"])
    heads[20] = PageHead(20, ["BÖLÜM 3", "x"])
    heads[21] = PageHead(21, ["3. ÜNİTE Geometri"])
    chapters = find([], heads, 30)
    assert [(c.number, c.start) for c in chapters] == [(1, 2), (2, 11), (3, 21)]
    assert chapters[1].title == "Cebirsel İfadeler"


def test_titles_read_like_titles():
    from ports.chapters import tidy
    assert tidy("WRITING A formal letter") == "Writing – A formal letter"
    assert tidy("RECYCLING: THE KAMIKATSU EXAMPLE by Emma Loewe") == "Recycling: the Kamikatsu Example"
    assert tidy("• Functions and Function Notation") == "Functions and Function Notation"
    assert tidy("SAYILAR VE İŞLEMLER") == "Sayılar ve İşlemler"
    assert tidy("IS IT A RITE OF PASSAGE?") == "Is It a Rite of Passage?"


def test_too_few_chapters_means_none():
    heads = [PageHead(i, ["Unit 1 Only"] if i == 4 else []) for i in range(20)]
    assert find([], heads, 20) == []
