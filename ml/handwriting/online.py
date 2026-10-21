"""The online (stroke trajectory) handwriting model: it reads how the pen moved, not a picture, so an
'e' that looks like an 'a' is still an 'e' by where the pen started and which way it went.

Input: the line's strokes in drawing order, levelled, scaled by the line's height (the 5th–95th
percentile of y, as ink_render does) and resampled every STEP line heights along each stroke. Each
point is (dx, dy, sin θ, cos θ, pen): the move from the previous point (across a pen lift too), its
direction, and pen = 1 on the first point of a stroke (the pen came down). Twin of OnlineReader in
Murekkep.swiftpm/HandwritingModel.swift.

Network: three 1-D convolutions (the last two halve the sequence), two bidirectional LSTM layers of
160, and a linear layer to the charset + blank; CTC loss. Output: one column per 4 input points."""
import math
import struct

import numpy as np
import torch
from torch import nn

from charset import CHARSET, NUM_CLASSES

STEP = 0.1
MAX_POINTS = 2400
FEATURES = 5
HIDDEN = 160
MAGIC = b"MRKON1\0\0"


def _resample(stroke, step):
    """Points every `step` along the stroke (repeated points dropped first), ends included."""
    p = np.asarray(stroke, dtype=np.float64).reshape(-1, 2)
    if len(p) > 1:
        p = p[np.concatenate([[True], np.hypot(*np.diff(p, axis=0).T) > 1e-9])]
    if len(p) < 2:
        return p[:1]
    seg = np.hypot(*np.diff(p, axis=0).T)
    total = float(seg.sum())
    n = max(2, int(math.ceil(total / step)) + 1)
    at = np.linspace(0, total, n)
    cum = np.concatenate([[0.0], np.cumsum(seg)])
    x = np.interp(at, cum, p[:, 0])
    y = np.interp(at, cum, p[:, 1])
    return np.stack([x, y], axis=1)


def line_height(strokes):
    """The 5th to 95th percentile of y along the ink, taken every 1/50 of its height, so it does not
    depend on how densely the pen was sampled (a slow pen gives many more points)."""
    pts = [np.asarray(s, dtype=np.float64).reshape(-1, 2) for s in strokes]
    every = np.concatenate(pts)
    span = max(float(np.ptp(every[:, 1])), float(np.ptp(every[:, 0])) / 10, 1.0)
    ys = np.concatenate([_resample(p, span / 50)[:, 1] for p in pts])
    p5, p95 = np.percentile(ys, [5, 95])
    return max(float(p95 - p5), 1.0)


def features(strokes):
    """(n, 5) float32 of a line of strokes (page points, y down, drawing order)."""
    strokes = [s for s in strokes if len(s)]
    if not strokes:
        return np.zeros((0, FEATURES), np.float32)
    h = line_height(strokes)
    rows = []
    prev = None
    for s in strokes:
        pts = _resample(s, STEP * h)
        for j, (x, y) in enumerate(pts):
            if prev is None:
                dx = dy = 0.0
            else:
                dx, dy = (x - prev[0]) / h, (y - prev[1]) / h
            n = math.hypot(dx, dy)
            sin, cos = (dy / n, dx / n) if n > 1e-9 else (0.0, 1.0)
            rows.append((max(-4.0, min(4.0, dx)), max(-4.0, min(4.0, dy)), sin, cos, 1.0 if j == 0 else 0.0))
            prev = (x, y)
    out = np.asarray(rows, dtype=np.float32)
    if len(out) > MAX_POINTS:
        # A very long line: every k-th point (moves summed so the path still adds up).
        k = int(math.ceil(len(out) / MAX_POINTS))
        out = _thin(out, k)
    return out


def _thin(f, k):
    keep = []
    for i in range(0, len(f), k):
        block = f[i:i + k]
        dx, dy = float(block[:, 0].sum()), float(block[:, 1].sum())
        n = math.hypot(dx, dy)
        sin, cos = (dy / n, dx / n) if n > 1e-9 else (0.0, 1.0)
        keep.append((max(-4, min(4, dx)), max(-4, min(4, dy)), sin, cos, float(block[:, 4].max())))
    return np.asarray(keep, dtype=np.float32)


class OnlineNet(nn.Module):
    def __init__(self, classes=NUM_CLASSES):
        super().__init__()
        self.conv = nn.Sequential(
            nn.Conv1d(FEATURES, 64, 5, padding=2), nn.ReLU(),
            nn.Conv1d(64, 128, 5, stride=2, padding=2), nn.ReLU(),
            nn.Conv1d(128, 128, 5, stride=2, padding=2), nn.ReLU(),
        )
        self.rnn = nn.LSTM(128, HIDDEN, num_layers=2, bidirectional=True, batch_first=True)
        self.fc = nn.Linear(2 * HIDDEN, classes)

    def forward(self, x):  # x: (batch, n, 5)
        y = self.conv(x.transpose(1, 2)).transpose(1, 2)
        y, _ = self.rnn(y)
        return self.fc(y)


