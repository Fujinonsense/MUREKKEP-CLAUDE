"""The font-image generator (ml/handwriting/font_lines.py): lines drawn whole by the twelve requested
handwriting fonts, letter spacing and baseline wandering at random, bent by an elastic transform, and
redrawn as the app draws a line for the model. Needs the fonts (fetch_handfonts.py) in MRK_DATA."""
import os
import sys
from pathlib import Path

import pytest

DATA = Path(os.environ.get("MRK_DATA", "C:/Users/orsyu/mrk-ml/data"))
if not (DATA / "handfonts" / "handfonts.json").exists():
    pytest.skip("handwriting fonts not fetched", allow_module_level=True)
np = pytest.importorskip("numpy")
pytest.importorskip("scipy")
pytest.importorskip("skimage")
pytest.importorskip("fontTools")

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "ml" / "handwriting"))
import font_lines  # noqa: E402
from ink_render import HEIGHT  # noqa: E402


def test_all_twelve_families_are_there():
    names = {f.path.name.split("[")[0].split("-")[0].replace(".ttf", "").lower() for f in font_lines.fonts()}
    for family in ["shantellsans", "playpensans", "caveat", "mynerve", "delicioushandrawn", "patrickhand", "kalam",
                   "shadowsintolighttwo", "reeniebeanie", "cedarville", "gloriahallelujah", "indieflower"]:
        assert any(n.startswith(family) for n in names), family


def test_turkish_text_only_with_turkish_fonts():
    rng = np.random.default_rng(0)
    for _ in range(40):
        f = font_lines.pick_font(rng, "Şimdi ığdır çözüm", font_lines.fonts())
        assert f is not None and f.turkish and f.covers("Şimdi ığdır çözüm")
    english = {font_lines.pick_font(rng, "the quick fox", font_lines.fonts()).path.name for _ in range(200)}
    assert "ReenieBeanie.ttf" in english  # English-only fonts still write English


def test_line_is_what_the_model_reads():
    rng = np.random.default_rng(1)
    for text in ["Bugün hava çok güzel.", "x² + 3x = 7", "Iğdır'a gidiyoruz"]:
        img, got = font_lines.make_line(rng, font_lines.fonts(), text)
        assert got == text
        assert img.dtype == np.float32 and img.shape[0] == HEIGHT and img.shape[1] % 4 == 0
        assert 0.0 <= img.min() and img.max() <= 1.0 and img.sum() > 50


def test_elastic_bends_but_keeps_the_ink():
    rng = np.random.default_rng(2)
    img, _ = font_lines.draw("Öğrenciler sınava çalışıyor", font_lines.fonts()[0].path, rng)
    same = font_lines.elastic(img, rng, magnitude=0, sigma=10)
    assert np.array_equal(same, img)
    bent = font_lines.elastic(img, np.random.default_rng(3), magnitude=3.0, sigma=12)
    assert not np.array_equal(bent, img)
    assert abs(bent.sum() - img.sum()) / img.sum() < 0.1


def test_same_seed_same_line():
    a = font_lines.make_line(np.random.default_rng(5), font_lines.fonts(), "Neler oluyor?")
    b = font_lines.make_line(np.random.default_rng(5), font_lines.fonts(), "Neler oluyor?")
    assert np.array_equal(a[0], b[0])


def test_training_mix_uses_them():
    import synth

    pool = synth.FontPool(synth.split_fonts()[0][:3], image_fonts=font_lines.training_fonts())
    rng = np.random.default_rng(6)
    lines = [synth.make_line(rng, pool) for _ in range(30)]
    assert all(img.shape[0] == HEIGHT for img, _ in lines)
    assert font_lines.training_fonts()
