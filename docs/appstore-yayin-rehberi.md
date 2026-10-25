# Mürekkep'i App Store'da yayınlama rehberi

Bu rehber "Mürekkep AppStore" sürümünü (build 26) mağazaya çıkarmayı sırayla anlatır. Üç aşama var:

1. Yüklemeden önce kontrol.
2. Apple hesabı ve mağaza sayfası.
3. Yükleme ve incelemeye gönderme.

Uygulamanın içi hazır. Apple hesabı, para ve imza işlerini yalnızca sen yapabilirsin.

Toplam süre: hesap onayıyla birlikte 2–7 gün. Senin harcayacağın zaman yaklaşık 4 saat.

## Önce bil

- **Bu IPA imzasız.** CI'ın ürettiği IPA'yı App Store kabul etmez. App Store yalnızca senin Apple Developer hesabınla imzalanmış derlemeyi alır. Mac'in olmadığı için imzayı GitHub'daki CI atacak. Bunun için önce Aşama 2'deki anahtarlar gerekiyor.
- **Satın alma her kopyada çalışmaz.** Sideloadly ile yüklenen kopyada çalışmaz. TestFlight'ta deneme parasıyla, App Store'da gerçek parayla çalışır.

## Aşama 1: Yüklemeden önce kontrol

### 1.1 Otomatik kontrol (her App Store derlemesinde ben yapıyorum)

Komut: `python tools/appstore_check.py Murekkep-AppStore.ipa`. Şunlara bakar:

| Kontrol | Eksikse ne olur |
|---|---|
| Uygulama yalnızca iPad için mi? | iPhone işaretliyse Apple iPhone ekran görüntüsü ister ve iPhone'da dener. |
| 1024 px simge saydam değil mi? | Yükleme reddedilir (ITMS-90717). |
| Mikrofon gibi izinlerin açıklama metni var mı? | Yükleme reddedilir (ITMS-90683). |
| Gizlilik manifesti uygulamanın kullandığı API'leri kapsıyor mu? | Yükleme reddedilir (ITMS-91053). |
| Üç Pro ürünü uygulamanın içinde var mı? | Satın alma ekranı boş kalır. |
| Uygulamada unutulmuş API anahtarı var mı? | Anahtar sızar. |

Build 25 bu kontrolde 6 yerden takıldı. Build 26'da hepsi düzeltildi:
- Gizlilik manifesti eklendi.
- Uygulama yalnızca iPad için işaretlendi.

### 1.2 iPad'de 10 dakikalık kontrol (sen yapıyorsun)

1. Önemli defterlerini PDF olarak dışa aktar.
2. `Murekkep-AppStore-build26.ipa`'yı Sideloadly ile yükle. Bu sürüm kişisel sürümün yerine geçer ve notlar yerinde kalır. Kontrol bitince kişisel sürümü yeniden yükleyebilirsin.
3. Uygulamayı aç ve aşağıdaki listeyi sırayla dene:

| # | Ne yap | Ne görmelisin |
|---|---|---|
| 1 | Uygulamayı aç | Kitaplık düz "Kâğıt" arka planla açılır. |
| 2 | Ayarlar > Mürekkep Pro | Bugün kalan yapay zekâ cevabı 15, özet 1, çalışma seti 3 yazar. |
| 3 | "Mürekkep Pro'ya geç" | Ebru başlıklı ödeme ekranı açılır. Yıllık plan seçilidir, "7 gün ücretsiz" yazar. Fiyatlar ₺899,99 / ₺129,99 / ₺2.999,99. |
| 4 | "7 gün ücretsiz dene" | "Satın alma, Mürekkep App Store'dan yüklendiğinde çalışır." yazar. Bu kopyada beklenen bu; para çekilmez. |
| 5 | "Gizlilik" ve "Kullanım koşulları" | İkisi de açılır. |
| 6 | Ayarlar > Kitaplık arka planı | Düz renkler seçilir. Ebru ve diğer Pro arka planlarda kilit vardır; dokununca ödeme ekranı açılır. |
| 7 | Bir defter aç > tüm kalemler | 3D mürekkeplerde kilit vardır. Lav'a dokununca panel kapanır, ödeme ekranı açılır. |
| 8 | Bir kalemin kalbine dokun | O kalem kalem çubuğunun başına gelir. |
| 9 | Yeni defter > şablonlar | Haftalık ve CV kilitlidir; Çizgili ve Kareli açıktır. |
| 10 | Yapay zekâya bir soru sor | Cevap gelir; Ayarlar'da kalan cevap 14 olur. |
| 11 | Uçak modunda aç | Uygulama çökmeden açılır. |

