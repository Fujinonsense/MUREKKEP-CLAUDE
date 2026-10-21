"""A second kind of training line: the text drawn whole by a handwriting font with Pillow, made ugly
the way a hand is, then turned into the image the app gives the model.

1. Every letter is drawn on its own with a random font of MRK_DATA/handfonts (fetch_handfonts.py;
   Turkish text only with fonts that have ç ğ ı İ ö ş ü), a little bigger or smaller, turned a few
   degrees, at its own distance from the last one (random letter spacing).
2. The baseline wanders: a slow random walk plus two gentle waves along the line; the line is slanted.
3. ElasticTransform: a smooth random displacement field (Gaussian-filtered noise, SciPy) bends the
   whole line, like a pen that slips.
4. The ink is thinned to its centre line (skeleton) and redrawn exactly like the app draws a line for
   the model (synth.render_segments: ink_render's transform, one pen width from 1.6 to 3.4 px), so a
   thick font or a thick 3D ink look the same to it.

usage (a sheet of samples): python font_lines.py [out.png]"""
import json
import math
import os
from functools import lru_cache
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage
from skimage.morphology import skeletonize

import glyphs
import synth
import texts

DATA = Path(os.environ.get("MRK_DATA", "C:/Users/orsyu/mrk-ml/data"))
FONTS = DATA / "handfonts"
TURKISH = set("çğıİöşüÇĞÖŞÜ")


class HandFont:
    def __init__(self, path, turkish):
        self.path = Path(path)
        self.turkish = turkish

    def covers(self, text):
        return all(c == " " or glyphs.covers(self.path, c) for c in text)


@lru_cache(maxsize=1)
def fonts():
    """The fonts fetch_handfonts.py downloaded (empty when it has not run)."""
    table = FONTS / "handfonts.json"
    if not table.exists():
        return ()
    out = []
    for family in json.loads(table.read_text(encoding="utf-8")).values():
        for name in family["files"]:
            out.append(HandFont(FONTS / name, family["turkish"]))
    return tuple(out)


@lru_cache(maxsize=4)
def _list(name):
    path = DATA / "text" / name
    return path.read_text(encoding="utf-8").split("\n")[:-1] if path.exists() else []


def sample_text(rng):
    """A word, a few words or a short phrase from wordlists.py, Turkish more often; otherwise
    texts.sample (math, punctuation, longer fragments)."""
    r = rng.random()
    lang = "tr" if rng.random() < 0.6 else "en"
    words, phrases = _list(f"words_{lang}.txt"), _list(f"phrases_{lang}.txt")
    if r < 0.25 and words:
        n = int(rng.integers(1, 5))
        return " ".join(words[int(rng.integers(len(words)))] for _ in range(n))[:texts.MAX_CHARS]
    if r < 0.6 and phrases:
        return phrases[int(rng.integers(len(phrases)))]
    return texts.sample(rng)


def pick_font(rng, text, choices):
    """A font that can draw every character of `text` (Turkish only where the family has it)."""
    needs_turkish = bool(TURKISH & set(text))
    usable = [f for f in choices if (f.turkish or not needs_turkish) and f.covers(text)]
    return usable[int(rng.integers(len(usable)))] if usable else None


def _font(path, size, rng):
    font = ImageFont.truetype(str(path), size)
    try:
        axes = font.get_variation_axes()
        values = []
        for a in axes:
            lo, hi = a["minimum"], a["maximum"]
            name = str(a.get("name", b"")).lower()
            if "weight" in name or "wght" in name:
                # Not the extremes: a hairline or a black weight is not a pen.
                values.append(lo + (hi - lo) * rng.uniform(0.15, 0.7))
            else:
                values.append(lo + (hi - lo) * rng.uniform(0, 1))
        font.set_variation_by_axes(values)
    except Exception:
        pass  # a static font
    return font


