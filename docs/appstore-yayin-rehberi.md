# Mürekkep'i App Store'da yayınlama rehberi

Bu rehber "Mürekkep AppStore" IPA'sını (build 25) mağazaya çıkarmak için senin yapman gerekenleri sırayla anlatır. Uygulamanın içindeki her şey hazır. Kalan adımlar Apple hesabı, para ve imza işleri; bunları yalnızca sen yapabilirsin.

Toplam süre: hesap onayıyla birlikte 2–7 gün. Senin harcayacağın zaman yaklaşık 3–4 saat.

## Önce bil: neden bu IPA'yı doğrudan yükleyemiyoruz

- CI'ın ürettiği IPA **imzasız**. App Store yalnızca senin Apple Developer sertifikanla imzalanmış bir derlemeyi kabul eder.
- Sideloadly ile yüklenen kopyada **satın alma çalışmaz**. Abonelikler yalnızca TestFlight'ta (deneme parası) ve App Store'da çalışır. Ödeme ekranı yine açılır ve tahmini fiyatları gösterir.
- Mac'in yok. İmzayı GitHub'daki CI yapabilir: aşağıdaki 3. adımdaki anahtarları oluşturunca imzalama ve yükleme adımını workflow'a ben eklerim.

## 1. Apple Developer Program üyeliği (yaklaşık 30 dk, onay 1–2 gün)

1. https://developer.apple.com/programs/enroll/ adresinden "Bireysel" (Individual) olarak üye ol.
2. Yıllık ücret 99 ABD doları; Apple bazı ülkelerde yerel fiyat gösterir.
3. Apple kimliğini doğrulayınca e-posta gelir.

## 2. Sözleşme, vergi ve banka (yaklaşık 30 dk)

Bunlar olmadan abonelik satılamaz.

1. App Store Connect > **İş (Business)** bölümüne gir.
2. **Ücretli Uygulamalar Sözleşmesi**'ni (Paid Apps Agreement) kabul et.
3. Banka hesabını (IBAN, TL hesabı olabilir) ekle.
4. Vergi formunu doldur. ABD dışındaki bireyler için bu W-8BEN formudur.

## 3. İmza anahtarları (yaklaşık 20 dk)

Bu adımda anahtar oluşturuyorsun. Anahtarları bana yazma; yalnızca GitHub'a "secret" olarak sen gireceksin.

1. **Bundle ID seç.** `com.murekkep.app` başkasına ait olabilir. `com.<soyadın>.murekkep` gibi sana özel bir kimlik seç ve bana yaz; workflow'u ona çeviririm.
2. developer.apple.com > Certificates, IDs & Profiles > **Identifiers** sayfasından bu Bundle ID'yi oluştur. "In-App Purchase" zaten açık gelir.
3. App Store Connect > Kullanıcılar ve Erişim > **Entegrasyonlar > App Store Connect API**: "App Manager" yetkili bir anahtar oluştur. `.p8` dosyasını indir; Key ID ve Issuer ID'yi not et.
4. GitHub'da MUREKKEP-CLAUDE > Settings > Secrets and variables > Actions sayfasında üç secret ekle: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8` (`.p8` dosyasının içeriği).
5. developer.apple.com > Membership sayfasındaki **Team ID**'yi (10 harf/rakam; gizli değil) ve seçtiğin Bundle ID'yi bana yaz, "anahtarlar girildi" de. Sertifika ve profil, API anahtarıyla CI'da kendiliğinden oluşturulur. CI derler, imzalar ve TestFlight'a yükler.

## 4. Uygulama kaydı (yaklaşık 20 dk)

1. App Store Connect > Uygulamalar > **+ Yeni Uygulama**: platform iOS, Bundle ID 3. adımdaki kimlik, SKU `murekkep-001`.
2. Ad olarak "Mürekkep" alınmışsa "Mürekkep: Not ve PDF" gibi bir ad dene.
3. Birincil dil Türkçe, kategori **Eğitim** (ikincisi Verimlilik).

## 5. Abonelikler ve ömür boyu satın alma (yaklaşık 40 dk)

Ürün kimlikleri koddakilerle **aynı** olmalı, harfi harfine.

1. Uygulama > **Abonelikler** sayfasında "Mürekkep Pro" adlı bir abonelik grubu oluştur.
2. Gruba iki abonelik ekle:

   | Ürün kimliği | Süre | Türkiye | ABD |
   |---|---|---|---|
   | `murekkep.pro.monthly` | 1 ay | ₺129,99 | $3.99 |
   | `murekkep.pro.yearly` | 1 yıl | ₺899,99 | $24.99 |

