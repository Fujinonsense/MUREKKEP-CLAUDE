package com.murekkep.notebook.data

import org.json.JSONArray
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
    /** When the note was last opened in the editor (the library's "Son açılanlar"); its last change until then. */
    val opened: Long = modified,
    /** Starred in the library (the iPad's NoteMeta.starred, kept under its key "isFavorite"). */
    val starred: Boolean = false,
    /** The pages marked with the ribbon (0-based, in order; the iPad's NoteMeta.bookmarks, left out
     *  when there are none). */
    val bookmarks: List<Int> = emptyList(),
    /** The course it is filed under (the iPad's NoteMeta.sectionID, kept under that key), an
     *  upper-case UUID; null in none. */
    val sectionId: String? = null,
) {
    fun toJson(): JSONObject = JSONObject()
        .put("id", id)
        .put("title", title)
        .put("created", Instant.ofEpochMilli(created).toString())
        .put("modified", Instant.ofEpochMilli(modified).toString())
        .put("opened", Instant.ofEpochMilli(opened).toString())
        .put("pageCount", pageCount)
        .put("paper", paper.raw)
        .put("kind", kind.raw)
        .put("isFavorite", starred)
        .also { if (bookmarks.isNotEmpty()) it.put("bookmarks", JSONArray(bookmarks)) }
        // Left out in no course, as the iPad leaves out a nil sectionID.
        .apply { if (sectionId != null) put("sectionID", sectionId) }

    companion object {
        /** The record in a folder named `id`; missing or odd fields take sensible defaults. */
        fun fromJson(json: JSONObject, id: String): NotebookMeta {
            val now = System.currentTimeMillis()
            val created = parseTime(json.opt("created")) ?: now
            val modified = parseTime(json.opt("modified")) ?: created
            return NotebookMeta(
                id = id,
                title = json.optString("title", ""),
                created = created,
                modified = modified,
                pageCount = json.optInt("pageCount", 1).coerceAtLeast(1),
                paper = PaperStyle.fromRaw(json.optString("paper", "")),
                kind = NoteKind.fromRaw(json.optString("kind", "")),
                opened = parseTime(json.opt("opened")) ?: modified,
                // Missing in older records: not starred.
                starred = json.optBoolean("isFavorite", false),
                bookmarks = json.optJSONArray("bookmarks")?.let { a -> (0 until a.length()).mapNotNull { (a.opt(it) as? Number)?.toInt() } } ?: emptyList(),
                // Missing, null or not a UUID: in no course.
                sectionId = NoteSection.normalizedId(json.opt("sectionID") as? String),
            )
        }

        /** ISO-8601 (as the iPad's index.json) or epoch milliseconds. */
        internal fun parseTime(value: Any?): Long? = when (value) {
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
