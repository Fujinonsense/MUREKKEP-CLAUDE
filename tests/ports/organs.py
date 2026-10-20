"""Port of the organ part of SketchRecognizer.recognize (kidney/spleen vs a plain circle).

Templates come from the app's own sticker outlines (StickerArtData.swift, the F* body path of
@kidney and @spleen), flattened like StickerArt.flatten (12 samples per cubic), resampled to 64
points, normalized to the unit square, in 8 orientations.
"""
import math
import re

from sketch import concavities, convex_hull, resample, segment_distance, smooth

KIDNEY = "M56 10 C76 10 84 30 80 50 C78 72 72 90 54 90 C36 90 26 76 30 64 C36 58 42 56 40 50 C40 44 34 42 30 36 C24 22 38 10 56 10 Z"
SPLEEN = "M20 30 C34 12 70 10 86 27 C94 37 91 55 81 66 C71 77 53 87 35 85 C23 83 27 71 35 65 C41 59 31 51 23 47 C15 43 14 36 20 30 Z"


def flatten(path):
    tok = re.findall(r"[MCZ]|-?\d+(?:\.\d+)?", path)
    out = []
    cur = start = (0.0, 0.0)
    i = 0
    while i < len(tok):
        c = tok[i]
        if c == "M":
            cur = start = (float(tok[i + 1]), float(tok[i + 2]))
            out.append(cur)
            i += 3
        elif c == "C":
            a = (float(tok[i + 1]), float(tok[i + 2]))
            b = (float(tok[i + 3]), float(tok[i + 4]))
            p = (float(tok[i + 5]), float(tok[i + 6]))
            for k in range(1, 13):
                s = k / 12
                u = 1 - s
                w0, w1, w2, w3 = u * u * u, 3 * u * u * s, 3 * u * s * s, s * s * s
                out.append((w0 * cur[0] + w1 * a[0] + w2 * b[0] + w3 * p[0], w0 * cur[1] + w1 * a[1] + w2 * b[1] + w3 * p[1]))
            cur = p
            i += 7
        elif c == "Z":
            out.append(start)
            cur = start
            i += 1
        else:
            raise ValueError(c)
    return out


def normalized(p):
    xs = [q[0] for q in p]
    ys = [q[1] for q in p]
    sx = max(max(xs) - min(xs), 1e-6)
    sy = max(max(ys) - min(ys), 1e-6)
    return [((q[0] - min(xs)) / sx, (q[1] - min(ys)) / sy) for q in p]


def chamfer(a, b):
    def one(x, y):
        return sum(min(math.hypot(p[0] - q[0], p[1] - q[1]) for q in y) for p in x) / max(len(x), 1)
    return (one(a, b) + one(b, a)) / 2


def orientations(p):
    out = []
    for turns in range(4):
        for mirror in (1, -1):
            q = []
            for x, y in p:
                x = (x - 50) * mirror
                y = y - 50
                for _ in range(turns):
                    x, y = -y, x
                q.append((x, y))
            out.append(normalized(resample(q, 64)))
    return out


KIDNEY_T = orientations(flatten(KIDNEY))
SPLEEN_T = orientations(flatten(SPLEEN))
ELLIPSE_T = normalized([(math.cos(2 * math.pi * i / 64), math.sin(2 * math.pi * i / 64)) for i in range(64)])


def junction_concavities(pts, ignore=0.12):
    """concavities() that skips dents whose deepest point is within `ignore` of the loop's ends
    (where the hand closes the loop)."""
    n = len(pts)
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    size = max(max(xs) - min(xs), max(ys) - min(ys), 1e-6)
    hull = sorted(convex_hull(pts))
    if len(hull) < 3:
        return []
    out = []
    for k in range(len(hull)):
        a = hull[k]
        c = hull[(k + 1) % len(hull)]
        depth, where = 0.0, a
        i = (a + 1) % n
        while i != c:
            d = segment_distance(pts[i], pts[a], pts[c])
            if d > depth:
                depth, where = d, i
            i = (i + 1) % n
        if depth <= 0:
            continue
        if min(where, n - where) < ignore * n:
            continue
        out.append(depth / size)
    return sorted(out, reverse=True)


# The rule the Swift code uses now (SketchRecognizer.recognize, 3.0).
RULE = "new"


def organ(loop, rule=None):
    """'kidney', 'spleen' or None for a closed loop, with the 2.9 rule ('old') or the new one:
    the notch (hilum) must be at least 10 % deep and away from where the hand closed the loop."""
    rule = rule or RULE
    shape = normalized(resample(loop, 64))
    to_kidney = min(chamfer(shape, t) for t in KIDNEY_T)
    to_spleen = min(chamfer(shape, t) for t in SPLEEN_T)
    prepared = smooth(resample(loop, 96), True, 2)
    if rule == "old":
        notches = [d for d in concavities(prepared) if d > 0.07]
        notched = 1 <= len(notches) <= 2 and 0.08 <= notches[0] < 0.4
    else:
        notches = [d for d in junction_concavities(prepared) if d > 0.07]
        notched = 1 <= len(notches) <= 2 and 0.10 <= notches[0] < 0.4
    found = []
    if notched and to_kidney < 0.06:
        found.append((to_kidney, "kidney"))
    if notched and to_spleen < 0.06:
        found.append((to_spleen, "spleen"))
    return min(found)[1] if found else None
