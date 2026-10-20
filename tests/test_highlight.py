"""Highlighted words of a slide question ("**anlık hızını**"), and the overview's accent colour."""
from ports.highlight import ACCENTS, accent_index, parse


def test_highlight_ranges_utf16():
    text, ranges = parse("Şampiyonun **anlık hızını** nasıl buluruz?")
    assert text == "Şampiyonun anlık hızını nasıl buluruz?"
    assert ranges == [(11, 12)]
    assert text[11:23] == "anlık hızını"


def test_two_highlights_and_emoji_offsets():
    text, ranges = parse("🙂 **a** ve **bc**")
    assert text == "🙂 a ve bc"
    # UTF-16: the emoji takes two units.
    assert ranges == [(3, 1), (8, 2)]


def test_unmatched_markers_dropped():
    text, ranges = parse("Bir **soru mu?")
    assert text == "Bir soru mu?"
    assert ranges == []


def test_accent_is_stable():
    assert accent_index("Anın Gücü: Kalkülüse Giriş") == accent_index("Anın Gücü: Kalkülüse Giriş")
    assert 0 <= accent_index("Functions") < len(ACCENTS)
    assert len({accent_index(t) for t in ["Functions", "Türev", "Limit", "Süreklilik", "Matrisler", "Olasılık"]}) >= 2
