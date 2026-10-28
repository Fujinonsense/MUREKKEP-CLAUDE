"""The ad recordings' scenes (tools/demo): what the scripted pencil writes and draws, as
scenes/DemoScene-<scene>-<language of the app>.json for DemoPlayer.swift, with a preview PNG of
every page and board in previews/. One video for everyone: the app in English, and the notebook
holds one line in English and one in Turkish (the ad's captions are English).

The handwriting is a neat hand made from single-line fonts (EMS Neato and EMS Tech, SVG fonts by
Windell Oskay under the SIL Open Font License, see fonts/OFL.txt): every letter a little different,
the way a hand makes it, written at a hand's speed (slower in the turns: the two-thirds power law).
Only the hand is staged. The app draws the ink, and the text pen reads what is written by itself.

    python tools/demo/make_scenes.py
"""
import base64
import json
import math
import re
import xml.etree.ElementTree as ET
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
FONTS = HERE / "fonts"
SCENES = HERE / "scenes"
PREVIEWS = HERE / "previews"
PAGE = (595.28, 841.89)
RULE_TOP, RULE_STEP, MARGIN = 84.0, 28.0, 72.0
RATE = 240.0  # Apple Pencil's samples a second
# The simulator's recorder keeps up with only a few changes a second, so the scenes the pen carries
# alone are filmed this much slower and sped up as much in the edit; the app's own timings (the text
# pen's pause, ink drying, lava cooling) stretch alike through launch arguments, so the finished
# video shows them at their real lengths. Ebru and the living ink run on their own clocks: pace 1.
PACE = {"notes": 1.8, "textpen": 1.8, "inks": 1.8, "ebru": 2.5, "living": 2.5,
        "check": 1.8, "solve": 1.8, "convert": 1.8,
        "shapes": 1.8, "tilt": 1.8, "dots": 1.8, "xox": 1.8}
# The games run on the app's DEMO clock at the same slower rate (their moves and time per frame).
CLOCKED = {"ebru", "living"}
LANGS = ("en",)  # the app's language in the recordings


# MARK: - Single-line fonts

def _flatten_path(d):
    """M/L/C path data (absolute, font units, y up) as polylines."""
    tokens = re.findall(r"[MLCZmlcz]|-?\d*\.?\d+(?:e-?\d+)?", d)
    strokes, cur, i, cmd = [], None, 0, None
    while i < len(tokens):
        t = tokens[i]
        if t.isalpha():
            cmd = t
            i += 1
            if cmd in "Zz" and cur:
                cur.append(cur[0])
            continue
        if cmd == "M":
            cur = [(float(tokens[i]), float(tokens[i + 1]))]
            strokes.append(cur)
            i += 2
            cmd = "L"
        elif cmd == "L":
            cur.append((float(tokens[i]), float(tokens[i + 1])))
            i += 2
        elif cmd == "C":
            x0, y0 = cur[-1]
            x1, y1, x2, y2, x3, y3 = (float(v) for v in tokens[i:i + 6])
            for k in range(1, 9):
                u = k / 8
                a, b, c, e = (1 - u) ** 3, 3 * u * (1 - u) ** 2, 3 * u * u * (1 - u), u ** 3
                cur.append((a * x0 + b * x1 + c * x2 + e * x3, a * y0 + b * y1 + c * y2 + e * y3))
            i += 6
        else:
            raise ValueError(f"path command {cmd} in {d[:40]}")
    return [s for s in strokes if len(s) >= 1]


class Font:
    def __init__(self, name):
        root = ET.parse(FONTS / f"{name}.svg").getroot()
        ns = "{http://www.w3.org/2000/svg}"
        default = float(root.find(f".//{ns}font").get("horiz-adv-x"))
        self.glyphs = {}
        for g in root.iter(f"{ns}glyph"):
            u = g.get("unicode")
            if u is None or len(u) != 1:
                continue
            self.glyphs[u] = (float(g.get("horiz-adv-x", default)), _flatten_path(g.get("d") or ""))
        self.xheight = max(y for s in self.glyphs["x"][1] for _, y in s)
        self.cap = max(y for s in self.glyphs["H"][1] for _, y in s)
        self._turkish()

    def _turkish(self):
        """ı İ ş Ş ğ Ğ from the Latin-1 letters (ç, ö, ü are there already)."""
        g = self.glyphs
        adv_i, i_strokes = g["i"]
        dot = max(i_strokes, key=lambda s: min(y for _, y in s))
        g["ı"] = (adv_i, [s for s in i_strokes if s is not dot])
        top_I = max(y for s in g["I"][1] for _, y in s)
        dot_y = min(y for _, y in dot)
        dot_x = np.mean([x for x, _ in dot])
        cx_I = np.mean([x for s in g["I"][1] for x, _ in s])
        lift = top_I + 0.18 * self.xheight - dot_y
        g["İ"] = (g["I"][0], g["I"][1] + [[(x - dot_x + cx_I, y + lift) for x, y in dot]])

        def cedilla(with_mark, plain):
            marks = [s for s in g[with_mark][1] if max(y for _, y in s) < 0.08 * self.xheight
                     and s not in g[plain][1]]
            return marks or [min(g[with_mark][1], key=lambda s: min(y for _, y in s))]

        def put_under(base, marks):
            adv, strokes = g[base]
            xs = [x for s in strokes for x, _ in s]
            cx = (min(xs) + max(xs)) / 2
            mx = np.mean([x for s in marks for x, _ in s])
            return adv, strokes + [[(x - mx + cx, y) for x, y in s] for s in marks]

        g["ş"] = put_under("s", cedilla("ç", "c"))
        g["Ş"] = put_under("S", cedilla("Ç", "C"))

        def breve(base, height):
            adv, strokes = g[base]
            xs = [x for s in strokes for x, y in s if y > 0]
            cx = (min(xs) + max(xs)) / 2
            r = 0.2 * self.xheight
            cy = height + 0.42 * self.xheight
            arc = [(cx + r * math.cos(a), cy + 0.8 * r * math.sin(a)) for a in np.linspace(math.pi * 1.02, math.pi * 1.98, 9)]
            return adv, strokes + [arc]

        g["ğ"] = breve("g", self.xheight)
        g["Ğ"] = breve("G", self.cap)


# MARK: - A hand

