"""Stars as a hand draws them, for the star rule's tests: a five-pointed star in one stroke whose lines
cross (each tip joined to the one two along), or the star's outline (ten corners, tips and notches).
Both with wobble, rounded corners, a tilt, a squash and a start anywhere."""
import math


def _wobbly(corners, rng, steps=24, wobble=0.02):
    """The corners joined by slightly wavy lines, corners cut round a little, closed."""
    out = []
    n = len(corners)
    cut = rng.uniform(0.0, 0.12)
    for i in range(n):
        a = corners[i]
        b = corners[(i + 1) % n]
        ph = rng.uniform(0, 2 * math.pi)
        for k in range(steps):
            t = cut / 2 + (1 - cut) * k / steps
            x = a[0] + (b[0] - a[0]) * t
            y = a[1] + (b[1] - a[1]) * t
            nx, ny = -(b[1] - a[1]), b[0] - a[0]
            norm = math.hypot(nx, ny) or 1
            off = wobble * 100 * math.sin(math.pi * t * 2 + ph) * rng.uniform(0.3, 1)
            out.append((x + nx / norm * off, y + ny / norm * off))
    out.append(out[0])
    return out


def _place(points, rng):
    turn = rng.uniform(-math.radians(25), math.radians(25))
    squash = rng.uniform(0.85, 1.15)
    out = []
    for x, y in points:
        x, y = x * squash, y
        out.append((200 + x * math.cos(turn) - y * math.sin(turn), 200 + x * math.sin(turn) + y * math.cos(turn)))
    shift = rng.randrange(len(out) - 1)
    loop = out[:-1]
    loop = loop[shift:] + loop[:shift]
    return loop + [loop[0]]


def crossing_star(rng, r=60.0):
    tips = [(r * math.cos(-math.pi / 2 + 2 * math.pi * k / 5), r * math.sin(-math.pi / 2 + 2 * math.pi * k / 5))
            for k in range(5)]
    order = [tips[(2 * k) % 5] for k in range(5)]
    return _place(_wobbly(order, rng), rng)


def outline_star(rng, r=60.0):
    inner = r * rng.uniform(0.38, 0.5)
    corners = []
    for k in range(10):
        a = -math.pi / 2 + math.pi * k / 5
        rr = r if k % 2 == 0 else inner
        corners.append((rr * math.cos(a), rr * math.sin(a)))
    return _place(_wobbly(corners, rng, steps=12), rng)
