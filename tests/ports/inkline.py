"""Port of InkLine.lines and InkLine.splitRaised (Murekkep.swiftpm/InkLine.swift): which strokes form
a line of writing, where dots and accents belong, and which small raised strokes are exponents.
Strokes are lists of (x, y) page points, y down.

Letter-size strokes (at least 0.6 × the median stroke height) build the lines, each joining the line
whose band it overlaps by 40 % of the smaller height; the band follows the line's slope once it has
six letters. A letter-size stroke wholly above or below the band (a y's tail or an ascender drawn on
its own) joins a line it stands beside when 75 % of it lies within 1.2 band heights of the band,
the line whose band is nearest when two qualify. Lines split while the writing was read left to right
(a first letter drawn in pieces gives a band of half a letter) are joined again: a smaller line whose
middle lies within 0.75 band heights of a bigger one's, or whose letters lie in its reach (a few
strokes narrower than 2.5 band heights: in its reach widened to 1.6, for long tails, or within the
line's own ascenders and descenders). Every smaller stroke (dots, accents, commas, exponents, a plus sign's bars) then joins
the line whose band is nearest, preferring lines it lies beside."""
import statistics

PRIMARY = 0.6
JOIN = 0.4
RAISED_BOTTOM = 0.3
RAISED_MIN = 0.25
OVER_LETTER = 0.1
GROUP_GAP = 0.5
RECENT = 12
FIT = 6  # letters a line needs before its slope is fitted
MAX_SLOPE = 0.0875  # tan 5°: the text pen levels the ink before it looks for lines
REACH = 1.2  # ascenders and descenders reach this many band heights above and below the band
INSIDE = 0.75  # share of a stroke's height inside that reach for it to belong to the line
MERGE = 0.75  # lines whose middles are closer than this many band heights are one line
FRAGMENT = 3  # a "line" of at most this many strokes, narrower than FRAGMENT_WIDTH band heights,
FRAGMENT_WIDTH = 2.5  # is a part of a letter when it lies within FRAGMENT_REACH band heights
FRAGMENT_REACH = 1.6


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
        the last 12 letters (a capital or a descender among them cannot tilt it), at most 5° (the text pen
        levels the ink first); a line
        of fewer than 6 letters is level ("Bug" alone would point the band below the next letter)."""
        ms = [boxes[i] for i in self.members]
        if len(ms) < 3:
            return min(b.min_y for b in ms), max(b.max_y for b in ms)
        core = statistics.median(b.h for b in ms)
        recent = ms[-RECENT:]
        a = 0.0
        if len(recent) >= FIT:
            slopes = [(b.cy - p.cy) / (b.cx - p.cx) for i, p in enumerate(recent) for b in recent[i + 1:]
                      if abs(b.cx - p.cx) > 1e-6]
            a = statistics.median(slopes) if slopes else 0.0
            a = max(-MAX_SLOPE, min(MAX_SLOPE, a))
        yc = statistics.median(b.cy - a * b.cx for b in recent) + a * x
        return yc - core / 2, yc + core / 2


def _overlap(lo1, hi1, lo2, hi2):
    return max(0.0, min(hi1, hi2) - max(lo1, lo2))


def _reach(found, boxes, b):
    """The line a stroke above or below every band belongs to: one it stands beside (not past the
    line's right end by more than two band heights) with 75 % of the stroke within the ascender and
    descender reach of its band; the line whose band is nearest wins."""
    best, best_gap = None, None
    for line in found:
        top, bottom = line.band(boxes, b.cx)
        core = bottom - top
        if len(line.members) < 3:
            # A line of one or two strokes has their whole height as its band already.
            core = statistics.median(boxes[j].h for j in line.members) * 0.5
        inside = _overlap(b.min_y, b.max_y, top - REACH * core, bottom + REACH * core) / max(b.h, 1e-6)
        right = max(boxes[j].max_x for j in line.members)
        if inside < INSIDE or b.min_x > right + 2 * (bottom - top):
            continue
        gap = 0.0 if b.max_y >= top and b.min_y <= bottom else min(abs(b.min_y - bottom), abs(top - b.max_y))
        if best_gap is None or gap < best_gap:
            best, best_gap = line, gap
    return best


def _same_line(small, big, boxes):
    """Whether `small` is part of the line `big` (see the module's description)."""
    ms = [boxes[i] for i in small.members]
    cx = statistics.median(m.cx for m in ms)
    top, bottom = big.band(boxes, cx)
    core = bottom - top
    if len(big.members) < 3:
        core = statistics.median(boxes[j].h for j in big.members) * 0.5
    height = max(bottom - top, statistics.median(m.h for m in ms))
    if abs(statistics.median(m.cy for m in ms) - (top + bottom) / 2) < MERGE * height:
        return True
    left = min(boxes[j].min_x for j in big.members) - 2 * (bottom - top)
    right = max(boxes[j].max_x for j in big.members) + 2 * (bottom - top)
    width = max(m.max_x for m in ms) - min(m.min_x for m in ms)
    fragment = len(ms) <= FRAGMENT and width < FRAGMENT_WIDTH * (bottom - top)
    reach = FRAGMENT_REACH if fragment else REACH
    # A fragment may also lie anywhere within the line's own ascenders and descenders (letters that
    # come in pieces make the band lower than the letters).
    high = min(boxes[j].min_y for j in big.members) - 0.3 * (bottom - top)
    low = max(boxes[j].max_y for j in big.members) + 0.3 * (bottom - top)
    inside = 0
    for m in ms:
        t, b = big.band(boxes, m.cx)
        share = _overlap(m.min_y, m.max_y, t - reach * core, b + reach * core) / max(m.h, 1e-6)
        if fragment:
            share = max(share, _overlap(m.min_y, m.max_y, high, low) / max(m.h, 1e-6))
        inside += share >= INSIDE and left <= m.cx <= right
    return inside >= INSIDE * len(ms)


def _merge(found, boxes):
    """The lines with every split line joined to the line it is part of, smallest first."""
    while len(found) > 1:
        pair = None
        for small in sorted(found, key=lambda ln: len(ln.members)):
            for big in sorted(found, key=lambda ln: -len(ln.members)):
                if big is not small and len(big.members) >= len(small.members) and _same_line(small, big, boxes):
                    pair = (small, big)
                    break
            if pair:
                break
        if pair is None:
            break
        small, big = pair
        big.members = sorted(big.members + small.members, key=lambda i: (boxes[i].min_x, i))
        found.remove(small)
    return found


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
            best = _reach(found, boxes, b)
        if best is None:
            best = _Line()
            found.append(best)
        best.members.append(i)
    found = _merge(found, boxes)
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
