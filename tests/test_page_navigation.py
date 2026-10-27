from ports.lasso import A4, layout
from ports.navigation import page_index, single_page_offset, single_page_target


def test_typed_page_number_goes_to_that_page():
    assert page_index("12", 300) == 11
    assert page_index(" 1 ", 300) == 0


def test_typed_page_number_past_the_end_goes_to_the_last_page():
    assert page_index("500", 300) == 299
    assert page_index("0", 300) == 0


def test_typed_text_that_is_not_a_number_goes_nowhere():
    assert page_index("", 300) is None
    assert page_index("abc", 300) is None


def test_single_page_flick_goes_one_page_on_or_back():
    rects = layout([A4] * 5)
    mid = rects[2][1] + rects[2][3] / 2
    assert single_page_target(rects, 2, mid, 1.2) == 3
    assert single_page_target(rects, 2, mid, -1.2) == 1
    # Not past the ends.
    assert single_page_target(rects, 4, rects[4][1], 2.0) == 4
    assert single_page_target(rects, 0, rects[0][1], -2.0) == 0


def test_single_page_slow_drag_settles_on_the_nearest_page():
    rects = layout([A4] * 5)
    # Dragged slowly until the middle of the screen is well inside page 3.
    assert single_page_target(rects, 2, rects[3][1] + 200, 0.05) == 3
    # Only a little: back to page 2.
    assert single_page_target(rects, 2, rects[2][1] + 500, 0.05) == 2


def test_single_page_offset_puts_the_page_in_the_middle():
    rects = layout([A4] * 3)
    zoom, view_h = 0.8, 900.0
    y = single_page_offset(rects[1], zoom, view_h)
    page_mid_on_screen = (rects[1][1] + rects[1][3] / 2) * zoom - y
    assert abs(page_mid_on_screen - view_h / 2) < 1e-6
