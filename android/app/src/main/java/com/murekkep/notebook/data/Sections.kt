package com.murekkep.notebook.data

import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject
import java.time.Instant
import java.time.temporal.ChronoUnit
import java.util.Locale
import java.util.UUID

// The library's courses (NoteSection in Sections.swift, kept by LibraryStore.swift): a name, a
// symbol and a colour, in `sections.json` at the library's root, apart from the notes; each note
// names its course in its own record ("sectionID", NotebookMeta.sectionId). The file is the iPad's:
// a JSON list of {id, name, symbol, colorIndex, created}, the ids upper-case UUIDs, the dates ISO
// 8601 in whole seconds, the symbols the iPad's SF Symbols names (ui/SectionEditor.kt draws them).
// It is read entry by entry (LenientList in SafeFiles.swift): an entry this build cannot read (a
// newer Mürekkep's, or a damaged one) is kept as it is and written back with the rest, so one bad
// entry never empties the list.

/** A course or topic of the library ("Calculus", "Anatomi"): notes and PDFs are filed under it. */
data class NoteSection(
    /** An upper-case UUID, as the iPad writes it. */
    val id: String,
    val name: String,
    /** One of [SYMBOLS], the iPad's SF Symbols names; one this build does not know draws a folder. */
    val symbol: String,
    /** Its colour among the [COLOR_COUNT]; any number, wrapped by [colorSlot]. */
    val colorIndex: Int,
    /** When it was made, epoch milliseconds in whole seconds (the file keeps no more). */
    val created: Long,
) {
    /** [colorIndex] wrapped into 0 until [COLOR_COUNT], a negative one too (NoteSection.color on iPad). */
    val colorSlot: Int get() = Math.floorMod(colorIndex, COLOR_COUNT)

    /** The entry of sections.json, the date in whole seconds as the iPad's .iso8601 reads it. */
    fun toJson(): JSONObject = JSONObject()
        .put("id", id)
        .put("name", name)
        .put("symbol", symbol)
        .put("colorIndex", colorIndex)
        .put("created", Instant.ofEpochMilli(created).truncatedTo(ChronoUnit.SECONDS).toString())

    companion object {
        /** How many colours a course can take (NoteSection.colors on iPad). */
        const val COLOR_COUNT = 8

        /** The symbols a course can take, in the editor's order (NoteSection.symbols on iPad). */
        val SYMBOLS = listOf(
            "function", "x.squareroot", "atom", "flask", "cross.case", "heart.text.square", "brain.head.profile",
            "gearshape.2", "bolt", "building.columns", "globe.europe.africa", "chart.line.uptrend.xyaxis",
            "book.closed", "text.book.closed", "music.note", "paintpalette", "laptopcomputer", "leaf",
        )

        private val UUID_FORM = Regex("[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}")

        /** A course's id as it is kept: a UUID in its 36 characters (what the iPad's UUID reads), in
         *  capitals; null for anything else. */
        fun normalizedId(raw: String?): String? = raw?.trim()?.takeIf { UUID_FORM.matches(it) }?.uppercase(Locale.ROOT)

        /** A new course, made [now]. */
        fun make(name: String, symbol: String, colorIndex: Int, now: Long = System.currentTimeMillis()): NoteSection =
            NoteSection(
                id = UUID.randomUUID().toString().uppercase(Locale.ROOT),
                name = name,
                symbol = symbol,
                colorIndex = colorIndex,
                created = now - Math.floorMod(now, 1000L),
            )

        /** The course in an entry of sections.json; null when the iPad could not read it either (a
         *  field missing or of another type, an id that is not a UUID). */
        fun fromJson(json: JSONObject): NoteSection? {
            val id = normalizedId(json.opt("id") as? String) ?: return null
            val name = json.opt("name") as? String ?: return null
            val symbol = json.opt("symbol") as? String ?: return null
            val colorIndex = wholeNumber(json.opt("colorIndex")) ?: return null
            val created = (json.opt("created") as? String)?.let { NotebookMeta.parseTime(it) } ?: return null
            return NoteSection(id, name, symbol, colorIndex, created)
        }

        /** A JSON number without a fraction that fits an Int (as Swift's Int decodes one). */
        private fun wholeNumber(value: Any?): Int? = when (value) {
            is Int -> value
            is Long -> value.takeIf { it in Int.MIN_VALUE..Int.MAX_VALUE }?.toInt()
            is Double -> value.takeIf { it % 1.0 == 0.0 && it >= Int.MIN_VALUE && it <= Int.MAX_VALUE }?.toInt()
            else -> null
        }
    }
}

/**
 * sections.json read entry by entry (LenientList in SafeFiles.swift): the courses, and the entries
 * this build could not read, as they came. A second entry with a course's id counts as unreadable,
 * so the list never holds one course twice.
 */
class SectionList(val items: List<NoteSection>, val unreadable: List<Any>) {
    /** The file: the courses, then the unreadable entries as they were. */
    fun encode(): String {
        val list = JSONArray()
        for (section in items) list.put(section.toJson())
        for (entry in unreadable) list.put(entry)
        return list.toString()
    }

    companion object {
        val EMPTY = SectionList(emptyList(), emptyList())

        /** The list in [text]; null when it is not a JSON list at all (then there is nothing to keep). */
        fun decode(text: String): SectionList? {
            val list = try {
                JSONArray(text)
            } catch (e: JSONException) {
                return null
            }
            val items = ArrayList<NoteSection>()
            val unreadable = ArrayList<Any>()
            val seen = HashSet<String>()
            for (i in 0 until list.length()) {
                val entry = list.opt(i) ?: JSONObject.NULL
                // Only an object can be an entry; anything else is kept as it came.
                val section = (entry as? JSONObject)?.let { NoteSection.fromJson(it) }
                if (section != null && seen.add(section.id)) items.add(section) else unreadable.add(entry)
            }
            return SectionList(items, unreadable)
        }
    }
}
