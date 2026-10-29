package com.murekkep.notebook.data

import android.content.Context
import android.content.SharedPreferences
import com.murekkep.notebook.ui.AppTheme

// The look the user chose in Ayarlar › Görünüm (the background part of AppSettings on iPad), kept
// between sessions in SharedPreferences.

class AppearancePreferences(context: Context) {
    private val prefs: SharedPreferences =
        context.applicationContext.getSharedPreferences("appearance", Context.MODE_PRIVATE)

    /** The theme, black and white until one is chosen. */
    var theme: AppTheme
        get() = AppTheme.fromKey(prefs.getString("theme", null))
        set(value) = prefs.edit().putString("theme", value.key).apply()
}
