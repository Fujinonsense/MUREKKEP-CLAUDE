"""What the synthetic lines say: fragments of Turkish and English Tatoeba sentences (CC-BY 2.0 FR),
generated math, and short items (marks, numbers, quotes, capitals) the text pen sees alone."""
import os
from functools import lru_cache
from pathlib import Path

from charset import CHARSET

DATA = Path(os.environ.get("MRK_DATA", "C:/Users/orsyu/mrk-ml/data"))
MAX_CHARS = 48
ALLOWED = set(CHARSET)
NORMALIZE = str.maketrans({"’": "'", "‘": "'", "“": '"', "”": '"', "«": '"', "»": '"', "–": "-", "—": "-",
                           "−": "-", "\u00a0": " ", "…": "..."})


def _clean(s):
    s = s.translate(NORMALIZE).strip()
    return s if s and all(c in ALLOWED for c in s) else None


@lru_cache(maxsize=2)
def sentences(lang, limit=400_000):
    path = DATA / "text" / ("tur_sentences.tsv" if lang == "tr" else "eng_sentences.tsv")
    out = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            parts = line.rstrip("\n").split("\t")
            if len(parts) == 3:
                s = _clean(parts[2])
                if s:
                    out.append(s)
                    if len(out) >= limit:
                        break
    return out


def tr_upper(s):
    return s.replace("i", "İ").replace("ı", "I").upper()


def _fragment(rng, lang):
    pool = sentences(lang)
    words = pool[int(rng.integers(len(pool)))].split()
    n = int(rng.integers(1, 9))
    start = int(rng.integers(0, max(1, len(words) - n + 1)))
    text = " ".join(words[start:start + n])
    # All-caps lines: the line image hides letter size, so the model needs many of them to tell
    # "WE" from "we" by shape and context.
    if rng.random() < 0.12:
        caps = tr_upper(text) if lang == "tr" else text.upper()
        # Greek letters have capitals outside the charset ("β" → "Β"): such a line stays as it is.
        if all(c in ALLOWED for c in caps):
            text = caps
    return text


VARS = "xyzabnktf"
OPS = ["+", "-", "×", "÷", "=", "≤", "≥", "≠", "≈", "<", ">", "±"]


def _math(rng):
    v = lambda: VARS[int(rng.integers(len(VARS)))]  # noqa: E731
    num = lambda: str(int(rng.integers(0, 100))) if rng.random() < 0.8 else f"{rng.integers(0, 10)},{rng.integers(0, 100)}"  # noqa: E731
    op = lambda: OPS[int(rng.integers(len(OPS)))]  # noqa: E731
    forms = [
        lambda: f"{num()}{v()} {op()} {num()}",
        lambda: f"f({v()}) = {num()}{v()} {op()} {num()}",
        lambda: f"∫ f({v()}) d{v()}",
        lambda: f"√{num()} ≈ {num()}",
        lambda: f"{v()} {op()} {v()}",
        lambda: f"Σ {v()} = {num()}",
        lambda: f"({v()} + {num()})({v()} - {num()})",
        lambda: f"π × r = {num()}",
        lambda: f"Δ{v()} = {num()} {op()} {num()}",
        lambda: f"{num()}% {op()} {num()}°",
        lambda: f"α + β = {num()}°",
        lambda: f"lim {v()} → ∞",
    ]
    return forms[int(rng.integers(len(forms)))]()


SHORT = [",", ".", "?", "!", ":", ";", "'", '"', "-", "(", ")", "...", "?!", "ı", "i", "İ", "I", "a", "ş", "ğ", "ç",
         "ö", "ü", "ve", "ile", "the", "a.", "p. 42", "s. 12", "Dr.", "vb.", "örn.", "e.g.", "İSTANBUL'DA",
         "ANKARA'YA", "NASA", "Türkiye'nin", "it's", "don't", '"alıntı"', '"quote"', "(bkz.)", "1.", "2)", "a)",
         "x", "y", "%50", "€20", "$5", "@", "&", "#3", "10:30", "3/4", "-5", "+7"]


def _short(rng):
    r = rng.random()
    if r < 0.6:
        return SHORT[int(rng.integers(len(SHORT)))]
    if r < 0.8:
        return f"{rng.integers(1, 32)}.{rng.integers(1, 13)}.{rng.integers(1990, 2030)}"
    return str(int(rng.integers(0, 10 ** int(rng.integers(1, 7)))))


def sample(rng):
    """One line of text, at most MAX_CHARS characters, every character in CHARSET."""
    r = rng.random()
    if r < 0.45:
        text = _fragment(rng, "tr")
    elif r < 0.80:
        text = _fragment(rng, "en")
    elif r < 0.90:
        text = _math(rng)
    else:
        text = _short(rng)
    if len(text) > MAX_CHARS:
        text = text[:MAX_CHARS].rsplit(" ", 1)[0] or text[:MAX_CHARS]
    return text
