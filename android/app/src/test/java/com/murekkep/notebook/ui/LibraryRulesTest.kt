package com.murekkep.notebook.ui

import com.murekkep.notebook.data.NoteKind
import com.murekkep.notebook.data.NotebookMeta
import com.murekkep.notebook.data.PaperStyle
import org.junit.Assert.assertEquals
import org.junit.Test
import java.time.LocalDateTime
import java.time.ZoneId
import java.util.Locale

// The library's rules: the page count a cover shows, the sections and the filter, the orders, the
// search, the counts, the covers' columns, the filter's segments and the time under a cover.
class LibraryRulesTest {
    private fun note(title: String, kind: NoteKind = NoteKind.NOTEBOOK, modified: Long = 0, pages: Int = 1) =
        NotebookMeta(id = title, title = title, created = 0, modified = modified, pageCount = pages, paper = PaperStyle.LINED, kind = kind)

    private val turkish = Locale.forLanguageTag("tr")

    @Test
    fun aCoverCountsTheRecordsPages() {
        // A notebook's record counts the blank page waiting for the pen, as the iPad prints it.
        assertEquals(1, LibraryRules.pagesShown(1))
        assertEquals(2, LibraryRules.pagesShown(2))
        assertEquals(204, LibraryRules.pagesShown(204))
        assertEquals(1, LibraryRules.pagesShown(0))
    }

    @Test
    fun theSectionsFilterByKindAndKeepTheOrder() {
        val notes = listOf(
            note("Hücre", modified = 3), note("Türev", modified = 5), note("Kitap", kind = NoteKind.PDF, modified = 4),
        )
        val all = LibraryFilter.ALL
        val order = LibrarySort.MODIFIED
        assertEquals(listOf("Türev", "Kitap", "Hücre"), LibraryRules.shown(notes, LibrarySection.ALL, all, order).map { it.title })
        assertEquals(listOf("Türev", "Hücre"), LibraryRules.shown(notes, LibrarySection.NOTEBOOKS, all, order).map { it.title })
        assertEquals(listOf("Kitap"), LibraryRules.shown(notes, LibrarySection.PDFS, all, order).map { it.title })
    }

    @Test
    fun theFilterBelongsToAllNotes() {
        val notes = listOf(note("Hücre", modified = 3), note("Kitap", kind = NoteKind.PDF, modified = 4))
        val order = LibrarySort.MODIFIED
        assertEquals(listOf("Kitap"), LibraryRules.shown(notes, LibrarySection.ALL, LibraryFilter.PDFS, order).map { it.title })
        assertEquals(listOf("Hücre"), LibraryRules.shown(notes, LibrarySection.ALL, LibraryFilter.NOTEBOOKS, order).map { it.title })
        // Defterler stays the notebooks whatever the filter was left at.
        assertEquals(listOf("Hücre"), LibraryRules.shown(notes, LibrarySection.NOTEBOOKS, LibraryFilter.PDFS, order).map { it.title })
    }

    @Test
    fun recentIsTheFortyLastChanged() {
        val notes = (1..50).map { note("n$it", modified = it.toLong()) }
        // Neither the filter nor the order touches it.
        val recent = LibraryRules.shown(notes, LibrarySection.RECENT, LibraryFilter.PDFS, LibrarySort.TITLE)
        assertEquals(LibraryRules.RECENT_COUNT, recent.size)
        assertEquals(40, recent.size)
        assertEquals("n50", recent.first().title)
        assertEquals("n11", recent.last().title)
    }

    @Test
    fun byNameIsFinderOrder() {
        val titles = listOf("Zeka", "Not 10", "çini", "Not 9", "abc", "Ödev", "not 2", "Not 09a")
        val sorted = titles.sortedWith(LibraryRules.titleOrder(turkish))
        assertEquals(listOf("abc", "çini", "not 2", "Not 9", "Not 09a", "Not 10", "Ödev", "Zeka"), sorted)
        val notes = listOf(note("b", modified = 1), note("A", modified = 2), note("c", modified = 3))
        assertEquals(listOf("A", "b", "c"), LibraryRules.sorted(notes, LibrarySort.TITLE, turkish).map { it.title })
        assertEquals(listOf("c", "A", "b"), LibraryRules.sorted(notes, LibrarySort.MODIFIED).map { it.title })
    }

    @Test
    fun theStoredPlacesReadBack() {
        assertEquals(LibrarySection.PDFS, LibrarySection.fromRaw("pdfs"))
        assertEquals(LibrarySection.ALL, LibrarySection.fromRaw("home"))
        assertEquals(LibrarySection.ALL, LibrarySection.fromRaw(null))
        assertEquals(LibraryFilter.NOTEBOOKS, LibraryFilter.fromRaw("notebooks"))
        assertEquals(LibraryFilter.ALL, LibraryFilter.fromRaw("courses"))
        assertEquals(LibrarySort.TITLE, LibrarySort.fromRaw("title"))
        // The third order of earlier builds is gone: it reads as the last edit.
        assertEquals(LibrarySort.MODIFIED, LibrarySort.fromRaw("CREATED"))
        assertEquals(LibrarySort.MODIFIED, LibrarySort.fromRaw(null))
    }

