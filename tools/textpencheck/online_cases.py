"""The pen-motion reader (OnlineReader) on the text pen cases: what the picture reader alone reads,
what the pen-motion reader alone reads, and what the two read together (Reading.choose, without
Vision and the dictionary), for a grid of weights and floors. With --out it also writes the cases
again with the pen-motion reader's numbers for the Swift check (main.swift compares them).
With --kinematic N it reads N lines written by the Kinematic Stroke Generator instead (a seed never
trained on), whose strokes come in a hand's order, unlike the font skeletons of the cases.
usage: python online_cases.py <repo> <cases.json> <hwonline.bin> [--grid] [--out cases-online.json]
       [--kinematic N]"""
import collections
import json
import math
import sys

import numpy as np

repo = sys.argv[1]
sys.path.insert(0, repo + "/ml/handwriting")
sys.path.insert(0, repo + "/tests")
import infer_np  # noqa: E402
import online  # noqa: E402
from charset import CHARSET  # noqa: E402
from ink_render import render_line  # noqa: E402
from ports import ctc, deskew, inkline, reading  # noqa: E402

weights = infer_np.load(repo + "/Murekkep.swiftpm/Assets.xcassets/hwmodel.dataset/hwmodel.bin")
_, pen = online.load(sys.argv[3])
GRID = "--grid" in sys.argv
OUT = sys.argv[sys.argv.index("--out") + 1] if "--out" in sys.argv else None


def is_math(text):
    return sum(c in "=+-×÷<>≤≥√^0123456789" for c in text) >= 2 or "=" in text


def lines_of(case):
    """[(offline beam, offline lp, online lp, online features)] for each line the finder makes."""
    st = [[tuple(p) for p in s] for s in case["strokes"]]
    lev = deskew.level(st, deskew.angle(st))
    out = []
    for line in inkline.lines(lev):
        base, _ = inkline.split_raised(lev, line)
        strokes = [lev[i] for i in base]
        lp = infer_np.log_probs(weights, render_line(strokes))
        feats = online.features(strokes)
        olp = online.log_probs(pen, feats) if len(feats) else None
        out.append((ctc.beam(lp, CHARSET), lp, olp, feats))
    return out


def candidates(beam, lp, olp):
    """Texts the two readers propose, with the picture's and the pen's log P."""
    seen = {t for t, _ in beam}
    extra = []
    if olp is not None:
        for t, _ in ctc.beam(olp, CHARSET):
            if t not in seen:
                seen.add(t)
                extra.append(t)
    others = [(t, ctc.score(t, lp, CHARSET)) for t in extra]
    scores = None
    if olp is not None:
        scores = {t: ctc.score(t, olp, CHARSET) for t in [t for t, _ in beam] + extra}
    return others, scores


def together(beam, others, scores, weight, floor):
    old = reading.ONLINE_WEIGHT, reading.ONLINE_FLOOR
    reading.ONLINE_WEIGHT, reading.ONLINE_FLOOR = weight, floor
    try:
        first = beam[0][0]
        return reading.choose(beam, others, len(first), is_math(first), lambda t: 0.0, scores)
    finally:
        reading.ONLINE_WEIGHT, reading.ONLINE_FLOOR = old


def main():
    if "--kinematic" in sys.argv:
        import kinematic
        import texts
        rng = np.random.default_rng(4242)
        data = {"charset": CHARSET, "cases": []}
        for _ in range(int(sys.argv[sys.argv.index("--kinematic") + 1])):
            text = texts.sample(rng).strip()
            if text:
                data["cases"].append({"texts": [text], "radius": 0, "strokes": kinematic.write(text, rng)})
    else:
        data = json.load(open(sys.argv[2], encoding="utf-8"))
    cases = [c for c in data["cases"] if c["radius"] == 0]
    settings = [(reading.ONLINE_WEIGHT, reading.ONLINE_FLOOR)]
    if GRID:
        settings = [(w, f) for w in (0.0, 0.25, 0.5, 0.75, 1.0, 1.5, 2.0) for f in (-1.0, -2.0, -4.0)]
    exact = collections.Counter()
    alone = picture = 0
    kept = 0
    for n, case in enumerate(cases):
        got = lines_of(case)
        picture += [b[0][0] for b, _, _, _ in got] == case["texts"]
        alone += [ctc.beam(o, CHARSET)[0][0] if o is not None else "" for _, _, o, _ in got] == case["texts"]
        prepared = [(b, *candidates(b, lp, o)) for b, lp, o, _ in got]
        for s in settings:
            exact[s] += [together(b, others, scores, *s) for b, others, scores in prepared] == case["texts"]
        if OUT and "python" in case:
            py = case["python"]
            if len(py["lines"]) == len(got):
                for pl, (b, lp, o, feats), (_, others, scores) in zip(py["lines"], got, prepared):
                    pl["onlineText"] = ctc.beam(o, CHARSET)[0][0] if o is not None else ""
                    pl["together"] = together(b, others, scores, reading.ONLINE_WEIGHT, reading.ONLINE_FLOOR)
                    if "image" in pl and kept < 120:
                        pl["onlineFeatures"] = [[round(float(v), 5) for v in row] for row in feats]
                        pl["onlineLogProbs"] = [[round(float(v), 4) for v in row] for row in o]
                        kept += 1
        if n % 50 == 0:
            print(f"{n}/{len(cases)}", flush=True)
    total = len(cases)
    print(f"picture reader alone: exact {picture}/{total}; pen-motion reader alone: {alone}/{total}")
    for s in settings:
        print(f"  together, weight {s[0]:.2f} floor {s[1]:.1f}: exact {exact[s]}/{total}")
    if OUT:
        json.dump(data, open(OUT, "w", encoding="utf-8"), ensure_ascii=False)
        print("wrote", OUT)


main()
