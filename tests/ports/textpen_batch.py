"""Twin of TextPenBatch.swift: whether new text-pen writing goes on the line the pen has just turned
into text, so the line is read again as a whole. Words read one at a time lose their context ("Aga"
alone reads "Asa") and the spaces between them.

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
