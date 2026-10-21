import math
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


def test_pen_motion_settles_what_the_picture_cannot():
    # The picture reads "a" a little better; the pen's path says "e" clearly.
    online = {"bel": -1.0, "bal": -9.0}
    assert choose([("bal", -2.0), ("bel", -2.3)], [], 3, False, lambda t: 0.0, online) == "bel"
    assert choose([("bal", -2.0), ("bel", -2.3)], [], 3, False, lambda t: 0.0) == "bal"


def test_pen_motion_alone_does_not_beat_a_sure_picture():
    online = {"bel": -1.0, "bal": -2.0}
    assert choose([("bal", -0.3), ("bel", -6.0)], [], 3, False, lambda t: 0.0, online) == "bal"


def test_reading_the_pen_cannot_follow_is_not_thrown_out():
    # Three dots drawn in a few points: the pen-motion reader has too few columns for "..." and
    # gives it no probability; the floor keeps the picture's sure reading.
    online = {"...": -math.inf, "-": -0.5}
    assert choose([("...", -0.2), ("-", -9.0)], [], 3, False, lambda t: 0.0, online) == "..."


def test_reading_the_pen_reader_did_not_score_gets_the_floor():
    online = {"bel": -2.0}
    assert choose([("bal", -1.0), ("bel", -1.2)], [], 3, False, lambda t: 0.0, online) == "bel"


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