3. Yıllık aboneliğe **Tanıtım Teklifi** ekle: "Ücretsiz", 1 hafta, yeni aboneler için. Ödeme ekranında "7 gün ücretsiz" bu teklife bağlı.
4. Uygulama İçi Satın Almalar > **Tüketilemeyen** (Non-Consumable) ürün ekle: `murekkep.pro.lifetime`, ₺2.999,99 / $79.99.
5. Her ürüne Türkçe ve İngilizce görünen ad ve kısa açıklama yaz. Örnek ad: "Mürekkep Pro – Aylık". Örnek açıklama: "Sınırsız yapay zekâ, 3D mürekkepler, yaratıcı arka planlar."
6. Her ürüne bir inceleme ekran görüntüsü ekle: TestFlight'taki ödeme ekranının fotoğrafı yeter.
7. Apple'da tam bu fiyat yoksa en yakın fiyat basamağını seç. Uygulama App Store'un gösterdiği fiyatı kendiliğinden yazar.

Bu fiyatlar piyasanın altında, Ekim 2026 App Store Türkiye fiyatlarıyla:

| Uygulama | Fiyat |
|---|---|
| Goodnotes Pro | ₺1.369,99/yıl, yapay zekâ ayrıca ₺379/ay |
| Notability Plus | ₺599,99/yıl |
| Noteshelf | ₺999,99/yıl |

## 6. Gizlilik (yaklaşık 20 dk)

1. Gizlilik politikası için **herkese açık bir adres** gerekli; depo gizli olduğu için oradan olmaz. `docs/gizlilik-politikasi.md` metnini açık bir Notion sayfasına ya da GitHub Pages'e koy. Adresi App Store Connect > Uygulama Gizliliği'ne yaz.
2. "Uygulama Gizliliği" anketinde **Veri Toplanmıyor** seç. Uygulamanın sunucusu, hesabı, reklamı ve analitiği yok. Notlar iPad'de kalıyor, yapay zekâ iPad'de çalışıyor.
3. Açıklamanın sonuna şu satırı ekle: "Kullanım Koşulları: https://www.apple.com/legal/internet-services/itunes/dev/stdeula/".

## 7. Mağaza sayfası (yaklaşık 1 saat)

1. **Ekran görüntüleri** gerekiyor: 13" iPad için 2064×2752 (dikey) ya da 2752×2064 (yatay), en az 3 tane. Önerilen ekranlar: kitaplık (ebru arka plan), el yazısıyla not, metin kalemi, yapay zekâ cevabı, video özet.
2. **Altyazı** (en fazla 30 karakter): "El yazısı not, PDF ve yapay zekâ".
3. **Anahtar kelimeler**: not,pdf,el yazısı,ders,ygs,yks,öğrenci,kalem,ipad,çalışma.
4. **İnceleme notu** (Apple'ın incelemecisine): "Giriş yok. Yapay zekâ modeli (Qwen3.5, 2–6 GB) ilk açılışta Wi‑Fi'de Hugging Face'ten indirilir ve iPad'de çalışır. Ücretsiz planda günde 15 cevap var; Pro'yu test etmek için yıllık plandaki 7 günlük deneme kullanılabilir."

## 8. TestFlight ve gönderme

1. CI build'i TestFlight'a yükleyince iPad'e **TestFlight** uygulamasını kur ve davet bağlantısını aç.
2. iPad Ayarlar > App Store > **Sandbox hesabı** ile giriş yap. Deneme satın almaları para çekmez.
3. Kontrol listesi:
   - Aylık plan satın alınıyor mu?
   - Yıllık planda 7 günlük deneme görünüyor mu?
   - Ömür boyu satın alınıyor mu?
   - "Satın alımları geri yükle" çalışıyor mu?
   - Kilitli 3D mürekkep ödeme ekranını açıyor mu?
4. Sürüm sayfasında "Uygulama İçi Satın Almalar ve Abonelikler" bölümüne üç ürünü ekle. İlk sürümle birlikte gönderilmeleri şart.
5. **İncelemeye Gönder**. İnceleme genelde 1–2 gün sürer.

## Uygulamanın içinde hazır olanlar

- **Ödeme ekranı:**
  - Ebru başlık ve 3 plan; yıllık plan seçili gelir, 7 günlük deneme ve "%42 daha ucuz" yazar.
  - Otomatik yenileme metni (Apple kuralı 3.1.2).
  - Geri yükle, Kullanım koşulları ve Gizlilik bağlantıları.
- **Ücretsiz plan:**
  - Defter, PDF, kalemler, metin kalemi ve öğrenci şablonları sınırsız.
  - Günde 15 yapay zekâ cevabı, haftada 1 özet ve 3 çalışma seti.
  - Düz renk arka planlar.
- **Pro:**
  - Sınırlar kalkar.
  - 10 adet 3D mürekkep.
  - Planlayıcı, CV ve özel şablonlar.
  - Ebru ve hareketli arka planlar.
- **Ayarlar > Mürekkep Pro:** durum, kalan haklar, geri yükleme, abonelik yönetimi ve gizlilik.
- **Kişisel sürüm** (Murekkep.ipa): her şey açık, satış yok.
