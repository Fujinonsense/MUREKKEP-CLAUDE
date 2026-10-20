import math

import numpy as np

from charset import CHARSET, encode
from ink_render import CORE, HEIGHT, TOP, line_transform, render_ink, render_line


def scribble(cap, x0=100.0, y0=200.0, letters=6):
    """A handwriting-like line: loops of x-height with an ascender every third letter, cap `cap` pt."""
    s = cap / 10
    strokes = []
    for k in range(letters):
        cx = x0 + k * 6.5 * s
        loop = [(cx + 3 * s * math.cos(a), y0 - 3.5 * s + 3.5 * s * math.sin(a))
                for a in np.linspace(0, 2 * math.pi, 24)]
        strokes.append(loop)
        if k % 3 == 0:
            strokes.append([(cx + 3 * s, y0 - 10 * s), (cx + 3 * s, y0)])
    return strokes


def test_core_band_is_30px_from_y9():
    strokes = scribble(15)
    scale, dx, dy = line_transform(strokes)
    ys = np.concatenate([np.asarray(s)[:, 1] for s in strokes])
    p5, p95 = np.percentile(ys, [5, 95])
    assert math.isclose(p5 * scale + dy, TOP, abs_tol=1e-6)
    assert math.isclose(p95 * scale + dy, TOP + CORE, abs_tol=1e-6)
    img = render_line(strokes)
    assert img.shape[0] == HEIGHT
    rows = np.where(img.max(axis=1) > 0.3)[0]
    assert rows.min() >= TOP - 12 and rows.max() <= TOP + CORE + 3


def test_size_does_not_matter():
    small, big = render_line(scribble(6)), render_line(scribble(60))
    assert abs(small.shape[1] - big.shape[1]) <= 4
    w = min(small.shape[1], big.shape[1])
    a, b = small[:, :w].ravel(), big[:, :w].ravel()
    assert np.corrcoef(a, b)[0, 1] > 0.9


def test_pen_width_is_ignored():
    pts = scribble(15)
    lava = [{"points": p, "brush": "lava", "width": 7.0} for p in pts]
    pen = [{"points": p, "brush": "pen", "width": 2.2} for p in pts]
    assert np.array_equal(render_ink(lava), render_ink(pen))


def test_width_is_multiple_of_4_and_clamped():
    dot = render_line([[(10.0, 10.0)]])
    assert dot.shape[1] == 16
    long_line = render_line(scribble(15, letters=400))
    assert long_line.shape[1] == 1600
    for n in (1, 3, 7, 12):
        assert render_line(scribble(15, letters=n)).shape[1] % 4 == 0


def test_charset_encodes_turkish_and_math():
    ids = encode("İstanbul'da ğüşıöç x≤√2")
    assert len(ids) == len("İstanbul'da ğüşıöç x≤√2")
    assert min(ids) >= 1 and max(ids) <= len(CHARSET)
