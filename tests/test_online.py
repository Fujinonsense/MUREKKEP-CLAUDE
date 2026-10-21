"""The online (stroke trajectory) text pen: the Kinematic Stroke Generator (ml/handwriting/kinematic.py),
the pen-motion features and the model (online.py), and font skeletons chained into pen trails
(trails.py). The numpy reader here is what the Swift reader (OnlineReader) does."""
import math
import sys
from pathlib import Path

import pytest

np = pytest.importorskip("numpy")
torch = pytest.importorskip("torch")

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "ml" / "handwriting"))
import kinematic  # noqa: E402
import online  # noqa: E402
import trails  # noqa: E402
from charset import CHARSET, NUM_CLASSES  # noqa: E402


def calm(**changes):
    style = {"jitter": 0.0, "wobble": 0.0, "density": 4.0, "size_var": 0.0, "turn": 0.0, "slant": 0.0,
             "reverse": 0.0, "reorder": 0.0, "join": 0.0, "delay_marks": 0.0, "mark_drift": 0.0,
             "gap": (0.0, 0.0), "space": 1.0, "baseline": 0.0, "scale": 2.0}
    style.update(changes)
    return style


# ---- features ----

def test_features_mark_each_pen_down_and_keep_unit_directions():
    strokes = [[(0, 0), (0, 10)], [(5, 0), (15, 0), (15, 10)]]
    f = online.features(strokes)
    assert f.shape[1] == online.FEATURES
    assert f[0, 4] == 1 and f[:, 4].sum() == 2
    second = int(np.flatnonzero(f[:, 4])[1])
    assert f[second - 1, 4] == 0
    assert np.allclose(f[:, 2] ** 2 + f[:, 3] ** 2, 1, atol=1e-5)
    # The moves add up to the pen's path in line heights (the jump between strokes included).
    h = online.line_height(strokes)
    assert f[:, 0].sum() == pytest.approx(15 / h, abs=1e-4)
    assert f[:, 1].sum() == pytest.approx(10 / h, abs=1e-4)


def test_features_do_not_depend_on_writing_size():
    rng = np.random.default_rng(3)
    strokes, _ = kinematic.make_sample(rng, "deneme yazısı")
    big = [[(3 * x + 40, 3 * y - 7) for x, y in s] for s in strokes]
    a, b = online.features(strokes), online.features(big)
    assert a.shape == b.shape
    assert np.allclose(a, b, atol=1e-3)


def test_features_do_not_depend_on_how_densely_the_pen_was_sampled():
    rng = np.random.default_rng(4)
    strokes, _ = kinematic.make_sample(rng, "yavaş yazılan kelime")
    dense = []
    for s in strokes:
        s = np.asarray(s)
        # Ten times as many points on the left half (written slowly), none added on the right.
        out = [s[0]]
        for p, q in zip(s, s[1:]):
            k = 10 if p[0] < np.median(np.concatenate(strokes)[:, 0]) else 1
            out += [p + (q - p) * j / k for j in range(1, k + 1)]
        dense.append(out)
    assert online.line_height(dense) == pytest.approx(online.line_height(strokes), rel=0.005)


def test_very_long_line_is_thinned_but_still_adds_up():
    stroke = [(x * 0.5, 10 * math.sin(x / 7)) for x in range(20_000)]
    f = online.features([stroke])
    assert len(f) <= online.MAX_POINTS
    full = online._resample(stroke, online.STEP * online.line_height([stroke]))
    h = online.line_height([stroke])
    assert f[:, 0].sum() == pytest.approx((full[-1, 0] - full[0, 0]) / h, rel=1e-3)


# ---- the model and its numpy twin ----

def fp16_model(seed=0):
    torch.manual_seed(seed)
    model = online.OnlineNet(NUM_CLASSES).eval()
    with torch.no_grad():
        for p in model.parameters():
            p.copy_(p.half().float())
    return model


@pytest.mark.parametrize("n", [5, 6, 17, 100, 401])
def test_frames_is_the_model_output_length(n):
    model = fp16_model()
    with torch.no_grad():
        out = model(torch.zeros(1, n, online.FEATURES))
    assert out.shape == (1, online.frames(n), NUM_CLASSES)


def test_numpy_reader_matches_torch(tmp_path):
    model = fp16_model(1)
    path = tmp_path / "hwonline.bin"
    online.write(model, path)
    charset, ts = online.load(path)
    assert charset == CHARSET and len(ts) == 20
    strokes, _ = kinematic.make_sample(np.random.default_rng(5), "Öğrenci şu işi çözdü")
    feats = online.features(strokes)
    with torch.no_grad():
        want = model(torch.from_numpy(feats)[None]).log_softmax(-1)[0].numpy()
    got = online.log_probs(ts, feats)
    assert got.shape == want.shape
    assert np.abs(got - want).max() < 2e-3


