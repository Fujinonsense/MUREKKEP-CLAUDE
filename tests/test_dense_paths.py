"""Item 11: a preset octagon must come out as an octagon, not a lumpy circle."""
import math
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "ports"))
from ribbon import smoothed, stroke_points  # noqa: E402


def octagon(radius=60.0, cx=100.0, cy=100.0):
    pts = [(cx + radius * math.cos(2 * math.pi * k / 8), cy + radius * math.sin(2 * math.pi * k / 8)) for k in range(8)]
    return pts + [pts[0]]


def distance_to_polygon(p, poly):
    best = math.inf
    for a, b in zip(poly, poly[1:]):
        dx, dy = b[0] - a[0], b[1] - a[1]
        l2 = dx * dx + dy * dy
        t = 0.0 if l2 == 0 else max(0.0, min(1.0, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / l2))
        best = min(best, math.hypot(p[0] - a[0] - t * dx, p[1] - a[1] - t * dy))
    return best


def max_deviation(width):
    poly = octagon()
    drawn = smoothed(stroke_points(poly, width))
    return max(distance_to_polygon(p, poly) for p in drawn)


def test_octagon_with_pen_keeps_its_sides():
    assert max_deviation(2.2) < 0.6


def test_octagon_with_thick_ink_keeps_its_sides():
    assert max_deviation(12.0) < 0.6
