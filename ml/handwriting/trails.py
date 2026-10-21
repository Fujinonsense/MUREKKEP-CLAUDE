"""Loose segments (a font skeleton) chained into pen strokes the way a pen would draw them: each trail
starts at a loose end (a vertex of odd degree, the leftmost first) and keeps going straightest through
unused segments. A letter becomes 1–4 strokes instead of hundreds of pieces."""
import math


def polylines(seg):
    """[[(x, y), …], …] from segment rows (x0, y0, x1, y1)."""
    def key(x, y):
        return (round(x, 2), round(y, 2))

    edges = []
    adj = {}
    for x0, y0, x1, y1 in seg.tolist():
        a, b = key(x0, y0), key(x1, y1)
        if a == b:
            continue
        e = len(edges)
        edges.append((a, b))
        adj.setdefault(a, []).append(e)
        adj.setdefault(b, []).append(e)
    used = [False] * len(edges)
    unused = {v: len(es) for v, es in adj.items()}  # unused segments at each vertex
    remaining = len(edges)
    out = []

    def left(v):
        return [e for e in adj[v] if not used[e]]

    while remaining:
        free = [v for v, k in unused.items() if k]
        odd = [v for v in free if unused[v] % 2 == 1]
        v = min(odd or free)
        trail = [v]
        prev = None
        while left(v):
            options = left(v)
            if prev is not None:
                hx, hy = v[0] - prev[0], v[1] - prev[1]

                def turn(e):
                    a, b = edges[e]
                    w = b if a == v else a
                    dx, dy = w[0] - v[0], w[1] - v[1]
                    return -(hx * dx + hy * dy) / (math.hypot(hx, hy) * math.hypot(dx, dy) + 1e-9)
                options.sort(key=turn)
            e = options[0]
            used[e] = True
            remaining -= 1
            a, b = edges[e]
            unused[a] -= 1
            unused[b] -= 1
            prev, v = v, (b if a == v else a)
            trail.append(v)
        out.append(trail)
    if not out and len(seg):
        out.append([(float(seg[0, 0]), float(seg[0, 1]))])  # a dot
    return out
