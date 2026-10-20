import random

from ports.spelling import MARGIN, choose


def brute_force(scores):
    best, best_score = 0, scores[0]
    for i, s in enumerate(scores[1:], start=1):
        if s > best_score + MARGIN:
            best, best_score = i, s
    return best


def test_well_read_line_skips_the_other_readings():
    # Every word of the first reading is known: nothing can beat it, so nothing else is looked up.
    assert choose([1.0, 0.5, 1.0, 0.2, 0.9, 0.7]) == (0, 1)
    assert choose([0.9, 1.0, 1.0])[1] == 1


def test_same_choice_as_scoring_every_reading():
    rng = random.Random(7)
    for _ in range(5000):
        n = rng.randint(1, 6)
        scores = [rng.choice([0, 0.2, 0.25, 0.4, 0.5, 0.6, 0.75, 0.8, 0.85, 0.9, 1.0]) for _ in range(n)]
        assert choose(scores)[0] == brute_force(scores)
