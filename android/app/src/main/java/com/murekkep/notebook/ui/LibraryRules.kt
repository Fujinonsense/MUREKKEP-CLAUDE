package com.murekkep.notebook.ui

import com.murekkep.notebook.data.NoteKind
import com.murekkep.notebook.data.NoteSection
import com.murekkep.notebook.data.NotebookMeta
import java.text.Collator
import java.time.Instant
import java.time.ZoneId
import java.time.ZonedDateTime
import java.time.temporal.ChronoUnit
import java.util.Locale
import kotlin.math.max
import kotlin.math.min

// The library's pure rules (NotesPane, SearchPane, CoursePane and NoteCard on iPad): which notes a
// section or a course shows, in what order, what a search finds, how the covers fill a row, how
// wide the filter's segments are, and what a cover's line says ("3 sayfa, dün").

/** The sidebar's sections; raw values are the iPad's `library.place`. */
enum class LibrarySection(val raw: String) {
    ALL("home"),
    RECENT("recent"),
    FAVORITES("favorites"),
    NOTEBOOKS("notebooks"),
    PDFS("pdfs");

    companion object {
        fun fromRaw(raw: String?): LibrarySection = entries.firstOrNull { it.raw == raw } ?: ALL
    }
}

/**
 * Where the library is (LibraryPlace on iPad): a list of the sidebar, or a course by its id. The raw
 * value is the iPad's `library.place`: the list's, or "course:" and the course's id. A course keeps
 * Tüm notlar under it, where the iPad goes when the course is gone.
 */
data class LibraryPlace(val section: LibrarySection, val course: String? = null) {
    val raw: String get() = if (course != null) COURSE_PREFIX + course else section.raw

    companion object {
        private const val COURSE_PREFIX = "course:"

        fun course(id: String) = LibraryPlace(LibrarySection.ALL, id)

        /** A course's place when [raw] names a UUID after "course:", else the list's (Tüm notlar for
         *  anything unknown, a "course:" without a UUID too, as on iPad). */
        fun fromRaw(raw: String?): LibraryPlace {
            val id = raw?.takeIf { it.startsWith(COURSE_PREFIX) }?.let { NoteSection.normalizedId(it.removePrefix(COURSE_PREFIX)) }
            return if (id != null) course(id) else LibraryPlace(LibrarySection.fromRaw(raw))
        }
    }
}

/** A course's tabs, Kaynaklar and Defterler (CoursePane on iPad, whose Stüdyo Android does not
 *  have); raw values are the iPad's `course.tab`. */
enum class CourseTab(val raw: String) {
    SOURCES("sources"),
    NOTEBOOKS("notebooks");

    companion object {
        /** An unknown tab (the iPad's "studio") reads as Kaynaklar. */
        fun fromRaw(raw: String?): CourseTab = entries.firstOrNull { it.raw == raw } ?: SOURCES
    }
}

/** The filter of Tüm notlar (Hepsi, Defterler, PDF'ler); raw values are the iPad's `library.filter`. */
enum class LibraryFilter(val raw: String) {
    ALL("all"),
    NOTEBOOKS("notebooks"),
    PDFS("pdfs");

    companion object {
        fun fromRaw(raw: String?): LibraryFilter = entries.firstOrNull { it.raw == raw } ?: ALL
    }
}

/** The orders, "Son düzenlenen" and "Ada göre"; raw values are the iPad's `library.sort`. */
enum class LibrarySort(val raw: String) {
    MODIFIED("modified"),
    TITLE("title");

    companion object {
        /** An unknown order (the "created" of earlier builds) reads as the last edit. */
        fun fromRaw(raw: String?): LibrarySort = entries.firstOrNull { it.raw == raw } ?: MODIFIED
    }
}

/** The units of a cover's time, from the smallest. */
enum class AgeUnit { SECOND, MINUTE, HOUR, DAY, WEEK, MONTH, YEAR }

/** How long ago something was: "8 saniye önce" is (SECOND, 8), "dün" (DAY, 1); (SECOND, 0) is now. */
data class RelativeAge(val unit: AgeUnit, val count: Int)

object LibraryRules {
    /** How many notes "Son açılanlar" shows. */
    const val RECENT_COUNT = 40

    /** How many pages the cover says a note has: the record's count, the blank page a notebook
     *  keeps for the pen included, as the iPad prints it and the page badge counts it. */
    fun pagesShown(pageCount: Int): Int = max(1, pageCount)

