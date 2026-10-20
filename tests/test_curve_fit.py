"""Item 27: an open curved stroke becomes a curve with a control point (no arcs, no arrowheads)."""
import math
import os
import random
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "ports"))
from curve import bezier_point, mid_handle_to_control, quadratic_bezier  # noqa: E402


def sample(p0, c, p2, n=60, noise=1.0, seed=3):
    rng = random.Random(seed)
    pts = []
    for i in range(n):
        x, y = bezier_point(p0, c, p2, i / (n - 1))
        pts.append((x + rng.uniform(-noise, noise), y + rng.uniform(-noise, noise)))
    pts[0], pts[-1] = p0, p2
    return pts


def test_control_point_is_recovered():
    p0, c, p2 = (20.0, 120.0), (90.0, 10.0), (200.0, 110.0)
    control, rms = quadratic_bezier(sample(p0, c, p2))
    assert math.dist(control, c) < 2.0
    assert rms < 1.2


def test_mid_handle_moves_the_curve_through_it():
    p0, p2 = (0.0, 0.0), (100.0, 0.0)
    control = mid_handle_to_control(p0, (50.0, -40.0), p2)
    mid = bezier_point(p0, control, p2, 0.5)
    assert math.dist(mid, (50.0, -40.0)) < 1e-9
