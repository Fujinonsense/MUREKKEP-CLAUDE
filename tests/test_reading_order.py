"""Reading a scanned page in order: column by column, fragments of a row joined, blanks kept."""
import json
import random
from pathlib import Path

from ports.reading_order import Piece, lines, normalize_blanks

FIXTURE = Path(__file__).parent / "fixtures" / "ocr_highnote_p12.json"


def page():
    d = json.loads(FIXTURE.read_text(encoding="utf-8"))
    return [Piece(l["text"], tuple(l["box"])) for l in d["lines"]]


def where(out, start):
    hits = [i for i, t in enumerate(out) if t.startswith(start)]
    assert hits, f"no line starts with {start!r}"
    return hits[0]


def test_columns_are_read_one_after_the_other():
    out = lines(page())
    order = ["READERS' LETTERS", "The wheel of fashion", "I'm a sales assistant", "it'll come back into style.",
             "1E GRAMMAR", "1 'Fashion is like a wheel.'", "2 Study the Grammar box", "8 I'm wearing a leather jacket.",
             "a We use no article", "g We use a/an", "Grammar Reference", "3 1.5 Complete the gaps",
             "They say that", "4 In pairs, complete", "5 1.6 PRONUNCIATION", "WATCH OUT!", "6 SPEAKING"]
    at = [where(out, s) for s in order]
    assert at == sorted(at)


def test_fragments_of_a_row_are_joined_with_their_blanks():
    out = lines(page())
    for want in ["2 ___ boys but I think shopping for clothes is3 ___ most",
                 "boring thing in ___ world. Today I'm wearing5",
                 "old pair of jeans andé ___ cotton top.7 ___ jeans were",
                 "8 ___ present and9 ___ friend gave me 1o ___ top",
                 "13 ___ fashion designer in 14 ___ future.",
                 "1 I think ___ sport is more fun than ___ fashion.",
                 "4 ___ last thing I do before I go out in ___ morning",
                 "is to look in ___ mirror by ___ door. I'd love to be",
                 "3 The boutique specialises in fashion from Europe."]:
        assert want in out


def test_a_number_beside_its_text_is_not_a_blank():
    out = lines(page())
    assert "3 1.5 Complete the gaps with o (no article), a/an or" in out
    assert "5 1.6 PRONUNCIATION Study Watch out! Then in" in out


def test_the_order_of_vision_results_does_not_matter():
    pieces = page()
    want = lines(pieces)
    for seed in range(3):
        shuffled = pieces[:]
        random.Random(seed).shuffle(shuffled)
        assert lines(shuffled) == want


def test_a_single_column_reads_top_to_bottom():
    pieces = [Piece("Second line of the text", (100, 160, 700, 30)),
              Piece("First line of the text", (100, 100, 650, 30)),
              Piece("1", (60, 220, 14, 30)), Piece("an item after a number", (120, 220, 500, 30))]
    assert lines(pieces) == ["First line of the text", "Second line of the text", "1 ___ an item after a number"]


def test_numbers_in_a_margin_are_not_a_column():
    pieces = []
    for i in range(8):
        pieces.append(Piece(str(i + 1), (100, 100 + 40 * i, 16, 30)))
        pieces.append(Piece(f"Item number {i + 1} is a sentence of some length", (150, 100 + 40 * i, 600, 30)))
    out = lines(pieces)
    assert out[0] == "1 Item number 1 is a sentence of some length"
    assert len(out) == 8


def test_words_far_apart_get_a_blank_between_them():
    words = [("I", (100, 100, 10, 30)), ("think", (118, 100, 70, 30)), ("sport", (260, 100, 70, 30)),
             ("is", (338, 100, 22, 30))]
    p = Piece("I think sport is", (100, 100, 260, 30), words)
    assert lines([p]) == ["I think ___ sport is"]


def test_printed_blanks_become_one_marker():
    assert normalize_blanks("I think____sport") == "I think ___ sport"
    assert normalize_blanks("1 I think_sport is") == "1 I think ___ sport is"
    assert normalize_blanks("Name .......... Date ……") == "Name ___ Date ___"
    assert normalize_blanks("fashion... ...is that") == "fashion... ...is that"
    assert normalize_blanks("____ ____ ok") == "___ ok"


def test_a_revision_page_is_read_column_by_column():
    """Lone item numbers, superscript gap numbers and speaker names are tiny boxes of their own: a
    column is told by its wide boxes, so the story on the left is not interleaved with the exercises
    on the right."""
    d = json.loads((Path(__file__).parent / "fixtures" / "ocr_highnote3_p91.json").read_text(encoding="utf-8"))
    out = lines([Piece(l["text"], tuple(l["box"])) for l in d["lines"]])
    order = ["1 Complete the story with one word in each gap", "'Will you \"cover", "I will cover for you",
             "2 Choose the correct words to describe the", "3 Complete the sentences with the words from the box",
             "Complete sentences 1-4 with the zero conditional", "5 Complete the conversation", "Alex Thanks!"]
    at = [where(out, s) for s in order]
    assert at == sorted(at)
    assert not any("cover" in t and "ask back crazy" in t for t in out)
