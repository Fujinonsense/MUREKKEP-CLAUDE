# Mürekkep — isteklerin tek tek kontrolü (build 23)

Durum işaretleri:
- ✅ **Ölçüldü**: kodda var ve burada testle ya da ölçümle doğrulandı (Python ikizi, Windows Swift veya uygulamanın kendi Swift dosyalarıyla).
- 🟡 **Kodda var**: yazıldı ve kanıtı kodda, ama ancak iPad'de görülüp hissedilebilir (görünüm, ses, akıcılık).
- ❌ **Yapılmadı**.

Hiçbir build'in (16–23) iPad derlemesi henüz CI'da yapılmadı: derleme kontrolü GitHub Actions'ta olur. Bunun için `gh auth login` gerekiyor.

Kanıt komutu: `py C:/Users/orsyu/mrk-ml/textpen/audit.py <repo>` → 50/50 istekte kodda kanıt bulundu.

## Metin kalemi

| # | İstek | Durum | Kanıt |
|---|---|---|---|
| 1 | TR/EN çirkin el yazısıyla eğit, normal ve 3D kalemde kusursuz | ✅ | Model CER %3.08 (önce %3.18). Uygulamanın kendi Swift'iyle 531 vakada tam okuma 376 (build 22: 361, satır düzeltmesinden önce 156). |
| 1b | Google Fonts el yazısı fontlarıyla sentetik veri üreteci | ✅ | 12 aile, 16 dosya indirildi. TR 30.000 kelime (%83'ünde ç ğ ı İ ö ş ü), EN 20.690. Pillow + SciPy elastik bozma. Eğitimin %30'u bu satırlardan. |
| 1c | Online HTR: kalem hareketinden okuma (dx, dy, sin, cos, kalem) | ✅ | Kinematik çizgi üreteci, nokta/çengeller kalem kaldırılıp sonradan. Swift = Python (fark ≤ 0.00012). Doğal kalem sırasıyla özensiz 400 satırda tam okuma 151 → 305. Font vakalarında kayıp yok (376 → 376). |
| 2 | ı → i, Ş → S, tırnak/virgül hataları | ✅ | Doğrulamada Türkçe harf doğruluğu %95.1. Sözlük onarımı (kucuk → küçük) testli. |
| 3 | Dönüşen kelimelerin yerleşimi | ✅ | Harf konumu CTC hizalamasından, `test_text_placement`. |
| 4 | Metin kalemindeyken sembol (kalp, daire) | ✅ | Kodda (L4). |
| 5 | 3D kalemlerde metin kalemi | ✅ | 2.6 pt kalem yarıçapı okumayı hiç değiştirmiyor (Swift harness). |
| 6b | Punto seçeneği | ✅ | `textScale`, `test_text_size`. |
| 7 | Metin kaleminde çift dokunma | 🟡 | Çift dokunma araca bakmadan çalışıyor (`handlePencilTap`). iPad'de denenmeli. |
| 10 | Üslü sayılar (x²) | ✅ | `splitRaised` + `insertSuperscripts`, testli. |

## Yapay zeka

| # | İstek | Durum | Kanıt |
|---|---|---|---|
| — | PC'siz, en iyi yerel model otomatik seçilsin | ✅ | iPad belleğine göre Qwen3.5 9B / 4B / 2B (MLX). |
| 8 | Cevap sorunun dilinde | ✅ | `test_answer_language`. |
| 9 | Prep school sözel ve matematik sorularını doğru çözsün | ✅ | Qwen3.5 4B, uygulamanın ayarlarıyla 40 YKS/YDS tarzı soruda 39/40. Tek hata cevap harfinin okunamamasıydı; düzeltildi, kayıtlı cevaplarla 40/40. Sayfadan soru okuma bu ölçümde yok. |
| — | Video ve sesli özeti de indirilen model yazsın | ✅ | `StudioWriter.brain`; yazamazsa Apple modeli, o da olmazsa çevrimdışı yazar. |

## Video ve sesli özet

| # | İstek | Durum | Kanıt |
|---|---|---|---|
| 12 | API anahtarı yok, sesler gömülü | ✅ | Supertonic sesler. Kodda ElevenLabs/OpenAI anahtar alanı yok. |
| 14 | "Okunabilir metin bulunamadı" yerine bölüm bölüm video | ✅ | `ChapterFinder`, taranmış sayfalar için OCR, `test_chapters`. |
| — | Tek dil, otomatik dil yok | ✅ | `OverviewLanguage` yalnızca Türkçe ve İngilizce. Sesler özetin dilinde. |
| — | Önemli ayarlar üstte, ekran büyük | 🟡 | Ayarlar en üstte "Temel ayarlar": Dil / Süre / Seviye. Sayfa boyutunda sayfa. |

## Kalemler, şekiller, kement

| # | İstek | Durum | Kanıt |
|---|---|---|---|
| 11 | Sekizgen vb. şekiller düzgün | ✅ | `test_sketch_rules`. |
| 13 | Kötü daire böbrek/dalak olmasın | ✅ | Kötü daire vakaları testli. |
| 23 | Kement seçerken kesikler kadar titreşim | ✅ | Kodda (L23). |
| 24 | Boşluğa dokununca tutamaçlar kapansın | 🟡 | Kodda: tek parmakla sayfaya dokunmak tutamaçları kapatıyor. |
| 25 | Kement sayfalar arası taşısın | ✅ | `test_lasso_pages`. |
| 26 | Sembol içinden tutularak taşınsın | 🟡 | Kodda: şekil herhangi bir yerinden tutulunca dokunuşla birlikte gidiyor. |
| 27 | Yay yerine parabol | ✅ | Testli. |
| 29 | Kalem seçici düzeni (doğa/sihirli ayrımı) | ✅ | `test_pen_sections`. Görünümü iPad'de. |
| 30 | Yıldırımın kalın modeli | ✅ | `test_lava_lightning`. |
| 31 | Lav ilk değdiği yerden kurusun | ✅ | `test_lava_lightning`. |
| — | 10 premium 3D mürekkep, lav→kor, basınçlı 3D dolma kalem | ✅ | Kodda (E5). |
| — | Çift dokununca araç menüsü (cetvel, kement, renk, silgi) | ✅ | Kodda (E7). |
| — | Kement döndürme 90°'de oturur | ✅ | Kodda: 7° içinde oturur ve titreşir. |

## PDF ve defter

| # | İstek | Durum | Kanıt |
|---|---|---|---|
| 6a | Sayfa numarasıyla git | ✅ | `test_page_navigation`. |
| 18 | Sayfa sonunda çekince yeni sayfa | 🟡 | Kodda (`pullToAddPage`, 90 pt). |
| 20 | Tek sayfa görünümü ve favori | ✅ | Kodda (L20). |
| 22 | Son kalınan sayfa | ✅ | Kodda (L22). |
| — | Çok sayıda şablon, CV dahil | ✅ | Kodda (E6). |

## Ses, görünüm, hız

| # | İstek | Durum | Kanıt |
|---|---|---|---|
| 15 | Yamukluk hazır seçenekleri kaymasın | 🟡 | Kodda (L15). |
| 16 | Aa: kağıt üstünde metin kutusu | 🟡 | Kodda (L16). |
| 17 | Kalem sesi gecikmesin, yazıya uysun | ✅ | `PenSoundEnvelope` testli. Kulağa nasıl geldiği iPad'de. |
| 28 | Her kaleme ses, müziği durdurmasın | ✅ | `mixWithOthers` + `.ambient`. |
| 19, 32 | 3D kalemlerde kasma, genel optimizasyon | 🟡 | 3D mürekkep katmanı ve mesh planı testli. Akıcılık iPad'de. |
| — | Eklentilerle daha güzel arayüz | 🟡 | Mürekkep-kağıt teması. Ancak iPad'de görülür. |
| 21 | Notability / Notion / NotebookLM'i geç | 🟡 | Ders kaydı, zoom penceresi, çalışma araçları, not içi arama, video özet var. Bitmeyen bir hedef. |

## Yapılmayan

- ❌ Android sürümü: sen vazgeçmiştin.
- ❌ CI derlemesi: `gh auth login` senin adımın.
