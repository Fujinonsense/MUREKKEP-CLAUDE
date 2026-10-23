"""Training copies of real lines with the words written closer together (real_lines.squeeze_gaps): the
reader lost spaces when a hand left only 40 % of its usual word gap ("çocukılık"). The widest gaps,
one per space, shrink; a gap never ends up narrower than 0.6 of the letters' height; the letters
inside the words do not move apart."""
import sys
from pathlib import Path

import numpy as np
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "ml" / "handwriting"))
real_lines = pytest.importorskip("real_lines")


def word(x0, letters=3, h=10.0):
    """A word of `letters` strokes 6 wide with gaps of 2."""
    return [np.array([[x0 + 8 * i, 0.0], [x0 + 8 * i + 6, h]]) for i in range(letters)]


def runs(strokes):
    spans = sorted((s[:, 0].min(), s[:, 0].max()) for s in strokes)
    out = [list(spans[0])]
    for a, b in spans[1:]:
        if a <= out[-1][1]:
            out[-1][1] = max(out[-1][1], b)
        else:
            out.append([a, b])
    return out


def gaps(strokes):
    r = runs(strokes)
    return [r[i + 1][0] - r[i][1] for i in range(len(r) - 1)]


def test_word_gaps_shrink_letter_gaps_stay():
    line = word(0) + word(60) + word(120)          # word gaps 38, letter gaps 2
    rng = np.random.default_rng(3)
    out = real_lines.squeeze_gaps(rng, line, spaces=2, low=0.3, high=0.3)
    g = sorted(gaps(out))
    assert g[:-2] == pytest.approx([2.0] * 6)      # inside the words: unchanged
    assert g[-2:] == pytest.approx([38 * 0.3] * 2)


def test_gap_never_below_six_tenths_of_the_height():
    line = word(0) + word(27)                       # word gap 5, height 10
    out = real_lines.squeeze_gaps(np.random.default_rng(0), line, spaces=1, low=0.1, high=0.1)
    assert max(gaps(out)) == pytest.approx(5.0)     # already under 0.6 × height: left as it is
    wide = word(0) + word(60)                       # word gap 38
    out = real_lines.squeeze_gaps(np.random.default_rng(0), wide, spaces=1, low=0.05, high=0.05)
    assert max(gaps(out)) == pytest.approx(6.0)     # 0.6 × height


def test_no_spaces_no_change():
    line = word(0) + word(60)
    out = real_lines.squeeze_gaps(np.random.default_rng(1), line, spaces=0)
    assert all(np.allclose(a, b) for a, b in zip(line, out))
