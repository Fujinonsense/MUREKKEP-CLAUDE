"""The recognizer in plain numpy, step by step as HandwritingModel.swift runs it on the iPad (the
Swift code is a transcription of this file): 3×3 convolutions as one matrix product over the
shifted image (im2col, index channel × 9 + row × 3 + column), ReLU, max pooling, LSTM gates i, f, g,
o with the backward direction run over reversed time, the linear layer and log-softmax."""
import struct

import numpy as np

POOLS = {0: (2, 2), 1: (2, 2), 3: (2, 1), 5: (2, 1)}
HIDDEN = 160


class Weights:
    def __init__(self, tensors, charset=None):
        self.tensors = [np.asarray(t, dtype=np.float32) for t in tensors]
        self.charset = charset
        t = self.tensors
        self.convs = [(t[2 * i], t[2 * i + 1]) for i in range(6)]
        self.lstms = [tuple(t[12 + 3 * k: 15 + 3 * k]) for k in range(4)]  # l1 fwd, l1 bwd, l2 fwd, l2 bwd
        self.fc = (t[24], t[25])


def load(path):
    data = open(path, "rb").read()
    assert data[:8] == b"MRKHW1\0\0"
    version, nchars = struct.unpack_from("<II", data, 8)
    pos = 16
    charset = data[pos:pos + nchars].decode("utf-8")
    pos += nchars
    (count,) = struct.unpack_from("<I", data, pos)
    pos += 4
    tensors = []
    for _ in range(count):
        (rank,) = struct.unpack_from("<I", data, pos)
        pos += 4
        dims = struct.unpack_from(f"<{rank}I", data, pos)
        pos += 4 * rank
        n = int(np.prod(dims))
        tensors.append(np.frombuffer(data, dtype="<f2", count=n, offset=pos).astype(np.float32).reshape(dims))
        pos += 2 * n
    return Weights(tensors, charset)


def conv3x3(x, w, b):
    c, h, wd = x.shape
    p = np.pad(x, ((0, 0), (1, 1), (1, 1)))
    cols = np.empty((c * 9, h * wd), dtype=np.float32)
    for ci in range(c):
        for dy in range(3):
            for dx in range(3):
                cols[ci * 9 + dy * 3 + dx] = p[ci, dy:dy + h, dx:dx + wd].ravel()
    out = w.reshape(w.shape[0], -1) @ cols + b[:, None]
    return np.maximum(out, 0).reshape(w.shape[0], h, wd)


def maxpool(x, ph, pw):
    c, h, w = x.shape
    return x.reshape(c, h // ph, ph, w // pw, pw).max(axis=(2, 4))


def _sigmoid(v):
    return 1 / (1 + np.exp(-v))


def lstm(xs, w_ih, w_hh, b, reverse):
    t_len = xs.shape[0]
    pre = xs @ w_ih.T + b
    h = np.zeros(HIDDEN, dtype=np.float32)
    c = np.zeros(HIDDEN, dtype=np.float32)
    out = np.zeros((t_len, HIDDEN), dtype=np.float32)
    for t in (range(t_len - 1, -1, -1) if reverse else range(t_len)):
        g = pre[t] + w_hh @ h
        i = _sigmoid(g[:HIDDEN])
        f = _sigmoid(g[HIDDEN:2 * HIDDEN])
        gg = np.tanh(g[2 * HIDDEN:3 * HIDDEN])
        o = _sigmoid(g[3 * HIDDEN:])
        c = f * c + i * gg
        h = o * np.tanh(c)
        out[t] = h
    return out


def log_probs(weights, image):
    """[W/4, classes] log-probabilities of a 48×W line image (ink 1 on 0)."""
    x = image[None].astype(np.float32)
    for i, (w, b) in enumerate(weights.convs):
        x = conv3x3(x, w, b)
        if i in POOLS:
            x = maxpool(x, *POOLS[i])
    c, h, t_len = x.shape
    seq = x.transpose(2, 0, 1).reshape(t_len, c * h)
    for layer in range(2):
        fwd = lstm(seq, *weights.lstms[2 * layer], reverse=False)
        bwd = lstm(seq, *weights.lstms[2 * layer + 1], reverse=True)
        seq = np.concatenate([fwd, bwd], axis=1)
    logits = seq @ weights.fc[0].T + weights.fc[1]
    m = logits.max(axis=1, keepdims=True)
    return logits - m - np.log(np.exp(logits - m).sum(axis=1, keepdims=True))