    /** The notes of a section in the section's order: Tüm notlar through its filter, Son açılanlar
     *  the last [RECENT_COUNT] changed, Favoriler the starred ones. */
    fun shown(notes: List<NotebookMeta>, section: LibrarySection, filter: LibraryFilter, sort: LibrarySort): List<NotebookMeta> =
        when (section) {
            LibrarySection.RECENT -> notes.sortedByDescending { it.modified }.take(RECENT_COUNT)
            LibrarySection.FAVORITES -> sorted(notes.filter { it.starred }, sort)
            LibrarySection.NOTEBOOKS -> sorted(notes.filter { it.kind == NoteKind.NOTEBOOK }, sort)
            LibrarySection.PDFS -> sorted(notes.filter { it.kind == NoteKind.PDF }, sort)
            LibrarySection.ALL -> sorted(
                when (filter) {
                    LibraryFilter.ALL -> notes
                    LibraryFilter.NOTEBOOKS -> notes.filter { it.kind == NoteKind.NOTEBOOK }
                    LibraryFilter.PDFS -> notes.filter { it.kind == NoteKind.PDF }
                },
                sort,
            )
        }

    /** What a search finds: every note whose title holds the query, or whose course's name does
     *  (SearchPane on iPad), whatever its section, the last changed first. */
    fun searched(
        notes: List<NotebookMeta>,
        query: String,
        locale: Locale = Locale.getDefault(),
        sections: List<NoteSection> = emptyList(),
    ): List<NotebookMeta> {
        val q = query.trim().lowercase(locale)
        if (q.isEmpty()) return emptyList()
        val courses = searchedCourses(sections, query, locale).mapTo(HashSet()) { it.id }
        return sorted(notes.filter { q in it.title.lowercase(locale) || it.sectionId in courses }, LibrarySort.MODIFIED)
    }

    /** The courses a search finds: those whose name holds the query, in the sidebar's order. */
    fun searchedCourses(sections: List<NoteSection>, query: String, locale: Locale = Locale.getDefault()): List<NoteSection> {
        val q = query.trim().lowercase(locale)
        if (q.isEmpty()) return emptyList()
        return sections.filter { q in it.name.lowercase(locale) }
    }

    /** A course's notes, the last changed first (the order the iPad's store keeps them in). */
    fun courseNotes(notes: List<NotebookMeta>, course: String): List<NotebookMeta> =
        notes.filter { it.sectionId == course }.sortedByDescending { it.modified }

    /** How many notes each course holds, by its id (the sidebar's counts). */
    fun courseCounts(notes: List<NotebookMeta>): Map<String, Int> =
        notes.mapNotNull { it.sectionId }.groupingBy { it }.eachCount()

    fun sorted(notes: List<NotebookMeta>, sort: LibrarySort, locale: Locale = Locale.getDefault()): List<NotebookMeta> = when (sort) {
        LibrarySort.MODIFIED -> notes.sortedByDescending { it.modified }
        LibrarySort.TITLE -> titleOrder(locale).let { order -> notes.sortedWith { a, b -> order.compare(a.title, b.title) } }
    }

    /**
     * "Ada göre" as Finder orders names (localizedStandardCompare on iPad): the language's alphabet,
     * capitals and small letters alike, and runs of digits by their value, so "Not 9" comes before
     * "Not 10" and, in Turkish, "Çini" before "Zeka".
     */
    fun titleOrder(locale: Locale = Locale.getDefault()): Comparator<String> {
        val collator = Collator.getInstance(locale).apply { strength = Collator.SECONDARY }
        return Comparator { a, b ->
            val x = runs(a)
            val y = runs(b)
            for (i in 0 until min(x.size, y.size)) {
                val p = x[i]
                val q = y[i]
                val c = if (p[0].isDigit() && q[0].isDigit()) compareNumbers(p, q) else collator.compare(p, q)
                if (c != 0) return@Comparator c
            }
            x.size.compareTo(y.size)
        }
    }

    /** "Not 10" as "Not ", "10": the runs of digits and of everything else. */
    private fun runs(s: String): List<String> {
        val out = ArrayList<String>()
        var i = 0
        while (i < s.length) {
            val digits = s[i].isDigit()
            var j = i + 1
            while (j < s.length && s[j].isDigit() == digits) j++
            out.add(s.substring(i, j))
            i = j
        }
        return out
    }

