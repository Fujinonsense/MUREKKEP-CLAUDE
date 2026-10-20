"""Splitting a page into its questions, so the small on-device model can solve one at a time."""
from ports.questions import split

YKS = """TÜRKÇE TESTİ
1. Aşağıdaki cümlelerin hangisinde yazım yanlışı vardır?
A) Herkes bu konuda hem fikirdi.
B) Toplantı saat üçte başladı.
C) Bu kitabı da okudum.
D) Yarın sınav var mı?
E) Sen de gel.
2. "Göz" sözcüğü aşağıdakilerin hangisinde mecaz anlamda kullanılmıştır?
A) Gözleri yorulmuştu.
B) Çantanın gözüne koydu.
C) Gözünü kırptı.
D) Göz doktoruna gitti.
E) Gözlüğünü taktı.
3. Bir sayının 3 katının 5 fazlası 20'dir. Bu sayı kaçtır?
A) 3 B) 4 C) 5 D) 6 E) 7
"""


def test_numbered_questions_with_five_options():
    qs = split(YKS)
    assert [q.number for q in qs] == [1, 2, 3]
    assert all([o.letter for o in q.options] == list("ABCDE") for q in qs)
    assert qs[0].stem == "Aşağıdaki cümlelerin hangisinde yazım yanlışı vardır?"
    assert qs[0].options[0].text == "Herkes bu konuda hem fikirdi."
    assert qs[2].options[2].text == "5"


def test_glued_options_split():
    q = split("7. 2x + 6 = 30 ise x kaçtır?\nA) 12 B) 15 C) 18 D) 21 E) 24")[0]
    assert [(o.letter, o.text) for o in q.options] == [("A", "12"), ("B", "15"), ("C", "18"), ("D", "21"), ("E", "24")]


PASSAGE = """3. - 5. soruları aşağıdaki parçaya göre cevaplayınız.
Kitap okumak insanın hayal gücünü geliştirir. Okuyan kişi başkalarının hayatlarını yaşar,
farklı düşünceleri tanır ve kendi fikirlerini sorgular. Bu yüzden okumak bir yolculuktur.
3. Bu parçada asıl anlatılmak istenen nedir?
A) Okumanın yararları B) Yazarların hayatı C) Kütüphaneler D) Yolculuklar E) Hayal gücünün sınırları
4. Parçada hangisine değinilmemiştir?
A) Hayal gücü B) Düşünceler C) Sorgulama D) Kitap fiyatları E) Yolculuk
5. Parçaya göre okuyan kişi ne yapar?
A) Uyur B) Başkalarının hayatlarını yaşar C) Koşar D) Yazar olur E) Susar
6. 12 ile 18'in en büyük ortak böleni kaçtır?
A) 2 B) 3 C) 4 D) 6 E) 9
"""


def test_passage_attached_to_range():
    qs = split(PASSAGE)
    assert [q.number for q in qs] == [3, 4, 5, 6]
    for q in qs[:3]:
        assert q.passage.startswith("Kitap okumak insanın hayal gücünü geliştirir.")
        assert q.passage.endswith("Bu yüzden okumak bir yolculuktur.")
    assert qs[3].passage is None
    assert qs[1].options[3].text == "Kitap fiyatları"


ENGLISH = """Questions 1-2 refer to the following passage.
Bees communicate the location of flowers through a dance. The angle of the dance shows the
direction of the food, and its length shows the distance.
1. What does the angle of the dance show?
(A) The distance (B) The direction (C) The colour (D) The season (E) The weather
2. According to the passage, how do bees communicate?
A. By sound
B. By dancing
C. By smell
D. By touch
E. By colour
"""


def test_english_questions_range():
    qs = split(ENGLISH)
    assert [q.number for q in qs] == [1, 2]
    assert qs[0].passage.startswith("Bees communicate")
    assert qs[0].options[1].text == "The direction"
    assert qs[1].options[1].text == "By dancing"


def test_ocr_l_as_one():
    qs = split("l. Which number is prime?\nA) 4 B) 6 C) 7 D) 9\n2. Which is even?\nA) 3 B) 5 C) 8 D) 11")
    assert [q.number for q in qs] == [1, 2]
    assert len(qs[0].options) == 4


def test_open_question_has_no_options():
    qs = split("1. Türevin tanımını yazınız.\n2. f(x) = x² ise f'(3) kaçtır?")
    assert [q.number for q in qs] == [1, 2]
    assert qs[0].options == [] and qs[1].options == []
    assert qs[1].stem == "f(x) = x² ise f'(3) kaçtır?"


def test_numbered_lines_inside_a_question_stay_in_it():
    qs = split("4. Aşağıdaki öncüllerden hangileri doğrudur?\n1. Kare bir dikdörtgendir.\n2. Üçgenin iç açıları 180'dir.\n"
               "A) Yalnız 1 B) Yalnız 2 C) 1 ve 2 D) Hiçbiri E) Bilinmez\n5. Sonraki soru?\nA) a B) b")
    assert [q.number for q in qs] == [4, 5]
    assert "Kare bir dikdörtgendir." in qs[0].stem


def test_no_questions_on_a_plain_page():
    assert split("Bu sayfada yalnızca düz bir metin var. Soru yok.") == []
