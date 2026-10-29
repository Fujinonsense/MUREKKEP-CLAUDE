# Google Play: listing drafts and the steps that are yours

Drafts for the Android edition. Before you submit, check every line against what the build really
does: the Android app does not yet have everything the iPad app has (see `README.md`).

## What only you can do (account, money, identity)

1. **Open a Google Play Console developer account**: play.google.com/console, a one-time $25 fee
   and an identity check. A personal account opened after November 2023 must run a **closed
   test with at least 12 testers for 14 days in a row** before it can publish to everyone. A
   company account (with a D-U-N-S number) skips that.
2. **Create the app** in the console: name "Mürekkep", default language Turkish or English,
   App, Free (Pro inside the app comes later with Play Billing).
3. **Upload the signed bundle** (`.aab`) to the closed test track. The bundle is signed with the
   upload key in `%USERPROFILE%\.murekkep-android\` (never share it, never put it on GitHub);
   Play keeps the real app signing key ("Play App Signing").
4. Fill in the forms with the answers below, add 12+ testers (their Gmail addresses), wait 14
   days, then apply for production.

## Store listing

**App name** (30 characters at most)
- EN: Mürekkep: Handwriting Notes
- TR: Mürekkep: El Yazısı Notlar

**Short description** (80 at most)
- EN: A notebook made for your pen: 3D inks, pressure, palm rejection, no account.
- TR: Kalemle yazmak için yapılmış defter: 3B mürekkep, basınç, avuç reddi, hesapsız.

**Full description** (EN)

Mürekkep is a notebook made for writing by hand on your tablet.

• Pens that feel like ink: pressure and tilt shape every line, with the S Pen and other styluses.
• 3D inks: liquid gold, chrome, galaxy, ice, jelly, lava and more, raised off the page with soft shadows.
• Highlighter, pencil, fountain pen, calligraphy and watercolor.
• Erase whole strokes or just the part you touch. Hold the pen's side button to erase, let go to keep writing.
• Palm rejection: rest your hand on the screen while you write; fingers move and zoom the pages.
• Smooth on fast screens: up to 120 Hz on tablets that have it.
• Your notebooks stay on your device. No account, no ads.

**Full description** (TR)

Mürekkep, tablette elle yazmak için yapılmış bir defter.

• Mürekkep gibi hissettiren kalemler: basınç ve eğim her çizgiyi şekillendirir; S Pen ve diğer kalemlerle.
• 3B mürekkepler: sıvı altın, krom, galaksi, buz, jöle, lav ve daha fazlası, yumuşak gölgeleriyle sayfadan kabarır.
• Fosforlu kalem, kurşun kalem, dolma kalem, hat kalemi ve sulu boya.
• Bütün çizgiyi ya da sadece dokunduğun kısmı sil. Kalemin yan tuşunu basılı tut, sil; bırak, yazmaya devam et.
• Avuç içi reddi: yazarken elini ekrana koyabilirsin; parmaklar sayfaları kaydırır ve yakınlaştırır.
• Hızlı ekranlarda akıcı: destekleyen tabletlerde 120 Hz'e kadar.
• Defterlerin cihazında kalır. Hesap yok, reklam yok.

## Form answers

- **Data safety**: no data collected, no data shared; notebooks are stored only on the device.
- **Ads**: no ads.
- **Content rating** (IARC questionnaire): reference/productivity app, no violence, no user
  interaction with others, no purchases of digital goods yet → Everyone / PEGI 3.
- **Target audience**: 13 and older (not designed for children; this keeps the Families rules out).
- **Privacy policy URL**: the one the App Store listing uses.
- **App category**: Productivity (or Education).
