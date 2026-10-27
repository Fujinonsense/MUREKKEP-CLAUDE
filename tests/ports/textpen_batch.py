"""Twin of TextPenBatch.swift: whether new text-pen writing goes on the line the pen has just turned
into text, so the line is read again as a whole. Words read one at a time lose their context ("Aga"
alone reads "Asa") and the spaces between them. The new writing was written after the typed words, so
it is moved to where it falls in the old handwriting (hand_x) before the line is read again.

Boxes are (min_x, min_y, max_x, max_y) in page points, y down."""
WINDOW = 15.0   # seconds after the last reading
REACH = 4.0     # how far right the next words may start, in the last writing's heights


def continues(last, nxt, elapsed):
    if elapsed < 0 or elapsed >= WINDOW:
        return False
    h = max(last[3] - last[1], 1.0)
    w, nh = nxt[2] - nxt[0], nxt[3] - nxt[1]
    cx, cy = (nxt[0] + nxt[2]) / 2, (nxt[1] + nxt[3]) / 2
    if max(w, nh) < 0.5 * h:
        # A dot, an accent, a comma or a full stop: over the line or just after it.
        return last[1] - 0.6 * h <= cy <= last[3] + 0.3 * h and last[0] - 0.2 * h <= cx <= last[2] + REACH * h
    if abs(cy - (last[1] + last[3]) / 2) > 0.5 * h:
        return False
    return last[0] - 0.5 * h <= nxt[0] <= last[2] + REACH * h


def hand_x(x, anchors):
    """Where x, written along the typed text, falls in the handwriting that text replaced. anchors:
    (typed_min, typed_max, hand_min, hand_max) per typed word, left to right. Linear between the
    anchors; past the ends it keeps its distance."""
    if not anchors:
        return x
    first, last = anchors[0], anchors[-1]
    if x <= first[0]:
        return first[2] + (x - first[0])
    if x >= last[1]:
        return last[3] + (x - last[1])
    points = []
    for a in anchors:
        points += [(a[0], a[2]), (a[1], a[3])]
    for (ta, ha), (tb, hb) in zip(points, points[1:]):
        if ta <= x <= tb:
            if tb <= ta:
                return ha
            return ha + (x - ta) * (hb - ha) / (tb - ta)
    return x


def anchors(typed, hand):
    """typed, hand: (min_x, max_x) per word, left to right. One anchor for the whole line when the
    handwriting words do not go left to right (one box per line)."""
    if not typed or len(typed) != len(hand):
        return []
    ordered = all(b[0] >= a[1] - 0.5 for a, b in zip(hand, hand[1:])) and all(h[1] > h[0] for h in hand)
    if not ordered:
        return [(typed[0][0], typed[-1][1], hand[0][0], max(max(h[1] for h in hand), hand[0][0] + 1))]
    return [(t[0], t[1], h[0], h[1]) for t, h in zip(typed, hand)]
