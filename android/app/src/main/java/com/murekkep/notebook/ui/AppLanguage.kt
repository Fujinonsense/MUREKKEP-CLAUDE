package com.murekkep.notebook.ui

import android.app.Activity
import android.app.LocaleManager
import android.content.Context
import android.content.res.Configuration
import android.os.Build
import android.os.LocaleList
import java.util.Locale

// Ayarlar › Dil (the iPad's AppLanguage and its language picker): the app in the device's language,
// or in Turkish or English whatever the device speaks. Each language names itself, so it can be
// found whatever language is on screen. From Android 13 the choice is the system's per-app language
// (it is also in the system's settings for the app, res/xml/locales_config.xml), which the open
// screen follows in place; before, it is kept here and laid over the activity's configuration, and
// the activity is made again to take it.

enum class AppLanguage(
    /** The BCP 47 tag; empty for the device's language. */
    val tag: String,
) {
    SYSTEM(""),
    TURKISH("tr"),
    ENGLISH("en");

    companion object {
        /** The language of [tag] ("tr", "tr-TR", "en-GB"...), else the device's. */
        fun fromTag(tag: String?): AppLanguage {
            val language = tag?.substringBefore('-')?.lowercase(Locale.ROOT).orEmpty()
            return entries.firstOrNull { it.tag.isNotEmpty() && it.tag == language } ?: SYSTEM
        }
    }
}

object AppLanguages {
    private const val PREFS = "appearance"
    private const val KEY = "appLanguage"

    /** The language picked in Ayarlar (the device's until one is picked). */
    fun current(context: Context): AppLanguage =
        if (Build.VERSION.SDK_INT >= 33) {
            val locales = context.getSystemService(LocaleManager::class.java)?.applicationLocales
            if (locales == null || locales.isEmpty) AppLanguage.SYSTEM else AppLanguage.fromTag(locales[0].toLanguageTag())
        } else {
            AppLanguage.fromTag(prefs(context).getString(KEY, ""))
        }

    /** Shows the app in [language]: from Android 13 the system's per-app language, which the open
     *  screen takes in place (MainActivity handles a change of locale); before, the activity is made
     *  again in it. */
    fun set(activity: Activity, language: AppLanguage) {
        if (Build.VERSION.SDK_INT >= 33) {
            activity.getSystemService(LocaleManager::class.java)?.applicationLocales =
                if (language == AppLanguage.SYSTEM) LocaleList.getEmptyLocaleList() else LocaleList.forLanguageTags(language.tag)
        } else {
            prefs(activity).edit().putString(KEY, language.tag).commit()
            activity.recreate()
        }
    }

    /** Before Android 13: the configuration to lay over the activity's for the language picked (null
     *  for the device's), for MainActivity.attachBaseContext. */
    fun overrideFor(context: Context): Configuration? {
        if (Build.VERSION.SDK_INT >= 33) return null
        val tag = prefs(context).getString(KEY, "").orEmpty()
        if (tag.isEmpty()) return null
        return Configuration().apply { setLocales(LocaleList(Locale.forLanguageTag(tag))) }
    }

    private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}
