# Mürekkep for Android

The Android tablet edition of Mürekkep, started on 2026-10-29. Kotlin + Jetpack Compose for the
screens, OpenGL ES 3.0 for the ink (the iPad's Metal renderer and shaders, ported). How the parts
fit together: `PORTING.md`. Google Play listing drafts and your steps: `STORE.md`.

## Build

There is no Android SDK on the development PC; builds run on Codemagic:

1. Codemagic → MUREKKEP-CLAUDE → Start new build → branch **android**, workflow
   **Murekkep Android (APK + AAB)** (`android-build` in `codemagic.yaml`, written by
   `tools/make_codemagic.py`).
2. About 4 minutes. Artifacts: `app-debug.apk` (install on a tablet to try it),
   `app-release.aab` (unsigned bundle for Google Play) and `android-build.log`.

Sign the bundle for Play with the upload key (kept outside git in `%USERPROFILE%\.murekkep-android\`,
password in `upload-password.txt` there):

```
jarsigner -keystore %USERPROFILE%\.murekkep-android\upload.jks app-release.aab upload
```

## Android pens

| On Android | What it does | iPad twin |
|---|---|---|
| Pressure, tilt (`AXIS_TILT`), direction (`AXIS_ORIENTATION`) | shape the line, pencil and watercolor shading | Apple Pencil force, altitude, azimuth |
| Side button (S Pen, USI) held | temporary eraser while held | Pencil Pro squeeze |
| Eraser end (`TOOL_TYPE_ERASER`) | erases | — |
| Pen hovering (`ACTION_HOVER_*`) | a ring with the line's width, red with the eraser's size while erasing | Pencil hover preview |
| Palm on the screen | ignored once a pen has been used; fingers move and zoom | Pencil-only drawing |
| A touch the system cancels (`FLAG_CANCELED`) | takes its stroke back | — |
| Unbuffered pen events + motion prediction | every pen sample, the line a step ahead of the tip | coalesced and predicted touches |
| 120 Hz panels | the highest refresh rate of the display | ProMotion |

## Status (2026-10-29, first night)

**Builds:** every push of the night compiled on Codemagic with the JUnit tests passing (the
ink logic checked against the iPad's numbers). Debug APK and unsigned AAB come out of each build.

**Seen working:** the ink shaders, drawn in WebGL2 (Chrome, real GPU) in the renderer's own order
(page shadow, lined paper, highlighters, the raised inks' shadows, the ink): every pen looks as on
iPad, `docs/ink-check-webgl.png`.

**Not seen yet:** the app itself on a screen. Codemagic's Mac is a virtual machine and cannot run
the Android emulator (no nested virtualization), and there is no Android SDK on the development
PC. To try it: install `app-debug.apk` on an Android tablet (or an emulator) and open a notebook;
a debuggable build started with
`adb shell am start -n com.murekkep.notebook/.MainActivity --es murekkep.demo pens`
opens a page with a wave in every pen.

**In the Android edition:**
- library (new, rename, delete);
- notebook pages, pinch and fling;
- all 23 pens with the iPad's shading, including 3D inks, shadows, grass blades and flowers;
- highlighter, eraser (whole stroke and partial), undo/redo;
- pen preferences;
- notebooks saved in the iPad's own ink format;
- the pen features in the table above.

**Not ported yet:**
- lasso;
- shapes and the compass;
- the text pen (handwriting to text);
- PDF import and export;
- page templates beyond plain, lined, grid and dotted;
- stickers;
- the break corner (games, Ebru, living ink pond);
- the assistant;
- Pro with Play Billing.

**Also left:**
- grass sprouting while the pen is still down: blades appear when it lifts;
- the eraser's "keep the meshes" plan from iPad: on Android a change still rebuilds the page.
