"""Kinematic Stroke Generator: handwriting as the pen moves, for the online (stroke trajectory) model.

Every character comes from the app's single-line font (strokefont.py, StrokeFont.swift), which keeps
its strokes in drawing order. Its directions are made the ones a hand uses (natural_direction):
straight downstrokes from the top, crossbars from the left, round letters anticlockwise (as seen on
the page). Then the writing is made sloppy the way a hand is:

- Control Point Perturbation: the stroke's control points are moved by a smooth random field and a
  little noise of their own, and each letter is turned, sheared and resized a little;
- minimum-jerk smoothing: the stroke is a Catmull-Rom spline through the moved points, sampled in time
  with the bell-shaped speed of a minimum-jerk movement (fast in the middle, slow at the ends);
- people differ: a stroke goes the other way, a letter's strokes come in another order, letters of a
  word are joined without lifting the pen, now and then;
- dots and accents (i, j, ç ğ ı İ ö ş ü, ! ? : ;) are pen-up strokes that come right after their letter
  or, as often as not, once the word is finished (delayed diacritics), and land a little off.

Coordinates are page points, y down, strokes in the order they were drawn."""
import math

import numpy as np

import strokefont
import texts

DIACRITIC_CHARS = set("ijçğıöşüÇĞİÖŞÜ!?:;")
TURKISH = set("çğıöşüÇĞİÖŞÜ")
X_HEIGHT = 7.0


def glyph(ch):
    """(advance, [path, …]) in font units (cap height 10, y up), strokes in drawing order."""
    g = strokefont.glyphs().get(ch) or strokefont.EXTRA.get(ch)
    if g is None:
        raise KeyError(ch)
    return g


def _is_mark(ch, k, paths):
    """Whether path k of character ch is a dot or an accent (drawn apart, possibly later)."""
    if ch not in DIACRITIC_CHARS or k == 0:
        return False
    p = np.asarray(paths[k])
    span = max(float(np.ptp(p[:, 0])), float(np.ptp(p[:, 1])))
    return span <= 4.5 and (p[:, 1].min() >= 7.5 or p[:, 1].max() <= 0.6 or len(p) <= 3)


def natural_direction(path):
    """The path the way a hand draws it: downstrokes from the top, crossbars from the left, closed
    loops anticlockwise on the page (clockwise in y-up units is reversed)."""
    p = np.asarray(path, dtype=np.float64)
    if len(p) < 2:
        return p
    span_x, span_y = float(np.ptp(p[:, 0])), float(np.ptp(p[:, 1]))
    closed = np.hypot(*(p[0] - p[-1])) < 0.15 * max(span_x, span_y, 1e-6) and len(p) > 6
    if closed:
        # Shoelace area > 0 is anticlockwise with y up.
        area = 0.5 * float(np.sum(p[:-1, 0] * p[1:, 1] - p[1:, 0] * p[:-1, 1]))
        return p if area >= 0 else p[::-1]
    if len(p) == 2 or _straight(p):
        dx, dy = p[-1] - p[0]
        if abs(dy) >= abs(dx):
            return p if dy <= 0 else p[::-1]  # top to bottom (y up: going down)
        return p if dx >= 0 else p[::-1]       # left to right
    return p


def _straight(p):
    a, b = p[0], p[-1]
    d = b - a
    n = math.hypot(*d)
    if n < 1e-6:
        return False
    dev = np.abs((p[:, 0] - a[0]) * d[1] - (p[:, 1] - a[1]) * d[0]) / n
    return float(dev.max()) < 0.12 * n


def _catmull(points, samples):
    """A Catmull-Rom spline through `points`, sampled at `samples` (0…1 along the knots)."""
    p = np.asarray(points, dtype=np.float64)
    t = np.asarray(samples, dtype=np.float64)[:, None]
    if len(p) < 3:
        return p[0] + (p[-1] - p[0]) * t
    ext = np.vstack([2 * p[0] - p[1], p, 2 * p[-1] - p[-2]])
    n = len(p) - 1
    u = np.minimum(t[:, 0] * n, n - 1e-9)
    i = u.astype(int)
    s = (u - i)[:, None]
    p0, p1, p2, p3 = ext[i], ext[i + 1], ext[i + 2], ext[i + 3]
    return 0.5 * ((2 * p1) + (-p0 + p2) * s + (2 * p0 - 5 * p1 + 4 * p2 - p3) * s * s
                  + (-p0 + 3 * p1 - 3 * p2 + p3) * s ** 3)


