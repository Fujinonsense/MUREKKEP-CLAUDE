"""Random hand-drawn circles: low-frequency radius wobble, squash, tilt, a landing hook and an
overshoot, cut like SketchRecognizer.closedLoop."""
import math
import random


def bad_circle(rng, r=50.0):
    a = [rng.uniform(0, 0.10) for _ in range(4)]
    ph = [rng.uniform(0, 2 * math.pi) for _ in range(4)]
    aspect = rng.uniform(0.7, 1.0)
    tilt = rng.uniform(0, math.pi)
    start = rng.uniform(0, 2 * math.pi)
    hook = rng.uniform(0, 0.2)
    over = math.radians(rng.uniform(0, 30))
    pts = []
    total = 2 * math.pi + over
    for i in range(201):
        t = total * i / 200
        rr = r * (1 + sum(a[k] * math.sin((k + 2) * t + ph[k]) for k in range(4)))
        if t < math.radians(25):
            rr *= 1 - hook * (1 - t / math.radians(25))
        x, y = rr * math.cos(t + start) * aspect, rr * math.sin(t + start)
        pts.append((100 + x * math.cos(tilt) - y * math.sin(tilt), 100 + x * math.sin(tilt) + y * math.cos(tilt)))
    s = int(len(pts) * 0.65)
    best = min(range(s, len(pts)), key=lambda i: math.dist(pts[i], pts[0]))
    return pts[: best + 1]