class Hand:
    """Writes text with a font as a careful person would: each letter a little different."""

    def __init__(self, font, seed, slant=0.0, jitter=1.0):
        self.font = font
        self.rng = np.random.default_rng(seed)
        self.slant = slant
        self.jitter = jitter

    def text(self, text, x, base, xh, digit_gap=0.0):
        """`digit_gap` (in x-heights) opens figures that follow each other ("33", "17"), which the
        lining figures of math_font otherwise let touch."""
        f, rng, j = self.font, self.rng, self.jitter
        s = xh / f.xheight
        phase = rng.uniform(0, 2 * math.pi)
        wave = rng.uniform(200, 340)
        out, starts = [], []
        for i, ch in enumerate(text):
            if digit_gap and ch.isdigit() and i > 0 and text[i - 1].isdigit():
                x += digit_gap * xh
            starts.append(x)
            adv, glyph = f.glyphs.get(ch) or f.glyphs["?"]
            if ch == " ":
                x += adv * s * rng.uniform(0.92, 1.12)
                continue
            k = 1 + rng.normal(0, 0.022 * j)
            rot = rng.normal(0, math.radians(1.1) * j)
            dy = rng.normal(0, 0.03 * xh * j) + 0.05 * xh * math.sin(2 * math.pi * x / wave + phase)
            cx = adv * s / 2
            cos, sin = math.cos(rot), math.sin(rot)
            for st in glyph:
                pts = []
                for gx, gy in st:
                    px, py = gx * s * k, -gy * s * k
                    px += self.slant * -py
                    qx = cx + (px - cx) * cos - py * sin
                    qy = (px - cx) * sin + py * cos
                    pts.append((x + qx, base + qy + dy))
                out.append(_wobble(pts, xh, rng, j))
            x += adv * s * k * (1 + rng.normal(0, 0.025 * j))
        starts.append(x)
        self.starts = starts
        return out, x


def _densify(pts, step=0.6):
    pts = np.asarray(pts, dtype=float)
    if len(pts) < 2:
        return pts
    out = [pts[0]]
    for a, b in zip(pts[:-1], pts[1:]):
        n = max(1, int(np.ceil(np.hypot(*(b - a)) / step)))
        for k in range(1, n + 1):
            out.append(a + (b - a) * k / n)
    return np.asarray(out)


def _wobble(pts, xh, rng, j):
    """A hand never draws the font's line exactly: a slow, small sway across the stroke."""
    p = _densify(pts)
    if len(p) < 3:
        return p.tolist()
    seg = np.diff(p, axis=0)
    u = np.concatenate([[0], np.cumsum(np.hypot(seg[:, 0], seg[:, 1]))])
    tangent = np.gradient(p, axis=0)
    norm = np.hypot(tangent[:, 0], tangent[:, 1])
    norm[norm == 0] = 1
    normal = np.stack([-tangent[:, 1] / norm, tangent[:, 0] / norm], axis=1)
    a = 0.016 * xh * j
    l1, l2 = rng.uniform(1.2, 2.2) * xh, rng.uniform(0.45, 0.8) * xh
    sway = a * (np.sin(2 * np.pi * u / l1 + rng.uniform(0, 6.3)) + 0.45 * np.sin(2 * np.pi * u / l2 + rng.uniform(0, 6.3)))
    return (p + normal * sway[:, None]).tolist()


# MARK: - Timing

def timed(strokes, rng, xh=11.0, speed=1.0, start=0.0, line_breaks=()):
    """Samples [t, x, y, force] for each stroke, timed like a hand: slower in the turns, a moment in
    the air between strokes (longer between lines: `line_breaks` are the stroke indices that begin
    one). Returns the strokes and the time the last one ends."""
    size = (xh / 11.0) ** 0.6
    v0, vmin, vmax = 92 * size, 30 * size, 175 * size
    out, t, last = [], start, None
    breaks = set(line_breaks)
    for n, st in enumerate(strokes):
        p = _densify(st, 0.5)
        if last is not None:
            gap = 0.075 + np.hypot(*(p[0] - last)) / (680 * size) + abs(rng.normal(0, 0.02))
            if n in breaks:
                gap += 0.32
            t += gap / speed
        if len(p) < 2:
            out.append([[round(t, 4), round(p[0][0], 2), round(p[0][1], 2), 0.8]])
            t += 0.03 / speed
            last = p[0]
            continue
        seg = np.diff(p, axis=0)
        ds = np.hypot(seg[:, 0], seg[:, 1])
        ang = np.arctan2(seg[:, 1], seg[:, 0])
        turn = np.abs((np.diff(ang) + np.pi) % (2 * np.pi) - np.pi)
        kappa = np.concatenate([[turn[0] if len(turn) else 0], turn, [turn[-1] if len(turn) else 0]]) / np.maximum(
            np.concatenate([[ds[0]], (ds[:-1] + ds[1:]) / 2, [ds[-1]]]), 1e-3)
        v = np.clip(v0 * (0.2 / np.maximum(kappa, 1e-4)) ** (1 / 3), vmin, vmax)
        v = np.convolve(np.pad(v, 4, mode="edge"), np.ones(9) / 9, mode="valid")
        u = np.concatenate([[0], np.cumsum(ds)])
        total = u[-1]
        ramp = np.clip(np.minimum(u, total - u) / (3.5 * size), 0, 1)
        v = v * (0.4 + 0.6 * ramp) * speed
        dt = ds / ((v[:-1] + v[1:]) / 2)
        times = np.concatenate([[0], np.cumsum(dt)])
        dur = times[-1]
        ts = np.arange(0, dur, 1 / RATE)
        if len(ts) == 0 or ts[-1] < dur:
            ts = np.append(ts, dur)
        xs = np.interp(ts, times, p[:, 0])
        ys = np.interp(ts, times, p[:, 1])
        vs = np.interp(ts, times, v)
        press = 0.95 + 0.12 * np.sin(2 * np.pi * ts / 0.9 + rng.uniform(0, 6.3)) - 0.18 * (vs / (vmax * speed))
        press *= np.clip(0.35 + ts / 0.035 * 0.65, 0.35, 1) * np.clip(0.5 + (dur - ts) / 0.05 * 0.5, 0.5, 1)
        out.append([[round(t + a, 4), round(b, 2), round(c, 2), round(float(f), 3)]
                    for a, b, c, f in zip(ts, xs, ys, press)])
        t += dur
        last = p[-1]
    return out, t


# MARK: - Drawings

def _smooth_closed(points, n=120):
    """A soft closed curve through control points (Catmull-Rom)."""
    pts = np.asarray(points, dtype=float)
    m = len(pts)
    out = []
    for i in range(m):
        p0, p1, p2, p3 = pts[(i - 1) % m], pts[i], pts[(i + 1) % m], pts[(i + 2) % m]
        for u in np.linspace(0, 1, n // m, endpoint=False):
            u2, u3 = u * u, u * u * u
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * u + (2 * p0 - 5 * p1 + 4 * p2 - p3) * u2 + (-p0 + 3 * p1 - 3 * p2 + p3) * u3))
    out.append(out[0])
    return np.asarray(out)


