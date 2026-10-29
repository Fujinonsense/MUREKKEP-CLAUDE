package com.murekkep.notebook.ui

import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import com.murekkep.notebook.R

// The themes of Ayarlar › Görünüm (the spec's "Temalar ve Pro", AppBackgrounds.swift on iPad):
// black and white is free and the default; every other theme is Pro, a picture made with
// Higgsfield with its own accent, a wash of paper or night over it, and the pens drawn as real
// bodies. There is no Play Billing yet, so a Pro theme chosen in the settings is shown as black and
// white until Pro exists (shownBackground(locked:) on iPad).

/** Whether Pro is bought: there is no Play Billing yet, so never. */
object Pro {
    const val UNLOCKED = false
}

enum class AppTheme(
    /** The key in the preferences and the pictures' names. */
    val key: String,
    val titleRes: Int,
    val isPro: Boolean,
    /** A picture's own light or dark look; null follows the system. */
    val darkLook: Boolean? = null,
    /** How much paper (or night, on a dark picture) lies over the picture. */
    val wash: Float = 0f,
    /** The theme's own accent; null keeps the ink blue. */
    val accent: Color? = null,
    /** The full picture (drawable-nodpi WebP, about 2048 px), null when there is none yet. */
    val picture: Int? = null,
    /** The 320 px thumbnail for the picker. */
    val thumb: Int? = null,
) {
    BLACK_WHITE("bw", R.string.theme_black_white, isPro = false),

    // The six new pictures, first among the Pro themes.
    EBRU("ebru", R.string.theme_ebru, true, darkLook = true, wash = 0.20f, accent = Color(0xFFD4A84F), picture = R.drawable.theme_ebru, thumb = R.drawable.theme_ebru_thumb),
    HOKKA("hokka", R.string.theme_hokka, true, darkLook = false, wash = 0.10f, accent = Color(0xFF234B7A), picture = R.drawable.theme_hokka, thumb = R.drawable.theme_hokka_thumb),
    LAPIS("lapis", R.string.theme_lapis, true, darkLook = true, wash = 0.10f, accent = Color(0xFFD2B062), picture = R.drawable.theme_lapis, thumb = R.drawable.theme_lapis_thumb),
    CINI("cini", R.string.theme_cini, true, darkLook = false, wash = 0.10f, accent = Color(0xFF1F4FB5), picture = R.drawable.theme_cini, thumb = R.drawable.theme_cini_thumb),
    VARAK("varak", R.string.theme_varak, true, darkLook = true, wash = 0.10f, accent = Color(0xFFD5A65A), picture = R.drawable.theme_varak, thumb = R.drawable.theme_varak_thumb),
    LAVI("lavi", R.string.theme_lavi, true, darkLook = false, wash = 0.12f, accent = Color(0xFFA8322D), picture = R.drawable.theme_lavi, thumb = R.drawable.theme_lavi_thumb),

    // The ruled paper and the iPad's older pictures (their full pictures come later; the picker shows their thumbnails).
    RULED("ruled", R.string.theme_ruled, true, darkLook = false),
    FERRO("ferro", R.string.theme_ferro, true, darkLook = true, wash = 0.15f, thumb = R.drawable.theme_ferro_thumb),
    HOLO("holo", R.string.theme_holo, true, darkLook = false, wash = 0.10f, thumb = R.drawable.theme_holo_thumb),
    SILK("silk", R.string.theme_silk, true, darkLook = false, wash = 0.16f, thumb = R.drawable.theme_silk_thumb),
    MOLTEN("molten", R.string.theme_molten, true, darkLook = true, wash = 0.18f, thumb = R.drawable.theme_molten_thumb),
    GLASS("glass", R.string.theme_glass, true, darkLook = false, wash = 0.10f, thumb = R.drawable.theme_glass_thumb),
    PEARL("pearl", R.string.theme_pearl, true, darkLook = false, wash = 0.10f, thumb = R.drawable.theme_pearl_thumb);

    /** A locked Pro theme shows as black and white. */
    val shown: AppTheme get() = if (isPro && !Pro.UNLOCKED) BLACK_WHITE else this

    companion object {
        fun fromKey(key: String?): AppTheme = entries.firstOrNull { it.key == key } ?: BLACK_WHITE
    }
}

/** The theme chosen in the settings (what is shown may be black and white while Pro is locked). */
val LocalAppTheme = staticCompositionLocalOf { AppTheme.BLACK_WHITE }