def frames(n):
    """Output columns for n input points (two stride-2 convolutions with padding 2, kernel 5)."""
    for _ in range(2):
        n = (n + 2 * 2 - 5) // 2 + 1
    return n


# ---- export and numpy inference (what the Swift reader does) ----

def tensors(model):
    sd = model.state_dict()
    out = []
    for i in (0, 2, 4):
        out += [sd[f"conv.{i}.weight"], sd[f"conv.{i}.bias"]]
    for layer in range(2):
        for suffix in ("", "_reverse"):
            out += [sd[f"rnn.weight_ih_l{layer}{suffix}"], sd[f"rnn.weight_hh_l{layer}{suffix}"],
                    sd[f"rnn.bias_ih_l{layer}{suffix}"] + sd[f"rnn.bias_hh_l{layer}{suffix}"]]
    out += [sd["fc.weight"], sd["fc.bias"]]
    return [t.detach().cpu().numpy().astype(np.float32) for t in out]


def write(model, path):
    """hwonline.bin: magic, version 1, charset, 20 float16 tensors (rank, dims, values), little-endian."""
    charset = CHARSET.encode("utf-8")
    with open(path, "wb") as f:
        f.write(MAGIC)
        f.write(struct.pack("<II", 1, len(charset)))
        f.write(charset)
        ts = tensors(model)
        f.write(struct.pack("<I", len(ts)))
        for t in ts:
            f.write(struct.pack("<I", t.ndim))
            f.write(struct.pack(f"<{t.ndim}I", *t.shape))
            f.write(t.astype("<f2").tobytes())


def load(path):
    data = open(path, "rb").read()
    assert data[:8] == MAGIC
    pos = 8
    version, n = struct.unpack_from("<II", data, pos)
    pos += 8
    charset = data[pos:pos + n].decode("utf-8")
    pos += n
    (count,) = struct.unpack_from("<I", data, pos)
    pos += 4
    ts = []
    for _ in range(count):
        (rank,) = struct.unpack_from("<I", data, pos)
        pos += 4
        dims = struct.unpack_from(f"<{rank}I", data, pos)
        pos += 4 * rank
        size = int(np.prod(dims))
        ts.append(np.frombuffer(data, "<f2", size, pos).astype(np.float32).reshape(dims))
        pos += 2 * size
    return charset, ts


def _conv1d(x, w, b, stride):
    """x (cin, n) → (cout, m): kernel 5, padding 2."""
    cin, n = x.shape
    pad = np.pad(x, ((0, 0), (2, 2)))
    m = (n + 4 - 5) // stride + 1
    cols = np.stack([pad[:, k:k + stride * (m - 1) + 1:stride] for k in range(5)], axis=1)  # (cin, 5, m)
    y = w.reshape(w.shape[0], -1) @ cols.reshape(cin * 5, m) + b[:, None]
    return np.maximum(y, 0)


def _lstm(xs, w_ih, w_hh, b, reverse):
    steps = xs.shape[0]
    pre = xs @ w_ih.T + b
    h = np.zeros(HIDDEN, np.float32)
    c = np.zeros(HIDDEN, np.float32)
    out = np.zeros((steps, HIDDEN), np.float32)
    order = range(steps - 1, -1, -1) if reverse else range(steps)
    for t in order:
        g = pre[t] + w_hh @ h
        i, f, gg, o = np.split(g, 4)
        with np.errstate(over="ignore"):  # exp overflowing to inf gives the right 0
            i, f, o = 1 / (1 + np.exp(-i)), 1 / (1 + np.exp(-f)), 1 / (1 + np.exp(-o))
        c = f * c + i * np.tanh(gg)
        h = o * np.tanh(c)
        out[t] = h
    return out


def log_probs(ts, feats):
    """(frames, classes) log-probabilities of a feature sequence, in numpy."""
    x = feats.T.astype(np.float32)
    x = _conv1d(x, ts[0], ts[1], 1)
    x = _conv1d(x, ts[2], ts[3], 2)
    x = _conv1d(x, ts[4], ts[5], 2)
    seq = x.T
    k = 6
    for _ in range(2):
        fwd = _lstm(seq, ts[k], ts[k + 1], ts[k + 2], False)
        bwd = _lstm(seq, ts[k + 3], ts[k + 4], ts[k + 5], True)
        seq = np.concatenate([fwd, bwd], axis=1)
        k += 6
    logits = seq @ ts[k].T + ts[k + 1]
    m = logits.max(axis=1, keepdims=True)
    return logits - (m + np.log(np.exp(logits - m).sum(axis=1, keepdims=True)))
