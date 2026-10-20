"""Port of TextLayer and PageSample (Murekkep.swiftpm/PageReading.swift).

A page's text layer is used when it has at least 25 letters and at most 2 % of its visible
characters are broken glyphs (U+FFFD, U+FFFE, private use, the empty box U+2B1A); otherwise the page
is read with OCR. Books whose fonts map ligatures to nothing ("de_ned", "coXee") are repaired word by
word: "_" (anywhere) and an "X" between lowercase letters are replaced by fi, fl, ff, ffi or ffl,
whichever first makes a dictionary word."""
import re

MIN_LETTERS = 25
MAX_BROKEN = 0.02
LIGATURES = ["fi", "fl", "ff", "ffi", "ffl"]
TOKEN = re.compile(r"[A-Za-zÇĞİÖŞÜçğıöşü_]+")
INNER_X = re.compile(r"(?<=[a-zçğıöşü])X(?=[a-zçğıöşü])")


def _broken(c):
    o = ord(c)
    return c in "�￾⬚" or 0xE000 <= o <= 0xF8FF


def is_usable(text):
    visible = [c for c in text if not c.isspace()]
    letters = sum(c.isalpha() for c in visible)
    if letters < MIN_LETTERS:
        return False
    return sum(_broken(c) for c in visible) <= MAX_BROKEN * len(visible)


def repair_ligatures(text, is_word):
    def fix(m):
        token = m.group(0)
        if "_" not in token and not INNER_X.search(token):
            return token
        for lig in LIGATURES:
            candidate = INNER_X.sub(lig, token.replace("_", lig))
            if is_word(candidate):
                return candidate
        return token

    return TOKEN.sub(fix, text)


def sample_pages(count, limit):
    """`limit` pages spread evenly over `count`, first and last included."""
    if count <= limit:
        return list(range(count))
    # Half away from zero, like Swift's rounded().
    return [int(i * (count - 1) / (limit - 1) + 0.5) for i in range(limit)]
