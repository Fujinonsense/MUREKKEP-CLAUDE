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
