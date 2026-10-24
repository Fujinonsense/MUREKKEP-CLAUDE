"""The app's single-line lettering font (Murekkep.swiftpm/StrokeFont.swift), read straight from the
Swift source so training sees exactly the letters the app writes. Units: cap height 10, y up."""
import math
import re
from functools import lru_cache
from pathlib import Path

SWIFT = Path(__file__).resolve().parents[2] / "Murekkep.swiftpm" / "StrokeFont.swift"
TRACKING = 2.8
# The word gap synthetic handwriting is built around (typed text in the app now uses 7.0,
# StrokeFont.spaceAdvance); kept so the training data stays as the readers were trained on.
SPACE = 5.5

_ENTRY = re.compile(r'^\s+"((?:[^"\\]|\\.)+)":\s*"((?:[^"\\]|\\.)*)"', re.M)


def _unescape(s):
    s = re.sub(r"\\u\{([0-9a-fA-F]+)\}", lambda m: chr(int(m.group(1), 16)), s)
    return s.replace('\\"', '"').replace("\\\\", "\\")


def _arc(cx, cy, rx, ry, a0, a1):
    sweep = a1 - a0
    steps = max(2, math.ceil(abs(sweep) / 12))
    return [(cx + rx * math.cos(math.radians(a0 + sweep * i / steps)),
             cy + ry * math.sin(math.radians(a0 + sweep * i / steps))) for i in range(steps + 1)]


def _parse(spec):
    advance, body = spec.split(";", 1)
    paths = []
    for segment in body.split("|"):
        pts = []
        for token in segment.split():
            if token.startswith(("a(", "e(")):
                v = [float(t) for t in token[2:-1].split(",")]
                if token.startswith("a(") and len(v) == 5:
                    pts += _arc(v[0], v[1], v[2], v[2], v[3], v[4])
                elif len(v) == 6:
                    pts += _arc(*v)
            else:
                v = [float(t) for t in token.split(",")]
                if len(v) == 2:
                    pts.append((v[0], v[1]))
        if pts:
            paths.append(pts)
    return float(advance), paths


@lru_cache(maxsize=1)
def glyphs():
    """{character: (advance, [path, …])} with paths as lists of (x, y)."""
    text = SWIFT.read_text(encoding="utf-8")
    table = text.split("private static let source")[1].split("\n    ]\n")[0]
    return {_unescape(k): _parse(v) for k, v in _ENTRY.findall(table)}


# Training-only shapes for the two charset characters StrokeFont does not draw (the app writes "&" as
# a word and has no "@").
EXTRA = {
    "&": _parse("6.2; 6,0 1.6,5.2 1.2,7.6 2.6,9.8 4.2,9.4 4.4,7.6 1,3.6 1.2,0.9 3,-0.1 6.2,3.8"),
    "@": _parse("8; e(4,4.4,4,4.6,-30,320) | e(4,4.4,1.6,2,0,360) | 5.6,6.2 5.6,3.2 6.4,2.4 7.6,3.6"),
}


def glyph(ch):
    """(advance, paths) from StrokeFont or the training-only extras; None when neither has it."""
    return glyphs().get(ch) or EXTRA.get(ch)
