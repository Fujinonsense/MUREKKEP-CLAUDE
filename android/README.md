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
| Palm on the screen | ignored once a pen has been used; fingers move and zoom | Pencil-only drawing |
| A touch the system cancels (`FLAG_CANCELED`) | takes its stroke back | — |
| Unbuffered pen events + motion prediction | every pen sample, the line a step ahead of the tip | coalesced and predicted touches |
| 120 Hz panels | the highest refresh rate of the display | ProMotion |

## Status

See the end of this file (updated with each build).
