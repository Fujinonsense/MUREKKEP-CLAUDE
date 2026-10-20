"""Handwriting-font glyphs as pen skeletons. Each glyph is rendered at EM pixels, thinned to its
one-pixel centre line (skimage skeletonize) and stored in StrokeFont units (cap height 10, y up,
baseline at 0) as segments between neighbouring skeleton pixels (arrays of rows x0, y0, x1, y1), so
the pen line stays connected however much a glyph is enlarged. A Turkish letter the font lacks is
composed from its base letter and a drawn accent, kept as a separate part so the generator can move
it like a hand does.

usage: python glyphs.py build   (fills the cache for every font, in parallel)"""
import math
import os
import sys
from functools import lru_cache
from multiprocessing import Pool
from pathlib import Path

import numpy as np
from fontTools.ttLib import TTFont
from PIL import Image, ImageDraw, ImageFont
from skimage.morphology import skeletonize

from charset import CHARSET

DATA = Path(os.environ.get("MRK_DATA", "C:/Users/orsyu/mrk-ml/data"))
CACHE = Path(os.environ.get("MRK_CACHE", "C:/Users/orsyu/mrk-ml/cache")) / "glyphs"
EM = 128
STEP = 0.06  # accent point spacing in units

# Turkish letter → (base, accent)
COMPOSE = {
    "ş": ("s", "cedilla"), "ç": ("c", "cedilla"), "ğ": ("g", "breve"), "ö": ("o", "dots"), "ü": ("u", "dots"),
    "Ş": ("S", "cedilla"), "Ç": ("C", "cedilla"), "Ğ": ("G", "breve"), "Ö": ("O", "dots"), "Ü": ("U", "dots"),
    "İ": ("I", "dot"), "ı": ("i", "dotless"),
}


# Capital letters with more than this many times the ink of small letters are calligraphy, not the
# handwriting of the people using the app.
CALLIGRAPHY = 3.5


def _all_fonts():
    # "Guides" variants draw handwriting-practice lines under every letter.
    return sorted(p for p in (DATA / "fonts").glob("*.ttf") if "Guides" not in p.name)


def caps_ratio(table):
    """Mean ink length of A–Z over a–z (1.0 when either is missing)."""
    def ink(parts):
        return sum(float(np.hypot(p[:, 2] - p[:, 0], p[:, 3] - p[:, 1]).sum()) for p in parts)
    up = [ink(table[c][0]) for c in "ABCDEFGHIJKLMNOPQRSTUVWXYZ" if c in table]
    lo = [ink(table[c][0]) for c in "abcdefghijklmnopqrstuvwxyz" if c in table]
    return float(np.mean(up) / np.mean(lo)) if up and lo and np.mean(lo) > 0 else 1.0


@lru_cache(maxsize=1)
def _usable():
    return tuple(p for p in _all_fonts() if caps_ratio(font_glyphs(p)[0]) <= CALLIGRAPHY)


def fonts():
    """Handwriting fonts used for training (no guide lines, no calligraphy)."""
    return list(_usable())


@lru_cache(maxsize=512)
def _cmap(path):
    try:
        return set((TTFont(str(path), lazy=True).getBestCmap() or {}).keys())
    except Exception:
        return set()


def covers(path, ch):
    return ord(ch) in _cmap(Path(path))


def segments(polyline):
    """Segments (rows x0, y0, x1, y1) of a polyline; a single point is a zero-length segment."""
    p = np.asarray(polyline, dtype=np.float32).reshape(-1, 2)
    if len(p) == 1:
        return np.concatenate([p, p], axis=1)
    return np.concatenate([p[:-1], p[1:]], axis=1)


def endpoints(segs):
    return segs.reshape(-1, 2)


def _accent(kind, base):
    """Segments of an accent for a base glyph (units)."""
    pts = endpoints(base)
    cx = float((pts[:, 0].min() + pts[:, 0].max()) / 2)
    top = float(pts[:, 1].max())
    if kind == "cedilla":
        return segments([(cx, -0.2), (cx + 0.6, -0.9), (cx - 0.1, -1.7), (cx - 0.7, -1.5)])
    if kind == "breve":
        return segments([(cx + 1.3 * math.cos(math.radians(a)), top + 2.4 + 1.3 * math.sin(math.radians(a)))
                         for a in range(200, 341, 10)])
    # Dots as a hand makes them: short dabs, big enough to survive a thin pen.
    if kind == "dots":
        return np.concatenate([segments([(cx - 1.2, top + 1.15), (cx - 0.8, top + 1.6)]),
                               segments([(cx + 0.8, top + 1.15), (cx + 1.2, top + 1.6)])])
    if kind == "dot":
        return segments([(cx - 0.15, top + 1.25), (cx + 0.25, top + 1.7)])
    raise ValueError(kind)


