"""Port of the lava and lightning pieces of InkShaders.swift (and how long InkRenderer keeps lava
animating)."""
import math


def smoothstep(a, b, x):
    t = min(max((x - a) / (b - a), 0.0), 1.0)
    return t * t * (3 - 2 * t)


def lava_heat(time, birth, arc, cool):
    """1 = molten, 0 = cooled. `birth` is when the pen lifted; `arc` the point's distance along."""
    age = time - (birth + max(arc, 0.0) / LAVA_COOL_SPEED)
    return 1.0 - smoothstep(0.0, max(cool, 0.5), age)


LAVA_COOL_SPEED = 380.0


def lava_animates_until(birth, length, cool):
    """Last moment the render loop keeps running for a lava stroke of `length` points."""
    return birth + length / LAVA_COOL_SPEED + cool + 0.5


def lightning_tip_fade(u, side, r):
    """Weight of the bolt's jagged core at a fragment; `u`, `side` in radius units as the vertex
    shader passes them (in the round caps |u| > |side|)."""
    beyond = math.sqrt(max(u * u - side * side, 0.0)) * r
    return 1.0 - smoothstep(0.0, r * 0.3, beyond)
