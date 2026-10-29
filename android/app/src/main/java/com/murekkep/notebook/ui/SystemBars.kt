package com.murekkep.notebook.ui

import android.graphics.Color
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.LocalActivity
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect

// The status and navigation bars: transparent, the app drawn under them, their icons dark on the
// light look and light on the dark one, androidx's scrim behind three-button navigation. The
// activity outlives a light/dark switch (it handles uiMode), so they follow every change, and they
// follow the screen in front: the library in its picture's look, everything else in the system's.

/** androidx's own scrims behind three-button navigation, light and dark. */
private val LightScrim = Color.argb(0xE6, 0xFF, 0xFF, 0xFF)
private val DarkScrim = Color.argb(0x80, 0x1B, 0x1B, 0x1B)

/** The activity's bars for the look of the screen in front ([dark]). */
@Composable
fun ActivityBars(dark: Boolean) {
    val activity = LocalActivity.current as? ComponentActivity ?: return
    DisposableEffect(activity, dark) {
        activity.enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.auto(Color.TRANSPARENT, Color.TRANSPARENT) { dark },
            navigationBarStyle = SystemBarStyle.auto(LightScrim, DarkScrim) { dark },
        )
        onDispose {}
    }
}