def _skeleton_segments(skel):
    """Segments joining 8-neighbouring skeleton pixels (each pair once); lone pixels become points."""
    rows, cols = np.nonzero(skel)
    on = set(zip(rows.tolist(), cols.tolist()))
    out = []
    for r, c in on:
        linked = False
        for dr, dc in ((0, 1), (1, -1), (1, 0), (1, 1)):
            if (r + dr, c + dc) in on:
                out.append((c, r, c + dc, r + dr))
                linked = True
        if not linked and not any((r + dr, c + dc) in on for dr, dc in ((0, -1), (-1, 1), (-1, 0), (-1, -1))):
            out.append((c, r, c, r))
    return np.asarray(out, dtype=np.float32).reshape(-1, 4)


def _render(font, ch, unit):
    """Skeleton segments (units) and advance of one glyph."""
    left, top, right, bottom = font.getbbox(ch, anchor="ls")
    if right - left < 1 and bottom - top < 1:
        return None
    pad = 4
    w, h = int(right - left) + 2 * pad, int(bottom - top) + 2 * pad
    img = Image.new("L", (w, h), 0)
    ImageDraw.Draw(img).text((pad - left, pad - top), ch, font=font, fill=255, anchor="ls")
    mask = np.asarray(img) > 127
    if not mask.any():
        return None
    seg = _skeleton_segments(skeletonize(mask))
    seg[:, [0, 2]] = (seg[:, [0, 2]] - (pad - left)) * unit
    seg[:, [1, 3]] = ((pad - top) - seg[:, [1, 3]]) * unit
    return seg, float(font.getlength(ch)) * unit


def _build(path):
    font = ImageFont.truetype(str(path), EM)
    cap = None
    for ref in "HEA":
        if covers(path, ref):
            l, t, r, b = font.getbbox(ref, anchor="ls")
            if -t > 4:
                cap = -t
                break
    unit = 10.0 / (cap or EM * 0.7)
    out = {}
    for ch in CHARSET:
        if ch == " " or not covers(path, ch):
            continue
        got = _render(font, ch, unit)
        if got is not None:
            out[ch] = ([got[0]], got[1])
    x_height = float(endpoints(out["x"][0][0])[:, 1].max()) if "x" in out else 6.5
    for ch, (base_ch, kind) in COMPOSE.items():
        if ch in out or base_ch not in out:
            continue
        base, advance = out[base_ch][0][0], out[base_ch][1]
        if kind == "dotless":
            body = base[np.maximum(base[:, 1], base[:, 3]) <= x_height * 1.15]
            if len(body):
                out[ch] = ([body], advance)
            continue
        out[ch] = ([base, _accent(kind, base)], advance)
    space = float(font.getlength(" ")) * unit if covers(path, " ") else 4.0
    return out, space


def _cache_file(path):
    return CACHE / (Path(path).stem + ".npz")


def font_glyphs(path):
    """({character: ([part points, …], advance)}, space advance) for a font, cached on disk."""
    f = _cache_file(path)
    if f.exists():
        z = np.load(f, allow_pickle=False)
        out = {}
        for key in z.files:
            if not key.startswith("a"):
                continue
            ch = chr(int(key[1:]))
            parts = []
            k = 0
            while f"p{ord(ch)}_{k}" in z.files:
                parts.append(z[f"p{ord(ch)}_{k}"].astype(np.float32))
                k += 1
            out[ch] = (parts, float(z[key]))
        return out, float(z["space"])
    out, space = _build(path)
    CACHE.mkdir(parents=True, exist_ok=True)
    arrays = {"space": np.float32(space)}
    for ch, (parts, advance) in out.items():
        arrays[f"a{ord(ch)}"] = np.float32(advance)
        for k, p in enumerate(parts):
            arrays[f"p{ord(ch)}_{k}"] = p.astype(np.float16)
    np.savez_compressed(f, **arrays)
    return out, space


def _build_one(path):
    try:
        font_glyphs(path)
        return path.name, None
    except Exception as e:  # a broken font is skipped, not fatal
        return path.name, repr(e)


if __name__ == "__main__" and sys.argv[1:] == ["build"]:
    all_fonts = _all_fonts()
    with Pool(20) as pool:
        failed = [(n, e) for n, e in pool.imap_unordered(_build_one, all_fonts) if e]
    print(f"{len(all_fonts) - len(failed)} fonts cached, {len(failed)} failed: {failed[:5]}")
