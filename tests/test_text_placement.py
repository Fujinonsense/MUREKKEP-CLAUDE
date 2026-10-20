from ports.placement import place

# Lined paper: baselines at 84 + 28k, text between 80 and 565, capitals 15.4 pt.
RULING = (84.0, 28.0, 80.0, 565.0, 15.4)
SPACE = 8.47
JOIN = 4.3


def baseline(k):
    return 84.0 + 28.0 * k


def word_box(x0, x1, k):
    """Typed text already on line k."""
    return (x0, baseline(k) - 15.4, x1, baseline(k) + 2)


def overlaps(a0, a1, b0, b1):
    return min(a1, b1) > max(a0, b0)


def test_no_overlap_with_existing_text():
    existing = word_box(100, 160, 2)
    placed = place([50, 30], 140, 2, RULING, SPACE, SPACE, [existing])
    for (x, k), w in zip(placed, [50, 30]):
        assert k == 2
        assert not overlaps(x, x + w, 100, 160)
    first_x = placed[0][0]
    assert abs(first_x - (160 + SPACE)) < 1e-6


def test_small_gap_closes_to_one_space():
    placed = place([40], 175, 3, RULING, SPACE, SPACE, [word_box(100, 150, 3)])
    assert abs(placed[0][0] - (150 + SPACE)) < 1e-6


def test_far_gap_is_kept():
    placed = place([40], 260, 3, RULING, SPACE, SPACE, [word_box(100, 150, 3)])
    assert placed[0][0] == 260


def test_punctuation_joins_without_space():
    placed = place([3], 158, 3, RULING, SPACE, JOIN, [word_box(100, 150, 3)])
    assert abs(placed[0][0] - (150 + JOIN)) < 1e-6


def test_wraps_at_right_margin():
    placed = place([200, 200, 200], 100, 4, RULING, SPACE, SPACE, [])
    assert placed[0] == (100, 4)
    assert placed[1][1] == 4
    assert placed[2] == (80.0, 5)


def test_wrap_skips_occupied_start():
    placed = place([300, 300], 200, 6, RULING, SPACE, SPACE, [word_box(80, 160, 7)])
    assert placed[1][1] == 7
    assert placed[1][0] >= 160 + SPACE - 1e-6


def test_other_lines_do_not_block():
    placed = place([60], 100, 2, RULING, SPACE, SPACE, [word_box(90, 400, 1), word_box(90, 400, 3)])
    assert placed[0] == (100, 2)


def test_underlines_and_frames_are_not_obstacles():
    from ports.placement import obstacles
    underline = (90, baseline(2) + 2, 400, baseline(2) + 4)
    frame = (70, baseline(1), 500, baseline(6))
    letter = (100, baseline(2) - 15, 110, baseline(2))
    assert obstacles([underline, frame, letter], RULING) == [letter]
