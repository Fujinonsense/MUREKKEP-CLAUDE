# Mürekkep for Android

The Android tablet edition of Mürekkep, started on 2026-10-29. Kotlin + Jetpack Compose for the
screens, OpenGL ES 3.0 for the ink (the iPad's Metal renderer and shaders, ported). How the parts
fit together: `PORTING.md`. Google Play listing drafts and your steps: `STORE.md`.

## Build

On the development PC (since 2026-10-29): Android SDK in `%LOCALAPPDATA%\Android\Sdk` (platform 36,
build tools 35, emulator, Android 16 x86_64 image), Gradle 8.14.3 in
`%LOCALAPPDATA%\Programs\gradle-8.14.3`, JDK 21 in `%LOCALAPPDATA%\Programs\jdk-21`. From Git Bash:

```
export JAVA_HOME="$LOCALAPPDATA/Programs/jdk-21" ANDROID_HOME="$LOCALAPPDATA/Android/Sdk"
"$LOCALAPPDATA/Programs/gradle-8.14.3/bin/gradle" -p android testDebugUnitTest assembleDebug bundleRelease
```

About 2 minutes the first time, seconds after that. The debug APK is in
`app/build/outputs/apk/debug/`, the unsigned bundle in `app/build/outputs/bundle/release/`.

Codemagic builds the same without the PC: MUREKKEP-CLAUDE → Start new build → branch **android**,
workflow **Murekkep Android (APK + AAB)** (`android-build` in `codemagic.yaml`, written by
`tools/make_codemagic.py`), about 4 minutes of the free Mac minutes.

Sign the bundle for Play with the upload key (kept outside git in `%USERPROFILE%\.murekkep-android\`,
password in `upload-password.txt` there). SHA-256, as the Android build tools sign; JDK 21's
jarsigner would pick SHA-384 for this 4096-bit key:

```
jarsigner -sigalg SHA256withRSA -digestalg SHA-256 -keystore %USERPROFILE%\.murekkep-android\upload.jks -signedjar app-release-signed.aab app-release.aab upload
```

Signed bundles and debug APKs are kept in `Downloads\Murekkep-android\<date>\` on the development
PC; the folder of the newest build is named after its commit.

## Android pens

| On Android | What it does | iPad twin |
|---|---|---|
| Pressure, tilt (`AXIS_TILT`), direction (`AXIS_ORIENTATION`) | shape the line, pencil and watercolor shading | Apple Pencil force, altitude, azimuth |
| Side button (S Pen, USI) held | temporary eraser while held | Pencil Pro squeeze |
| Eraser end (`TOOL_TYPE_ERASER`) | erases | — |
| Pen hovering (`ACTION_HOVER_*`) | a ring with the line's width, red with the eraser's size while erasing (Ayarlar › Kalem › Havada önizleme) | Pencil hover preview |
| Palm on the screen | ignored once a pen has been used, or always with Yalnızca kalemle çiz (Diğer, Ayarlar › Kalem); fingers move and zoom | Pencil-only drawing |
| A touch the system cancels (`FLAG_CANCELED`) | takes its stroke back, or puts an instrument it carried back where it was | — |
| Unbuffered pen events + motion prediction | every pen sample, the line a step ahead of the tip | coalesced and predicted touches |
| 120 Hz panels | the highest refresh rate of the display | ProMotion |

## Status (2026-10-29)

**Builds:** on the PC and on Codemagic, with the 224 JUnit tests passing (the ink logic checked
against the iPad's numbers; the shape recognizer, its handles and the shape tool against the
iPad's own Swift code, run on the PC by `tools/shapecheck`; the library's screen on Robolectric).

**Seen working on the emulator** (Pixel Tablet, Android 16, the PC's GPU through the emulator's
GLES translator), `docs/emulator-pens.png`:
- library, new notebook, rename, delete (its folder goes too), English and Turkish;
- every one of the 23 pens, drawn with a stylus; grass blades and flowers grow when the pen lifts;
- the eraser, whole stroke and partial; undo, redo;
- a finger draws until a pen has been seen, then it scrolls the pages;
- the notebook saved and read back after the app is closed and after a language change;
- turning the tablet: the page fits the new width;
- a virtual pen made with Android's `uinput` tool (`tools/androidcheck/pen.py`): pressure makes the
  line thicker, a tilted pencil shades wide, the side button erases while held, the eraser end
  erases, hovering shows the ring (red with the side button);
- the lasso: a loop or a tap selects, the frame moves, resizes ("144%") and turns (settling at
  right angles, "-90°"); Duplicate, Apply ink, Delete, Done; a selection dragged onto the next page
  moves there, one undo puts both pages back; the side button still erases with the lasso in hand;
- held shapes: a shaky circle, square or triangle held still becomes a clean circle, square or
  equilateral triangle, follows the pen ("Circle · 175% · 0°") and keeps handles after the pen
  lifts (a circle's axis handle makes an ellipse, a corner shows its angle, the middle moves it);
  a held line straightens and its end follows the pen;
- the shape tool: a rectangle and a dashed regular hexagon previewed with their size and drawn in
  the pen's ink (`docs/emulator-lasso-shapes.png`).

Not checkable on the emulator: palm rejection by the system (`FLAG_CANCELED`), 120 Hz (the emulator
runs at 60 Hz) and how prediction feels under a real pen.

**Fixed on the emulator (2026-10-29):**
- saves lost: the library read the disk again whenever it appeared, and a scan that finished after
  a notebook was made dropped it from the list; that notebook's saves then found no record and
  wrote nothing (1 demo start in 3). The disk is now read once per process.
- turning the tablet kept the old zoom, so in portrait the page ran off the right edge.
- the library said "0 min. ago" in the first minute; now "now", as on iPad.

**Checking on the emulator:** `tools/androidcheck/` (`drive.py` taps by label, draws with
`input stylus`, draws lasso loops (`loop`) and shaky shapes held still (`hold`), takes screenshots;
`pen.py` is the virtual pen, made for the landscape screen; `savecheck.sh` repeats the save
check). Start the emulator with
`%LOCALAPPDATA%\Android\Sdk\emulator\emulator -avd murekkep_tab -no-window -gpu host`; a debuggable
build started with `adb shell am start -n com.murekkep.notebook/.MainActivity --es murekkep.demo pens`
opens a page with a wave in 21 pens.

**The zen interface (2026-10-29, branch android-zen):** the screens follow
`docs/superpowers/specs/2026-10-29-zen-arayuz-design.md`, the same design as the iPad's. The tokens
(paper, ink, the greys at zero chroma, the ink blue only for what is selected) are `ui/Theme.kt`, light
and dark after the system. The editor has a quiet top bar ("‹ Notlar", the title, Paylaş, Diğer) and
a floating pen bar at the bottom centre: undo, redo | five pens (the favourites, then the pens used
last, `ui/PenStripRule.kt`, the iPad's PenStrip rule) and the eraser standing in a tray, flat silhouettes
in black and white (`ui/PenSilhouettes.kt`), the iPad's bodies (`ui/ToolArt.kt`) in a Pro theme, then
every pen | the ink's colour | lasso, shapes, Araçlar | add page. A second tap on the picked pen opens
its settings in a popover (name, one sentence, the ink's real look drawn by FlatInk, colours, width,
favourite); the eraser's and the shapes' settings open the same way; a long press stars a pen. The
page badge "1 / 1" sits at the bottom right. Paylaş writes the note as a PDF (`export/PdfShare.kt`)
and opens the system's share chooser through a FileProvider. The library has a sidebar (search, Tüm
notlar, Son açılanlar, Defterler, PDF'ler, Ayarlar; a drawer under 600 dp) and the notes as the covers
of their first pages (`thumb.jpg`, drawn at every save) with "3 sayfa, dün" under them. Ayarlar ›
Görünüm › Tema offers black and white (free) and the Pro themes as picture tiles (`ui/AppTheme.kt`,
the pictures in `res/drawable-nodpi`); without Play Billing a Pro tile says Pro is coming and the look
stays black and white. Checked on the emulator in English and Turkish, light and dark, landscape and
portrait, at font scale 1.3.

Since then: an imported PDF is shared with its own pages, vectors and text, the ink laid over them
by PDFBox (`export/PdfOverlay.kt`; its pages go as pictures only when PDFBox cannot do it), and
Ayarlar › 3B mürekkep is the iPad's ink section (animations, the battery saver's 30 fps, the drying
and cooling times, the flowers in the grass) on the same settings the pens' popovers and Diğer change
(`data/InkSettings.kt`).

**In the Android edition:**
- library (new, rename, delete, search, sections, favourites, covers) and settings (the language,
  the theme, the pen, the 3D ink);
- PDFs: import (files, photos as one PDF, drag and drop) and Paylaş as a PDF, an imported PDF with
  its own pages;
- notebook pages, pinch and fling; a notebook's template changed from Diğer;
- all 23 pens with the iPad's shading, including 3D inks, shadows, grass blades and flowers;
- highlighter, eraser (whole stroke and partial), undo/redo;
- the lasso: select, move, resize, turn, carry to another page, duplicate, apply ink, delete;
- hold-to-shape (lines, broken lines, curves, circles, ellipses, triangles, rectangles, polygons)
  with handles to fix them afterwards;
- the shape tool: line, arrow, double arrow, rectangle, ellipse, circle from the center, triangle,
  right triangle, regular polygon (3 to 12 sides), dashed or not;
- Araçlar on the pen bar (between Şekiller and Sayfa ekle): the ruler, the 45° and 30°/60° set
  squares and the protractor laid on the page, carried by a finger and turned by two (settling at
  15°, the angle shown over them), Açıyı ayarla's round angles and Kaldır; a pen stroke started by
  an edge runs along it, from the protractor's center along whole-degree rays, its length or angle
  beside the pen. Pergel: a drag sets the center and the radius, then the pen draws arcs. The
  geometry is held to the iPad's own Instruments.swift by `tools/instrumentcheck`;
- pen preferences;
- notebooks saved in the iPad's own ink format;
- the pen features in the table above.

**Deliberately unlike the iPad:**
- on a phone (a window under 480 dp) the library keeps 16 dp at the sides of its notes, where the
  iPad's 40 would leave the header no room; from 480 dp it keeps the iPad's 40 and its 34 sp title;
- Yalnızca kalemle çiz starts off: fingers draw until a pen has touched the screen, as many Android
  tablets have no pen (the iPad's starts on);
- Ayarlar › Dil offers the device's language besides Türkçe and English, as Android's per-app
  language does;
- a finger left on an instrument after a two-finger turn carries it on (the iPad's holds it still
  until every finger lifts), and a touch the system takes back (a palm) puts the instrument back
  where it was, as it takes back a stroke; while the pen is down a finger that lands on an
  instrument is left alone, as every finger is then (the iPad's takes the instrument);
- a two-finger turn starts settled on the 15° step the instrument rests on: it clicks when it comes
  back to that step or reaches another, not as it starts (the iPad's clicks at once); the angle over
  a turning instrument and the reading beside a pen along it stand in the dark capsule of the
  canvas's other measurements, where the iPad's bubbles are accent blue.

**Not ported yet:**
- Araçlar's typed text (Metin), the engineering toolbox (Mühendislik) and the page angle (Sayfa açısı);
- the shape tool's coordinate axes and dimension line, and plots (they write with the stroke font);
- held drawings that become pictures (heart, face, organs) and their suggestions;
- the lasso's "Convert to text" (it comes with the text pen);
- the text pen (handwriting to text);
- page templates beyond plain, lined, grid and dotted;
- stickers;
- the break corner (games, Ebru, living ink pond);
- the assistant;
- Pro with Play Billing.

**Also left:**
- grass sprouting while the pen is still down: blades appear when it lifts;
- the eraser's "keep the meshes" plan from iPad: on Android a change still rebuilds the page.