def _smooth_open(points, n=80):
    pts = np.asarray(points, dtype=float)
    pts = np.vstack([pts[0] * 2 - pts[1], pts, pts[-1] * 2 - pts[-2]])
    out = []
    for i in range(1, len(pts) - 2):
        p0, p1, p2, p3 = pts[i - 1], pts[i], pts[i + 1], pts[i + 2]
        for u in np.linspace(0, 1, max(2, n // (len(pts) - 3)), endpoint=False):
            u2, u3 = u * u, u * u * u
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * u + (2 * p0 - 5 * p1 + 4 * p2 - p3) * u2 + (-p0 + 3 * p1 - 3 * p2 + p3) * u3))
    out.append(pts[-2])
    return np.asarray(out)


def fish(cx, cy, length, facing_left=True, rng=None):
    """One stroke from the mouth over the back to a forked tail and along the belly back, then the eye.
    The tail end is the taller one, so the living ink knows where the head is."""
    h = length * 0.42
    body = [(0.0, 0.0), (0.12, -0.42), (0.38, -0.55), (0.62, -0.42), (0.80, -0.12),
            (1.0, -0.62), (0.96, 0.0), (1.0, 0.62), (0.80, 0.12), (0.62, 0.42), (0.38, 0.55), (0.12, 0.40), (0.0, 0.02)]
    pts = _smooth_open(body, 140)
    s = 1 if facing_left else -1
    line = [(cx + s * (x - 0.5) * length, cy + y * h / 1.1) for x, y in pts]
    eye_c = (cx + s * (0.16 - 0.5) * length, cy - 0.16 * h)
    eye = [(eye_c[0] + 0.035 * length * math.cos(a), eye_c[1] + 0.035 * length * math.sin(a)) for a in np.linspace(0, 2 * math.pi, 14)]
    if rng is not None:
        line = _wobble(line, length * 0.12, rng, 1.0)
    return [line, eye]


def eel(cx, cy, length, rng=None):
    """A long eel: the stroke begins at its round head on the left and waves out to a forked tail fin,
    the taller end, so the living ink swims it head first."""
    r = 0.035 * length
    x0 = cx - 0.5 * length
    head = [(x0 + r + r * math.cos(a), cy + r * math.sin(a)) for a in np.linspace(math.pi * 0.15, math.pi * 2.1, 18)]
    u = np.linspace(0, 1, 140)
    xs = x0 + 2 * r + u * (length - 2 * r - 0.05 * length)
    ys = cy + 0.06 * length * np.sin(u * 2.6 * math.pi) * (1 - 0.35 * u)
    xe, ye = xs[-1], ys[-1]
    fin = _smooth_open([(xe, ye), (xe + 0.05 * length, ye - 0.085 * length), (xe + 0.02 * length, ye),
                        (xe + 0.05 * length, ye + 0.085 * length)], 30)
    line = head + list(zip(xs, ys)) + [tuple(p) for p in fin[1:]]
    if rng is not None:
        line = _wobble(line, length * 0.08, rng, 1.0)
    eye = [(x0 + 1.2 * r + 0.25 * r * math.cos(a), cy - 0.25 * r + 0.25 * r * math.sin(a)) for a in np.linspace(0, 2 * math.pi, 8)]
    return [line, eye]


def faces_right(strokes):
    """InkPond.facesRight (LivingInkLogic.swift): the taller outer eighth is the tail; when the ends
    are even, the head is where the stroke began."""
    pts = np.asarray([p for st in strokes for p in st], dtype=float)
    lo, hi = pts[:, 0].min(), pts[:, 0].max()
    width = hi - lo

    def tall(a, b):
        ys = pts[(pts[:, 0] >= a) & (pts[:, 0] <= b), 1]
        return ys.max() - ys.min() if len(ys) else 0

    left, right = tall(lo, lo + width / 8), tall(hi - width / 8, hi)
    if right > left * 1.3 + 1:
        return False
    if left > right * 1.3 + 1:
        return True
    return pts[0, 0] > lo + width / 2


def branch(x0, y0, length, rng):
    """A branch with a few twigs, for the flowers on water."""
    main = _smooth_open([(x0, y0), (x0 + 0.3 * length, y0 - 0.12 * length), (x0 + 0.62 * length, y0 - 0.16 * length),
                         (x0 + length, y0 - 0.34 * length)], 90)
    out = [_wobble(main, 14, rng, 1.0)]
    for u, dx, dy in [(0.28, 0.08, -0.2), (0.55, 0.12, 0.12), (0.75, 0.04, -0.22)]:
        i = int(u * (len(main) - 1))
        sx, sy = main[i]
        twig = _smooth_open([(sx, sy), (sx + dx * length * 0.6, sy + dy * length * 0.45), (sx + dx * length, sy + dy * length * 0.8)], 30)
        out.append(_wobble(twig, 10, rng, 1.0))
    return out


def wavy(x0, x1, y, amp, waves, rng):
    xs = np.linspace(x0, x1, 160)
    ys = y + amp * np.sin(np.linspace(0, waves * 2 * math.pi, 160) + 0.3)
    return [_wobble(list(zip(xs, ys)), 18, rng, 1.0)]


def loop(cx, cy, rx, ry, rng, turns=1.06):
    a = np.linspace(-math.pi * 0.62, -math.pi * 0.62 + 2 * math.pi * turns, 140)
    pts = [(cx + rx * math.cos(t) * (1 + 0.03 * math.sin(3 * t)), cy + ry * math.sin(t)) for t in a]
    return [_wobble(pts, 20, rng, 1.0)]


# MARK: - Scenes

NAVY = [0.10, 0.17, 0.42]
INK = [0.11, 0.12, 0.20]
RED = [0.80, 0.16, 0.16]
YELLOW = [1.0, 0.86, 0.25]
GALAXY = [0.35, 0.25, 0.85]

