package com.murekkep.notebook.data

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.ConscryptMode
import java.time.Instant

// sections.json as the iPad writes and reads it (NoteSection in Sections.swift, LenientList in
// SafeFiles.swift, whose cases in tools/safefilescheck/main.swift are taken over here), and a note's
// course in its record under the iPad's key "sectionID". On Robolectric for Android's org.json.
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
@ConscryptMode(ConscryptMode.Mode.OFF)
class SectionsTest {
    private val anatomy = "E621E1F8-C36C-495A-93FC-0C247A3E6E5F"
    private val calculus = "6B29FC40-CA47-1067-B31D-00DD010662DA"

    private fun entry(id: String, name: String, created: String = "2026-10-26T10:00:00Z") =
        """{"id": "$id", "name": "$name", "symbol": "atom", "colorIndex": 1, "created": "$created"}"""

    @Test
    fun theIpadsFileIsRead() {
        val file = """[{"id":"$anatomy","name":"Anatomi","symbol":"heart.text.square","colorIndex":5,"created":"2026-10-26T10:00:00Z"},
            {"id":"${calculus.lowercase()}","name":"Calculus","symbol":"function","colorIndex":0,"created":"2026-10-27T08:30:15Z"}]"""
        val read = SectionList.decode(file)
        assertNotNull(read)
        assertEquals(
            listOf(
                NoteSection(anatomy, "Anatomi", "heart.text.square", 5, Instant.parse("2026-10-26T10:00:00Z").toEpochMilli()),
                // An id in small letters is kept in capitals, as the iPad writes every UUID.
                NoteSection(calculus, "Calculus", "function", 0, Instant.parse("2026-10-27T08:30:15Z").toEpochMilli()),
            ),
            read!!.items,
        )
        assertTrue(read.unreadable.isEmpty())
    }

    @Test
    fun aCourseIsWrittenAsTheIpadReadsIt() {
        // Made at a moment with milliseconds: the file keeps whole seconds, which .iso8601 reads.
        val made = Instant.parse("2026-10-30T01:02:03.456Z").toEpochMilli()
        val json = NoteSection(anatomy, "Anatomi", "heart.text.square", 5, made).toJson()
        assertEquals(setOf("id", "name", "symbol", "colorIndex", "created"), json.keys().asSequence().toSet())
        assertEquals(anatomy, json.getString("id"))
        assertEquals("Anatomi", json.getString("name"))
        assertEquals("heart.text.square", json.getString("symbol"))
        assertEquals(5, json.getInt("colorIndex"))
        assertEquals("2026-10-30T01:02:03Z", json.getString("created"))
        // A new course is made in whole seconds, its id an upper-case UUID.
        val fresh = NoteSection.make("Calculus", "function", 0, now = made)
        assertEquals(Instant.parse("2026-10-30T01:02:03Z").toEpochMilli(), fresh.created)
        assertEquals(fresh.id, NoteSection.normalizedId(fresh.id))
        assertEquals(fresh.id.uppercase(), fresh.id)
        assertEquals(listOf(fresh), SectionList.decode(SectionList(listOf(fresh), emptyList()).encode())!!.items)
    }

    @Test
    fun oneBadEntryNeverEmptiesTheList() {
        val mixed = """[${entry(anatomy, "first")},
            {"id": "two", "name": "from a newer build", "symbol": "atom", "colorIndex": 2, "created": "2026-10-26T11:00:00Z", "extra": {"deep": [1, 2]}},
            ${entry(calculus, "third", "2026-10-26T12:00:00Z")},
            "not even an object"]"""
        val read = SectionList.decode(mixed)!!
        assertEquals(listOf("first", "third"), read.items.map { it.name })
        assertEquals(2, read.unreadable.size)
        assertEquals("from a newer build", (read.unreadable.first() as JSONObject).getString("name"))
        assertEquals("not even an object", read.unreadable.last())

        // Written back: all four entries, the bad ones as they were, after the good ones.
        val written = read.encode()
        val back = JSONArray(written)
        assertEquals(4, back.length())
        val again = SectionList.decode(written)!!
        assertEquals(read.items, again.items)
        assertEquals(2, again.unreadable.size)
        val kept = back.getJSONObject(2)
        assertEquals(listOf(1, 2), kept.getJSONObject("extra").getJSONArray("deep").let { a -> (0 until a.length()).map { a.getInt(it) } })
        assertEquals("not even an object", back.getString(3))
    }

