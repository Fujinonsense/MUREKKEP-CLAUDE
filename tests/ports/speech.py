"""Port of SpeechText.spokenMath / turkishNumber / chunks (Murekkep.swiftpm/EmbeddedVoices.swift).

The embedded voice (Supertonic 3) reads English digits well but misreads Turkish numbers, and drops
math symbols in both languages, so they are written out first. Turkish: f(x) → "fe iks", x² → "iks
kare", x^2 → "iks üssü iki", %25 → "yüzde yirmi beş", 14:45 → "on dört kırk beş", "7. soru" →
"yedinci soru", 1.250 → "bin iki yüz elli", 3,5 → "üç virgül beş", 3.5 → "üç nokta beş", -5 → "eksi
beş", 42'deki → "kırk ikideki", = + − × ÷ / → eşittir artı eksi çarpı bölü. English: f(x) → "f of x",
x² → "x squared", = + → "equals plus", a/b → "a over b"; digits stay. Long texts are cut at sentence
ends (then at commas, then between words) into pieces of at most `max_chars`."""
import re

UNITS = ["", "bir", "iki", "üç", "dört", "beş", "altı", "yedi", "sekiz", "dokuz"]
TENS = ["", "on", "yirmi", "otuz", "kırk", "elli", "altmış", "yetmiş", "seksen", "doksan"]
SCALES = [(10 ** 9, "milyar"), (10 ** 6, "milyon"), (10 ** 3, "bin")]
ORDINAL = {"bir": "birinci", "iki": "ikinci", "üç": "üçüncü", "dört": "dördüncü", "beş": "beşinci", "altı": "altıncı",
           "yedi": "yedinci", "sekiz": "sekizinci", "dokuz": "dokuzuncu", "on": "onuncu", "yirmi": "yirminci",
           "otuz": "otuzuncu", "kırk": "kırkıncı", "elli": "ellinci", "altmış": "altmışıncı", "yetmiş": "yetmişinci",
           "seksen": "sekseninci", "doksan": "doksanıncı", "yüz": "yüzüncü", "bin": "bininci", "milyon": "milyonuncu",
           "milyar": "milyarıncı", "sıfır": "sıfırıncı"}
LETTERS = {"a": "a", "b": "be", "c": "ce", "d": "de", "e": "e", "f": "fe", "g": "ge", "h": "he", "i": "i", "j": "je",
           "k": "ke", "l": "le", "m": "me", "n": "ne", "o": "o", "p": "pe", "q": "kü", "r": "re", "s": "se", "t": "te",
           "u": "u", "v": "ve", "w": "çift ve", "x": "iks", "y": "ye", "z": "ze"}


