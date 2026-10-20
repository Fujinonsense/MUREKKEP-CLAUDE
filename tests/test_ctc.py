import itertools
import math

import numpy as np

from ports.ctc import alignment, beam, score


def logs(rows):
    return np.log(np.asarray(rows, dtype=np.float64))


def test_beam_finds_best_path():
    # Greedy reads blank, blank (0.36); "a" over all its paths is 0.64.
    lp = logs([[0.6, 0.4], [0.6, 0.4]])
    best_text, best_score = beam(lp, "a")[0]
    assert best_text == "a"
    assert math.isclose(math.exp(best_score), 0.64, rel_tol=1e-9)


def test_repeated_letters_need_blank():
    l_blank_l = logs([[0.05, 0.95], [0.9, 0.1], [0.05, 0.95]])
    assert beam(l_blank_l, "l")[0][0] == "ll"
    l_l_l = logs([[0.01, 0.99], [0.01, 0.99], [0.01, 0.99]])
    assert beam(l_l_l, "l")[0][0] == "l"
    assert score("ll", l_l_l, "l") < math.log(0.05)


def collapse(path):
    out, prev = [], 0
    for k in path:
        if k != prev and k != 0:
            out.append(k)
        prev = k
    return out


def test_forward_score_matches_bruteforce():
    rng = np.random.default_rng(0)
    p = rng.random((5, 3))
    p /= p.sum(axis=1, keepdims=True)
    lp = np.log(p)
    for text in ["ab", "a", "ba", "aa", ""]:
        target = [" ab".index(c) for c in text]
        total = sum(math.prod(p[t, k] for t, k in enumerate(path))
                    for path in itertools.product(range(3), repeat=5) if collapse(path) == target)
        got = score(text, lp, "ab")
        assert got is not None
        assert math.isclose(math.exp(got), total, rel_tol=1e-9), text


def test_unknown_char_scores_none():
    assert score("ax", logs([[0.5, 0.5]]), "a") is None


def test_alignment_gives_frames_of_written_characters():
    lp = logs([[0.1, 0.8, 0.1], [0.1, 0.8, 0.1], [0.8, 0.1, 0.1], [0.1, 0.1, 0.8]])
    assert alignment(lp) == [0, 3]
