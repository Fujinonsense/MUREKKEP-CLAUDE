"""Python ports of the stroke geometry in Murekkep.swiftpm, kept line for line with the Swift code.

- `stroke_points` mirrors `StrokeText.strokes` (StrokeFont.swift): the points a shape or typed
  text path becomes.
- `smoothed` mirrors `RibbonBuilder.smoothed` (RibbonBuilder.swift): the Catmull-Rom curve the
  renderer draws through those points.
"""
import math


def stroke_points(path, width):
    """[(x, y)] -> [(x, y, r)] exactly as StrokeText.strokes builds InkPoints: straight pieces are
    filled in so the renderer's curve cannot bulge between far-apart corners."""
    r = max(width * 0.5, 0.35)
    spacing = max(0.6, r * 0.5)
    out = []
    for i, (x, y) in enumerate(path):
        out.append((x, y, r))
        if i + 1 < len(path):
            nx, ny = path[i + 1]
            n = int(math.hypot(nx - x, ny - y) / spacing)
            for k in range(1, n):
                t = k / n
                out.append((x + (nx - x) * t, y + (ny - y) * t, r))
    return out


def _angle(a, b):
    la = math.hypot(*a)
    lb = math.hypot(*b)
    if la <= 1e-5 or lb <= 1e-5:
        return 0.0
    c = (a[0] * b[0] + a[1] * b[1]) / (la * lb)
    return math.acos(max(-1.0, min(1.0, c)))


def _catmull_rom(p0, p1, p2, p3, t):
    t2 = t * t
    t3 = t2 * t
    out = []
    for i in range(2):
        a = p1[i] * 2
        b = (p2[i] - p0[i]) * t
        c = (p0[i] * 2 - p1[i] * 5 + p2[i] * 4 - p3[i]) * t2
        d = (p1[i] * 3 - p0[i] - p2[i] * 3 + p3[i]) * t3
        out.append((a + b + c + d) * 0.5)
    return out


def smoothed(pts):
    """pts: [(x, y, r)] -> [(x, y)] following RibbonBuilder.smoothed."""
    n = len(pts)
    if n <= 2:
        return [(p[0], p[1]) for p in pts]
    out = [(pts[0][0], pts[0][1])]
    for i in range(n - 1):
        p0 = pts[max(i - 1, 0)]
        p1 = pts[i]
        p2 = pts[i + 1]
        p3 = pts[min(i + 2, n - 1)]
        seg = (p2[0] - p1[0], p2[1] - p1[1])
        length = math.hypot(*seg)
        if length < 1e-4:
            continue
        step = max(0.5, min(p1[2], p2[2]) * 0.45)
        m = int(math.ceil(length / step))
        turn = max(_angle((p1[0] - p0[0], p1[1] - p0[1]), seg), _angle(seg, (p3[0] - p2[0], p3[1] - p2[1])))
        m = max(m, int(math.ceil(turn / 0.3)))
        m = min(max(m, 1), 32)
        for k in range(1, m + 1):
            t = k / m
            x, y = _catmull_rom(p0, p1, p2, p3, t)
            out.append((x, y))
    return out
