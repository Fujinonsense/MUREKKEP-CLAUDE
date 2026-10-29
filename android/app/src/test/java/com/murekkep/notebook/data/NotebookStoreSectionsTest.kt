package com.murekkep.notebook.data

import android.content.Context
import android.os.Looper
import androidx.test.core.app.ApplicationProvider
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.ConscryptMode
import java.io.File

// The store keeps the courses as the iPad's LibraryStore does: sections.json at the library's root
// (made, changed and deleted courses written to it, its unreadable entries kept, a file that is not
// a list copied aside), each note's course in its own record, a deleted course's notes left in the
// library in no course, a course made before the first read of the disk never writing over the
// ones there, and a write that fails (a full disk) leaving the old file, as the iPad's try? does.
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
@ConscryptMode(ConscryptMode.Mode.OFF)
class NotebookStoreSectionsTest {
    private val context: Context get() = ApplicationProvider.getApplicationContext()
    private val root: File get() = File(context.filesDir, "notebooks")
    private val sectionsFile: File get() = File(root, "sections.json")

    private val anatomy = "E621E1F8-C36C-495A-93FC-0C247A3E6E5F"
    private val ipadsFile = """[{"id":"$anatomy","name":"Anatomi","symbol":"heart.text.square","colorIndex":5,"created":"2026-10-26T10:00:00Z"},
        {"id":"from-a-newer-build","name":"?","symbol":"sparkles","colorIndex":1,"created":"2026-10-26T10:00:00Z","extra":true}]"""

    @Before
    fun freshStore() {
        // The store is one per process: each test reads its own folders.
        NotebookStore::class.java.getDeclaredField("shared").apply { isAccessible = true }.set(null, null)
    }

    /** Runs the main thread's work until [done], as the screen's frames would. */
    private fun idleUntil(what: String, done: () -> Boolean) {
        val end = System.currentTimeMillis() + 5_000
        while (!done()) {
            shadowOf(Looper.getMainLooper()).idle()
            if (System.currentTimeMillis() > end) fail("timed out waiting for $what")
            Thread.sleep(5)
        }
    }

    private fun loaded(): NotebookStore {
        val store = NotebookStore.get(context)
        var done = false
        CoroutineScope(Dispatchers.Main.immediate).launch {
            store.load()
            done = true
        }
        idleUntil("the first read") { done }
        return store
    }

    private fun writeNote(id: String, sectionId: String? = null, modified: Long = 0) {
        val meta = NotebookMeta(id = id, title = id, created = 0, modified = modified, pageCount = 1, paper = PaperStyle.LINED, sectionId = sectionId)
        File(root, id).apply { mkdirs() }.resolve("meta.json").writeText(meta.toJson().toString())
    }

    /** Runs the main thread's work until the store's own jobs (its writes) are over. */
    private fun idleUntilWritten(store: NotebookStore) {
        val scope = NotebookStore::class.java.getDeclaredField("scope").apply { isAccessible = true }.get(store) as CoroutineScope
        val jobs = scope.coroutineContext[Job]!!
        idleUntil("the writes") { jobs.children.none() }
    }

    private fun record(id: String): JSONObject = JSONObject(File(root, "$id/meta.json").readText())

    private fun fileNames(): List<String> = (0 until JSONArray(sectionsFile.readText()).length()).map {
        JSONArray(sectionsFile.readText()).getJSONObject(it).optString("name")
    }

    @Test
    fun aCourseIsWrittenAndReadBack() {
        val store = loaded()
        val made = store.createSection("  Anatomi ", "heart.text.square", 5)
        assertEquals("Anatomi", made.name)
        idleUntil("the file") { sectionsFile.isFile && "Anatomi" in sectionsFile.readText() }
        store.updateSection(made.copy(name = "Anatomy", colorIndex = 2))
        idleUntil("the change") { "Anatomy" in sectionsFile.readText() }
        freshStore()
        assertEquals(listOf(made.copy(name = "Anatomy", colorIndex = 2)), loaded().sections)
    }

    @Test
    fun theIpadsCoursesAreReadAndItsUnreadableEntriesKept() {
        root.mkdirs()
        sectionsFile.writeText(ipadsFile)
        val store = loaded()
        assertEquals(listOf("Anatomi"), store.sections.map { it.name })
        store.createSection("Calculus", "function", 0)
        idleUntil("the new course") { "Calculus" in sectionsFile.readText() }
        // The courses first, then the entry this build could not read, as it was.
        assertEquals(listOf("Anatomi", "Calculus", "?"), fileNames())
        assertTrue(JSONArray(sectionsFile.readText()).getJSONObject(2).getBoolean("extra"))
    }