def draw(text, font_path, rng):
    """The text as a grayscale float image (ink 1 on 0), letters drawn one by one."""
    size = int(rng.integers(44, 66))
    base = _font(font_path, size, rng)
    gap_lo, gap_hi = -0.12, rng.uniform(0.05, 0.35)
    tilt = rng.uniform(0, 4)
    size_var = rng.uniform(0.03, 0.1)
    width = int(sum(base.getlength(c) for c in text) * (1.5 + gap_hi) + 3 * size)
    height = int(size * 3.2)
    canvas = Image.new("L", (width, height), 0)
    # Baseline wander: a random walk smoothed along the line, plus two slow waves.
    steps = max(len(text), 2)
    walk = np.cumsum(rng.normal(0, 0.035 * size, steps))
    walk = ndimage.gaussian_filter1d(walk - walk.mean(), sigma=1.5)
    waves = [(rng.uniform(0, 0.06) * size, rng.uniform(4, 16) * size, rng.uniform(0, 2 * math.pi)) for _ in range(2)]
    x = size
    y0 = height * 0.62
    for i, ch in enumerate(text):
        advance = base.getlength(ch) if ch != " " else base.getlength(" ")
        if ch == " ":
            x += advance * rng.uniform(0.7, 1.7)
            continue
        k = 1 + rng.uniform(-size_var, size_var)
        font = _font(font_path, max(10, int(size * k)), rng) if abs(k - 1) > 0.02 else base
        left, top, right, bottom = font.getbbox(ch, anchor="ls")
        pad = int(size * 0.4)
        w, h = int(right - left) + 2 * pad, int(bottom - top) + 2 * pad
        if w <= 2 * pad and h <= 2 * pad:
            x += advance
            continue
        glyph = Image.new("L", (w, h), 0)
        ImageDraw.Draw(glyph).text((pad - left, pad - top), ch, font=font, fill=255, anchor="ls")
        glyph = glyph.rotate(rng.uniform(-tilt, tilt), resample=Image.BILINEAR, center=(pad - left, pad - top))
        dy = walk[min(i, steps - 1)] + sum(a * math.sin(2 * math.pi * x / length + phase) for a, length, phase in waves)
        px = int(round(x + left - pad))
        py = int(round(y0 + dy + top - pad))
        canvas.paste(255, (px, py), glyph)
        x += advance * k * (1 + rng.uniform(gap_lo, gap_hi))
    img = np.asarray(canvas, dtype=np.float32) / 255.0
    # The slant: a shear around the baseline.
    shear = math.tan(math.radians(rng.uniform(-12, 18)))
    rows = np.arange(img.shape[0], dtype=np.float32)[:, None] - y0
    cols = np.arange(img.shape[1], dtype=np.float32)[None, :]
    img = ndimage.map_coordinates(img, [np.broadcast_to(rows + y0, img.shape), cols + shear * rows], order=1)
    return img, size


def elastic(img, rng, magnitude, sigma):
    """ElasticTransform: every pixel moved by a smooth random field (Gaussian-filtered noise scaled to
    `magnitude` pixels standard deviation; `sigma` sets how smooth it is)."""
    if magnitude <= 0:
        return img
    fields = []
    for _ in range(2):
        f = ndimage.gaussian_filter(rng.standard_normal(img.shape).astype(np.float32), sigma)
        fields.append(f / max(float(f.std()), 1e-6) * magnitude)
    rows, cols = np.mgrid[0:img.shape[0], 0:img.shape[1]].astype(np.float32)
    return ndimage.map_coordinates(img, [rows + fields[0], cols + fields[1]], order=1)


def make_line(rng, choices, text=None):
    """(image 48×W float32, text) — like synth.make_line, from a whole-font drawing; None when no font
    of `choices` can write the text."""
    text = text if text is not None else sample_text(rng)
    font = pick_font(rng, text, choices)
    if font is None or not text.strip():
        return None
    img, size = draw(text, font.path, rng)
    img = elastic(img, rng, magnitude=size * rng.uniform(0.015, 0.06), sigma=size * rng.uniform(0.15, 0.35))
    skel = skeletonize(img > 0.5)
    if not skel.any():
        return None
    seg = glyphs._skeleton_segments(skel).astype(np.float64)
    return synth.render_segments(seg, rng.uniform(1.6, 3.4)), text


def training_fonts():
    """The fonts minus any family the trainer holds out for validation."""
    held = {p.name.lower() for p in synth.split_fonts()[1]}
    return tuple(f for f in fonts() if f.path.name.lower() not in held)


if __name__ == "__main__":
    import sys

    rng = np.random.default_rng(1)
    rows = []
    for _ in range(14):
        line = None
        while line is None:
            line = make_line(rng, fonts())
        rows.append(line)
    w = max(r[0].shape[1] for r in rows)
    sheet = np.zeros((len(rows) * 52, w), np.float32)
    for i, (img, _) in enumerate(rows):
        sheet[i * 52:i * 52 + 48, :img.shape[1]] = img
    out = sys.argv[1] if len(sys.argv) > 1 else "font_lines.png"
    Image.fromarray((255 - sheet * 255).astype(np.uint8)).save(out)
    print("\n".join(t for _, t in rows))