TEXT = {
    "en": {
        "notes.title": "Biology",
        "notes.head": "Cell Biology",
        # One line in English, the same idea in Turkish under it.
        "notes.lines": ["Mitochondria are the powerhouse of the cell.",
                        "Mitokondri hücrenin enerji santralidir."],
        "notes.mark": "powerhouse of the cell",
        "notes.under": "enerji santralidir",
        "textpen.title": "Notes",
        "textpen.lines": ["The cell is the basic unit of life.", "Hücre canlının en küçük birimidir."],
        "inks.title": "Inks",
        "inks.lava": "Sınav!", "inks.gold": "A+", "inks.galaxy": "Dream big",
        "break.title": "Study",
        # The math pages hold a one-word label and calculations only: a sentence on the page sends it
        # to the language model (PageMath.engineSettles), which the recording build does not have.
        # Each scene has an English and a Turkish word: one is the notebook's title, one on the page.
        "check.title": "Matematik",
        "check.label": "Homework",
        "check.lines": ["5x - 3 = 2x + 9", "3x = 12", "x = 5"],
        "solve.title": "Algebra",
        "solve.label": "Ödev",
        "solve.lines": ["3 + 3 = 33", "15 - 7 = 8", "2x + 3 = 11", "x + y = 10", "x - y = 2"],
        "solve.chat": "Is 7+8=16?",
        "convert.title": "Biology",
        "convert.lines": ["Biology", "Exam on Tuesday", "Sınav salı günü"],
        "shapes.title": "Biyoloji",
        "tilt.title": "Notes",
        "tilt.lines": ["Turn the page like paper.", "Sayfayı kağıt gibi çevir."],
        # The searched page shows in the hit as Vision read it. Run 6ae226b3 read "Mitokondri" as
        # "Mitokonari" but "enerji üretir" right, so the Turkish line keeps to those two words.
        "search.notes": [("Biology", ["Mitochondria make energy.", "Enerji üretir."]),
                         ("Chemistry", ["Water boils at 100 degrees.", "Su 100 derecede kaynar."]),
                         ("Tarih", ["Istanbul was taken in 1453.", "İstanbul 1453'te alındı."])],
        "search.query": "mitochondria",
        "photo.title": "Worksheet",
    },
}


def rule(k):
    return RULE_TOP + RULE_STEP * k


class Script:
    def __init__(self):
        self.launch = []
        self.steps = []
        self.page_strokes = []  # (brush, colour, width, strokes) for the preview
        self.boards = {}        # name -> list of (colour index, strokes)

    def add(self, op, **kw):
        self.steps.append({"op": op, **kw})

    def write(self, strokes, brush, colour, width, page=0, hold=False):
        if hold:
            # The pencil rests at the end of each stroke: the canvas's own wait turns it into a shape.
            self.add("write", page=page, strokes=strokes, hold=True)
        else:
            self.add("write", page=page, strokes=strokes)
        self.page_strokes.append((brush, colour, width, [[(p[1], p[2]) for p in s] for s in strokes]))


def notes_lines(script, lang, hand, rng, speed=1.0, head=True, count=3):
    t = TEXT[lang]
    if head:
        script.add("pen", brush="fountain", color=NAVY, width=3.0)
        strokes, _ = hand.text(t["notes.head"], MARGIN + 12, rule(1) - 2, 18)
        timed_strokes, _ = timed(strokes, rng, xh=18, speed=speed)
        script.write(timed_strokes, "fountain", NAVY, 3.0)
        script.add("wait", seconds=0.5 / speed)
    script.add("pen", brush="pen", color=INK, width=2.0)
    all_strokes, breaks, starts = [], [], []
    for k, line in enumerate(t["notes.lines"][:count]):
        strokes, _ = hand.text(line, MARGIN + 12, rule(3 + k) - 1.5, 12.5)
        starts.append(hand.starts)
        breaks.append(len(all_strokes))
        all_strokes += strokes
    timed_strokes, _ = timed(all_strokes, rng, xh=12.5, speed=speed, line_breaks=breaks[1:])
    script.write(timed_strokes, "pen", INK, 2.0)
    return starts


def scene_notes(lang):
    rng = np.random.default_rng(11 if lang == "en" else 12)
    hand = Hand(Font("EMSNeato"), seed=5 if lang == "en" else 6, slant=0.04)
    s = Script()
    t = TEXT[lang]
    s.add("note", title=t["notes.title"], paper="lined", seconds=1.2)
    starts = notes_lines(s, lang, hand, rng)
    s.add("wait", seconds=0.6)
    # The highlighter over the English key phrase, the Turkish one underlined in red.
    first = t["notes.lines"][0]
    mark = t["notes.mark"]
    a = first.index(mark)
    x_before, x_after = starts[0][a], starts[0][a + len(mark)]
    y = rule(3) - 1.5 - 5.6
    s.add("pen", brush="highlighter", color=YELLOW, width=14)
    swipe = [list(zip(np.linspace(x_before - 3, x_after + 2, 60), y + 0.8 * np.sin(np.linspace(0, 2.5, 60))))]
    hl, _ = timed(swipe, rng, xh=26, speed=0.9)
    s.write(hl, "highlighter", YELLOW, 14)
    s.add("wait", seconds=0.5)
    s.add("pen", brush="pen", color=RED, width=2.2)
    second = t["notes.lines"][1]
    b = second.index(t["notes.under"])
    under = [list(zip(np.linspace(starts[1][b] - 2, starts[1][b + len(t["notes.under"])] + 1, 40),
                      rule(4) + 1.6 + np.linspace(0.6, -0.8, 40)))]
    un, _ = timed(under, rng, xh=14, speed=1.0)
    s.write(un, "pen", RED, 2.2)
    s.add("wait", seconds=2.5)
    return s


def scene_textpen(lang):
    # The text pen writes with the last pen picked; a galaxy ink in a round hand makes the change
    # to typed text plain to see (EMS Tech looked typed already). Each line waits long enough for
    # its conversion and a still moment after it (the user, 2026-10-28: the Turkish line ended
    # the old recording while it was still converting).
    rng = np.random.default_rng(21 if lang == "en" else 22)
    hand = Hand(Font("EMSNeato"), seed=7 if lang == "en" else 8, slant=0.04, jitter=0.9)
    s = Script()
    t = TEXT[lang]
    s.add("note", title=t["textpen.title"], paper="lined", seconds=1.2)
    s.add("textpen", brush="galaxy", color=GALAXY, width=3.6)
    for k, line in enumerate(t["textpen.lines"]):
        strokes, _ = hand.text(line, MARGIN + 12, rule(2 + 2 * k) - 1.5, 14)
        timed_strokes, _ = timed(strokes, rng, xh=14)
        s.write(timed_strokes, "galaxy", GALAXY, 3.6)
        s.add("wait", seconds=5.0 if k == 0 else 7.0)
    return s


