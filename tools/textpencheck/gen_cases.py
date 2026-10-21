"""Cases for the text pen check (tools/textpencheck): handwriting written with held-out handwriting
fonts as pen strokes (continuous polylines, dots and accents their own strokes), on level and turned
pages, in one and two lines, with the radius a thin pen and a thick 3D pen give every point. For the
cases without radius it also records what the Python twins read (deskew, line finder, renderer, model,
CTC), so the app's own Swift code can be compared with them number by number.
usage: python gen_cases.py <repo> <out.json>"""
import json
import math
import sys

import numpy as np

repo = sys.argv[1]
sys.path.insert(0, repo + "/ml/handwriting")
sys.path.insert(0, repo + "/tests")
import glyphs  # noqa: E402
import infer_np  # noqa: E402
import synth  # noqa: E402
from charset import CHARSET  # noqa: E402
from ink_render import render_line  # noqa: E402
from ports import ctc, deskew, inkline  # noqa: E402

MODEL = repo + "/Murekkep.swiftpm/Assets.xcassets/hwmodel.dataset/hwmodel.bin"
weights = infer_np.load(MODEL)
_, held_out = synth.split_fonts()

PHRASES = [
    "Neler oluyor?", "için", "Bugün hava çok güzel.", "Türevin tanımı", "Öğrenciler sınava çalışıyor",
    "Işık ve gölge", "Şimdi değil", "The quick brown fox", "Fotosentez", "Osmanlı Devleti 1299",
    "Ağaç", "limit ve süreklilik", "Çözüm: 12 + 7 = 19", "kuvvet = kütle × ivme", "What is happening?",
]
TWO_LINES = [("Bugün hava çok güzel.", "Yarın sınav var"), ("Neler oluyor?", "için"),
             ("Türevin tanımı", "limit ve süreklilik")]
ANGLES = [0.0, -19.0, 8.0]
RADII = [0.0, 1.1, 2.6]  # no radius (compared with Python), a ballpoint, a thick 3D pen
PT = 1.6  # page points per font unit: capitals about 16 pt high


def polylines(seg):
    """A glyph part's segments as pen strokes. A font skeleton comes as loose segments, so they are
    chained into trails the way a pen would draw them: each trail starts at a loose end (a vertex of
    odd degree) and keeps going straightest through unused segments. A letter becomes 1–4 strokes."""
    def key(x, y):
        return (round(x, 2), round(y, 2))

    edges = []
    adj = {}
    for x0, y0, x1, y1 in seg.tolist():
        a, b = key(x0, y0), key(x1, y1)
        if a == b:
            continue
        e = len(edges)
        edges.append((a, b))
        adj.setdefault(a, []).append(e)
        adj.setdefault(b, []).append(e)
    used = [False] * len(edges)
    out = []

    def left(v):
        return [e for e in adj[v] if not used[e]]

    while not all(used):
        free = [v for v in adj if left(v)]
        odd = [v for v in free if len(left(v)) % 2 == 1]
        v = min(odd or free)
        trail = [v]
        prev = None
        while left(v):
            options = left(v)
            if prev is not None:
                hx, hy = v[0] - prev[0], v[1] - prev[1]

                def turn(e):
                    a, b = edges[e]
                    w = b if a == v else a
                    dx, dy = w[0] - v[0], w[1] - v[1]
                    return -(hx * dx + hy * dy) / (math.hypot(hx, hy) * math.hypot(dx, dy) + 1e-9)
                options.sort(key=turn)
            e = options[0]
            used[e] = True
            a, b = edges[e]
            prev, v = v, (b if a == v else a)
            trail.append(v)
        out.append(trail)
    if not out and len(seg):
        out.append([(float(seg[0, 0]), float(seg[0, 1]))])  # a dot
    return out


def write(text, font, rng, x0=60.0, y0=200.0):
    """Pen strokes of `text` in page points (y down), every glyph slightly different."""
    src = synth.GlyphSource(font)
    strokes, x = [], 0.0
    for ch in text:
        if ch == " ":
            x += src.space
            continue
        advance, parts = src.get(ch)
        pts = np.concatenate([glyphs.endpoints(p) for p in parts])
        cx = float((pts[:, 0].min() + pts[:, 0].max()) / 2)
        width = float(pts[:, 0].max() - pts[:, 0].min())
        k = 1 + rng.uniform(-0.06, 0.06)
        for part in parts:
            seg = part.astype(np.float64).copy() * k
            seg[:, [0, 2]] += x - cx * k + width / 2
            for line in polylines(seg):
                strokes.append([(x0 + px * PT, y0 - py * PT) for px, py in line])
        x += max(advance * k, width * k * 0.6) + src.tracking
    return strokes


def turn(strokes, deg):
    pts = [p for s in strokes for p in s]
    cx = sum(p[0] for p in pts) / len(pts)
    cy = sum(p[1] for p in pts) / len(pts)
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a)
    return [[(cx + (x - cx) * c - (y - cy) * s, cy + (x - cx) * s + (y - cy) * c) for x, y in st] for st in strokes]


def python_reading(strokes, keep_arrays):
    deg = deskew.angle(strokes)
    lev = deskew.level(strokes, deg)
    lines = inkline.lines(lev)
    out = []
    for line in lines:
        base, raised = inkline.split_raised(lev, line)
        img = render_line([lev[i] for i in base])
        lp = infer_np.log_probs(weights, img)
        best = ctc.beam(lp, CHARSET)[0]
        item = {"members": line, "base": base, "text": best[0], "score": float(best[1]), "width": int(img.shape[1]),
                "inkSum": float(img.sum())}
        if keep_arrays:
            item["image"] = [round(float(v), 4) for v in img.ravel()]
            item["logProbs"] = [[round(float(v), 4) for v in row] for row in lp]
        out.append(item)
    return {"angle": float(deg), "lines": out}


def main():
    rng = np.random.default_rng(7)
    fonts = [None] + held_out[:10]
    cases, kept = [], 0
    for text in PHRASES:
        for f in fonts:
            for deg in ANGLES:
                try:
                    st = write(text, f, rng)
                except KeyError:
                    continue
                cases.append({"texts": [text], "font": f and str(f).split("/")[-1].split("\\")[-1], "angle": deg,
                              "strokes": turn(st, deg)})
    for a, b in TWO_LINES:
        for f in fonts[:6]:
            for deg in (0.0, -19.0):
                try:
                    first = write(a, f, rng)
                    cap = max(p[1] for s in first for p in s) - min(p[1] for s in first for p in s)
                    second = write(b, f, rng, y0=200.0 + max(cap, 16 * 1.0) * 1.9)
                except KeyError:
                    continue
                cases.append({"texts": [a, b], "font": f and str(f).split("/")[-1].split("\\")[-1], "angle": deg,
                              "strokes": turn(first + second, deg)})
    out = []
    for i, case in enumerate(cases):
        strokes = case.pop("strokes")
        for r in RADII:
            item = dict(case, radius=r, strokes=[[[round(x, 3), round(y, 3)] for x, y in s] for s in strokes])
            if r == 0:
                keep = kept < 40
                kept += keep
                item["python"] = python_reading([[tuple(p) for p in s] for s in item["strokes"]], keep)
            out.append(item)
        if i % 50 == 0:
            print(f"{i}/{len(cases)}", flush=True)
    json.dump({"charset": CHARSET, "cases": out}, open(sys.argv[2], "w", encoding="utf-8"), ensure_ascii=False)
    print(f"{len(out)} cases from {len(cases)} writings")


main()
