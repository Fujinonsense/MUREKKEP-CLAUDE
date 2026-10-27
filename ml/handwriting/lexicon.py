"""The text pen's word list (Assets.xcassets/wordlist.dataset/wordlist.txt, read by WordFix.swift and
tests/ports/wordfix.py): every word form of the Turkish and English Tatoeba sentences seen at least
twice, lowercased (Turkish words the Turkish way: I → ı, İ → i), with its count; most frequent first.
Only words the readers can write (CHARSET) go in. A word with an apostrophe counts as the part before it
(Ankara'da → ankara, Tom's → tom), never the suffix after it; an English "n't" word not at all (isn't
gives no "isn").

usage: python lexicon.py <out.txt>   (sentences from MRK_DATA/text/{tur,eng}_sentences.tsv)"""
import collections
import re
import sys

from charset import CHARSET
from texts import DATA

WORD = re.compile(r"[^\W\d_]+(?:['’][^\W\d_]+)*")
ALLOWED = set(CHARSET)
MIN_COUNT = 2


def lower_tr(w):
    return w.replace("I", "ı").replace("İ", "i").lower()


def lower_en(w):
    return w.replace("İ", "i").lower()


def counts(path, lower):
    c = collections.Counter()
    with open(path, encoding="utf-8") as f:
        for line in f:
            parts = line.rstrip("\n").split("\t")
            if len(parts) < 3:
                continue
            for token in WORD.findall(parts[2]):
                w = re.split("['’]", token)[0]
                if w != token and lower(token).endswith(("n't", "n’t")):
                    continue
                if all(ch in ALLOWED for ch in w):
                    c[lower(w)] += 1
    return c


def main():
    merged = counts(DATA / "text" / "tur_sentences.tsv", lower_tr)
    for w, n in counts(DATA / "text" / "eng_sentences.tsv", lower_en).items():
        merged[w] = max(merged[w], n)
    rows = sorted(((w, n) for w, n in merged.items() if n >= MIN_COUNT and len(w) >= 2), key=lambda r: (-r[1], r[0]))
    with open(sys.argv[1], "w", encoding="utf-8", newline="\n") as f:
        for w, n in rows:
            f.write(f"{w} {n}\n")
    print(len(rows), "words")


if __name__ == "__main__":
    main()
