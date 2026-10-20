import math

from ports.textsize import cap_height, mark_size, symbol_size


def test_scale_changes_cap():
    assert math.isclose(cap_height(15.4, 28, 1.25), 19.25)
    assert math.isclose(cap_height(15.4, 28, 0.8), 12.32)
    assert math.isclose(cap_height(15.4, 28, 1.0), 15.4)


def test_cap_fits_between_ruled_lines():
    assert math.isclose(cap_height(15.4, 28, 1.5), 20.16)


def test_thick_pen_thresholds():
    assert symbol_size(2.2) == 28 and mark_size(2.2) == 14
    assert symbol_size(7) == 28 and mark_size(7) == 21
    assert symbol_size(10) == 40 and mark_size(10) == 30
