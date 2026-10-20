from ports.squeeze import Pencil


def test_short_squeeze_lends_the_eraser_for_one_stroke():
    p = Pencil("textPen")
    p.squeeze("began", 0.0)
    p.squeeze("ended", 0.12)
    assert p.tool == "eraser"
    p.erase_begin(1.0)
    p.erase_end(1.4)
    assert p.tool == "textPen"


def test_holding_the_squeeze_erases_until_let_go():
    p = Pencil("pen")
    p.squeeze("began", 0.0)
    p.erase_begin(0.3)
    p.erase_end(0.6)
    p.erase_begin(0.8)
    p.erase_end(1.1)
    assert p.tool == "eraser"
    p.squeeze("ended", 1.5)
    assert p.tool == "pen"


def test_letting_go_mid_stroke_gives_the_pen_back_when_the_stroke_ends():
    p = Pencil("lava")
    p.squeeze("began", 0.0)
    p.erase_begin(0.3)
    p.squeeze("ended", 0.6)
    assert p.tool == "eraser"
    p.erase_end(0.9)
    assert p.tool == "lava"


def test_a_squeeze_that_arrives_as_its_end_alone_still_switches_once():
    p = Pencil("pen")
    p.squeeze("ended", 0.0)
    p.squeeze("ended", 0.1)
    assert p.tool == "eraser"


def test_held_squeeze_let_go_without_erasing_gives_the_pen_back():
    p = Pencil("textPen")
    p.squeeze("began", 0.0)
    p.squeeze("changed", 0.4)
    p.squeeze("ended", 0.9)
    assert p.tool == "textPen"


def test_second_short_squeeze_without_erasing_gives_the_pen_back():
    p = Pencil("pen")
    p.squeeze("began", 0.0)
    p.squeeze("ended", 0.1)
    p.squeeze("began", 2.0)
    p.squeeze("ended", 2.1)
    assert p.tool == "pen"
