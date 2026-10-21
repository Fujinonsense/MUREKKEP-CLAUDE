"""Synthetic lines of ugly handwriting for training: a text from texts.sample, written with the
skeleton of a handwriting font (70 %) or the app's StrokeFont (30 %), every letter a little
different in size, angle and height, slanted, wavy, with drifting dots and accents, uneven gaps,
some joined letters and small breaks — then drawn exactly like the app draws a line for the model
(ink_render's transform, any line width between 1.6 and 3.4 px)."""
import math

import numpy as np
from scipy import ndimage

import glyphs
import strokefont
import texts
from ink_render import HEIGHT, SUPERSAMPLE, image_width, line_transform

X_HEIGHT = 7.0  # StrokeFont units
# All-caps lines are written only with fonts whose capitals are plain (people print capitals; an
# ornate script capital is something written at the start of a sentence, not in a whole word).
PLAIN_CAPS = 2.2


def split_fonts():
    """(training fonts, held-out fonts): every 9th font is never trained on."""
    fs = glyphs.fonts()
    return [f for i, f in enumerate(fs) if i % 9], [f for i, f in enumerate(fs) if i % 9 == 0]


def _strokefont_glyph(ch):
    g = strokefont.glyph(ch)
    if g is None:
        return None
    advance, paths = g
    return advance, [np.concatenate([glyphs.segments(p) for p in paths])]


class GlyphSource:
    """Glyphs of one handwriting font (None = the app's StrokeFont); characters a font cannot draw
    come from StrokeFont."""

    def __init__(self, path=None):
        self.path = path
        if path is None:
            self.table, self.space, self.tracking = {}, strokefont.SPACE, strokefont.TRACKING
            self.caps_ratio = 1.0
        else:
            self.table, self.space = glyphs.font_glyphs(path)
            self.tracking = 0.0
            self.caps_ratio = glyphs.caps_ratio(self.table)

    def get(self, ch):
        """(advance, [segment array, …]) in units; the first part is the letter, the rest accents."""
        if ch in self.table:
            parts, advance = self.table[ch]
            return advance, parts
        g = _strokefont_glyph(ch)
        if g is None:
            raise KeyError(ch)
        advance, parts = g
        return advance + (strokefont.TRACKING * 0.6 if self.path is not None else 0.0), parts


class FontPool:
    def __init__(self, paths, image_fonts=()):
        self.sources = [GlyphSource(p) for p in paths]
        self.plain = [s for s in self.sources if s.caps_ratio <= PLAIN_CAPS]
        self.stroke_font = GlyphSource(None)
        # Whole-font drawings with an elastic bend (font_lines.py), for a share of the lines.
        self.image_fonts = tuple(image_fonts)

    def random(self, rng):
        return self.sources[int(rng.integers(len(self.sources)))]


def mostly_caps(text):
    letters = [c for c in text if c.isalpha()]
    return len(letters) >= 3 and sum(c.isupper() for c in letters) >= 0.6 * len(letters)


def pick_source(rng, pool, text):
    """StrokeFont for 30 % of lines, otherwise a handwriting font (a plain-capitals one for all caps)."""
    if rng.random() >= 0.7:
        return pool.stroke_font
    if mostly_caps(text):
        return pool.plain[int(rng.integers(len(pool.plain)))] if pool.plain else pool.stroke_font
    return pool.random(rng)


def _rotate(seg, angle, cx, cy, scale):
    c, s = math.cos(angle), math.sin(angle)
    out = seg.astype(np.float64).copy()
    for i in (0, 2):
        x, y = out[:, i] - cx, out[:, i + 1] - cy
        out[:, i] = cx + (x * c - y * s) * scale
        out[:, i + 1] = cy + (x * s + y * c) * scale
    return out


def _join(a, b):
    """A connecting pen stroke from point a to point b (a lowercase join)."""
    mid = ((a[0] + b[0]) / 2, min(a[1], b[1]) - 0.6)
    pts = [a, ((a[0] + mid[0]) / 2, (a[1] + mid[1]) / 2 - 0.2), mid, b]
    return glyphs.segments(pts).astype(np.float64)


