"""The pen sound's loudness follows the hand: it rises and falls within a few milliseconds, stays even
along a long straight line (the line the user found most annoying) and moves with the turns of letters,
so it sounds like writing rather than a hiss that tracks speed alone. Port: tests/ports/pen_sound.py,
twin of Murekkep.swiftpm/PenSoundEnvelope.swift."""
import math
import statistics

from ports.pen_sound import RATE, Envelope, Smoother


def samples(path, seconds=1.0, hz=240):
    """(x, y, t) of the pencil at `hz` along `path(t)`."""
    return [(*path(i / hz), i / hz) for i in range(int(seconds * hz) + 1)]


def targets(points, force=1.0):
    e = Envelope()
    return [e.update(x, y, t, force) for x, y, t in points]


def test_gain_reaches_the_hand_within_12_ms():
    s = Smoother()
    g = 0.0
    for _ in range(int(RATE * 0.012)):
        g = s.step(1.0)
    assert g >= 0.9


def test_gain_falls_within_25_ms_of_a_stop():
    s = Smoother()
    for _ in range(RATE // 10):
        s.step(1.0)
    g = 1.0
    for _ in range(int(RATE * 0.025)):
        g = s.step(0.0)
    assert g <= 0.1


def test_a_long_straight_line_is_even():
    t = targets(samples(lambda t: (400 * t, 0.3 * t)))
    steady = t[24:]
    assert min(steady) > 0
    assert max(steady) / min(steady) < 1.1


def test_letters_move_the_level_more_than_a_line():
    # Cursive loops: the hand moves on at 160 pt/s and turns six loops a second.
    loops = targets(samples(lambda t: (160 * t + 14 * math.sin(2 * math.pi * 6 * t), 14 * math.cos(2 * math.pi * 6 * t))))
    line = targets(samples(lambda t: (400 * t, 0.0)))
    spread = lambda xs: statistics.pstdev(xs[24:]) / statistics.mean(xs[24:])  # noqa: E731
    assert spread(loops) > 2 * spread(line) + 0.05
    assert statistics.mean(loops[24:]) > statistics.mean(line[24:]) * 0.8


def test_a_still_pencil_falls_silent():
    pts = samples(lambda t: (400 * t, 0.0), seconds=0.3) + [(120.0, 0.0, 0.3 + i / 240) for i in range(1, 25)]
    t = targets(pts)
    assert t[-1] < 0.02


def test_faster_is_louder_up_to_a_cap():
    levels = [statistics.mean(targets(samples(lambda t, v=v: (v * t, 0.0)))[24:]) for v in (150, 400, 900, 3000)]
    assert levels[0] < levels[1] < levels[2] <= levels[3] <= 1.0
    # Only a timbre: a straight line never reaches full loudness.
    assert levels[3] <= 0.65


def test_pressure_adds_a_little():
    light = statistics.mean(targets(samples(lambda t: (400 * t, 0.0)), force=0.3)[24:])
    firm = statistics.mean(targets(samples(lambda t: (400 * t, 0.0)), force=2.0)[24:])
    assert light < firm < light * 1.4
