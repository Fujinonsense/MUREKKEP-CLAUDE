"""Text the embedded voice reads: numbers, percentages and math written out as words (the voice
misreads Turkish digits and every math symbol), and long texts cut at sentence ends."""
import re

from ports.speech import chunks, spoken_math, turkish_number


def test_turkish_numbers():
    assert [turkish_number(n) for n in (0, 11, 105, 1250, 2_000_000, 2026)] == [
        "sıfır", "on bir", "yüz beş", "bin iki yüz elli", "iki milyon", "iki bin yirmi altı"]


def test_turkish_math_is_spoken():
    assert spoken_math("x² + 3x = 10, %25, π", english=False) == "iks kare artı üç iks eşittir on, yüzde yirmi beş, pi"


def test_turkish_sentences_with_numbers():
    assert spoken_math("Bu sınavda 1.250 öğrenci vardı ve %25'i 3,5 saatte bitirdi.", english=False) == (
        "Bu sınavda bin iki yüz elli öğrenci vardı ve yüzde yirmi beşi üç virgül beş saatte bitirdi.")
    assert spoken_math("Sayfa 42'deki 7. soruda 2026 yılı soruluyor.", english=False) == (
        "Sayfa kırk ikideki yedinci soruda iki bin yirmi altı yılı soruluyor.")
    assert spoken_math("f(x) = x^2 - 4 ve saat 14:45", english=False) == "fe iks eşittir iks üssü iki eksi dört ve saat on dört kırk beş"
    assert spoken_math("Sıcaklık -5 derece, oran 0,05.", english=False) == "Sıcaklık eksi beş derece, oran sıfır virgül sıfır beş."


def test_english_math_is_spoken():
    assert spoken_math("Solve x² + 3x = 10 and find f(x) for π/2.", english=True) == (
        "Solve x squared plus 3 x equals 10 and find f of x for pi over 2.")


def test_words_are_left_alone():
    s = "Ödev: Kalkülüs-Giriş bölümünü oku; o da zor değil."
    assert spoken_math(s, english=False) == s


def test_chunks_keep_words_and_sentences():
    text = ("Türev, bir fonksiyonun anlık değişim oranıdır. " * 6
            + "Bu çok uzun bir cümle, " * 20 + "ve burada biter. Son cümle.")
    parts = chunks(text, 260)
    assert all(len(p) <= 260 for p in parts)
    assert " ".join(parts) == re.sub(r"\s+", " ", text).strip()
    assert parts[0].endswith(".")
