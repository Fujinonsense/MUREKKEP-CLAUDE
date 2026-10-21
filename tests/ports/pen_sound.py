"""Port of PenSoundEnvelope (Murekkep.swiftpm/PenSoundEnvelope.swift): how loud the pen sound should be
from the pencil's samples, and how the audio thread glides to that loudness.

The loudness has three parts. Motion: the hand's speed (smoothed over 15 ms, nothing below 20 pt/s),
square-rooted so slow writing is still heard, full at 700 pt/s. Texture: how fast the line turns
(smoothed over 30 ms); a straight line sits at 60 %, the loops and corners of letters lift it to 100 %,
so the sound moves with the shape of the writing instead of droning along a long line. Pressure adds
up to a quarter. The audio thread glides there sample by sample, quickly up and a little slower down."""
import math

RATE = 44100
ATTACK = 0.005
RELEASE = 0.003
SPEED_GATE = 20.0
SPEED_FULL = 700.0
TURN_FULL = 25.0
SPEED_TAU = 0.015
TURN_TAU = 0.03
MIN_STEP = 0.25


class Smoother:
    """The audio thread's glide from the current gain to the target, per sample."""

    def __init__(self):
        self.g = 0.0

    def step(self, target):
        k = ATTACK if target > self.g else RELEASE
        self.g += (target - self.g) * k
        return self.g


class Envelope:
    def __init__(self):
        self.last = None
        self.heading = None
        self.speed = 0.0
        self.turn = 0.0

    def update(self, x, y, t, force):
        """Target loudness 0…1 for a pencil sample (view points, seconds, force 0…~4)."""
        if self.last is None:
            self.last = (x, y, t)
            return 0.0
        lx, ly, lt = self.last
        self.last = (x, y, t)
        dt = max(t - lt, 1 / 480)
        dx, dy = x - lx, y - ly
        dist = math.hypot(dx, dy)
        self.speed += (dist / dt - self.speed) * (1 - math.exp(-dt / SPEED_TAU))
        turn_k = 1 - math.exp(-dt / TURN_TAU)
        if dist > MIN_STEP:
            heading = math.atan2(dy, dx)
            if self.heading is not None:
                d = (heading - self.heading + math.pi) % (2 * math.pi) - math.pi
                self.turn += (abs(d) / dt - self.turn) * turn_k
            self.heading = heading
        else:
            self.turn -= self.turn * turn_k
        motion = math.sqrt(min(max(self.speed - SPEED_GATE, 0.0) / (SPEED_FULL - SPEED_GATE), 1.0))
        texture = min(self.turn / TURN_FULL, 1.0)
        press = 0.75 + 0.25 * min(max(force, 0.0), 2.0) / 2.0
        return motion * (0.6 + 0.4 * texture) * press
