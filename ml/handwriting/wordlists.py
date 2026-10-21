"""Turkish and English word and phrase lists for the font-image generator, from the Tatoeba sentences
the trainer already uses (MRK_DATA/text): words Turkish students write, with the letters Latin
handwriting gets wrong most (ç ğ ı İ ö ş ü) well represented, and short phrases of up to 32 characters.
Every character is one the model can write.

usage: python wordlists.py   (writes MRK_DATA/text/{words,phrases}_{tr,en}.txt)"""
import collections
import re

import texts
from charset import CHARSET

ALLOWED = set(CHARSET)
TURKISH = set("çğıİöşüÇĞÖŞÜ")
WORD = re.compile(r"[^\W\d_]+(?:'[^\W\d_]+)?")


def build(lang, min_count, words_wanted, phrases_wanted):
    counts = collections.Counter()
    phrases = []
    for s in texts.sentences(lang):
        for w in WORD.findall(s):
            if len(w) >= 2 and all(c in ALLOWED for c in w):
                counts[w] += 1
        if 6 <= len(s) <= 32 and all(c in ALLOWED for c in s):
            phrases.append(s)
    words = [w for w, n in counts.most_common() if n >= min_count]
    if lang == "tr":
        # Words with Turkish letters first, so every letter comes up often.
        words = [w for w in words if TURKISH & set(w)] + [w for w in words if not TURKISH & set(w)]
        phrases = [p for p in phrases if len(TURKISH & set(p)) >= 2] + [p for p in phrases if len(TURKISH & set(p)) < 2]
    seen, unique = set(), []
    for p in phrases:
        if p not in seen:
            seen.add(p)
            unique.append(p)
    return words[:words_wanted], unique[:phrases_wanted]


def main():
    for lang in ("tr", "en"):
        words, phrases = build(lang, min_count=3, words_wanted=30_000, phrases_wanted=60_000)
        (texts.DATA / "text" / f"words_{lang}.txt").write_text("\n".join(words) + "\n", encoding="utf-8")
        (texts.DATA / "text" / f"phrases_{lang}.txt").write_text("\n".join(phrases) + "\n", encoding="utf-8")
        tr_share = sum(bool(TURKISH & set(w)) for w in words) / max(len(words), 1)
        print(f"{lang}: {len(words)} words ({tr_share:.0%} with Turkish letters), {len(phrases)} phrases")


if __name__ == "__main__":
    main()