def scene_inks(lang):
    rng = np.random.default_rng(31 if lang == "en" else 32)
    hand = Hand(Font("EMSNeato"), seed=9 if lang == "en" else 10, slant=0.05, jitter=0.9)
    s = Script()
    t = TEXT[lang]
    s.add("note", title=t["inks.title"], paper="plain", seconds=1.2)

    def big(word, brush, colour, width, x, base, xh, wait):
        s.add("pen", brush=brush, color=colour, width=width)
        strokes, end = hand.text(word, x, base, xh)
        ts, _ = timed(strokes, rng, xh=xh)
        s.write(ts, brush, colour, width)
        s.add("wait", seconds=wait)
        pts = np.asarray([p for st in strokes for p in st])
        return pts.min(axis=0), pts.max(axis=0)

    big(t["inks.lava"], "lava", [0.95, 0.35, 0.08], 9, 92, 200, 46, 3.4)
    lo, hi = big(t["inks.gold"], "gold", [0.93, 0.72, 0.25], 7, 400, 210, 48, 0.8)
    s.add("pen", brush="wave", color=[0.12, 0.45, 0.80], width=10)
    ring = loop((lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2, (hi[0] - lo[0]) / 2 + 24, (hi[1] - lo[1]) / 2 + 24, rng)
    ts, _ = timed(ring, rng, xh=40)
    s.write(ts, "wave", [0.12, 0.45, 0.80], 10)
    s.add("wait", seconds=1.2)
    lo, hi = big(t["inks.galaxy"], "galaxy", [0.35, 0.25, 0.85], 10, 96, 380, 40, 1.0)
    s.add("pen", brush="sea", color=[0.10, 0.55, 0.75], width=9)
    ts, _ = timed(wavy(lo[0] - 6, max(hi[0] + 10, 420), hi[1] + 16, 7, 4, rng), rng, xh=36)
    s.write(ts, "sea", [0.10, 0.55, 0.75], 9)
    s.add("wait", seconds=1.2)
    s.add("pen", brush="bloom", color=[0.20, 0.55, 0.35], width=7)
    ts, _ = timed(branch(120, 600, 330, rng), rng, xh=40)
    s.write(ts, "bloom", [0.20, 0.55, 0.35], 7)
    s.add("wait", seconds=4.5)
    return s


def break_intro(s, lang, rng):
    """A page of notes written briskly, then the break corner opened from it."""
    hand = Hand(Font("EMSNeato"), seed=5 if lang == "en" else 6, slant=0.04)
    s.add("note", title=TEXT[lang]["break.title"], paper="lined", seconds=1.0)
    notes_lines(s, lang, hand, rng, speed=4.0, head=False, count=2)
    s.add("wait", seconds=0.8)
    s.add("games", open=True, expanded=False)
    s.add("wait", seconds=1.4)
    s.add("layer", name="creative")
    s.add("wait", seconds=1.2)


def board_touch(s, name, op, strokes, rng, speed=1.0, colour=0, hold=None):
    """Board strokes in parts of the board's shorter side (0.5 = the centre)."""
    if hold is not None:
        out, t = [], 0.0
        for (x, y) in strokes:
            n = max(2, int(hold * RATE))
            out.append([[round(t + k / RATE, 4), round(x, 4), round(y, 4), 1.0] for k in range(n)])
            t += hold + 0.22 + abs(rng.normal(0, 0.05))
        timed_strokes = out
    else:
        scaled = [[(x * 300, y * 300) for x, y in st] for st in strokes]
        ts, _ = timed(scaled, rng, xh=16, speed=speed)
        timed_strokes = [[[a, round(b / 300, 4), round(c / 300, 4), f] for a, b, c, f in st] for st in ts]
    s.add(op, strokes=timed_strokes)
    s.boards.setdefault(name, []).append((colour, [[(p[1], p[2]) for p in st] for st in timed_strokes]))


def scene_ebru(lang):
    rng = np.random.default_rng(41 if lang == "en" else 42)
    s = Script()
    break_intro(s, lang, rng)
    s.add("game", name="ebru")
    s.add("wait", seconds=1.0)
    s.add("games", open=True, expanded=True)
    s.add("wait", seconds=1.2)
    s.add("ebru.tool", name="drop")
    # Drops in a ring of colours; each colour dropped again into the last makes rings.
    for pigment, spots, hold in [
        (0, [(0.50, 0.48), (0.22, 0.30), (0.78, 0.66)], 0.9),
        (2, [(0.50, 0.48), (0.24, 0.31), (0.77, 0.65), (0.30, 0.72)], 0.55),
        (1, [(0.50, 0.48), (0.70, 0.26), (0.30, 0.72)], 0.45),
        (5, [(0.50, 0.48), (0.22, 0.30), (0.78, 0.66), (0.62, 0.86), (0.12, 0.62)], 0.25),
    ]:
        s.add("ebru.pigment", index=pigment)
        s.add("wait", seconds=0.35)
        board_touch(s, "ebru", "ebru.touch", spots, rng, colour=pigment, hold=hold)
    s.add("wait", seconds=0.6)
    s.add("ebru.tool", name="needle")
    s.add("wait", seconds=0.4)
    swirl = [(0.5 + 0.03 * a * math.cos(a), 0.48 + 0.03 * a * math.sin(a)) for a in np.linspace(0.5, 13.5, 120)]
    board_touch(s, "ebru", "ebru.touch", [swirl], rng, speed=0.55, colour=9)
    s.add("wait", seconds=1.2)
    s.add("ebru.pattern", name="bulbul")
    s.add("wait", seconds=7.0)
    return s


def scene_living(lang):
    rng = np.random.default_rng(51 if lang == "en" else 52)
    s = Script()
    break_intro(s, lang, rng)
    s.add("game", name="creatures")
    s.add("wait", seconds=1.0)
    s.add("games", open=True, expanded=True)
    s.add("wait", seconds=1.2)
    s.add("pond.ink", index=0)
    creatures = [(0, fish(0.52, 0.42, 0.42, facing_left=True, rng=rng), False, 3.0),
                 (3, fish(0.42, 0.70, 0.30, facing_left=False, rng=rng), True, 2.6),
                 (2, eel(0.50, 0.22, 0.50, rng=rng), False, 3.0)]
    for k, (ink, drawing, right, wait) in enumerate(creatures):
        # In pond points the drawing keeps its shape (the board is scaled evenly).
        assert faces_right([[(x * 300, y * 300) for x, y in st] for st in drawing]) == right, f"creature {k} faces the wrong way"
        s.add("pond.ink", index=ink)
        board_touch(s, "pond", "pond.touch", drawing, rng, speed=0.8, colour=ink)
        if k < len(creatures) - 1:
            s.add("wait", seconds=wait)
    s.add("wait", seconds=3.2)
    s.add("pond.feed")
    s.add("wait", seconds=5.0)
    return s


def math_font(lining=False):
    """EMS Neato with a straight minus: its hyphen is a wavy dash that a reader could take for "~",
    which no calculation has. `lining` stands every figure on the line, as tall as a capital: the
    font's 3, 4, 5, 7 and 9 hang below it, and the recording of 28 Oct read the second 3 of
    "3 + 3 = 33" as a z."""
    font = Font("EMSNeato")
    adv, _ = font.glyphs["-"]
    font.glyphs["-"] = (adv, [[(70.0, 270.0), (350.0, 280.0)]])
    if lining:
        for digit in "0123456789":
            adv, strokes = font.glyphs[digit]
            ys = [y for st in strokes for _, y in st]
            lo, hi = min(ys), max(ys)
            k = font.cap / (hi - lo)
            font.glyphs[digit] = (adv, [[(x, (y - lo) * k) for x, y in st] for st in strokes])
    return font


def math_page(s, hand, rng, label, lines, xh=19.0, gap_before=()):
    """A page of handwritten math in a blue pen: a one-word label, then one calculation a line, large
    enough to read when the assistant's panel opens beside the page and the page shrinks to fit."""
    s.add("pen", brush="pen", color=NAVY, width=2.4)
    strokes, _ = hand.text(label, MARGIN + 12, 128, 0.8 * xh)
    all_strokes, breaks = list(strokes), []
    y = 200.0
    for k, line in enumerate(lines):
        if k in gap_before:
            y += 18
        line_strokes, end = hand.text(line, MARGIN + 12, y, xh)
        assert end < PAGE[0] - 40, f"{line!r} runs off the page"
        breaks.append(len(all_strokes))
        all_strokes += line_strokes
        y += 62
    timed_strokes, _ = timed(all_strokes, rng, xh=xh, line_breaks=breaks)
    s.write(timed_strokes, "pen", NAVY, 2.4)


def scene_check(lang):
    """A solution whose last step is wrong; the assistant's "Check my solution" names the line."""
    rng = np.random.default_rng(61)
    hand = Hand(math_font(), seed=13, slant=0.04, jitter=0.9)
    s = Script()
    t = TEXT[lang]
    s.add("note", title=t["check.title"], paper="grid", seconds=1.2)
    math_page(s, hand, rng, t["check.label"], t["check.lines"])
    s.add("wait", seconds=1.0)
    s.add("assistant", open=True)
    s.add("wait", seconds=1.2)
    s.add("assistant.ask", name="check")
    s.add("assistant.wait", seconds=4.0)
    return s


def scene_solve(lang):
    """Sums, an equation and a pair of equations; the toolbar's Solve (the panel opens and the page
    is solved), then a sum typed into the chat, which the engine answers without reading the page."""
    rng = np.random.default_rng(62)
    hand = Hand(math_font(lining=True), seed=14, slant=0.04, jitter=0.9)
    s = Script()
    t = TEXT[lang]
    s.add("note", title=t["solve.title"], paper="grid", seconds=1.2)
    math_page(s, hand, rng, t["solve.label"], t["solve.lines"], gap_before=(3,))
    s.add("wait", seconds=1.0)
    s.add("assistant", open=True)
    s.add("wait", seconds=1.0)
    s.add("assistant.ask", name="solve")
    s.add("assistant.wait", seconds=3.5)
    s.add("assistant.type", text=t["solve.chat"], seconds=1.6)
    s.add("assistant.wait", seconds=4.0)
    return s


def scene_convert(lang):
    """Three lines in three 3D inks, then Convert to text (the drafting rail's button): the page is
    written again as neat text on the template's lines, every word in its own ink. The hand is the
    text pen scene's (its lines were read right); the recording of 28 Oct read this hand's F as "f-"."""
    rng = np.random.default_rng(63)
    hand = Hand(Font("EMSNeato"), seed=15, slant=0.04, jitter=0.9)
    s = Script()
    t = TEXT[lang]
    s.add("note", title=t["convert.title"], paper="lined", seconds=1.2)
    inks = [("gold", [0.93, 0.72, 0.25], 6, 30), ("lava", [0.95, 0.35, 0.08], 6, 26),
            ("galaxy", [0.35, 0.25, 0.85], 6, 26)]
    for k, ((brush, colour, width, xh), line) in enumerate(zip(inks, t["convert.lines"])):
        s.add("pen", brush=brush, color=colour, width=width)
        strokes, end = hand.text(line, MARGIN + 14, rule(3 + 3 * k) - 2, xh)
        assert end < PAGE[0] - 40, f"{line!r} runs off the page"
        ts, _ = timed(strokes, rng, xh=xh)
        s.write(ts, brush, colour, width)
        s.add("wait", seconds=0.6)
    s.add("wait", seconds=2.4)
    s.add("convert", page=0)
    s.add("wait", seconds=6.0)
    return s


# MARK: - Second phase: the smart pen, the search, the games and a photographed worksheet

# The kidney of the app's own sticker (StickerArtData.swift, as tests/ports/organs.py has it): the
# hand traces the outline the recognizer compares drawings with.
KIDNEY_PATH = ("M56 10 C76 10 84 30 80 50 C78 72 72 90 54 90 C36 90 26 76 30 64 C36 58 42 56 40 50 "
               "C40 44 34 42 30 36 C24 22 38 10 56 10 Z")


def _cubic_path(path):
    """M/C/Z path data as one polyline, 12 samples a curve (StickerArt.flatten)."""
    tok = re.findall(r"[MCZ]|-?\d+(?:\.\d+)?", path)
    out, cur, start, i = [], (0.0, 0.0), (0.0, 0.0), 0
    while i < len(tok):
        if tok[i] == "M":
            cur = start = (float(tok[i + 1]), float(tok[i + 2]))
            out.append(cur)
            i += 3
        elif tok[i] == "C":
            a, b, p = ((float(tok[i + k]), float(tok[i + k + 1])) for k in (1, 3, 5))
            for k in range(1, 13):
                u = k / 12
                w = ((1 - u) ** 3, 3 * u * (1 - u) ** 2, 3 * u * u * (1 - u), u ** 3)
                out.append((w[0] * cur[0] + w[1] * a[0] + w[2] * b[0] + w[3] * p[0],
                            w[0] * cur[1] + w[1] * a[1] + w[2] * b[1] + w[3] * p[1]))
            cur = p
            i += 7
        else:
            out.append(start)
            cur = start
            i += 1
    return out


def with_hold(stroke, seconds):
    """The stroke with the pencil resting at its end for `seconds` before it lifts."""
    t, x, y, f = stroke[-1]
    return stroke + [[round(t + seconds, 4), x, y, f]]


def scene_shapes(lang):
    """Draw, rest the pencil, and the drawing becomes what it is: a rough kidney is offered as the
    picture (a biology class), then a circle and a triangle snap clean. The rest is the canvas's own
    (Settings: "Fix the shape when you hold"; the recognizers are rule-based, not a language model)."""
    rng = np.random.default_rng(65)
    s = Script()
    t = TEXT[lang]
    s.add("note", title=t["shapes.title"], paper="plain", seconds=1.2)
    s.add("pen", brush="pen", color=NAVY, width=2.8)
    kidney = [(330 + 2.1 * x, 120 + 2.1 * y) for x, y in _cubic_path(KIDNEY_PATH)]
    triangle = [(330, 640), (420, 480), (520, 640), (330, 640)]
    drawings = [("kidney", [_wobble(kidney, 22, rng, 1.0)]),
                ("circle", loop(190, 470, 82, 78, rng, turns=1.03)),
                ("triangle", [_wobble(_densify(triangle, 1.0).tolist(), 16, rng, 1.0)])]
    for name, strokes in drawings:
        ts, _ = timed(strokes, rng, xh=26)
        s.write([with_hold(st, 1.0) for st in ts], "pen", NAVY, 2.8, hold=True)
        s.add("wait", seconds=1.4)
        if name == "kidney":
            # The menu around the drawing offers its pictures; the first is the kidney.
            s.add("suggest.pick", index=0)
            s.add("wait", seconds=1.6)
    s.add("wait", seconds=2.0)
    return s


def rotated(strokes, degrees, pivot):
    """Strokes turned by `degrees` around `pivot` (y down: a positive angle turns clockwise)."""
    a = math.radians(degrees)
    c, sn = math.cos(a), math.sin(a)
    px, py = pivot
    return [[(px + (x - px) * c - (y - py) * sn, py + (x - px) * sn + (y - py) * c) for x, y in st] for st in strokes]


def scene_tilt(lang):
    """The page turned 15 degrees like paper on a desk. The text pen writes level on the screen, so the
    ink lies 15 degrees off the page's lines; the app finds the angle and levels it before reading."""
    rng = np.random.default_rng(64)
    hand = Hand(Font("EMSNeato"), seed=16, slant=0.04, jitter=0.9)
    s = Script()
    t = TEXT[lang]
    s.add("note", title=t["tilt.title"], paper="lined", seconds=1.2)
    s.add("angle", degrees=15)
    s.add("wait", seconds=1.5)
    s.add("textpen", brush="galaxy", color=GALAXY, width=3.6)
    for k, line in enumerate(t["tilt.lines"]):
        x0, base = MARGIN + 30, rule(5 + 3 * k)
        strokes, end = hand.text(line, x0, base, 14)
        assert end < PAGE[0] - 40, f"{line!r} runs off the page"
        # Level on the screen is turned back by the page's angle on the page.
        ts, _ = timed(rotated(strokes, -15, (x0, base)), rng, xh=14)
        s.write(ts, "galaxy", GALAXY, 3.6)
        s.add("wait", seconds=5.0 if k == 0 else 7.0)
    # The angle is a setting the next scenes would inherit (they run in the same app).
    s.add("angle", degrees=0)
    return s


def scene_search(lang):
    """Three notebooks with two lines each, each opened from the library (the one before closes and its
    ink is read), then in the library, once the app has read them all, a word typed into the search
    finds the page it was handwritten on, and the hit opens."""
    rng = np.random.default_rng(66)
    hand = Hand(Font("EMSNeato"), seed=17, slant=0.04, jitter=0.9)
    s = Script()
    t = TEXT[lang]
    for title, lines in t["search.notes"]:
        s.add("note", title=title, paper="lined", seconds=1.0)
        s.add("pen", brush="pen", color=INK, width=2.2)
        all_strokes, breaks = [], []
        for j, line in enumerate(lines):
            strokes, _ = hand.text(line, MARGIN + 12, rule(3 + 2 * j) - 1.5, 13)
            breaks.append(len(all_strokes))
            all_strokes += strokes
        ts, _ = timed(all_strokes, rng, xh=13, speed=2.0, line_breaks=breaks[1:])
        s.write(ts, "pen", INK, 2.2)
        s.add("wait", seconds=0.8)
    s.add("library")
    s.add("ink.read", seconds=90)
    s.add("wait", seconds=1.5)
    s.add("search", text=t["search.query"], seconds=1.6)
    s.add("wait", seconds=3.5)
    s.add("open.hit")
    s.add("wait", seconds=3.0)
    return s


def scene_dots(lang):
    """Kare kapmaca against the iPad (Orta, 4x4). The hand's line is chosen as a careful player would
    (a box to take, else a line that gives none away); the iPad's lines are its own."""
    rng = np.random.default_rng(67)
    s = Script()
    break_intro(s, lang, rng)
    s.add("game", name="dots")
    s.add("wait", seconds=1.0)
    s.add("game.level", name="medium")
    s.add("games", open=True, expanded=True)
    s.add("wait", seconds=1.5)
    for _ in range(24):
        s.add("dots.move")
        s.add("wait", seconds=1.7)
    s.add("wait", seconds=3.0)
    return s


def scene_xox(lang):
    """XOX against the iPad on Zor ("the iPad makes no mistakes"). The hand plays as a careful player
    would (a win, a block, the centre, a corner); the iPad's moves are its own."""
    rng = np.random.default_rng(68)
    s = Script()
    break_intro(s, lang, rng)
    s.add("game", name="xox")
    s.add("wait", seconds=1.0)
    s.add("game.level", name="hard")
    s.add("games", open=True, expanded=True)
    s.add("wait", seconds=1.5)
    for _ in range(6):
        s.add("xox.move")
        s.add("wait", seconds=1.8)
    s.add("wait", seconds=3.0)
    return s


WORKSHEET = [("23 + 9 =", "32"), ("7 + 8 =", "16"), ("45 - 28 =", "17")]


def worksheet_jpeg():
    """The photographed worksheet of ad V10, made here (no one's files): a printed sheet in EMS Tech with
    the answers handwritten in blue, one of them wrong (7 + 8 = 16). Labels and calculations only, so the
    math engine checks it by itself; no printed 1 (EMS Tech's 1 reads as an l)."""
    import io
    from PIL import Image, ImageDraw, ImageFilter
    W, H = 1500, 2000
    rng = np.random.default_rng(71)
    y, x = np.mgrid[0:H, 0:W]
    light = 1.0 - 0.10 * ((x - 0.35 * W) ** 2 + (y - 0.25 * H) ** 2) / (W ** 2 + H ** 2)
    paper = np.stack([246 * light, 243 * light, 234 * light], axis=-1) + rng.normal(0, 1.6, (H, W, 3))
    im = Image.fromarray(np.clip(paper, 0, 255).astype("uint8"), "RGB")
    d = ImageDraw.Draw(im)
    printed = Hand(Font("EMSTech"), seed=3, slant=0.0, jitter=0.15)
    hand = Hand(math_font(lining=True), seed=21, slant=0.05, jitter=0.9)

    def draw(strokes, colour, width):
        for st in strokes:
            if len(st) > 1:
                d.line([(px, py) for px, py in st], fill=colour, width=width, joint="curve")

    gray, blue = (52, 54, 60), (28, 52, 140)
    draw(printed.text("Worksheet 4", 150, 230, 48)[0], gray, 5)
    d.line([(150, 280), (1350, 280)], fill=(120, 122, 128), width=3)
    yy = 470
    for problem, answer in WORKSHEET:
        strokes, end = printed.text(problem, 170, yy, 44)
        draw(strokes, gray, 5)
        draw(hand.text(answer, end + 40, yy + 4, 52, digit_gap=0.22)[0], blue, 6)
        yy += 190
    draw(printed.text("3x + 4 = 25", 170, yy, 44)[0], gray, 5)
    draw(hand.text("x = 7", 200, yy + 170, 52)[0], blue, 6)
    draw(hand.text("Ödev", 1080, 1820, 40)[0], blue, 5)
    im = im.filter(ImageFilter.GaussianBlur(0.6)).rotate(1.2, resample=Image.BICUBIC, fillcolor=(214, 206, 190))
    PREVIEWS.mkdir(exist_ok=True)
    im.save(PREVIEWS / "photo-en-worksheet.png")
    out = io.BytesIO()
    im.save(out, format="JPEG", quality=86)
    return out.getvalue()


def scene_photo(lang):
    """A photographed worksheet becomes a PDF through the app's own photo import (PhotoPDF); the
    assistant's "Check my solution" reads the photo and the math engine marks the wrong answer."""
    s = Script()
    t = TEXT[lang]
    s.add("photos", title=t["photo.title"], image=base64.b64encode(worksheet_jpeg()).decode("ascii"), seconds=1.5)
    s.add("wait", seconds=1.0)
    s.add("assistant", open=True)
    s.add("wait", seconds=1.2)
    s.add("assistant.ask", name="check")
    s.add("assistant.wait", seconds=4.0)
    return s


def stretch(script, k):
    """The scene k times slower: the pen's schedule and the waits; the samples keep their own
    timestamps (`pace`), so the stroke builder sees a hand at its real speed."""
    for st in script.steps:
        if "seconds" in st:
            st["seconds"] = round(st["seconds"] * k, 3)
        if st["op"] == "write":
            st["pace"] = k
            st["strokes"] = [[[round(p[0] * k, 4), p[1], p[2], p[3]] for p in s] for s in st["strokes"]]
    script.launch = ["-textPenDelay", f"{1.3 * k:.2f}", "-dryDuration", f"{4.0 * k:.2f}",
                     "-lavaCoolDuration", f"{6.0 * k:.2f}"]


SCENE_MAKERS = {"notes": scene_notes, "textpen": scene_textpen, "inks": scene_inks,
                "ebru": scene_ebru, "living": scene_living,
                "check": scene_check, "solve": scene_solve, "convert": scene_convert,
                "shapes": scene_shapes, "photo": scene_photo, "search": scene_search, "dots": scene_dots,
                "tilt": scene_tilt, "xox": scene_xox}


# MARK: - Previews

def preview(name, script):
    from PIL import Image, ImageDraw
    S = 2
    im = Image.new("RGB", (int(PAGE[0] * S), int(PAGE[1] * S)), (252, 251, 247))
    d = ImageDraw.Draw(im)
    lined = any(st.get("paper") == "lined" for st in script.steps if st["op"] == "note")
    if lined:
        y = RULE_TOP
        while y < PAGE[1] - 8:
            d.line([(0, y * S), (PAGE[0] * S, y * S)], fill=(168, 204, 242), width=1)
            y += RULE_STEP
        d.line([(MARGIN * S, 0), (MARGIN * S, PAGE[1] * S)], fill=(240, 160, 160), width=1)
    for brush, colour, width, strokes in script.page_strokes:
        c = tuple(int(255 * v) for v in colour[:3])
        w = max(1, int(width * S * (0.5 if brush in ("lava", "gold", "galaxy", "sea", "wave", "bloom") else 0.55)))
        if brush == "highlighter":
            c = (255, 232, 120)
            w = int(width * S * 0.8)
        for st in strokes:
            if len(st) > 1:
                d.line([(x * S, y * S) for x, y in st], fill=c, width=w, joint="curve")
    PREVIEWS.mkdir(exist_ok=True)
    im.save(PREVIEWS / f"{name}.png")
    for board, items in script.boards.items():
        B = 600
        bim = Image.new("RGB", (B, B), (230, 224, 210) if board == "ebru" else (226, 240, 246))
        bd = ImageDraw.Draw(bim)
        palette = [(43, 63, 126), (168, 50, 45), (227, 178, 60), (63, 125, 78), (138, 90, 59), (245, 241, 230), (0, 0, 0),
                   (0, 0, 0), (0, 0, 0), (60, 60, 60)]
        for colour, strokes in items:
            for st in strokes:
                pts = [(x * B, y * B) for x, y in st]
                if len(set(pts)) == 1:
                    x, y = pts[0]
                    r = 6 + 10 * min(1, len(pts) / RATE)
                    bd.ellipse([x - r, y - r, x + r, y + r], fill=palette[colour % len(palette)])
                else:
                    bd.line(pts, fill=palette[colour % len(palette)], width=3)
        bim.save(PREVIEWS / f"{name}-{board}.png")


def main():
    SCENES.mkdir(exist_ok=True)
    for old in SCENES.glob("DemoScene-*.json"):
        old.unlink()
    total = 0.0
    for lang in LANGS:
        for key, make in SCENE_MAKERS.items():
            script = make(lang)
            pace = PACE.get(key, 1.0)
            preview(f"{key}-{lang}", script)
            if pace != 1.0:
                stretch(script, pace)
            name = f"{key}-{lang}"
            (SCENES / f"DemoScene-{name}.json").write_text(
                json.dumps({"pace": pace, "clock": pace if key in CLOCKED else 1.0, "launch": script.launch,
                            "steps": script.steps},
                           ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
            seconds = sum(st.get("seconds", 0) for st in script.steps) + sum(
                max((s[-1][0] for s in st["strokes"]), default=0) for st in script.steps if "strokes" in st)
            total += seconds
            print(f"{name}: {len(script.steps)} steps, about {seconds:.0f} s filmed (pace {pace})")
    # The warm-up: every ink once, so the first recorded scene does not wait for shaders.
    warm = Script()
    warm.add("note", title="Warm-up", paper="plain", seconds=0.8)
    rng = np.random.default_rng(3)
    for k, brush in enumerate(["fountain", "pen", "highlighter", "lava", "gold", "wave", "galaxy", "sea", "bloom"]):
        warm.add("pen", brush=brush, color=[0.2, 0.3, 0.6], width=6)
        ts, _ = timed([[(60 + 50 * k, 100), (90 + 50 * k, 140)]], rng, xh=20, speed=3)
        warm.write(ts, brush, [0.2, 0.3, 0.6], 6)
    warm.add("wait", seconds=1.5)
    (SCENES / "DemoScene-warmup.json").write_text(json.dumps({"pace": 1.0, "launch": [], "steps": warm.steps},
                                                             separators=(",", ":")), encoding="utf-8")
    print(f"all scenes: about {total / 60:.1f} min")


if __name__ == "__main__":
    main()
