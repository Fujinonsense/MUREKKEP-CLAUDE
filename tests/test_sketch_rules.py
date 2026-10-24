"""Item 13: a quickly drawn circle must not read as a kidney or a spleen, while drawn organs still do."""
import math
import os
import random
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "ports"))
from badcircles import bad_circle  # noqa: E402
from organs import KIDNEY, SPLEEN, flatten, organ  # noqa: E402


def noisy(outline, rng):
    """The organ as a person draws it: wobble, a slight tilt in any of the four directions, a squash."""
    turn = rng.uniform(-math.radians(20), math.radians(20)) + rng.choice([0, math.pi / 2, math.pi, 3 * math.pi / 2])
    squash = rng.uniform(0.85, 1.15)
    ph = rng.uniform(0, 2 * math.pi)
    out = []
    n = len(outline)
    for i, (x, y) in enumerate(outline):
        k = 1 + 0.03 * math.sin(5 * 2 * math.pi * i / n + ph)
        x, y = (x - 50) * k * squash, (y - 50) * k
        out.append((100 + x * math.cos(turn) - y * math.sin(turn), 100 + x * math.sin(turn) + y * math.cos(turn)))
    return out


def test_bad_circles_are_not_organs():
    rng = random.Random(7)
    wrong = sum(organ(bad_circle(rng)) is not None for _ in range(3000))
    assert wrong == 0


def test_drawn_kidneys_and_spleens_are_found():
    rng = random.Random(11)
    kidneys = sum(organ(noisy(flatten(KIDNEY), rng)) == "kidney" for _ in range(150))
    spleens = sum(organ(noisy(flatten(SPLEEN), rng)) == "spleen" for _ in range(150))
    # As many as the 2.9 rule finds (145 and 118 of 150 with these seeds).
    assert kidneys >= 140
    assert spleens >= 115


# Held stars: a five-pointed star in one stroke (lines crossing) or its outline is offered as a star.
from sketch import star_kind  # noqa: E402
from stargen import crossing_star, outline_star  # noqa: E402


def test_drawn_stars_are_found():
    rng = random.Random(5)
    crossing = sum(star_kind(crossing_star(rng)) == "crossing" for _ in range(200))
    outline = sum(star_kind(outline_star(rng)) == "outline" for _ in range(200))
    assert crossing >= 190
    assert outline >= 185


def test_circles_and_organs_are_not_stars():
    rng = random.Random(9)
    assert sum(star_kind(bad_circle(rng)) is not None for _ in range(3000)) == 0
    assert sum(star_kind(noisy(flatten(KIDNEY), rng)) is not None for _ in range(200)) == 0
    assert sum(star_kind(noisy(flatten(SPLEEN), rng)) is not None for _ in range(200)) == 0


def test_polygons_are_not_stars():
    def polygon(n, r=60.0):
        pts = [(200 + r * math.cos(2 * math.pi * k / n), 200 + r * math.sin(2 * math.pi * k / n)) for k in range(n)]
        out = []
        for i in range(n):
            a, b = pts[i], pts[(i + 1) % n]
            out += [(a[0] + (b[0] - a[0]) * t / 20, a[1] + (b[1] - a[1]) * t / 20) for t in range(20)]
        return out + [out[0]]
    assert all(star_kind(polygon(n)) is None for n in (3, 4, 5, 6))
