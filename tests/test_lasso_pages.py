import math

from ports.lasso import A4, DASH, dash_ticks, drop_page, layout, rebase


def test_selection_dropped_on_next_page_moves_there():
    rects = layout([A4, A4, A4])
    # Dragged down past the bottom of page 0: its center is now 100 pt into page 1.
    below = A4[1] + 22 + 100 - 40
    assert drop_page(rects, 0, (200, below, 80, 80)) == 1


def test_selection_dropped_on_previous_page_moves_there():
    rects = layout([A4, A4, A4])
    assert drop_page(rects, 2, (100, -300, 60, 60)) == 1


def test_selection_staying_on_its_page_or_in_the_gap_stays():
    rects = layout([A4, A4])
    assert drop_page(rects, 0, (100, 100, 50, 50)) is None
    # Center in the gap between the pages: nowhere to move to.
    assert drop_page(rects, 0, (100, A4[1] + 11 - 2, 4, 4)) is None


def test_rebase_keeps_the_point_in_place_on_the_document():
    rects = layout([A4, (420.0, 595.0), A4])
    p = (50.0, 900.0)
    q = rebase(p, 0, 1, rects)
    doc_p = (rects[0][0] + p[0], rects[0][1] + p[1])
    doc_q = (rects[1][0] + q[0], rects[1][1] + q[1])
    assert math.isclose(doc_p[0], doc_q[0]) and math.isclose(doc_p[1], doc_q[1])
    assert rebase(q, 1, 0, rects) == p


def test_pencil_ticks_once_per_dash_period_on_screen():
    period = sum(DASH)
    # A 200 pt straight lasso at zoom 1 sampled every 2 pt: one tick per 10 pt.
    pts = [(x * 2.0, 0.0) for x in range(101)]
    assert len(dash_ticks(pts, 1.0)) == int(200 / period)
    # Zoomed in 2x the same document length is twice as long on screen.
    assert len(dash_ticks(pts, 2.0)) == int(400 / period)


def test_no_tick_before_the_first_dash_ends():
    pts = [(0.0, 0.0), (3.0, 0.0), (6.0, 4.0)]
    assert dash_ticks(pts, 1.0) == []
