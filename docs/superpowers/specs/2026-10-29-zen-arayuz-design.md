# Zen arayüz: siyah beyaz ücretsiz, ultra premium temalar Pro

Tarih: 2026-10-29. Kaynak: kullanıcının "şu an AI slop gibi duruyor, daha zen bir tasarım" isteği,
hallmark ve impeccable becerileriyle hazırlanan ve kullanıcının onayladığı örnek
(Artifact "Mürekkep zen arayüz", https://claude.ai/artifact/8f7P33BhnTqzh7hpsJZDeT: Editör,
Editör kalem ayarı açık, Editör koyu, Kütüphane). Bu belge iPad (SwiftUI) ve Android (Compose)
için tek kaynaktır.

## Neden

Eski arayüzün yapay görünen yanları: kütüphanede selamlama ve dört sayı kartı, renkli geçişli
düğmeler (Defter, PDF, Kurs), seri kartı, 3B krom duvar kâğıdı; editörde mor geçişli Asistan
kapsülü, bir sıra mavi simge, sol araç rayı, cam kalem rafı. Zen hali: sayfa öne çıkar, araçlar
alçak ve sessiz durur, renk yalnızca mürekkepte ve seçili durumda görünür.

## Temalar ve Pro

- **Siyah beyaz** (ücretsiz, varsayılan): aşağıdaki token'lar; açık ve koyu sistem görünümünü izler.
  Duvar kâğıdı yok; kütüphane düz kâğıt.
- **Ultra premium** (Pro): her tema Higgsfield ile yapılmış bir görsel + kendi paleti (vurgu,
  yüzey, kenar). Mevcut premium arka planlar (Defter, Sıvı cam, İpek, Erimiş altın, Kâğıt dalgası,
  Oluklu, Ferro, Holo, Küreler, Işık boyası, İnci) Pro tema olur; yenileri Higgsfield ile birlikte
  seçilerek eklenir. Pro temalarda kalemler gerçekçi gövdelerle çizilir (iPad ToolArt).