def compose(rng, source, text):
    """Segments (rows x0, y0, x1, y1) of `text` in page points, y down."""
    slant = math.tan(math.radians(rng.uniform(-15, 25)))
    size_var = rng.uniform(0.04, 0.15)
    rot_max = math.radians(rng.uniform(0, 6))
    base_var = rng.uniform(0, 0.08) * X_HEIGHT
    gap_lo, gap_hi = -0.15, rng.uniform(0.0, 0.4)
    accent_drift = rng.uniform(0, 0.15) * X_HEIGHT
    join_p = 0.2 if source.path is not None else 0.05
    out = []
    x = 0.0
    prev_end = None
    for ch in text:
        if ch == " ":
            x += source.space * rng.uniform(0.7, 1.6)
            prev_end = None
            continue
        advance, parts = source.get(ch)
        pts = np.concatenate([glyphs.endpoints(p) for p in parts])
        cx = float((pts[:, 0].min() + pts[:, 0].max()) / 2)
        width = float(pts[:, 0].max() - pts[:, 0].min())
        k = 1 + rng.uniform(-size_var, size_var)
        angle = rng.uniform(-rot_max, rot_max)
        dy = rng.normal(0, base_var) if base_var > 0 else 0.0
        letter = []
        for i, part in enumerate(parts):
            seg = _rotate(part, angle, cx, X_HEIGHT / 2, k)
            if i > 0 and accent_drift > 0:
                seg[:, [0, 2]] += rng.normal(0, accent_drift)
                seg[:, [1, 3]] += rng.normal(0, accent_drift * 0.6)
            seg[:, [0, 2]] += x - cx + width / 2
            seg[:, [1, 3]] += dy
            letter.append(seg)
        body = np.concatenate(letter)
        ends = glyphs.endpoints(body)
        if ch.islower() and prev_end is not None and rng.random() < join_p:
            low = ends[ends[:, 1] < X_HEIGHT * 0.8]
            if len(low):
                out.append(_join(prev_end, tuple(low[np.argmin(low[:, 0])])))
        out += letter
        low = ends[ends[:, 1] < X_HEIGHT * 0.8]
        prev_end = tuple(low[np.argmax(low[:, 0])]) if ch.islower() and len(low) else None
        x += max(advance * k, width * k * 0.6) * (1 + rng.uniform(gap_lo, gap_hi)) + source.tracking
    seg = np.concatenate(out) if out else np.zeros((0, 4))
    # Slant, a gentle wave along the line, and a few breaks in the pen line.
    for i in (0, 2):
        seg[:, i] += slant * seg[:, i + 1]
    amp, length, phase = rng.uniform(0, 0.6), rng.uniform(20, 80), rng.uniform(0, 2 * math.pi)
    for i in (1, 3):
        seg[:, i] += amp * np.sin(2 * math.pi * seg[:, i - 1] / length + phase)
    if rng.random() < 0.3 and len(seg) > 20:
        for _ in range(int(rng.integers(1, 3))):
            c = seg[int(rng.integers(len(seg))), :2]
            r = rng.uniform(0.3, 0.6)
            mid = (seg[:, :2] + seg[:, 2:]) / 2
            seg = seg[np.hypot(mid[:, 0] - c[0], mid[:, 1] - c[1]) > r]
    # The whole line turned a little: real baselines drift, and the app levels a line only to within a
    # few degrees before reading it.
    if len(seg) and rng.random() < 0.85:
        a = math.radians(rng.uniform(-8, 8))
        c, s = math.cos(a), math.sin(a)
        mx = float(seg[:, [0, 2]].mean())
        my = float(seg[:, [1, 3]].mean())
        turned = seg.copy()
        for i in (0, 2):
            x, y = seg[:, i] - mx, seg[:, i + 1] - my
            turned[:, i] = mx + c * x - s * y
            turned[:, i + 1] = my + s * x + c * y
        seg = turned
    # Units to page points (cap height 10–22 pt), y down.
    pt = rng.uniform(1.0, 2.2)
    seg = seg * pt
    seg[:, [1, 3]] *= -1
    return seg


def render_segments(seg, line_px):
    """Like ink_render.render_line, for segments: sample each segment densely, splat at 4×, grow by
    the pen radius, and average down."""
    pts = glyphs.endpoints(seg.astype(np.float64))
    scale, dx, dy = line_transform([pts])
    w = image_width([pts], scale)
    k = SUPERSAMPLE
    a = (seg[:, :2] * scale + (dx, dy)) * k
    b = (seg[:, 2:] * scale + (dx, dy)) * k
    r = line_px * k / 2
    n = int(np.ceil(np.hypot(*(b - a).T).max() / max(r * 0.8, 1e-3))) + 1 if len(seg) else 1
    t = np.linspace(0, 1, n)[None, :, None]
    samples = (a[:, None, :] + (b - a)[:, None, :] * t).reshape(-1, 2)
    grid = np.zeros((HEIGHT * k, w * k), dtype=bool)
    xs = np.round(samples[:, 0]).astype(int)
    ys = np.round(samples[:, 1]).astype(int)
    keep = (xs >= 0) & (xs < w * k) & (ys >= 0) & (ys < HEIGHT * k)
    grid[ys[keep], xs[keep]] = True
    ri = int(math.ceil(r))
    yy, xx = np.mgrid[-ri:ri + 1, -ri:ri + 1]
    grid = ndimage.binary_dilation(grid, structure=(xx * xx + yy * yy) <= r * r)
    return grid.reshape(HEIGHT, k, w, k).mean(axis=(1, 3)).astype(np.float32)


IMAGE_SHARE = 0.3  # of training lines drawn whole by a handwriting font (font_lines.py)


def make_line(rng, pool, text=None):
    """(image 48×W float32, text) of one synthetic handwritten line."""
    if pool.image_fonts and text is None and rng.random() < IMAGE_SHARE:
        import font_lines

        line = font_lines.make_line(rng, pool.image_fonts)
        if line is not None:
            return line
    text = text if text is not None else texts.sample(rng)
    seg = compose(rng, pick_source(rng, pool, text), text)
    if len(seg) == 0:
        seg = np.zeros((1, 4))
    return render_segments(seg, rng.uniform(1.6, 3.4)), text