Bir şey farklıysa ekran görüntüsünü bana at.

## Aşama 2: Apple hesabı ve mağaza

### 2.1 Apple Developer Program üyeliği (yaklaşık 30 dk, onay 1–2 gün)

**Durum (25 Ekim 2026):** üyelik alındı. Apple'ın onay e-postası gelince 2.2'ye geç.

1. https://developer.apple.com/programs/enroll/ adresinden "Bireysel" (Individual) olarak üye ol.
2. Yıllık ücret 99 ABD doları; Apple bazı ülkelerde yerel fiyat gösterir.
3. Apple kimliğini doğrulayınca e-posta gelir.

### 2.2 Sözleşme, vergi ve banka (yaklaşık 30 dk)

Bunlar olmadan abonelik satılamaz.

1. App Store Connect > **İş (Business)** bölümüne gir.
2. **Ücretli Uygulamalar Sözleşmesi**'ni (Paid Apps Agreement) kabul et.
3. Banka hesabını ekle (IBAN; TL hesabı olabilir).
4. Vergi formunu doldur. ABD dışındaki bireyler için bu W-8BEN formudur.
5. **AB "trader" beyanı** (App Store Connect > İş): AB'de satış için zorunlu. Trader olarak beyan edersen adresin, telefonun ve e-postan AB mağaza sayfasında herkese açık görünür. İki yol var: ayrı bir telefon ve posta kutusu kullan, ya da AB ülkelerini ilk sürümde satış listesinden çıkar ve sonra ekle. Ayrıntı: `Downloads\Murekkep-reklam\globale-acilma-plani.md`, bölüm 7.
6. Türkiye'de vergi (GVK 20/B istisnası ve ayrı banka hesabı) için bir mali müşavire danış.

### 2.3 İmza anahtarları (yaklaşık 20 dk)

Anahtarları bana yazma. Onları yalnızca sen GitHub'a "secret" olarak gireceksin.

**Durum (25 Ekim 2026):** Team ID `DW66Y98N3Z`. App Store sürümünün kimliği **`com.murekkep.notebook`** ("Murekkep App Store"); In-App Purchase ve Increased Memory Limit açık, kaydedildi. Kişisel sürüm `com.murekkep.app` olarak kalır, böylece ikisi aynı iPad'de yan yana kurulabilir. Swift Playgrounds'un kendiliğinden açtığı `com.murekkep.app.DW66Y98N3Z` kullanılmıyor. CI'ın App Store derlemesi `PRODUCT_BUNDLE_IDENTIFIER` olarak `com.murekkep.notebook` ve sürüm 1.0 kullanıyor (a3227a1).

