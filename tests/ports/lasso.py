"""Port of the lasso's page logic: DocumentLayout, the page a dropped selection lands on, and the
dash ticks the pencil plays while the loop is drawn (EditorModel.endSelectionEdit,
CanvasView.lassoMoved)."""
import math

MARGIN = 28.0
GAP = 22.0
A4 = (595.0, 842.0)

# CanvasOverlay draws the lasso with setLineDash(lengths: [6, 4]) in view points.
DASH = (6.0, 4.0)


def layout(sizes):
    """DocumentLayout.pageRects as (x, y, w, h)."""
    max_w = max(w for w, _ in sizes)
    y = MARGIN
    rects = []
    for w, h in sizes:
        rects.append((MARGIN + (max_w - w) / 2, y, w, h))
        y += h + GAP
    return rects


def page_containing(rects, p, tol=0.0):
    for i, (x, y, w, h) in enumerate(rects):
        if x - tol <= p[0] <= x + w + tol and y - tol <= p[1] <= y + h + tol:
            return i
    return None


def drop_page(rects, page, bounds):
    """The page a moved selection belongs to once dropped; None when it stays where it is.
    `bounds` is page-local (x, y, w, h)."""
    ox, oy = rects[page][0], rects[page][1]
    center = (ox + bounds[0] + bounds[2] / 2, oy + bounds[1] + bounds[3] / 2)
    target = page_containing(rects, center)
    return target if target is not None and target != page else None


def rebase(p, page_from, page_to, rects):
    """A page-local point of `page_from` in the page-local space of `page_to`."""
    dx = rects[page_from][0] - rects[page_to][0]
    dy = rects[page_from][1] - rects[page_to][1]
    return (p[0] + dx, p[1] + dy)


def dash_ticks(points, zoom):
    """Indices of the lasso points (document space) at which the pencil ticks."""
    period = sum(DASH)
    ticks = []
    length = 0.0
    for i in range(1, len(points)):
        before = int(length // period)
        length += math.hypot(points[i][0] - points[i - 1][0], points[i][1] - points[i - 1][1]) * zoom
        if int(length // period) > before:
            ticks.append(i)
    return ticks