def turkish_number(n):
    if n == 0:
        return "sıfır"
    parts = []
    for scale, name in SCALES:
        if n >= scale:
            head, n = divmod(n, scale)
            if not (scale == 1000 and head == 1):  # "bin", not "bir bin"
                parts.append(turkish_number(head))
            parts.append(name)
    if n >= 100:
        if n // 100 > 1:
            parts.append(UNITS[n // 100])
        parts.append("yüz")
        n %= 100
    if n >= 10:
        parts.append(TENS[n // 10])
        n %= 10
    if n > 0:
        parts.append(UNITS[n])
    return " ".join(parts)


def turkish_ordinal(n):
    words = turkish_number(n).split()
    words[-1] = ORDINAL.get(words[-1], words[-1])
    return " ".join(words)


def _digits(s):
    """A fraction part: digit by digit when it starts with 0 ("05" → "sıfır beş"), else as a number."""
    if s.startswith("0"):
        return " ".join(turkish_number(int(c)) for c in s)
    return turkish_number(int(s))


def _letter(c, english):
    return c if english else LETTERS.get(c.lower(), c)


def spoken_math(text, english):
    t = text
    # Function notation: f(x) → "fe iks" / "f of x".
    def function(m):
        arg = m.group(2)
        arg = _letter(arg, english) if len(arg) == 1 and arg.isalpha() else arg
        return f"{_letter(m.group(1), english)} {'of ' if english else ''}{arg}"
    t = re.sub(r"\b([A-Za-z])\(([A-Za-z0-9]+)\)", function, t)
    t = t.replace("²", " squared" if english else " kare").replace("³", " cubed" if english else " küp")
    t = re.sub(r"([\w)])\s*\^\s*(-?\w+)", lambda m: f"{m.group(1)} {'to the power of' if english else 'üssü'} {m.group(2)}", t)
    if not english:
        t = re.sub(r"%\s?(\d+(?:[.,]\d+)?)", r"yüzde \1", t)
        t = re.sub(r"(\d+(?:[.,]\d+)?)\s?%", r"yüzde \1", t)
        t = re.sub(r"\b(\d{1,2}):(\d{2})\b", lambda m: f"{turkish_number(int(m.group(1)))} {turkish_number(int(m.group(2)))}", t)
        t = re.sub(r"\b(\d{1,4})\.(?=\s+[a-zçğıöşü])", lambda m: turkish_ordinal(int(m.group(1))), t)
        t = re.sub(r"\b\d{1,3}(?:\.\d{3})+\b", lambda m: m.group(0).replace(".", ""), t)
        t = re.sub(r"\b(\d+),(\d+)\b", lambda m: f"{turkish_number(int(m.group(1)))} virgül {_digits(m.group(2))}", t)
        t = re.sub(r"\b(\d+)\.(\d+)\b", lambda m: f"{turkish_number(int(m.group(1)))} nokta {_digits(m.group(2))}", t)
        t = re.sub(r"(?<![\w)])[-−](\d)", r"eksi \1", t)
        t = re.sub(r"(\d+)'([a-zçğıöşü]+)", lambda m: turkish_number(int(m.group(1))) + m.group(2), t)
    t = re.sub(r"(\d)([A-Za-z])\b", r"\1 \2", t)
    minus, plus, equals = (" minus ", " plus ", " equals ") if english else (" eksi ", " artı ", " eşittir ")
    t = re.sub(r"\s*=\s*", equals, t)
    t = re.sub(r"\s*\+\s*", plus, t)
    t = re.sub(r"\s*−\s*", minus, t)
    t = re.sub(r"(\d|\b[xyz])\s+-\s+(?=\d|[xyz]\b)", lambda m: m.group(1) + minus, t)
    t = re.sub(r"\s*×\s*", " times " if english else " çarpı ", t)
    t = re.sub(r"\s*÷\s*", " divided by " if english else " bölü ", t)
    t = re.sub(r"(?:(?<=[\dπ)])|(?<=\b[xyz]))\s*/\s*(?=[\dπ(]|[xyz]\b)", " over " if english else " bölü ", t)
    t = t.replace("π", " pi ")
    if not english:
        t = re.sub(r"\d+", lambda m: turkish_number(int(m.group(0))), t)
        t = re.sub(r"\b([xyz])\b", lambda m: LETTERS[m.group(1)], t)
    t = re.sub(r"[ \t]{2,}", " ", t)
    t = re.sub(r" ([,.;:!?])", r"\1", t)
    return t.strip()


def _split_long(sentence, max_chars):
    pieces, current = [], ""
    for part in re.split(r"(?<=[,;:])\s+", sentence):
        words = part.split(" ") if len(part) > max_chars else [part]
        for w in words:
            candidate = (current + " " + w).strip() if current else w
            if len(candidate) <= max_chars:
                current = candidate
            else:
                if current:
                    pieces.append(current)
                current = w
    if current:
        pieces.append(current)
    return pieces


def chunks(text, max_chars):
    text = re.sub(r"\s+", " ", text).strip()
    out, current = [], ""
    for sentence in re.split(r"(?<=[.!?…])\s+", text):
        for piece in ([sentence] if len(sentence) <= max_chars else _split_long(sentence, max_chars)):
            candidate = (current + " " + piece) if current else piece
            if len(candidate) <= max_chars:
                current = candidate
            else:
                out.append(current)
                current = piece
    if current:
        out.append(current)
    return out
