package com.murekkep.notebook.ui

import android.graphics.Color
import android.os.Build
import android.view.View
import android.view.Window
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.LocalActivity
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.window.DialogWindowProvider
import androidx.core.view.WindowCompat

// The status and navigation bars: transparent, the app drawn under them, their icons dark on the
// light look and light on the dark one, androidx's scrim behind three-button navigation. The
// activity outlives a light/dark switch (it handles uiMode), so they follow every change, and they
// follow the screen in front: the library in its picture's look, everything else in the system's.
// A sheet that covers the screen is a window of its own and sets its own bars the same way.

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

/** The bars of the dialog window this is composed in, for a sheet drawn edge to edge over the whole screen. */
@Composable
fun DialogBars(dark: Boolean) {
    val view = LocalView.current
    val window = (view.parent as? DialogWindowProvider)?.window ?: return
    DisposableEffect(window, dark) {
        window.edgeToEdgeBars(view, dark)
        onDispose {}
    }
}

/** What enableEdgeToEdge does to an activity's window (from Android 15 the system keeps the bars clear itself). */
@Suppress("DEPRECATION")
private fun Window.edgeToEdgeBars(view: View, dark: Boolean) {
    statusBarColor = Color.TRANSPARENT
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
        // The system lays its own scrim behind three buttons.
        navigationBarColor = Color.TRANSPARENT
        isStatusBarContrastEnforced = false
        isNavigationBarContrastEnforced = true
    } else {
        navigationBarColor = if (dark) DarkScrim else LightScrim
    }
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
        attributes = attributes.apply { layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS }
    } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
        attributes = attributes.apply { layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES }
    }
    WindowCompat.getInsetsController(this, view).run {
        isAppearanceLightStatusBars = !dark
        isAppearanceLightNavigationBars = !dark
    }
}
