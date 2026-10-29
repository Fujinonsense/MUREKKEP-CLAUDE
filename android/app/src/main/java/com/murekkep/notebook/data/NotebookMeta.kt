package com.murekkep.notebook.data

import org.json.JSONObject
import java.time.Instant
import java.time.format.DateTimeParseException

// A notebook's record on disk (Murekkep.swiftpm/LibraryStore.swift: NoteMeta, and PaperStyle from
// Templates.swift). The Android edition keeps notebooks only (no PDFs yet), one folder a notebook.

/** Page template of a notebook. Raw values are the iPad's (they are stored in meta.json); existing
 *  ones never change. */
enum class PaperStyle(val raw: String) {
    PLAIN("plain"),
    LINED("lined"),
    GRID("grid"),
    DOTTED("dotted"),
    NARROW_LINED("narrowLined"),
    SMALL_GRID("smallGrid"),
    ENGINEERING("engineering"),
    ISOMETRIC("isometric"),
    HEXAGON("hexagon"),
    MUSIC("music"),
    HANDWRITING("handwriting"),
    TODO("todo"),
    DAILY("daily"),
    WEEKLY("weekly"),
    MONTHLY("monthly"),
    MEETING("meeting"),
    RESUME("resume"),
    LETTER("letter"),
    CORNELL("cornell"),
    STORYBOARD("storyboard");

    companion object {
        /** Unknown raw values (a newer app's templates) read as lined paper. */
        fun fromRaw(raw: String?): PaperStyle = entries.firstOrNull { it.raw == raw } ?: LINED
    }
}

/** One notebook in the library: `meta.json` in its folder. Times are epoch milliseconds. */
data class NotebookMeta(
    /** The folder's name (a UUID). */
    val id: String,
    val title: String,
    val created: Long,
    val modified: Long,
    val pageCount: Int,
    val paper: PaperStyle,
) {
    fun toJson(): JSONObject = JSONObject()
        .put("id", id)
        .put("title", title)
        .put("created", Instant.ofEpochMilli(created).toString())
        .put("modified", Instant.ofEpochMilli(modified).toString())
        .put("pageCount", pageCount)
        .put("paper", paper.raw)

    companion object {
        /** The record in a folder named `id`; missing or odd fields take sensible defaults. */
        fun fromJson(json: JSONObject, id: String): NotebookMeta {
            val now = System.currentTimeMillis()
            val created = parseTime(json.opt("created")) ?: now
            return NotebookMeta(
                id = id,
                title = json.optString("title", ""),
                created = created,
                modified = parseTime(json.opt("modified")) ?: created,
                pageCount = json.optInt("pageCount", 1).coerceAtLeast(1),
                paper = PaperStyle.fromRaw(json.optString("paper", "")),
            )
        }

        /** ISO-8601 (as the iPad's index.json) or epoch milliseconds. */
        private fun parseTime(value: Any?): Long? = when (value) {
            is Number -> value.toLong()
            is String -> try {
                Instant.parse(value).toEpochMilli()
            } catch (e: DateTimeParseException) {
                value.toLongOrNull()
            }
            else -> null
        }
    }
}
