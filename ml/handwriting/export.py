"""Writes the trained recognizer as hwmodel.bin, the file the app loads from its asset catalog:

    b"MRKHW1\\0\\0", u32 version (1), u32 charset byte count, UTF-8 charset, u32 tensor count,
    then per tensor: u32 rank, u32 dims…, float16 values (little endian).

Tensor order: six convolutions with batch norm folded in (weight [out, in, 3, 3], bias [out]); for
each LSTM layer, forward then backward direction: W_ih [640, in], W_hh [640, 160], bias [640]
(b_ih + b_hh, gates i, f, g, o); the linear layer weight [classes, 320], bias [classes].

usage: python export.py <checkpoint.pt> <hwmodel.bin>"""
import struct
import sys

import numpy as np
import torch

from charset import CHARSET, NUM_CLASSES
from model import CRNN, convs, norms

MAGIC = b"MRKHW1\0\0"
VERSION = 1


def tensors(model):
    """The 26 float32 arrays in file order."""
    out = []
    with torch.no_grad():
        for conv, bn in zip(convs(model), norms(model)):
            k = bn.weight / torch.sqrt(bn.running_var + bn.eps)
            out.append((conv.weight * k[:, None, None, None]).numpy().astype(np.float32))
            out.append((bn.bias - bn.running_mean * k).numpy().astype(np.float32))
        for rnn in (model.rnn1, model.rnn2):
            for suffix in ("", "_reverse"):
                out.append(getattr(rnn, "weight_ih_l0" + suffix).numpy().astype(np.float32))
                out.append(getattr(rnn, "weight_hh_l0" + suffix).numpy().astype(np.float32))
                b = getattr(rnn, "bias_ih_l0" + suffix) + getattr(rnn, "bias_hh_l0" + suffix)
                out.append(b.numpy().astype(np.float32))
        out.append(model.fc.weight.numpy().astype(np.float32))
        out.append(model.fc.bias.numpy().astype(np.float32))
    return out


def write(model, path):
    model = model.eval()
    chars = CHARSET.encode("utf-8")
    with open(path, "wb") as f:
        f.write(MAGIC)
        f.write(struct.pack("<II", VERSION, len(chars)))
        f.write(chars)
        ts = tensors(model)
        f.write(struct.pack("<I", len(ts)))
        for t in ts:
            f.write(struct.pack("<I", t.ndim))
            f.write(struct.pack(f"<{t.ndim}I", *t.shape))
            f.write(t.astype("<f2").tobytes())


if __name__ == "__main__":
    state = torch.load(sys.argv[1], map_location="cpu")
    m = CRNN(NUM_CLASSES)
    m.load_state_dict(state["model"] if "model" in state else state)
    write(m, sys.argv[2])
    print("written", sys.argv[2])
