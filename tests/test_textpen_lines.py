"""The text pen's line finder on handwriting whose letters come in several strokes (held-out
handwriting fonts written as pen strokes, tools/textpencheck/gen_cases.py), on level and turned pages:
before the fix 217 of 531 such writings were split into the right number of lines, after it 515.
This keeps a sample of them right. Needs the fonts in MRK_DATA (C:/Users/orsyu/mrk-ml/data)."""
import os
import sys
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parent.parent
DATA = Path(os.environ.get("MRK_DATA", "C:/Users/orsyu/mrk-ml/data"))
if not (DATA / "fonts").exists():
    pytest.skip("handwriting fonts not here", allow_module_level=True)
np = pytest.importorskip("numpy")
pytest.importorskip("scipy")
pytest.importorskip("PIL")
pytest.importorskip("fontTools")
pytest.importorskip("skimage")

sys.path.insert(0, str(REPO / "ml" / "handwriting"))
sys.path.insert(0, str(REPO / "tools" / "textpencheck"))
from ports import deskew, inkline  # noqa: E402


@pytest.fixture(scope="module")
def writer():
    # gen_cases.py without running it: its `write` and `turn`.
    source = (REPO / "tools" / "textpencheck" / "gen_cases.py").read_text(encoding="utf-8")
    source = source.replace("weights = infer_np.load(MODEL)\n", "").replace("\nmain()\n", "\n")
    g = {"__name__": "gen_cases"}
    old = sys.argv
    sys.argv = ["gen_cases.py", str(REPO)]
    try:
        exec(compile(source, "gen_cases.py", "exec"), g)
    finally:
        sys.argv = old
    return g


def found(strokes):
    lev = deskew.level(strokes, deskew.angle(strokes))
    return inkline.lines(lev)


def test_one_line_in_pieces(writer):
    rng = np.random.default_rng(3)
    fonts = [None] + writer["held_out"][:6]
    right = total = 0
    for text in ["Neler oluyor?", "Bugün hava çok güzel.", "Türevin tanımı", "Öğrenciler sınava çalışıyor"]:
        for f in fonts:
            for deg in (0.0, -19.0):
                try:
                    st = writer["turn"](writer["write"](text, f, rng), deg)
                except KeyError:
                    continue
                total += 1
                right += len(found(st)) == 1
    assert right >= 0.9 * total, f"{right}/{total} read as one line"


def test_two_lines_in_pieces(writer):
    rng = np.random.default_rng(4)
    right = total = 0
    for f in [None] + writer["held_out"][:6]:
        for a, b in [("Bugün hava çok güzel.", "Yarın sınav var"), ("Neler oluyor?", "için")]:
            try:
                first = writer["write"](a, f, rng)
                cap = max(p[1] for s in first for p in s) - min(p[1] for s in first for p in s)
                second = writer["write"](b, f, rng, y0=200.0 + cap * 1.9)
            except KeyError:
                continue
            total += 1
            right += len(found(first + second)) == 2
    assert right >= 0.9 * total, f"{right}/{total} read as two lines"
