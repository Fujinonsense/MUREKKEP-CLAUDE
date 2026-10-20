"""Port of InkDeskew (Murekkep.swiftpm/InkDeskew.swift): the angle of the writing on the page.

The ink's points are turned through every angle from -35° to 35° (1° steps, then ±1° in 0.25° steps
around the best); the angle at which the points pile up in the fewest, fullest horizontal bands
(bins a quarter of a letter high; score = sum of squared bin counts) is the writing's direction.
An angle that scores less than 3 % better than level is treated as level. Angles are in degrees,
y down: a positive angle is writing that goes down to the right."""
import math
import statistics

MAX_DEG = 35.0
MIN_GAIN = 1.03
MAX_POINTS = 3000


def _points(strokes):
    pts = [p for s in strokes for p in s]
    if len(pts) > MAX_POINTS:
        step = len(pts) / MAX_POINTS
        pts = [pts[int(i * step)] for i in range(MAX_POINTS)]
    return pts


def _letter_height(strokes):
    hs = [max(p[1] for p in s) - min(p[1] for p in s) for s in strokes if s]
    big = [h for h in hs if h >= 3]
    return statistics.median(big) if big else max(hs + [1.0])


def _score(pts, deg, bin_size):
    a = math.radians(deg)
    s, c = math.sin(a), math.cos(a)
    ys = [-x * s + y * c for x, y in pts]
    lo = min(ys)
    counts = {}
    for y in ys:
        k = int((y - lo) / bin_size)
        counts[k] = counts.get(k, 0) + 1
    return sum(v * v for v in counts.values())


def angle(strokes):
    pts = _points(strokes)
    if len(pts) < 8:
        return 0.0
    xs = [p[0] for p in pts]
    if max(xs) - min(xs) < 1e-6:
        return 0.0
    bin_size = max(_letter_height(strokes) / 4, 0.5)
    level_score = _score(pts, 0.0, bin_size)
    best_deg, best = 0.0, level_score
    deg = -MAX_DEG
    while deg <= MAX_DEG + 1e-9:
        sc = _score(pts, deg, bin_size)
        if sc > best:
            best_deg, best = deg, sc
        deg += 1.0
    centre = best_deg
    for k in range(-4, 5):
        d = centre + k * 0.25
        sc = _score(pts, d, bin_size)
        if sc > best:
            best_deg, best = d, sc
    if best < level_score * MIN_GAIN:
        return 0.0
    return best_deg


def level(strokes, deg):
    """The strokes turned by -deg around their centre (the writing made level)."""
    pts = [p for s in strokes for p in s]
    if not pts or deg == 0:
        return [list(s) for s in strokes]
    cx = sum(p[0] for p in pts) / len(pts)
    cy = sum(p[1] for p in pts) / len(pts)
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a)
    return [[(cx + (x - cx) * c + (y - cy) * s, cy - (x - cx) * s + (y - cy) * c) for x, y in st] for st in strokes]