    @Test
    fun aCourseMadeBeforeTheFirstReadKeepsTheOnesOnDisk() {
        root.mkdirs()
        sectionsFile.writeText(ipadsFile)
        val store = NotebookStore.get(context)
        // The library's + before the disk has been read: the list in memory is still empty.
        val made = store.createSection("Calculus", "function", 0)
        idleUntil("the new course") { "Calculus" in sectionsFile.readText() }
        assertEquals(listOf("Anatomi", "Calculus", "?"), fileNames())
        idleUntil("the read") { store.loaded }
        assertEquals(listOf(anatomy, made.id), store.sections.map { it.id })
    }

    @Test
    fun aFileThatIsNotAListIsCopiedAsideBeforeItIsReplaced() {
        root.mkdirs()
        sectionsFile.writeText("{oops")
        val store = loaded()
        assertTrue(store.sections.isEmpty())
        val kept = root.listFiles()!!.filter { it.name.startsWith("sections" + FileBackup.MARKER) }
        assertEquals(1, kept.size)
        assertEquals("{oops", kept.single().readText())
        store.createSection("Calculus", "function", 0)
        idleUntil("the new list") { "Calculus" in sectionsFile.readText() }
        assertEquals(listOf("Calculus"), fileNames())
    }

    @Test
    fun aNoteMovesBetweenCoursesAndADeletedCourseLeavesItsNotes() {
        writeNote("kalp")
        writeNote("akciger")
        val store = loaded()
        val course = store.createSection("Anatomi", "heart.text.square", 5)
        store.move("kalp", course.id)
        store.move("akciger", course.id)
        idleUntil("the records") { record("kalp").optString("sectionID") == course.id && record("akciger").optString("sectionID") == course.id }
        assertEquals(course.id, store.notebook("kalp")!!.sectionId)
        store.move("akciger", null)
        idleUntil("the move out") { !record("akciger").has("sectionID") }

        store.deleteSection(course.id)
        idleUntil("the deletion") { !record("kalp").has("sectionID") && "Anatomi" !in sectionsFile.readText() }
        // The notes stay, in no course.
        assertEquals(setOf("kalp", "akciger"), store.notebooks.map { it.id }.toSet())
        assertTrue(store.notebooks.all { it.sectionId == null })
        assertTrue(store.sections.isEmpty())
        // Read again, the library says the same.
        freshStore()
        val again = loaded()
        assertTrue(again.sections.isEmpty())
        assertNull(again.notebook("kalp")!!.sectionId)
    }

    @Test
    fun aWriteThatFailsKeepsTheOldFileAndTheAppGoesOn() {
        root.mkdirs()
        sectionsFile.writeText(ipadsFile)
        // Freed newest first: "kalp", whose record cannot be written, then "akciger".
        writeNote("kalp", anatomy, modified = 2)
        writeNote("akciger", anatomy, modified = 1)
        val store = loaded()
        // A full disk, as far as the writes can tell: their files beside the old ones cannot be made.
        File(root, "sections.json.tmp").mkdirs()
        File(root, "kalp/meta.json.tmp").mkdirs()
        val crashes = ArrayList<Throwable>()
        val handler = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { _, e -> synchronized(crashes) { crashes.add(e) } }
        try {
            store.deleteSection(anatomy)
            // The second record is written after the first one failed.
            idleUntil("the second record") { !record("akciger").has("sectionID") }
            idleUntilWritten(store)
        } finally {
            Thread.setDefaultUncaughtExceptionHandler(handler)
        }
        // Nothing went uncaught (Android would have closed the app), as the iPad's try? ignores it.
        assertEquals(emptyList<Throwable>(), synchronized(crashes) { crashes.toList() })
        // The old file and the old record stay; the library in memory has the change.
        assertEquals(ipadsFile, sectionsFile.readText())
        assertEquals(anatomy, record("kalp").getString("sectionID"))
        assertTrue(store.sections.isEmpty())
        assertTrue(store.notebooks.all { it.sectionId == null })
    }

    @Test
    fun aNotebookMadeInACourseIsFiledThere() {
        val store = loaded()
        val course = store.createSection("Anatomi", "heart.text.square", 5)
        val note = store.create("Anatomi 30 Eki", section = course.id)
        assertEquals(course.id, note.sectionId)
        idleUntil("the record") { File(root, "${note.id}/meta.json").isFile && record(note.id).optString("sectionID") == course.id }
        // Renaming it keeps its course: the library owns both.
        store.rename(note.id, "Kalp")
        idleUntil("the rename") { record(note.id).optString("title") == "Kalp" }
        assertEquals(course.id, record(note.id).getString("sectionID"))
    }
}
