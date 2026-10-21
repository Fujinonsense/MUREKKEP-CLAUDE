"""Port of ReadingOrder (Murekkep.swiftpm/ReadingOrder.swift): the lines of a scanned page in reading
order, from the boxes text recognition found (pixels, top-left origin).

Columns are found where few boxes cross a vertical band that has at least a fifth of the boxes on
each side; boxes that cross it (a title, a full-width letter) break the page into sections, and each
section is read column by column. Boxes of one row inside a column are joined left to right; a
blank (a printed answer line) between them, or between words, becomes "___"."""
import re
from bisect import bisect_left
from dataclasses import dataclass, field
from statistics import median

GAP = 1.2            # pieces or words farther apart than this many line heights have a blank between them
GUTTER_MIN = 0.6     # a column gap is at least this many line heights wide
SIDE_SHARE = 0.2     # each side of a column gap holds at least this share of the boxes
CROSS_SHARE = 0.2    # at most this share of the boxes cross a column gap
COLUMN_WIDTH = 4     # a column's typical box is at least this many line heights wide
ROW_OVERLAP = 0.5    # boxes of one row overlap vertically by half the smaller height
MAX_DEPTH = 2        # up to four columns


@dataclass
class Piece:
    text: str
    box: tuple                                   # x, y, w, h
    words: list = field(default_factory=list)    # [(text, (x, y, w, h))]

    @property
    def left(self):
        return self.box[0]

    @property
    def right(self):
        return self.box[0] + self.box[2]

    @property
    def top(self):
        return self.box[1]

    @property
    def bottom(self):
        return self.box[1] + self.box[3]

    @property
    def cx(self):
        return self.box[0] + self.box[2] / 2

    @property
    def cy(self):
        return self.box[1] + self.box[3] / 2


def normalize_blanks(s):
    """Printed blanks (underscores, dot leaders) as one "___"."""
    s = re.sub(r"_+", " ___ ", s)
    s = re.sub(r"\.{5,}|…{2,}", " ___ ", s)
    s = re.sub(r"\s+", " ", s).strip()
    return re.sub(r"___(?: ___)+", "___", s)


def _gutter(pieces, h):
    """(start, end) of the widest band few boxes cross, with enough boxes on both sides."""
    n = len(pieces)
    if n < 6:
        return None
    lo = min(p.left for p in pieces)
    hi = max(p.right for p in pieces)
    step = max(h / 8, 1)
    xs = []
    x = lo + step
    while x < hi:
        xs.append(x)
        x += step
    cross, inner = [], []
    for x in xs:
        cross.append(sum(1 for p in pieces if p.left < x < p.right))
        left = sum(1 for p in pieces if p.right <= x)
        right = sum(1 for p in pieces if p.left >= x)
        inner.append(left >= SIDE_SHARE * n and right >= SIDE_SHARE * n)
    if not any(inner):
        return None
    least = min(c for c, ok in zip(cross, inner) if ok)
    if least > CROSS_SHARE * n:
        return None
    limit = least + max(1, round(0.03 * n))
    best, start = None, None
    for i in range(len(xs) + 1):
        ok = i < len(xs) and inner[i] and cross[i] <= limit
        if ok and start is None:
            start = i
        elif not ok and start is not None:
            if best is None or i - start > best[1] - best[0]:
                best = (start, i)
            start = None
    if best is None:
        return None
    a, b = xs[best[0]], xs[best[1] - 1]
    if b - a < GUTTER_MIN * h:
        return None
    mid = (a + b) / 2
    sides = ([p for p in pieces if not _crosses(p, (a, b)) and p.cx < mid],
             [p for p in pieces if not _crosses(p, (a, b)) and p.cx >= mid])
    if any(not side or median(p.box[2] for p in side) < COLUMN_WIDTH * h for side in sides):
        return None
    return a, b


def _crosses(p, gutter):
    a, b = gutter
    return min(p.right, b) - max(p.left, a) >= (b - a) / 2


def _gutters(pieces, h, depth=0):
    g = _gutter(pieces, h)
    if g is None:
        return []
    if depth + 1 >= MAX_DEPTH:
        return [g]
    mid = (g[0] + g[1]) / 2
    rest = [p for p in pieces if not _crosses(p, g)]
    left = [p for p in rest if p.cx < mid]
    right = [p for p in rest if p.cx >= mid]
    return _gutters(left, h, depth + 1) + [g] + _gutters(right, h, depth + 1)


def _rows(pieces):
    """Pieces of one row together, rows top to bottom, each row left to right."""
    rows = []
    for p in sorted(pieces, key=lambda p: (p.cy, p.left, p.text)):
        for r in reversed(rows[-3:]):
            anchor = r[0]
            overlap = min(anchor.bottom, p.bottom) - max(anchor.top, p.top)
            if overlap < ROW_OVERLAP * min(anchor.box[3], p.box[3]):
                continue
            if any(min(q.right, p.right) - max(q.left, p.left) > 0.5 * min(q.box[2], p.box[2]) for q in r):
                continue
            r.append(p)
            break
        else:
            rows.append([p])
    rows = [sorted(r, key=lambda p: (p.left, p.text)) for r in rows]
    return sorted(rows, key=lambda r: (sum(p.cy for p in r) / len(r), r[0].left))


def _text(p):
    if len(p.words) < 2:
        return p.text.strip()
    out = p.words[0][0]
    for (_, (x0, _, w0, _)), (t, (x1, _, _, _)) in zip(p.words, p.words[1:]):
        out += (" ___ " if x1 - (x0 + w0) > GAP * p.box[3] else " ") + t
    return out


def _join(row, h):
    out = ""
    right = None
    for p in row:
        if right is not None:
            out += " ___ " if p.left - right > GAP * h else " "
        out += _text(p)
        right = p.right
    return normalize_blanks(out)


def lines(pieces):
    pieces = [p for p in pieces if p.text.strip() and p.box[2] > 0 and p.box[3] > 0]
    if not pieces:
        return []
    h = median(p.box[3] for p in pieces)
    gutters = _gutters(pieces, h)
    spanning = [p for p in pieces if any(_crosses(p, g) for g in gutters)]
    columns = [p for p in pieces if not any(_crosses(p, g) for g in gutters)]
    span_rows = _rows(spanning)
    edges = [sum(p.cy for p in r) / len(r) for r in span_rows]
    mids = [(a + b) / 2 for a, b in gutters]
    out = []
    for k in range(len(span_rows) + 1):
        section = [p for p in columns if bisect_left(edges, p.cy) == k]
        for c in range(len(gutters) + 1):
            mine = [p for p in section if sum(1 for m in mids if p.cx >= m) == c]
            out += [_join(r, h) for r in _rows(mine)]
        if k < len(span_rows):
            out.append(_join(span_rows[k], h))
    return [t for t in out if t]
