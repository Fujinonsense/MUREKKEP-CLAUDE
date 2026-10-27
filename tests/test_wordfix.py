"""The text pen swaps a word no list knows for a known word a letter or two away when the readers find
it almost as likely (twin of WordFix.swift). On the iPad, "I had to run to the restaurant because" came
out "... becavse": this hand's u is pointed, and both readers were sure of the v."""
from pathlib import Path

from ports import wordfix
from ports.wordfix import Lexicon, cased, distance, fix, is_formula, near

ROOT = Path(__file__).resolve().parents[1]
WORDLIST = ROOT / "Murekkep.swiftpm" / "Assets.xcassets" / "wordlist.dataset" / "wordlist.txt"

SMALL_ROWS = [("because", 9570), ("the", 5000), ("restaurant", 2400), ("sınavda", 130), ("üçgenin", 40),
              ("dog", 900), ("day", 800), ("yağız", 2), ("var", 700), ("ankara", 300)]
SMALL = Lexicon(SMALL_ROWS)


def scorer(likely):
    """log P: 0 for the text the readers read, likely[text] for others they could follow."""
    def score(text):
        return likely.get(text, -100.0)
    return score


def test_a_pointed_u_becomes_because_when_the_readers_almost_agree():
    read = "I had to run to the restaurant becavse"
    score = scorer({read: 0.0, "I had to run to the restaurant because": -11.5})
    assert fix(read, score, SMALL, readers=2) == "I had to run to the restaurant because"


def test_not_when_the_readers_are_too_sure():
    read = "I had to run to the restaurant becavse"
    score = scorer({read: 0.0, "I had to run to the restaurant because": -14.5})
    assert fix(read, score, SMALL, readers=2) == read
    # One reader alone may lose half as much.
    score = scorer({read: 0.0, "I had to run to the restaurant because": -7.5})
    assert fix(read, score, SMALL, readers=1) == read


def test_known_words_short_words_and_suffixes_stay():
    lex = Lexicon(SMALL_ROWS + [("sini", 50), ("ab", 50), ("yavız", 50), ("ankara", 50), ("is", 50)])
    read = "yağız ba 37'sinii Ankra'da isn't"
    # Every other text scores higher, yet "yağız" is known (seen twice), "ba" is too short, "sinii"
    # is a suffix after an apostrophe, and "Ankra" and "isn" stand before one.
    assert fix(read, lambda t: 0.0 if t == read else 10.0, lex, readers=2) == read


def test_the_best_of_the_near_words_wins():
    read = "lazy dag"
    score = scorer({read: 0.0, "lazy dog": -2.0, "lazy day": -1.0})
    assert fix(read, score, SMALL, readers=2) == "lazy day"


def test_a_capital_stays_a_capital_and_turkish_letters_come_back():
    read = "Sıravda 40 sorunun"
    score = scorer({read: 0.0, "Sınavda 40 sorunun": 6.4})
    assert fix(read, score, SMALL, readers=2) == "Sınavda 40 sorunun"
    assert cased("üçgenin", "Üçgein") == "Üçgenin"
    assert cased("ankara", "Ankra") == "Ankara"
    assert cased("ıslak", "Islk") == "Islak"


def test_formulas_and_acronyms_are_left_alone():
    assert is_formula("f(x) = 3x + 1")
    assert is_formula("x^2 + y")
    assert not is_formula("Kurtuluş Savaşı 1919 - 1922 yılları arasında.")
    assert not is_formula("Sınavda 40 sorunun 37'sini doğru yaptım!")
    read = "DNA becavse"
    score = scorer({read: 0.0, "DNA because": -1.0, "DNE becavse": 3.0})
    assert fix(read, score, SMALL, readers=2) == "DNA because"


def test_distance_and_near_words():
    assert distance("becavse", "because", 2) == 1
    assert distance("kurtulş", "kurtuluş", 2) == 1
    assert distance("abc", "xyzuvw", 2) == 3
    assert "because" in near("becavse", SMALL)
    assert "dog" in near("dag", SMALL) and "day" in near("dag", SMALL)
    assert "restaurant" not in near("tavrant", SMALL)            # three letters away


def test_the_apps_word_list_knows_the_words_of_the_report():
    lex = Lexicon.load(WORDLIST)
    for w in ("because", "restaurant", "hungry", "sınavda", "savaşı", "üçgenin", "kurtuluş"):
        assert lex.knows(w), w
    assert not lex.knows("becavse") and not lex.knows("festauront")
    # Words cut at an apostrophe count by the part before it, and "n't" words not at all.
    assert lex.knows("Ankara") and lex.knows("Tom")
    assert not lex.knows("isn") and not lex.knows("didn") and not lex.knows("doesn")
    assert lex.knows("I") is False and lex.knows("İstanbul")
    assert "because" in near("becavse", lex)
    # Most frequent first, two counts per line.
    rows = [line.split() for line in WORDLIST.read_text(encoding="utf-8").splitlines()[:50]]
    counts = [int(n) for _, n in rows]
    assert counts == sorted(counts, reverse=True) and all(len(r) == 2 for r in rows)
    assert wordfix.KNOWN_MIN <= min(int(line.split()[1]) for line in WORDLIST.read_text(encoding="utf-8").splitlines())
