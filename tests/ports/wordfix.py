"""Twin of WordFix.swift: a word of the chosen reading that the word list does not know is swapped for
a known word one letter away (two from five letters on) when the readers find the swap almost as
likely: their summed log P may drop by at most PER_READER per reader. Both readers can be sure of a
wrong letter ("becavse": this hand's u is pointed); the word list knows "because" one letter away.
Short words, words next to an apostrophe (37'sini, Ankara'da, isn't) and words with more than one
capital are left alone,
and so are formulas (an "=" or two operators); a line with numbers is still prose ("Sınavda 40 sorunun
37'sini").

The word list (ml/handwriting/lexicon.py) holds Tatoeba's word forms seen at least KNOWN_MIN times;
swaps come from forms seen at least SWAP_MIN times, tried shortest first and in the list's order."""
import re

KNOWN_MIN = 2
SWAP_MIN = 3
PER_READER = 7.0
WORD = re.compile(r"[^\W\d_]+")
TURKISH = set("çğışöü")


def is_formula(text):
    """A formula, which keeps its letters as read: an "=" or at least two operators."""
    return "=" in text or sum(c in "+-−×÷*/^√<>±" for c in text) >= 2


def lower_tr(w):
    return w.replace("I", "ı").replace("İ", "i").lower()


def lower_en(w):
    return w.replace("İ", "i").lower()


class Lexicon:
    def __init__(self, rows):
        """rows: (word, count) in the file's order."""
        self.known = {w for w, n in rows if n >= KNOWN_MIN}
        self.by_len = {}
        for w, n in rows:
            if n >= SWAP_MIN:
                self.by_len.setdefault(len(w), []).append(w)

    @classmethod
    def load(cls, path):
        rows = []
        with open(path, encoding="utf-8") as f:
            for line in f:
                w, n = line.split()
                rows.append((w, int(n)))
        return cls(rows)

    def knows(self, w):
        return lower_tr(w) in self.known or lower_en(w) in self.known


def distance(a, b, cap):
    """Levenshtein distance, or cap + 1 once it is sure to pass cap."""
    if abs(len(a) - len(b)) > cap:
        return cap + 1
    prev = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        cur = [i] + [0] * len(b)
        low = i
        for j, cb in enumerate(b, 1):
            cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (ca != cb))
            low = min(low, cur[j])
        if low > cap:
            return cap + 1
        prev = cur
    return prev[-1]


def near(w, lexicon):
    cap = 1 if len(w) <= 4 else 2
    forms = {lower_tr(w), lower_en(w)}
    out = []
    for n in range(len(w) - cap, len(w) + cap + 1):
        for c in lexicon.by_len.get(n, ()):
            if min(distance(f, c, cap) for f in forms) <= cap:
                out.append(c)
    return out


def cased(c, w):
    """The known word c written like w: w's capital first letter stays a capital."""
    if not w[0].isupper():
        return c
    if lower_tr(w[0]) == c[0] or lower_en(w[0]) == c[0]:
        return w[0] + c[1:]
    if c[0] == "i":
        return ("İ" if TURKISH & set(c) else "I") + c[1:]
    return lower_en(c[0]).upper() + c[1:]


def fix(text, score, lexicon, readers):
    """score(text): the readers' summed log P, or None."""
    base = score(text)
    if base is None:
        return text
    limit = PER_READER * readers
    out = text
    for m in reversed(list(WORD.finditer(text))):
        w = m.group()
        if len(w) < 3 or sum(c.isupper() for c in w) > 1 or lexicon.knows(w):
            continue
        if (m.start() > 0 and text[m.start() - 1] in "'’") or (m.end() < len(text) and text[m.end()] in "'’"):
            continue
        best, best_d = None, None
        for c in near(w, lexicon):
            swap = cased(c, w)
            s = score(out[:m.start()] + swap + out[m.end():])
            if s is None:
                continue
            if best_d is None or s - base > best_d:
                best, best_d = swap, s - base
        if best is not None and best_d >= -limit:
            out = out[:m.start()] + best + out[m.end():]
            base = score(out)
    return out