    @Test
    fun aSearchLooksThroughEveryNote() {
        val notes = listOf(note("Biyoloji", modified = 1), note("biyokimya", kind = NoteKind.PDF, modified = 2), note("Kimya", modified = 3))
        assertEquals(listOf("biyokimya", "Biyoloji"), LibraryRules.searched(notes, " BİYO ", turkish).map { it.title })
        assertEquals(listOf("Kimya", "biyokimya"), LibraryRules.searched(notes, "kimya", turkish).map { it.title })
        assertEquals(emptyList<NotebookMeta>(), LibraryRules.searched(notes, "  ", turkish))
    }

    @Test
    fun theSidebarCounts() {
        val notes = listOf(note("a"), note("b"), note("p", kind = NoteKind.PDF))
        assertEquals(Triple(3, 2, 1), LibraryRules.counts(notes))
    }

    @Test
    fun theCoversColumns() {
        // The iPad's adaptive(190...260) with 28 between: four across a Pixel Tablet's 911 dp, a fifth from 1062.
        assertEquals(4 to 206.75f, LibraryRules.adaptiveColumns(911f, 190f, 260f, 28f))
        assertEquals(4, LibraryRules.adaptiveColumns(1061f, 190f, 260f, 28f).first)
        assertEquals(5, LibraryRules.adaptiveColumns(1062f, 190f, 260f, 28f).first)
        // A phone's single column stops at 260, and there is always one.
        assertEquals(1 to 260f, LibraryRules.adaptiveColumns(368f, 190f, 260f, 28f))
        assertEquals(1 to 100f, LibraryRules.adaptiveColumns(100f, 190f, 260f, 28f))
        // The theme tiles' 112...150 with 14 between.
        assertEquals(2 to 143f, LibraryRules.adaptiveColumns(300f, 112f, 150f, 14f))
        assertEquals(1 to 150f, LibraryRules.adaptiveColumns(200f, 112f, 150f, 14f))
    }

    @Test
    fun theFiltersSegments() {
        // Equal thirds while every label fits in one, as the iPad's picker has them.
        assertEquals(listOf(105, 105, 105), LibraryRules.segmentWidths(listOf(39, 60, 49), 315))
        // A 360 dp phone's 172: "Defterler" would be cut in a third, so each takes its label and a share of the rest.
        assertEquals(listOf(48, 67, 57), LibraryRules.segmentWidths(listOf(39, 58, 49), 172))
        // Narrower still: the short labels whole, the long ones share what is left.
        assertEquals(listOf(30, 35, 35), LibraryRules.segmentWidths(listOf(30, 70, 50), 100))
        // The pixels lost to rounding go to the first segments, so the track is filled.
        assertEquals(listOf(34, 33, 33), LibraryRules.segmentWidths(listOf(10, 10, 10), 100))
        assertEquals(emptyList<Int>(), LibraryRules.segmentWidths(emptyList(), 100))
    }

    @Test
    fun theTimeUnderACover() {
        val zone = ZoneId.of("Europe/Istanbul")
        fun at(month: Int, day: Int, hour: Int, minute: Int = 0, year: Int = 2026) =
            LocalDateTime.of(year, month, day, hour, minute).atZone(zone).toInstant().toEpochMilli()
        val now = at(10, 29, 9)
        fun age(then: Long) = LibraryRules.relativeAge(then, now, zone)
        assertEquals(RelativeAge(AgeUnit.SECOND, 0), age(now))
        assertEquals(RelativeAge(AgeUnit.SECOND, 8), age(now - 8_000))
        assertEquals(RelativeAge(AgeUnit.MINUTE, 15), age(now - 15 * 60_000 - 5_000))
        // Last night is hours ago, not yesterday.
        assertEquals(RelativeAge(AgeUnit.HOUR, 10), age(at(10, 28, 23)))
        assertEquals(RelativeAge(AgeUnit.DAY, 1), age(at(10, 28, 8)))
        // 35 hours, but two days back: "evvelsi gün".
        assertEquals(RelativeAge(AgeUnit.DAY, 2), age(at(10, 27, 22)))
        assertEquals(RelativeAge(AgeUnit.WEEK, 1), age(at(10, 21, 12)))
        assertEquals(RelativeAge(AgeUnit.WEEK, 3), age(at(10, 7, 9)))
        assertEquals(RelativeAge(AgeUnit.MONTH, 1), age(at(9, 20, 9)))
        assertEquals(RelativeAge(AgeUnit.YEAR, 2), age(at(6, 1, 9, year = 2024)))
        // A clock that ran ahead says now.
        assertEquals(RelativeAge(AgeUnit.SECOND, 0), age(now + 60_000))
    }
}
