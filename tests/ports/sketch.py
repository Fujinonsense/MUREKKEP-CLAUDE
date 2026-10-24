"""Python ports of SketchRecognizer helpers (SketchRecognizer.swift, Geo in ShapeRecognizer.swift)."""
import math


def dist(a, b):
    return math.hypot(a[0] - b[0], a[1] - b[1])


def length(p):
    return sum(dist(p[i - 1], p[i]) for i in range(1, len(p)))


def resample(p, n):
    total = length(p)
    if total <= 0 or len(p) < 2 or n < 2:
        return list(p)
    step = total / (n - 1)
    out = [p[0]]
    acc = 0.0
    for i in range(1, len(p)):
        a = p[i - 1]
        b = p[i]
        d = dist(a, b)
        while acc + d >= step and d > 0 and len(out) < n:
            t = (step - acc) / d
            q = (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)
            out.append(q)
            a = q
            d = dist(a, b)
            acc = 0.0
        acc += d
    while len(out) < n:
        out.append(p[-1])
    return out


def smooth(p, closed, k):
    n = len(p)
    if n <= 2 * k + 1:
        return list(p)
    out = []
    for i in range(n):
        sx = sy = 0.0
        for j in range(-k, k + 1):
            idx = ((i + j) % n + n) % n if closed else min(max(i + j, 0), n - 1)
            sx += p[idx][0]
            sy += p[idx][1]
        c = 2 * k + 1
        out.append((sx / c, sy / c))
    if not closed:
        out[0] = p[0]
        out[-1] = p[-1]
    return out


def segment_distance(p, a, b):
    dx, dy = b[0] - a[0], b[1] - a[1]
    l2 = dx * dx + dy * dy
    if l2 <= 1e-9:
        return dist(p, a)
    t = min(max(((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / l2, 0.0), 1.0)
    return math.hypot(p[0] - a[0] - t * dx, p[1] - a[1] - t * dy)


def convex_hull(pts):
    order = sorted(range(len(pts)), key=lambda i: (pts[i][0], pts[i][1]))

    def cross(o, a, b):
        return (pts[a][0] - pts[o][0]) * (pts[b][1] - pts[o][1]) - (pts[a][1] - pts[o][1]) * (pts[b][0] - pts[o][0])

    lower = []
    for i in order:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], i) <= 0:
            lower.pop()
        lower.append(i)
    upper = []
    for i in reversed(order):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], i) <= 0:
            upper.pop()
        upper.append(i)
    return lower[:-1] + upper[:-1]


def concavities(pts):
    """How deep the outline dips inside its convex hull, relative to its size (deepest first)."""
    n = len(pts)
    if n < 5:
        return []
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
        depth = 0.0
        i = (a + 1) % n
        while i != c:
            depth = max(depth, segment_distance(pts[i], pts[a], pts[c]))
            i = (i + 1) % n
        if depth > 0:
            out.append(depth / size)
    return sorted(out, reverse=True)


def _turns(loop, n=96, w=4):
    """The closed loop resampled to n points: the signed turn at each point over w points either side,
    and the total turning around the loop."""
    p = resample(loop, n + 1)[:-1]
    m = len(p)

    def ang(a, b):
        return math.atan2(b[1] - a[1], b[0] - a[0])

    def wrap(x):
        while x > math.pi:
            x -= 2 * math.pi
        while x < -math.pi:
            x += 2 * math.pi
        return x

    total = sum(wrap(ang(p[i], p[(i + 1) % m]) - ang(p[i - 1], p[i])) for i in range(m))
    turns = [wrap(ang(p[i], p[(i + w) % m]) - ang(p[i - w], p[i])) for i in range(m)]
    return turns, total


def _corners(turns, sign, threshold, spacing):
    """Indices where the loop turns more than `threshold` in the direction `sign`, strongest first,
    at least `spacing` points apart around the loop."""
    m = len(turns)
    picked = []
    for i in sorted(range(m), key=lambda i: -sign * turns[i]):
        if sign * turns[i] < threshold:
            break
        if all(min(abs(i - j), m - abs(i - j)) >= spacing for j in picked):
            picked.append(i)
    return picked


def star_kind(loop):
    """'crossing' (five lines, each tip joined to the one two along: the loop turns round twice),
    'outline' (five tips and five notches, turning round once) or None. Twin of SketchRecognizer.star."""
    if len(loop) < 8:
        return None
    turns, total = _turns(loop)
    m = len(turns)
    s = 1 if total > 0 else -1
    full = abs(total)
    if 4 * math.pi * 0.85 < full < 4 * math.pi * 1.15:
        return "crossing" if len(_corners(turns, s, math.radians(100), m // 12)) == 5 else None
    if 2 * math.pi * 0.8 < full < 2 * math.pi * 1.2:
        tips = _corners(turns, s, math.radians(60), m // 16)
        notches = _corners(turns, -s, math.radians(28), m // 16)
        if len(tips) == 5 and len(notches) == 5:
            return "outline"
    return None