1. **Bundle ID seç.** `com.murekkep.app` başkasına ait olabilir. Sana özel bir kimlik seç, örneğin `com.<soyadın>.murekkep`.
2. developer.apple.com > Certificates, IDs & Profiles > **Identifiers** sayfasında bu Bundle ID'yi oluştur. "In-App Purchase" zaten açık gelir. Capabilities listesinde **Increased Memory Limit**'i de işaretle; yapay zekâ modeli iPad'in belleğine ancak bununla sığar.
3. App Store Connect > Kullanıcılar ve Erişim > **Entegrasyonlar > App Store Connect API** sayfasında **Admin** yetkili bir anahtar oluştur (App Manager yetmiyor: Apple bulut imzasını yalnız Admin anahtarına veriyor). `.p8` dosyasını indir, Key ID ile Issuer ID'yi not et.
**Durum (25 Ekim 2026):** App Store Connect API erişimi onaylandı; "Murekkep CI" adlı App Manager anahtarı oluşturuldu. Üç secret **Fujinonsense/MUREKKEP-CLAUDE** deposuna girildi (CI bu depoda çalışıyor; Fujibonita eski depo). `.p8` dosyası yalnız bir kez indirilebilir; kullanıcı saklıyor.

4. GitHub'da MUREKKEP-CLAUDE > Settings > Secrets and variables > Actions sayfasına üç secret ekle:
   - `ASC_KEY_ID`
   - `ASC_ISSUER_ID`
   - `ASC_KEY_P8`: `.p8` dosyasının içeriği.
5. Bana iki şey yaz: Team ID ve Bundle ID. Team ID'yi developer.apple.com > Membership sayfasında bulursun; 10 harf ve rakamdan oluşur ve gizli değildir.
6. Ben CI'a "imzala ve TestFlight'a yükle" adımını eklerim. Sertifika ve profil API anahtarıyla kendiliğinden oluşur. İlk denemede ufak bir hata çıkabilir; düzeltip yeniden çalıştırırım.
**Durum (25 Ekim 2026):** adım yazıldı ve Fujinonsense'e gönderildi (a3227a1), henüz hiç çalıştırılmadı. Çalıştırmak için: Actions > Murekkep IPA Builder > Run workflow > `edition: appstore`, `testflight` kutusu işaretli. İmzasız arşiv alır, bellek izniyle ad hoc imzalar, Apple'ın bulutta tuttuğu dağıtım sertifikasıyla API anahtarı üzerinden dışa aktarır ve TestFlight'a yükler. Her yüklemenin build numarası 100 + çalıştırma numarası olur. Apple bulut imzasını App Manager anahtarına vermeyebilir; hata "cloud signing permission" derse Admin yetkili yeni bir anahtar oluşturulur, `ASC_KEY_ID` ve `ASC_KEY_P8` güncellenir (`ASC_ISSUER_ID` aynı kalır).
**Durum (25 Ekim 2026, iki deneme):**
- Run 40204167042: arşiv tamam, dışa aktarma `invalidPEMDocument` ile düştü. Secret'ta yalnız anahtarın gövdesi vardı (BEGIN/END satırları yoktu). `tools/asc_key.py` artık her yapıştırmayı katı PEM'e çeviriyor ve anahtarı build'den önce Apple'a soruyor (8ae2330).
- Run 40207308022: anahtar Apple'da çalıştı ("Mürekkep, Apple ID 6826858468"), arşiv tamam, dışa aktarma `Cloud signing permission error` ile düştü. App Manager anahtarı bulut imzasına yetmiyor.
- Admin anahtarı "Murekkep CI Admin" (Key ID `7T62YL32F2`) oluşturuldu; `ASC_KEY_ID` ve `ASC_KEY_P8` güncellendi. Eski App Manager anahtarı `CUP7X4WHX8` artık kullanılmıyor.
- **Run 40216278389: TestFlight'a yüklendi.** Build **1.0 (109)**, 25 Ekim 21:49'da App Store Connect'te "Processing". Toplam yaklaşık 85 dk sürdü (Intel Mac'te derleme 38 dk, arşiv ve yükleme 44 dk).

### 2.4 Uygulama kaydı (yaklaşık 20 dk)

**Durum (25 Ekim 2026):** kayıt açıldı. Ad **Mürekkep**, Apple ID `6826858468`, SKU `murekkep-001`, Bundle ID `com.murekkep.notebook`, birincil dil English (U.S.), kategori Eğitim + Verimlilik. Sürüm 1.0, "Prepare for Submission".

