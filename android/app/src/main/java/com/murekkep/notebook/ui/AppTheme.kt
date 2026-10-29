package com.murekkep.notebook.ui

import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import com.murekkep.notebook.BuildConfig
import com.murekkep.notebook.R

// The themes of Ayarlar › Görünüm (the spec's "Temalar ve Pro", AppBackgrounds.swift on iPad), in
// the iPad's order and with its names: black and white is free and the default; every other theme
// is Pro, a picture made with Higgsfield laid behind the library under a wash of paper or night (or
// the ruled notebook paper), and the pens drawn as real bodies. The chrome keeps the brand's ink
// blue as its accent in every theme, as the iPad does.

/**
 * Whether the Pro themes are open. Debug builds are the personal edition and open everything, as
 * the iPad's build without APPSTORE does; the Play build keeps them locked until Play Billing
 * exists, and shows a locked theme as black and white (shownBackground(locked:) on iPad).
 */
object Pro {
    val UNLOCKED: Boolean = BuildConfig.DEBUG
}

enum class AppTheme(
    /** The key in the preferences (the iPad's raw value) and the pictures' names. */
    val key: String,
    val titleRes: Int,
    val isPro: Boolean,
    /** A picture's own light or dark look; null follows the system. */
    val darkLook: Boolean? = null,
    /** How much paper (or night, on a dark picture) lies over the picture. */
    val wash: Float = 0f,
    /** The theme's own accent from its palette. Like the iPad's, it stands ready for the day the
     *  palettes are wired in; the chrome draws its chosen states in the ink blue meanwhile. */
    val accent: Color? = null,
    /** The full picture (drawable-nodpi WebP, 2048 px). */
    val picture: Int? = null,
    /** The 320 px thumbnail for the picker. */
    val thumb: Int? = null,
) {
    BLACK_WHITE("bw", R.string.theme_black_white, isPro = false),

    // The zen set first (its pictures already mirrored, so their calm side lies behind the sidebar).
    EBRU("ebru", R.string.theme_ebru, true, darkLook = true, wash = 0.20f, accent = Color(0xFFD4A84F), picture = R.drawable.theme_ebru, thumb = R.drawable.theme_ebru_thumb),
    HOKKA("hokka", R.string.theme_hokka, true, darkLook = false, wash = 0.10f, accent = Color(0xFF234B7A), picture = R.drawable.theme_hokka, thumb = R.drawable.theme_hokka_thumb),
    LAPIS("lapis", R.string.theme_lapis, true, darkLook = true, wash = 0.10f, accent = Color(0xFFD2B062), picture = R.drawable.theme_lapis, thumb = R.drawable.theme_lapis_thumb),
    CINI("cini", R.string.theme_cini, true, darkLook = false, wash = 0.10f, accent = Color(0xFF1F4FB5), picture = R.drawable.theme_cini, thumb = R.drawable.theme_cini_thumb),
    VARAK("varak", R.string.theme_varak, true, darkLook = true, wash = 0.10f, accent = Color(0xFFD5A65A), picture = R.drawable.theme_varak, thumb = R.drawable.theme_varak_thumb),
    LAVI("lavi", R.string.theme_lavi, true, darkLook = false, wash = 0.12f, accent = Color(0xFFA8322D), picture = R.drawable.theme_lavi, thumb = R.drawable.theme_lavi_thumb),

    // The ruled notebook: faint lines behind the library, which follows the system's look.
    RULED("ruled", R.string.theme_ruled, true),

    // Material and light.
    GLASS("glass", R.string.theme_glass, true, darkLook = false, wash = 0.10f, picture = R.drawable.theme_glass, thumb = R.drawable.theme_glass_thumb),
    SILK("silk", R.string.theme_silk, true, darkLook = false, wash = 0.16f, picture = R.drawable.theme_silk, thumb = R.drawable.theme_silk_thumb),
    MOLTEN("molten", R.string.theme_molten, true, darkLook = true, wash = 0.18f, picture = R.drawable.theme_molten, thumb = R.drawable.theme_molten_thumb),
    PAPER_WAVE("paperWave", R.string.theme_paper_wave, true, darkLook = false, wash = 0.10f, picture = R.drawable.theme_paperwave, thumb = R.drawable.theme_paperwave_thumb),
    REEDED("reeded", R.string.theme_reeded, true, darkLook = true, wash = 0.28f, picture = R.drawable.theme_reeded, thumb = R.drawable.theme_reeded_thumb),
    FERRO("ferro", R.string.theme_ferro, true, darkLook = true, wash = 0.15f, picture = R.drawable.theme_ferro, thumb = R.drawable.theme_ferro_thumb),
    HOLO("holo", R.string.theme_holo, true, darkLook = false, wash = 0.10f, picture = R.drawable.theme_holo, thumb = R.drawable.theme_holo_thumb),
    ORBS("orbs", R.string.theme_orbs, true, darkLook = false, wash = 0.08f, picture = R.drawable.theme_orbs, thumb = R.drawable.theme_orbs_thumb),
    LIGHT_PAINT("lightPaint", R.string.theme_light_paint, true, darkLook = true, wash = 0.12f, picture = R.drawable.theme_lightpaint, thumb = R.drawable.theme_lightpaint_thumb),
    PEARL("pearl", R.string.theme_pearl, true, darkLook = false, wash = 0.10f, picture = R.drawable.theme_pearl, thumb = R.drawable.theme_pearl_thumb);

    /** A locked Pro theme shows as black and white. */
    val shown: AppTheme get() = if (locked) BLACK_WHITE else this

    /** A Pro theme while Pro is closed: its tile wears the Pro badge. */
    val locked: Boolean get() = isPro && !Pro.UNLOCKED

    /** Whether the library is dark (LibraryBackdrop on iPad): over a dark picture, not over a light
     *  one, else as the system is ([systemDark]). Only the library takes a picture's look. */
    fun libraryDark(systemDark: Boolean): Boolean = shown.darkLook ?: systemDark

    companion object {
        fun fromKey(key: String?): AppTheme = entries.firstOrNull { it.key == key } ?: BLACK_WHITE
    }
}

/** The theme chosen in the settings (what is shown may be black and white while Pro is locked). */
val LocalAppTheme = staticCompositionLocalOf { AppTheme.BLACK_WHITE }
