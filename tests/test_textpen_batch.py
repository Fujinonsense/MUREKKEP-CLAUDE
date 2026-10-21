"""When the text pen goes on writing the line it has just turned into text, the whole line is read
again (twin of TextPenBatch.swift). On the iPad, "Aga" written, a pause, then "naber?" read as
"Asa" + "naber?" with no space; the same ink read at once is '"Aga naber?"'."""
from ports.textpen_batch import REACH, WINDOW, continues

# The last writing: "Aga" at x 100–160, letters from y 200 (top of A) to 240 (tail of g).
AGA = (100, 200, 160, 240)


def test_the_next_word_on_the_same_line_continues_it():
    assert continues(AGA, (180, 205, 260, 236), elapsed=2.0)       # "naber?"


def test_a_word_with_a_descender_or_ascender_still_counts():
    assert continues(AGA, (175, 196, 230, 238), elapsed=1.0)       # "bel"
    assert continues(AGA, (175, 212, 230, 248), elapsed=1.0)       # "yağ"


def test_the_next_line_does_not():
    assert not continues(AGA, (100, 262, 200, 300), elapsed=2.0)


def test_far_to_the_right_or_back_at_the_start_does_not():
    h = 40
    assert not continues(AGA, (160 + REACH * h + 5, 205, 400, 236), elapsed=2.0)
    assert not continues(AGA, (20, 205, 80, 236), elapsed=2.0)


def test_a_dot_an_accent_or_a_full_stop_continues_it():
    assert continues(AGA, (148, 190, 152, 194), elapsed=3.0)       # a dot over the last letter
    assert continues(AGA, (163, 234, 166, 238), elapsed=3.0)       # a full stop after it
    assert continues(AGA, (165, 196, 171, 206), elapsed=3.0)       # a closing quote


def test_only_for_a_while():
    assert continues(AGA, (180, 205, 260, 236), elapsed=WINDOW - 0.1)
    assert not continues(AGA, (180, 205, 260, 236), elapsed=WINDOW + 0.1)
    assert not continues(AGA, (180, 205, 260, 236), elapsed=-1.0)