1. App Store Connect > Uygulamalar > **+ Yeni Uygulama** sayfasını aç:
   - platform: iOS,
   - Bundle ID: 2.3'teki kimlik,
   - SKU: `murekkep-001`.
2. Ad olarak "Mürekkep" alınmışsa "Mürekkep: Not ve PDF" gibi bir ad dene.
3. Birincil dil **English (U.S.)**, kategori **Eğitim** (ikincisi Verimlilik). Türkçe'yi ayrıca yerelleştirme olarak ekle. Küresel plana göre birincil dil İngilizce olmalı; Türkçe kalırsa çevirisi olmayan ülkelerde Türkçe sayfa çıkabilir. İngilizce ad, alt başlık ve anahtar kelime taslakları planın 4. bölümünde.

### 2.5 Abonelikler ve ömür boyu satın alma (yaklaşık 40 dk)

Ürün kimlikleri koddakilerle harfi harfine **aynı** olmalı.

1. Uygulama > **Abonelikler** sayfasında "Mürekkep Pro" adlı bir abonelik grubu oluştur.
2. Gruba iki abonelik ekle:

   | Ürün kimliği | Süre | Türkiye | ABD |
   |---|---|---|---|
   | `murekkep.pro.monthly` | 1 ay | ₺129,99 | $3.99 |
   | `murekkep.pro.yearly` | 1 yıl | ₺899,99 | $24.99 |

3. Yıllık aboneliğe **Tanıtım Teklifi** ekle: "Ücretsiz", 1 hafta, yeni aboneler için. Ödeme ekranındaki "7 gün ücretsiz" yazısı bu teklife bağlı.
4. Uygulama İçi Satın Almalar > **Tüketilemeyen** (Non-Consumable) ürün ekle: `murekkep.pro.lifetime`, ₺2.999,99 / $79.99.
5. Her ürüne Türkçe ve İngilizce görünen ad ve kısa açıklama yaz:
   - Ad örneği: "Mürekkep Pro – Aylık".
   - Açıklama örneği: "Sınırsız yapay zekâ, 3D mürekkepler, yaratıcı arka planlar."
6. Her ürüne bir inceleme ekran görüntüsü ekle. Ödeme ekranının fotoğrafı yeter.
7. Apple'da tam bu fiyat yoksa en yakın fiyat basamağını seç. Uygulama App Store'un gösterdiği fiyatı kendiliğinden yazar.

Ekim 2026 App Store Türkiye fiyatlarıyla karşılaştırma:

| Uygulama | Fiyat |
|---|---|
| Goodnotes Pro | ₺1.369,99/yıl, yapay zekâ için ayrıca ₺379/ay |
| Notability Plus | ₺599,99/yıl |
| Notability Pro | ₺4.499,99/yıl |
| Noteshelf | ₺999,99/yıl |

- Yıllık Mürekkep Pro Goodnotes Pro'dan %34 ucuz.
- Ömür boyu plan 3,3 yıllık abonelik fiyatına eşit ve Notability Pro'nun bir yılından ucuz.

### 2.6 Gizlilik (yaklaşık 20 dk)

1. Gizlilik politikası için **herkese açık bir adres** gerekli. Depo gizli olduğu için oradan olmaz.
   - `docs/gizlilik-politikasi.md` metnine iletişim e-postanı yaz.
   - Metni açık bir Notion sayfasına ya da GitHub Pages'e koy.
   - Adresi App Store Connect > Uygulama Gizliliği'ne yaz.
2. "Uygulama Gizliliği" anketinde **Veri Toplanmıyor** seç. Uygulamanın sunucusu, hesabı, reklamı ve analitiği yok.
3. Açıklamanın sonuna şu satırı ekle: "Kullanım Koşulları: https://www.apple.com/legal/internet-services/itunes/dev/stdeula/".
4. Yaş derecelendirmesi anketini dürüst doldur. Uygulamada yapay zekâ sohbeti ve Wikipedia araması var.