- Eski ücretsiz renkli arka planlar (Fildişi, Kum, Adaçayı, Lavanta, Gece) ücretsiz listeden çıkar:
  ücretsiz olan siyah beyazdır (Gece'nin yerini koyu görünüm alır).
- Pro kilitliyken seçilmiş bir Pro tema siyah beyaza düşer (bugünkü `shownBackground(locked:)` gibi).
- Ayarlar › Görünüm › Tema: önce "Siyah beyaz", sonra Pro temaların önizlemeleri; kilitli olana
  dokunmak satın alma ekranını açar.

## Token'lar (siyah beyaz)

| Rol | Açık | Koyu |
| --- | --- | --- |
| paper (yüzeyler, raf) | oklch(99.5% 0.003 100) ≈ #FDFDFC | oklch(24% 0.006 260) ≈ #2A2B2E |
| paper-2 (çubuklar, kenar çubuğu) | oklch(97% 0.004 100) ≈ #F6F6F4 | oklch(20% 0.006 260) ≈ #202124 |
| paper-3 (zemin, seçili satır) | oklch(94% 0.006 100) ≈ #EDEDEA | oklch(15% 0.006 260) ≈ #151618 |
| ink (başlık, metin) | oklch(16% 0 0) ≈ #141414 | oklch(96% 0.005 260) ≈ #F2F3F5 |
| ink-2 (gövde metni, simgeler) | oklch(28% 0 0) ≈ #2E2E2E | oklch(87% 0.005 260) ≈ #D7D9DC |
| muted (ikincil metin) | oklch(44% 0 0) ≈ #565656 | oklch(72% 0.006 260) ≈ #A9ACB1 |
| rule (ince kenar) | oklch(89% 0.004 100) ≈ #DFDFDC | oklch(34% 0.006 260) ≈ #43454A |
| accent (seçim, odak, birincil durum) | #2457D6 (marka mürekkep mavisi) | #4D7BEA |

- Sayfanın kendisi her zaman kâğıttır (koyu görünümde de beyaz kalır); sayfa üstündeki yazılar
  `on-page` (#565656) ile yazılır.
- Gölge yalnızca yüzen şeyde (kalem rafı, açılır pencere, menü): 0 12 32 siyah %12 + 0 1 2 siyah %8.
  Duran yüzeyde gölge yok; cam/malzeme yok (Pro temalar görselin üstünde malzeme kullanabilir).
- Yazı: her yerde sistem yazısı (iPad SF Pro, Android Roboto). Başlıklar kalın sistem yazısı,
  sıkı aralık; tırnaklı (serif) başlık yok. Etiketler cümle düzeninde, harf aralığı açılmamış,
  büyük harf yok.
- Asistanın rengi geçiş değil: Asistan sade kenarlı bir düğme; AI yüzeyleri mürekkep mavisi düz.
- Köşe: kontroller 10, kartlar ve kapaklar 10–12, yüzen raf 18, açılır pencere 16.
- Simgeler: iPad SF Symbols (tek ağırlık, .medium), Android Material Symbols Outlined; emoji yok.

## Ekranlar

**Editör.** Üst çubuk paper-2 + alt kenar çizgisi: solda "‹ Notlar", ortada başlık, sağda
"Asistan" (kenarlı), Yakınlaştır, Paylaş, Diğer. Sayfa tam genişlik. Kalem rafı yüzen, altta
ortada (kenar ayarı korunur: üst/alt/sağ): Geri al, Yinele | 5 kalem (favoriler + son
kullanılanlar) + Metin kalemi + Silgi | renk dairesi | Kement, Şekiller, Araçlar (cetvel, pergel,
metin, çıkartma, tarama, f(x), sayfa) | Sayfa ekle. Sol ray kalkar, araçları raftaki "Araçlar"
menüsüne gider. Siyah beyazda kalemler düz silüet (ince çizgi gövde, mürekkep rengi bant, seçili
olan yukarı kalkar); Pro temalarda gerçekçi gövde. Sayfa sayacı sağ altta düz yazı "1 / 1".

**Kalem ayarı** (seçili kaleme tekrar dokununca veya renk dairesine): 320 genişlik açılır pencere:
kalemin adı, bir cümle açıklama, mürekkebin gerçek görüntüsü, Renk (6 renk + özel), Kalınlık,
kaleme özel ayarlar (Soğuma süresi, Çiçekler, Uç açısı...), animasyon anahtarı.

**Kütüphane / ana sayfa.** Kenar çubuğu (paper-2): "Mürekkep" yazısı, Ara, Tüm notlar,
Son açılanlar, Favoriler, Defterler, PDF'ler (sayılarıyla), Kurslar (+), altta Stüdyo, Sesler,
Ayarlar. Ana alan: "Tüm notlar" başlığı, sağda "PDF içe aktar" (kenarlı) ve "Yeni not" (dolu
siyah); Hepsi / Defterler / PDF'ler seçici, sıralama; notlar ilk sayfalarının kapağıyla 4 sütun,
altında başlık ve "3 sayfa, dün". Selamlama, sayı kartları, seri kartı, renkli düğmeler ve duvar
kâğıdı yok (Pro tema seçiliyse görsel kenar çubuğunun arkasında ve başlık alanında durur).

**Ayarlar.** Gruplu liste; Görünüm › Tema seçici (yukarıda).

## Platform notları

- iPad: Theme.swift token'ları ve glassCapsule/glassCard bu belgeye göre değişir (26 kullanım);
  ekranlar sırayla: kütüphane, editör üst çubuğu ve rafı, kalem ayarı, ayarlar, satın alma.
  Mac'te derlenemediği için değişiklikler Codemagic derlemesiyle doğrulanır (kullanıcı "Derle"
  deyince).
- Android: aynı token'lar Compose temasına (Theme.kt), aynı ekran düzeni; kalem silüetleri
  Compose çizimi; gerçekçi gövdeler (ToolArt.kt) Pro temalar için.
