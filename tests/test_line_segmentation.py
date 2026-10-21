import math

from ports.inkline import lines, split_raised

CAP = 15.0
X = 7.0 * CAP / 10  # x-height


def loop(cx, base, h=X, w=None):
    """An o-like letter: a closed loop of height h sitting on the baseline."""
    w = w or h * 0.8
    return [(cx + w / 2 * math.cos(a), base - h / 2 + h / 2 * math.sin(a)) for a in [i * math.pi / 12 for i in range(25)]]


def stem(cx, base, h=X):
    return [(cx, base - h), (cx, base)]


def dot(cx, y):
    return [(cx, y), (cx + 0.6, y + 0.4)]


def word(x0, base, n):
    """n loop letters 0.9 x-height apart."""
    return [loop(x0 + k * X * 1.1, base) for k in range(n)]


def membership(strokes, groups):
    out = {}
    for li, g in enumerate(groups):
        for i in g:
            out[i] = li
    return out


def test_two_lines():
    a = word(100, 200, 8)
    b = word(100, 240, 6)
    groups = lines(a + b)
    assert len(groups) == 2
    m = membership(a + b, groups)
    assert {m[i] for i in range(len(a))} == {0}
    assert {m[i] for i in range(len(a), len(a) + len(b))} == {1}


def test_i_dots_and_cedillas_stay_on_their_line():
    base1, base2 = 200.0, 230.0
    strokes = word(100, base1, 3)
    marks1 = [
        stem(140, base1), dot(140, base1 - X - 3),                       # i
        loop(150, base1), [(150, base1 + 1), (151, base1 + 3.5), (149, base1 + 4.5)],  # ş + cedilla
        loop(160, base1), [(157, base1 - X - 3), (160, base1 - X - 1.5), (163, base1 - X - 3)],  # ğ + breve
    ]
    line2 = word(100, base2, 3)
    marks2 = [loop(140, base2), dot(138.5, base2 - X - 2.5), dot(141.5, base2 - X - 2.5)]  # ü
    all_strokes = strokes + marks1 + line2 + marks2
    groups = lines(all_strokes)
    assert len(groups) == 2
    m = membership(all_strokes, groups)
    first = range(0, len(strokes) + len(marks1))
    second = range(len(strokes) + len(marks1), len(all_strokes))
    assert {m[i] for i in first} == {0}
    assert {m[i] for i in second} == {1}


def test_tilted_line_is_one_line():
    slope = math.tan(math.radians(8))
    strokes = [loop(100 + k * X * 1.1, 300 - k * X * 1.1 * slope) for k in range(30)]
    assert len(lines(strokes)) == 1


def test_superscript_detected():
    base = 200.0
    x_letter = [[(100, base - X), (100 + X * 0.8, base)], [(100, base), (100 + X * 0.8, base - X)]]
    two = [(108, base - X - 2.5), (110.5, base - X - 4.5), (112, base - X - 2.5), (108, base - X + 0.5), (112.5, base - X + 0.5)]
    plus = [[(118, base - X / 2), (124, base - X / 2)], [(121, base - X / 2 - 3), (121, base - X / 2 + 3)]]
    y_letter = loop(130, base)
    strokes = x_letter + [two] + plus + [y_letter]
    groups = lines(strokes)
    assert len(groups) == 1
    base_idx, raised = split_raised(strokes, groups[0])
    assert len(raised) == 1
    idx, gx = raised[0]
    assert idx == [2]
    assert abs(gx - 108) < 0.01
    assert 2 not in base_idx


def test_i_dot_is_not_a_superscript():
    base = 200.0
    strokes = word(100, base, 2) + [stem(120, base), dot(120, base - X - 3)] + word(125, base, 2)
    groups = lines(strokes)
    assert len(groups) == 1
    _, raised = split_raised(strokes, groups[0])
    assert raised == []



def box(x0, y0, x1, y1):
    """A stroke that fills a box (its diagonal)."""
    return [(x0, y0), (x1, y1)]


def test_capital_then_descender_is_one_line():
    # "Bugün hava" in a held-out handwriting font (the boxes measured from it): B, u and a deep g at
    # the start once tilted the line's band so far that the rest fell onto a line of its own
    # ("Bug" | "ün hava…").
    strokes = [box(0.0, -15.9, 8.0, 0.3), box(9.0, -9.4, 16.0, -0.2), box(17.7, -9.5, 23.5, 10.7),
               box(24.6, -12.6, 32.0, -0.3), box(33.0, -8.6, 40.0, 0.0), box(44.3, -18.9, 50.5, 0.2),
               box(51.7, -9.3, 58.5, 0.0), box(59.9, -9.3, 65.0, 0.0), box(65.8, -9.0, 72.0, 0.0)]
    assert len(lines(strokes)) == 1


def test_short_start_does_not_tilt_the_band():
    # "Bugün hava çok güzel." in another held-out font, levelled from 6°: with only "Bug" on the line
    # the slope between a capital, a small letter and a deep g pointed the band below the "ü".
    strokes = [box(0.005, -14.064, 12.758, -1.049), box(15.58, -9.232, 24.742, -0.839),
               box(26.492, -9.565, 35.844, 8.558), box(38.889, -13.924, 47.819, -1.128),
               box(49.448, -11.152, 58.442, -1.121), box(69.652, -15.181, 78.493, -1.998),
               box(81.484, -9.965, 91.162, -1.53), box(92.462, -10.814, 101.108, -2.267),
               box(103.415, -10.349, 113.198, -1.822), box(123.229, -11.213, 135.431, 2.828),
               box(137.818, -11.285, 147.553, -2.72), box(150.54, -16.629, 161.815, -2.649),
               box(172.767, -11.073, 181.706, 6.25), box(184.098, -16.803, 193.678, -3.073),
               box(195.872, -11.368, 205.547, -3.385), box(206.769, -12.612, 216.435, -3.645),
               box(219.009, -18.092, 220.112, -3.431), box(222.924, -3.824, 223.821, -3.457)]
    assert len(lines(strokes)) == 1
