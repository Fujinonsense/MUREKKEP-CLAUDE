"""The writing's angle on the page, so the text pen can level it before reading: a page turned
by -19° with the writing level on the screen leaves the ink 19° off the page's lines."""
import math
import sys
from pathlib import Path

import pytest

pytest.importorskip("skimage")
DATA = Path("C:/Users/orsyu/mrk-ml/data")
if not (DATA / "fonts").exists():
    pytest.skip("handwriting fonts not downloaded", allow_module_level=True)
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "ml" / "handwriting"))

import numpy as np  # noqa: E402
import glyphs  # noqa: E402
import synth  # noqa: E402

from ports.deskew import angle, level  # noqa: E402


def written(text, y0=0.0, font=None):
    """Letter strokes (lists of (x, y) page points, y down) of `text` with a handwriting skeleton."""
    src = synth.GlyphSource(font)
    out, x = [], 0.0
    for ch in text:
        if ch == " ":
            x += src.space
            continue
        advance, parts = src.get(ch)
        pts = np.concatenate([glyphs.endpoints(p) for p in parts])
        cx = float((pts[:, 0].min() + pts[:, 0].max()) / 2)
        width = float(pts[:, 0].max() - pts[:, 0].min())
        for part in parts:
            e = glyphs.endpoints(part) * 1.6
            out.append([(float(px + (x - cx + width / 2) * 1.6), float(-py + y0)) for px, py in e])
        x += max(advance, width * 0.6) + src.tracking
    return out


def turned(strokes, deg):
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a)
    return [[(c * x - s * y, s * x + c * y) for x, y in st] for st in strokes]


@pytest.mark.parametrize("deg", [19, -12, 25, 7, -30])
def test_angle_of_a_turned_line(deg):
    assert abs(angle(turned(written("Neler oluyor? Bugün hava güzel."), deg)) - deg) <= 2


def test_level_line_stays_level():
    assert abs(angle(written("Neler oluyor? Bugün hava güzel."))) <= 1


def test_short_word():
    assert abs(angle(turned(written("için"), 19)) - 19) <= 3


def test_two_lines():
    both = written("Birinci satır burada.") + written("İkinci satır da var.", y0=40)
    assert abs(angle(turned(both, 15)) - 15) <= 2


def test_level_undoes_the_turn():
    strokes = turned(written("Neler oluyor?"), 19)
    flat = level(strokes, angle(strokes))
    assert abs(angle(flat)) <= 1


def test_too_little_ink_is_left_alone():
    assert angle([[(10.0, 10.0), (11.0, 10.5)]]) == 0.0
    assert angle([]) == 0.0
