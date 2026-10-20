import math
import re
from pathlib import Path

import numpy as np
import pytest

pytest.importorskip("skimage")
pytest.importorskip("fontTools")

DATA = Path("C:/Users/orsyu/mrk-ml/data")
if not (DATA / "fonts").exists():
    pytest.skip("handwriting fonts not downloaded", allow_module_level=True)

import glyphs  # noqa: E402
import strokefont  # noqa: E402
import synth  # noqa: E402
import texts  # noqa: E402
from charset import CHARSET, encode  # noqa: E402

SWIFT = Path(__file__).resolve().parent.parent / "Murekkep.swiftpm" / "StrokeFont.swift"


def test_strokefont_parse_matches_swift():
    g = strokefont.glyphs()
    table = SWIFT.read_text(encoding="utf-8").split("private static let source")[1].split("\n    ]\n")[0]
    keys = re.findall(r'^\s+"((?:[^"\\]|\\.)+)":', table, re.M)
    assert len(g) == len(keys)
    assert g["A"][0] == 7.0
    assert len(g["A"][1]) == 2


def test_every_charset_char_drawable():
    train, _ = synth.split_fonts()
    for path in train[:20]:
        source = synth.GlyphSource(path)
        for ch in CHARSET:
            if ch == " ":
                continue
            advance, parts = source.get(ch)
            assert advance > 0 or ch in "Iil|'.,:;!", (path, ch)
            assert sum(len(p) for p in parts) > 0, (path.name, ch)


def test_turkish_letters_composed_when_missing():
    train, _ = synth.split_fonts()
    lacking = [p for p in train if not glyphs.covers(p, "ş")][:3]
    assert lacking, "expected some fonts without ş"
    for path in lacking:
        advance, parts = synth.GlyphSource(path).get("ş")
        assert len(parts) == 2  # the s and its cedilla


def test_caps_and_apostrophes_sampled():
    rng = np.random.default_rng(1)
    sample = "".join(texts.sample(rng) for _ in range(10000))
    for ch in "İı'\"şğ∫√":
        assert ch in sample, ch
    assert all(c in CHARSET for c in sample)


def test_make_line_shape():
    rng = np.random.default_rng(3)
    pool = synth.FontPool(synth.split_fonts()[0][:10])
    for _ in range(20):
        img, text = synth.make_line(rng, pool)
        assert img.shape[0] == 48 and img.dtype == np.float32
        assert 0 < len(text) == len(encode(text))
        assert img.max() > 0.5


def test_guide_line_and_calligraphy_fonts_excluded():
    names = [p.name for p in glyphs.fonts()]
    assert not any("Guides" in n for n in names)
    assert "MonsieurLaDoulaise-Regular.ttf" not in names


def test_caps_lines_avoid_ornate_capitals():
    rng = np.random.default_rng(5)
    pool = synth.FontPool(synth.split_fonts()[0][:60])
    for _ in range(200):
        source = synth.pick_source(rng, pool, "TOM ANAHTARI KAPIDAN ÇIKARDI.")
        assert source.path is None or source.caps_ratio <= synth.PLAIN_CAPS


def test_heldout_fonts_disjoint():
    train, val = synth.split_fonts()
    assert set(train).isdisjoint(val)
    assert len(val) == math.ceil((len(train) + len(val)) / 9)


def _baseline_angle(seg):
    """Angle (degrees) of the least-squares line through the segment midpoints."""
    mid = (seg[:, :2] + seg[:, 2:]) / 2
    x, y = mid[:, 0] - mid[:, 0].mean(), mid[:, 1] - mid[:, 1].mean()
    return math.degrees(math.atan2((x * y).sum(), (x * x).sum()))


def test_lines_are_written_at_an_angle_sometimes():
    # Real lines drift: the model must see baselines turned by several degrees, both ways, not
    # only level ones (a 6° turn broke most readings of the first model).
    rng = np.random.default_rng(5)
    source = synth.GlyphSource(None)
    angles = [_baseline_angle(synth.compose(rng, source, "Bugün hava çok güzel ve sıcak.")) for _ in range(60)]
    assert max(angles) > 4 and min(angles) < -4
    assert all(abs(a) < 11 for a in angles)
