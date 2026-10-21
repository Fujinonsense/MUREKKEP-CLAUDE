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


def augment(rng, strokes):
    """A changed copy of a line's strokes."""
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
    return render_line(augment(rng, strokes), line_px=rng.uniform(1.8, 3.2)), text


def images(lines):
    """The real lines as they are, for measuring."""
    return [(render_line(strokes), text) for text, strokes in lines]