### 2.7 Mağaza sayfası (yaklaşık 1 saat)

1. **Ekran görüntüleri:**
   - En az 3 tane.
   - Boyut 13" iPad için 2064×2752 (dikey) ya da 2752×2064 (yatay).
   - Önerilen ekranlar: kitaplık (ebru arka planla), el yazısıyla not, metin kalemi, yapay zekâ cevabı, video özet.
2. **Altyazı** (en fazla 30 karakter): "El yazısı not, PDF ve yapay zekâ".
3. **Anahtar kelimeler**: not,pdf,el yazısı,ders,yks,öğrenci,kalem,ipad,çalışma.
4. **İnceleme notu** (Apple'ın incelemecisine): "Giriş yok. Yapay zekâ modeli (Qwen3.5, 2–6 GB) ilk açılışta internetten (Wi‑Fi ya da mobil veri) Hugging Face'ten indirilir ve iPad'de çalışır. Ücretsiz planda günde 15 cevap var; Pro'yu test etmek için yıllık plandaki 7 günlük deneme kullanılabilir. Arka planda ses: ders kaydı ve sesli özetler uygulama arka plandayken de sürer."

## Aşama 3: Yükleme ve gönderme

1. **TestFlight'a yükleme (benim adımım).** CI derler, imzalar ve TestFlight'a yükler. App Store Connect'te build 15–30 dakikada "İşleniyor"dan "Test Edilebilir"e geçer.
2. **TestFlight'ı kur.** iPad'e TestFlight uygulamasını kur. App Store Connect > TestFlight > Dahili Test bölümünde kendini test eden olarak ekle ve daveti kabul et.
   **Durum (25 Ekim 2026):** dahili grup **Murekkep Ekibi** kuruldu, otomatik dağıtım açık: CI'ın her yeni yüklemesi gruba kendiliğinden düşer. Test eden: orsyureky@gmail.com (davet gönderildi). Build 1.0 (109) "Ready to Test".
3. **Deneme hesabı aç.** App Store Connect > Kullanıcılar ve Erişim > Sandbox sayfasında bir deneme hesabı oluştur. Sonra iPad'de Ayarlar > App Store > **Sandbox hesabı** ile giriş yap. Deneme satın almaları para çekmez.
4. **TestFlight kontrolü** (yaklaşık 15 dk):
   - Aylık plan satın alınıyor ve Pro açılıyor mu? Kilitler kalkmalı, arka planlar seçilebilmeli.
   - Yıllık planda 7 günlük deneme görünüyor mu?
   - Ömür boyu plan satın alınıyor mu?
   - Uygulamayı silip yeniden yükle: "Satın alımları geri yükle" Pro'yu geri getiriyor mu?
   - Ayarlar > Mürekkep Pro > "Aboneliği yönet" Apple'ın abonelik sayfasını açıyor mu?
5. **Ürünleri sürüme bağla.** Sürüm sayfasındaki "Uygulama İçi Satın Almalar ve Abonelikler" bölümüne üç ürünü ekle. İlk sürümle birlikte gönderilmeleri şart.
6. **Build'i seç.** Sürüm sayfasında TestFlight'ta denediğin build'i seç.
7. **İncelemeye Gönder.** İnceleme genelde 1–2 gün sürer. Reddedilirse Apple sebebi yazar; bana at, düzeltelim.
8. **Yayınla.** Onaylanınca "Yayınla"ya bas ya da otomatik yayını seç.

## Uygulamanın içinde hazır olanlar

- **Ödeme ekranı:**
  - Ebru başlık ve 3 plan. Yıllık plan seçili gelir; 7 günlük deneme ve "%42 daha ucuz" yazar.
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
- **Gizlilik manifesti** (`PrivacyInfo.xcprivacy`): izleme yok, veri toplama yok. Kullanılan API'lerin gerekçeleri yazılı.
- **Kişisel sürüm** (`Murekkep.ipa`): her şey açık, satış yok.
