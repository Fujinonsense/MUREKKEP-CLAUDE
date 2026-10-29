package com.murekkep.notebook.data

import android.content.Context
import android.content.SharedPreferences
import com.murekkep.notebook.ink.Brush
import com.murekkep.notebook.ink.InkColor
import com.murekkep.notebook.ui.PaletteEdge

// What the user last chose for each pen (the pen part of AppSettings on iPad): its color, its width,
// the pen in the hand, the starred pens and the pens picked last (the bar's pens), the custom colours
// picked lately; the ink's settings the canvas and the renderer follow (animations, a held pen
// straightening its stroke, the drying and cooling times, the grass's flowers, the nib's angle); and
// where the pen bar stands. Kept between sessions in SharedPreferences.

class PenPreferences(context: Context) {
    private val prefs: SharedPreferences =
        context.applicationContext.getSharedPreferences("pens", Context.MODE_PRIVATE)

    /** The pen's remembered color, or null when it was never changed. */
    fun color(brush: Brush): InkColor? {
        val key = "color.${brush.raw}"
        if (!prefs.contains(key)) return null
        return unpack(prefs.getInt(key, 0))
    }

    fun setColor(brush: Brush, color: InkColor) {
        prefs.edit().putInt("color.${brush.raw}", pack(color)).apply()
    }

    /** The pen's remembered width in points, or null when it was never changed. */
    fun width(brush: Brush): Float? {
        val key = "width.${brush.raw}"
        return if (prefs.contains(key)) prefs.getFloat(key, brush.defaultWidth) else null
    }

    fun setWidth(brush: Brush, width: Float) {
        prefs.edit().putFloat("width.${brush.raw}", width).apply()
    }

    /** The pen last picked, or null the first time. */
    fun lastBrush(): Brush? =
        if (prefs.contains("lastBrush")) Brush.fromRaw(prefs.getInt("lastBrush", Brush.PEN.raw)) else null

    fun rememberBrush(brush: Brush) {
        prefs.edit().putInt("lastBrush", brush.raw).apply()
    }

    /** The starred pens, in the order they were starred. */
    fun favoriteBrushes(): List<Brush> = brushes("favoriteBrushes")

    fun setFavoriteBrushes(brushes: List<Brush>) = setBrushes("favoriteBrushes", brushes)

    /** The pens picked most recently, newest first; null until a pen was ever picked. */
    fun recentBrushes(): List<Brush>? = if (prefs.contains("recentBrushes")) brushes("recentBrushes") else null

    fun setRecentBrushes(brushes: List<Brush>) = setBrushes("recentBrushes", brushes)

    /** The custom colours picked lately, newest first (AppSettings.recentColors). */
    fun recentColors(): List<InkColor> =
        prefs.getString("recentColors", "")!!.split(',').mapNotNull { it.toIntOrNull()?.let(::unpack) }

    fun setRecentColors(colors: List<InkColor>) {
        prefs.edit().putString("recentColors", colors.joinToString(",") { pack(it).toString() }).apply()
    }

    // The ink's settings, with the iPad's defaults and bounds (AppSettings.init).

    /** The moving inks move (Diğer › Animasyonlar, and each animated pen's own switch). */
    var animations: Boolean
        get() = prefs.getBoolean("animations", true)
        set(value) = prefs.edit().putBoolean("animations", value).apply()

    /** A pen resting at the end of a stroke straightens it into a shape (Bekleyince şekli düzelt). */
    var straightLine: Boolean
        get() = prefs.getBoolean("straightLine", true)
        set(value) = prefs.edit().putBoolean("straightLine", value).apply()

    /** Seconds wet ink takes to dry. */
    var dryDuration: Float
        get() = prefs.getFloat("dryDuration", 4f).coerceIn(1f, 20f)
        set(value) = prefs.edit().putFloat("dryDuration", value).apply()

    /** Seconds lava takes to cool. */
    var coolDuration: Float
        get() = prefs.getFloat("lavaCoolDuration", 6f).coerceIn(2f, 20f)
        set(value) = prefs.edit().putFloat("lavaCoolDuration", value).apply()

    /** The grass's flowers: 0 none, 1 some, 2 lots. */
    var flowerLevel: Int
        get() = prefs.getInt("flowerLevel", 1).coerceIn(0, 2)
        set(value) = prefs.edit().putInt("flowerLevel", value).apply()

    /** The calligraphy nib's angle in degrees, 0...180. */
    var nibAngle: Float
        get() = prefs.getFloat("nibAngle", 38f).coerceIn(0f, 180f)
        set(value) = prefs.edit().putFloat("nibAngle", value).apply()

    // The pen bar.

    /** The edge the pen bar stands on, the bottom until it is moved. */
    var paletteEdge: PaletteEdge
        get() = PaletteEdge.fromRaw(prefs.getString("paletteEdge", null))
        set(value) = prefs.edit().putString("paletteEdge", value.raw).apply()

    /** The bar folded to its undo, redo and the ink in hand. */
    var paletteCollapsed: Boolean
        get() = prefs.getBoolean("paletteCollapsed", false)
        set(value) = prefs.edit().putBoolean("paletteCollapsed", value).apply()

    /** The pen panel's shelf used last ("" until one is picked). */
    var penPanelShelf: String
        get() = prefs.getString("penPanelShelf", "")!!
        set(value) = prefs.edit().putString("penPanelShelf", value).apply()

    private fun brushes(key: String): List<Brush> =
        prefs.getString(key, "")!!.split(',').filter { it.isNotEmpty() }.mapNotNull { raw ->
            raw.toIntOrNull()?.let { n -> Brush.entries.firstOrNull { it.raw == n } }
        }

    private fun setBrushes(key: String, brushes: List<Brush>) {
        prefs.edit().putString(key, brushes.joinToString(",") { it.raw.toString() }).apply()
    }

    private fun pack(color: InkColor): Int =
        (channel(color.a) shl 24) or (channel(color.r) shl 16) or (channel(color.g) shl 8) or channel(color.b)

    private fun unpack(argb: Int): InkColor = InkColor(
        ((argb shr 16) and 0xFF) / 255f,
        ((argb shr 8) and 0xFF) / 255f,
        (argb and 0xFF) / 255f,
        ((argb ushr 24) and 0xFF) / 255f,
    )

    private fun channel(v: Float): Int = (v.coerceIn(0f, 1f) * 255f + 0.5f).toInt()
}
