"""Port of InkLine.lines and InkLine.splitRaised (Murekkep.swiftpm/InkLine.swift): which strokes form
a line of writing, where dots and accents belong, and which small raised strokes are exponents.
Strokes are lists of (x, y) page points, y down.

Letter-size strokes (at least 0.6 × the median stroke height) build the lines, each joining the line
whose band it overlaps by 40 % of the smaller height; the band follows the line's slope once it has
three letters. Every smaller stroke (dots, accents, commas, exponents, a plus sign's bars) then joins
the line whose band is nearest, preferring lines it lies beside."""
import statistics

PRIMARY = 0.6
JOIN = 0.4
RAISED_BOTTOM = 0.3
RAISED_MIN = 0.25
OVER_LETTER = 0.1
GROUP_GAP = 0.5
RECENT = 12
MAX_SLOPE = 0.2126  # tan 12°


class Box:
    def __init__(self, pts):
        xs = [p[0] for p in pts]
        ys = [p[1] for p in pts]
        self.min_x, self.max_x, self.min_y, self.max_y = min(xs), max(xs), min(ys), max(ys)
        self.h = self.max_y - self.min_y
        self.w = self.max_x - self.min_x
        self.cx = (self.min_x + self.max_x) / 2
        self.cy = (self.min_y + self.max_y) / 2


def _letter_height(boxes):
    hs = sorted(b.h for b in boxes if b.h >= 3)
    return statistics.median(hs) if hs else max([b.h for b in boxes] + [1.0])


class _Line:
    def __init__(self):
        self.members = []

    def band(self, boxes, x):
        """(top, bottom) of the line's letters at x. The slope is the median of the slopes between
        the last 12 letters (a capital or a descender among them cannot tilt it), at most 12°."""
        ms = [boxes[i] for i in self.members]
        if len(ms) < 3:
            return min(b.min_y for b in ms), max(b.max_y for b in ms)
        core = statistics.median(b.h for b in ms)
        recent = ms[-RECENT:]
        slopes = [(b.cy - a.cy) / (b.cx - a.cx) for i, a in enumerate(recent) for b in recent[i + 1:]
                  if abs(b.cx - a.cx) > 1e-6]
        a = statistics.median(slopes) if slopes else 0.0
        a = max(-MAX_SLOPE, min(MAX_SLOPE, a))
        yc = statistics.median(b.cy - a * b.cx for b in recent) + a * x
        return yc - core / 2, yc + core / 2


def _overlap(lo1, hi1, lo2, hi2):
    return max(0.0, min(hi1, hi2) - max(lo1, lo2))


def lines(strokes):
    """Lists of stroke indices, one per line, top to bottom."""
    if not strokes:
        return []
    boxes = [Box(s) for s in strokes]
    letter = _letter_height(boxes)
    primary = sorted((i for i, b in enumerate(boxes) if b.h >= PRIMARY * letter), key=lambda i: boxes[i].min_x)
    if not primary:
        return [list(range(len(strokes)))]
    found = []
    for i in primary:
        b = boxes[i]
        best, best_ratio = None, 0.0
        for line in found:
            top, bottom = line.band(boxes, b.cx)
            ratio = _overlap(b.min_y, b.max_y, top, bottom) / max(min(b.h, bottom - top), 1e-6)
            if ratio > best_ratio:
                best, best_ratio = line, ratio
        if best is None or best_ratio < JOIN:
            best = _Line()
            found.append(best)
        best.members.append(i)
    taken = set(primary)
    for i, b in enumerate(boxes):
        if i in taken:
            continue
        best, best_key = None, None
        for line in found:
            top, bottom = line.band(boxes, b.cx)
            gap = 0.0 if top <= b.cy <= bottom else min(abs(b.cy - top), abs(b.cy - bottom))
            ms = [boxes[j] for j in line.members]
            reach = 2 * (bottom - top)
            beside = min(m.min_x for m in ms) - reach <= b.cx <= max(m.max_x for m in ms) + reach
            key = (0 if beside else 1, gap)
            if best_key is None or key < best_key:
                best, best_key = line, key
        best.members.append(i)
    found.sort(key=lambda ln: statistics.mean(boxes[i].cy for i in ln.members))
    return [sorted(ln.members) for ln in found]


def split_raised(strokes, line):
    """(base indices, [(group indices, group min x)]) — exponents written small and high after a letter."""
    boxes = {i: Box(strokes[i]) for i in line}
    letter = _letter_height(list(boxes.values()))
    primary = [i for i in line if boxes[i].h >= PRIMARY * letter]
    if not primary:
        return list(line), []
    core = _Line()
    core.members = primary
    core_h = statistics.median(boxes[i].h for i in primary)
    first_x = min(boxes[i].min_x for i in primary)
    raised = []
    for i in line:
        if i in primary:
            continue
        b = boxes[i]
        top, _ = core.band(boxes, b.cx)
        over_letter = any(boxes[j].min_x - OVER_LETTER * core_h <= b.cx <= boxes[j].max_x + OVER_LETTER * core_h
                          for j in primary)
        if (b.max_y < top + RAISED_BOTTOM * core_h and b.h >= RAISED_MIN * core_h
                and not over_letter and b.min_x > first_x):
            raised.append(i)
    raised.sort(key=lambda i: boxes[i].min_x)
    groups = []
    for i in raised:
        if groups and boxes[i].min_x - max(boxes[j].max_x for j in groups[-1]) < GROUP_GAP * core_h:
            groups[-1].append(i)
        else:
            groups.append([i])
    base = [i for i in line if i not in raised]
    return base, [(g, min(boxes[j].min_x for j in g)) for g in groups]
