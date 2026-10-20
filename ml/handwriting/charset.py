"""Characters the handwriting model can write out. Index 0 of the model's output is the CTC blank;
character i of CHARSET is output i + 1. The charset is stored inside hwmodel.bin, so the app reads it
from there."""

CHARSET = (
    " abcdefghijklmnopqrstuvwxyzçğıöşü"
    "ABCDEFGHIJKLMNOPQRSTUVWXYZÇĞİÖŞÜ"
    "0123456789"
    ".,;:!?'\"()[]{}-_/\\%&+=*<>#@$€°^|"
    "×÷±√π≈≠≤≥∞→∫Σ∏∂Δαβγδθλμσφωε"
)

INDEX = {c: i + 1 for i, c in enumerate(CHARSET)}
assert len(INDEX) == len(CHARSET), "duplicate character in CHARSET"

NUM_CLASSES = len(CHARSET) + 1


def encode(text):
    """Model output indices of `text`; characters outside the charset raise KeyError."""
    return [INDEX[c] for c in text]


def decode(ids):
    return "".join(CHARSET[i - 1] for i in ids if i > 0)
