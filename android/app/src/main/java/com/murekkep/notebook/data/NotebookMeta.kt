package com.murekkep.notebook.data

import org.json.JSONObject
import java.time.Instant
import java.time.format.DateTimeParseException

// A notebook's record on disk (Murekkep.swiftpm/LibraryStore.swift: NoteMeta, NoteKind, and
// PaperStyle from Templates.swift): one folder a note, a notebook or an imported PDF.

/** A notebook of blank pages, or a PDF written on. Raw values are the iPad's. */
enum class NoteKind(val raw: String) {
    NOTEBOOK("notebook"),
    PDF("pdf");

    companion object {
        fun fromRaw(raw: String?): NoteKind = entries.firstOrNull { it.raw == raw } ?: NOTEBOOK
    }
}

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
    /** An imported PDF keeps it as `source.pdf` in its folder, its pages are the PDF's. */
    val kind: NoteKind = NoteKind.NOTEBOOK,
) {
    fun toJson(): JSONObject = JSONObject()
        .put("id", id)
        .put("title", title)
        .put("created", Instant.ofEpochMilli(created).toString())
        .put("modified", Instant.ofEpochMilli(modified).toString())
        .put("pageCount", pageCount)
        .put("paper", paper.raw)
        .put("kind", kind.raw)

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
                kind = NoteKind.fromRaw(json.optString("kind", "")),
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
