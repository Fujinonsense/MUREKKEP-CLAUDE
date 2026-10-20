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