    @Test
    fun aGoodListHasNothingUnreadable() {
        val read = SectionList.decode("[${entry(anatomy, "five")}]")!!
        assertEquals(listOf("five"), read.items.map { it.name })
        assertTrue(read.unreadable.isEmpty())
    }

    @Test
    fun aFileThatIsNotAListHasNothingToKeep() {
        assertNull("an object is not a list", SectionList.decode("""{"a": 1}"""))
        assertNull("a cut file is not a list", SectionList.decode("[1, 2"))
        assertNull("an empty file is not a list", SectionList.decode(""))
        assertTrue("an empty list is a list", SectionList.decode("[]")!!.items.isEmpty())
    }

    @Test
    fun anEntryTheIpadCouldNotReadIsKeptAsItIs() {
        val missingDate = """{"id": "$anatomy", "name": "x", "symbol": "atom", "colorIndex": 1}"""
        val fraction = """{"id": "$anatomy", "name": "x", "symbol": "atom", "colorIndex": 2.5, "created": "2026-10-26T10:00:00Z"}"""
        val numberName = """{"id": "$anatomy", "name": 7, "symbol": "atom", "colorIndex": 1, "created": "2026-10-26T10:00:00Z"}"""
        val notADate = """{"id": "$anatomy", "name": "x", "symbol": "atom", "colorIndex": 1, "created": "yesterday"}"""
        for (bad in listOf(missingDate, fraction, numberName, notADate)) {
            val read = SectionList.decode("[$bad]")!!
            assertTrue(bad, read.items.isEmpty())
            assertEquals(bad, 1, read.unreadable.size)
        }
        // A whole number written with a point is still a number, as Swift's Int reads it.
        val whole = """{"id": "$anatomy", "name": "x", "symbol": "atom", "colorIndex": 2.0, "created": "2026-10-26T10:00:00Z"}"""
        assertEquals(2, SectionList.decode("[$whole]")!!.items.single().colorIndex)
    }

    @Test
    fun aSecondEntryWithACoursesIdIsKeptAside() {
        val read = SectionList.decode("[${entry(anatomy, "first")}, ${entry(anatomy.lowercase(), "again")}]")!!
        assertEquals(listOf("first"), read.items.map { it.name })
        assertEquals("again", (read.unreadable.single() as JSONObject).getString("name"))
    }

    @Test
    fun theColourWrapsAsTheIpads() {
        fun slot(i: Int) = NoteSection(anatomy, "x", "atom", i, 0).colorSlot
        assertEquals(listOf(0, 7, 0, 5, 7), listOf(slot(0), slot(7), slot(8), slot(13), slot(-1)))
    }

    @Test
    fun anIdIsAUuidInCapitals() {
        assertEquals(anatomy, NoteSection.normalizedId(anatomy.lowercase()))
        assertEquals(anatomy, NoteSection.normalizedId(" $anatomy "))
        assertNull(NoteSection.normalizedId("two"))
        assertNull(NoteSection.normalizedId("1-1-1-1-1"))
        assertNull(NoteSection.normalizedId(null))
    }

    @Test
    fun aNoteKeepsItsCourseUnderTheIpadsKey() {
        val meta = NotebookMeta(id = "n", title = "Kalp", created = 0, modified = 0, pageCount = 1, paper = PaperStyle.LINED, sectionId = anatomy)
        val json = meta.toJson()
        assertEquals(anatomy, json.getString("sectionID"))
        assertEquals(anatomy, NotebookMeta.fromJson(json, "n").sectionId)
        // In no course the key is left out, as the iPad leaves out a nil sectionID.
        assertFalse(meta.copy(sectionId = null).toJson().has("sectionID"))
        // Missing, null, or not a UUID: in no course; small letters read in capitals.
        assertNull(NotebookMeta.fromJson(json.apply { remove("sectionID") }, "n").sectionId)
        assertNull(NotebookMeta.fromJson(JSONObject(json.toString()).put("sectionID", JSONObject.NULL), "n").sectionId)
        assertNull(NotebookMeta.fromJson(JSONObject(json.toString()).put("sectionID", "anatomi"), "n").sectionId)
        assertEquals(anatomy, NotebookMeta.fromJson(JSONObject(json.toString()).put("sectionID", anatomy.lowercase()), "n").sectionId)
    }
}
