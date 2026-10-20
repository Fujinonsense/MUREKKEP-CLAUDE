"""Port of page navigation: the number typed in "Sayfaya git" (PageNavigator), single-page snapping
and pulling past the end of a notebook (CanvasView.scrollViewWillEndDragging)."""

GAP = 22.0
PULL_TO_ADD = 90.0
FLICK = 0.3


def page_index(text, count):
    """0-based page for the typed page number; None when it is not a number."""
    try:
        n = int(text.strip())
    except ValueError:
        return None
    return min(max(n, 1), count) - 1


def single_page_target(rects, start_page, center_y, velocity):
    """Page to settle on after a drag in single-page mode: a flick goes one page on, a slow drag
    settles on the page nearest the middle of the screen. `center_y` is in document space."""
    last = len(rects) - 1
    if velocity > FLICK:
        return min(start_page + 1, last)
    if velocity < -FLICK:
        return max(start_page - 1, 0)
    return min(range(len(rects)), key=lambda i: abs(rects[i][1] + rects[i][3] / 2 - center_y))


def single_page_offset(rect, zoom, view_h):
    """Content offset y that shows `rect` (x, y, w, h) in the middle of the screen."""
    return (rect[1] + rect[3] / 2) * zoom - view_h / 2


def pull_action(overscroll, last_page_has_ink):
    """What pulling `overscroll` view points past the end of a notebook does on release."""
    if overscroll <= PULL_TO_ADD:
        return None
    return "add" if last_page_has_ink else "show_last"
