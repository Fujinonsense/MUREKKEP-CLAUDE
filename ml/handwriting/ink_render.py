"""The handwriting model's input: one line of strokes drawn as a 48-pixel-high image. Twin of
`InkLine.render` in Murekkep.swiftpm/InkLine.swift; both use these constants.

The middle 90 % of the line's points (5th to 95th percentile of y, numpy's linear interpolation) is
scaled to CORE pixels with its top at row TOP; every line is drawn TOP_LINE pixels wide whatever pen
and width wrote it, so 3D inks look exactly like a plain pen to the model."""
import math

import numpy as np
from PIL import Image, ImageDraw

HEIGHT = 48
CORE = 30.0
TOP = 9.0
LEFT = 4.0
MARGIN = 8
MIN_WIDTH = 16
MAX_WIDTH = 1600
LINE_PX = 2.4
SUPERSAMPLE = 4


def _points(strokes):
    return np.concatenate([np.asarray(s, dtype=np.float64).reshape(-1, 2) for s in strokes])


def line_transform(strokes):
    """(scale, dx, dy): image = point × scale + (dx, dy)."""
    pts = _points(strokes)
    p5, p95 = np.percentile(pts[:, 1], [5, 95])
    scale = CORE / max(p95 - p5, 1.0)
    ink = (pts[:, 0].max() - pts[:, 0].min()) * scale
    if math.ceil(ink) + MARGIN > MAX_WIDTH:
        # A very long line is shrunk to fit rather than cut.
        scale *= (MAX_WIDTH - MARGIN) / max(ink, 1e-6)
    dx = LEFT - pts[:, 0].min() * scale
    dy = TOP - p5 * scale
    return scale, dx, dy


def image_width(strokes, scale):
    pts = _points(strokes)
    ink = (pts[:, 0].max() - pts[:, 0].min()) * scale
    w = math.ceil(ink) + MARGIN
    w = (w + 3) // 4 * 4
    return min(max(w, MIN_WIDTH), MAX_WIDTH)


def render_line(strokes, line_px=LINE_PX):
    """float32 array of shape (48, W), ink 1.0 on 0.0. `strokes` are lists of (x, y) in page points."""
    scale, dx, dy = line_transform(strokes)
    w = image_width(strokes, scale)
    k = SUPERSAMPLE
    img = Image.new("L", (w * k, HEIGHT * k), 0)
    draw = ImageDraw.Draw(img)
    lw = line_px * k
    r = lw / 2
    for s in strokes:
        pts = [((x * scale + dx) * k, (y * scale + dy) * k) for x, y in np.asarray(s, dtype=np.float64).reshape(-1, 2)]
        if len(pts) > 1:
            draw.line(pts, fill=255, width=max(1, round(lw)))
        # Round caps and joins; a single point is a dot a little larger than the line.
        rr = r if len(pts) > 1 else r * 1.2
        for x, y in pts:
            draw.ellipse((x - rr, y - rr, x + rr, y + rr), fill=255)
    small = img.resize((w, HEIGHT), Image.BOX)
    return np.asarray(small, dtype=np.float32) / 255.0


def render_ink(records):
    """The app's view of a line of Stroke records ({"points", "brush", "width"}): brush and width
    play no part."""
    return render_line([r["points"] for r in records])
