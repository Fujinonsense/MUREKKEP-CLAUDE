"""Reads the text pen cases again with the current Python twins (line finder, levelling, renderer,
model, CTC) and counts exact readings and right line counts, with or without the pen's radius
(boxes grown by the radius, as Stroke.bounds does in the app).
usage: python eval_python.py <repo> <cases.json> [--radius] [--lines-only] [--show N] [--model hwmodel.bin]"""
import collections
import json
import sys

repo = sys.argv[1]
sys.path.insert(0, repo + "/ml/handwriting")
sys.path.insert(0, repo + "/tests")
import infer_np  # noqa: E402
from charset import CHARSET  # noqa: E402
from ink_render import render_line  # noqa: E402
from ports import ctc, deskew, inkline  # noqa: E402

weights = infer_np.load(sys.argv[sys.argv.index("--model") + 1] if "--model" in sys.argv
                        else repo + "/Murekkep.swiftpm/Assets.xcassets/hwmodel.dataset/hwmodel.bin")
RADIUS = "--radius" in sys.argv
LINES_ONLY = "--lines-only" in sys.argv
SHOW = int(sys.argv[sys.argv.index("--show") + 1]) if "--show" in sys.argv else 0


class RadiusBox(inkline.Box):
    """A box grown by the pen's radius on every side, like Stroke.bounds."""
    r = 0.0

    def __init__(self, pts):
        super().__init__(pts)
        r = RadiusBox.r
        self.min_x -= r
        self.max_x += r
        self.min_y -= r
        self.max_y += r
        self.h = self.max_y - self.min_y
        self.w = self.max_x - self.min_x


def read(case):
    st = [[tuple(p) for p in s] for s in case["strokes"]]
    lev = deskew.level(st, deskew.angle(st))
    RadiusBox.r = case["radius"]
    found = inkline.lines(lev)
    if LINES_ONLY:
        return [str(len(g)) for g in found]
    out = []
    for line in found:
        base, _ = inkline.split_raised(lev, line)
        lp = infer_np.log_probs(weights, render_line([lev[i] for i in base]))
        out.append(ctc.beam(lp, CHARSET)[0][0])
    return out


def main():
    inkline.Box = RadiusBox
    cases = [c for c in json.load(open(sys.argv[2], encoding="utf-8"))["cases"]
             if (c["radius"] > 0) == RADIUS and (not RADIUS or c["radius"] > 2)]
    by = collections.defaultdict(lambda: [0, 0, 0])
    shown = 0
    for c in cases:
        got = read(c)
        key = (len(c["texts"]), c["angle"])
        by[key][1] += len(got) == len(c["texts"])
        by[key][2] += 1
        if not LINES_ONLY:
            ok = got == c["texts"]
            by[key][0] += ok
            if not ok and shown < SHOW:
                print(" ", c["texts"], "->", got, c["font"], c["angle"])
                shown += 1
    tot = [sum(v[i] for v in by.values()) for i in range(3)]
    print(f"radius {'thick' if RADIUS else 'none'}: exact {tot[0]}/{tot[2]}, right line count {tot[1]}/{tot[2]}")
    for k, v in sorted(by.items()):
        print(f"  lines {k[0]} angle {k[1]:>5}: exact {v[0]}/{v[2]}, line count {v[1]}/{v[2]}")


main()
