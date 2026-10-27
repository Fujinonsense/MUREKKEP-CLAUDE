"""Port of page navigation: the number typed in "Sayfaya git" (PageNavigator), single-page snapping
(CanvasView.scrollViewWillEndDragging) and the blank page every notebook ends in
(EditorModel.keepBlankPageAtEnd, its in-memory twin in EditorModel.init, exportPDF)."""

GAP = 22.0
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


def keep_blank_page_at_end(used, is_pdf=False):
    """The pages after an edit, one bool per page (ink or a picture on it): a notebook whose last page
    is used gets a blank page after it. Pages are only added, never taken away."""
    if is_pdf or not used or not used[-1]:
        return list(used)
    return list(used) + [False]


def pages_on_open(used, is_pdf=False, read_only=False):
    """The pages an opened note shows: the same blank page, unless the note opened read-only."""
    return list(used) if read_only else keep_blank_page_at_end(used, is_pdf)


def shared_page_count(used, is_pdf=False):
    """Pages in the shared PDF: a notebook's blank pages at the end stay out (at least one page)."""
    if is_pdf:
        return len(used)
    return max((i for i, u in enumerate(used) if u), default=0) + 1
