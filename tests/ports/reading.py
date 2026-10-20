"""Port of Reading in HandwritingConverter.swift: which reading of a line wins, and where exponents
go back into it.

Every candidate (the model's beam, and Vision's readings scored by the model) is worth
log P / length + 0.6 × the share of its words the dictionary knows (case does not count). The model
decides when it is sure, the dictionary when the model hesitates (kucuk / küçük); math lines are left
to the model alone. Without the model, Vision's first reading stands."""
import math

DICT_WEIGHT = 0.6

# StrokeFont's raised characters (Murekkep.swiftpm/StrokeFont.swift, `superscripts`).
SUPERS = {
    "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹",
    "-": "⁻", "+": "⁺", "n": "ⁿ", "=": "⁼", "(": "⁽", ")": "⁾",
    "a": "ᵃ", "b": "ᵇ", "c": "ᶜ", "d": "ᵈ", "e": "ᵉ", "f": "ᶠ", "g": "ᵍ", "h": "ʰ", "i": "ⁱ", "j": "ʲ",
    "k": "ᵏ", "l": "ˡ", "m": "ᵐ", "o": "ᵒ", "p": "ᵖ", "r": "ʳ", "s": "ˢ", "t": "ᵗ", "u": "ᵘ", "v": "ᵛ",
    "w": "ʷ", "x": "ˣ", "y": "ʸ", "z": "ᶻ", "α": "ᵅ", "β": "ᵝ", "θ": "ᶿ",
}
# Small high marks that are punctuation, not exponents.
PUNCTUATION = set("'\"`,.")


def choose(model, vision, length, is_math, dictionary):
    """model: [(text, log P)], vision: [(text, log P under the model or None)]."""
    if not model:
        return vision[0][0] if vision else ""
    n = max(length, 1)
    best, best_value = model[0][0], -math.inf
    for text, s in list(model) + list(vision):
        if s is None:
            continue
        value = s / n + (0.0 if is_math else DICT_WEIGHT * dictionary(text))
        if value > best_value:
            best, best_value = text, value
    return best


def raised_text(text):
    if text and all(c in PUNCTUATION for c in text):
        return text
    if text and all(c in SUPERS for c in text):
        return "".join(SUPERS[c] for c in text)
    return "^" + text


def insert_superscripts(text, char_x, raised):
    """text with each (group text, x) put after the last character left of x."""
    at = {}
    for group, gx in raised:
        if group:
            pos = sum(1 for x in char_x if x <= gx)
            at[pos] = at.get(pos, "") + raised_text(group)
    out = [at.get(0, "")]
    for i, c in enumerate(text):
        out.append(c + at.get(i + 1, ""))
    return "".join(out)
