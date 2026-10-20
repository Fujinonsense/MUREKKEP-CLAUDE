"""Port of Highlight and the explainer accent (Murekkep.swiftpm/SlideRenderer.swift).

"**…**" pairs mark the words a question slide highlights; the markers are removed and the ranges come
back in UTF-16 units (NSRange). A marker without a partner is dropped. The explainer look takes one
accent colour per overview, chosen by a 32-bit FNV-1a hash of the title's UTF-8 bytes."""

ACCENTS = ["#F28C28", "#1A73E8", "#0F9D58", "#8E44AD"]


def _u16(s):
    return len(s.encode("utf-16-le")) // 2


def parse(s):
    pieces = s.split("**")
    text, ranges = "", []
    for k, piece in enumerate(pieces):
        inside = k % 2 == 1 and k < len(pieces) - 1  # an odd piece is highlighted when its "**" closes
        if inside:
            ranges.append((_u16(text), _u16(piece)))
        text += piece
    return text, ranges


def accent_index(title):
    h = 0x811C9DC5
    for b in title.encode("utf-8"):
        h ^= b
        h = (h * 0x01000193) & 0xFFFFFFFF
    return h % len(ACCENTS)
