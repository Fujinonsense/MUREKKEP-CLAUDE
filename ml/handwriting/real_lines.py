"""Lines of the user's own handwriting (strokes taken from iPad screenshots of known text), made many
by small random changes, for fine-tuning the reader on the hand it has to read.

A file holds {"lines": [{"text": str, "strokes": [[[x, y], …], …], "held_out": bool}]} in page
points, y down. Every training copy is turned, sheared, stretched and bent a little, its strokes
moved a little apart, and drawn with a random line width, the way render_segments draws synthetic
lines."""
import json
import math

import numpy as np

from ink_render import render_line


def load(path):
    lines = json.load(open(path, encoding="utf-8"))["lines"]
    train = [(l["text"], [np.asarray(s, dtype=np.float64).reshape(-1, 2) for s in l["strokes"]])
             for l in lines if not l.get("held_out")]
    held = [(l["text"], [np.asarray(s, dtype=np.float64).reshape(-1, 2) for s in l["strokes"]])
            for l in lines if l.get("held_out")]
    return train, held


def _height(strokes):
    ys = np.concatenate([s[:, 1] for s in strokes])
    p5, p95 = np.percentile(ys, [5, 95])
    return max(float(p95 - p5), 1.0)


def _runs(strokes):
    """The line's ink runs left to right: stroke x-ranges merged where they overlap."""
    spans = sorted((float(s[:, 0].min()), float(s[:, 0].max())) for s in strokes)
    out = [list(spans[0])]
    for a, b in spans[1:]:
        if a <= out[-1][1]:
            out[-1][1] = max(out[-1][1], b)
        else:
            out.append([a, b])
    return out


def squeeze_gaps(rng, strokes, spaces, low=0.35, high=1.0):
    """The words written closer together: the line's `spaces` widest gaps between ink runs (its word
    gaps) shrink to a random 35-100 %, never below 0.6 of the letters' height. The reader lost
    spaces when a hand left 40 % of its usual gap."""
    if spaces <= 0 or len(strokes) < 2:
        return [s.copy() for s in strokes]
    h = _height(strokes)
    r = _runs(strokes)
    widest = sorted(range(len(r) - 1), key=lambda i: r[i + 1][0] - r[i][1], reverse=True)[:spaces]
    shifts = []
    for i in widest:
        gap = r[i + 1][0] - r[i][1]
        new = max(gap * rng.uniform(low, high), min(gap, 0.6 * h))
        shifts.append((r[i + 1][0], gap - new))
    out = []
    for s in strokes:
        q = s.copy()
        x0 = float(s[:, 0].min())
        q[:, 0] -= sum(d for start, d in shifts if x0 >= start - 1e-9)
        out.append(q)
    return out


def augment(rng, strokes, spaces=0):
    """A changed copy of a line's strokes; half the time with its words written closer together."""
    if spaces and rng.random() < 0.5:
        strokes = squeeze_gaps(rng, strokes, spaces)
    h = _height(strokes)
    pts = np.concatenate(strokes)
    centre = pts.mean(axis=0)
    angle = math.radians(rng.normal(0, 1.5))
    shear = rng.uniform(-0.25, 0.25)
    sx = rng.uniform(0.85, 1.2)
    c, s = math.cos(angle), math.sin(angle)
    waves = [(rng.normal(0, 1, 2), rng.uniform(0.5, 2.0) / h, rng.uniform(0, 2 * math.pi), rng.normal(0, 0.05 * h, 2))
             for _ in range(3)]
    out = []
    for stroke in strokes:
        q = stroke - centre
        q = q + rng.normal(0, 0.04 * h, 2)                    # strokes a little apart
        q[:, 0] = (q[:, 0] + shear * q[:, 1]) * sx
        q = np.stack([c * q[:, 0] - s * q[:, 1], s * q[:, 0] + c * q[:, 1]], axis=1)
        for direction, freq, phase, shift in waves:           # a smooth bend
            q = q + np.outer(np.sin(q @ direction * freq + phase), shift)
        q = q + rng.normal(0, 0.008 * h, q.shape)             # a shaky hand
        out.append(q + centre)
    return out


def make_line(rng, lines):
    """(image 48×W, text) of one changed copy of a random real line."""
    text, strokes = lines[int(rng.integers(len(lines)))]
    return render_line(augment(rng, strokes, text.count(" ")), line_px=rng.uniform(1.8, 3.2)), text


def images(lines):
    """The real lines as they are, for measuring."""
    return [(render_line(strokes), text) for text, strokes in lines]
