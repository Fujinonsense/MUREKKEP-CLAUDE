package com.murekkep.notebook.data

import android.content.Context
import android.content.SharedPreferences
import com.murekkep.notebook.ink.Brush
import com.murekkep.notebook.ink.InkColor

// What the user last chose for each pen (the pen part of AppSettings on iPad): its color, its width,
// the pen in the hand, the starred pens and the pens picked last (the bar's pens), kept between
// sessions in SharedPreferences.

class PenPreferences(context: Context) {
    private val prefs: SharedPreferences =
        context.applicationContext.getSharedPreferences("pens", Context.MODE_PRIVATE)

    /** The pen's remembered color, or null when it was never changed. */
    fun color(brush: Brush): InkColor? {
        val key = "color.${brush.raw}"
        if (!prefs.contains(key)) return null
        val argb = prefs.getInt(key, 0)
        return InkColor(
            ((argb shr 16) and 0xFF) / 255f,
            ((argb shr 8) and 0xFF) / 255f,
            (argb and 0xFF) / 255f,
            ((argb ushr 24) and 0xFF) / 255f,
        )
    }

    fun setColor(brush: Brush, color: InkColor) {
        val argb = (channel(color.a) shl 24) or (channel(color.r) shl 16) or (channel(color.g) shl 8) or channel(color.b)
        prefs.edit().putInt("color.${brush.raw}", argb).apply()
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

    private fun brushes(key: String): List<Brush> =
        prefs.getString(key, "")!!.split(',').filter { it.isNotEmpty() }.mapNotNull { raw ->
            raw.toIntOrNull()?.let { n -> Brush.entries.firstOrNull { it.raw == n } }
        }

    private fun setBrushes(key: String, brushes: List<Brush>) {
        prefs.edit().putString(key, brushes.joinToString(",") { it.raw.toString() }).apply()
    }

    private fun channel(v: Float): Int = (v.coerceIn(0f, 1f) * 255f + 0.5f).toInt()
}
