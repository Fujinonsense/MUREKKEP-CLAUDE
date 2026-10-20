from ports.shaders import lava_animates_until, lava_heat, lightning_tip_fade


def test_lava_cools_from_where_the_pen_started():
    birth, cool = 100.0, 3.0
    t = birth + 2.5
    start, middle, end = (lava_heat(t, birth, a, cool) for a in (0.0, 380.0, 760.0))
    assert start < middle < end


def test_far_end_of_lava_is_still_molten_just_after_lifting():
    birth, cool = 100.0, 3.0
    assert lava_heat(birth + 0.5, birth, 760.0, cool) == 1.0
    assert lava_heat(birth + 0.5, birth, 0.0, cool) < 1.0


def test_whole_stroke_ends_cool():
    birth, cool = 100.0, 3.0
    assert lava_heat(birth + 2.0 + cool, birth, 760.0, cool) == 0.0


def test_render_loop_runs_until_the_last_point_has_cooled():
    birth, cool, length = 100.0, 3.0, 760.0
    assert lava_animates_until(birth, length, cool) >= birth + length / 380.0 + cool


def test_lightning_bolt_stops_at_the_tip():
    r = 10.0
    # Two radii straight ahead of the last point (inside the round end cap): no bolt.
    assert lightning_tip_fade(2.0, 0.0, r) == 0.0
    # Along the body (|u| == |side|): the full bolt.
    assert lightning_tip_fade(0.5, 0.5, r) == 1.0
    assert lightning_tip_fade(-0.8, -0.8, r) == 1.0
