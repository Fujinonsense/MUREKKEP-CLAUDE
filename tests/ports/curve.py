"""Port of Fit.quadraticBezier (ShapeRecognizer.swift) and the curve handle (ShapeEditing.swift)."""
import math


def bezier_point(p0, c, p2, t):
    u = 1 - t
    return (u * u * p0[0] + 2 * u * t * c[0] + t * t * p2[0], u * u * p0[1] + 2 * u * t * c[1] + t * t * p2[1])


def mid_handle_to_control(p0, m, p2):
    """The control point that makes the curve pass through `m` at its middle (t = 0.5)."""
    return (2 * m[0] - (p0[0] + p2[0]) / 2, 2 * m[1] - (p0[1] + p2[1]) / 2)


def quadratic_bezier(pts, iterations=24):
    """Least-squares control point with the ends fixed on the first and last point.
    Returns (control, rms) or None."""
    n = len(pts)
    if n < 3:
        return None
    p0, p2 = pts[0], pts[-1]
    acc = [0.0]
    for i in range(1, n):
        acc.append(acc[-1] + math.dist(pts[i - 1], pts[i]))
    total = acc[-1]
    if total <= 1e-6:
        return None
    ts = [a / total for a in acc]
    c = None
    for _ in range(iterations):
        nx = ny = den = 0.0
        for t, p in zip(ts, pts):
            w = 2 * t * (1 - t)
            rx = p[0] - (1 - t) ** 2 * p0[0] - t * t * p2[0]
            ry = p[1] - (1 - t) ** 2 * p0[1] - t * t * p2[1]
            nx += w * rx
            ny += w * ry
            den += w * w
        if den < 1e-9:
            return None
        c = (nx / den, ny / den)
        # Each point moves to the parameter of the nearest point of the curve (two Newton steps).
        for i in range(1, n - 1):
            t = ts[i]
            p = pts[i]
            for _ in range(2):
                b = bezier_point(p0, c, p2, t)
                d1 = (2 * (1 - t) * (c[0] - p0[0]) + 2 * t * (p2[0] - c[0]), 2 * (1 - t) * (c[1] - p0[1]) + 2 * t * (p2[1] - c[1]))
                d2 = (2 * (p2[0] - 2 * c[0] + p0[0]), 2 * (p2[1] - 2 * c[1] + p0[1]))
                ex, ey = b[0] - p[0], b[1] - p[1]
                f1 = ex * d1[0] + ey * d1[1]
                f2 = d1[0] * d1[0] + d1[1] * d1[1] + ex * d2[0] + ey * d2[1]
                if f2 > 1e-9:
                    t = min(max(t - f1 / f2, 0.0), 1.0)
            ts[i] = t
    err = 0.0
    for t, p in zip(ts, pts):
        b = bezier_point(p0, c, p2, t)
        err += (b[0] - p[0]) ** 2 + (b[1] - p[1]) ** 2
    return c, math.sqrt(err / n)
