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


def test_descender_and_ascender_strokes_stay_on_their_line():
    """A y or p whose tail is its own stroke, or a letter's top drawn apart, lies wholly below or
    above the line's middle band; it still belongs to the line it stands in (tools/textpencheck
    found such strokes opening lines of their own: "Neler oluyor?" → "..?", "Neler oluyor.", "(")."""
    base = 200
    letters = word(100, base, 4)                                    # oluy…
    tail = [(100 + 4 * X * 1.1, base), (100 + 4 * X * 1.1 - 2, base + X * 1.1)]  # y's tail, below
    top = [(100 + 5 * X * 1.1, base - X * 1.9), (100 + 5 * X * 1.1, base - X * 1.05)]  # an ascender's top part
    more = word(100 + 6 * X * 1.1, base, 3)
    strokes = letters + [tail, top] + more
    assert len(lines(strokes)) == 1


def test_two_close_lines_stay_two_with_tails():
    """The same allowance must not pull the next line in: lines 2.2 x-heights apart, with tails."""
    a = word(100, 200, 6) + [[(100 + 6 * X * 1.1, 200), (98 + 6 * X * 1.1, 200 + X * 1.1)]]
    b = word(100, 200 + 2.2 * X, 6) + [[(100 + 6 * X * 1.1, 200 + 2.2 * X - X * 1.9),
                                        (100 + 6 * X * 1.1, 200 + 2.2 * X - X * 1.05)]]
    groups = lines(a + b)
    assert len(groups) == 2
    m = membership(a + b, groups)
    assert len({m[i] for i in range(len(a))}) == 1 and len({m[i] for i in range(len(a), len(a) + len(b))}) == 1


def test_first_letter_in_pieces_is_one_line():
    """A capital drawn as a top bowl and then the rest (B, R, P) gives the line's first band only its
    top half; the letters that follow must not grow a second line beside it (found by
    tools/textpencheck: "Bugün hava çok güzel." read as two lines)."""
    base = 200
    top_bowl = [(100, base - 1.5 * X), (106, base - 1.35 * X), (106, base - 0.9 * X), (100, base - 0.8 * X)]
    rest = [(100, base - 0.8 * X), (107, base - 0.6 * X), (107, base - 0.1 * X), (100, base)]
    strokes = [top_bowl, rest] + word(112, base, 6)
    assert len(lines(strokes)) == 1


def test_short_high_piece_inside_the_line_stays():
    """"Türevin tanımı" in a held-out script font, levelled (tools/textpencheck case 309): its letters
    come in pieces, so the line's middle band is only 5.4 pt high; a short piece high in the line (still
    within the line's own ascenders) opened a line of its own."""
    strokes = [box(0.0, -11.2, 8.2, -0.8), box(1.8, -16.6, 14.2, -11.2), box(9.1, -9.3, 14.7, -0.9),
               box(10.2, -9.3, 18.3, -2.3), box(10.4, -2.5, 10.5, -2.3), box(12.7, -5.1, 14.9, -0.9),
               box(14.3, -6.0, 18.8, -2.3), box(14.3, -5.1, 14.6, -4.9), box(14.8, -5.1, 15.1, -4.9),
               box(15.3, -12.3, 16.1, -11.3), box(18.6, -12.1, 19.2, -11.5), box(16.7, -7.8, 24.4, -0.4),
               box(20.4, -9.2, 22.7, -5.6), box(20.4, -5.9, 20.7, -5.7), box(24.4, -8.7, 25.3, -7.5),
               box(24.4, -7.7, 24.5, -7.7), box(22.1, -6.3, 29.4, -1.0), box(23.0, -9.5, 28.4, -4.3),
               box(28.7, -9.4, 32.7, -0.4), box(29.5, -6.3, 36.4, -1.9), box(29.5, -2.0, 29.8, -2.0),
               box(32.8, -9.8, 36.4, -4.5), box(32.9, -4.9, 33.2, -4.7), box(34.9, -8.9, 39.5, -1.2),
               box(35.6, -2.5, 35.8, -2.2), box(35.6, -5.8, 40.3, -2.2), box(40.0, -11.6, 40.8, -10.4),
               box(38.2, -9.1, 44.6, -0.4), box(41.0, -8.9, 48.1, -3.7), box(41.0, -3.9, 41.3, -3.9),
               box(42.9, -7.3, 46.6, -0.3), box(44.3, -5.9, 49.0, -2.1), box(49.9, -5.6, 55.9, -0.4),
               box(51.0, -13.4, 56.7, -1.6), box(51.0, -1.8, 51.2, -1.6), box(56.7, -16.8, 59.2, -13.1),
               box(56.7, -13.2, 56.8, -13.2), box(57.3, -13.7, 60.0, -13.4), box(57.5, -13.8, 57.5, -13.7),
               box(55.8, -7.6, 63.9, -0.2), box(56.7, -9.0, 64.4, -1.8), box(56.9, -1.9, 57.0, -1.8),
               box(59.4, -4.0, 61.0, -0.5), box(60.5, -5.7, 65.1, -1.7), box(60.5, -1.9, 60.8, -1.9),
               box(60.8, -4.0, 61.2, -3.8), box(63.2, -9.0, 69.6, -0.1), box(66.0, -7.4, 71.7, -0.1),
               box(66.0, -3.7, 66.3, -3.7), box(69.4, -5.7, 74.2, -1.9), box(71.7, -8.8, 73.2, -7.2),
               box(71.1, -9.4, 76.4, -0.7), box(72.0, -2.2, 72.2, -1.9), box(72.0, -5.9, 77.1, -1.9),
               box(74.9, -9.3, 81.2, -0.0), box(77.7, -8.7, 84.7, -3.5), box(77.7, -3.7, 78.0, -3.7),
               box(79.2, -7.4, 83.5, 0.0), box(82.0, -8.7, 89.0, -3.5), box(82.0, -3.6, 82.2, -3.5),
               box(83.4, -7.4, 83.5, -7.3), box(84.0, -7.4, 87.9, -0.3), box(85.5, -5.7, 90.2, -1.8),
               box(87.7, -7.4, 87.9, -7.2), box(87.7, -8.5, 92.5, -0.5), box(88.5, -1.9, 88.6, -1.6),
               box(88.5, -5.3, 93.1, -1.6)]
    assert len(lines(strokes)) == 1