def min_jerk_times(n):
    """n sample positions 0…1 of a minimum-jerk movement taken at equal time steps."""
    tau = np.linspace(0, 1, n)
    return 10 * tau ** 3 - 15 * tau ** 4 + 6 * tau ** 5


def _control_points(path, rng, jitter):
    """Fewer, moved control points: every k-th vertex and the ends, each moved by noise."""
    p = np.asarray(path, dtype=np.float64)
    if len(p) <= 2:
        return p + rng.normal(0, jitter * 0.5, p.shape)
    step = max(1, len(p) // int(rng.integers(4, 9)))
    idx = sorted(set(list(range(0, len(p), step)) + [len(p) - 1]))
    c = p[idx].copy()
    c += rng.normal(0, jitter, c.shape)
    if np.hypot(*(p[0] - p[-1])) < 1e-6:
        c[-1] = c[0]  # a closed loop stays closed (or nearly)
        c[-1] += rng.normal(0, jitter * 0.4, 2)
    return c


def _smooth_field(rng, amount):
    """A smooth random displacement of the plane (a few low-frequency waves)."""
    waves = [(rng.normal(0, 1, 2), rng.uniform(0.08, 0.3), rng.uniform(0, 2 * math.pi), rng.normal(0, amount, 2))
             for _ in range(3)]

    def move(pts):
        out = pts.copy()
        for direction, freq, phase, shift in waves:
            out += np.outer(np.sin(pts @ direction * freq + phase), shift)
        return out
    return move


def _stroke(path, rng, style, field, transform):
    ctrl = _control_points(path, rng, style["jitter"])
    ctrl = field(ctrl)
    n = max(4, int(np.hypot(*np.diff(ctrl, axis=0).T).sum() * style["density"]) + 2)
    pts = _catmull(ctrl, min_jerk_times(n))
    return transform(pts)


def letter_strokes(ch, rng, style):
    """The letter's strokes (font units, y up) and its marks, sloppy, with the letter's own small turn,
    size and slant. Returns (advance, body strokes, mark strokes)."""
    advance, paths = glyph(ch)
    order = list(range(len(paths)))
    body = [k for k in order if not _is_mark(ch, k, paths)]
    marks = [k for k in order if _is_mark(ch, k, paths)]
    if len(body) > 1 and rng.random() < style["reorder"]:
        rng.shuffle(body)
    k_size = 1 + rng.uniform(-style["size_var"], style["size_var"])
    angle = math.radians(rng.normal(0, style["turn"]))
    c, s = math.cos(angle), math.sin(angle)
    slant = style["slant"]

    def transform(pts):
        q = pts * k_size
        x, y = q[:, 0], q[:, 1]
        x = x + slant * y
        return np.stack([c * x - s * y, s * x + c * y], axis=1)

    field = _smooth_field(rng, style["wobble"])
    out = []
    for group in (body, marks):
        strokes = []
        for k in group:
            path = natural_direction(paths[k])
            if rng.random() < style["reverse"]:
                path = path[::-1]
            strokes.append(_stroke(path, rng, style, field, transform))
        out.append(strokes)
    return advance * k_size, out[0], out[1]


def random_style(rng):
    return {
        "jitter": rng.uniform(0.08, 0.45),     # control point noise, font units
        "wobble": rng.uniform(0.05, 0.35),     # smooth field amplitude
        "density": rng.uniform(2.5, 5.0),      # samples per font unit
        "size_var": rng.uniform(0.03, 0.14),
        "turn": rng.uniform(0, 5),             # degrees
        "slant": math.tan(math.radians(rng.uniform(-10, 25))),
        "reverse": rng.uniform(0.03, 0.2),     # a stroke drawn the other way
        "reorder": rng.uniform(0.0, 0.2),      # a letter's strokes in another order
        "join": rng.uniform(0.0, 0.6),         # letters of a word joined without lifting the pen
        "delay_marks": rng.uniform(0.2, 0.8),  # dots and accents after the word
        "mark_drift": rng.uniform(0.1, 0.9),   # how far they land from their place, font units
        "gap": (-0.1, rng.uniform(0.05, 0.45)),
        "space": rng.uniform(0.7, 1.6),
        "baseline": rng.uniform(0.0, 0.5),     # baseline wander, font units
        "scale": rng.uniform(1.0, 2.2),        # page points per font unit
    }


def write(text, rng, style=None):
    """Pen strokes of `text` (page points, y down) in drawing order."""
    style = style or random_style(rng)
    strokes = []
    x = 0.0
    drift = 0.0
    pending = []  # marks waiting for the end of the word
    word_last = None  # end point of the last stroke of the previous letter in this word

    def flush():
        nonlocal pending
        for m in pending:
            strokes.append(m)
        pending = []

    for ch in text:
        if ch == " ":
            flush()
            x += strokefont.SPACE * style["space"] * rng.uniform(0.8, 1.25)
            word_last = None
            continue
        advance, body, marks = letter_strokes(ch, rng, style)
        drift = 0.85 * drift + rng.normal(0, style["baseline"] * 0.5)
        offset = np.array([x, drift])
        body = [b + offset for b in body]
        marks = [m + offset + rng.normal(0, style["mark_drift"], 2) for m in marks]
        if body:
            first = body[0]
            if (word_last is not None and ch.isalpha() and ch.islower() and rng.random() < style["join"]
                    and strokes):
                # Joined: the previous stroke runs on into this letter without a pen lift.
                bridge = _catmull([word_last, (word_last + first[0]) / 2 + [0, -0.4], first[0]],
                                  np.linspace(0, 1, 6))
                strokes[-1] = np.vstack([strokes[-1], bridge[1:-1], first])
                body = body[1:]
            strokes.extend(body)
            word_last = strokes[-1][-1] if strokes else None
        if marks:
            if rng.random() < style["delay_marks"]:
                pending.extend(marks)
            else:
                strokes.extend(marks)
        x += max(advance, 0.6) * (1 + rng.uniform(*style["gap"])) + strokefont.TRACKING
    flush()
    k = style["scale"]
    return [[(float(px) * k, float(-py) * k) for px, py in s] for s in strokes if len(s)]


def make_sample(rng, text=None):
    """(strokes, text) of one written line."""
    text = text if text is not None else texts.sample(rng)
    return write(text, rng), text


if __name__ == "__main__":
    import sys

    from PIL import Image, ImageDraw

    rng = np.random.default_rng(int(sys.argv[2]) if len(sys.argv) > 2 else 0)
    lines = ["için Neler oluyor?", "Bugün hava çok güzel.", "e a e a ğüşıöç", "Öğrenciler sınava çalışıyor"]
    img = Image.new("RGB", (1300, 90 * len(lines)), "white")
    d = ImageDraw.Draw(img)
    for i, t in enumerate(lines):
        st = write(t, rng)
        pts = np.concatenate([np.asarray(s) for s in st])
        lo = pts.min(axis=0)
        k = 60 / max(np.ptp(pts[:, 1]), 1)
        for j, s in enumerate(st):
            q = [((px - lo[0]) * k + 10, (py - lo[1]) * k + 15 + 90 * i) for px, py in s]
            colour = (int(255 * j / max(len(st), 1)), 60, 200)
            if len(q) > 1:
                d.line(q, fill=colour, width=2)
            d.ellipse((q[0][0] - 3, q[0][1] - 3, q[0][0] + 3, q[0][1] + 3), fill=(0, 160, 0))
    img.save(sys.argv[1] if len(sys.argv) > 1 else "kinematic.png")
