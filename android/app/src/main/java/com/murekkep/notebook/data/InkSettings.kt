package com.murekkep.notebook.data

import android.content.SharedPreferences
import androidx.compose.runtime.mutableStateOf
import kotlin.properties.ReadWriteProperty
import kotlin.reflect.KProperty

// The ink's settings (the ink part of AppSettings on iPad), one set for the app: the moving inks
// moving, the battery saver's 30 frames a second, the drying and cooling times, the grass's
// flowers, the nib's angle and a held pen straightening its stroke. A pen's popover, Diğer and
// Ayarlar › 3B mürekkep read and write these same values, and they are Compose state, so a change
// in one place shows in the others at once (Ayarlar opens over a note, too). Kept in the pens'
// SharedPreferences under the iPad's keys, with its defaults and bounds; without them (the tests)
// they last for the run.

class InkSettings(private val prefs: SharedPreferences? = null) {
    /** The moving inks move: the sea, the wind in the grass, glitter, lava's flow and embers. */
    var animations: Boolean by setting(prefs?.getBoolean("animations", true) ?: true) { putBoolean("animations", it) }

    /** Moving ink is drawn at most 30 times a second (Pil tasarrufu). */
    var batterySaver: Boolean by setting(prefs?.getBoolean("batterySaver", false) ?: false) { putBoolean("batterySaver", it) }

    /** A pen resting at the end of a stroke straightens it into a shape (Bekleyince şekli düzelt). */
    var straightLine: Boolean by setting(prefs?.getBoolean("straightLine", true) ?: true) { putBoolean("straightLine", it) }

    /** Seconds wet ink takes to dry (the sliders give 1 to 15). */
    var dryDuration: Float by setting((prefs?.getFloat("dryDuration", 4f) ?: 4f).coerceIn(1f, 20f)) { putFloat("dryDuration", it) }

    /** Seconds lava takes to cool into embers, 2 to 20. */
    var coolDuration: Float by setting((prefs?.getFloat("lavaCoolDuration", 6f) ?: 6f).coerceIn(2f, 20f)) { putFloat("lavaCoolDuration", it) }

    /** The grass's flowers: 0 none, 1 some, 2 lots. */
    var flowerLevel: Int by setting((prefs?.getInt("flowerLevel", 1) ?: 1).coerceIn(0, 2)) { putInt("flowerLevel", it) }

    /** The calligraphy nib's angle in degrees, 0 to 180. */
    var nibAngle: Float by setting((prefs?.getFloat("nibAngle", 38f) ?: 38f).coerceIn(0f, 180f)) { putFloat("nibAngle", it) }

    /** A value Compose observes, written through to the preferences when it changes. */
    private fun <T> setting(initial: T, write: SharedPreferences.Editor.(T) -> Unit): ReadWriteProperty<Any?, T> =
        object : ReadWriteProperty<Any?, T> {
            private val state = mutableStateOf(initial)

            override fun getValue(thisRef: Any?, property: KProperty<*>): T = state.value

            override fun setValue(thisRef: Any?, property: KProperty<*>, value: T) {
                if (state.value == value) return
                state.value = value
                val editor = prefs?.edit() ?: return
                editor.write(value)
                editor.apply()
            }
        }
}
