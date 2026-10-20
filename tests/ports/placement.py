"""Port of TextPlacement (Murekkep.swiftpm/TextPlacement.swift): where the typed words of a converted
line go. A ruling is (top, spacing, left, right, cap); obstacles are (min_x, min_y, max_x, max_y) of
the page's other ink.

The words start on their line where the hand started, unless ink on that line begins left of there
and ends at most 3 capital heights before it: then the hand meant to go on, and the words follow it
after one space (punctuation: a hairline). A word that would overlap ink moves past it; past the right
margin it wraps to the next line's left margin and is checked again. Words never go above the line
they were written on."""

JOIN_REACH = 3.0  # capital heights
BAND_UP = 1.25
BAND_DOWN = 0.35


def _on_line(o, k, ruling):
    top, spacing, _, _, cap = ruling
    b = top + spacing * k
    return min(o[3], b + BAND_DOWN * cap) > max(o[1], b - BAND_UP * cap)


def obstacles(rects, ruling):
    """The page's ink that typed words keep clear of: not long flat lines (underlines, rules) and
    not drawings taller than two lines (a frame around the writing)."""
    _, spacing, _, _, cap = ruling
    return [o for o in rects
            if not (o[2] - o[0] > 4 * cap and o[3] - o[1] < 0.4 * cap) and o[3] - o[1] <= 2 * spacing]


def place(widths, start_x, start_line, ruling, space, join_gap, obstacles):
    """[(x, line)] for each word."""
    _, _, left, right, cap = ruling
    k = start_line
    x = min(max(start_x, left), right - 20)
    before = [o[2] for o in obstacles
              if _on_line(o, k, ruling) and o[0] < start_x and o[2] >= start_x - JOIN_REACH * cap]
    if before:
        x = max(before) + join_gap
    out = []
    for w in widths:
        for _ in range(64):
            if x + w > right and x > left + 1:
                k += 1
                x = left
            hits = [o for o in obstacles if _on_line(o, k, ruling) and min(o[2], x + w) > max(o[0], x)]
            if not hits:
                break
            x = max(o[2] for o in hits) + space
        out.append((x, k))
        x += w + space
    return out
