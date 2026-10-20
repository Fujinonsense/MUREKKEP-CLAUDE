import re
from pathlib import Path

from ports.reading import SUPERS, choose, insert_superscripts

WORDS = {"küçük", "tamir", "istanbul'da", "merhaba"}


def dictionary(text):
    """Share of words the dictionary knows, case-insensitive (Turkish rules)."""
    words = [w for w in text.replace("İ", "i").replace("I", "ı").lower().split() if len(w) >= 2]
    return sum(w in WORDS for w in words) / len(words) if words else 0.0


def test_dictionary_breaks_ties():
    assert choose([("kucuk", -3.0), ("küçük", -3.4)], [], 5, False, dictionary) == "küçük"


def test_confident_model_keeps_a_name():
    assert choose([("Tomris", -1.0), ("Tamir", -6.0)], [], 6, False, dictionary) == "Tomris"


def test_model_wins_on_math():
    assert choose([("x=2", -1.0), ("x-2", -1.2)], [("küçük", -1.1)], 3, True, dictionary) == "x=2"


def test_vision_reading_can_win_when_the_model_agrees():
    assert choose([("merhoba", -2.0)], [("merhaba", -2.1)], 7, False, dictionary) == "merhaba"


def test_lone_marks_stay_marks():
    assert choose([(",", -0.5), ("a", -3.0)], [], 1, False, dictionary) == ","
    assert choose([("ı", -0.3), ("i", -1.5)], [], 1, False, dictionary) == "ı"


def test_caps_reading_kept():
    assert choose([("İSTANBUL'DA", -2.0), ("istanbul'da", -2.2)], [], 11, False, dictionary) == "İSTANBUL'DA"


def test_vision_only_when_model_missing():
    assert choose([], [("merhaba", None), ("merhoba", None)], 0, False, dictionary) == "merhaba"


def test_superscript_inserted():
    assert insert_superscripts("x+y", [100, 112, 124], [("2", 108)]) == "x²+y"
    assert insert_superscripts("a+b", [100, 112, 124], [("n", 130)]) == "a+bⁿ"


def test_superscript_without_a_raised_form():
    assert insert_superscripts("x", [100], [("q", 108)]) == "x^q"


def test_raised_apostrophe_is_just_an_apostrophe():
    assert insert_superscripts("İSTANBULDA", [100 + 10 * i for i in range(10)], [("'", 175)]) == "İSTANBUL'DA"


def test_raised_table_matches_strokefont():
    swift = (Path(__file__).resolve().parent.parent / "Murekkep.swiftpm" / "StrokeFont.swift").read_text(encoding="utf-8")
    table = swift.split("private static let superscripts")[1].split("= [", 1)[1].split("]")[0]
    pairs = dict((base, raised) for raised, base in re.findall(r'"(.)": "(.)"', table))
    assert pairs == SUPERS