# ---- Kinematic Stroke Generator ----

def test_minimum_jerk_is_slow_at_the_ends_and_fast_in_the_middle():
    t = kinematic.min_jerk_times(41)
    assert t[0] == 0 and t[-1] == pytest.approx(1)
    steps = np.diff(t)
    assert (steps > 0).all()
    assert steps[0] < steps[20] / 10 and steps[-1] < steps[20] / 10


def test_spline_goes_through_its_control_points():
    pts = np.array([[0, 0], [1, 2], [3, 3], [4, 0], [6, 1]], float)
    knots = np.linspace(0, 1, len(pts))
    assert np.allclose(kinematic._catmull(pts, knots), pts, atol=1e-6)


def test_hand_direction_downstrokes_crossbars_and_loops():
    up = kinematic.natural_direction([(0, 0), (0, 10)])          # y up: drawn bottom to top
    assert up[0][1] == 10 and up[-1][1] == 0                      # becomes top to bottom
    bar = kinematic.natural_direction([(6, 5), (0, 5)])
    assert bar[0][0] == 0
    a = np.linspace(0, 2 * math.pi, 30)
    clockwise = np.stack([np.cos(-a), np.sin(-a)], axis=1)       # y up
    loop = kinematic.natural_direction(clockwise)
    area = 0.5 * float(np.sum(loop[:-1, 0] * loop[1:, 1] - loop[1:, 0] * loop[:-1, 1]))
    assert area > 0                                               # anticlockwise


def test_sloppy_e_keeps_the_pen_path_of_an_e():
    # However the control points are moved, the 'e' starts with its crossbar going right and then
    # turns up and round: the order of the pen's moves is the letter's, not the look.
    rng = np.random.default_rng(0)
    for _ in range(20):
        strokes = kinematic.write("e", rng, calm(jitter=0.45, wobble=0.35))
        assert len(strokes) == 1
        s = np.asarray(strokes[0])
        head = s[: max(3, len(s) // 6)]
        assert head[-1, 0] > head[0, 0]                           # starts going right


def turkish_marks(text, delay):
    strokes = kinematic.write(text, np.random.default_rng(2), calm(delay_marks=delay))
    tops = [min(y for _, y in s) for s in strokes]
    bottoms = [max(y for _, y in s) for s in strokes]
    return strokes, tops, bottoms


def test_turkish_dots_are_pen_up_strokes_after_the_letter():
    strokes, tops, bottoms = turkish_marks("öö", delay=0.0)
    assert len(strokes) == 6                                      # body, dot, dot, body, dot, dot
    body_top = min(tops[0], tops[3])
    for k in (1, 2, 4, 5):
        assert bottoms[k] < body_top                              # above the letter


def test_delayed_dots_come_after_the_whole_word():
    strokes, tops, bottoms = turkish_marks("öö", delay=1.0)
    assert len(strokes) == 6
    body_top = min(tops[0], tops[1])
    assert all(bottoms[k] < body_top for k in (2, 3, 4, 5))       # bodies first, then the four dots


def test_cedilla_and_breve_and_dotted_capital_i_are_their_own_strokes():
    for ch, below in [("ç", True), ("ş", True), ("ğ", False), ("İ", False), ("ı", None)]:
        _, paths = kinematic.glyph(ch)
        marks = [k for k in range(len(paths)) if kinematic._is_mark(ch, k, paths)]
        if below is None:
            assert not marks, ch                                  # dotless i has no dot
            continue
        assert marks, ch
        ys = np.concatenate([np.asarray(paths[k])[:, 1] for k in marks])
        assert (ys.max() <= 0.6) if below else (ys.min() >= 7.5), ch


def test_every_charset_character_can_be_written():
    rng = np.random.default_rng(9)
    text = CHARSET.replace(" ", "")
    for i in range(0, len(text), 12):
        assert kinematic.write(text[i:i + 12], rng), text[i:i + 12]


# ---- font skeletons as pen trails ----

def test_trails_draw_every_segment_once_in_few_strokes():
    # A '+' and an 'o' as loose segments.
    seg = [(0, 5, 5, 5), (5, 5, 10, 5), (5, 0, 5, 5), (5, 5, 5, 10)]
    a = np.linspace(0, 2 * math.pi, 13)
    ring = [(20 + 4 * math.cos(a[i]), 5 + 4 * math.sin(a[i]), 20 + 4 * math.cos(a[i + 1]), 5 + 4 * math.sin(a[i + 1]))
            for i in range(12)]
    out = trails.polylines(np.array(seg + ring))
    assert len(out) <= 3
    drawn = set()
    for t in out:
        for p, q in zip(t, t[1:]):
            drawn.add(frozenset((p, q)))
    assert len(drawn) == len(seg) + len(ring)
    assert sum(len(t) - 1 for t in out) == len(seg) + len(ring)  # no segment twice