    /** Two runs of digits by their value, however long; leading zeros do not count. */
    private fun compareNumbers(a: String, b: String): Int {
        val x = a.trimStart('0')
        val y = b.trimStart('0')
        return if (x.length != y.length) x.length.compareTo(y.length) else x.compareTo(y)
    }

    /** The sidebar's counts: all notes, notebooks, PDFs. */
    fun counts(notes: List<NotebookMeta>): Triple<Int, Int, Int> {
        val pdfs = notes.count { it.kind == NoteKind.PDF }
        return Triple(notes.size, notes.size - pdfs, pdfs)
    }

    /**
     * An adaptive grid's columns (GridItem.adaptive on iPad): as many as fit at [minWidth] with
     * [spacing] between them, at least one, each then as wide as the row allows up to [maxWidth].
     * The count and the width, in the units given.
     */
    fun adaptiveColumns(available: Float, minWidth: Float, maxWidth: Float, spacing: Float): Pair<Int, Float> {
        val n = max(1, ((available + spacing) / (minWidth + spacing)).toInt())
        return n to min((available - spacing * (n - 1)) / n, maxWidth)
    }

    /**
     * The widths of a segmented control's segments across [total], given the width each label
     * needs with its padding ([natural]): equal shares, as the iPad's picker has them, while every
     * label fits in one. When an equal share would cut a label, each segment takes its label's
     * width and the room left is shared out evenly; when even that does not fit, the short labels
     * keep their width and the long ones share what is left. The widths fill [total] exactly.
     */
    fun segmentWidths(natural: List<Int>, total: Int): List<Int> {
        val n = natural.size
        if (n == 0) return emptyList()
        val widths = when {
            natural.all { it * n <= total } -> IntArray(n) { total / n }
            natural.sum() <= total -> {
                val extra = (total - natural.sum()) / n
                IntArray(n) { natural[it] + extra }
            }
            else -> {
                val out = IntArray(n)
                var left = total
                var count = n
                for (i in natural.indices.sortedBy { natural[it] }) {
                    out[i] = min(natural[i], left / count)
                    left -= out[i]
                    count--
                }
                out
            }
        }
        // The pixels lost to rounding go to the first segments.
        val rest = total - widths.sum()
        return widths.mapIndexed { i, w -> if (i < rest) w + 1 else w }
    }

    /**
     * How long ago [then] was at [now], as the iPad's named relative style picks it: the largest
     * calendar unit that is not zero; from a day up, counted between the days themselves, so last
     * evening seen this morning is "10 saat önce", the evening before is "evvelsi gün". Seconds
     * are whole; a time in the future is now.
     */
    fun relativeAge(then: Long, now: Long, zone: ZoneId): RelativeAge {
        val from = Instant.ofEpochMilli(then).truncatedTo(ChronoUnit.SECONDS).atZone(zone)
        val to = Instant.ofEpochMilli(now).truncatedTo(ChronoUnit.SECONDS).atZone(zone)
        if (!from.isBefore(to)) return RelativeAge(AgeUnit.SECOND, 0)
        val age = largestUnit(from, to)
        if (age.unit < AgeUnit.DAY) return age
        return largestUnit(from.toLocalDate().atStartOfDay(zone), to.toLocalDate().atStartOfDay(zone))
    }

    /** Calendar.dateComponents([year, month, weekOfMonth, day, hour, minute, second], from:to:): the
     *  largest that is not zero. */
    private fun largestUnit(from: ZonedDateTime, to: ZonedDateTime): RelativeAge {
        var t = from
        val parts = ArrayList<Pair<AgeUnit, Long>>()
        for ((unit, chrono) in CALENDAR_UNITS) {
            val n = chrono.between(t, to)
            t = t.plus(n, chrono)
            parts.add(unit to n)
        }
        val (unit, n) = parts.firstOrNull { it.second > 0 } ?: return RelativeAge(AgeUnit.SECOND, 0)
        return RelativeAge(unit, n.coerceAtMost(Int.MAX_VALUE.toLong()).toInt())
    }

    private val CALENDAR_UNITS = listOf(
        AgeUnit.YEAR to ChronoUnit.YEARS,
        AgeUnit.MONTH to ChronoUnit.MONTHS,
        AgeUnit.WEEK to ChronoUnit.WEEKS,
        AgeUnit.DAY to ChronoUnit.DAYS,
        AgeUnit.HOUR to ChronoUnit.HOURS,
        AgeUnit.MINUTE to ChronoUnit.MINUTES,
        AgeUnit.SECOND to ChronoUnit.SECONDS,
    )
}
